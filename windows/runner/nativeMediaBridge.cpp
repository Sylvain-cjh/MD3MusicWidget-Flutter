#include "nativeMediaBridge.h"
#include "nativeAudioService.h"
#include <algorithm>
#include <atomic>
#include <chrono>
#include <condition_variable>
#include <flutter/method_channel.h>
#include <flutter/standard_method_codec.h>
#include <map>
#include <mutex>
#include <thread>
#include <vector>
#include <winrt/Windows.Data.Json.h>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Foundation.h>
#include <winrt/Windows.Media.Control.h>
#include <winrt/Windows.Media.h>
#include <winrt/Windows.Storage.Streams.h>

namespace {
using namespace winrt;
using namespace Windows::Foundation;
using namespace Windows::Data::Json;
using namespace Windows::Media::Control;
using namespace Windows::Storage::Streams;
using Value = flutter::EncodableValue;
struct Payload {
  std::string info, sources, error;
  std::vector<uint8_t> artwork;
  bool command = false, accepted = false;
};
struct State {
  std::atomic<bool> stop{false};
  std::atomic<bool> active{true}, cleanup{false};
  std::mutex mutex;
  std::condition_variable wake;
  bool requested = false;
  int command = 0;
  std::atomic<uint64_t> metadata_revision{1};
  std::atomic<bool> change_posted{false};
  std::atomic<uint64_t> snapshots{0}, property_reads{0}, cover_reads{0},
      session_binds{0}, notifications{0};
  std::shared_ptr<NativeAudioService> audio =
      std::make_shared<NativeAudioService>();
  std::string selected, known_cover;
  std::unique_ptr<Payload> completed;
  HWND window = nullptr;
};
void Notify(const std::weak_ptr<State> &weak, bool metadata) {
  if (auto state = weak.lock(); state && !state->stop && state->active) {
    ++state->notifications;
    if (metadata)
      ++state->metadata_revision;
    if (!state->change_posted.exchange(true))
      PostMessageW(state->window, NativeMediaBridge::kChanged, 0, 0);
  }
}
struct Cache {
  GlobalSystemMediaTransportControlsSessionManager manager{nullptr};
  GlobalSystemMediaTransportControlsSession session{nullptr};
  event_token sessions{}, current{}, properties{}, playback{}, timeline{};
  GlobalSystemMediaTransportControlsSessionMediaProperties props{nullptr};
  uint64_t revision = 0, track = 0;
  std::string identity, cover;
  std::vector<uint8_t> bytes;
  double last_position = 0;
  int64_t cover_retry = 0;
  void DetachSession() {
    if (session) {
      try {
        session.MediaPropertiesChanged(properties);
      } catch (...) {
      }
      try {
        session.PlaybackInfoChanged(playback);
      } catch (...) {
      }
      try {
        session.TimelinePropertiesChanged(timeline);
      } catch (...) {
      }
    }
    session = nullptr;
    props = nullptr;
    revision = 0;
    cover.clear();
    bytes.clear();
    identity.clear();
    last_position = 0;
    cover_retry = 0;
  }
  void Reset() {
    DetachSession();
    if (manager) {
      try {
        manager.SessionsChanged(sessions);
      } catch (...) {
      }
      try {
        manager.CurrentSessionChanged(current);
      } catch (...) {
      }
    }
    manager = nullptr;
  }
  ~Cache() { Reset(); }
  void
  ObserveManager(const GlobalSystemMediaTransportControlsSessionManager &value,
                 const std::shared_ptr<State> &state) {
    if (manager == value)
      return;
    Reset();
    manager = value;
    std::weak_ptr<State> weak = state;
    sessions = manager.SessionsChanged(
        [weak](auto const &, auto const &) { Notify(weak, true); });
    current = manager.CurrentSessionChanged(
        [weak](auto const &, auto const &) { Notify(weak, true); });
  }
  void Observe(const GlobalSystemMediaTransportControlsSession &value,
               const std::shared_ptr<State> &state) {
    if (session == value)
      return;
    DetachSession();
    session = value;
    if (!session)
      return;
    ++state->session_binds;
    std::weak_ptr<State> weak = state;
    properties = session.MediaPropertiesChanged(
        [weak](auto const &, auto const &) { Notify(weak, true); });
    playback = session.PlaybackInfoChanged(
        [weak](auto const &, auto const &) { Notify(weak, false); });
    timeline = session.TimelinePropertiesChanged(
        [weak](auto const &, auto const &) { Notify(weak, false); });
  }
};
GlobalSystemMediaTransportControlsSession
Choose(const GlobalSystemMediaTransportControlsSessionManager &manager,
       const std::string &source) {
  if (source.empty())
    return manager.GetCurrentSession();
  GlobalSystemMediaTransportControlsSession chosen{nullptr};
  for (const auto &s : manager.GetSessions())
    if (_wcsicmp(s.SourceAppUserModelId().c_str(),
                 to_hstring(source).c_str()) == 0) {
      if (!chosen)
        chosen = s;
      try {
        if (s.GetPlaybackInfo().PlaybackStatus() ==
            GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing)
          return s;
      } catch (...) {
      }
    }
  return chosen;
}
template <typename Operation>
auto Read(const Operation &operation, const std::shared_ptr<State> &state) {
  const auto deadline =
      std::chrono::steady_clock::now() + std::chrono::seconds(2);
  while (operation.Status() == AsyncStatus::Started) {
    if (state->stop || std::chrono::steady_clock::now() >= deadline) {
      operation.Cancel();
      throw hresult_error(HRESULT_FROM_WIN32(ERROR_CANCELLED));
    }
    std::this_thread::sleep_for(std::chrono::milliseconds(5));
  }
  return operation.GetResults();
}
std::string CoverVersion(const std::vector<uint8_t> &bytes) {
  if (bytes.empty())
    return {};
  uint64_t hash = 14695981039346656037ull;
  for (auto byte : bytes) {
    hash ^= byte;
    hash *= 1099511628211ull;
  }
  return "native-" + std::to_string(hash);
}
Payload
Snapshot(const std::shared_ptr<State> &state,
         const GlobalSystemMediaTransportControlsSessionManager &manager,
         const std::string &selected, const std::string &known_cover,
         Cache &cache) {
  ++state->snapshots;
  Payload result;
  JsonObject sources;
  JsonArray entries;
  struct IdLess {
    bool operator()(const std::wstring &a, const std::wstring &b) const {
      return _wcsicmp(a.c_str(), b.c_str()) < 0;
    }
  };
  std::map<std::wstring, bool, IdLess> unique;
  GlobalSystemMediaTransportControlsSession chosen{nullptr};
  for (const auto &session : manager.GetSessions()) {
    const auto id = session.SourceAppUserModelId();
    bool playing = false;
    try {
      playing =
          session.GetPlaybackInfo().PlaybackStatus() ==
          GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
    } catch (...) {
    }
    auto key = std::wstring(id.c_str());
    if (!key.empty())
      unique[key] = unique[key] || playing;
    if (!selected.empty() &&
        _wcsicmp(id.c_str(), to_hstring(selected).c_str()) == 0 &&
        (!chosen || playing))
      chosen = session;
  }
  for (const auto &[id, playing] : unique) {
    JsonObject entry;
    entry.SetNamedValue(L"sourceAppId", JsonValue::CreateStringValue(id));
    entry.SetNamedValue(L"isPlaying", JsonValue::CreateBooleanValue(playing));
    entries.Append(entry);
  }
  if (selected.empty())
    chosen = manager.GetCurrentSession();
  cache.Observe(chosen, state);
  
  
  
  sources.SetNamedValue(L"selectedSourceAppId",
                        JsonValue::CreateStringValue(to_hstring(selected)));
  sources.SetNamedValue(L"sources", entries);
  result.sources = to_string(sources.Stringify());
  JsonObject info;
  const auto now = std::chrono::duration_cast<std::chrono::milliseconds>(
                       std::chrono::system_clock::now().time_since_epoch())
                       .count();
  info.SetNamedValue(L"processId", JsonValue::CreateNumberValue(0));
  info.SetNamedValue(L"fetcherUpdatedAtMs",
                     JsonValue::CreateNumberValue(static_cast<double>(now)));
  info.SetNamedValue(L"capabilities", JsonValue::CreateNumberValue(7 | 128));
  info.SetNamedValue(L"sourceAppId", JsonValue::CreateStringValue(L""));
  info.SetNamedValue(L"title", JsonValue::CreateStringValue(L"暂无音乐播放"));
  info.SetNamedValue(L"artist",
                     JsonValue::CreateStringValue(L"请打开播放软件"));
  info.SetNamedValue(L"isPlaying", JsonValue::CreateBooleanValue(false));
  info.SetNamedValue(L"coverVersion", JsonValue::CreateStringValue(L""));
  info.SetNamedValue(L"isShuffleActive", JsonValue::CreateNullValue());
  info.SetNamedValue(L"autoRepeatMode", JsonValue::CreateStringValue(L""));
  info.SetNamedValue(L"trackVersion",
                     JsonValue::CreateStringValue(L"native-empty"));
  if (chosen) {
    const auto revision = state->metadata_revision.load();
    const bool changed = !cache.props || cache.revision != revision;
    if (changed) {
      ++state->property_reads;
      cache.props = Read(chosen.TryGetMediaPropertiesAsync(), state);
      cache.revision = revision;
      cache.cover_retry = 0;
    }
    const auto props = cache.props;
    const auto playback = chosen.GetPlaybackInfo();
    const auto timeline = chosen.GetTimelineProperties();
    const bool playing =
        playback.PlaybackStatus() ==
        GlobalSystemMediaTransportControlsSessionPlaybackStatus::Playing;
    const auto duration =
        std::max(0.0, std::chrono::duration<double, std::milli>(
                          timeline.EndTime() - timeline.StartTime())
                          .count());
    auto position =
        std::max(0.0, std::chrono::duration<double, std::milli>(
                          timeline.Position() - timeline.StartTime())
                          .count());
    const auto age = std::chrono::duration<double, std::milli>(
                         winrt::clock::now() - timeline.LastUpdatedTime())
                         .count();
    if (playing && age >= 0 && age < 86400000)
      position += age;
    if (duration > 0)
      position = std::min(position, duration);
    const auto source = chosen.SourceAppUserModelId();
    const auto identity =
        to_string(source + L"|" + props.Title() + L"|" + props.Artist());
    if (identity != cache.identity ||
        (cache.last_position > 5000 && position + 1500 < cache.last_position)) {
      ++cache.track;
      cache.cover.clear();
      cache.bytes.clear();
      cache.cover_retry = now;
      cache.identity = identity;
    }
    cache.last_position = position;
    
    
    if (changed || cache.cover_retry > 0 && now >= cache.cover_retry)
      try {
        if (const auto thumbnail = props.Thumbnail()) {
          ++state->cover_reads;
          const auto stream = Read(thumbnail.OpenReadAsync(), state);
          if (stream.Size() > 20 * 1024 * 1024)
            throw hresult_error(E_BOUNDS);
          DataReader reader(stream.GetInputStreamAt(0));
          const auto count = Read(
              reader.LoadAsync(static_cast<uint32_t>(stream.Size())), state);
          if (count != stream.Size())
            throw hresult_error(E_FAIL);
          std::vector<uint8_t> bytes(count);
          reader.ReadBytes(bytes);
          cache.cover = CoverVersion(bytes);
          cache.bytes = std::move(bytes);
          cache.cover_retry = cache.bytes.empty() ? now + 1500 : 0;
        } else {
          cache.cover.clear();
          cache.bytes.clear();
          cache.cover_retry = now + 1500;
        }
      } catch (...) {
        cache.cover_retry = now + 1500;
      }
    const auto &cover = cache.cover;
    if (cover != known_cover)
      result.artwork = cache.bytes;
    state->audio->Target(std::wstring(source.c_str()), playing,
                         !selected.empty());
    const auto controls = playback.Controls();
    
    
    try {
      if (const auto shuffle = playback.IsShuffleActive())
        info.SetNamedValue(L"isShuffleActive",
                           JsonValue::CreateBooleanValue(shuffle.Value()));
    } catch (...) {
    }
    try {
      if (const auto repeat = playback.AutoRepeatMode()) {
        const wchar_t *mode = L"";
        switch (repeat.Value()) {
        case Windows::Media::MediaPlaybackAutoRepeatMode::None:
          mode = L"none";
          break;
        case Windows::Media::MediaPlaybackAutoRepeatMode::Track:
          mode = L"track";
          break;
        case Windows::Media::MediaPlaybackAutoRepeatMode::List:
          mode = L"list";
          break;
        }
        info.SetNamedValue(L"autoRepeatMode",
                           JsonValue::CreateStringValue(mode));
      }
    } catch (...) {
    }
    int capabilities = 7 | 128;
    if (controls.IsPlayPauseToggleEnabled() || controls.IsPlayEnabled() ||
        controls.IsPauseEnabled())
      capabilities |= 8;
    if (controls.IsPreviousEnabled())
      capabilities |= 16;
    if (controls.IsNextEnabled())
      capabilities |= 32;
    info.SetNamedValue(L"capabilities",
                       JsonValue::CreateNumberValue(capabilities));
    info.SetNamedValue(L"sourceAppId", JsonValue::CreateStringValue(source));
    info.SetNamedValue(L"title", JsonValue::CreateStringValue(props.Title()));
    info.SetNamedValue(L"artist", JsonValue::CreateStringValue(props.Artist()));
    info.SetNamedValue(L"isPlaying", JsonValue::CreateBooleanValue(playing));
    info.SetNamedValue(L"coverVersion",
                       JsonValue::CreateStringValue(to_hstring(cover)));
    info.SetNamedValue(L"trackVersion",
                       JsonValue::CreateStringValue(to_hstring(
                           identity + "|" + std::to_string(cache.track))));
    info.SetNamedValue(L"durationMs", JsonValue::CreateNumberValue(duration));
    info.SetNamedValue(L"positionMs", JsonValue::CreateNumberValue(position));
    info.SetNamedValue(L"timelineUpdatedAtMs",
                       JsonValue::CreateNumberValue(static_cast<double>(now)));
  } else
    state->audio->Target(L"", false, !selected.empty());
  result.info = to_string(info.Stringify());
  return result;
}
void Worker(std::shared_ptr<State> state) {
  bool initialized = false;
  GlobalSystemMediaTransportControlsSessionManager manager{nullptr};
  Cache cache;
  while (!state->stop) {
    std::string selected, known;
    int command = 0;
    {
      std::unique_lock lock(state->mutex);
      state->wake.wait(lock, [&] {
        return state->stop || state->requested || state->cleanup;
      });
      if (state->stop)
        break;
      if (state->cleanup.exchange(false)) {
        lock.unlock();
        cache.Reset();
        manager = nullptr;
        continue;
      }
      state->requested = false;
      selected = state->selected;
      known = state->known_cover;
      command = state->command;
      state->command = 0;
    }
    auto payload = std::make_unique<Payload>();
    try {
      if (!initialized) {
        init_apartment(apartment_type::multi_threaded);
        initialized = true;
      }
      if (!manager)
        manager = Read(
            GlobalSystemMediaTransportControlsSessionManager::RequestAsync(),
            state);
      cache.ObserveManager(manager, state);
      if (command) {
        payload->command = true;
        if (auto session = Choose(manager, selected)) {
          const auto controls = session.GetPlaybackInfo().Controls();
          if (command == 1 && controls.IsPreviousEnabled())
            payload->accepted = Read(session.TrySkipPreviousAsync(), state);
          if (command == 2) {
            if (controls.IsPlayPauseToggleEnabled())
              payload->accepted =
                  Read(session.TryTogglePlayPauseAsync(), state);
            else if (
                session.GetPlaybackInfo().PlaybackStatus() ==
                    GlobalSystemMediaTransportControlsSessionPlaybackStatus::
                        Playing &&
                controls.IsPauseEnabled())
              payload->accepted = Read(session.TryPauseAsync(), state);
            else if (controls.IsPlayEnabled())
              payload->accepted = Read(session.TryPlayAsync(), state);
          }
          if (command == 3 && controls.IsNextEnabled())
            payload->accepted = Read(session.TrySkipNextAsync(), state);
          if (command == 4)
            payload->accepted =
                session.GetPlaybackInfo().PlaybackStatus() ==
                    GlobalSystemMediaTransportControlsSessionPlaybackStatus::
                        Playing ||
                controls.IsPlayEnabled() && Read(session.TryPlayAsync(), state);
          if (command == 5)
            payload->accepted =
                session.GetPlaybackInfo().PlaybackStatus() !=
                    GlobalSystemMediaTransportControlsSessionPlaybackStatus::
                        Playing ||
                controls.IsPauseEnabled() &&
                    Read(session.TryPauseAsync(), state);
        }
        Notify(state, true);
      } else
        *payload = Snapshot(state, manager, selected, known, cache);
    } catch (const hresult_error &error) {
      payload->error =
          "native_media_hresult:" + std::to_string(error.code().value);
      cache.Reset();
      manager = nullptr;
    } catch (...) {
      payload->error = "native_media_failed";
      cache.Reset();
      manager = nullptr;
    }
    if (state->stop)
      break;
    {
      std::lock_guard lock(state->mutex);
      state->completed = std::move(payload);
    }
    if (!state->stop)
      PostMessageW(state->window, NativeMediaBridge::kReady, 0, 0);
  }
  cache.Reset();
  manager = nullptr;
  if (initialized)
    uninit_apartment();
}
} 
struct NativeMediaBridge::Impl {
  std::shared_ptr<State> state = std::make_shared<State>();
  std::unique_ptr<flutter::MethodChannel<Value>> channel;
  std::unique_ptr<flutter::MethodResult<Value>> pending;
  bool started = false;
};
NativeMediaBridge::NativeMediaBridge(flutter::BinaryMessenger *messenger,
                                     HWND window)
    : impl_(std::make_unique<Impl>()) {
  impl_->state->window = window;
  impl_->channel = std::make_unique<flutter::MethodChannel<Value>>(
      messenger, "md3_music_widget/native_media_preview",
      &flutter::StandardMethodCodec::GetInstance());
  impl_->channel->SetMethodCallHandler([this](const auto &call, auto result) {
    const auto *args =
        call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments())
                         : nullptr;
    if (call.method_name() == "spectrumDemand") {
      bool enabled = false;
      if (args) {
        auto it = args->find(Value("enabled"));
        if (it != args->end())
          if (auto v = std::get_if<bool>(&it->second))
            enabled = *v;
      }
      impl_->state->audio->Demand(enabled);
      result->Success();
      return;
    }
    if (call.method_name() == "diagnostics") {
      auto &s = *impl_->state;
      result->Success(Value(flutter::EncodableMap{
          {Value("snapshots"), Value(static_cast<int64_t>(s.snapshots.load()))},
          {Value("propertyReads"),
           Value(static_cast<int64_t>(s.property_reads.load()))},
          {Value("coverReads"),
           Value(static_cast<int64_t>(s.cover_reads.load()))},
          {Value("sessionBinds"),
           Value(static_cast<int64_t>(s.session_binds.load()))},
          {Value("notifications"),
           Value(static_cast<int64_t>(s.notifications.load()))}}));
      return;
    }
    if (call.method_name() == "spectrum") {
      auto reading = impl_->state->audio->Reading();
      result->Success(Value(flutter::EncodableMap{
          {Value("packet"), Value(reading.packet)},
          {Value("status"), Value(reading.status)},
          {Value("frames"), Value(static_cast<int64_t>(reading.frames))},
          {Value("processId"),
           Value(static_cast<int64_t>(reading.process_id))},
          {Value("lookupOpenedProcesses"),
           Value(static_cast<int64_t>(reading.lookup_open_attempts))}}));
      return;
    }
    if (call.method_name() == "audioRetry") {
      impl_->state->audio->Retry();
      result->Success();
      return;
    }
    if (call.method_name() == "stop") {
      impl_->state->active = false;
      impl_->state->audio->Demand(false);
      impl_->state->cleanup = true;
      impl_->state->wake.notify_one();
      result->Success();
      return;
    }
    if (call.method_name() != "snapshot" && call.method_name() != "command") {
      result->NotImplemented();
      return;
    }
    if (impl_->pending) {
      result->Error("native_media_busy", "A request is already in flight");
      return;
    }
    if (!impl_->state->active.exchange(true))
      ++impl_->state->metadata_revision;
    int command = 0;
    if (call.method_name() == "command" && args) {
      auto it = args->find(Value("command"));
      if (it != args->end())
        if (auto v = std::get_if<int32_t>(&it->second))
          command = *v;
    }
    if (call.method_name() == "command" && (command < 1 || command > 5)) {
      result->Error("invalid_command", "Unknown media command");
      return;
    }
    std::string selected, known;
    if (args) {
      for (const auto &pair : *args) {
        const auto *key = std::get_if<std::string>(&pair.first);
        const auto *value = std::get_if<std::string>(&pair.second);
        if (key && value && *key == "source")
          selected = *value;
        if (key && value && *key == "knownCover")
          known = *value;
      }
    }
    if (selected.size() > 2048) {
      result->Error("invalid_source", "Source ID is too long");
      return;
    }
    impl_->pending = std::move(result);
    {
      std::lock_guard lock(impl_->state->mutex);
      impl_->state->command = command;
      impl_->state->selected = selected;
      impl_->state->known_cover = known;
      impl_->state->requested = true;
    }
    if (!impl_->started) {
      try {
        std::thread(Worker, impl_->state).detach();
        impl_->started = true;
      } catch (...) {
        impl_->pending->Error("native_media_worker", "Worker creation failed");
        impl_->pending.reset();
        return;
      }
    }
    impl_->state->wake.notify_one();
  });
}
NativeMediaBridge::~NativeMediaBridge() {
  impl_->channel->SetMethodCallHandler(nullptr);
  impl_->state->stop = true;
  impl_->state->wake.notify_one();
  impl_->state->audio->Demand(false);
  if (impl_->pending)
    impl_->pending->Error("native_media_closed", "Bridge closed");
  
  
}
void NativeMediaBridge::Drain() {
  std::unique_ptr<Payload> payload;
  {
    std::lock_guard lock(impl_->state->mutex);
    payload = std::move(impl_->state->completed);
  }
  if (!payload || !impl_->pending)
    return;
  auto result = std::move(impl_->pending);
  if (!payload->error.empty()) {
    result->Error("native_media_failed", payload->error);
    return;
  }
  if (payload->command) {
    result->Success(Value(payload->accepted));
    return;
  }
  result->Success(Value(
      flutter::EncodableMap{{Value("info"), Value(payload->info)},
                            {Value("sources"), Value(payload->sources)},
                            {Value("artwork"), Value(payload->artwork)}}));
}
void NativeMediaBridge::Changed() {
  impl_->state->change_posted = false;
  if (impl_->state->active)
    impl_->channel->InvokeMethod("changed", nullptr);
}

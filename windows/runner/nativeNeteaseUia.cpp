#include "nativeNeteaseUia.h"
#include "neteaseUiaScan.h"
#include <condition_variable>
#include <mutex>
#include <thread>

using namespace netease_uia;
namespace {
struct Observation {
  NeteaseUiaSample sample;
  HWND window;
  DWORD pid;
  Clock::time_point at;
};

std::optional<Observation> Scan(IUIAutomation *automation,
                                const std::wstring &selected) {
  const auto processes = NetEaseProcesses();
  if (!processes || processes->empty()) return {};
  WindowSearch search{*processes, {}};
  if (!EnumWindows(CollectWindows, reinterpret_cast<LPARAM>(&search))) return {};
  std::optional<Observation> found;
  size_t attempted = 0;
  for (const auto &window : search.windows) {
    if (!HasTrackCandidate(window.title) ||
        !StillNetEase(window.hwnd, window.pid, selected)) continue;
    if (++attempted > 3) return {};  
    const auto scan = ReadWindow(automation, window, selected);
    if (FAILED(scan.result) || scan.unstable || scan.times.empty()) continue;
    if (scan.times.size() != 1 || found) return {};
    const auto [position, duration] = *scan.times.begin();
    const auto separator = window.title.find(L" - ");
    const auto title = TrimText(window.title.substr(0, separator));
    const auto artist = TrimText(window.title.substr(separator + 3));
    if (title.empty() || artist.empty()) continue;
    const auto now = std::chrono::system_clock::now().time_since_epoch();
    found = Observation{
        {title, artist, position, duration,
         std::chrono::duration_cast<std::chrono::milliseconds>(now).count(), {}},
        window.hwnd, window.pid, Clock::now()};
  }
  return found;
}
} 

struct NativeNeteaseUia::State {
  std::mutex mutex;
  std::condition_variable wake;
  bool stop = false, started = false;
  unsigned long long generation = 0;
  std::wstring selected;
  std::optional<NeteaseUiaSample> latest;
  Clock::time_point published{};
};

NativeNeteaseUia::NativeNeteaseUia() : state_(std::make_shared<State>()) {}

NativeNeteaseUia::~NativeNeteaseUia() {
  std::lock_guard lock(state_->mutex);
  state_->stop = true;
  state_->wake.notify_one();
}

std::optional<NeteaseUiaSample> NativeNeteaseUia::Read(
    const std::wstring &selected) {
  std::lock_guard lock(state_->mutex);
  if (state_->selected != selected) {
    state_->selected = selected;
    state_->latest.reset();
    ++state_->generation;
    state_->wake.notify_one();
  }
  if (selected.empty()) return {};
  if (!state_->started) {
    try {
      std::thread(Work, state_).detach();
      state_->started = true;
    } catch (...) {
      return {};
    }
  }
  return Clock::now() - state_->published <= std::chrono::seconds(3)
             ? state_->latest : std::nullopt;
}

void NativeNeteaseUia::Work(std::shared_ptr<State> state) {
  const HRESULT initialized = CoInitializeEx(nullptr, COINIT_MULTITHREADED);
  if (FAILED(initialized)) return;
  {
    ComPtr<IUIAutomation> automation;
    ComPtr<IUIAutomation2> timeouts;
    if (SUCCEEDED(CoCreateInstance(__uuidof(CUIAutomation8), nullptr,
                                   CLSCTX_INPROC_SERVER,
                                   IID_PPV_ARGS(&automation))) &&
        SUCCEEDED(automation.As(&timeouts)) &&
        SUCCEEDED(timeouts->put_ConnectionTimeout(500)) &&
        SUCCEEDED(timeouts->put_TransactionTimeout(500))) {
      std::optional<Observation> previous;
      Clock::time_point lastAdvance{};
      unsigned long long lastGeneration = 0;
      std::unique_lock lock(state->mutex);
      while (!state->stop) {
        state->wake.wait(lock, [&] { return state->stop || !state->selected.empty(); });
        if (state->stop) break;
        const auto generation = state->generation;
        const auto source = state->selected;
        lock.unlock();
        std::optional<Observation> current;
        try { current = Scan(automation.Get(), source); } catch (...) {}
        lock.lock();
        if (state->stop) break;
        if (state->generation != generation) continue;
        if (lastGeneration != generation) {
          previous.reset();
          lastAdvance = {};
          lastGeneration = generation;
        }
        state->latest.reset();
        if (current && previous &&
            current->pid == previous->pid && current->window == previous->window &&
            current->sample.title == previous->sample.title &&
            current->sample.artist == previous->sample.artist &&
            current->sample.durationSeconds == previous->sample.durationSeconds) {
          const int change = current->sample.positionSeconds - previous->sample.positionSeconds;
          if (change > 0 && change <= 3) {
            lastAdvance = current->at;
            current->sample.playing = true;
          } else if (change == 0 && lastAdvance != Clock::time_point{} &&
                     current->at - lastAdvance < std::chrono::seconds(2)) {
            current->sample.playing = true;
          } else if (change != 0) {
            lastAdvance = {};
          }
          state->latest = current->sample;
          state->published = current->at;
        } else {
          lastAdvance = {};
        }
        previous = std::move(current);
        state->wake.wait_for(
            lock, previous ? std::chrono::milliseconds(900)
                           : std::chrono::milliseconds(2500),
            [&] { return state->stop || state->generation != generation; });
      }
    }
  }
  CoUninitialize();
}

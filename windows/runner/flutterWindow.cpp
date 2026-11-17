#include "flutterWindow.h"
#include "systemFonts.h"
#include "utils.h"

#include <optional>
#include <algorithm>
#include <cmath>
#include <cstdint>
#include <shellapi.h>
#include <mmdeviceapi.h>
#include <endpointvolume.h>
#include <wrl/client.h>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
constexpr UINT kFontsReady = WM_APP + 83;
constexpr UINT_PTR kAudioOutputsTimer = 0x4D334F55;

std::wstring AudioEndpointFromUtf8(const std::string &id) {
  const auto size = static_cast<int>(id.size());
  const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                        id.data(), size, nullptr, 0);
  if (length <= 0) return {};
  std::wstring result(length, 0);
  if (!MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, id.data(), size,
                           result.data(), length) ||
      result.find(L'\0') != std::wstring::npos) return {};
  return result;
}

flutter::EncodableValue EncodeAudioOutputs(AudioOutputSnapshot snapshot) {
  using Value = flutter::EncodableValue;
  flutter::EncodableList endpoints;
  for (const auto &endpoint : snapshot.endpoints) {
    endpoints.emplace_back(flutter::EncodableMap{
        {Value("id"), Value(Utf8FromUtf16(endpoint.id.c_str()))},
        {Value("name"), Value(Utf8FromUtf16(endpoint.name.c_str()))},
        {Value("bluetoothGroup"), Value(Utf8FromUtf16(endpoint.bluetooth_group.c_str()))},
    });
  }
  return Value(flutter::EncodableMap{
      {Value("available"), Value(snapshot.available)},
      {Value("defaultId"), Value(Utf8FromUtf16(snapshot.multimedia.c_str()))},
      {Value("consoleId"), Value(Utf8FromUtf16(snapshot.console.c_str()))},
      {Value("outputs"), Value(std::move(endpoints))},
  });
}



std::optional<flutter::EncodableValue> AccessSystemVolume(
    std::optional<double> value, const std::wstring* expected_id = nullptr) {
  using Microsoft::WRL::ComPtr;
  ComPtr<IMMDeviceEnumerator> devices;
  ComPtr<IMMDevice> device;
  ComPtr<IAudioEndpointVolume> volume;
  float level = 0;
  BOOL muted = FALSE;
  if (FAILED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&devices))) ||
      FAILED(devices->GetDefaultAudioEndpoint(eRender, eMultimedia, &device))) {
    return std::nullopt;
  }
  if (expected_id) {
    LPWSTR actual_id = nullptr;
    const HRESULT status = device->GetId(&actual_id);
    const bool matches = SUCCEEDED(status) && actual_id &&
                         *expected_id == actual_id;
    CoTaskMemFree(actual_id);
    if (!matches) return std::nullopt;
  }
  if (FAILED(device->Activate(__uuidof(IAudioEndpointVolume), CLSCTX_ALL,
                              nullptr, &volume)) ||
      FAILED(volume->GetMasterVolumeLevelScalar(&level)) ||
      FAILED(volume->GetMute(&muted))) {
    return std::nullopt;
  }
  if (value) {
    
    
    const double requested = expected_id ? *value : level + *value;
    const auto next = static_cast<float>(std::clamp(requested, 0.0, 1.0));
    if ((next != level && FAILED(volume->SetMasterVolumeLevelScalar(next, nullptr))) ||
        (*value > 0 && muted && FAILED(volume->SetMute(FALSE, nullptr))) ||
        FAILED(volume->GetMasterVolumeLevelScalar(&level)) ||
        FAILED(volume->GetMute(&muted))) {
      return std::nullopt;
    }
  }
  return flutter::EncodableValue(flutter::EncodableMap{
      {flutter::EncodableValue("level"), flutter::EncodableValue(double{level})},
      {flutter::EncodableValue("muted"), flutter::EncodableValue(muted != FALSE)},
  });
}
}  
static_assert(SystemTray::kCallback != kFontsReady &&
              SystemTray::kCallback != NativeMediaBridge::kReady &&
              SystemTray::kCallback != NativeMediaBridge::kChanged);
static_assert(AudioOutputDevices::kChanged != SystemTray::kCallback &&
              AudioOutputDevices::kChanged != NativeMediaBridge::kReady &&
              AudioOutputDevices::kChanged != NativeMediaBridge::kChanged &&
              AudioOutputDevices::kChanged != kFontsReady);

flutter::EncodableValue FlutterWindow::ClientViewport() {
  const auto rect = GetClientArea();
  const auto inset = ClientSurfaceInset();
  return flutter::EncodableValue(flutter::EncodableList{
      flutter::EncodableValue(static_cast<int32_t>(rect.right)),
      flutter::EncodableValue(static_cast<int32_t>(rect.bottom)),
      flutter::EncodableValue(static_cast<int32_t>(inset.x)),
      flutter::EncodableValue(static_cast<int32_t>(inset.y)),
  });
}

void FlutterWindow::OnClientSurfaceChanged() {
  if (!watch_client_viewport_ || !client_viewport_channel_) return;
  const auto rect = GetClientArea();
  const auto inset = ClientSurfaceInset();
  if (rect.right <= 0 || rect.bottom <= 0 ||
      (rect.right == published_client_width_ &&
       rect.bottom == published_client_height_ &&
       inset.x == published_client_inset_.x &&
       inset.y == published_client_inset_.y)) return;
  published_client_width_ = rect.right;
  published_client_height_ = rect.bottom;
  published_client_inset_ = inset;
  client_viewport_channel_->InvokeMethod(
      "changed", std::make_unique<flutter::EncodableValue>(ClientViewport()));
}

void FlutterWindow::RefreshFonts() {
  font_catalog_started_ = true;
  const HWND handle = GetHandle();
  if (!font_catalog_.Refresh([handle] { PostMessageW(handle, kFontsReady, 0, 0); })) {
    font_refresh_pending_ = true;
  }
}

FlutterWindow::FlutterWindow(const flutter::DartProject& project)
    : project_(project) {}

FlutterWindow::~FlutterWindow() {}

bool FlutterWindow::OnCreate() {
  if (!Win32Window::OnCreate()) {
    return false;
  }

  RECT frame = GetClientArea();

  
  
  flutter_controller_ = std::make_unique<flutter::FlutterViewController>(
      frame.right - frame.left, frame.bottom - frame.top, project_);
  
  if (!flutter_controller_->engine() || !flutter_controller_->view()) {
    return false;
  }
  performance_monitor_ = std::make_unique<SystemPerformanceMonitor>();
  RegisterPlugins(flutter_controller_->engine());
  system_tray_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "md3_music_widget/system_tray",
          &flutter::StandardMethodCodec::GetInstance());
  system_tray_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "start") {
          result->Success(flutter::EncodableValue(system_tray_.Start(GetHandle())));
        } else if (call.method_name() == "stop") {
          system_tray_.Stop();
          result->Success();
        } else if (call.method_name() == "menu") {
          const char* action = system_tray_.ShowMenuAtCursor();
          result->Success(action ? flutter::EncodableValue(action)
                                 : flutter::EncodableValue());
        } else {
          result->NotImplemented();
        }
      });
  system_volume_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "md3_music_widget/system_volume",
          &flutter::StandardMethodCodec::GetInstance());
  system_volume_channel_->SetMethodCallHandler(
      [](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "wheelUnitsPerNotch") {
          UINT lines = 3;
          SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
          
          
          const double units = lines > 0 && lines < 1000
              ? static_cast<int>(static_cast<float>(lines) * 100.0 / 3.0)
              : 100.0;
          result->Success(flutter::EncodableValue(units));
          return;
        }
        if (call.method_name() != "adjust") {
          result->NotImplemented();
          return;
        }
        const auto* delta = call.arguments() ?
            std::get_if<double>(call.arguments()) : nullptr;
        if (!delta || !std::isfinite(*delta) || std::abs(*delta) > 1.0) {
          result->Error("invalid_delta", "Expected a finite volume delta in [-1, 1]");
          return;
        }
        const auto volume = AccessSystemVolume(*delta);
        result->Success(volume ? *volume : flutter::EncodableValue());
      });
  audio_outputs_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "md3_music_widget/audio_outputs",
          &flutter::StandardMethodCodec::GetInstance());
  audio_outputs_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        using Value = flutter::EncodableValue;
        try {
          const auto &method = call.method_name();
          if (method == "openWindowsSettings") {
            const auto opened = reinterpret_cast<INT_PTR>(ShellExecuteW(
                GetHandle(), L"open", L"ms-settings:sound", nullptr, nullptr, SW_SHOWNORMAL));
            result->Success(Value(opened > 32));
            return;
          }
          if (method == "readVolume" || method == "setVolume") {
            const auto *id = call.arguments()
                ? std::get_if<std::string>(call.arguments()) : nullptr;
            std::optional<double> level;
            if (method == "setVolume") {
              const auto* args = call.arguments()
                  ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
              if (args) {
                const auto id_it = args->find(Value("id"));
                const auto level_it = args->find(Value("level"));
                id = id_it == args->end() ? nullptr :
                     std::get_if<std::string>(&id_it->second);
                const auto* scalar = level_it == args->end() ? nullptr :
                     std::get_if<double>(&level_it->second);
                if (scalar && std::isfinite(*scalar) && *scalar >= 0 && *scalar <= 1) {
                  level = *scalar;
                }
              }
            }
            if (!id || id->empty() || id->size() > 512 ||
                (method == "setVolume" && !level)) {
              result->Error("invalid_volume_request", "Expected endpoint ID and valid scalar");
              return;
            }
            const auto endpoint = AudioEndpointFromUtf8(*id);
            const auto volume = endpoint.empty() ? std::nullopt :
                                AccessSystemVolume(level, &endpoint);
            result->Success(volume ? *volume : Value());
            return;
          }
          if (method != "watch" && method != "select") {
            result->NotImplemented();
            return;
          }
          if (!audio_outputs_) audio_outputs_ = std::make_unique<AudioOutputDevices>();
          if (method == "watch") {
            const bool watching = audio_outputs_->Watch(GetHandle());
            result->Success(Value(flutter::EncodableMap{
                {Value("watching"), Value(watching)},
                {Value("snapshot"), EncodeAudioOutputs(audio_outputs_->Snapshot())},
            }));
            return;
          }
          const auto* id = call.arguments() ? std::get_if<std::string>(call.arguments()) : nullptr;
          if (!id || id->empty() || id->size() > 512) {
            result->Error("invalid_device", "Expected a render endpoint ID");
            return;
          }
          const bool selected = audio_outputs_->Select(AudioEndpointFromUtf8(*id));
          result->Success(Value(flutter::EncodableMap{
              {Value("selected"), Value(selected)},
              {Value("snapshot"), EncodeAudioOutputs(audio_outputs_->Snapshot())},
          }));
        } catch (...) {
          result->Error("audio_outputs_unavailable", "Windows audio outputs are unavailable");
        }
      });
  app_info_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "md3_music_widget/app_info",
          &flutter::StandardMethodCodec::GetInstance());
  app_info_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() == "version") {
          result->Success(flutter::EncodableValue(FLUTTER_VERSION));
          return;
        }
        
        
        const wchar_t* url = nullptr;
        if (call.method_name() == "openProject") {
          url = L"https://github.com/Sylvain-cjh/MD3MusicWidget-Flutter";
        } else if (call.method_name() == "openReleases") {
          url = L"https://github.com/Sylvain-cjh/MD3MusicWidget-Flutter/releases";
        }
        if (!url) {
          result->NotImplemented();
          return;
        }
        const auto launched = reinterpret_cast<INT_PTR>(
            ShellExecuteW(GetHandle(), L"open", url, nullptr, nullptr, SW_SHOWNORMAL));
        result->Success(flutter::EncodableValue(launched > 32));
      });
  client_viewport_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "md3_music_widget/client_viewport",
          &flutter::StandardMethodCodec::GetInstance());
  client_viewport_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "watch") { result->NotImplemented(); return; }
        const auto rect = GetClientArea();
        published_client_width_ = rect.right;
        published_client_height_ = rect.bottom;
        published_client_inset_ = ClientSurfaceInset();
        watch_client_viewport_ = true;
        SetRetainClientSurface(true);
        result->Success(ClientViewport());
      });
  native_media_bridge_ = std::make_unique<NativeMediaBridge>(flutter_controller_->engine()->messenger(), GetHandle());
  system_fonts_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(), "md3_music_widget/system_fonts",
          &flutter::StandardMethodCodec::GetInstance());
  system_fonts_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
         std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>> result) {
        if (call.method_name() != "families") { result->NotImplemented(); return; }
        bool ready = false;
        const auto families = font_catalog_.Snapshot(&ready);
        if (!ready) {
          if (!font_catalog_started_) RefreshFonts();
          result->Error("fonts_loading", "System families are loading in the background");
          return;
        }
        flutter::EncodableList names;
        for (const auto& family : families) names.emplace_back(family);
        result->Success(flutter::EncodableValue(names));
      });
  
  
  
  system_performance_channel_ =
      std::make_unique<flutter::MethodChannel<flutter::EncodableValue>>(
          flutter_controller_->engine()->messenger(),
          "md3_music_widget/system_performance",
          &flutter::StandardMethodCodec::GetInstance());
  system_performance_channel_->SetMethodCallHandler(
      [this](const flutter::MethodCall<flutter::EncodableValue>& call,
             std::unique_ptr<flutter::MethodResult<flutter::EncodableValue>>
                 result) {
        if (call.method_name() == "shutdown") {
          performance_monitor_->Shutdown();
          result->Success();
          return;
        }
        if (call.method_name() == "restartElevated") {
          wchar_t executable[32768] = {};
          GetModuleFileNameW(nullptr, executable, 32768);
          const auto launched = reinterpret_cast<INT_PTR>(ShellExecuteW(
              nullptr, L"runas", executable, nullptr, nullptr, SW_SHOWNORMAL));
          result->Success(flutter::EncodableValue(launched > 32));
          return;
        }
        if (call.method_name() == "processes") {
          flutter::EncodableList entries;
          for (const auto& process : SystemPerformanceMonitor::Processes()) {
            entries.emplace_back(flutter::EncodableMap{
              {flutter::EncodableValue("executable"), flutter::EncodableValue(process.executable)},
              {flutter::EncodableValue("title"), flutter::EncodableValue(process.title)},
            });
          }
          result->Success(flutter::EncodableValue(entries));
          return;
        }
        if (call.method_name() == "configure") {
          const auto* args = call.arguments() ? std::get_if<flutter::EncodableMap>(call.arguments()) : nullptr;
          bool enabled = false;
          uint32_t metrics_mask = 15;
          std::string executable;
          if (args) {
            const auto active = args->find(flutter::EncodableValue("enabled"));
            const auto target = args->find(flutter::EncodableValue("executable"));
            const auto metrics = args->find(flutter::EncodableValue("metricsMask"));
            if (active != args->end()) {
              if (const auto* value = std::get_if<bool>(&active->second)) enabled = *value;
            }
            if (target != args->end()) {
              if (const auto* value = std::get_if<std::string>(&target->second)) executable = *value;
            }
            if (metrics != args->end()) {
              if (const auto* value = std::get_if<int32_t>(&metrics->second)) metrics_mask = static_cast<uint32_t>(*value) & 15;
              else if (const auto* large_value = std::get_if<int64_t>(&metrics->second)) metrics_mask = static_cast<uint32_t>(*large_value) & 15;
            }
          }
          performance_monitor_->Configure(enabled, executable, metrics_mask);
          result->Success();
          return;
        }
        if (call.method_name() != "sample") {
          result->NotImplemented();
          return;
        }
        const auto reading = performance_monitor_->Sample();
        flutter::EncodableMap sample = {
            {flutter::EncodableValue("idleTicks"),
             flutter::EncodableValue(reading.idle_ticks)},
            {flutter::EncodableValue("kernelTicks"),
             flutter::EncodableValue(reading.kernel_ticks)},
            {flutter::EncodableValue("userTicks"),
             flutter::EncodableValue(reading.user_ticks)},
            {flutter::EncodableValue("totalMemoryBytes"),
             flutter::EncodableValue(reading.total_memory_bytes)},
            {flutter::EncodableValue("availableMemoryBytes"),
             flutter::EncodableValue(reading.available_memory_bytes)},
            {flutter::EncodableValue("metricsMask"), flutter::EncodableValue(static_cast<int32_t>(reading.metrics_mask))},
            {flutter::EncodableValue("fpsStatus"), flutter::EncodableValue(reading.fps_status)},
            {flutter::EncodableValue("processId"), flutter::EncodableValue(static_cast<int64_t>(reading.process_id))},
            {flutter::EncodableValue("revision"), flutter::EncodableValue(static_cast<int64_t>(reading.revision))},
        };
        if (reading.frames_per_second) sample[flutter::EncodableValue("framesPerSecond")] = flutter::EncodableValue(*reading.frames_per_second);
        if (reading.gpu_percent) sample[flutter::EncodableValue("gpuPercent")] = flutter::EncodableValue(*reading.gpu_percent);
        result->Success(flutter::EncodableValue(sample));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  
  
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
  if (GetHandle()) KillTimer(GetHandle(), kAudioOutputsTimer);
  audio_outputs_.reset();
  if (audio_outputs_channel_) {
    audio_outputs_channel_->SetMethodCallHandler(nullptr);
    audio_outputs_channel_.reset();
  }
  if (system_volume_channel_) {
    system_volume_channel_->SetMethodCallHandler(nullptr);
    system_volume_channel_.reset();
  }
  native_media_bridge_.reset();
  system_tray_.Stop();
  if (system_tray_channel_) {
    system_tray_channel_->SetMethodCallHandler(nullptr);
    system_tray_channel_.reset();
  }
  if (app_info_channel_) {
    app_info_channel_->SetMethodCallHandler(nullptr);
    app_info_channel_.reset();
  }
  watch_client_viewport_ = false;
  SetRetainClientSurface(false);
  if (client_viewport_channel_) {
    client_viewport_channel_->SetMethodCallHandler(nullptr);
    client_viewport_channel_.reset();
  }
  font_catalog_.Wait();
  font_refresh_pending_ = false;
  font_catalog_started_ = false;
  if (system_fonts_channel_) {
    system_fonts_channel_->SetMethodCallHandler(nullptr);
    system_fonts_channel_.reset();
  }
  if (performance_monitor_) {
    performance_monitor_->Shutdown();
    performance_monitor_.reset();
  }
  if (system_performance_channel_) {
    system_performance_channel_->SetMethodCallHandler(nullptr);
    system_performance_channel_.reset();
  }
  if (flutter_controller_) {
    flutter_controller_ = nullptr;
  }

  Win32Window::OnDestroy();
}

LRESULT
FlutterWindow::MessageHandler(HWND hwnd, UINT const message,
                              WPARAM const wparam,
                              LPARAM const lparam) noexcept {
  if (message == NativeMediaBridge::kReady) {
    if (native_media_bridge_) native_media_bridge_->Drain();
    return 0;
  }
  if (message == NativeMediaBridge::kChanged) {
    if (native_media_bridge_) native_media_bridge_->Changed();
    return 0;
  }
  if (message == AudioOutputDevices::kChanged) {
    if (audio_outputs_) {
      audio_outputs_->AcknowledgeChange();
      SetTimer(hwnd, kAudioOutputsTimer, 180, nullptr);
    }
    return 0;
  }
  if (message == WM_TIMER && wparam == kAudioOutputsTimer) {
    KillTimer(hwnd, kAudioOutputsTimer);
    if (audio_outputs_channel_ && audio_outputs_) {
      try {
        audio_outputs_channel_->InvokeMethod("changed", std::make_unique<flutter::EncodableValue>(
            EncodeAudioOutputs(audio_outputs_->Snapshot())));
      } catch (...) {
        
      }
    }
    return 0;
  }
  if (system_tray_channel_ && system_tray_.requested()) {
    static const UINT taskbar_created = RegisterWindowMessageW(L"TaskbarCreated");
    if (message == SystemTray::kCallback) {
      const char* action = system_tray_.HandleClick(wparam, lparam);
      if (action && system_tray_channel_) {
        system_tray_channel_->InvokeMethod(action, nullptr);
      }
      return 0;
    }
    if (taskbar_created && message == taskbar_created) {
      const bool restored = system_tray_.RestoreAfterShellRestart();
      system_tray_channel_->InvokeMethod(restored ? "available" : "unavailable",
                                          nullptr);
    } else if (message == WM_SETTINGCHANGE || message == WM_THEMECHANGED ||
               message == WM_SYSCOLORCHANGE) {
      system_tray_.RefreshTheme();
    }
  }
  
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case kFontsReady:
      if (font_refresh_pending_ && system_fonts_channel_) {
        font_refresh_pending_ = false;
        RefreshFonts();
      } else if (system_fonts_channel_) {
        system_fonts_channel_->InvokeMethod("changed", nullptr);
      }
      return 0;
    case WM_FONTCHANGE:
      if (flutter_controller_) flutter_controller_->engine()->ReloadSystemFonts();
      if (system_fonts_channel_) RefreshFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

#include "flutter_window.h"

#include <optional>
#include <cstdint>
#include <shellapi.h>

#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

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
          std::string executable;
          if (args) {
            const auto active = args->find(flutter::EncodableValue("enabled"));
            const auto target = args->find(flutter::EncodableValue("executable"));
            if (active != args->end()) {
              if (const auto* value = std::get_if<bool>(&active->second)) enabled = *value;
            }
            if (target != args->end()) {
              if (const auto* value = std::get_if<std::string>(&target->second)) executable = *value;
            }
          }
          performance_monitor_->Configure(enabled, executable);
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
            {flutter::EncodableValue("fpsStatus"), flutter::EncodableValue(reading.fps_status)},
            {flutter::EncodableValue("processId"), flutter::EncodableValue(static_cast<int64_t>(reading.process_id))},
            {flutter::EncodableValue("revision"), flutter::EncodableValue(static_cast<int64_t>(reading.revision))},
        };
        if (reading.frames_per_second) sample[flutter::EncodableValue("framesPerSecond")] = flutter::EncodableValue(*reading.frames_per_second);
        if (reading.gpu_percent) sample[flutter::EncodableValue("gpuPercent")] = flutter::EncodableValue(*reading.gpu_percent);
        result->Success(flutter::EncodableValue(sample));
      });
  SetChildContent(flutter_controller_->view()->GetNativeWindow());

  flutter_controller_->engine()->SetNextFrameCallback([&]() {
    this->Show();
  });

  
  
  
  flutter_controller_->ForceRedraw();

  return true;
}

void FlutterWindow::OnDestroy() {
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
  
  if (flutter_controller_) {
    std::optional<LRESULT> result =
        flutter_controller_->HandleTopLevelWindowProc(hwnd, message, wparam,
                                                      lparam);
    if (result) {
      return *result;
    }
  }

  switch (message) {
    case WM_FONTCHANGE:
      flutter_controller_->engine()->ReloadSystemFonts();
      break;
  }

  return Win32Window::MessageHandler(hwnd, message, wparam, lparam);
}

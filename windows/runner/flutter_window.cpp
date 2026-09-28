#include "flutter_window.h"

#include <optional>
#include <cstdint>

#include <dwmapi.h>
#include <flutter/standard_method_codec.h>

#include "flutter/generated_plugin_registrant.h"

namespace {
int64_t FileTimeTicks(const FILETIME& value) {
  return (static_cast<int64_t>(value.dwHighDateTime) << 32) |
         value.dwLowDateTime;
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
        if (call.method_name() != "sample") {
          result->NotImplemented();
          return;
        }
        FILETIME idle = {}, kernel = {}, user = {};
        MEMORYSTATUSEX memory = {};
        memory.dwLength = sizeof(memory);
        if (!GetSystemTimes(&idle, &kernel, &user) ||
            !GlobalMemoryStatusEx(&memory)) {
          result->Error("system_sample_failed", "Unable to sample system counters");
          return;
        }
        flutter::EncodableMap sample = {
            {flutter::EncodableValue("idleTicks"),
             flutter::EncodableValue(FileTimeTicks(idle))},
            {flutter::EncodableValue("kernelTicks"),
             flutter::EncodableValue(FileTimeTicks(kernel))},
            {flutter::EncodableValue("userTicks"),
             flutter::EncodableValue(FileTimeTicks(user))},
            {flutter::EncodableValue("totalMemoryBytes"),
             flutter::EncodableValue(static_cast<int64_t>(memory.ullTotalPhys))},
            {flutter::EncodableValue("availableMemoryBytes"),
             flutter::EncodableValue(static_cast<int64_t>(memory.ullAvailPhys))},
        };
        DWM_TIMING_INFO timing = {};
        timing.cbSize = sizeof(timing);
        if (SUCCEEDED(DwmGetCompositionTimingInfo(nullptr, &timing))) {
          if (has_dwm_timing_sample_) {
            sample[flutter::EncodableValue("displayedFrames")] =
                flutter::EncodableValue(
                    static_cast<int64_t>(timing.cFramesDisplayed));
          }
          has_dwm_timing_sample_ = true;
        } else {
          has_dwm_timing_sample_ = false;
        }
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

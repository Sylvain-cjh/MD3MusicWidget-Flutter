#ifndef RUNNER_FLUTTER_WINDOW_H_
#define RUNNER_FLUTTER_WINDOW_H_

#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <flutter/method_channel.h>
#include <flutter/encodable_value.h>

#include <memory>

#include "win32Window.h"
#include "systemPerformanceMonitor.h"
#include "systemFonts.h"
#include "nativeMediaBridge.h"


class FlutterWindow : public Win32Window {
 public:
  
  explicit FlutterWindow(const flutter::DartProject& project);
  virtual ~FlutterWindow();

 protected:
  
  bool OnCreate() override;
  void OnDestroy() override;
  LRESULT MessageHandler(HWND window, UINT const message, WPARAM const wparam,
                         LPARAM const lparam) noexcept override;

 private:
  void RefreshFonts();
  SystemFontCatalog font_catalog_;
  bool font_refresh_pending_ = false;
  bool font_catalog_started_ = false;
  
  flutter::DartProject project_;

  
  std::unique_ptr<flutter::FlutterViewController> flutter_controller_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>>
      system_performance_channel_;
  std::unique_ptr<flutter::MethodChannel<flutter::EncodableValue>> system_fonts_channel_;
  
  
  std::unique_ptr<SystemPerformanceMonitor> performance_monitor_;
  std::unique_ptr<NativeMediaBridge> native_media_bridge_;
};

#endif  

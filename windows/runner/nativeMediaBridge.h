#pragma once
#include <flutter/binary_messenger.h>
#include <memory>
#include <windows.h>


class NativeMediaBridge {
public:
  static constexpr UINT kReady = WM_APP + 84;
  static constexpr UINT kChanged = WM_APP + 85;
  NativeMediaBridge(flutter::BinaryMessenger *messenger, HWND window);
  ~NativeMediaBridge();
  void Drain();
  void Changed();

private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};

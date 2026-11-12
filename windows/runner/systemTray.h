#ifndef RUNNER_SYSTEM_TRAY_H_
#define RUNNER_SYSTEM_TRAY_H_

#include <windows.h>

class SystemTray {
 public:
  ~SystemTray();
  bool Start(HWND window);
  void Stop();
  void RefreshTheme();
  bool RestoreAfterShellRestart();
  const char* HandleClick(WPARAM wparam, LPARAM lparam);
  const char* ShowMenuAtCursor();
  bool requested() const { return window_ != nullptr; }
  static constexpr UINT kCallback = WM_APP + 86;

 private:
  bool SetIcon(bool add, bool dark);
  const char* ShowMenu(POINT anchor);
  HWND window_ = nullptr;
  HICON icon_ = nullptr;
  bool dark_ = false;
  bool version4_ = false;
};

#endif

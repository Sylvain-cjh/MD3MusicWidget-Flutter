#include "systemTray.h"

#include <shellapi.h>
#include <strsafe.h>
#include <windowsx.h>

#include "resource.h"

namespace {
constexpr UINT kTrayId = 1;
constexpr UINT kRestore = 1;
constexpr UINT kExit = 2;

bool DarkTaskbar() {
  HIGHCONTRASTW contrast{};
  contrast.cbSize = sizeof(contrast);
  DWORD light = 1;
  DWORD bytes = sizeof(light);
  if (!(SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) &&
        (contrast.dwFlags & HCF_HIGHCONTRASTON)) &&
      RegGetValueW(HKEY_CURRENT_USER,
          L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
          L"SystemUsesLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes) == ERROR_SUCCESS) {
    return light == 0;
  }
  const COLORREF background = GetSysColor(COLOR_WINDOW);
  return 54 * GetRValue(background) + 183 * GetGValue(background) +
             19 * GetBValue(background) < 128 * 256;
}

NOTIFYICONDATAW TrayData(HWND window) {
  NOTIFYICONDATAW data{};
  data.cbSize = sizeof(data);
  data.hWnd = window;
  data.uID = kTrayId;
  return data;
}
}  

SystemTray::~SystemTray() { Stop(); }

bool SystemTray::Start(HWND window) {
  if (window_ == window && icon_) return true;
  if (window_ != window) Stop();
  window_ = window;
  return SetIcon(true, DarkTaskbar());
}

void SystemTray::Stop() {
  if (window_ && icon_) {
    auto data = TrayData(window_);
    Shell_NotifyIconW(NIM_DELETE, &data);
  }
  if (icon_) DestroyIcon(icon_);
  icon_ = nullptr;
  window_ = nullptr;
  version4_ = false;
}

bool SystemTray::SetIcon(bool add, bool dark) {
  if (!window_) return false;
  auto data = TrayData(window_);
  data.uFlags = NIF_ICON;
  const int resource = dark ? IDI_TRAY_ICON_DARK : IDI_APP_ICON;
  const auto next = static_cast<HICON>(LoadImageW(
      GetModuleHandleW(nullptr), MAKEINTRESOURCEW(resource), IMAGE_ICON,
      GetSystemMetrics(SM_CXSMICON), GetSystemMetrics(SM_CYSMICON), 0));
  if (!next) return false;
  data.hIcon = next;
  if (add) {
    data.uFlags |= NIF_MESSAGE | NIF_TIP | NIF_SHOWTIP;
    data.uCallbackMessage = kCallback;
    StringCchCopyW(data.szTip, _countof(data.szTip), L"MD3 Music Widget");
  }
  if (!Shell_NotifyIconW(add ? NIM_ADD : NIM_MODIFY, &data)) {
    DestroyIcon(next);
    return false;
  }
  if (icon_) DestroyIcon(icon_);
  icon_ = next;
  dark_ = dark;
  if (add) {
    data.uVersion = NOTIFYICON_VERSION_4;
    version4_ = Shell_NotifyIconW(NIM_SETVERSION, &data) != FALSE;
  }
  return true;
}

void SystemTray::RefreshTheme() {
  if (!window_ || !icon_) return;
  const bool dark = DarkTaskbar();
  if (dark != dark_) SetIcon(false, dark);
}

bool SystemTray::RestoreAfterShellRestart() {
  const bool dark = DarkTaskbar();
  return SetIcon(true, dark) || (icon_ && SetIcon(false, dark));
}

const char* SystemTray::HandleClick(WPARAM wparam, LPARAM lparam) {
  if (!window_ || !icon_) return nullptr;
  if (version4_ && HIWORD(lparam) != kTrayId) return nullptr;
  const UINT event = version4_ ? LOWORD(lparam) : static_cast<UINT>(lparam);
  if (event == NIN_SELECT || event == NIN_KEYSELECT ||
      (!version4_ && event == WM_LBUTTONUP)) {
    return "activate";
  }
  if (event != WM_CONTEXTMENU && (version4_ || event != WM_RBUTTONUP)) {
    return nullptr;
  }
  POINT anchor{};
  if (version4_) {
    anchor = {GET_X_LPARAM(wparam), GET_Y_LPARAM(wparam)};
  } else if (!GetCursorPos(&anchor)) {
    return nullptr;
  }
  return ShowMenu(anchor);
}

const char* SystemTray::ShowMenuAtCursor() {
  POINT cursor{};
  return window_ && icon_ && GetCursorPos(&cursor) ? ShowMenu(cursor) : nullptr;
}

const char* SystemTray::ShowMenu(POINT anchor) {
  const HMENU menu = CreatePopupMenu();
  if (!menu) return nullptr;
  AppendMenuW(menu, MF_STRING, kRestore, L"恢复鼠标交互");
  AppendMenuW(menu, MF_SEPARATOR, 0, nullptr);
  AppendMenuW(menu, MF_STRING, kExit, L"完全退出挂件");
  SetForegroundWindow(window_);
  const UINT command = TrackPopupMenu(
      menu, TPM_RETURNCMD | TPM_NONOTIFY | TPM_RIGHTBUTTON,
      anchor.x, anchor.y, 0, window_, nullptr);
  PostMessageW(window_, WM_NULL, 0, 0);
  DestroyMenu(menu);
  if (command == kRestore) return "restore";
  if (command == kExit) return "exit";
  return nullptr;
}

#include "win32Window.h"

#include <algorithm>
#include <cstdint>
#include <dwmapi.h>
#include <flutter_windows.h>

#include "resource.h"

namespace {






#ifndef DWMWA_USE_IMMERSIVE_DARK_MODE
#define DWMWA_USE_IMMERSIVE_DARK_MODE 20
#endif

constexpr const wchar_t kWindowClassName[] = L"FLUTTER_RUNNER_WIN32_WINDOW";





constexpr const wchar_t kGetPreferredBrightnessRegKey[] =
  L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize";
constexpr const wchar_t kGetPreferredBrightnessRegValue[] = L"AppsUseLightTheme";


static int g_active_window_count = 0;

using EnableNonClientDpiScaling = BOOL __stdcall(HWND hwnd);



int Scale(int source, double scale_factor) {
  return static_cast<int>(source * scale_factor);
}



void EnableFullDpiSupportIfAvailable(HWND hwnd) {
  HMODULE user32_module = LoadLibraryA("User32.dll");
  if (!user32_module) {
    return;
  }
  auto enable_non_client_dpi_scaling =
      reinterpret_cast<EnableNonClientDpiScaling*>(
          GetProcAddress(user32_module, "EnableNonClientDpiScaling"));
  if (enable_non_client_dpi_scaling != nullptr) {
    enable_non_client_dpi_scaling(hwnd);
  }
  FreeLibrary(user32_module);
}

}  


class WindowClassRegistrar {
 public:
  ~WindowClassRegistrar() = default;

  
  static WindowClassRegistrar* GetInstance() {
    if (!instance_) {
      instance_ = new WindowClassRegistrar();
    }
    return instance_;
  }

  
  
  const wchar_t* GetWindowClass();

  
  
  void UnregisterWindowClass();

 private:
  WindowClassRegistrar() = default;

  static WindowClassRegistrar* instance_;

  bool class_registered_ = false;
};

WindowClassRegistrar* WindowClassRegistrar::instance_ = nullptr;

const wchar_t* WindowClassRegistrar::GetWindowClass() {
  if (!class_registered_) {
    WNDCLASS window_class{};
    window_class.hCursor = LoadCursor(nullptr, IDC_ARROW);
    window_class.lpszClassName = kWindowClassName;
    
    
    window_class.style = 0;
    window_class.cbClsExtra = 0;
    window_class.cbWndExtra = 0;
    window_class.hInstance = GetModuleHandle(nullptr);
    window_class.hIcon =
        LoadIcon(window_class.hInstance, MAKEINTRESOURCE(IDI_APP_ICON));
    window_class.hbrBackground = 0;
    window_class.lpszMenuName = nullptr;
    window_class.lpfnWndProc = Win32Window::WndProc;
    RegisterClass(&window_class);
    class_registered_ = true;
  }
  return kWindowClassName;
}

void WindowClassRegistrar::UnregisterWindowClass() {
  UnregisterClass(kWindowClassName, nullptr);
  class_registered_ = false;
}

Win32Window::Win32Window() {
  ++g_active_window_count;
}

Win32Window::~Win32Window() {
  --g_active_window_count;
  Destroy();
}

bool Win32Window::Create(const std::wstring& title,
                         const Point& origin,
                         const Size& size) {
  Destroy();

  const wchar_t* window_class =
      WindowClassRegistrar::GetInstance()->GetWindowClass();

  const POINT target_point = {static_cast<LONG>(origin.x),
                              static_cast<LONG>(origin.y)};
  HMONITOR monitor = MonitorFromPoint(target_point, MONITOR_DEFAULTTONEAREST);
  UINT dpi = FlutterDesktopGetDpiForMonitor(monitor);
  double scale_factor = dpi / 96.0;

  HWND window = CreateWindow(
      window_class, title.c_str(), WS_OVERLAPPEDWINDOW,
      Scale(origin.x, scale_factor), Scale(origin.y, scale_factor),
      Scale(size.width, scale_factor), Scale(size.height, scale_factor),
      nullptr, nullptr, GetModuleHandle(nullptr), this);

  if (!window) {
    return false;
  }

  UpdateTheme(window);

  return OnCreate();
}

bool Win32Window::Show() {
  return ShowWindow(window_handle_, SW_SHOWNORMAL);
}


LRESULT CALLBACK Win32Window::WndProc(HWND const window,
                                      UINT const message,
                                      WPARAM const wparam,
                                      LPARAM const lparam) noexcept {
  if (message == WM_NCCREATE) {
    auto window_struct = reinterpret_cast<CREATESTRUCT*>(lparam);
    SetWindowLongPtr(window, GWLP_USERDATA,
                     reinterpret_cast<LONG_PTR>(window_struct->lpCreateParams));

    auto that = static_cast<Win32Window*>(window_struct->lpCreateParams);
    EnableFullDpiSupportIfAvailable(window);
    that->window_handle_ = window;
  } else if (Win32Window* that = GetThisFromHandle(window)) {
    return that->MessageHandler(window, message, wparam, lparam);
  }

  return DefWindowProc(window, message, wparam, lparam);
}

LRESULT
Win32Window::MessageHandler(HWND hwnd,
                            UINT const message,
                            WPARAM const wparam,
                            LPARAM const lparam) noexcept {
  switch (message) {
    case WM_DESTROY:
      window_handle_ = nullptr;
      Destroy();
      if (quit_on_close_) {
        PostQuitMessage(0);
      }
      return 0;

    case WM_DPICHANGED: {
      auto newRectSize = reinterpret_cast<RECT*>(lparam);
      LONG newWidth = newRectSize->right - newRectSize->left;
      LONG newHeight = newRectSize->bottom - newRectSize->top;

      reset_client_surface_ = true;
      SetWindowPos(hwnd, nullptr, newRectSize->left, newRectSize->top, newWidth,
                   newHeight, SWP_NOZORDER | SWP_NOACTIVATE);
      reset_client_surface_ = false;

      return 0;
    }
    case WM_ERASEBKGND:
      
      return 1;

    case WM_WINDOWPOSCHANGING: {
      POINT origin{};
      have_client_origin_before_position_ = ClientToScreen(hwnd, &origin);
      client_origin_before_position_ = origin;
      break;
    }
    case WM_WINDOWPOSCHANGED: {
      
      const auto result = DefWindowProc(hwnd, message, wparam, lparam);
      have_client_origin_before_position_ = false;
      return result;
    }

    case WM_SIZE: {
      if (child_content_ == nullptr || wparam == SIZE_MINIMIZED) {
        return 0;
      }
      RECT rect = GetClientArea();
      RECT child_rect{};
      auto width = rect.right - rect.left;
      auto height = rect.bottom - rect.top;
      const bool child_size_known = GetClientRect(child_content_, &child_rect);
      POINT inset{};
      if (child_size_known && width > 0 && height > 0 &&
          retain_client_surface_ && !reset_client_surface_ &&
          IsWindowVisible(hwnd)) {
        
        
        
        
        constexpr int64_t kMaxExtraPixels = 1024 * 1024;
        auto x = client_surface_inset_.x;
        auto y = client_surface_inset_.y;
        POINT origin{};
        if (have_client_origin_before_position_ && ClientToScreen(hwnd, &origin)) {
          x += origin.x - client_origin_before_position_.x;
          y += origin.y - client_origin_before_position_.y;
        }
        
        
        const auto candidate_x = (std::max)(0L, x);
        const auto candidate_y = (std::max)(0L, y);
        const auto required_width = width + candidate_x;
        const auto required_height = height + candidate_y;
        const auto retained_width = (std::max)(required_width, child_rect.right);
        const auto retained_height = (std::max)(required_height, child_rect.bottom);
        const auto extra = int64_t{retained_width} * retained_height -
                           int64_t{width} * height;
        
        
        if ((required_width <= child_rect.right &&
             required_height <= child_rect.bottom) ||
            extra <= kMaxExtraPixels) {
          inset = {candidate_x, candidate_y};
          width = retained_width;
          height = retained_height;
        }
      }
      const auto old_inset = client_surface_inset_;
      const bool moved = old_inset.x != inset.x || old_inset.y != inset.y;
      const bool resized = !child_size_known || child_rect.right != width ||
                           child_rect.bottom != height;
      if (width > 0 && height > 0 && (resized || moved)) {
        
        
        
        client_surface_inset_ = inset;
        if (resized) OnClientSurfaceChanged();
        if (!SetWindowPos(child_content_, nullptr, -inset.x, -inset.y,
                          width, height,
                          SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOREDRAW |
                              (resized ? 0 : SWP_NOSIZE))) {
          client_surface_inset_ = old_inset;
        }
      }
      OnClientSurfaceChanged();
      return 0;
    }

    case WM_SHOWWINDOW:
      if (!wparam && retain_client_surface_ && child_content_ != nullptr &&
          IsWindow(child_content_)) {
        
        
        const auto rect = GetClientArea();
        RECT child_rect{};
        if (rect.right > 0 && rect.bottom > 0 &&
            GetClientRect(child_content_, &child_rect) &&
            (child_rect.right != rect.right || child_rect.bottom != rect.bottom ||
             client_surface_inset_.x != 0 || client_surface_inset_.y != 0)) {
          const auto old_inset = client_surface_inset_;
          client_surface_inset_ = {};
          OnClientSurfaceChanged();
          if (!SetWindowPos(child_content_, nullptr, 0, 0, rect.right, rect.bottom,
                            SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOREDRAW)) {
            client_surface_inset_ = old_inset;
            OnClientSurfaceChanged();
          }
        }
      }
      break;

    case WM_ACTIVATE:
      if (LOWORD(wparam) != WA_INACTIVE && child_content_ != nullptr) {
        SetFocus(child_content_);
      }
      return 0;

    case WM_DWMCOLORIZATIONCOLORCHANGED:
      UpdateTheme(hwnd);
      return 0;
  }

  return DefWindowProc(window_handle_, message, wparam, lparam);
}

void Win32Window::Destroy() {
  OnDestroy();

  if (window_handle_) {
    DestroyWindow(window_handle_);
    window_handle_ = nullptr;
  }
  if (g_active_window_count == 0) {
    WindowClassRegistrar::GetInstance()->UnregisterWindowClass();
  }
}

Win32Window* Win32Window::GetThisFromHandle(HWND const window) noexcept {
  return reinterpret_cast<Win32Window*>(
      GetWindowLongPtr(window, GWLP_USERDATA));
}

void Win32Window::SetChildContent(HWND content) {
  child_content_ = content;
  client_surface_inset_ = {};
  SetParent(content, window_handle_);
  RECT frame = GetClientArea();

  MoveWindow(content, frame.left, frame.top, frame.right - frame.left,
             frame.bottom - frame.top, true);

  SetFocus(child_content_);
}

RECT Win32Window::GetClientArea() {
  RECT frame;
  GetClientRect(window_handle_, &frame);
  return frame;
}

HWND Win32Window::GetHandle() {
  return window_handle_;
}

void Win32Window::SetQuitOnClose(bool quit_on_close) {
  quit_on_close_ = quit_on_close;
}

bool Win32Window::OnCreate() {
  
  return true;
}

void Win32Window::OnDestroy() {
  
}

void Win32Window::UpdateTheme(HWND const window) {
  DWORD light_mode;
  DWORD light_mode_size = sizeof(light_mode);
  LSTATUS result = RegGetValue(HKEY_CURRENT_USER, kGetPreferredBrightnessRegKey,
                               kGetPreferredBrightnessRegValue,
                               RRF_RT_REG_DWORD, nullptr, &light_mode,
                               &light_mode_size);

  if (result == ERROR_SUCCESS) {
    BOOL enable_dark_mode = light_mode == 0;
    DwmSetWindowAttribute(window, DWMWA_USE_IMMERSIVE_DARK_MODE,
                          &enable_dark_mode, sizeof(enable_dark_mode));
  }
}

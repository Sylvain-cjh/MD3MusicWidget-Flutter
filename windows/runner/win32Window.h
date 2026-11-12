#ifndef RUNNER_WIN32_WINDOW_H_
#define RUNNER_WIN32_WINDOW_H_

#include <windows.h>

#include <functional>
#include <memory>
#include <string>




class Win32Window {
 public:
  struct Point {
    unsigned int x;
    unsigned int y;
    Point(unsigned int x, unsigned int y) : x(x), y(y) {}
  };

  struct Size {
    unsigned int width;
    unsigned int height;
    Size(unsigned int width, unsigned int height)
        : width(width), height(height) {}
  };

  Win32Window();
  virtual ~Win32Window();

  
  
  
  
  
  
  bool Create(const std::wstring& title, const Point& origin, const Size& size);

  
  bool Show();

  
  void Destroy();

  
  void SetChildContent(HWND content);

  
  
  HWND GetHandle();

  
  void SetQuitOnClose(bool quit_on_close);

  
  RECT GetClientArea();

 protected:
  void SetRetainClientSurface(bool retain) { retain_client_surface_ = retain; }
  POINT ClientSurfaceInset() const { return client_surface_inset_; }
  virtual void OnClientSurfaceChanged() {}

  
  
  
  virtual LRESULT MessageHandler(HWND window,
                                 UINT const message,
                                 WPARAM const wparam,
                                 LPARAM const lparam) noexcept;

  
  
  virtual bool OnCreate();

  
  virtual void OnDestroy();

 private:
  friend class WindowClassRegistrar;

  
  
  
  
  
  static LRESULT CALLBACK WndProc(HWND const window,
                                  UINT const message,
                                  WPARAM const wparam,
                                  LPARAM const lparam) noexcept;

  
  static Win32Window* GetThisFromHandle(HWND const window) noexcept;

  
  static void UpdateTheme(HWND const window);

  bool quit_on_close_ = false;

  
  HWND window_handle_ = nullptr;

  
  HWND child_content_ = nullptr;
  bool retain_client_surface_ = false;
  bool reset_client_surface_ = false;
  POINT client_surface_inset_{};
  POINT client_origin_before_position_{};
  bool have_client_origin_before_position_ = false;
};

#endif  

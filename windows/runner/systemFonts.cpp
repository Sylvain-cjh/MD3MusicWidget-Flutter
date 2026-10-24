#include "systemFonts.h"
#include <windows.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <algorithm>

std::vector<std::string> SystemFontFamilies() {
  using Microsoft::WRL::ComPtr;
  ComPtr<IDWriteFactory> factory;
  if (FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED, __uuidof(IDWriteFactory),
      reinterpret_cast<IUnknown**>(factory.GetAddressOf())))) return {};
  ComPtr<IDWriteFontCollection> collection;
  if (FAILED(factory->GetSystemFontCollection(collection.GetAddressOf(), TRUE))) return {};
  std::vector<std::string> result;
  const auto count = collection->GetFontFamilyCount();
  result.reserve(count);
  for (UINT32 i = 0; i < count; ++i) {
    ComPtr<IDWriteFontFamily> family;
    ComPtr<IDWriteLocalizedStrings> names;
    if (FAILED(collection->GetFontFamily(i, family.GetAddressOf())) ||
        FAILED(family->GetFamilyNames(names.GetAddressOf())) || names->GetCount() == 0) continue;
    UINT32 index = 0, length = 0;
    BOOL found = FALSE;
    names->FindLocaleName(L"en-us", &index, &found);
    if (!found) index = 0;
    if (FAILED(names->GetStringLength(index, &length)) || length > 4096) continue;
    std::wstring name(length + 1, L'\0');
    if (FAILED(names->GetString(index, name.data(), length + 1))) continue;
    const int bytes = WideCharToMultiByte(CP_UTF8, 0, name.data(), static_cast<int>(length),
                                        nullptr, 0, nullptr, nullptr);
    if (bytes <= 0) continue;
    std::string utf8(bytes, '\0');
    WideCharToMultiByte(CP_UTF8, 0, name.data(), static_cast<int>(length),
                        utf8.data(), bytes, nullptr, nullptr);
    result.push_back(std::move(utf8));
  }
  std::sort(result.begin(), result.end());
  result.erase(std::unique(result.begin(), result.end()), result.end());
  return result;
}

SystemFontCatalog::~SystemFontCatalog() { Wait(); }
void SystemFontCatalog::Wait() {
  if (worker_.joinable()) worker_.join();
}
std::vector<std::string> SystemFontCatalog::Snapshot(bool* ready) const {
  std::lock_guard<std::mutex> guard(mutex_);
  *ready = ready_;
  return families_;
}
bool SystemFontCatalog::Refresh(std::function<void()> completed) {
  if (worker_.joinable()) {
    bool ready = false;
    Snapshot(&ready);
    if (!ready) return false;
    worker_.join();
  }
  {
    std::lock_guard<std::mutex> guard(mutex_);
    ready_ = false;
  }
  try {
  worker_ = std::thread([this, completed = std::move(completed)] {
    std::vector<std::string> names;
    try { names = SystemFontFamilies(); } catch (...) { }
    {
      std::lock_guard<std::mutex> guard(mutex_);
      families_ = std::move(names);
      ready_ = true;
    }
    completed();
  });
  } catch (...) {
    std::lock_guard<std::mutex> guard(mutex_);
    ready_ = true; 
  }
  return true;
}

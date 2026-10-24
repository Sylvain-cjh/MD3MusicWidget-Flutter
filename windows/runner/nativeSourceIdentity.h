#pragma once
#include <algorithm>
#include <cwctype>
#include <string>



inline std::wstring NativeIdentityKey(std::wstring value) {
  std::replace(value.begin(), value.end(), L'/', L'\\');
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) {
    return static_cast<wchar_t>(std::towlower(c));
  });
  return value;
}
inline bool NativeSourceMatchesExecutable(const std::wstring &source,
                                          const std::wstring &path) {
  if (source.empty() || path.empty())
    return false;
  const auto id = NativeIdentityKey(source), image = NativeIdentityKey(path);
  if (id.find(L'\\') != std::wstring::npos)
    return id == image;
  const auto split = image.find_last_of(L'\\');
  const auto name = image.substr(split == std::wstring::npos ? 0 : split + 1);
  if (id == name)
    return true;
  if (name.size() > 4 && name.substr(name.size() - 4) == L".exe")
    return id == name.substr(0, name.size() - 4);
  return false;
}

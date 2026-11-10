#pragma once
#include "nativeSourceIdentity.h"
#include <cmath>
#include <cwchar>

namespace netease_uia {
inline bool IsExplicitNetEaseSource(const std::wstring &source) {
  const auto id = NativeIdentityKey(source);
  return NativeSourceMatchesExecutable(L"cloudmusic.exe", id) ||
         id == L"cloudmusic";
}

inline std::wstring TrimText(std::wstring value) {
  const auto white = [](wchar_t ch) { return std::iswspace(ch) != 0; };
  value.erase(value.begin(), std::find_if_not(value.begin(), value.end(), white));
  value.erase(std::find_if_not(value.rbegin(), value.rend(), white).base(),
              value.end());
  return value;
}

inline bool SameTrackText(const std::wstring &title, const std::wstring &artist,
                          const std::wstring &otherTitle,
                          const std::wstring &otherArtist) {
  return !TrimText(title).empty() && !TrimText(artist).empty() &&
         _wcsicmp(TrimText(title).c_str(), TrimText(otherTitle).c_str()) == 0 &&
         _wcsicmp(TrimText(artist).c_str(), TrimText(otherArtist).c_str()) == 0;
}

enum class Route { smtc, full, timeline };

inline Route SelectRoute(const std::wstring &selected, bool hasTrack,
                         bool hasPosition, double duration, double position,
                         const std::wstring &title, const std::wstring &artist,
                         const std::wstring &uiaTitle, const std::wstring &uiaArtist,
                         double uiaDuration, double uiaPosition) {
  if (!IsExplicitNetEaseSource(selected) ||
      (hasTrack && hasPosition && duration > 0) ||
      TrimText(uiaTitle).empty() || TrimText(uiaArtist).empty() ||
      !std::isfinite(uiaPosition) || !std::isfinite(uiaDuration) ||
      uiaDuration <= 0 || uiaPosition < 0 || uiaPosition > uiaDuration)
    return Route::smtc;
  if (!hasTrack) return Route::full;
  if (!SameTrackText(title, artist, uiaTitle, uiaArtist) ||
      (hasPosition && std::abs(position - uiaPosition) > 4000) ||
      (duration > 0 && std::abs(duration - uiaDuration) > 2000))
    return Route::smtc;
  return Route::timeline;
}
} 

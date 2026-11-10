#pragma once
#include "nativeNeteaseUiaPolicy.h"
#ifndef NOMINMAX
#define NOMINMAX
#endif
#include <windows.h>
#include <tlhelp32.h>
#include <uiautomation.h>
#include <wrl/client.h>

#include <algorithm>
#include <chrono>
#include <cwctype>
#include <optional>
#include <regex>
#include <set>
#include <string>
#include <vector>

namespace netease_uia {
using Microsoft::WRL::ComPtr;
using Clock = std::chrono::steady_clock;
using Progress = std::pair<int, int>;

inline std::optional<int> ParseTime(const std::wstring &text) {
  static const std::wregex pattern(LR"(^(?:(\d{1,2}):)?(\d{1,3}):([0-5]\d)$)");
  std::wsmatch match;
  if (!std::regex_match(text, match, pattern)) return {};
  const int minutes = std::stoi(match[2]);
  if (match[1].matched && minutes > 59) return {};
  const int hours = match[1].matched ? std::stoi(match[1]) : 0;
  return hours * 3600 + minutes * 60 + std::stoi(match[3]);
}

inline std::optional<Progress> ParseProgress(const std::wstring &name) {
  static const std::wregex pattern(
      LR"(^\s*([0-9:]{3,9})\s*[/|／]\s*([0-9:]{3,9})\s*$)");
  std::wsmatch match;
  if (name.size() > 48 || !std::regex_match(name, match, pattern)) return {};
  const auto position = ParseTime(match[1]);
  const auto duration = ParseTime(match[2]);
  if (!position || !duration || *duration == 0 || *position > *duration) {
    return {};
  }
  return Progress{*position, *duration};
}

inline std::wstring WindowTitle(HWND hwnd) {
  wchar_t title[512]{};
  return std::wstring(title, GetWindowTextW(hwnd, title, ARRAYSIZE(title)));
}

inline bool HasTrackCandidate(const std::wstring &title) {
  const auto split = title.find(L" - ");
  return split != std::wstring::npos && split > 0 && split + 3 < title.size() &&
         title.find(L"MediaPlayer") == std::wstring::npos &&
         title.find(L" - ", split + 3) == std::wstring::npos;
}

inline std::optional<std::set<DWORD>> NetEaseProcesses() {
  std::set<DWORD> ids;
  const auto snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return {};
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  if (!Process32FirstW(snapshot, &entry)) {
    CloseHandle(snapshot);
    return {};
  }
  do {
    if (_wcsicmp(entry.szExeFile, L"cloudmusic.exe") == 0) {
      ids.insert(entry.th32ProcessID);
    }
  } while (Process32NextW(snapshot, &entry));
  const bool complete = GetLastError() == ERROR_NO_MORE_FILES;
  CloseHandle(snapshot);
  return complete ? std::optional{std::move(ids)} : std::nullopt;
}

struct WindowSample {
  HWND hwnd;
  DWORD pid;
  std::wstring title;
  bool visible;
  bool minimized;
};

struct WindowSearch {
  const std::set<DWORD> &ids;
  std::vector<WindowSample> windows;
};

inline BOOL CALLBACK CollectWindows(HWND hwnd, LPARAM parameter) {
  auto &search = *reinterpret_cast<WindowSearch *>(parameter);
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (search.ids.count(pid)) {
    search.windows.push_back({hwnd, pid, WindowTitle(hwnd),
                              IsWindowVisible(hwnd) != FALSE,
                              IsIconic(hwnd) != FALSE});
  }
  return TRUE;
}

inline bool StillNetEase(HWND hwnd, DWORD expectedPid,
                         const std::wstring &selected = L"cloudmusic.exe") {
  DWORD pid = 0;
  GetWindowThreadProcessId(hwnd, &pid);
  if (pid != expectedPid) return false;
  const auto process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
  if (!process) return false;
  wchar_t path[1024]{};
  DWORD size = ARRAYSIZE(path);
  const bool ok = QueryFullProcessImageNameW(process, 0, path, &size) != FALSE;
  CloseHandle(process);
  if (!ok) return false;
  const std::wstring full(path, size);
  return NativeSourceMatchesExecutable(L"cloudmusic.exe", full) &&
         NativeSourceMatchesExecutable(selected, full);
}

struct UiaScan {
  HRESULT result = E_FAIL;
  size_t textCount = 0;
  bool unstable = false;
  std::set<Progress> times;
};

inline UiaScan ScanTextElements(IUIAutomation *automation, HWND hwnd) {
  UiaScan scan;
  ComPtr<IUIAutomationElement> root;
  scan.result = automation->ElementFromHandle(hwnd, &root);
  if (FAILED(scan.result) || !root) return scan;
  VARIANT type{};
  type.vt = VT_I4;
  type.lVal = UIA_TextControlTypeId;
  ComPtr<IUIAutomationCondition> textCondition;
  scan.result = automation->CreatePropertyCondition(
      UIA_ControlTypePropertyId, type, &textCondition);
  if (FAILED(scan.result)) return scan;
  ComPtr<IUIAutomationCacheRequest> cache;
  scan.result = automation->CreateCacheRequest(&cache);
  if (FAILED(scan.result)) return scan;
  scan.result = cache->AddProperty(UIA_NamePropertyId);
  if (FAILED(scan.result)) return scan;
  scan.result = cache->put_AutomationElementMode(AutomationElementMode_None);
  if (FAILED(scan.result)) return scan;
  ComPtr<IUIAutomationElementArray> results;
  scan.result = root->FindAllBuildCache(TreeScope_Descendants, textCondition.Get(),
                                        cache.Get(), &results);
  if (FAILED(scan.result) || !results) return scan;
  int count = 0;
  scan.result = results->get_Length(&count);
  if (FAILED(scan.result)) return scan;
  scan.textCount = count > 0 ? static_cast<size_t>(count) : 0;
  
  if (count > 2048) {
    scan.result = HRESULT_FROM_WIN32(ERROR_MORE_DATA);
    return scan;
  }
  for (int i = 0; i < count; ++i) {
    ComPtr<IUIAutomationElement> element;
    if (FAILED(results->GetElement(i, &element)) || !element) continue;
    BSTR name = nullptr;
    if (SUCCEEDED(element->get_CachedName(&name)) && name) {
      if (const auto time = ParseProgress({name, SysStringLen(name)})) {
        scan.times.insert(*time);
      }
    }
    SysFreeString(name);
  }
  return scan;
}

inline UiaScan ReadWindow(IUIAutomation *automation, const WindowSample &window,
                          const std::wstring &selected = L"cloudmusic.exe") {
  if (!StillNetEase(window.hwnd, window.pid, selected)) {
    UiaScan invalid;
    invalid.result = HRESULT_FROM_WIN32(ERROR_INVALID_WINDOW_HANDLE);
    return invalid;
  }
  auto scan = ScanTextElements(automation, window.hwnd);
  scan.unstable = WindowTitle(window.hwnd) != window.title ||
                  !StillNetEase(window.hwnd, window.pid, selected);
  return scan;
}
} 

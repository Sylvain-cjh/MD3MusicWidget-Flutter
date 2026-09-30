#include "system_performance_monitor.h"

#include <tlhelp32.h>
#include <pdh.h>
#include <pdhmsg.h>
#include <algorithm>
#include <chrono>
#include <cmath>
#include <cwctype>
#include <map>
#include <vector>

#include "frame_rate_window.h"

namespace {
using Clock = std::chrono::steady_clock;
double Seconds() { return std::chrono::duration<double>(Clock::now().time_since_epoch()).count(); }
int64_t Ticks(const FILETIME& value) {
  return (static_cast<int64_t>(value.dwHighDateTime) << 32) | value.dwLowDateTime;
}
std::wstring Wide(const std::string& value) {
  if (value.empty()) return {};
  const int length = MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0);
  std::wstring result(length, L'\0');
  MultiByteToWideChar(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), length);
  return result;
}
std::string Utf8(const std::wstring& value) {
  if (value.empty()) return {};
  const int length = WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), nullptr, 0, nullptr, nullptr);
  std::string result(length, '\0');
  WideCharToMultiByte(CP_UTF8, 0, value.data(), static_cast<int>(value.size()), result.data(), length, nullptr, nullptr);
  return result;
}
std::wstring Lower(std::wstring value) {
  std::transform(value.begin(), value.end(), value.begin(), [](wchar_t c) { return static_cast<wchar_t>(std::towlower(c)); });
  return value;
}
BOOL CALLBACK CollectWindows(HWND window, LPARAM parameter) {
  if (!IsWindowVisible(window) || GetWindow(window, GW_OWNER)) return TRUE;
  DWORD process = 0;
  GetWindowThreadProcessId(window, &process);
  wchar_t title[512] = {};
  if (GetWindowTextW(window, title, 512) > 0) {
    auto& windows = *reinterpret_cast<std::map<DWORD, std::wstring>*>(parameter);
    windows.emplace(process, title);
  }
  return TRUE;
}
std::map<DWORD, std::wstring> Windows() {
  std::map<DWORD, std::wstring> windows;
  EnumWindows(CollectWindows, reinterpret_cast<LPARAM>(&windows));
  return windows;
}
DWORD FindProcess(const std::wstring& executable) {
  const auto windows = Windows();
  const auto wanted = Lower(executable);
  DWORD result = 0;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return 0;
  PROCESSENTRY32W entry = {}; entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) do {
    if (Lower(entry.szExeFile) != wanted) continue;
    if (!result) result = entry.th32ProcessID;
    if (windows.count(entry.th32ProcessID)) { result = entry.th32ProcessID; break; }
  } while (Process32NextW(snapshot, &entry));
  CloseHandle(snapshot);
  return result;
}

class GpuCounter {
 public:
  ~GpuCounter() { if (query_) PdhCloseQuery(query_); }
  std::optional<double> Read() {
    if (!query_) {
      if (PdhOpenQueryW(nullptr, 0, &query_) != ERROR_SUCCESS) return std::nullopt;
      if (PdhAddEnglishCounterW(query_, L"\\GPU Engine(*)\\Utilization Percentage", 0, &counter_) != ERROR_SUCCESS) {
        PdhCloseQuery(query_); query_ = nullptr; return std::nullopt;
      }
      PdhCollectQueryData(query_);
      return std::nullopt;
    }
    if (PdhCollectQueryData(query_) != ERROR_SUCCESS) return std::nullopt;
    DWORD bytes = 0, count = 0;
    if (PdhGetFormattedCounterArrayW(counter_, PDH_FMT_DOUBLE, &bytes, &count, nullptr) != PDH_MORE_DATA || !bytes) return std::nullopt;
    buffer_.resize((bytes + sizeof(uint64_t) - 1) / sizeof(uint64_t));
    auto* items = reinterpret_cast<PDH_FMT_COUNTERVALUE_ITEM_W*>(buffer_.data());
    if (PdhGetFormattedCounterArrayW(counter_, PDH_FMT_DOUBLE, &bytes, &count, items) != ERROR_SUCCESS) return std::nullopt;
    std::map<std::wstring, double> engines;
    for (DWORD i = 0; i < count; ++i) {
      const auto& value = items[i].FmtValue;
      if ((value.CStatus != PDH_CSTATUS_VALID_DATA && value.CStatus != PDH_CSTATUS_NEW_DATA) || !std::isfinite(value.doubleValue)) continue;
      std::wstring name(items[i].szName);
      const auto start = name.find(L"luid_");
      if (start == std::wstring::npos) continue;
      name = name.substr(start);
      const auto duplicate = name.find(L'#');
      if (duplicate != std::wstring::npos) name.resize(duplicate);
      engines[name] += std::max(0.0, value.doubleValue);
    }
    if (engines.empty()) return std::nullopt;
    double busiest = 0;
    for (const auto& engine : engines) busiest = std::max(busiest, engine.second);
    return std::clamp(busiest, 0.0, 100.0);
  }
 private:
  PDH_HQUERY query_ = nullptr;
  PDH_HCOUNTER counter_ = nullptr;
  std::vector<uint64_t> buffer_;
};

class FrameCapture {
 public:
  FrameCapture() {
    wchar_t path[32768] = {};
    const DWORD length = GetModuleFileNameW(nullptr, path, 32768);
    executable_ = std::wstring(path, length);
    const auto slash = executable_.find_last_of(L"\\/");
    executable_.resize(slash == std::wstring::npos ? 0 : slash + 1);
    executable_ += L"runtime\\PresentMon.exe";
    session_ = L"MD3MusicWidgetFPS-" + std::to_wstring(GetCurrentProcessId());
  }
  ~FrameCapture() { Stop(); }
  void Start(DWORD target) {
    Stop();
    if (GetFileAttributesW(executable_.c_str()) == INVALID_FILE_ATTRIBUTES) { status = "missingHelper"; return; }
    SECURITY_ATTRIBUTES security = {sizeof(security), nullptr, TRUE};
    HANDLE output = nullptr;
    if (!CreatePipe(&pipe_, &output, &security, 0)) { status = "captureFailed"; return; }
    SetHandleInformation(pipe_, HANDLE_FLAG_INHERIT, 0);
    HANDLE input = CreateFileW(L"NUL", GENERIC_READ, FILE_SHARE_READ | FILE_SHARE_WRITE, &security, OPEN_EXISTING, 0, nullptr);
    STARTUPINFOW startup = {}; startup.cb = sizeof(startup);
    startup.dwFlags = STARTF_USESTDHANDLES;
    startup.hStdOutput = output; startup.hStdError = output; startup.hStdInput = input;
    PROCESS_INFORMATION process = {};
    std::wstring command = L"\"" + executable_ + L"\" --process_id " + std::to_wstring(target) +
      L" --output_stdout --no_console_stats --v1_metrics --no_track_gpu --no_track_input --session_name " +
      session_ + L" --stop_existing_session --terminate_on_proc_exit";
    const BOOL started = CreateProcessW(executable_.c_str(), command.data(), nullptr, nullptr, TRUE,
      CREATE_NO_WINDOW | CREATE_SUSPENDED, nullptr, nullptr, &startup, &process);
    CloseHandle(output);
    if (input != INVALID_HANDLE_VALUE) CloseHandle(input);
    if (!started) { CloseHandle(pipe_); pipe_ = nullptr; status = "captureFailed"; return; }
    job_ = CreateJobObjectW(nullptr, nullptr);
    if (job_) {
      JOBOBJECT_EXTENDED_LIMIT_INFORMATION limits = {};
      limits.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
      SetInformationJobObject(job_, JobObjectExtendedLimitInformation, &limits, sizeof(limits));
      if (!AssignProcessToJobObject(job_, process.hProcess)) { CloseHandle(job_); job_ = nullptr; }
    }
    process_ = process.hProcess;
    ResumeThread(process.hThread); CloseHandle(process.hThread);
    status = "starting";
  }
  void Poll() {
    if (!process_) return;
    DWORD available = 0;
    while (pipe_ && PeekNamedPipe(pipe_, nullptr, 0, nullptr, &available, nullptr) && available) {
      char chunk[16384]; DWORD read = 0;
      if (!ReadFile(pipe_, chunk, std::min<DWORD>(available, sizeof(chunk)), &read, nullptr) || !read) break;
      pending_.append(chunk, read);
      size_t newline = 0;
      while ((newline = pending_.find('\n')) != std::string::npos) {
        const auto line = pending_.substr(0, newline);
        pending_.erase(0, newline + 1);
        frames_.AddCsv(line, Seconds());
        if (line.find("Application,") == 0) status = "capturing";
        if (line.find("denied") != std::string::npos || line.find("administrator") != std::string::npos ||
            line.find("error=5") != std::string::npos) status = "permissionDenied";
      }
      if (pending_.size() > 65536) pending_.clear();
    }
    if (WaitForSingleObject(process_, 0) == WAIT_OBJECT_0 && status != "permissionDenied") status = "captureFailed";
  }
  std::optional<double> Fps() const { return status == "capturing" ? frames_.Fps(Seconds()) : std::nullopt; }
  void Stop() {
    if (process_) {
      if (WaitForSingleObject(process_, 0) == WAIT_TIMEOUT) {
        STARTUPINFOW startup = {}; startup.cb = sizeof(startup);
        PROCESS_INFORMATION stop = {};
        std::wstring command = L"\"" + executable_ + L"\" --terminate_existing_session --session_name " + session_;
        if (CreateProcessW(executable_.c_str(), command.data(), nullptr, nullptr, FALSE, CREATE_NO_WINDOW,
                           nullptr, nullptr, &startup, &stop)) {
          WaitForSingleObject(stop.hProcess, 1000);
          if (WaitForSingleObject(stop.hProcess, 0) == WAIT_TIMEOUT) TerminateProcess(stop.hProcess, 0);
          CloseHandle(stop.hThread); CloseHandle(stop.hProcess);
        }
        if (WaitForSingleObject(process_, 500) == WAIT_TIMEOUT) TerminateProcess(process_, 0);
      }
      CloseHandle(process_); process_ = nullptr;
    }
    if (job_) { CloseHandle(job_); job_ = nullptr; }
    if (pipe_) { CloseHandle(pipe_); pipe_ = nullptr; }
    frames_.Reset(); pending_.clear();
  }
  std::string status = "selectProcess";
 private:
  std::wstring executable_, session_;
  HANDLE process_ = nullptr, pipe_ = nullptr, job_ = nullptr;
  std::string pending_;
  FrameRateWindow frames_;
};
}  

SystemPerformanceMonitor::~SystemPerformanceMonitor() {
  Shutdown();
}
void SystemPerformanceMonitor::Shutdown() {
  { std::lock_guard<std::mutex> lock(mutex_); stopping_ = true; }
  wake_.notify_one();
  if (worker_.joinable()) worker_.join();
}
void SystemPerformanceMonitor::Configure(bool enabled, const std::string& executable) {
  std::lock_guard<std::mutex> lock(mutex_);
  if (stopping_) return;
  if (enabled_ == enabled && executable_ == executable) return;
  enabled_ = enabled; executable_ = executable; ++revision_;
  snapshot_ = {};
  snapshot_.revision = revision_;
  snapshot_.fps_status = executable.empty() ? "selectProcess" : "starting";
  if (!worker_.joinable() && enabled) worker_ = std::thread(&SystemPerformanceMonitor::Run, this);
  wake_.notify_one();
}
PerformanceSnapshot SystemPerformanceMonitor::Sample() {
  std::lock_guard<std::mutex> lock(mutex_);
  return snapshot_;
}
std::vector<MonitorProcess> SystemPerformanceMonitor::Processes() {
  const auto windows = Windows();
  std::map<std::wstring, MonitorProcess> grouped;
  HANDLE snapshot = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
  if (snapshot == INVALID_HANDLE_VALUE) return {};
  PROCESSENTRY32W entry = {}; entry.dwSize = sizeof(entry);
  if (Process32FirstW(snapshot, &entry)) do {
    if (entry.th32ProcessID == GetCurrentProcessId()) continue;
    const auto window = windows.find(entry.th32ProcessID);
    if (window == windows.end()) continue;
    const auto key = Lower(entry.szExeFile);
    grouped.emplace(key, MonitorProcess{Utf8(entry.szExeFile), Utf8(window->second)});
  } while (Process32NextW(snapshot, &entry));
  CloseHandle(snapshot);
  std::vector<MonitorProcess> processes;
  for (const auto& grouped_process : grouped) {
    processes.push_back(grouped_process.second);
  }
  return processes;
}
void SystemPerformanceMonitor::Run() {
  while (true) {
    std::string executable;
    uint64_t revision;
    {
      std::unique_lock<std::mutex> lock(mutex_);
      wake_.wait(lock, [this] { return stopping_ || enabled_; });
      if (stopping_) return;
      executable = executable_; revision = revision_;
    }
    GpuCounter gpu;
    FrameCapture capture;
    DWORD target = 0;
    double next_lookup = 0, next_sample = 0;
    while (true) {
      {
        std::lock_guard<std::mutex> lock(mutex_);
        if (stopping_ || !enabled_ || revision != revision_) break;
      }
      const double now = Seconds();
      if (!executable.empty() && now >= next_lookup) {
        next_lookup = now + 2;
        const auto found = FindProcess(Wide(executable));
        if (found != target) {
          target = found;
          if (target) capture.Start(target);
          else { capture.Stop(); capture.status = "waitingProcess"; }
        } else if (!target) capture.status = "waitingProcess";
      }
      capture.Poll();
      if (now >= next_sample) {
        next_sample = now + 0.5;
        FILETIME idle = {}, kernel = {}, user = {};
        MEMORYSTATUSEX memory = {}; memory.dwLength = sizeof(memory);
        PerformanceSnapshot next;
        if (GetSystemTimes(&idle, &kernel, &user) && GlobalMemoryStatusEx(&memory)) {
          next.idle_ticks = Ticks(idle); next.kernel_ticks = Ticks(kernel); next.user_ticks = Ticks(user);
          next.total_memory_bytes = static_cast<int64_t>(memory.ullTotalPhys);
          next.available_memory_bytes = static_cast<int64_t>(memory.ullAvailPhys);
        }
        next.gpu_percent = gpu.Read(); next.frames_per_second = capture.Fps();
        next.fps_status = capture.status; next.process_id = target; next.revision = revision;
        std::lock_guard<std::mutex> lock(mutex_);
        if (revision == revision_) snapshot_ = std::move(next);
      }
      std::unique_lock<std::mutex> lock(mutex_);
      wake_.wait_for(lock, std::chrono::milliseconds(target ? 50 : 500),
        [this, revision] { return stopping_ || !enabled_ || revision != revision_; });
    }
  }
}

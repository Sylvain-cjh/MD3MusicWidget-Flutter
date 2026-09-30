#ifndef RUNNER_SYSTEM_PERFORMANCE_MONITOR_H_
#define RUNNER_SYSTEM_PERFORMANCE_MONITOR_H_

#include <windows.h>
#include <condition_variable>
#include <cstdint>
#include <mutex>
#include <optional>
#include <string>
#include <thread>
#include <vector>

struct MonitorProcess {
  std::string executable;
  std::string title;
};

struct PerformanceSnapshot {
  int64_t idle_ticks = 0;
  int64_t kernel_ticks = 0;
  int64_t user_ticks = 0;
  int64_t total_memory_bytes = 0;
  int64_t available_memory_bytes = 0;
  std::optional<double> gpu_percent;
  std::optional<double> frames_per_second;
  std::string fps_status = "selectProcess";
  uint32_t process_id = 0;
  uint64_t revision = 0;
};

class SystemPerformanceMonitor {
 public:
  SystemPerformanceMonitor() = default;
  ~SystemPerformanceMonitor();
  void Shutdown();
  void Configure(bool enabled, const std::string& executable);
  PerformanceSnapshot Sample();
  static std::vector<MonitorProcess> Processes();

 private:
  void Run();
  std::mutex mutex_;
  std::condition_variable wake_;
  std::thread worker_;
  bool enabled_ = false;
  bool stopping_ = false;
  std::string executable_;
  uint64_t revision_ = 0;
  PerformanceSnapshot snapshot_;
};
#endif

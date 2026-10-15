#ifndef RUNNER_SYSTEM_FONTS_H_
#define RUNNER_SYSTEM_FONTS_H_
#include <string>
#include <vector>
#include <functional>
#include <mutex>
#include <thread>


std::vector<std::string> SystemFontFamilies();

class SystemFontCatalog {
 public:
  ~SystemFontCatalog();
  bool Refresh(std::function<void()> completed);
  std::vector<std::string> Snapshot(bool* ready) const;
  void Wait();
 private:
  mutable std::mutex mutex_;
  std::thread worker_;
  bool ready_ = false;
  std::vector<std::string> families_;
};
#endif

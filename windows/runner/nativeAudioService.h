#pragma once
#include <cstdint>
#include <memory>
#include <string>
#include <vector>
struct NativeAudioReading {
  std::vector<uint8_t> packet;
  std::string status;
  uint64_t frames = 0;
  uint32_t process_id = 0;
  uint32_t lookup_open_attempts = 0;
};
class NativeAudioService {
public:
  NativeAudioService();
  ~NativeAudioService();
  void Demand(bool enabled);
  void Target(const std::wstring &source, bool playing, bool strict);
  void Retry();
  NativeAudioReading Reading();

private:
  struct State;
  std::shared_ptr<State> state_;
  static void Run(std::shared_ptr<State> state);
};

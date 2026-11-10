#pragma once
#include <memory>
#include <optional>
#include <string>

struct NeteaseUiaSample {
  std::wstring title, artist;
  int positionSeconds = 0, durationSeconds = 0;
  long long updatedAtMs = 0;
  std::optional<bool> playing;
};



class NativeNeteaseUia {
public:
  NativeNeteaseUia();
  ~NativeNeteaseUia();
  std::optional<NeteaseUiaSample> Read(const std::wstring &selected);

private:
  struct State;
  static void Work(std::shared_ptr<State> state);
  std::shared_ptr<State> state_;
};

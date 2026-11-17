#pragma once

#include <windows.h>
#include <memory>
#include <string>
#include <vector>

struct AudioOutputEndpoint {
  std::wstring id;
  std::wstring name;
  
  std::wstring bluetooth_group;
};

struct AudioOutputSnapshot {
  bool available = false;
  std::wstring multimedia;
  std::wstring console;
  std::vector<AudioOutputEndpoint> endpoints;
};



class AudioOutputDevices {
public:
  static constexpr UINT kChanged = WM_APP + 87;
  AudioOutputDevices();
  ~AudioOutputDevices();
  bool Watch(HWND target);
  void AcknowledgeChange();
  AudioOutputSnapshot Snapshot();
  bool Select(const std::wstring &id);
  bool CanSelect();

private:
  struct State;
  std::unique_ptr<State> state_;
};

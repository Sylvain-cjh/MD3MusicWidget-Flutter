#include "audioOutputDevices.h"

#include <atomic>
#include <cwchar>
#include <cwctype>
#include <mmdeviceapi.h>
#include <propsys.h>
#include <utility>
#include <wrl/implements.h>
#include <cfgmgr32.h>
#include <initguid.h>
#include <devpkey.h>
#include <functiondiscoverykeys_devpkey.h>

namespace {
using Microsoft::WRL::ComPtr;

class PropValue {
public:
  PROPVARIANT value{};
  ~PropValue() { PropVariantClear(&value); }
  std::wstring String() const {
    return value.vt == VT_LPWSTR && value.pwszVal ? value.pwszVal : L"";
  }
};

std::wstring EndpointId(IMMDevice *device) {
  LPWSTR raw = nullptr;
  if (!device || FAILED(device->GetId(&raw))) return {};
  const std::wstring id = raw ? raw : L"";
  CoTaskMemFree(raw);
  return id;
}

std::wstring DefaultId(IMMDeviceEnumerator *devices, ERole role) {
  ComPtr<IMMDevice> endpoint;
  return SUCCEEDED(devices->GetDefaultAudioEndpoint(eRender, role, &endpoint))
             ? EndpointId(endpoint.Get()) : L"";
}

bool IsBluetoothInstance(std::wstring id) {
  const auto end = id.find(L'\\');
  if (end == std::wstring::npos) return false;
  id.resize(end);
  for (auto &ch : id) ch = static_cast<wchar_t>(std::towupper(ch));
  return id == L"BTHENUM" || id == L"BTHHFENUM" || id == L"BTHLEDEVICE" ||
         id == L"BTHLE" || id == L"BTHA2DP" || id == L"BTHHFPAUDIO" ||
         id == L"BTHLEAUDIO";
}

std::wstring BluetoothGroup(const std::wstring &instance,
                            const std::wstring &endpointId) {
  if (instance.empty()) return {};
  auto path = instance;
  DEVINST node = 0;
  bool bluetooth = IsBluetoothInstance(instance);
  GUID container{};
  if (CM_Locate_DevNodeW(&node, path.data(), CM_LOCATE_DEVNODE_NORMAL) ==
      CR_SUCCESS) {
    for (int depth = 0; depth < 10; ++depth) {
      wchar_t id[MAX_DEVICE_ID_LEN]{};
      const bool bluetoothNode =
          CM_Get_Device_IDW(node, id, MAX_DEVICE_ID_LEN, 0) == CR_SUCCESS &&
          IsBluetoothInstance(id);
      if (bluetoothNode) {
        bluetooth = true;
        DEVPROPTYPE type = 0;
        ULONG size = sizeof(container);
        if (CM_Get_DevNode_PropertyW(
                node, &DEVPKEY_Device_ContainerId, &type,
                reinterpret_cast<PBYTE>(&container), &size, 0) == CR_SUCCESS &&
            type == DEVPROP_TYPE_GUID && !IsEqualGUID(container, GUID{})) {
          break;
        }
        container = GUID{};
      }
      DEVINST parent = 0;
      if (CM_Get_Parent(&parent, node, 0) != CR_SUCCESS) break;
      node = parent;
    }
  }
  if (!bluetooth) return {};
  wchar_t group[40]{};
  return !IsEqualGUID(container, GUID{}) &&
                 StringFromGUID2(container, group, 40) > 0
             ? std::wstring(group) : endpointId;
}

struct DeviceSignal {
  std::atomic<HWND> window{nullptr};
  std::atomic<bool> pending{false};
};

class EndpointNotifications final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          Microsoft::WRL::FtmBase, IMMNotificationClient> {
public:
  std::shared_ptr<DeviceSignal> signal;
  STDMETHODIMP OnDefaultDeviceChanged(EDataFlow flow, ERole role,
                                      LPCWSTR) override {
    if (flow == eRender && role != eCommunications) Post();
    return S_OK;
  }
  STDMETHODIMP OnDeviceAdded(LPCWSTR) override { Post(); return S_OK; }
  STDMETHODIMP OnDeviceRemoved(LPCWSTR) override { Post(); return S_OK; }
  STDMETHODIMP OnDeviceStateChanged(LPCWSTR, DWORD) override {
    Post(); return S_OK;
  }
  STDMETHODIMP OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY key) override {
    if (IsEqualPropertyKey(key, PKEY_Device_FriendlyName) ||
        IsEqualPropertyKey(key, PKEY_Device_InstanceId)) Post();
    return S_OK;
  }

private:
  void Post() {
    const auto window = signal->window.load();
    if (window && !signal->pending.exchange(true) &&
        !PostMessageW(window, AudioOutputDevices::kChanged, 0, 0)) {
      signal->pending = false;
    }
  }
};




MIDL_INTERFACE("f8679f50-850a-41cf-9c72-430f290290c8")
  PlaybackPolicy : IUnknown {
  virtual HRESULT STDMETHODCALLTYPE GetMixFormat(PCWSTR, void **) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetDeviceFormat(PCWSTR, INT, void **) = 0;
  virtual HRESULT STDMETHODCALLTYPE ResetDeviceFormat(PCWSTR) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetDeviceFormat(PCWSTR, void *, void *) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetProcessingPeriod(PCWSTR, INT, void *, void *) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetProcessingPeriod(PCWSTR, void *) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetShareMode(PCWSTR, void *) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetShareMode(PCWSTR, void *) = 0;
  virtual HRESULT STDMETHODCALLTYPE GetPropertyValue(PCWSTR, INT, const PROPERTYKEY &, PROPVARIANT *) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetPropertyValue(PCWSTR, INT, const PROPERTYKEY &, PROPVARIANT *) = 0;
  virtual HRESULT STDMETHODCALLTYPE SetDefaultEndpoint(PCWSTR, ERole) = 0;
};

struct __declspec(uuid("870af99c-171d-4f9e-af0d-e63df40c2bc9"))
    PlaybackPolicyClient;

ComPtr<PlaybackPolicy> CreatePolicy() {
  ComPtr<PlaybackPolicy> result;
  CoCreateInstance(__uuidof(PlaybackPolicyClient), nullptr, CLSCTX_INPROC_SERVER,
                   IID_PPV_ARGS(&result));
  return result;
}
}  

struct AudioOutputDevices::State {
  ComPtr<IMMDeviceEnumerator> devices;
  ComPtr<EndpointNotifications> callback;
  std::shared_ptr<DeviceSignal> signal = std::make_shared<DeviceSignal>();
  bool EnsureEnumerator() {
    return devices || SUCCEEDED(CoCreateInstance(
        __uuidof(MMDeviceEnumerator), nullptr, CLSCTX_INPROC_SERVER,
        IID_PPV_ARGS(&devices)));
  }
};

AudioOutputDevices::AudioOutputDevices() : state_(std::make_unique<State>()) {}
AudioOutputDevices::~AudioOutputDevices() {
  state_->signal->window = nullptr;
  if (state_->devices && state_->callback)
    state_->devices->UnregisterEndpointNotificationCallback(state_->callback.Get());
}

bool AudioOutputDevices::Watch(HWND target) {
  if (state_->callback) return true;
  if (!target || !state_->EnsureEnumerator()) return false;
  auto callback = Microsoft::WRL::Make<EndpointNotifications>();
  if (!callback) return false;
  callback->signal = state_->signal;
  state_->signal->window = target;
  if (FAILED(state_->devices->RegisterEndpointNotificationCallback(callback.Get()))) {
    state_->signal->window = nullptr;
    return false;
  }
  state_->callback = std::move(callback);
  return true;
}

void AudioOutputDevices::AcknowledgeChange() { state_->signal->pending = false; }

AudioOutputSnapshot AudioOutputDevices::Snapshot() {
  AudioOutputSnapshot result;
  if (!state_->EnsureEnumerator()) return result;
  ComPtr<IMMDeviceCollection> active;
  if (FAILED(state_->devices->EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE,
                                                 &active))) return result;
  UINT count = 0;
  if (FAILED(active->GetCount(&count))) return result;
  result.available = true;
  result.multimedia = DefaultId(state_->devices.Get(), eMultimedia);
  result.console = DefaultId(state_->devices.Get(), eConsole);
  for (UINT i = 0; i < count; ++i) {
    ComPtr<IMMDevice> endpoint;
    if (FAILED(active->Item(i, &endpoint))) continue;
    auto id = EndpointId(endpoint.Get());
    if (id.empty()) continue;
    ComPtr<IPropertyStore> store;
    PropValue name, instance;
    if (SUCCEEDED(endpoint->OpenPropertyStore(STGM_READ, &store))) {
      store->GetValue(PKEY_Device_FriendlyName, &name.value);
      store->GetValue(PKEY_Device_InstanceId, &instance.value);
    }
    auto group = BluetoothGroup(instance.String(), id);
    result.endpoints.push_back({std::move(id), name.String(), std::move(group)});
  }
  return result;
}

bool AudioOutputDevices::CanSelect() { return CreatePolicy() != nullptr; }

bool AudioOutputDevices::Select(const std::wstring &id) {
  if (id.empty() || id.size() > 512 || !state_->EnsureEnumerator()) return false;
  ComPtr<IMMDevice> endpoint;
  ComPtr<IMMEndpoint> output;
  DWORD status = 0;
  EDataFlow flow = eAll;
  if (FAILED(state_->devices->GetDevice(id.c_str(), &endpoint)) ||
      FAILED(endpoint->GetState(&status)) || status != DEVICE_STATE_ACTIVE ||
      FAILED(endpoint.As(&output)) || FAILED(output->GetDataFlow(&flow)) ||
      flow != eRender) return false;
  const auto policy = CreatePolicy();
  if (!policy) return false;
  for (const auto role : {eMultimedia, eConsole}) {
    if (DefaultId(state_->devices.Get(), role) == id) continue;
    if (FAILED(policy->SetDefaultEndpoint(id.c_str(), role))) return false;
  }
  return DefaultId(state_->devices.Get(), eMultimedia) == id &&
         DefaultId(state_->devices.Get(), eConsole) == id;
}

#include "nativeAudioService.h"

#include <windows.h>

#include "nativeSpectrumDsp.h"
#include "nativeSourceIdentity.h"
#include <appmodel.h>
#include <atomic>
#include <audioclient.h>
#include <audioclientactivationparams.h>
#include <chrono>
#include <condition_variable>
#include <ksmedia.h>
#include <limits>
#include <mmdeviceapi.h>
#include <mutex>
#include <thread>
#include <tlhelp32.h>
#include <windows.h>
#include <winrt/base.h>
#include <wrl.h>

namespace {
using Microsoft::WRL::ComPtr;
void Check(HRESULT result) {
  if (FAILED(result))
    throw winrt::hresult_error(result);
}
int64_t Now() {
  return std::chrono::duration_cast<std::chrono::milliseconds>(
             std::chrono::system_clock::now().time_since_epoch())
      .count();
}
struct Handle {
  HANDLE value = nullptr;
  ~Handle() {
    if (value && value != INVALID_HANDLE_VALUE)
      CloseHandle(value);
  }
};
struct Format {
  WAVEFORMATEX *value = nullptr;
  ~Format() { CoTaskMemFree(value); }
};
uint32_t FindProcess(const std::wstring &source, Handle &retained,
                     uint32_t &opened) {
  if (source.empty())
    return 0;
  Handle snapshot{CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0)};
  if (snapshot.value == INVALID_HANDLE_VALUE)
    return 0;
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  uint32_t best = 0;
  uint64_t oldest = std::numeric_limits<uint64_t>::max();
  const auto split = source.find_last_of(L"\\/");
  const auto name = source.substr(split == std::wstring::npos ? 0 : split + 1);
  
  
  for (int pass = 0; pass < 2 && best == 0; ++pass) {
    for (BOOL more = Process32FirstW(snapshot.value, &entry); more;
         more = Process32NextW(snapshot.value, &entry)) {
      if (pass == 0 && !NativeSourceMatchesExecutable(name, entry.szExeFile))
        continue;
      ++opened;
      Handle process{
          OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION | SYNCHRONIZE, FALSE,
                      entry.th32ProcessID)};
      if (!process.value)
        continue;
      bool matches =
          pass == 0 && NativeSourceMatchesExecutable(source, entry.szExeFile);
      if (pass == 0 && !matches &&
          (source.find(L'\\') != std::wstring::npos ||
           source.find(L'/') != std::wstring::npos)) {
        wchar_t image[32768];
        DWORD length = static_cast<DWORD>(std::size(image));
        if (QueryFullProcessImageNameW(process.value, 0, image, &length))
          matches = NativeSourceMatchesExecutable(source,
                                                  std::wstring(image, length));
      }
      if (pass == 1) {
        UINT32 size = 0;
        GetApplicationUserModelId(process.value, &size, nullptr);
        if (size > 0 && size < 4096) {
          std::wstring id(size, L'\0');
          if (GetApplicationUserModelId(process.value, &size, id.data()) ==
              ERROR_SUCCESS)
            matches = _wcsicmp(id.c_str(), source.c_str()) == 0;
        }
      }
      if (!matches)
        continue;
      FILETIME creation{}, exit{}, kernel{}, user{};
      if (GetProcessTimes(process.value, &creation, &exit, &kernel, &user)) {
        uint64_t time = (static_cast<uint64_t>(creation.dwHighDateTime) << 32) |
                        creation.dwLowDateTime;
        if (time < oldest) {
          oldest = time;
          best = entry.th32ProcessID;
          if (retained.value)
            CloseHandle(retained.value);
          retained.value = process.value;
          process.value = nullptr;
        }
      }
    }
  }
  return best;
}
class Activation final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          Microsoft::WRL::FtmBase, IActivateAudioInterfaceCompletionHandler> {
public:
  Handle ready{CreateEventW(nullptr, TRUE, FALSE, nullptr)};
  HRESULT status = E_PENDING;
  ComPtr<IAudioClient> client;
  AUDIOCLIENT_ACTIVATION_PARAMS params{};
  PROPVARIANT variant{};
  STDMETHODIMP
  ActivateCompleted(IActivateAudioInterfaceAsyncOperation *operation) override {
    ComPtr<IUnknown> object;
    HRESULT activation = E_FAIL;
    status = operation->GetActivateResult(&activation, &object);
    if (SUCCEEDED(status))
      status = activation;
    if (SUCCEEDED(status))
      status = object.As(&client);
    SetEvent(ready.value);
    return S_OK;
  }
};
class Notifications final
    : public Microsoft::WRL::RuntimeClass<
          Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>,
          Microsoft::WRL::FtmBase, IMMNotificationClient> {
public:
  std::shared_ptr<std::atomic<uint64_t>> revision;
  void Changed() { ++*revision; }
  STDMETHODIMP OnDefaultDeviceChanged(EDataFlow flow, ERole, LPCWSTR) override {
    if (flow == eRender)
      Changed();
    return S_OK;
  }
  STDMETHODIMP OnDeviceAdded(LPCWSTR) override {
    Changed();
    return S_OK;
  }
  STDMETHODIMP OnDeviceRemoved(LPCWSTR) override {
    Changed();
    return S_OK;
  }
  STDMETHODIMP OnDeviceStateChanged(LPCWSTR, DWORD) override {
    Changed();
    return S_OK;
  }
  STDMETHODIMP OnPropertyValueChanged(LPCWSTR, const PROPERTYKEY key) override {
    
    
    
    
    
    static constexpr PROPERTYKEY deviceFormat = {
        {0xf19f064d,
         0x082c,
         0x4e27,
         {0xbc, 0x73, 0x68, 0x82, 0xa1, 0xbb, 0x8e, 0x4c}},
        0};
    if (IsEqualPropertyKey(key, deviceFormat))
      Changed();
    return S_OK;
  }
};
float Sample(const BYTE *bytes, int count, bool floating) {
  if (floating && count == 4) {
    float v;
    memcpy(&v, bytes, 4);
    return std::isfinite(v) ? v : 0;
  }
  if (floating && count == 8) {
    double v;
    memcpy(&v, bytes, 8);
    return std::isfinite(v) ? static_cast<float>(v) : 0;
  }
  if (count == 1)
    return (bytes[0] - 128) / 128.0f;
  if (count == 2) {
    int16_t v;
    memcpy(&v, bytes, 2);
    return v / 32768.0f;
  }
  if (count == 3) {
    int32_t v = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16);
    if (v & 0x800000)
      v |= static_cast<int32_t>(0xff000000);
    return v / 8388608.0f;
  }
  if (count == 4) {
    int32_t v;
    memcpy(&v, bytes, 4);
    return v / 2147483648.0f;
  }
  return 0;
}
} 
struct NativeAudioService::State {
  std::atomic<bool> stop{false};
  std::mutex mutex;
  std::condition_variable wake;
  bool enabled = false, playing = false, strict = false, started = false;
  uint64_t revision = 0;
  std::wstring source;
  NativeAudioReading reading;
};
NativeAudioService::NativeAudioService() : state_(std::make_shared<State>()) {}
NativeAudioService::~NativeAudioService() {
  state_->stop = true;
  state_->wake.notify_all();
}
void NativeAudioService::Demand(bool enabled) {
  std::lock_guard lock(state_->mutex);
  if (state_->enabled != enabled) {
    state_->enabled = enabled;
    ++state_->revision;
    state_->reading = {};
  }
  if (enabled && !state_->started) {
    try {
      std::thread(Run, state_).detach();
      state_->started = true;
    } catch (...) {
      state_->reading.status = "audio_worker_unavailable";
    }
  }
  state_->wake.notify_one();
}
void NativeAudioService::Target(const std::wstring &source, bool playing,
                                bool strict) {
  std::lock_guard lock(state_->mutex);
  if (state_->source != source || state_->playing != playing ||
      state_->strict != strict) {
    state_->source = source;
    state_->playing = playing;
    state_->strict = strict;
    ++state_->revision;
    state_->reading = {};
  }
  state_->wake.notify_one();
}
NativeAudioReading NativeAudioService::Reading() {
  std::lock_guard lock(state_->mutex);
  auto r = state_->reading;
  if (r.packet.empty()) {
    r.packet.resize(140, 0);
    r.packet[0] = 1;
    r.packet[2] = 32;
  }
  return r;
}
void NativeAudioService::Retry() {
  std::lock_guard lock(state_->mutex);
  ++state_->revision;
  state_->reading = {};
  state_->wake.notify_one();
}
void NativeAudioService::Run(std::shared_ptr<State> state) {
  bool initialized = false;
  try {
    winrt::init_apartment(winrt::apartment_type::multi_threaded);
    initialized = true;
  } catch (...) {
    std::lock_guard lock(state->mutex);
    state->reading.status = "audio_com_unavailable";
    state->started = false;
    return;
  }
  auto devices = std::make_shared<std::atomic<uint64_t>>(0);
  ComPtr<IMMDeviceEnumerator> enumerator;
  auto notifications = Microsoft::WRL::Make<Notifications>();
  notifications->revision = devices;
  if (SUCCEEDED(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                 CLSCTX_ALL, IID_PPV_ARGS(&enumerator))))
    enumerator->RegisterEndpointNotificationCallback(notifications.Get());
  int failures = 0;
  uint64_t previousRevision = ~uint64_t{0};
  while (!state->stop) {
    uint64_t revision;
    bool enabled, playing, strict;
    std::wstring source;
    {
      std::unique_lock lock(state->mutex);
      state->wake.wait(lock, [&] {
        return state->stop || (state->enabled && state->playing);
      });
      if (state->stop)
        break;
      revision = state->revision;
      enabled = state->enabled;
      playing = state->playing;
      strict = state->strict;
      source = state->source;
    }
    if (!enabled || !playing) {
      std::this_thread::sleep_for(std::chrono::milliseconds(40));
      continue;
    }
    if (revision != previousRevision) {
      failures = 0;
      previousRevision = revision;
    }
    ComPtr<IAudioClient> client;
    ComPtr<IAudioCaptureClient> capture;
    Handle target;
    uint32_t opened = 0;
    uint32_t pid = FindProcess(source, target, opened);
    uint64_t deviceRevision = devices->load();
    try {
      bool processMode = false;
      WAVEFORMATEX processFormat{};
      processFormat.wFormatTag = WAVE_FORMAT_PCM;
      processFormat.nChannels = 2;
      processFormat.nSamplesPerSec = 48000;
      processFormat.wBitsPerSample = 16;
      processFormat.nBlockAlign = 4;
      processFormat.nAvgBytesPerSec = 192000;
      if (pid) {
        auto activation = Microsoft::WRL::Make<Activation>();
        activation->params.ActivationType =
            AUDIOCLIENT_ACTIVATION_TYPE_PROCESS_LOOPBACK;
        activation->params.ProcessLoopbackParams.TargetProcessId = pid;
        activation->params.ProcessLoopbackParams.ProcessLoopbackMode =
            PROCESS_LOOPBACK_MODE_INCLUDE_TARGET_PROCESS_TREE;
        activation->variant.vt = VT_BLOB;
        activation->variant.blob.cbSize = sizeof(activation->params);
        activation->variant.blob.pBlobData =
            reinterpret_cast<BYTE *>(&activation->params);
        ComPtr<IActivateAudioInterfaceAsyncOperation> operation;
        HRESULT result = ActivateAudioInterfaceAsync(
            VIRTUAL_AUDIO_DEVICE_PROCESS_LOOPBACK, __uuidof(IAudioClient),
            &activation->variant, activation.Get(), &operation);
        if (SUCCEEDED(result)) {
          const auto deadline = GetTickCount64() + 2500;
          while (!state->stop &&
                 WaitForSingleObject(activation->ready.value, 20) ==
                     WAIT_TIMEOUT &&
                 GetTickCount64() < deadline) {
          }
          if (WaitForSingleObject(activation->ready.value, 0) ==
                  WAIT_OBJECT_0 &&
              SUCCEEDED(activation->status)) {
            client = activation->client;
            processMode = true;
          }
        }
      }
      if (state->stop)
        break;
      if (strict && !processMode)
        throw winrt::hresult_error(
            HRESULT_FROM_WIN32(ERROR_NOT_SUPPORTED),
            L"Strict source process capture unavailable");
      Format mix;
      WAVEFORMATEX *format = &processFormat;
      if (!processMode) {
        if (!enumerator)
          Check(CoCreateInstance(__uuidof(MMDeviceEnumerator), nullptr,
                                 CLSCTX_ALL, IID_PPV_ARGS(&enumerator)));
        ComPtr<IMMDevice> device;
        Check(
            enumerator->GetDefaultAudioEndpoint(eRender, eMultimedia, &device));
        Check(
            device->Activate(__uuidof(IAudioClient), CLSCTX_ALL, nullptr,
                             reinterpret_cast<void **>(client.GetAddressOf())));
        Check(client->GetMixFormat(&mix.value));
        format = mix.value;
        pid = 0;
      }
      bool floating = format->wFormatTag == WAVE_FORMAT_IEEE_FLOAT;
      if (format->wFormatTag == WAVE_FORMAT_EXTENSIBLE && format->cbSize >= 22)
        floating =
            reinterpret_cast<WAVEFORMATEXTENSIBLE *>(format)->SubFormat ==
            KSDATAFORMAT_SUBTYPE_IEEE_FLOAT;
      if (!format->nChannels || !format->nSamplesPerSec ||
          format->wBitsPerSample % 8 || format->wBitsPerSample < 8 ||
          format->wBitsPerSample > 64)
        throw winrt::hresult_error(AUDCLNT_E_UNSUPPORTED_FORMAT);
      const int channels = format->nChannels,
                bytes = format->wBitsPerSample / 8, block = format->nBlockAlign;
      if (block < channels * bytes)
        throw winrt::hresult_error(AUDCLNT_E_UNSUPPORTED_FORMAT);
      Handle event{CreateEventW(nullptr, FALSE, FALSE, nullptr)};
      if (!event.value)
        throw winrt::hresult_error(E_OUTOFMEMORY);
      Check(client->Initialize(
          AUDCLNT_SHAREMODE_SHARED,
          AUDCLNT_STREAMFLAGS_LOOPBACK | AUDCLNT_STREAMFLAGS_EVENTCALLBACK |
              (processMode ? AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM : 0),
          processMode ? 0 : 1000000, 0, format, nullptr));
      Check(client->SetEventHandle(event.value));
      Check(client->GetService(IID_PPV_ARGS(&capture)));
      Check(client->Start());
      NativeSpectrumDsp dsp(format->nSamplesPerSec);
      uint64_t frames = 0;
      int64_t lastPublished = 0;
      const auto started = GetTickCount64();
      std::vector<float> mono;
      mono.reserve(16384);
      while (!state->stop) {
        {
          std::lock_guard lock(state->mutex);
          if (state->revision != revision)
            break;
        }
        if (devices->load() != deviceRevision)
          break;
        if (target.value &&
            WaitForSingleObject(target.value, 0) == WAIT_OBJECT_0)
          break;
        WaitForSingleObject(event.value, 40);
        if (GetTickCount64() - started > 5000) {
          if (!frames)
            throw winrt::hresult_error(HRESULT_FROM_WIN32(ERROR_TIMEOUT));
          failures = 0;
        }
        UINT32 packet = 0;
        Check(capture->GetNextPacketSize(&packet));
        mono.clear();
        while (packet) {
          BYTE *data = nullptr;
          UINT32 count = 0;
          DWORD flags = 0;
          Check(capture->GetBuffer(&data, &count, &flags, nullptr, nullptr));
          const auto keep = std::min<UINT32>(count, 96000);
          try {
            if (mono.size() + keep > 96000)
              mono.clear();
            for (UINT32 f = count - keep; f < count; ++f) {
              float v = 0;
              if (!(flags & AUDCLNT_BUFFERFLAGS_SILENT) && data) {
                for (int c = 0; c < channels; ++c)
                  v += Sample(data + static_cast<size_t>(f) * block + c * bytes,
                              bytes, floating);
                v /= channels;
              }
              mono.push_back(v);
            }
          } catch (...) {
            capture->ReleaseBuffer(count);
            throw;
          }
          Check(capture->ReleaseBuffer(count));
          frames += count;
          Check(capture->GetNextPacketSize(&packet));
        }
        const auto now = Now();
        const bool changed = dsp.Push(mono.data(), mono.size(), now);
        
        
        
        const bool publish =
            changed || lastPublished == 0 || now - lastPublished >= 33;
        auto packetBytes =
            publish ? dsp.Packet(true, now) : std::vector<uint8_t>{};
        {
          std::lock_guard lock(state->mutex);
          if (state->revision == revision) {
            auto &reading = state->reading;
            if (publish) {
              reading.packet = std::move(packetBytes);
              lastPublished = now;
            }
            reading.status = processMode ? "process" : "system";
            reading.frames = frames;
            reading.process_id = pid;
            reading.lookup_open_attempts = opened;
          }
        }
      }
      client->Stop();
    } catch (const winrt::hresult_error &error) {
      if (client)
        client->Stop();
      {
        std::lock_guard lock(state->mutex);
        if (state->revision == revision) {
          state->reading = {};
          state->reading.status =
              (strict ? "strict_capture_unavailable:" : "audio_retry:") +
              std::to_string(error.code().value);
        }
      }
      const int waits = std::min(1500, 25 * (1 << std::min(failures++, 6)));
      for (int i = 0; i < waits && !state->stop; ++i) {
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
        std::lock_guard lock(state->mutex);
        if (state->revision != revision || devices->load() != deviceRevision)
          break;
      }
    } catch (...) {
      if (client)
        client->Stop();
      {
        std::lock_guard lock(state->mutex);
        state->reading.status = "audio_capture_retry";
      }
      for (int i = 0; i < 50 && !state->stop; ++i)
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
    }
  }
  if (enumerator)
    enumerator->UnregisterEndpointNotificationCallback(notifications.Get());
  enumerator.Reset();
  notifications.Reset();
  if (initialized)
    winrt::uninit_apartment();
}

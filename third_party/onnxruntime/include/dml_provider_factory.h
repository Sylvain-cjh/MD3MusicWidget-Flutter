


#pragma once

#pragma warning(push)
#pragma warning(disable : 4201)  
#ifdef _GAMING_XBOX_SCARLETT
#include <d3d12_xs.h>
#elif defined(_GAMING_XBOX_XBOXONE)
#include <d3d12_x.h>
#else
#include <d3d12.h>
#endif
#pragma warning(pop)

#ifdef __cplusplus
#include <DirectML.h>
#else
struct IDMLDevice;
typedef struct IDMLDevice IDMLDevice;
#endif


#undef OPTIONAL

#include "onnxruntime_c_api.h"

#ifdef __cplusplus

extern "C" {

enum OrtDmlDeviceFilter : uint32_t {
#ifdef ENABLE_NPU_ADAPTER_ENUMERATION
  Any = 0xffffffff,
  Gpu = 1 << 0,
  Npu = 1 << 1,
#else
  Gpu = 1 << 0,
#endif
};

inline OrtDmlDeviceFilter operator~(OrtDmlDeviceFilter a) { return (OrtDmlDeviceFilter) ~(int)a; }
inline OrtDmlDeviceFilter operator|(OrtDmlDeviceFilter a, OrtDmlDeviceFilter b) { return (OrtDmlDeviceFilter)((int)a | (int)b); }
inline OrtDmlDeviceFilter operator&(OrtDmlDeviceFilter a, OrtDmlDeviceFilter b) { return (OrtDmlDeviceFilter)((int)a & (int)b); }
inline OrtDmlDeviceFilter operator^(OrtDmlDeviceFilter a, OrtDmlDeviceFilter b) { return (OrtDmlDeviceFilter)((int)a ^ (int)b); }
inline OrtDmlDeviceFilter& operator|=(OrtDmlDeviceFilter& a, OrtDmlDeviceFilter b) { return (OrtDmlDeviceFilter&)((int&)a |= (int)b); }
inline OrtDmlDeviceFilter& operator&=(OrtDmlDeviceFilter& a, OrtDmlDeviceFilter b) { return (OrtDmlDeviceFilter&)((int&)a &= (int)b); }
inline OrtDmlDeviceFilter& operator^=(OrtDmlDeviceFilter& a, OrtDmlDeviceFilter b) { return (OrtDmlDeviceFilter&)((int&)a ^= (int)b); }

#else

typedef enum OrtDmlDeviceFilter {
#ifdef ENABLE_NPU_ADAPTER_ENUMERATION
  Any = 0xffffffff,
  Gpu = 1 << 0,
  Npu = 1 << 1,
#else
  Gpu = 1 << 0,
#endif
} OrtDmlDeviceFilter;

#endif

typedef enum OrtDmlPerformancePreference {
  Default = 0,
  HighPerformance = 1,
  MinimumPower = 2
} OrtDmlPerformancePreference;

struct OrtDmlDeviceOptions {
  OrtDmlPerformancePreference Preference;
  OrtDmlDeviceFilter Filter;
};

typedef struct OrtDmlDeviceOptions OrtDmlDeviceOptions;

 









ORT_API_STATUS(OrtSessionOptionsAppendExecutionProvider_DML, _In_ OrtSessionOptions* options, int device_id);

 












ORT_API_STATUS(OrtSessionOptionsAppendExecutionProviderEx_DML, _In_ OrtSessionOptions* options,
               _In_ IDMLDevice* dml_device, _In_ ID3D12CommandQueue* cmd_queue);

struct OrtDmlApi;
typedef struct OrtDmlApi OrtDmlApi;

struct OrtDmlApi {
   





  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_DML, _In_ OrtSessionOptions* options, int device_id);

   








  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_DML1, _In_ OrtSessionOptions* options,
                  _In_ IDMLDevice* dml_device, _In_ ID3D12CommandQueue* cmd_queue);

   



  ORT_API2_STATUS(CreateGPUAllocationFromD3DResource, _In_ ID3D12Resource* d3d_resource, _Out_ void** dml_resource);

   



  ORT_API2_STATUS(FreeGPUAllocation, _In_ void* dml_resource);

   



  ORT_API2_STATUS(GetD3D12ResourceFromAllocation, _In_ OrtAllocator* provider, _In_ void* dml_resource, _Out_ ID3D12Resource** d3d_resource);

   




  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_DML2, _In_ OrtSessionOptions* options, OrtDmlDeviceOptions* device_opts);
};

#ifdef __cplusplus
}
#endif






#ifdef __cplusplus
extern "C" {
#endif

ORT_RUNTIME_CLASS(Ep);
ORT_RUNTIME_CLASS(EpFactory);
ORT_RUNTIME_CLASS(EpGraphSupportInfo);
ORT_RUNTIME_CLASS(MemoryDevice);  
ORT_RUNTIME_CLASS(NodeComputeContext);

ORT_RUNTIME_CLASS(DataTransferImpl);
ORT_RUNTIME_CLASS(SyncNotificationImpl);
ORT_RUNTIME_CLASS(SyncStreamImpl);


struct OrtDataTransferImpl {
  uint32_t ort_version_supported;  

   








  ORT_API_T(void, Release, _In_ OrtDataTransferImpl* this_ptr);

   








  ORT_API_T(bool, CanCopy, _In_ const OrtDataTransferImpl* this_ptr,
            _In_ const OrtMemoryDevice* src_memory_device, _In_ const OrtMemoryDevice* dst_memory_device);

   















  ORT_API2_STATUS(CopyTensors, _In_ OrtDataTransferImpl* this_ptr,
                  _In_reads_(num_tensors) const OrtValue** src_tensors,
                  _In_reads_(num_tensors) OrtValue** dst_tensors,
                  _In_reads_(num_tensors) OrtSyncStream** streams,
                  _In_ size_t num_tensors);
};

 



struct OrtSyncNotificationImpl {
  uint32_t ort_version_supported;  

   








  ORT_API_T(void, Release, _In_ OrtSyncNotificationImpl* this_ptr);

   





  ORT_API2_STATUS(Activate, _In_ OrtSyncNotificationImpl* this_ptr);

   






  ORT_API2_STATUS(WaitOnDevice, _In_ OrtSyncNotificationImpl* this_ptr, _In_ OrtSyncStream* consumer_stream);

   





  ORT_API2_STATUS(WaitOnHost, _In_ OrtSyncNotificationImpl* this_ptr);
};

 





struct OrtSyncStreamImpl {
  uint32_t ort_version_supported;  

   








  ORT_API_T(void, Release, _In_ OrtSyncStreamImpl* this_ptr);

   








  ORT_API_T(void*, GetHandle, _In_ OrtSyncStreamImpl* this_ptr);

   






  ORT_API2_STATUS(CreateNotification, _In_ OrtSyncStreamImpl* this_ptr,
                  _Outptr_ OrtSyncNotificationImpl** notification);

   







  ORT_API2_STATUS(Flush, _In_ OrtSyncStreamImpl* this_ptr);

   








  ORT_API2_STATUS(OnSessionRunEnd, _In_ OrtSyncStreamImpl* this_ptr);
};

struct OrtNodeFusionOptions;
typedef struct OrtNodeFusionOptions OrtNodeFusionOptions;

struct OrtNodeComputeInfo;
typedef struct OrtNodeComputeInfo OrtNodeComputeInfo;

 






struct OrtNodeFusionOptions {
   






  uint32_t ort_version_supported;

   









  bool drop_constant_initializers;

  
};

 




struct OrtNodeComputeInfo {
   






  uint32_t ort_version_supported;

   











  OrtStatus*(ORT_API_CALL* CreateState)(_In_ OrtNodeComputeInfo* this_ptr,
                                        _In_ OrtNodeComputeContext* compute_context,
                                        _Outptr_ void** compute_state);

   








  OrtStatus*(ORT_API_CALL* Compute)(_In_ OrtNodeComputeInfo* this_ptr, _In_ void* compute_state,
                                    _In_ OrtKernelContext* kernel_context);

   





  void(ORT_API_CALL* ReleaseState)(_In_ OrtNodeComputeInfo* this_ptr, _Frees_ptr_opt_ void* compute_state);
};

struct OrtEpApi {
   












  ORT_API2_STATUS(CreateEpDevice, _In_ OrtEpFactory* ep_factory,
                  _In_ const OrtHardwareDevice* hardware_device,
                  _In_opt_ const OrtKeyValuePairs* ep_metadata,
                  _In_opt_ const OrtKeyValuePairs* ep_options,
                  _Out_ OrtEpDevice** ep_device);

  ORT_CLASS_RELEASE(EpDevice);

   
















  ORT_API2_STATUS(EpGraphSupportInfo_AddNodesToFuse, _In_ OrtEpGraphSupportInfo* graph_support_info,
                  _In_reads_(num_nodes) const OrtNode* const* nodes, _In_ size_t num_nodes,
                  _In_opt_ const OrtNodeFusionOptions* node_fusion_options);

   








  ORT_API2_STATUS(EpGraphSupportInfo_AddSingleNode, _In_ OrtEpGraphSupportInfo* graph_support_info,
                  _In_ const OrtNode* node);

   










  ORT_API_T(const char*, NodeComputeContext_NodeName, _In_ const OrtNodeComputeContext* context);

   





















  ORT_API2_STATUS(EpDevice_AddAllocatorInfo, _In_ OrtEpDevice* ep_device,
                  _In_ const OrtMemoryInfo* allocator_memory_info);

   









  ORT_API_T(const OrtMemoryDevice*, MemoryInfo_GetMemoryDevice, _In_ const OrtMemoryInfo* memory_info);

   






  ORT_API_T(const OrtMemoryDevice*, Value_GetMemoryDevice, _In_ const OrtValue* value);

   










  ORT_API_T(bool, MemoryDevice_AreEqual, _In_ const OrtMemoryDevice* a, _In_ const OrtMemoryDevice* b);

   






  ORT_API_T(OrtMemoryInfoDeviceType, MemoryDevice_GetDeviceType, _In_ const OrtMemoryDevice* memory_device);

   






  ORT_API_T(OrtDeviceMemoryType, MemoryDevice_GetMemoryType, _In_ const OrtMemoryDevice* memory_device);

   










  ORT_API_T(uint32_t, MemoryDevice_GetVendorId, _In_ const OrtMemoryDevice* memory_device);

   






  ORT_API_T(uint32_t, MemoryDevice_GetDeviceId, _In_ const OrtMemoryDevice* memory_device);

   










  ORT_API_T(const OrtSyncStreamImpl*, SyncStream_GetImpl, _In_ const OrtSyncStream* stream);

   






  ORT_API_T(uint64_t, SyncStream_GetSyncId, _In_ const OrtSyncStream* stream);

   









  ORT_API_T(uint64_t, GetSyncIdForLastWaitOnSyncStream,
            _In_ const OrtSyncStream* producer_stream, _In_ const OrtSyncStream* consumer_stream);
};

 







typedef enum OrtEpDataLayout {
  OrtEpDataLayout_NCHW = 0,
  OrtEpDataLayout_NHWC,

  OrtEpDataLayout_Default = OrtEpDataLayout_NCHW,
} OrtEpDataLayout;

 



struct OrtEp {
   






  uint32_t ort_version_supported;

   








  ORT_API_T(const char*, GetName, _In_ const OrtEp* this_ptr);

   















  ORT_API2_STATUS(GetCapability, _In_ OrtEp* this_ptr, _In_ const OrtGraph* graph,
                  _Inout_ OrtEpGraphSupportInfo* graph_support_info);

   




































  ORT_API2_STATUS(Compile, _In_ OrtEp* this_ptr, _In_ const OrtGraph** graphs,
                  _In_ const OrtNode** fused_nodes, _In_ size_t count,
                  _Out_writes_all_(count) OrtNodeComputeInfo** node_compute_infos,
                  _Out_writes_(count) OrtNode** ep_context_nodes);

   







  ORT_API_T(void, ReleaseNodeComputeInfos, _In_ OrtEp* this_ptr,
            OrtNodeComputeInfo** node_compute_infos,
            _In_ size_t num_node_compute_infos);

   











  ORT_API2_STATUS(GetPreferredDataLayout, _In_ OrtEp* this_ptr, _Out_ OrtEpDataLayout* preferred_data_layout);

   





















  ORT_API2_STATUS(ShouldConvertDataLayoutForOp, _In_ OrtEp* this_ptr,
                  _In_z_ const char* domain, _In_z_ const char* op_type,
                  _In_ OrtEpDataLayout target_data_layout,
                  _Outptr_ int* should_convert);

   















  ORT_API2_STATUS(SetDynamicOptions, _In_ OrtEp* this_ptr,
                  _In_reads_(num_options) const char* const* option_keys,
                  _In_reads_(num_options) const char* const* option_values,
                  _In_ size_t num_options);

   










  ORT_API2_STATUS(OnRunStart, _In_ OrtEp* this_ptr, _In_ const OrtRunOptions* run_options);

   












  ORT_API2_STATUS(OnRunEnd, _In_ OrtEp* this_ptr, _In_ const OrtRunOptions* run_options, _In_ bool sync_stream);

   














  ORT_API2_STATUS(CreateAllocator, _In_ OrtEp* this_ptr,
                  _In_ const OrtMemoryInfo* memory_info,
                  _Outptr_result_maybenull_ OrtAllocator** allocator);

   















  ORT_API2_STATUS(CreateSyncStreamForDevice, _In_ OrtEp* this_ptr,
                  _In_ const OrtMemoryDevice* memory_device,
                  _Outptr_ OrtSyncStreamImpl** stream);

   














  ORT_API_T(const char*, GetCompiledModelCompatibilityInfo, _In_ OrtEp* this_ptr,
            _In_ const OrtGraph* graph);
};

 


















typedef OrtStatus* (*CreateEpApiFactoriesFn)(_In_ const char* registered_name, _In_ const OrtApiBase* ort_api_base,
                                             _In_ const OrtLogger* default_logger,
                                             _Inout_ OrtEpFactory** factories, _In_ size_t max_factories,
                                             _Out_ size_t* num_factories);

 









typedef OrtStatus* (*ReleaseEpApiFactoryFn)(_In_ OrtEpFactory* factory);

 



struct OrtEpFactory {
   






  uint32_t ort_version_supported;

   








  ORT_API_T(const char*, GetName, const OrtEpFactory* this_ptr);

   








  ORT_API_T(const char*, GetVendor, const OrtEpFactory* this_ptr);  

   
















  ORT_API2_STATUS(GetSupportedDevices, _In_ OrtEpFactory* this_ptr,
                  _In_reads_(num_devices) const OrtHardwareDevice* const* devices,
                  _In_ size_t num_devices,
                  _Inout_ OrtEpDevice** ep_devices,
                  _In_ size_t max_ep_devices,
                  _Out_ size_t* num_ep_devices);

   























  ORT_API2_STATUS(CreateEp, _In_ OrtEpFactory* this_ptr,
                  _In_reads_(num_devices) const OrtHardwareDevice* const* devices,
                  _In_reads_(num_devices) const OrtKeyValuePairs* const* ep_metadata_pairs,
                  _In_ size_t num_devices,
                  _In_ const OrtSessionOptions* session_options,
                  _In_ const OrtLogger* logger, _Outptr_ OrtEp** ep);

   






  ORT_API_T(void, ReleaseEp, OrtEpFactory* this_ptr, struct OrtEp* ep);

   








  ORT_API_T(uint32_t, GetVendorId, const OrtEpFactory* this_ptr);

   











  ORT_API_T(const char*, GetVersion, _In_ const OrtEpFactory* this_ptr);

   


















  ORT_API2_STATUS(ValidateCompiledModelCompatibilityInfo, _In_ OrtEpFactory* this_ptr,
                  _In_reads_(num_devices) const OrtHardwareDevice* const* devices,
                  _In_ size_t num_devices,
                  _In_ const char* compatibility_info,
                  _Out_ OrtCompiledModelCompatibility* model_compatibility);

   













  ORT_API2_STATUS(CreateAllocator, _In_ OrtEpFactory* this_ptr,
                  _In_ const OrtMemoryInfo* memory_info,
                  _In_opt_ const OrtKeyValuePairs* allocator_options,
                  _Outptr_result_maybenull_ OrtAllocator** allocator);

   



  ORT_API_T(void, ReleaseAllocator, _In_ OrtEpFactory* this_ptr, _In_ OrtAllocator* allocator);

   











  ORT_API2_STATUS(CreateDataTransfer, _In_ OrtEpFactory* this_ptr,
                  _Outptr_result_maybenull_ OrtDataTransferImpl** data_transfer);

   






  ORT_API_T(bool, IsStreamAware, _In_ const OrtEpFactory* this_ptr);

   













  ORT_API2_STATUS(CreateSyncStreamForDevice, _In_ OrtEpFactory* this_ptr,
                  _In_ const OrtMemoryDevice* memory_device,
                  _In_opt_ const OrtKeyValuePairs* stream_options,
                  _Outptr_ OrtSyncStreamImpl** stream);
};

#ifdef __cplusplus
}
#endif

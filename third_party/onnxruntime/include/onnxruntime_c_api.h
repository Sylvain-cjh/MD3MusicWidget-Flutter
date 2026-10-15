




 
























#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

 



#define ORT_API_VERSION 23

#ifdef __cplusplus
extern "C" {
#endif



#ifndef _MSC_VER
#define _In_
#define _In_z_
#define _In_opt_
#define _In_opt_z_
#define _Out_
#define _Out_opt_
#define _Outptr_
#define _Outptr_opt_
#define _Inout_
#define _Inout_opt_
#define _Frees_ptr_opt_
#define _Ret_maybenull_
#define _Ret_notnull_
#define _Check_return_
#define _Outptr_result_maybenull_
#define _Outptr_result_maybenull_z_
#define _In_reads_(X)
#define _In_reads_opt_
#define _Inout_updates_(X)
#define _Out_writes_(X)
#define _Out_writes_opt_(X)
#define _Inout_updates_all_(X)
#define _Out_writes_bytes_all_(X)
#define _Out_writes_all_(X)
#define _Success_(X)
#define _Outptr_result_buffer_maybenull_(X)
#define ORT_ALL_ARGS_NONNULL __attribute__((nonnull))
#else
#include <specstrings.h>
#define ORT_ALL_ARGS_NONNULL
#endif

#ifdef _WIN32


#ifdef ORT_DLL_IMPORT
#define ORT_EXPORT __declspec(dllimport)
#else
#define ORT_EXPORT
#endif
#define ORT_API_CALL _stdcall
#define ORT_MUST_USE_RESULT
#define ORTCHAR_T wchar_t
#else

#ifdef __APPLE__
#define ORT_EXPORT __attribute__((visibility("default")))
#else
#define ORT_EXPORT
#endif
#define ORT_API_CALL
#define ORT_MUST_USE_RESULT __attribute__((warn_unused_result))
#define ORTCHAR_T char
#endif



#ifndef ORT_TSTR
#ifdef _WIN32
#define ORT_TSTR(X) L##X

#define ORT_TSTR_ON_MACRO(X) L"" X
#else
#define ORT_TSTR(X) X
#define ORT_TSTR_ON_MACRO(X) X
#endif
#endif



#ifndef ORT_FILE
#define ORT_FILE_INTERNAL(x) ORT_TSTR(x)
#define ORT_FILE ORT_FILE_INTERNAL(__FILE__)
#endif







#ifdef __cplusplus


#ifndef __has_feature
#define __has_feature(x) 0
#endif
#if ((__cplusplus >= 201103L) || (_MSC_VER >= 1900) || (defined(__has_feature) && __has_feature(cxx_noexcept)))
#define NO_EXCEPTION noexcept
#else
#define NO_EXCEPTION throw()
#endif
#else
#define NO_EXCEPTION
#endif


#define ORT_API(RETURN_TYPE, NAME, ...) RETURN_TYPE ORT_API_CALL NAME(__VA_ARGS__) NO_EXCEPTION

#define ORT_API_T(RETURN_TYPE, NAME, ...) \
  RETURN_TYPE(ORT_API_CALL* NAME)(__VA_ARGS__) NO_EXCEPTION

#define ORT_API_STATUS(NAME, ...)                                                                   \
  _Success_(return == 0) _Check_return_ _Ret_maybenull_ OrtStatusPtr ORT_API_CALL NAME(__VA_ARGS__) \
  NO_EXCEPTION ORT_MUST_USE_RESULT


#define ORT_API2_STATUS(NAME, ...) \
  _Check_return_ _Ret_maybenull_ OrtStatusPtr(ORT_API_CALL* NAME)(__VA_ARGS__) NO_EXCEPTION ORT_MUST_USE_RESULT


#define ORT_API_STATUS_IMPL(NAME, ...) \
  _Success_(return == 0) _Check_return_ _Ret_maybenull_ OrtStatusPtr ORT_API_CALL NAME(__VA_ARGS__) NO_EXCEPTION

#define ORT_CLASS_RELEASE(X) void(ORT_API_CALL * Release##X)(_Frees_ptr_opt_ Ort##X * input)

#ifdef __DOXYGEN__
#undef ORT_API_STATUS
#define ORT_API_STATUS(NAME, ...) OrtStatus* NAME(__VA_ARGS__)
#undef ORT_API2_STATUS
#define ORT_API2_STATUS(NAME, ...) OrtStatus* NAME(__VA_ARGS__)
#undef ORT_CLASS_RELEASE
#define ORT_CLASS_RELEASE(X) void Release##X(Ort##X* input)
#undef NO_EXCEPTION
#define NO_EXCEPTION
#endif
 




 


typedef enum ONNXTensorElementDataType {
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UNDEFINED,
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,   
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT8,   
  ONNX_TENSOR_ELEMENT_DATA_TYPE_INT8,    
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT16,  
  ONNX_TENSOR_ELEMENT_DATA_TYPE_INT16,   
  ONNX_TENSOR_ELEMENT_DATA_TYPE_INT32,   
  ONNX_TENSOR_ELEMENT_DATA_TYPE_INT64,   
  ONNX_TENSOR_ELEMENT_DATA_TYPE_STRING,  
  ONNX_TENSOR_ELEMENT_DATA_TYPE_BOOL,
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT16,
  ONNX_TENSOR_ELEMENT_DATA_TYPE_DOUBLE,      
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT32,      
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT64,      
  ONNX_TENSOR_ELEMENT_DATA_TYPE_COMPLEX64,   
  ONNX_TENSOR_ELEMENT_DATA_TYPE_COMPLEX128,  
  ONNX_TENSOR_ELEMENT_DATA_TYPE_BFLOAT16,    
  
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT8E4M3FN,    
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT8E4M3FNUZ,  
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT8E5M2,      
  ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT8E5M2FNUZ,  
  
  ONNX_TENSOR_ELEMENT_DATA_TYPE_UINT4,  
  ONNX_TENSOR_ELEMENT_DATA_TYPE_INT4    
} ONNXTensorElementDataType;


typedef enum ONNXType {
  ONNX_TYPE_UNKNOWN,
  ONNX_TYPE_TENSOR,
  ONNX_TYPE_SEQUENCE,
  ONNX_TYPE_MAP,
  ONNX_TYPE_OPAQUE,
  ONNX_TYPE_SPARSETENSOR,
  ONNX_TYPE_OPTIONAL
} ONNXType;



typedef enum OrtSparseFormat {
  ORT_SPARSE_UNDEFINED = 0,
  ORT_SPARSE_COO = 0x1,
  ORT_SPARSE_CSRC = 0x2,
  ORT_SPARSE_BLOCK_SPARSE = 0x4
} OrtSparseFormat;


enum OrtSparseIndicesFormat {
  ORT_SPARSE_COO_INDICES,
  ORT_SPARSE_CSR_INNER_INDICES,
  ORT_SPARSE_CSR_OUTER_INDICES,
  ORT_SPARSE_BLOCK_SPARSE_INDICES
};

 



typedef enum OrtLoggingLevel {
  ORT_LOGGING_LEVEL_VERBOSE,  
  ORT_LOGGING_LEVEL_INFO,     
  ORT_LOGGING_LEVEL_WARNING,  
  ORT_LOGGING_LEVEL_ERROR,    
  ORT_LOGGING_LEVEL_FATAL,    
} OrtLoggingLevel;

typedef enum OrtErrorCode {
  ORT_OK,
  ORT_FAIL,
  ORT_INVALID_ARGUMENT,
  ORT_NO_SUCHFILE,
  ORT_NO_MODEL,
  ORT_ENGINE_ERROR,
  ORT_RUNTIME_EXCEPTION,
  ORT_INVALID_PROTOBUF,
  ORT_MODEL_LOADED,
  ORT_NOT_IMPLEMENTED,
  ORT_INVALID_GRAPH,
  ORT_EP_FAIL,
  ORT_MODEL_LOAD_CANCELED,
  ORT_MODEL_REQUIRES_COMPILATION,
  ORT_NOT_FOUND,
} OrtErrorCode;

typedef enum OrtOpAttrType {
  ORT_OP_ATTR_UNDEFINED = 0,
  ORT_OP_ATTR_INT,
  ORT_OP_ATTR_INTS,
  ORT_OP_ATTR_FLOAT,
  ORT_OP_ATTR_FLOATS,
  ORT_OP_ATTR_STRING,
  ORT_OP_ATTR_STRINGS,
  ORT_OP_ATTR_GRAPH,
  ORT_OP_ATTR_TENSOR,
} OrtOpAttrType;


#define ORT_RUNTIME_CLASS(X) \
  struct Ort##X;             \
  typedef struct Ort##X Ort##X

 




ORT_RUNTIME_CLASS(Env);
ORT_RUNTIME_CLASS(Status);  
ORT_RUNTIME_CLASS(MemoryInfo);
ORT_RUNTIME_CLASS(IoBinding);
ORT_RUNTIME_CLASS(Session);  
ORT_RUNTIME_CLASS(Value);
ORT_RUNTIME_CLASS(RunOptions);
ORT_RUNTIME_CLASS(TypeInfo);
ORT_RUNTIME_CLASS(TensorTypeAndShapeInfo);
ORT_RUNTIME_CLASS(MapTypeInfo);
ORT_RUNTIME_CLASS(SequenceTypeInfo);
ORT_RUNTIME_CLASS(OptionalTypeInfo);
ORT_RUNTIME_CLASS(SessionOptions);
ORT_RUNTIME_CLASS(CustomOpDomain);
ORT_RUNTIME_CLASS(ModelMetadata);
ORT_RUNTIME_CLASS(ThreadPoolParams);
ORT_RUNTIME_CLASS(ThreadingOptions);
ORT_RUNTIME_CLASS(ArenaCfg);
ORT_RUNTIME_CLASS(PrepackedWeightsContainer);
ORT_RUNTIME_CLASS(TensorRTProviderOptionsV2);
ORT_RUNTIME_CLASS(NvTensorRtRtxProviderOptions);
ORT_RUNTIME_CLASS(CUDAProviderOptionsV2);
ORT_RUNTIME_CLASS(CANNProviderOptions);
ORT_RUNTIME_CLASS(DnnlProviderOptions);
ORT_RUNTIME_CLASS(Op);
ORT_RUNTIME_CLASS(OpAttr);
ORT_RUNTIME_CLASS(Logger);
ORT_RUNTIME_CLASS(ShapeInferContext);
ORT_RUNTIME_CLASS(LoraAdapter);
ORT_RUNTIME_CLASS(ValueInfo);
ORT_RUNTIME_CLASS(Node);
ORT_RUNTIME_CLASS(Graph);
ORT_RUNTIME_CLASS(Model);
ORT_RUNTIME_CLASS(ModelCompilationOptions);
ORT_RUNTIME_CLASS(HardwareDevice);
ORT_RUNTIME_CLASS(EpDevice);
ORT_RUNTIME_CLASS(KeyValuePairs);
ORT_RUNTIME_CLASS(SyncStream);  
ORT_RUNTIME_CLASS(ExternalInitializerInfo);

#ifdef _MSC_VER
typedef _Return_type_success_(return == 0) OrtStatus* OrtStatusPtr;
#else
typedef OrtStatus* OrtStatusPtr;
#endif

 





typedef struct OrtAllocator {
  uint32_t version;  

  
  void*(ORT_API_CALL* Alloc)(struct OrtAllocator* this_, size_t size);

  
  void(ORT_API_CALL* Free)(struct OrtAllocator* this_, void* p);

  
  const struct OrtMemoryInfo*(ORT_API_CALL* Info)(const struct OrtAllocator* this_);
   









  void*(ORT_API_CALL* Reserve)(struct OrtAllocator* this_, size_t size);

   
























  ORT_API2_STATUS(GetStats, _In_ const struct OrtAllocator* this_, _Outptr_ OrtKeyValuePairs** out);

   














  void*(ORT_API_CALL* AllocOnStream)(struct OrtAllocator* this_, size_t size, OrtSyncStream* stream);
} OrtAllocator;

typedef void(ORT_API_CALL* OrtLoggingFunction)(
    void* param, OrtLoggingLevel severity, const char* category, const char* logid, const char* code_location,
    const char* message);

 




typedef enum GraphOptimizationLevel {
  ORT_DISABLE_ALL = 0,
  ORT_ENABLE_BASIC = 1,
  ORT_ENABLE_EXTENDED = 2,
  ORT_ENABLE_LAYOUT = 3,
  ORT_ENABLE_ALL = 99
} GraphOptimizationLevel;

typedef enum ExecutionMode {
  ORT_SEQUENTIAL = 0,
  ORT_PARALLEL = 1,
} ExecutionMode;

 


typedef enum OrtLanguageProjection {
  ORT_PROJECTION_C = 0,
  ORT_PROJECTION_CPLUSPLUS = 1,
  ORT_PROJECTION_CSHARP = 2,
  ORT_PROJECTION_PYTHON = 3,
  ORT_PROJECTION_JAVA = 4,
  ORT_PROJECTION_WINML = 5,
  ORT_PROJECTION_NODEJS = 6,
} OrtLanguageProjection;

struct OrtKernelInfo;
typedef struct OrtKernelInfo OrtKernelInfo;
struct OrtKernelContext;
typedef struct OrtKernelContext OrtKernelContext;
struct OrtCustomOp;
typedef struct OrtCustomOp OrtCustomOp;

typedef enum OrtAllocatorType {
  OrtInvalidAllocator = -1,
  OrtDeviceAllocator = 0,
  OrtArenaAllocator = 1,
  OrtReadOnlyAllocator = 2,
} OrtAllocatorType;

 


typedef enum OrtMemType {
  
  OrtMemTypeCPUInput = -2,
  
  OrtMemTypeCPUOutput = -1,
  
  OrtMemTypeCPU = OrtMemTypeCPUOutput,
  
  OrtMemTypeDefault = 0,
} OrtMemType;

 
typedef enum OrtDeviceMemoryType {
  OrtDeviceMemoryType_DEFAULT = 0,          
  OrtDeviceMemoryType_HOST_ACCESSIBLE = 5,  
} OrtDeviceMemoryType;

 

typedef enum OrtMemoryInfoDeviceType {
  OrtMemoryInfoDeviceType_CPU = 0,
  OrtMemoryInfoDeviceType_GPU = 1,
  OrtMemoryInfoDeviceType_FPGA = 2,
  OrtMemoryInfoDeviceType_NPU = 3,
} OrtMemoryInfoDeviceType;

typedef enum OrtHardwareDeviceType {
  OrtHardwareDeviceType_CPU,
  OrtHardwareDeviceType_GPU,
  OrtHardwareDeviceType_NPU
} OrtHardwareDeviceType;

 

typedef enum OrtExecutionProviderDevicePolicy {
  OrtExecutionProviderDevicePolicy_DEFAULT,
  OrtExecutionProviderDevicePolicy_PREFER_CPU,
  OrtExecutionProviderDevicePolicy_PREFER_NPU,
  OrtExecutionProviderDevicePolicy_PREFER_GPU,
  OrtExecutionProviderDevicePolicy_MAX_PERFORMANCE,
  OrtExecutionProviderDevicePolicy_MAX_EFFICIENCY,
  OrtExecutionProviderDevicePolicy_MIN_OVERALL_POWER,
} OrtExecutionProviderDevicePolicy;

 


















typedef OrtStatus*(ORT_API_CALL* EpSelectionDelegate)(_In_ const OrtEpDevice** ep_devices,
                                                      _In_ size_t num_devices,
                                                      _In_ const OrtKeyValuePairs* model_metadata,
                                                      _In_opt_ const OrtKeyValuePairs* runtime_metadata,
                                                      _Inout_ const OrtEpDevice** selected,
                                                      _In_ size_t max_selected,
                                                      _Out_ size_t* num_selected,
                                                      _In_ void* state);

 









typedef OrtStatus*(ORT_API_CALL* OrtWriteBufferFunc)(_In_ void* state,
                                                     _In_ const void* buffer,
                                                     _In_ size_t buffer_num_bytes);

 





























typedef OrtStatus*(ORT_API_CALL* OrtGetInitializerLocationFunc)(
    _In_ void* state,
    _In_ const char* initializer_name,
    _In_ const OrtValue* initializer_value,
    _In_opt_ const OrtExternalInitializerInfo* external_info,
    _Outptr_result_maybenull_ OrtExternalInitializerInfo** new_external_info);

 

typedef enum OrtCudnnConvAlgoSearch {
  OrtCudnnConvAlgoSearchExhaustive,  
  OrtCudnnConvAlgoSearchHeuristic,   
  OrtCudnnConvAlgoSearchDefault,     
} OrtCudnnConvAlgoSearch;

 



typedef struct OrtCUDAProviderOptions {
#ifdef __cplusplus
  OrtCUDAProviderOptions()
      : device_id{},
        cudnn_conv_algo_search{OrtCudnnConvAlgoSearchExhaustive},
        gpu_mem_limit{SIZE_MAX},
        arena_extend_strategy{},
        do_copy_in_default_stream{1},
        has_user_compute_stream{},
        user_compute_stream{},
        default_memory_arena_cfg{},
        tunable_op_enable{false},
        tunable_op_tuning_enable{false},
        tunable_op_max_tuning_duration_ms{} {}
#endif

   


  int device_id;

   



  OrtCudnnConvAlgoSearch cudnn_conv_algo_search;

   



  size_t gpu_mem_limit;

   





  int arena_extend_strategy;

   






  int do_copy_in_default_stream;

   


  int has_user_compute_stream;

   


  void* user_compute_stream;

   

  OrtArenaCfg* default_memory_arena_cfg;

   



  int tunable_op_enable;

   



  int tunable_op_tuning_enable;

   


  int tunable_op_max_tuning_duration_ms;

} OrtCUDAProviderOptions;

 



typedef struct OrtROCMProviderOptions {
#ifdef __cplusplus
  OrtROCMProviderOptions()
      : device_id{},
        miopen_conv_exhaustive_search{0},
        gpu_mem_limit{SIZE_MAX},
        arena_extend_strategy{},
        do_copy_in_default_stream{1},
        has_user_compute_stream{},
        user_compute_stream{},
        default_memory_arena_cfg{},
        enable_hip_graph{false},
        tunable_op_enable{false},
        tunable_op_tuning_enable{false},
        tunable_op_max_tuning_duration_ms{} {}
#endif

   


  int device_id;

   


  int miopen_conv_exhaustive_search;

   



  size_t gpu_mem_limit;

   





  int arena_extend_strategy;

   






  int do_copy_in_default_stream;

   


  int has_user_compute_stream;

   


  void* user_compute_stream;

   

  OrtArenaCfg* default_memory_arena_cfg;

  int enable_hip_graph;

   



  int tunable_op_enable;

   



  int tunable_op_tuning_enable;

   


  int tunable_op_max_tuning_duration_ms;

} OrtROCMProviderOptions;

 



typedef struct OrtTensorRTProviderOptions {
  int device_id;                                
  int has_user_compute_stream;                  
  void* user_compute_stream;                    
  int trt_max_partition_iterations;             
  int trt_min_subgraph_size;                    
  size_t trt_max_workspace_size;                
  int trt_fp16_enable;                          
  int trt_int8_enable;                          
  const char* trt_int8_calibration_table_name;  
  int trt_int8_use_native_calibration_table;    
  int trt_dla_enable;                           
  int trt_dla_core;                             
  int trt_dump_subgraphs;                       
  int trt_engine_cache_enable;                  
  const char* trt_engine_cache_path;            
  int trt_engine_decryption_enable;             
  const char* trt_engine_decryption_lib_path;   
  int trt_force_sequential_engine_build;        
  
  
  
} OrtTensorRTProviderOptions;

 



typedef struct OrtMIGraphXProviderOptions {
  int device_id;                                     
  int migraphx_fp16_enable;                          
  int migraphx_fp8_enable;                           
  int migraphx_int8_enable;                          
  int migraphx_use_native_calibration_table;         
  const char* migraphx_int8_calibration_table_name;  
  int migraphx_save_compiled_model;                  
  const char* migraphx_save_model_path;              
  int migraphx_load_compiled_model;                  
  const char* migraphx_load_model_path;              
  bool migraphx_exhaustive_tune;                     

   



  size_t migraphx_mem_limit;

   





  int migraphx_arena_extend_strategy;

  
} OrtMIGraphXProviderOptions;

 








typedef struct OrtOpenVINOProviderOptions {
#ifdef __cplusplus
  OrtOpenVINOProviderOptions() : device_type{},
                                 enable_npu_fast_compile{},
                                 device_id{},
                                 num_of_threads{},
                                 cache_dir{},
                                 context{},
                                 enable_opencl_throttling{},
                                 enable_dynamic_shapes{} {}
#endif
   



  const char* device_type;
  unsigned char enable_npu_fast_compile;  
  const char* device_id;
  size_t num_of_threads;  
  const char* cache_dir;  
  void* context;
  unsigned char enable_opencl_throttling;  
  unsigned char enable_dynamic_shapes;     
} OrtOpenVINOProviderOptions;

struct OrtApi;
typedef struct OrtApi OrtApi;

struct OrtTrainingApi;
typedef struct OrtTrainingApi OrtTrainingApi;

struct OrtModelEditorApi;
typedef struct OrtModelEditorApi OrtModelEditorApi;

struct OrtCompileApi;
typedef struct OrtCompileApi OrtCompileApi;

struct OrtEpApi;
typedef struct OrtEpApi OrtEpApi;

 



struct OrtApiBase {
   








  const OrtApi*(ORT_API_CALL* GetApi)(uint32_t version)NO_EXCEPTION;

   



  const char*(ORT_API_CALL* GetVersionString)(void)NO_EXCEPTION;
};

typedef struct OrtApiBase OrtApiBase;

 



ORT_EXPORT const OrtApiBase* ORT_API_CALL OrtGetApiBase(void) NO_EXCEPTION;

 




typedef void (*OrtThreadWorkerFn)(void* ort_worker_fn_param);

typedef const struct OrtCustomHandleType {
  char __place_holder;
}* OrtCustomThreadHandle;

 




typedef OrtCustomThreadHandle (*OrtCustomCreateThreadFn)(void* ort_custom_thread_creation_options, OrtThreadWorkerFn ort_thread_worker_fn, void* ort_worker_fn_param);

 




typedef void (*OrtCustomJoinThreadFn)(OrtCustomThreadHandle ort_custom_thread_handle);

typedef OrtStatus*(ORT_API_CALL* RegisterCustomOpsFn)(OrtSessionOptions* options, const OrtApiBase* api);

 






typedef void (*RunAsyncCallbackFn)(void* user_data, OrtValue** outputs, size_t num_outputs, OrtStatusPtr status);

 






 


typedef enum OrtCompiledModelCompatibility {
  OrtCompiledModelCompatibility_EP_NOT_APPLICABLE = 0,
  OrtCompiledModelCompatibility_EP_SUPPORTED_OPTIMAL,
  OrtCompiledModelCompatibility_EP_SUPPORTED_PREFER_RECOMPILATION,
  OrtCompiledModelCompatibility_EP_UNSUPPORTED,
} OrtCompiledModelCompatibility;

struct OrtApi {
  
  

   






  OrtStatus*(ORT_API_CALL* CreateStatus)(OrtErrorCode code, _In_ const char* msg)NO_EXCEPTION ORT_ALL_ARGS_NONNULL;

   




  OrtErrorCode(ORT_API_CALL* GetErrorCode)(_In_ const OrtStatus* status) NO_EXCEPTION ORT_ALL_ARGS_NONNULL;

   




  const char*(ORT_API_CALL* GetErrorMessage)(_In_ const OrtStatus* status)NO_EXCEPTION ORT_ALL_ARGS_NONNULL;

  
  
  

   









  ORT_API2_STATUS(CreateEnv, OrtLoggingLevel log_severity_level, _In_ const char* logid, _Outptr_ OrtEnv** out);

   













  ORT_API2_STATUS(CreateEnvWithCustomLogger, _In_ OrtLoggingFunction logging_function, _In_opt_ void* logger_param,
                  _In_ OrtLoggingLevel log_severity_level, _In_ const char* logid, _Outptr_ OrtEnv** out);

   






  ORT_API2_STATUS(EnableTelemetryEvents, _In_ const OrtEnv* env);
   






  ORT_API2_STATUS(DisableTelemetryEvents, _In_ const OrtEnv* env);

  
  
  

   








  
  
  
  
  
  ORT_API2_STATUS(CreateSession, _In_ const OrtEnv* env, _In_ const ORTCHAR_T* model_path,
                  _In_ const OrtSessionOptions* options, _Outptr_ OrtSession** out);

   









  ORT_API2_STATUS(CreateSessionFromArray, _In_ const OrtEnv* env,
                  _In_ const void* model_data, size_t model_data_length,
                  _In_ const OrtSessionOptions* options, _Outptr_ OrtSession** out);

   

















  ORT_API2_STATUS(Run, _Inout_ OrtSession* session, _In_opt_ const OrtRunOptions* run_options,
                  _In_reads_(input_len) const char* const* input_names,
                  _In_reads_(input_len) const OrtValue* const* inputs, size_t input_len,
                  _In_reads_(output_names_len) const char* const* output_names, size_t output_names_len,
                  _Inout_updates_all_(output_names_len) OrtValue** outputs);

  
  
  

   














  ORT_API2_STATUS(CreateSessionOptions, _Outptr_ OrtSessionOptions** options);

   






  ORT_API2_STATUS(SetOptimizedModelFilePath, _Inout_ OrtSessionOptions* options,
                  _In_ const ORTCHAR_T* optimized_model_filepath);

   






  ORT_API2_STATUS(CloneSessionOptions, _In_ const OrtSessionOptions* in_options,
                  _Outptr_ OrtSessionOptions** out_options);

   










  ORT_API2_STATUS(SetSessionExecutionMode, _Inout_ OrtSessionOptions* options, ExecutionMode execution_mode);

   






  ORT_API2_STATUS(EnableProfiling, _Inout_ OrtSessionOptions* options, _In_ const ORTCHAR_T* profile_file_prefix);

   





  ORT_API2_STATUS(DisableProfiling, _Inout_ OrtSessionOptions* options);

   












  ORT_API2_STATUS(EnableMemPattern, _Inout_ OrtSessionOptions* options);

   







  ORT_API2_STATUS(DisableMemPattern, _Inout_ OrtSessionOptions* options);

   







  ORT_API2_STATUS(EnableCpuMemArena, _Inout_ OrtSessionOptions* options);

   





  ORT_API2_STATUS(DisableCpuMemArena, _Inout_ OrtSessionOptions* options);

   






  ORT_API2_STATUS(SetSessionLogId, _Inout_ OrtSessionOptions* options, const char* logid);

   








  ORT_API2_STATUS(SetSessionLogVerbosityLevel, _Inout_ OrtSessionOptions* options, int session_log_verbosity_level);

   






  ORT_API2_STATUS(SetSessionLogSeverityLevel, _Inout_ OrtSessionOptions* options, int session_log_severity_level);

   







  ORT_API2_STATUS(SetSessionGraphOptimizationLevel, _Inout_ OrtSessionOptions* options,
                  GraphOptimizationLevel graph_optimization_level);

   












  ORT_API2_STATUS(SetIntraOpNumThreads, _Inout_ OrtSessionOptions* options, int intra_op_num_threads);

   











  ORT_API2_STATUS(SetInterOpNumThreads, _Inout_ OrtSessionOptions* options, int inter_op_num_threads);

  
  
  

   






  ORT_API2_STATUS(CreateCustomOpDomain, _In_ const char* domain, _Outptr_ OrtCustomOpDomain** out);

   








  ORT_API2_STATUS(CustomOpDomain_Add, _Inout_ OrtCustomOpDomain* custom_op_domain, _In_ const OrtCustomOp* op);

  
  
  

   








  ORT_API2_STATUS(AddCustomOpDomain, _Inout_ OrtSessionOptions* options, _In_ OrtCustomOpDomain* custom_op_domain);

   















  ORT_API2_STATUS(RegisterCustomOpsLibrary, _Inout_ OrtSessionOptions* options, _In_ const char* library_path, _Outptr_ void** library_handle);

  
  
  

   










  ORT_API2_STATUS(SessionGetInputCount, _In_ const OrtSession* session, _Out_ size_t* out);

   










  ORT_API2_STATUS(SessionGetOutputCount, _In_ const OrtSession* session, _Out_ size_t* out);

   








  ORT_API2_STATUS(SessionGetOverridableInitializerCount, _In_ const OrtSession* session, _Out_ size_t* out);

   







  ORT_API2_STATUS(SessionGetInputTypeInfo, _In_ const OrtSession* session, size_t index, _Outptr_ OrtTypeInfo** type_info);

   







  ORT_API2_STATUS(SessionGetOutputTypeInfo, _In_ const OrtSession* session, size_t index, _Outptr_ OrtTypeInfo** type_info);

   







  ORT_API2_STATUS(SessionGetOverridableInitializerTypeInfo, _In_ const OrtSession* session, size_t index, _Outptr_ OrtTypeInfo** type_info);

   








  ORT_API2_STATUS(SessionGetInputName, _In_ const OrtSession* session, size_t index, _Inout_ OrtAllocator* allocator, _Outptr_ char** value);

   








  ORT_API2_STATUS(SessionGetOutputName, _In_ const OrtSession* session, size_t index, _Inout_ OrtAllocator* allocator, _Outptr_ char** value);

   








  ORT_API2_STATUS(SessionGetOverridableInitializerName, _In_ const OrtSession* session, size_t index,
                  _Inout_ OrtAllocator* allocator, _Outptr_ char** value);

  
  
  

   





  ORT_API2_STATUS(CreateRunOptions, _Outptr_ OrtRunOptions** out);

   








  ORT_API2_STATUS(RunOptionsSetRunLogVerbosityLevel, _Inout_ OrtRunOptions* options, int log_verbosity_level);

   






  ORT_API2_STATUS(RunOptionsSetRunLogSeverityLevel, _Inout_ OrtRunOptions* options, int log_severity_level);

   








  ORT_API2_STATUS(RunOptionsSetRunTag, _Inout_ OrtRunOptions* options, _In_ const char* run_tag);

   








  ORT_API2_STATUS(RunOptionsGetRunLogVerbosityLevel, _In_ const OrtRunOptions* options,
                  _Out_ int* log_verbosity_level);

   






  ORT_API2_STATUS(RunOptionsGetRunLogSeverityLevel, _In_ const OrtRunOptions* options, _Out_ int* log_severity_level);

   










  ORT_API2_STATUS(RunOptionsGetRunTag, _In_ const OrtRunOptions* options, _Out_ const char** run_tag);

   







  ORT_API2_STATUS(RunOptionsSetTerminate, _Inout_ OrtRunOptions* options);

   







  ORT_API2_STATUS(RunOptionsUnsetTerminate, _Inout_ OrtRunOptions* options);

  
  
  

   











  ORT_API2_STATUS(CreateTensorAsOrtValue, _Inout_ OrtAllocator* allocator, _In_ const int64_t* shape, size_t shape_len,
                  ONNXTensorElementDataType type, _Outptr_ OrtValue** out);

   
















  ORT_API2_STATUS(CreateTensorWithDataAsOrtValue, _In_ const OrtMemoryInfo* info, _Inout_ void* p_data,
                  size_t p_data_len, _In_ const int64_t* shape, size_t shape_len, ONNXTensorElementDataType type,
                  _Outptr_ OrtValue** out);

   






  ORT_API2_STATUS(IsTensor, _In_ const OrtValue* value, _Out_ int* out);

   









  ORT_API2_STATUS(GetTensorMutableData, _In_ OrtValue* value, _Outptr_ void** out);

   







  ORT_API2_STATUS(FillStringTensor, _Inout_ OrtValue* value, _In_ const char* const* s, size_t s_len);

   








  ORT_API2_STATUS(GetStringTensorDataLength, _In_ const OrtValue* value, _Out_ size_t* len);

   


















  ORT_API2_STATUS(GetStringTensorContent, _In_ const OrtValue* value, _Out_writes_bytes_all_(s_len) void* s,
                  size_t s_len, _Out_writes_all_(offsets_len) size_t* offsets, size_t offsets_len);

  
  
  

   







  ORT_API2_STATUS(CastTypeInfoToTensorInfo, _In_ const OrtTypeInfo* type_info,
                  _Outptr_result_maybenull_ const OrtTensorTypeAndShapeInfo** out);

   






  ORT_API2_STATUS(GetOnnxTypeFromTypeInfo, _In_ const OrtTypeInfo* type_info, _Out_ enum ONNXType* out);

  
  
  

   





  ORT_API2_STATUS(CreateTensorTypeAndShapeInfo, _Outptr_ OrtTensorTypeAndShapeInfo** out);

   






  ORT_API2_STATUS(SetTensorElementType, _Inout_ OrtTensorTypeAndShapeInfo* info, enum ONNXTensorElementDataType type);

   







  ORT_API2_STATUS(SetDimensions, OrtTensorTypeAndShapeInfo* info, _In_ const int64_t* dim_values, size_t dim_count);

   








  ORT_API2_STATUS(GetTensorElementType, _In_ const OrtTensorTypeAndShapeInfo* info,
                  _Out_ enum ONNXTensorElementDataType* out);

   








  ORT_API2_STATUS(GetDimensionsCount, _In_ const OrtTensorTypeAndShapeInfo* info, _Out_ size_t* out);

   







  ORT_API2_STATUS(GetDimensions, _In_ const OrtTensorTypeAndShapeInfo* info, _Out_ int64_t* dim_values,
                  size_t dim_values_length);

   







  ORT_API2_STATUS(GetSymbolicDimensions, _In_ const OrtTensorTypeAndShapeInfo* info,
                  _Out_writes_all_(dim_params_length) const char* dim_params[], size_t dim_params_length);

   















  ORT_API2_STATUS(GetTensorShapeElementCount, _In_ const OrtTensorTypeAndShapeInfo* info, _Out_ size_t* out);

  
  
  

   






  ORT_API2_STATUS(GetTensorTypeAndShape, _In_ const OrtValue* value, _Outptr_ OrtTensorTypeAndShapeInfo** out);

   






  ORT_API2_STATUS(GetTypeInfo, _In_ const OrtValue* value, _Outptr_result_maybenull_ OrtTypeInfo** out);

   






  ORT_API2_STATUS(GetValueType, _In_ const OrtValue* value, _Out_ enum ONNXType* out);

  
  
  

   









  ORT_API2_STATUS(CreateMemoryInfo, _In_ const char* name, enum OrtAllocatorType type, int id,
                  enum OrtMemType mem_type, _Outptr_ OrtMemoryInfo** out);

   









  ORT_API2_STATUS(CreateCpuMemoryInfo, enum OrtAllocatorType type, enum OrtMemType mem_type,
                  _Outptr_ OrtMemoryInfo** out);

   









  ORT_API2_STATUS(CompareMemoryInfo, _In_ const OrtMemoryInfo* info1, _In_ const OrtMemoryInfo* info2, _Out_ int* out);

   






  ORT_API2_STATUS(MemoryInfoGetName, _In_ const OrtMemoryInfo* ptr, _Out_ const char** out);

   

  ORT_API2_STATUS(MemoryInfoGetId, _In_ const OrtMemoryInfo* ptr, _Out_ int* out);

   

  ORT_API2_STATUS(MemoryInfoGetMemType, _In_ const OrtMemoryInfo* ptr, _Out_ OrtMemType* out);

   

  ORT_API2_STATUS(MemoryInfoGetType, _In_ const OrtMemoryInfo* ptr, _Out_ OrtAllocatorType* out);

  
  
  

  
  ORT_API2_STATUS(AllocatorAlloc, _Inout_ OrtAllocator* ort_allocator, size_t size, _Outptr_ void** out);
  
  ORT_API2_STATUS(AllocatorFree, _Inout_ OrtAllocator* ort_allocator, void* p);
  
  ORT_API2_STATUS(AllocatorGetInfo, _In_ const OrtAllocator* ort_allocator, _Outptr_ const struct OrtMemoryInfo** out);

   







  ORT_API2_STATUS(GetAllocatorWithDefaultOptions, _Outptr_ OrtAllocator** out);

  
  
  

   










  ORT_API2_STATUS(AddFreeDimensionOverride, _Inout_ OrtSessionOptions* options, _In_ const char* dim_denotation,
                  _In_ int64_t dim_value);

  
  
  

   

























   













  ORT_API2_STATUS(GetValue, _In_ const OrtValue* value, int index, _Inout_ OrtAllocator* allocator,
                  _Outptr_ OrtValue** out);

   









  ORT_API2_STATUS(GetValueCount, _In_ const OrtValue* value, _Out_ size_t* out);

   














  ORT_API2_STATUS(CreateValue, _In_reads_(num_values) const OrtValue* const* in, size_t num_values,
                  enum ONNXType value_type, _Outptr_ OrtValue** out);

   





















  ORT_API2_STATUS(CreateOpaqueValue, _In_z_ const char* domain_name, _In_z_ const char* type_name,
                  _In_ const void* data_container, size_t data_container_size, _Outptr_ OrtValue** out);

   













  ORT_API2_STATUS(GetOpaqueValue, _In_ const char* domain_name, _In_ const char* type_name, _In_ const OrtValue* in,
                  _Out_ void* data_container, size_t data_container_size);

  
  
  
  

   







  ORT_API2_STATUS(KernelInfoGetAttribute_float, _In_ const OrtKernelInfo* info, _In_ const char* name,
                  _Out_ float* out);

   







  ORT_API2_STATUS(KernelInfoGetAttribute_int64, _In_ const OrtKernelInfo* info, _In_ const char* name,
                  _Out_ int64_t* out);

   



















  ORT_API2_STATUS(KernelInfoGetAttribute_string, _In_ const OrtKernelInfo* info, _In_ const char* name, _Out_ char* out,
                  _Inout_ size_t* size);

  
  
  
  

   



  ORT_API2_STATUS(KernelContext_GetInputCount, _In_ const OrtKernelContext* context, _Out_ size_t* out);

   



  ORT_API2_STATUS(KernelContext_GetOutputCount, _In_ const OrtKernelContext* context, _Out_ size_t* out);

   










  ORT_API2_STATUS(KernelContext_GetInput, _In_ const OrtKernelContext* context, _In_ size_t index,
                  _Out_ const OrtValue** out);

   












  ORT_API2_STATUS(KernelContext_GetOutput, _Inout_ OrtKernelContext* context, _In_ size_t index,
                  _In_ const int64_t* dim_values, size_t dim_count, _Outptr_ OrtValue** out);

  
  
  
  ORT_CLASS_RELEASE(Env);
  
  
  
  ORT_CLASS_RELEASE(Status);
  
  
  
  ORT_CLASS_RELEASE(MemoryInfo);
  
  
  
  ORT_CLASS_RELEASE(Session);  
  
  
  
  ORT_CLASS_RELEASE(Value);
  
  
  
  ORT_CLASS_RELEASE(RunOptions);
  
  
  
  ORT_CLASS_RELEASE(TypeInfo);
  
  
  
  ORT_CLASS_RELEASE(TensorTypeAndShapeInfo);
  
  
  
  ORT_CLASS_RELEASE(SessionOptions);
  
  
  
  ORT_CLASS_RELEASE(CustomOpDomain);

  
  
  

   











  ORT_API2_STATUS(GetDenotationFromTypeInfo, _In_ const OrtTypeInfo* type_info, _Out_ const char** const denotation,
                  _Out_ size_t* len);

   












  ORT_API2_STATUS(CastTypeInfoToMapTypeInfo, _In_ const OrtTypeInfo* type_info,
                  _Outptr_result_maybenull_ const OrtMapTypeInfo** out);

   












  ORT_API2_STATUS(CastTypeInfoToSequenceTypeInfo, _In_ const OrtTypeInfo* type_info,
                  _Outptr_result_maybenull_ const OrtSequenceTypeInfo** out);

  
  
  

   










  ORT_API2_STATUS(GetMapKeyType, _In_ const OrtMapTypeInfo* map_type_info, _Out_ enum ONNXTensorElementDataType* out);

   







  ORT_API2_STATUS(GetMapValueType, _In_ const OrtMapTypeInfo* map_type_info, _Outptr_ OrtTypeInfo** type_info);

  
  
  

   









  ORT_API2_STATUS(GetSequenceElementType, _In_ const OrtSequenceTypeInfo* sequence_type_info,
                  _Outptr_ OrtTypeInfo** type_info);

  
  
  
  ORT_CLASS_RELEASE(MapTypeInfo);
  
  
  
  ORT_CLASS_RELEASE(SequenceTypeInfo);

  
  
  

   









  ORT_API2_STATUS(SessionEndProfiling, _In_ OrtSession* session, _Inout_ OrtAllocator* allocator, _Outptr_ char** out);

   






  ORT_API2_STATUS(SessionGetModelMetadata, _In_ const OrtSession* session, _Outptr_ OrtModelMetadata** out);

  
  
  

   







  ORT_API2_STATUS(ModelMetadataGetProducerName, _In_ const OrtModelMetadata* model_metadata,
                  _Inout_ OrtAllocator* allocator, _Outptr_ char** value);

   







  ORT_API2_STATUS(ModelMetadataGetGraphName, _In_ const OrtModelMetadata* model_metadata,
                  _Inout_ OrtAllocator* allocator, _Outptr_ char** value);

   







  ORT_API2_STATUS(ModelMetadataGetDomain, _In_ const OrtModelMetadata* model_metadata, _Inout_ OrtAllocator* allocator,
                  _Outptr_ char** value);

   







  ORT_API2_STATUS(ModelMetadataGetDescription, _In_ const OrtModelMetadata* model_metadata,
                  _Inout_ OrtAllocator* allocator, _Outptr_ char** value);

   









  ORT_API2_STATUS(ModelMetadataLookupCustomMetadataMap, _In_ const OrtModelMetadata* model_metadata,
                  _Inout_ OrtAllocator* allocator, _In_ const char* key, _Outptr_result_maybenull_ char** value);

   






  ORT_API2_STATUS(ModelMetadataGetVersion, _In_ const OrtModelMetadata* model_metadata, _Out_ int64_t* value);

  ORT_CLASS_RELEASE(ModelMetadata);

  
  
  

   












  ORT_API2_STATUS(CreateEnvWithGlobalThreadPools, OrtLoggingLevel log_severity_level, _In_ const char* logid,
                  _In_ const OrtThreadingOptions* tp_options, _Outptr_ OrtEnv** out);

  
  
  

   








  ORT_API2_STATUS(DisablePerSessionThreads, _Inout_ OrtSessionOptions* options);

  
  
  

   




  ORT_API2_STATUS(CreateThreadingOptions, _Outptr_ OrtThreadingOptions** out);

  ORT_CLASS_RELEASE(ThreadingOptions);

  
  
  

   










  ORT_API2_STATUS(ModelMetadataGetCustomMetadataMapKeys, _In_ const OrtModelMetadata* model_metadata,
                  _Inout_ OrtAllocator* allocator, _Outptr_result_buffer_maybenull_(*num_keys) char*** keys, _Out_ int64_t* num_keys);

  
  
  

   






  ORT_API2_STATUS(AddFreeDimensionOverrideByName,
                  _Inout_ OrtSessionOptions* options, _In_ const char* dim_name,
                  _In_ int64_t dim_value);

  
  
  

   










  ORT_API2_STATUS(GetAvailableProviders, _Outptr_ char*** out_ptr, _Out_ int* provider_length);

   







  ORT_API2_STATUS(ReleaseAvailableProviders, _In_ char** ptr,
                  _In_ int providers_length);

  
  
  

   







  ORT_API2_STATUS(GetStringTensorElementLength, _In_ const OrtValue* value, size_t index, _Out_ size_t* out);

   








  ORT_API2_STATUS(GetStringTensorElement, _In_ const OrtValue* value, size_t s_len, size_t index, _Out_writes_bytes_all_(s_len) void* s);

   







  ORT_API2_STATUS(FillStringTensorElement, _Inout_ OrtValue* value, _In_ const char* s, size_t index);

  
  
  

   











  ORT_API2_STATUS(AddSessionConfigEntry, _Inout_ OrtSessionOptions* options,
                  _In_z_ const char* config_key, _In_z_ const char* config_value);

  
  
  

   









  ORT_API2_STATUS(CreateAllocator, _In_ const OrtSession* session, _In_ const OrtMemoryInfo* mem_info,
                  _Outptr_ OrtAllocator** out);

   

  ORT_CLASS_RELEASE(Allocator);

  
  
  

   









  ORT_API2_STATUS(RunWithBinding, _Inout_ OrtSession* session, _In_ const OrtRunOptions* run_options, _In_ const OrtIoBinding* binding_ptr);

   










  ORT_API2_STATUS(CreateIoBinding, _Inout_ OrtSession* session, _Outptr_ OrtIoBinding** out);

  
  
  

   

  ORT_CLASS_RELEASE(IoBinding);

   









  ORT_API2_STATUS(BindInput, _Inout_ OrtIoBinding* binding_ptr, _In_ const char* name, _In_ const OrtValue* val_ptr);

   









  ORT_API2_STATUS(BindOutput, _Inout_ OrtIoBinding* binding_ptr, _In_ const char* name, _In_ const OrtValue* val_ptr);

   














  ORT_API2_STATUS(BindOutputToDevice, _Inout_ OrtIoBinding* binding_ptr, _In_ const char* name, _In_ const OrtMemoryInfo* mem_info_ptr);

   
















  ORT_API2_STATUS(GetBoundOutputNames, _In_ const OrtIoBinding* binding_ptr, _In_ OrtAllocator* allocator,
                  _Out_ char** buffer, _Out_writes_all_(count) size_t** lengths, _Out_ size_t* count);

   
















  ORT_API2_STATUS(GetBoundOutputValues, _In_ const OrtIoBinding* binding_ptr, _In_ OrtAllocator* allocator,
                  _Out_writes_all_(output_count) OrtValue*** output, _Out_ size_t* output_count);

   

  void(ORT_API_CALL* ClearBoundInputs)(_Inout_ OrtIoBinding* binding_ptr) NO_EXCEPTION ORT_ALL_ARGS_NONNULL;

   

  void(ORT_API_CALL* ClearBoundOutputs)(_Inout_ OrtIoBinding* binding_ptr) NO_EXCEPTION ORT_ALL_ARGS_NONNULL;

  
  
  

   













  ORT_API2_STATUS(TensorAt, _Inout_ OrtValue* value, const int64_t* location_values, size_t location_values_count, _Outptr_ void** out);

  
  
  

   













  ORT_API2_STATUS(CreateAndRegisterAllocator, _Inout_ OrtEnv* env, _In_ const OrtMemoryInfo* mem_info,
                  _In_ const OrtArenaCfg* arena_cfg);

   










  ORT_API2_STATUS(SetLanguageProjection, _In_ const OrtEnv* ort_env, _In_ OrtLanguageProjection projection);

  
  
  

   








  ORT_API2_STATUS(SessionGetProfilingStartTimeNs, _In_ const OrtSession* session, _Outptr_ uint64_t* out);

  
  
  

   










  ORT_API2_STATUS(SetGlobalIntraOpNumThreads, _Inout_ OrtThreadingOptions* tp_options, int intra_op_num_threads);

   










  ORT_API2_STATUS(SetGlobalInterOpNumThreads, _Inout_ OrtThreadingOptions* tp_options, int inter_op_num_threads);

   












  ORT_API2_STATUS(SetGlobalSpinControl, _Inout_ OrtThreadingOptions* tp_options, int allow_spinning);

  
  
  

   













  ORT_API2_STATUS(AddInitializer, _Inout_ OrtSessionOptions* options, _In_z_ const char* name,
                  _In_ const OrtValue* val);

  
  
  

   














  ORT_API2_STATUS(CreateEnvWithCustomLoggerAndGlobalThreadPools, OrtLoggingFunction logging_function, _In_opt_ void* logger_param, OrtLoggingLevel log_severity_level,
                  _In_ const char* logid, _In_ const struct OrtThreadingOptions* tp_options, _Outptr_ OrtEnv** out);

  
  
  

   








  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_CUDA,
                  _In_ OrtSessionOptions* options, _In_ const OrtCUDAProviderOptions* cuda_options);

   








  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_ROCM,
                  _In_ OrtSessionOptions* options, _In_ const OrtROCMProviderOptions* rocm_options);

   








  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_OpenVINO,
                  _In_ OrtSessionOptions* options, _In_ const OrtOpenVINOProviderOptions* provider_options);

  
  
  

   









  ORT_API2_STATUS(SetGlobalDenormalAsZero, _Inout_ OrtThreadingOptions* tp_options);

  
  
  

   











  ORT_API2_STATUS(CreateArenaCfg, _In_ size_t max_mem, int arena_extend_strategy, int initial_chunk_size_bytes,
                  int max_dead_bytes_per_chunk, _Outptr_ OrtArenaCfg** out);

  ORT_CLASS_RELEASE(ArenaCfg);

  
  
  

   










  ORT_API2_STATUS(ModelMetadataGetGraphDescription, _In_ const OrtModelMetadata* model_metadata,
                  _Inout_ OrtAllocator* allocator, _Outptr_ char** value);

  
  
  

   








  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_TensorRT,
                  _In_ OrtSessionOptions* options, _In_ const OrtTensorRTProviderOptions* tensorrt_options);

  
  
  

   









  ORT_API2_STATUS(SetCurrentGpuDeviceId, _In_ int device_id);

   









  ORT_API2_STATUS(GetCurrentGpuDeviceId, _In_ int* device_id);

  
  
  
  

   





















  ORT_API2_STATUS(KernelInfoGetAttributeArray_float, _In_ const OrtKernelInfo* info, _In_ const char* name,
                  _Out_ float* out, _Inout_ size_t* size);

   




















  ORT_API2_STATUS(KernelInfoGetAttributeArray_int64, _In_ const OrtKernelInfo* info, _In_ const char* name,
                  _Out_ int64_t* out, _Inout_ size_t* size);

  
  
  

   






























  ORT_API2_STATUS(CreateArenaCfgV2, _In_reads_(num_keys) const char* const* arena_config_keys,
                  _In_reads_(num_keys) const size_t* arena_config_values, _In_ size_t num_keys,
                  _Outptr_ OrtArenaCfg** out);

  
  
  

   











  ORT_API2_STATUS(AddRunConfigEntry, _Inout_ OrtRunOptions* options,
                  _In_z_ const char* config_key, _In_z_ const char* config_value);

  
  
  

   











  ORT_API2_STATUS(CreatePrepackedWeightsContainer, _Outptr_ OrtPrepackedWeightsContainer** out);

   



  ORT_CLASS_RELEASE(PrepackedWeightsContainer);

  
  
  

   
















  ORT_API2_STATUS(CreateSessionWithPrepackedWeightsContainer, _In_ const OrtEnv* env, _In_ const ORTCHAR_T* model_path,
                  _In_ const OrtSessionOptions* options,
                  _Inout_ OrtPrepackedWeightsContainer* prepacked_weights_container,
                  _Outptr_ OrtSession** out);

   

















  ORT_API2_STATUS(CreateSessionFromArrayWithPrepackedWeightsContainer, _In_ const OrtEnv* env,
                  _In_ const void* model_data, size_t model_data_length,
                  _In_ const OrtSessionOptions* options,
                  _Inout_ OrtPrepackedWeightsContainer* prepacked_weights_container,
                  _Outptr_ OrtSession** out);

  
  
  

   
















  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_TensorRT_V2,
                  _In_ OrtSessionOptions* options, _In_ const OrtTensorRTProviderOptionsV2* tensorrt_options);

  
  
  

   





  ORT_API2_STATUS(CreateTensorRTProviderOptions, _Outptr_ OrtTensorRTProviderOptionsV2** out);

   














  ORT_API2_STATUS(UpdateTensorRTProviderOptions, _Inout_ OrtTensorRTProviderOptionsV2* tensorrt_options,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   










  ORT_API2_STATUS(GetTensorRTProviderOptionsAsString, _In_ const OrtTensorRTProviderOptionsV2* tensorrt_options, _Inout_ OrtAllocator* allocator, _Outptr_ char** ptr);

   



  void(ORT_API_CALL* ReleaseTensorRTProviderOptions)(_Frees_ptr_opt_ OrtTensorRTProviderOptionsV2* input);

  
  
  

   





  ORT_API2_STATUS(EnableOrtCustomOps, _Inout_ OrtSessionOptions* options);

  
  
  

   














  ORT_API2_STATUS(RegisterAllocator, _Inout_ OrtEnv* env, _In_ OrtAllocator* allocator);

   









  ORT_API2_STATUS(UnregisterAllocator, _Inout_ OrtEnv* env,
                  _In_ const OrtMemoryInfo* mem_info);

  
  
  

   







  ORT_API2_STATUS(IsSparseTensor, _In_ const OrtValue* value, _Out_ int* out);

   















  ORT_API2_STATUS(CreateSparseTensorAsOrtValue, _Inout_ OrtAllocator* allocator, _In_ const int64_t* dense_shape,
                  size_t dense_shape_len, ONNXTensorElementDataType type, _Outptr_ OrtValue** out);

   
















  ORT_API2_STATUS(FillSparseTensorCoo, _Inout_ OrtValue* ort_value, _In_ const OrtMemoryInfo* data_mem_info,
                  _In_ const int64_t* values_shape, size_t values_shape_len, _In_ const void* values,
                  _In_ const int64_t* indices_data, size_t indices_num);

   


















  ORT_API2_STATUS(FillSparseTensorCsr, _Inout_ OrtValue* ort_value, _In_ const OrtMemoryInfo* data_mem_info,
                  _In_ const int64_t* values_shape, size_t values_shape_len, _In_ const void* values,
                  _In_ const int64_t* inner_indices_data, size_t inner_indices_num,
                  _In_ const int64_t* outer_indices_data, size_t outer_indices_num);

   

















  ORT_API2_STATUS(FillSparseTensorBlockSparse, _Inout_ OrtValue* ort_value, _In_ const OrtMemoryInfo* data_mem_info,
                  _In_ const int64_t* values_shape, size_t values_shape_len, _In_ const void* values,
                  _In_ const int64_t* indices_shape_data, size_t indices_shape_len,
                  _In_ const int32_t* indices_data);

   























  ORT_API2_STATUS(CreateSparseTensorWithValuesAsOrtValue, _In_ const OrtMemoryInfo* info, _Inout_ void* p_data,
                  _In_ const int64_t* dense_shape, size_t dense_shape_len,
                  _In_ const int64_t* values_shape, size_t values_shape_len,
                  ONNXTensorElementDataType type, _Outptr_ OrtValue** out);

   













  ORT_API2_STATUS(UseCooIndices, _Inout_ OrtValue* ort_value, _Inout_ int64_t* indices_data, size_t indices_num);

   















  ORT_API2_STATUS(UseCsrIndices, _Inout_ OrtValue* ort_value, _Inout_ int64_t* inner_data, size_t inner_num,
                  _Inout_ int64_t* outer_data, size_t outer_num);

   












  ORT_API2_STATUS(UseBlockSparseIndices, _Inout_ OrtValue* ort_value, const int64_t* indices_shape, size_t indices_shape_len, _Inout_ int32_t* indices_data);

   






  ORT_API2_STATUS(GetSparseTensorFormat, _In_ const OrtValue* ort_value, _Out_ enum OrtSparseFormat* out);

   






  ORT_API2_STATUS(GetSparseTensorValuesTypeAndShape, _In_ const OrtValue* ort_value, _Outptr_ OrtTensorTypeAndShapeInfo** out);

   






  ORT_API2_STATUS(GetSparseTensorValues, _In_ const OrtValue* ort_value, _Outptr_ const void** out);

   








  ORT_API2_STATUS(GetSparseTensorIndicesTypeShape, _In_ const OrtValue* ort_value, enum OrtSparseIndicesFormat indices_format, _Outptr_ OrtTensorTypeAndShapeInfo** out);

   








  ORT_API2_STATUS(GetSparseTensorIndices, _In_ const OrtValue* ort_value, enum OrtSparseIndicesFormat indices_format, _Out_ size_t* num_indices, _Outptr_ const void** indices);
  
  
  

   











  ORT_API2_STATUS(HasValue, _In_ const OrtValue* value, _Out_ int* out);

  
  
  
  

   










  ORT_API2_STATUS(KernelContext_GetGPUComputeStream, _In_ const OrtKernelContext* context, _Outptr_ void** out);

  
  
  
   





  ORT_API2_STATUS(GetTensorMemoryInfo, _In_ const OrtValue* value, _Out_ const OrtMemoryInfo** mem_info);

  
  
  
   









  ORT_API2_STATUS(GetExecutionProviderApi, _In_ const char* provider_name, _In_ uint32_t version, _Outptr_ const void** provider_api);

  

  
  
   






  ORT_API2_STATUS(SessionOptionsSetCustomCreateThreadFn, _Inout_ OrtSessionOptions* options, _In_ OrtCustomCreateThreadFn ort_custom_create_thread_fn);

   






  ORT_API2_STATUS(SessionOptionsSetCustomThreadCreationOptions, _Inout_ OrtSessionOptions* options, _In_ void* ort_custom_thread_creation_options);

   






  ORT_API2_STATUS(SessionOptionsSetCustomJoinThreadFn, _Inout_ OrtSessionOptions* options, _In_ OrtCustomJoinThreadFn ort_custom_join_thread_fn);
  

  
  
   






  ORT_API2_STATUS(SetGlobalCustomCreateThreadFn, _Inout_ OrtThreadingOptions* tp_options, _In_ OrtCustomCreateThreadFn ort_custom_create_thread_fn);

   






  ORT_API2_STATUS(SetGlobalCustomThreadCreationOptions, _Inout_ OrtThreadingOptions* tp_options, _In_ void* ort_custom_thread_creation_options);

   






  ORT_API2_STATUS(SetGlobalCustomJoinThreadFn, _Inout_ OrtThreadingOptions* tp_options, _In_ OrtCustomJoinThreadFn ort_custom_join_thread_fn);
  

   







  ORT_API2_STATUS(SynchronizeBoundInputs, _Inout_ OrtIoBinding* binding_ptr);

   







  ORT_API2_STATUS(SynchronizeBoundOutputs, _Inout_ OrtIoBinding* binding_ptr);

  
  

   


















  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_CUDA_V2,
                  _In_ OrtSessionOptions* options, _In_ const OrtCUDAProviderOptionsV2* cuda_options);

  
  
  

   







  ORT_API2_STATUS(CreateCUDAProviderOptions, _Outptr_ OrtCUDAProviderOptionsV2** out);

   
















  ORT_API2_STATUS(UpdateCUDAProviderOptions, _Inout_ OrtCUDAProviderOptionsV2* cuda_options,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   













  ORT_API2_STATUS(GetCUDAProviderOptionsAsString, _In_ const OrtCUDAProviderOptionsV2* cuda_options, _Inout_ OrtAllocator* allocator, _Outptr_ char** ptr);

   





  void(ORT_API_CALL* ReleaseCUDAProviderOptions)(_Frees_ptr_opt_ OrtCUDAProviderOptionsV2* input);

  

   










  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_MIGraphX,
                  _In_ OrtSessionOptions* options, _In_ const OrtMIGraphXProviderOptions* migraphx_options);

   




















  ORT_API2_STATUS(AddExternalInitializers, _In_ OrtSessionOptions* options,
                  _In_reads_(num_initializers) const char* const* initializer_names,
                  _In_reads_(num_initializers) const OrtValue* const* initializers, size_t num_initializers);

   










  ORT_API2_STATUS(CreateOpAttr,
                  _In_ const char* name,
                  _In_ const void* data,
                  _In_ int len,
                  _In_ OrtOpAttrType type,
                  _Outptr_ OrtOpAttr** op_attr);

   





  ORT_CLASS_RELEASE(OpAttr);

   
















  ORT_API2_STATUS(CreateOp,
                  _In_ const OrtKernelInfo* info,
                  _In_z_ const char* op_name,
                  _In_z_ const char* domain,
                  int version,
                  _In_reads_(type_constraint_count) const char** type_constraint_names,
                  _In_reads_(type_constraint_count) const ONNXTensorElementDataType* type_constraint_values,
                  int type_constraint_count,
                  _In_reads_(attr_count) const OrtOpAttr* const* attr_values,
                  int attr_count,
                  int input_count,
                  int output_count,
                  _Outptr_ OrtOp** ort_op);

   











  ORT_API2_STATUS(InvokeOp,
                  _In_ const OrtKernelContext* context,
                  _In_ const OrtOp* ort_op,
                  _In_ const OrtValue* const* input_values,
                  _In_ int input_count,
                  _Inout_ OrtValue* const* output_values,
                  _In_ int output_count);

   





  ORT_CLASS_RELEASE(Op);

   





















































































































  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider, _In_ OrtSessionOptions* options,
                  _In_ const char* provider_name,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   






  ORT_API2_STATUS(CopyKernelInfo,
                  _In_ const OrtKernelInfo* info,
                  _Outptr_ OrtKernelInfo** info_copy);

   





  ORT_CLASS_RELEASE(KernelInfo);

  
  
   













  const OrtTrainingApi*(ORT_API_CALL* GetTrainingApi)(uint32_t version)NO_EXCEPTION;

  

   










  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_CANN,
                  _In_ OrtSessionOptions* options, _In_ const OrtCANNProviderOptions* cann_options);

   







  ORT_API2_STATUS(CreateCANNProviderOptions, _Outptr_ OrtCANNProviderOptions** out);

   










  ORT_API2_STATUS(UpdateCANNProviderOptions, _Inout_ OrtCANNProviderOptions* cann_options,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   












  ORT_API2_STATUS(GetCANNProviderOptionsAsString, _In_ const OrtCANNProviderOptions* cann_options,
                  _Inout_ OrtAllocator* allocator, _Outptr_ char** ptr);

   





  void(ORT_API_CALL* ReleaseCANNProviderOptions)(_Frees_ptr_opt_ OrtCANNProviderOptions* input);

   



  void(ORT_API_CALL* MemoryInfoGetDeviceType)(_In_ const OrtMemoryInfo* ptr, _Out_ OrtMemoryInfoDeviceType* out);

   






  ORT_API2_STATUS(UpdateEnvWithCustomLogLevel, _In_ OrtEnv* ort_env, OrtLoggingLevel log_severity_level);

   


















  ORT_API2_STATUS(SetGlobalIntraOpThreadAffinity, _Inout_ OrtThreadingOptions* tp_options, const char* affinity_string);

   

















  ORT_API2_STATUS(RegisterCustomOpsLibrary_V2, _Inout_ OrtSessionOptions* options, _In_ const ORTCHAR_T* library_name);

   























  ORT_API2_STATUS(RegisterCustomOpsUsingFunction, _Inout_ OrtSessionOptions* options,
                  _In_ const char* registration_func_name);

  
  
  

   










  ORT_API2_STATUS(KernelInfo_GetInputCount, _In_ const OrtKernelInfo* info, _Out_ size_t* out);

   










  ORT_API2_STATUS(KernelInfo_GetOutputCount, _In_ const OrtKernelInfo* info, _Out_ size_t* out);

   























  ORT_API2_STATUS(KernelInfo_GetInputName, _In_ const OrtKernelInfo* info, size_t index, _Out_ char* out,
                  _Inout_ size_t* size);

   
























  ORT_API2_STATUS(KernelInfo_GetOutputName, _In_ const OrtKernelInfo* info, size_t index, _Out_ char* out,
                  _Inout_ size_t* size);

   











  ORT_API2_STATUS(KernelInfo_GetInputTypeInfo, _In_ const OrtKernelInfo* info, size_t index,
                  _Outptr_ OrtTypeInfo** type_info);

   











  ORT_API2_STATUS(KernelInfo_GetOutputTypeInfo, _In_ const OrtKernelInfo* info, size_t index,
                  _Outptr_ OrtTypeInfo** type_info);

   











  ORT_API2_STATUS(KernelInfoGetAttribute_tensor, _In_ const OrtKernelInfo* info, _In_z_ const char* name,
                  _Inout_ OrtAllocator* allocator, _Outptr_ OrtValue** out);

  
  
  
  

   














  ORT_API2_STATUS(HasSessionConfigEntry, _In_ const OrtSessionOptions* options,
                  _In_z_ const char* config_key, _Out_ int* out);

   



























  ORT_API2_STATUS(GetSessionConfigEntry, _In_ const OrtSessionOptions* options,
                  _In_z_ const char* config_key, _Out_ char* config_value, _Inout_ size_t* size);

  

   










  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_Dnnl,
                  _In_ OrtSessionOptions* options, _In_ const OrtDnnlProviderOptions* dnnl_options);

   







  ORT_API2_STATUS(CreateDnnlProviderOptions, _Outptr_ OrtDnnlProviderOptions** out);

   















  ORT_API2_STATUS(UpdateDnnlProviderOptions, _Inout_ OrtDnnlProviderOptions* dnnl_options,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   













  ORT_API2_STATUS(GetDnnlProviderOptionsAsString, _In_ const OrtDnnlProviderOptions* dnnl_options, _Inout_ OrtAllocator* allocator, _Outptr_ char** ptr);

   



  void(ORT_API_CALL* ReleaseDnnlProviderOptions)(_Frees_ptr_opt_ OrtDnnlProviderOptions* input);

  
  
  

   





















  ORT_API2_STATUS(KernelInfo_GetNodeName, _In_ const OrtKernelInfo* info, _Out_ char* out, _Inout_ size_t* size);

   










  ORT_API2_STATUS(KernelInfo_GetLogger, _In_ const OrtKernelInfo* info, _Outptr_ const OrtLogger** logger);

  
  
  
  

   










  ORT_API2_STATUS(KernelContext_GetLogger, _In_ const OrtKernelContext* context, _Outptr_ const OrtLogger** logger);

  
  
  
  

   

















  ORT_API2_STATUS(Logger_LogMessage, _In_ const OrtLogger* logger, OrtLoggingLevel log_severity_level,
                  _In_z_ const char* message, _In_z_ const ORTCHAR_T* file_path, int line_number,
                  _In_z_ const char* func_name);

   










  ORT_API2_STATUS(Logger_GetLoggingSeverityLevel, _In_ const OrtLogger* logger, _Out_ OrtLoggingLevel* out);

  

   












  ORT_API2_STATUS(KernelInfoGetConstantInput_tensor, _In_ const OrtKernelInfo* info, size_t index, _Out_ int* is_constant, _Outptr_ const OrtValue** out);

   



















  ORT_API2_STATUS(CastTypeInfoToOptionalTypeInfo, _In_ const OrtTypeInfo* type_info,
                  _Outptr_result_maybenull_ const OrtOptionalTypeInfo** out);

   















  ORT_API2_STATUS(GetOptionalContainedTypeInfo, _In_ const OrtOptionalTypeInfo* optional_type_info,
                  _Outptr_ OrtTypeInfo** out);

   









  ORT_API2_STATUS(GetResizedStringTensorElementBuffer, _Inout_ OrtValue* value, _In_ size_t index, _In_ size_t length_in_bytes, _Inout_ char** buffer);

   









  ORT_API2_STATUS(KernelContext_GetAllocator, _In_ const OrtKernelContext* context, _In_ const OrtMemoryInfo* mem_info, _Outptr_ OrtAllocator** out);

   





  const char*(ORT_API_CALL* GetBuildInfoString)(void);

  
  

   







  ORT_API2_STATUS(CreateROCMProviderOptions, _Outptr_ OrtROCMProviderOptions** out);

   
















  ORT_API2_STATUS(UpdateROCMProviderOptions, _Inout_ OrtROCMProviderOptions* rocm_options,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   













  ORT_API2_STATUS(GetROCMProviderOptionsAsString, _In_ const OrtROCMProviderOptions* rocm_options, _Inout_ OrtAllocator* allocator, _Outptr_ char** ptr);

   





  void(ORT_API_CALL* ReleaseROCMProviderOptions)(_Frees_ptr_opt_ OrtROCMProviderOptions* input);

   












  ORT_API2_STATUS(CreateAndRegisterAllocatorV2, _Inout_ OrtEnv* env, _In_ const char* provider_type,
                  _In_ const OrtMemoryInfo* mem_info, _In_ const OrtArenaCfg* arena_cfg,
                  _In_reads_(num_keys) const char* const* provider_options_keys, _In_reads_(num_keys) const char* const* provider_options_values, _In_ size_t num_keys);

   

















  ORT_API2_STATUS(RunAsync, _Inout_ OrtSession* session, _In_opt_ const OrtRunOptions* run_options,
                  _In_reads_(input_len) const char* const* input_names,
                  _In_reads_(input_len) const OrtValue* const* input, size_t input_len,
                  _In_reads_(output_names_len) const char* const* output_names, size_t output_names_len,
                  _Inout_updates_all_(output_names_len) OrtValue** output,
                  _In_ RunAsyncCallbackFn run_async_callback, _In_opt_ void* user_data);

   











  ORT_API2_STATUS(UpdateTensorRTProviderOptionsWithValue, _Inout_ OrtTensorRTProviderOptionsV2* tensorrt_options, _In_ const char* key, _In_ void* value);

   









  ORT_API2_STATUS(GetTensorRTProviderOptionsByName, _In_ const OrtTensorRTProviderOptionsV2* tensorrt_options, _In_ const char* key, _Outptr_ void** ptr);

   











  ORT_API2_STATUS(UpdateCUDAProviderOptionsWithValue, _Inout_ OrtCUDAProviderOptionsV2* cuda_options, _In_ const char* key, _In_ void* value);

   









  ORT_API2_STATUS(GetCUDAProviderOptionsByName, _In_ const OrtCUDAProviderOptionsV2* cuda_options, _In_ const char* key, _Outptr_ void** ptr);

   










  ORT_API2_STATUS(KernelContext_GetResource, _In_ const OrtKernelContext* context, _In_ int resource_version,
                  _In_ int resource_id, _Outptr_ void** resource);

   
















  ORT_API2_STATUS(SetUserLoggingFunction, _Inout_ OrtSessionOptions* options,
                  _In_ OrtLoggingFunction user_logging_function, _In_opt_ void* user_logging_param);

   







  ORT_API2_STATUS(ShapeInferContext_GetInputCount, _In_ const OrtShapeInferContext* context, _Out_ size_t* out);

   








  ORT_API2_STATUS(ShapeInferContext_GetInputTypeShape, _In_ const OrtShapeInferContext* context, _In_ size_t index, _Outptr_ OrtTensorTypeAndShapeInfo** info);

   








  ORT_API2_STATUS(ShapeInferContext_GetAttribute, _In_ const OrtShapeInferContext* context, _In_ const char* attr_name, _Outptr_ const OrtOpAttr** attr);

   








  ORT_API2_STATUS(ShapeInferContext_SetOutputTypeShape, _In_ const OrtShapeInferContext* context, _In_ size_t index, _In_ const OrtTensorTypeAndShapeInfo* info);

   








  ORT_API2_STATUS(SetSymbolicDimensions, _In_ OrtTensorTypeAndShapeInfo* info, _In_ const char* dim_params[], _In_ size_t dim_params_length);

   












  ORT_API2_STATUS(ReadOpAttr, _In_ const OrtOpAttr* op_attr, _In_ OrtOpAttrType type, _Inout_ void* data, _In_ size_t len, _Out_ size_t* out);

   









  ORT_API2_STATUS(SetDeterministicCompute, _Inout_ OrtSessionOptions* options, bool value);

   










  ORT_API2_STATUS(KernelContext_ParallelFor, _In_ const OrtKernelContext* context, _In_ void (*fn)(void*, size_t), _In_ size_t total, _In_ size_t num_batch, _In_ void* usr_data);

   












  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_OpenVINO_V2,
                  _In_ OrtSessionOptions* options,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   












  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_VitisAI,
                  _In_ OrtSessionOptions* options,
                  _In_reads_(num_keys) const char* const* provider_options_keys,
                  _In_reads_(num_keys) const char* const* provider_options_values,
                  _In_ size_t num_keys);

   










  ORT_API2_STATUS(KernelContext_GetScratchBuffer, _In_ const OrtKernelContext* context, _In_ const OrtMemoryInfo* mem_info, _In_ size_t count_or_bytes, _Outptr_ void** out);

   









  ORT_API2_STATUS(KernelInfoGetAllocator, _In_ const OrtKernelInfo* info, _In_ OrtMemType mem_type, _Outptr_ OrtAllocator** out);

   




















  ORT_API2_STATUS(AddExternalInitializersFromFilesInMemory, _In_ OrtSessionOptions* options,
                  _In_reads_(num_external_initializer_files) const ORTCHAR_T* const* external_initializer_file_names,
                  _In_reads_(num_external_initializer_files) char* const* external_initializer_file_buffer_array,
                  _In_reads_(num_external_initializer_files) const size_t* external_initializer_file_lengths,
                  size_t num_external_initializer_files);

   

















  ORT_API2_STATUS(CreateLoraAdapter, const ORTCHAR_T* adapter_file_path, _In_ OrtAllocator* allocator,
                  _Outptr_ OrtLoraAdapter** out);

   
















  ORT_API2_STATUS(CreateLoraAdapterFromArray, _In_ const void* bytes, size_t num_bytes, _In_ OrtAllocator* allocator,
                  _Outptr_ OrtLoraAdapter** out);

   

  ORT_CLASS_RELEASE(LoraAdapter);

   















  ORT_API2_STATUS(RunOptionsAddActiveLoraAdapter, _Inout_ OrtRunOptions* options, _In_ const OrtLoraAdapter* adapter);

  
  
  

   













  ORT_API2_STATUS(SetEpDynamicOptions, _Inout_ OrtSession* sess, _In_reads_(kv_len) const char* const* keys,
                  _In_reads_(kv_len) const char* const* values, _In_ size_t kv_len);

  

   


  ORT_CLASS_RELEASE(ValueInfo);

   


  ORT_CLASS_RELEASE(Node);

   



  ORT_CLASS_RELEASE(Graph);

   



  ORT_CLASS_RELEASE(Model);

   





  ORT_API2_STATUS(GetValueInfoName, _In_ const OrtValueInfo* value_info, _Out_ const char** name);

   





  ORT_API2_STATUS(GetValueInfoTypeInfo, _In_ const OrtValueInfo* value_info, _Outptr_ const OrtTypeInfo** type_info);

   







  const OrtModelEditorApi*(ORT_API_CALL* GetModelEditorApi)();

   

















  ORT_API2_STATUS(CreateTensorWithDataAndDeleterAsOrtValue, _In_ OrtAllocator* deleter,
                  _In_ void* p_data, size_t p_data_len,
                  _In_ const int64_t* shape, size_t shape_len,
                  ONNXTensorElementDataType type,
                  _Outptr_ OrtValue** out);

   















  ORT_API2_STATUS(SessionOptionsSetLoadCancellationFlag, _Inout_ OrtSessionOptions* options,
                  _In_ bool cancel);

   












  const OrtCompileApi*(ORT_API_CALL* GetCompileApi)();

  
  
  

   







  void(ORT_API_CALL* CreateKeyValuePairs)(_Outptr_ OrtKeyValuePairs** out);

   












  void(ORT_API_CALL* AddKeyValuePair)(_In_ OrtKeyValuePairs* kvps, _In_ const char* key, _In_ const char* value);

   








  const char*(ORT_API_CALL* GetKeyValue)(_In_ const OrtKeyValuePairs* kvps, _In_ const char* key);

   








  void(ORT_API_CALL* GetKeyValuePairs)(_In_ const OrtKeyValuePairs* kvps,
                                       _Outptr_ const char* const** keys, _Outptr_ const char* const** values,
                                       _Out_ size_t* num_entries);

   






  void(ORT_API_CALL* RemoveKeyValuePair)(_In_ OrtKeyValuePairs* kvps, _In_ const char* key);

   





  ORT_CLASS_RELEASE(KeyValuePairs);

   












  ORT_API2_STATUS(RegisterExecutionProviderLibrary, _In_ OrtEnv* env, _In_ const char* registration_name,
                  _In_ const ORTCHAR_T* path);

   













  ORT_API2_STATUS(UnregisterExecutionProviderLibrary, _In_ OrtEnv* env, _In_ const char* registration_name);

   











  ORT_API2_STATUS(GetEpDevices, _In_ const OrtEnv* env,
                  _Outptr_ const OrtEpDevice* const** ep_devices, _Out_ size_t* num_ep_devices);

   


















  ORT_API2_STATUS(SessionOptionsAppendExecutionProvider_V2, _In_ OrtSessionOptions* session_options,
                  _In_ OrtEnv* env,
                  _In_reads_(num_ep_devices) const OrtEpDevice* const* ep_devices, _In_ size_t num_ep_devices,
                  _In_reads_(num_op_options) const char* const* ep_option_keys,
                  _In_reads_(num_op_options) const char* const* ep_option_vals,
                  size_t num_ep_options);

   









  ORT_API2_STATUS(SessionOptionsSetEpSelectionPolicy, _In_ OrtSessionOptions* session_options,
                  _In_ OrtExecutionProviderDevicePolicy policy);

   









  ORT_API2_STATUS(SessionOptionsSetEpSelectionPolicyDelegate, _In_ OrtSessionOptions* session_options,
                  _In_ EpSelectionDelegate delegate,
                  _In_opt_ void* delegate_state);

   






  OrtHardwareDeviceType(ORT_API_CALL* HardwareDevice_Type)(_In_ const OrtHardwareDevice* device);

   






  uint32_t(ORT_API_CALL* HardwareDevice_VendorId)(_In_ const OrtHardwareDevice* device);

   






  const char*(ORT_API_CALL* HardwareDevice_Vendor)(_In_ const OrtHardwareDevice* device);

   







  uint32_t(ORT_API_CALL* HardwareDevice_DeviceId)(_In_ const OrtHardwareDevice* device);

   







  const OrtKeyValuePairs*(ORT_API_CALL* HardwareDevice_Metadata)(_In_ const OrtHardwareDevice* device);

   






  const char*(ORT_API_CALL* EpDevice_EpName)(_In_ const OrtEpDevice* ep_device);

   






  const char*(ORT_API_CALL* EpDevice_EpVendor)(_In_ const OrtEpDevice* ep_device);

   






  const OrtKeyValuePairs*(ORT_API_CALL* EpDevice_EpMetadata)(_In_ const OrtEpDevice* ep_device);

   






  const OrtKeyValuePairs*(ORT_API_CALL* EpDevice_EpOptions)(_In_ const OrtEpDevice* ep_device);

   






  const OrtHardwareDevice*(ORT_API_CALL* EpDevice_Device)(_In_ const OrtEpDevice* ep_device);

   



  const OrtEpApi*(ORT_API_CALL* GetEpApi)();

   












  ORT_API2_STATUS(GetTensorSizeInBytes, _In_ const OrtValue* ort_value, _Out_ size_t* size);

   













  ORT_API2_STATUS(AllocatorGetStats, _In_ const OrtAllocator* ort_allocator, _Outptr_ OrtKeyValuePairs** out);

   



















  ORT_API2_STATUS(CreateMemoryInfo_V2, _In_ const char* name, _In_ enum OrtMemoryInfoDeviceType device_type,
                  _In_ uint32_t vendor_id, _In_ int32_t device_id, _In_ enum OrtDeviceMemoryType mem_type,
                  _In_ size_t alignment, enum OrtAllocatorType allocator_type,
                  _Outptr_ OrtMemoryInfo** out);

   






  ORT_API_T(OrtDeviceMemoryType, MemoryInfoGetDeviceMemType, _In_ const OrtMemoryInfo* ptr);

   






  ORT_API_T(uint32_t, MemoryInfoGetVendorId, _In_ const OrtMemoryInfo* ptr);

  
  

   









  ORT_API2_STATUS(ValueInfo_GetValueProducer, _In_ const OrtValueInfo* value_info,
                  _Outptr_ const OrtNode** producer_node, _Out_opt_ size_t* producer_output_index);

   














  ORT_API2_STATUS(ValueInfo_GetValueNumConsumers, _In_ const OrtValueInfo* value_info, _Out_ size_t* num_consumers);

   

























  ORT_API2_STATUS(ValueInfo_GetValueConsumers, _In_ const OrtValueInfo* value_info,
                  _Out_writes_all_(num_consumers) const OrtNode** nodes,
                  _Out_writes_all_(num_consumers) int64_t* input_indices,
                  _In_ size_t num_consumers);

   


















  ORT_API2_STATUS(ValueInfo_GetInitializerValue, _In_ const OrtValueInfo* value_info,
                  _Outptr_ const OrtValue** initializer_value);

   














  ORT_API2_STATUS(ValueInfo_GetExternalInitializerInfo, _In_ const OrtValueInfo* value_info,
                  _Outptr_result_maybenull_ OrtExternalInitializerInfo** info);

   













  ORT_API2_STATUS(ValueInfo_IsRequiredGraphInput, _In_ const OrtValueInfo* value_info,
                  _Out_ bool* is_required_graph_input);

   












  ORT_API2_STATUS(ValueInfo_IsOptionalGraphInput, _In_ const OrtValueInfo* value_info,
                  _Out_ bool* is_optional_graph_input);

   








  ORT_API2_STATUS(ValueInfo_IsGraphOutput, _In_ const OrtValueInfo* value_info, _Out_ bool* is_graph_output);

   













  ORT_API2_STATUS(ValueInfo_IsConstantInitializer, _In_ const OrtValueInfo* value_info,
                  _Out_ bool* is_constant_initializer);

   












  ORT_API2_STATUS(ValueInfo_IsFromOuterScope, _In_ const OrtValueInfo* value_info,
                  _Out_ bool* is_from_outer_scope);

  

  
  

   








  ORT_API2_STATUS(Graph_GetName, _In_ const OrtGraph* graph, _Outptr_ const char** graph_name);

   












  ORT_API2_STATUS(Graph_GetModelPath, _In_ const OrtGraph* graph, _Outptr_ const ORTCHAR_T** model_path);

   








  ORT_API2_STATUS(Graph_GetOnnxIRVersion, _In_ const OrtGraph* graph, _Out_ int64_t* onnx_ir_version);

   












  ORT_API2_STATUS(Graph_GetNumOperatorSets, _In_ const OrtGraph* graph, _Out_ size_t* num_operator_sets);

   



















  ORT_API2_STATUS(Graph_GetOperatorSets, _In_ const OrtGraph* graph,
                  _Out_writes_(num_operator_sets) const char** domains,
                  _Out_writes_(num_operator_sets) int64_t* opset_versions, _In_ size_t num_operator_sets);

   










  ORT_API2_STATUS(Graph_GetNumInputs, _In_ const OrtGraph* graph, _Out_ size_t* num_inputs);

   













  ORT_API2_STATUS(Graph_GetInputs, _In_ const OrtGraph* graph,
                  _Out_writes_(num_inputs) const OrtValueInfo** inputs, _In_ size_t num_inputs);

   








  ORT_API2_STATUS(Graph_GetNumOutputs, _In_ const OrtGraph* graph, _Out_ size_t* num_outputs);

   











  ORT_API2_STATUS(Graph_GetOutputs, _In_ const OrtGraph* graph,
                  _Out_writes_(num_outputs) const OrtValueInfo** outputs, _In_ size_t num_outputs);

   










  ORT_API2_STATUS(Graph_GetNumInitializers, _In_ const OrtGraph* graph, _Out_ size_t* num_initializers);

   




















  ORT_API2_STATUS(Graph_GetInitializers, _In_ const OrtGraph* graph,
                  _Out_writes_(num_initializers) const OrtValueInfo** initializers,
                  _In_ size_t num_initializers);

   








  ORT_API2_STATUS(Graph_GetNumNodes, _In_ const OrtGraph* graph, _Out_ size_t* num_nodes);

   














  ORT_API2_STATUS(Graph_GetNodes, _In_ const OrtGraph* graph,
                  _Out_writes_(num_nodes) const OrtNode** nodes, _In_ size_t num_nodes);

   












  ORT_API2_STATUS(Graph_GetParentNode, _In_ const OrtGraph* graph, _Outptr_result_maybenull_ const OrtNode** node);

   













  ORT_API2_STATUS(Graph_GetGraphView, _In_ const OrtGraph* src_graph, _In_ const OrtNode** nodes,
                  _In_ size_t num_nodes, _Outptr_ OrtGraph** dst_graph);

  

  
  

   











  ORT_API2_STATUS(Node_GetId, _In_ const OrtNode* node, _Out_ size_t* node_id);

   








  ORT_API2_STATUS(Node_GetName, _In_ const OrtNode* node, _Outptr_ const char** node_name);

   








  ORT_API2_STATUS(Node_GetOperatorType, _In_ const OrtNode* node, _Outptr_ const char** operator_type);

   








  ORT_API2_STATUS(Node_GetDomain, _In_ const OrtNode* node, _Outptr_ const char** domain_name);

   








  ORT_API2_STATUS(Node_GetSinceVersion, _In_ const OrtNode* node, _Out_ int* since_version);

   








  ORT_API2_STATUS(Node_GetNumInputs, _In_ const OrtNode* node, _Out_ size_t* num_inputs);

   











  ORT_API2_STATUS(Node_GetInputs, _In_ const OrtNode* node,
                  _Out_writes_(num_inputs) const OrtValueInfo** inputs, _In_ size_t num_inputs);

   








  ORT_API2_STATUS(Node_GetNumOutputs, _In_ const OrtNode* node, _Out_ size_t* num_outputs);

   











  ORT_API2_STATUS(Node_GetOutputs, _In_ const OrtNode* node,
                  _Out_writes_(num_outputs) const OrtValueInfo** outputs, _In_ size_t num_outputs);

   












  ORT_API2_STATUS(Node_GetNumImplicitInputs, _In_ const OrtNode* node, _Out_ size_t* num_implicit_inputs);

   
















  ORT_API2_STATUS(Node_GetImplicitInputs, _In_ const OrtNode* node,
                  _Out_writes_(num_implicit_inputs) const OrtValueInfo** implicit_inputs,
                  _In_ size_t num_implicit_inputs);

   








  ORT_API2_STATUS(Node_GetNumAttributes, _In_ const OrtNode* node, _Out_ size_t* num_attributes);

   
















  ORT_API2_STATUS(Node_GetAttributes, _In_ const OrtNode* node,
                  _Out_writes_(num_attributes) const OrtOpAttr** attributes, _In_ size_t num_attributes);

   

















  ORT_API2_STATUS(Node_GetAttributeByName, _In_ const OrtNode* node, _In_ const char* attribute_name,
                  _Outptr_result_maybenull_ const OrtOpAttr** attribute);

   









  ORT_API2_STATUS(OpAttr_GetTensorAttributeAsOrtValue, _In_ const OrtOpAttr* attribute,
                  _Outptr_result_maybenull_ OrtValue** attr_tensor);

   








  ORT_API2_STATUS(OpAttr_GetType, _In_ const OrtOpAttr* attribute, _Out_ OrtOpAttrType* type);

   








  ORT_API2_STATUS(OpAttr_GetName, _In_ const OrtOpAttr* attribute, _Outptr_ const char** name);

   










  ORT_API2_STATUS(Node_GetNumSubgraphs, _In_ const OrtNode* node, _Out_ size_t* num_subgraphs);

   
















  ORT_API2_STATUS(Node_GetSubgraphs, _In_ const OrtNode* node,
                  _Out_writes_(num_subgraphs) const OrtGraph** subgraphs, _In_ size_t num_subgraphs,
                  _Out_writes_opt_(num_subgraphs) const char** attribute_names);

   











  ORT_API2_STATUS(Node_GetGraph, _In_ const OrtNode* node, _Outptr_result_maybenull_ const OrtGraph** graph);

   










  ORT_API2_STATUS(Node_GetEpName, _In_ const OrtNode* node, _Outptr_result_maybenull_ const char** out);

  

  
  

   





  ORT_CLASS_RELEASE(ExternalInitializerInfo);

   










  ORT_API_T(const ORTCHAR_T*, ExternalInitializerInfo_GetFilePath, _In_ const OrtExternalInitializerInfo* info);

   






  ORT_API_T(int64_t, ExternalInitializerInfo_GetFileOffset, _In_ const OrtExternalInitializerInfo* info);

   






  ORT_API_T(size_t, ExternalInitializerInfo_GetByteSize, _In_ const OrtExternalInitializerInfo* info);

  

  
  

   













  ORT_API_T(const char*, GetRunConfigEntry, _In_ const OrtRunOptions* options,
            _In_z_ const char* config_key);

  

   








  ORT_API_T(const OrtMemoryInfo*, EpDevice_MemoryInfo, _In_ const OrtEpDevice* ep_device,
            _In_ OrtDeviceMemoryType memory_type);

   






















  ORT_API2_STATUS(CreateSharedAllocator, _In_ OrtEnv* env, _In_ const OrtEpDevice* ep_device,
                  _In_ OrtDeviceMemoryType mem_type, _In_ OrtAllocatorType allocator_type,
                  _In_opt_ const OrtKeyValuePairs* allocator_options,
                  _Outptr_opt_ OrtAllocator** allocator);

   

















  ORT_API2_STATUS(GetSharedAllocator, _In_ OrtEnv* env, _In_ const OrtMemoryInfo* mem_info,
                  _Outptr_result_maybenull_ OrtAllocator** allocator);

   












  ORT_API2_STATUS(ReleaseSharedAllocator, _In_ OrtEnv* env, _In_ const OrtEpDevice* ep_device,
                  _In_ OrtDeviceMemoryType mem_type);

   











  ORT_API2_STATUS(GetTensorData, _In_ const OrtValue* value, _Outptr_ const void** out);

   









  ORT_API2_STATUS(GetSessionOptionsConfigEntries, _In_ const OrtSessionOptions* options, _Outptr_ OrtKeyValuePairs** out);

   
















  ORT_API2_STATUS(SessionGetMemoryInfoForInputs, _In_ const OrtSession* session,
                  _Out_writes_(num_inputs) const OrtMemoryInfo** inputs_memory_info,
                  _In_ size_t num_inputs);

   


















  ORT_API2_STATUS(SessionGetMemoryInfoForOutputs, _In_ const OrtSession* session,
                  _Out_writes_(num_outputs) const OrtMemoryInfo** outputs_memory_info,
                  _In_ size_t num_outputs);

   























  ORT_API2_STATUS(SessionGetEpDeviceForInputs, _In_ const OrtSession* session,
                  _Out_writes_(num_inputs) const OrtEpDevice** inputs_ep_devices,
                  _In_ size_t num_inputs);

   














  ORT_API2_STATUS(CreateSyncStreamForEpDevice, _In_ const OrtEpDevice* ep_device,
                  _In_opt_ const OrtKeyValuePairs* stream_options,
                  _Outptr_ OrtSyncStream** stream);

   









  ORT_API_T(void*, SyncStream_GetHandle, _In_ OrtSyncStream* stream);

  ORT_CLASS_RELEASE(SyncStream);

   























  ORT_API2_STATUS(CopyTensors, _In_ const OrtEnv* env,
                  _In_reads_(num_tensors) const OrtValue* const* src_tensors,
                  _In_reads_(num_tensors) OrtValue* const* dst_tensors,
                  _In_opt_ OrtSyncStream* stream,
                  _In_ size_t num_tensors);

   








  ORT_API2_STATUS(Graph_GetModelMetadata, _In_ const OrtGraph* graph, _Outptr_ OrtModelMetadata** out);

   











  ORT_API2_STATUS(GetModelCompatibilityForEpDevices,
                  _In_reads_(num_ep_devices) const OrtEpDevice* const* ep_devices,
                  _In_ size_t num_ep_devices,
                  _In_ const char* compatibility_info,
                  _Out_ OrtCompiledModelCompatibility* out_status);

  
  

   











  ORT_API2_STATUS(CreateExternalInitializerInfo, _In_ const ORTCHAR_T* filepath, _In_ int64_t file_offset,
                  _In_ size_t byte_size, _Outptr_ OrtExternalInitializerInfo** out);

  
};

 














typedef enum OrtCustomOpInputOutputCharacteristic {
  INPUT_OUTPUT_REQUIRED = 0,
  INPUT_OUTPUT_OPTIONAL,
  INPUT_OUTPUT_VARIADIC,
} OrtCustomOpInputOutputCharacteristic;

 



struct OrtCustomOp {
  uint32_t version;  

  
  
  
  
  void*(ORT_API_CALL* CreateKernel)(_In_ const struct OrtCustomOp* op, _In_ const OrtApi* api,
                                    _In_ const OrtKernelInfo* info);

  
  const char*(ORT_API_CALL* GetName)(_In_ const struct OrtCustomOp* op);

  
  const char*(ORT_API_CALL* GetExecutionProviderType)(_In_ const struct OrtCustomOp* op);

  
  ONNXTensorElementDataType(ORT_API_CALL* GetInputType)(_In_ const struct OrtCustomOp* op, _In_ size_t index);
  size_t(ORT_API_CALL* GetInputTypeCount)(_In_ const struct OrtCustomOp* op);
  ONNXTensorElementDataType(ORT_API_CALL* GetOutputType)(_In_ const struct OrtCustomOp* op, _In_ size_t index);
  size_t(ORT_API_CALL* GetOutputTypeCount)(_In_ const struct OrtCustomOp* op);

  
  
  
  void(ORT_API_CALL* KernelCompute)(_In_ void* op_kernel, _In_ OrtKernelContext* context);
  void(ORT_API_CALL* KernelDestroy)(_In_ void* op_kernel);

  
  OrtCustomOpInputOutputCharacteristic(ORT_API_CALL* GetInputCharacteristic)(_In_ const struct OrtCustomOp* op, _In_ size_t index);
  OrtCustomOpInputOutputCharacteristic(ORT_API_CALL* GetOutputCharacteristic)(_In_ const struct OrtCustomOp* op, _In_ size_t index);

  
  
  
  
  
  OrtMemType(ORT_API_CALL* GetInputMemoryType)(_In_ const struct OrtCustomOp* op, _In_ size_t index);

  
  
  int(ORT_API_CALL* GetVariadicInputMinArity)(_In_ const struct OrtCustomOp* op);

  
  
  
  int(ORT_API_CALL* GetVariadicInputHomogeneity)(_In_ const struct OrtCustomOp* op);

  
  
  int(ORT_API_CALL* GetVariadicOutputMinArity)(_In_ const struct OrtCustomOp* op);

  
  
  
  int(ORT_API_CALL* GetVariadicOutputHomogeneity)(_In_ const struct OrtCustomOp* op);

  
  OrtStatusPtr(ORT_API_CALL* CreateKernelV2)(_In_ const struct OrtCustomOp* op, _In_ const OrtApi* api,
                                             _In_ const OrtKernelInfo* info,
                                             _Out_ void** kernel);

  
  OrtStatusPtr(ORT_API_CALL* KernelComputeV2)(_In_ void* op_kernel, _In_ OrtKernelContext* context);

  OrtStatusPtr(ORT_API_CALL* InferOutputShapeFn)(_In_ const struct OrtCustomOp* op, _In_ OrtShapeInferContext*);

  
  int(ORT_API_CALL* GetStartVersion)(_In_ const struct OrtCustomOp* op);
  int(ORT_API_CALL* GetEndVersion)(_In_ const struct OrtCustomOp* op);

  
  
  
  
  
  size_t(ORT_API_CALL* GetMayInplace)(_Out_ int** input_index, _Out_ int** output_index);

  
  
  void(ORT_API_CALL* ReleaseMayInplace)(_Frees_ptr_opt_ int* input_index, _Frees_ptr_opt_ int* output_index);

  
  size_t(ORT_API_CALL* GetAliasMap)(_Out_ int** input_index, _Out_ int** output_index);
  void(ORT_API_CALL* ReleaseAliasMap)(_Frees_ptr_opt_ int* input_index, _Frees_ptr_opt_ int* output_index);
};

 



 






struct OrtModelEditorApi {
  
  
  
#if defined(ORT_MINIMAL_BUILD)
  const bool not_defined_in_this_build;
#else
   












  ORT_API2_STATUS(CreateTensorTypeInfo, _In_ const OrtTensorTypeAndShapeInfo* tensor_info,
                  _Outptr_ OrtTypeInfo** type_info);

   












  ORT_API2_STATUS(CreateSparseTensorTypeInfo, _In_ const OrtTensorTypeAndShapeInfo* tensor_info,
                  _Outptr_ OrtTypeInfo** type_info);

   













  ORT_API2_STATUS(CreateMapTypeInfo, ONNXTensorElementDataType map_key_type, _In_ const OrtTypeInfo* map_value_type,
                  _Outptr_ OrtTypeInfo** type_info);

   












  ORT_API2_STATUS(CreateSequenceTypeInfo, _In_ const OrtTypeInfo* sequence_type, _Outptr_ OrtTypeInfo** type_info);

   












  ORT_API2_STATUS(CreateOptionalTypeInfo, _In_ const OrtTypeInfo* contained_type, _Outptr_ OrtTypeInfo** type_info);

   









  ORT_API2_STATUS(CreateValueInfo, _In_ const char* name, _In_ const OrtTypeInfo* type_info,
                  _Outptr_ OrtValueInfo** value_info);

   




















  ORT_API2_STATUS(CreateNode, _In_ const char* operator_name, _In_ const char* domain_name, _In_ const char* node_name,
                  _In_reads_(input_names_len) const char* const* input_names, size_t input_names_len,
                  _In_reads_(output_names_len) const char* const* output_names, size_t output_names_len,
                  _In_reads_(attribs_len) _In_opt_ OrtOpAttr** attributes, _In_ size_t attribs_len,
                  _Outptr_ OrtNode** node);

   



  ORT_API2_STATUS(CreateGraph, _Outptr_ OrtGraph** graph);

   












  ORT_API2_STATUS(SetGraphInputs, _Inout_ OrtGraph* graph,
                  _In_reads_(inputs_len) _In_ OrtValueInfo** inputs, _In_ size_t inputs_len);

   












  ORT_API2_STATUS(SetGraphOutputs, _Inout_ OrtGraph* graph,
                  _In_reads_(outputs_len) _In_ OrtValueInfo** outputs, _In_ size_t outputs_len);

   





































  ORT_API2_STATUS(AddInitializerToGraph, _Inout_ OrtGraph* graph, _In_ const char* name, _In_ OrtValue* tensor,
                  bool data_is_external);

   










  ORT_API2_STATUS(AddNodeToGraph, _Inout_ OrtGraph* graph, _In_ OrtNode* node);

   

















  ORT_API2_STATUS(CreateModel,
                  _In_reads_(opset_entries_len) const char* const* domain_names,
                  _In_reads_(opset_entries_len) const int* opset_versions,
                  size_t opset_entries_len,
                  _Outptr_ OrtModel** model);

   












  ORT_API2_STATUS(AddGraphToModel, _Inout_ OrtModel* model, _In_ OrtGraph* graph);

   

















  ORT_API2_STATUS(CreateSessionFromModel, _In_ const OrtEnv* env, _In_ const OrtModel* model,
                  _In_ const OrtSessionOptions* options, _Outptr_ OrtSession** out);

   





















  ORT_API2_STATUS(CreateModelEditorSession, _In_ const OrtEnv* env, _In_ const ORTCHAR_T* model_path,
                  _In_ const OrtSessionOptions* options,
                  _Outptr_ OrtSession** out);

   























  ORT_API2_STATUS(CreateModelEditorSessionFromArray, _In_ const OrtEnv* env,
                  _In_ const void* model_data, size_t model_data_length,
                  _In_ const OrtSessionOptions* options,
                  _Outptr_ OrtSession** out);

   













  ORT_API2_STATUS(SessionGetOpsetForDomain, _In_ const OrtSession* session, _In_ const char* domain, _Out_ int* opset);

   

















  ORT_API2_STATUS(ApplyModelToModelEditorSession, _Inout_ OrtSession* session, _In_ OrtModel* model);

   












  ORT_API2_STATUS(FinalizeModelEditorSession, _Inout_ OrtSession* session, _In_ const OrtSessionOptions* options,
                  _In_opt_ OrtPrepackedWeightsContainer* prepacked_weights_container);
#endif  
};

 



 

typedef enum OrtCompileApiFlags {
  
  OrtCompileApiFlags_NONE = 0,

  
  
  OrtCompileApiFlags_ERROR_IF_NO_NODES_COMPILED = 1 << 0,

  
  
  OrtCompileApiFlags_ERROR_IF_OUTPUT_FILE_EXISTS = 1 << 1,
} OrtCompileApiFlags;

 






















struct OrtCompileApi {
  
  
  ORT_CLASS_RELEASE(ModelCompilationOptions);

   

















  ORT_API2_STATUS(CreateModelCompilationOptionsFromSessionOptions, _In_ const OrtEnv* env,
                  _In_ const OrtSessionOptions* session_options, _Outptr_ OrtModelCompilationOptions** out);

   











  ORT_API2_STATUS(ModelCompilationOptions_SetInputModelPath, _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ const ORTCHAR_T* input_model_path);

   












  ORT_API2_STATUS(ModelCompilationOptions_SetInputModelFromBuffer,
                  _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ const void* input_model_data,
                  size_t input_model_data_size);

   
















  ORT_API2_STATUS(ModelCompilationOptions_SetOutputModelPath, _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ const ORTCHAR_T* output_model_path);

   














  ORT_API2_STATUS(ModelCompilationOptions_SetOutputModelExternalInitializersFile,
                  _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ const ORTCHAR_T* external_initializers_file_path,
                  size_t external_initializers_size_threshold);

   




















  ORT_API2_STATUS(ModelCompilationOptions_SetOutputModelBuffer,
                  _In_ OrtModelCompilationOptions* model_compile_options,
                  _Inout_ OrtAllocator* allocator,
                  _Outptr_ void** output_model_buffer_ptr,
                  _Out_ size_t* output_model_buffer_size_ptr);

   





















  ORT_API2_STATUS(ModelCompilationOptions_SetEpContextEmbedMode, _In_ OrtModelCompilationOptions* model_compile_options,
                  bool embed_ep_context_in_model);

   








  ORT_API2_STATUS(CompileModel, _In_ const OrtEnv* env, _In_ const OrtModelCompilationOptions* model_options);

   








  ORT_API2_STATUS(ModelCompilationOptions_SetFlags, _In_ OrtModelCompilationOptions* model_compile_options,
                  uint32_t flags);

   












  ORT_API2_STATUS(ModelCompilationOptions_SetEpContextBinaryInformation,
                  _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ const ORTCHAR_T* output_directory,
                  _In_ const ORTCHAR_T* model_name);

   








  ORT_API2_STATUS(ModelCompilationOptions_SetGraphOptimizationLevel,
                  _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ GraphOptimizationLevel graph_optimization_level);

   
















  ORT_API2_STATUS(ModelCompilationOptions_SetOutputModelWriteFunc,
                  _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ OrtWriteBufferFunc write_func, _In_ void* state);

   











  ORT_API2_STATUS(ModelCompilationOptions_SetOutputModelGetInitializerLocationFunc,
                  _In_ OrtModelCompilationOptions* model_compile_options,
                  _In_ OrtGetInitializerLocationFunc get_initializer_location_func, _In_ void* state);
};

 





ORT_API_STATUS(OrtSessionOptionsAppendExecutionProvider_CUDA, _In_ OrtSessionOptions* options, int device_id);

 







ORT_API_STATUS(OrtSessionOptionsAppendExecutionProvider_ROCM, _In_ OrtSessionOptions* options, int device_id);

 







ORT_API_STATUS(OrtSessionOptionsAppendExecutionProvider_MIGraphX, _In_ OrtSessionOptions* options, int device_id);

 







ORT_API_STATUS(OrtSessionOptionsAppendExecutionProvider_Dnnl, _In_ OrtSessionOptions* options, int use_arena);

 





ORT_API_STATUS(OrtSessionOptionsAppendExecutionProvider_Tensorrt, _In_ OrtSessionOptions* options, int device_id);

#ifdef __cplusplus
}
#endif


#include "onnxruntime_ep_c_api.h"

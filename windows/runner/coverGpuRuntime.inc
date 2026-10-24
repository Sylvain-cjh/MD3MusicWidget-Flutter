
class CoverGpuContext {
 public:
  ComPtr<ID3D12Device> device;
  ComPtr<ID3D12CommandQueue> queue;
  ComPtr<ID3D12CommandAllocator> allocator;
  ComPtr<ID3D12GraphicsCommandList> list;
  ComPtr<ID3D12Fence> fence;
  ComPtr<ID3D12RootSignature> root;
  ComPtr<ID3D12DescriptorHeap> heap;
  std::map<std::string, ComPtr<ID3D12PipelineState>> pipelines;
  std::string adapter;
  bool integrated = false;
  HANDLE event = nullptr;
  UINT64 serial = 0;
  UINT descriptor_size = 0;
  Buffer source, input, mask, stats, seeds[2], refined[2], confidence, body_anchor, filled[2], presence[2], final_mask, background;
  Buffer actors, objects, text_areas, subject_labels, component_info, text_fill, priority, text_repair;
  bool scene_ready=false;
  UINT width, height, out_width, out_height;
  static constexpr UINT grid_side = 512;
  UINT model_side = 512, model_kind = 1, model_channels = 1;
  UINT inference_flip = 0;
  UINT refinement_mode = 0;
  float inference_crop[4] = {0,0,1,1};

  CoverGpuContext(UINT w, UINT h, UINT ow, UINT oh, bool subject_draft=false) : width(w), height(h), out_width(ow), out_height(oh) {
    
    
    bool prefer_discrete = false;
#ifdef COVER_DEV_DISCRETE_DRAFTS
    prefer_discrete = subject_draft;
#else
    (void)subject_draft;
#endif
    ComPtr<IDXGIFactory6> factory;
    Check(CreateDXGIFactory2(0, IID_PPV_ARGS(&factory)), "dxgi_factory");
    ComPtr<ID3D12Device> integrated_fallback;
    std::string integrated_name;
    ComPtr<IDXCoreAdapterFactory> core_factory;
    const HRESULT core_result = DXCoreCreateAdapterFactory(IID_PPV_ARGS(&core_factory));
    for (UINT index = 0;; ++index) {
      ComPtr<IDXGIAdapter1> candidate;
      HRESULT enumerated = factory->EnumAdapterByGpuPreference(index,
          DXGI_GPU_PREFERENCE_MINIMUM_POWER, IID_PPV_ARGS(&candidate));
      if (enumerated == DXGI_ERROR_NOT_FOUND) break;
      if (FAILED(enumerated)) {
        enumerated = factory->EnumAdapters1(index, &candidate);
        if (enumerated == DXGI_ERROR_NOT_FOUND) break;
        Check(enumerated, "enumerate_gpu_adapters");
      }
      DXGI_ADAPTER_DESC1 description = {};
      Check(candidate->GetDesc1(&description), "adapter_description");
      if (description.Flags & DXGI_ADAPTER_FLAG_SOFTWARE) continue;
      bool reported_integrated = false, has_integrated_property = false;
      if (SUCCEEDED(core_result)) {
        ComPtr<IDXCoreAdapter> core_adapter;
        if (SUCCEEDED(core_factory->GetAdapterByLuid(description.AdapterLuid,
            IID_PPV_ARGS(&core_adapter))) &&
            core_adapter->IsPropertySupported(DXCoreAdapterProperty::IsIntegrated)) {
          has_integrated_property = SUCCEEDED(core_adapter->GetProperty(
              DXCoreAdapterProperty::IsIntegrated, &reported_integrated));
        }
      }
      if (has_integrated_property && !reported_integrated && !prefer_discrete) continue;
      ComPtr<ID3D12Device> possible;
      if (FAILED(D3D12CreateDevice(candidate.Get(), D3D_FEATURE_LEVEL_11_0,
          IID_PPV_ARGS(&possible)))) continue;
      D3D12_FEATURE_DATA_ARCHITECTURE architecture = {};
      const bool uma = SUCCEEDED(possible->CheckFeatureSupport(D3D12_FEATURE_ARCHITECTURE,
          &architecture, sizeof(architecture))) && architecture.UMA;
      const bool is_integrated = has_integrated_property ? reported_integrated : uma;
      if (!is_integrated) {
        if (prefer_discrete) {
          device = possible; adapter = Utf8(description.Description); break;
        }
        continue;
      }
      if (is_integrated) {
        if (prefer_discrete) {
          if (!integrated_fallback) {
            integrated_fallback = possible; integrated_name = Utf8(description.Description);
          }
        } else {
          device = possible; adapter = Utf8(description.Description); integrated = true; break;
        }
      }
    }
    if (!device && integrated_fallback) {
      device = integrated_fallback; adapter = integrated_name; integrated = true;
    }
    if (!device) throw std::runtime_error("integrated_gpu_unavailable_no_discrete_or_cpu_fallback");
    D3D12_COMMAND_QUEUE_DESC queue_desc = {};
    queue_desc.Type = D3D12_COMMAND_LIST_TYPE_DIRECT;
    Check(device->CreateCommandQueue(&queue_desc, IID_PPV_ARGS(&queue)), "gpu_queue");
    Check(device->CreateCommandAllocator(D3D12_COMMAND_LIST_TYPE_DIRECT,
        IID_PPV_ARGS(&allocator)), "gpu_allocator");
    Check(device->CreateCommandList(0, D3D12_COMMAND_LIST_TYPE_DIRECT,
        allocator.Get(), nullptr, IID_PPV_ARGS(&list)), "gpu_list");
    Check(list->Close(), "close_initial_list");
    Check(device->CreateFence(0, D3D12_FENCE_FLAG_NONE, IID_PPV_ARGS(&fence)), "gpu_fence");
    D3D12_DESCRIPTOR_RANGE ranges[2] = {};
    ranges[0].RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_SRV; ranges[0].NumDescriptors = 11;
    ranges[1].RangeType = D3D12_DESCRIPTOR_RANGE_TYPE_UAV; ranges[1].NumDescriptors = 13;
    D3D12_ROOT_PARAMETER parameters[3] = {};
    parameters[0].ParameterType = D3D12_ROOT_PARAMETER_TYPE_32BIT_CONSTANTS;
    parameters[0].Constants.Num32BitValues = 16;
    for (int i = 0; i < 2; ++i) {
      parameters[i + 1].ParameterType = D3D12_ROOT_PARAMETER_TYPE_DESCRIPTOR_TABLE;
      parameters[i + 1].DescriptorTable.NumDescriptorRanges = 1;
      parameters[i + 1].DescriptorTable.pDescriptorRanges = &ranges[i];
    }
    D3D12_ROOT_SIGNATURE_DESC signature = {};
    signature.NumParameters = 3; signature.pParameters = parameters;
    ComPtr<ID3DBlob> serialized, error;
    Check(D3D12SerializeRootSignature(&signature, D3D_ROOT_SIGNATURE_VERSION_1,
        &serialized, &error), "serialize_gpu_root");
    Check(device->CreateRootSignature(0, serialized->GetBufferPointer(),
        serialized->GetBufferSize(), IID_PPV_ARGS(&root)), "gpu_root");
    D3D12_DESCRIPTOR_HEAP_DESC heap_desc = {};
    heap_desc.Type = D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV;
    heap_desc.NumDescriptors = 24; heap_desc.Flags = D3D12_DESCRIPTOR_HEAP_FLAG_SHADER_VISIBLE;
    Check(device->CreateDescriptorHeap(&heap_desc, IID_PPV_ARGS(&heap)), "gpu_heap");
    descriptor_size = device->GetDescriptorHandleIncrementSize(heap_desc.Type);
    source = Create(static_cast<UINT64>(w) * h * 4);
    input = Create(grid_side * grid_side * 3 * sizeof(float));
    mask = Create(grid_side * grid_side * 2 * sizeof(float));
    stats = Create(64);
    seeds[0] = Create(grid_side * grid_side * 4); seeds[1] = Create(grid_side * grid_side * 4);
    refined[0] = Create(seeds[0].bytes); refined[1] = Create(seeds[0].bytes);
    confidence = Create(seeds[0].bytes);
    filled[0] = Create(seeds[0].bytes); filled[1] = Create(seeds[0].bytes);
    final_mask = Create(static_cast<UINT64>(ow) * oh * 4);
    background = Create(final_mask.bytes);
    event = CreateEventW(nullptr, FALSE, FALSE, nullptr);
    if (!event) throw std::runtime_error("gpu_event_failed");
  }
  ~CoverGpuContext() { if (event) CloseHandle(event); }
  void EnsureScene() {
    if(scene_ready) return;
    actors=Create(seeds[0].bytes); objects=Create(seeds[0].bytes);
    text_areas=Create(seeds[0].bytes); subject_labels=Create(seeds[0].bytes);
    text_fill=Create(seeds[0].bytes); component_info=Create(seeds[0].bytes*4);
    priority=Create(final_mask.bytes); text_repair=Create(final_mask.bytes);
    scene_ready=true;
  }
  void EnsureModelCapacity(UINT side) {
    const UINT64 plane=static_cast<UINT64>(side)*side*sizeof(float);
    if(input.bytes<plane*3) input=Create(plane*3);
    if(mask.bytes<plane*2) mask=Create(plane*2);
  }


  Buffer Create(UINT64 bytes, D3D12_HEAP_TYPE type = D3D12_HEAP_TYPE_DEFAULT) {
    Buffer buffer; buffer.bytes = bytes;
    buffer.state = type == D3D12_HEAP_TYPE_UPLOAD ? D3D12_RESOURCE_STATE_GENERIC_READ :
        type == D3D12_HEAP_TYPE_READBACK ? D3D12_RESOURCE_STATE_COPY_DEST :
        D3D12_RESOURCE_STATE_UNORDERED_ACCESS;
    D3D12_HEAP_PROPERTIES properties = {}; properties.Type = type;
    D3D12_RESOURCE_DESC desc = {};
    desc.Dimension = D3D12_RESOURCE_DIMENSION_BUFFER; desc.Width = bytes;
    desc.Height = 1; desc.DepthOrArraySize = 1; desc.MipLevels = 1;
    desc.SampleDesc.Count = 1; desc.Layout = D3D12_TEXTURE_LAYOUT_ROW_MAJOR;
    desc.Flags = type == D3D12_HEAP_TYPE_DEFAULT ? D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS : D3D12_RESOURCE_FLAG_NONE;
    Check(device->CreateCommittedResource(&properties, D3D12_HEAP_FLAG_NONE,
        &desc, buffer.state, nullptr, IID_PPV_ARGS(&buffer.resource)), "gpu_buffer");
    return buffer;
  }
  void Begin() {
    Check(allocator->Reset(), "reset_gpu_allocator");
    Check(list->Reset(allocator.Get(), nullptr), "reset_gpu_list");
  }
  void Transition(Buffer& buffer, D3D12_RESOURCE_STATES state) {
    if (buffer.state == state) return;
    D3D12_RESOURCE_BARRIER barrier = {};
    barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_TRANSITION;
    barrier.Transition.pResource = buffer.resource.Get();
    barrier.Transition.StateBefore = buffer.state; barrier.Transition.StateAfter = state;
    barrier.Transition.Subresource = D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES;
    list->ResourceBarrier(1, &barrier); buffer.state = state;
  }
  void Sync() {
    Check(queue->Signal(fence.Get(), ++serial), "signal_gpu_fence");
    if (fence->GetCompletedValue() >= serial) return;
    Check(fence->SetEventOnCompletion(serial, event), "gpu_completion");
    const DWORD waited = WaitForSingleObject(event, 30000);
    if (waited != WAIT_OBJECT_0) throw std::runtime_error("gpu_timeout");
  }
  void Submit() {
    Check(list->Close(), "close_gpu_list");
    ID3D12CommandList* commands[] = {list.Get()};
    queue->ExecuteCommandLists(1, commands); Sync();
  }
  void Upload(Buffer& buffer, const void* bytes) {
    auto upload = Create(buffer.bytes, D3D12_HEAP_TYPE_UPLOAD);
    void* mapped = nullptr; D3D12_RANGE no_read = {0, 0};
    Check(upload.resource->Map(0, &no_read, &mapped), "map_upload");
    memcpy(mapped, bytes, static_cast<size_t>(buffer.bytes)); upload.resource->Unmap(0, nullptr);
    Begin(); Transition(buffer, D3D12_RESOURCE_STATE_COPY_DEST);
    list->CopyBufferRegion(buffer.resource.Get(), 0, upload.resource.Get(), 0, buffer.bytes);
    Transition(buffer, D3D12_RESOURCE_STATE_UNORDERED_ACCESS); Submit();
  }
  void Read(Buffer& buffer, void* bytes) {
    auto readback = Create(buffer.bytes, D3D12_HEAP_TYPE_READBACK);
    Begin(); const auto previous = buffer.state;
    Transition(buffer, D3D12_RESOURCE_STATE_COPY_SOURCE);
    list->CopyBufferRegion(readback.resource.Get(), 0, buffer.resource.Get(), 0, buffer.bytes);
    Transition(buffer, previous); Submit();
    void* mapped = nullptr; D3D12_RANGE range = {0, static_cast<SIZE_T>(buffer.bytes)};
    Check(readback.resource->Map(0, &range, &mapped), "map_readback");
    memcpy(bytes, mapped, static_cast<size_t>(buffer.bytes));
    D3D12_RANGE no_write = {0, 0}; readback.resource->Unmap(0, &no_write);
  }
  void Copy(Buffer& from, Buffer& to) {
    Begin(); const auto before=from.state;
    Transition(from,D3D12_RESOURCE_STATE_COPY_SOURCE);
    Transition(to,D3D12_RESOURCE_STATE_COPY_DEST);
    list->CopyBufferRegion(to.resource.Get(),0,from.resource.Get(),0,to.bytes);
    Transition(from,before); Transition(to,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    Submit();
  }
  void Srv(UINT index, Buffer& buffer, bool raw) {
    D3D12_SHADER_RESOURCE_VIEW_DESC desc = {};
    desc.ViewDimension = D3D12_SRV_DIMENSION_BUFFER;
    desc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    desc.Format = raw ? DXGI_FORMAT_R32_TYPELESS : DXGI_FORMAT_UNKNOWN;
    desc.Buffer.NumElements = static_cast<UINT>(buffer.bytes / 4);
    desc.Buffer.StructureByteStride = raw ? 0 : 4;
    desc.Buffer.Flags = raw ? D3D12_BUFFER_SRV_FLAG_RAW : D3D12_BUFFER_SRV_FLAG_NONE;
    auto handle = heap->GetCPUDescriptorHandleForHeapStart(); handle.ptr += index * descriptor_size;
    device->CreateShaderResourceView(buffer.resource.Get(), &desc, handle);
  }
  void Uav(UINT index, Buffer& buffer, bool raw) {
    D3D12_UNORDERED_ACCESS_VIEW_DESC desc = {};
    desc.ViewDimension = D3D12_UAV_DIMENSION_BUFFER;
    desc.Format = raw ? DXGI_FORMAT_R32_TYPELESS : DXGI_FORMAT_UNKNOWN;
    desc.Buffer.NumElements = static_cast<UINT>(buffer.bytes / 4);
    desc.Buffer.StructureByteStride = raw ? 0 : 4;
    desc.Buffer.Flags = raw ? D3D12_BUFFER_UAV_FLAG_RAW : D3D12_BUFFER_UAV_FLAG_NONE;
    auto handle = heap->GetCPUDescriptorHandleForHeapStart(); handle.ptr += index * descriptor_size;
    device->CreateUnorderedAccessView(buffer.resource.Get(), nullptr, &desc, handle);
  }
  void Dispatch(const char* entry, UINT x, UINT y, UINT seed_in = 0,
      UINT seed_out = 1, UINT step = 0, bool alpha = false,
      UINT refined_in = 0, UINT refined_out = 1, UINT filled_in = 0, UINT filled_out = 1,
      Buffer* detector_output = nullptr) {
    auto found = pipelines.find(entry);
    if (found == pipelines.end()) {
      const auto shader = Shader(entry);
      D3D12_COMPUTE_PIPELINE_STATE_DESC desc = {}; desc.pRootSignature = root.Get();
      desc.CS = {shader->GetBufferPointer(), shader->GetBufferSize()};
      ComPtr<ID3D12PipelineState> pipeline;
      const auto operation=std::string("gpu_pipeline:")+entry;
      Check(device->CreateComputePipelineState(&desc, IID_PPV_ARGS(&pipeline)), operation.c_str());
      found = pipelines.emplace(entry, pipeline).first;
    }
    auto& selected_mask = detector_output ? *detector_output : mask;
    Srv(0, source, true); Srv(1, selected_mask, false); Srv(2, seeds[seed_in], false);
    Srv(3, refined[refined_in], false); Srv(4, filled[filled_in], false);
    Uav(11, input, false); Uav(12, stats, true); Uav(13, seeds[seed_out], false);
    Uav(14, final_mask, false); Uav(15, background, false);
    Uav(16, refined[refined_out], false); Uav(17, filled[filled_out], false);
    if(scene_ready) {
      Srv(5,actors,false); Srv(6,objects,false); Srv(7,text_areas,false);
      Srv(8,subject_labels,false); Srv(9,component_info,true); Srv(10,text_fill,false);
      Uav(18,priority,false); Uav(19,text_repair,false);
      Uav(20,actors,false); Uav(21,objects,false); Uav(22,text_areas,false);
      Uav(23,component_info,true);
    }
    Begin(); Transition(source, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    Transition(selected_mask, D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    Transition(seeds[seed_in], D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    if (selected_mask.resource.Get()!=seeds[seed_out].resource.Get()) {
      Transition(seeds[seed_out], D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    }
    Transition(input, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    Transition(refined[refined_in], D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    Transition(refined[refined_out], D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    Transition(filled[filled_in], D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    Transition(filled[filled_out], D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    if(scene_ready) {
      const std::string kernel=entry;
      Transition(actors,(kernel=="SceneInit") ? D3D12_RESOURCE_STATE_UNORDERED_ACCESS : D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
      Transition(objects,(kernel=="SceneInit" || kernel=="StoreObjects" || kernel=="RemoveTextObjects") ? D3D12_RESOURCE_STATE_UNORDERED_ACCESS : D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
      Transition(text_areas,(kernel=="SceneInit" || kernel=="StoreText" || kernel=="ClearText") ? D3D12_RESOURCE_STATE_UNORDERED_ACCESS : D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
      Transition(subject_labels,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
      Transition(text_fill,D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
      Transition(component_info,(kernel=="SceneComponentsClear" || kernel=="SceneComponentsCount" || kernel=="InkHistogramClear" || kernel=="InkHistogram") ? D3D12_RESOURCE_STATE_UNORDERED_ACCESS : D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
    }
    UINT config[16] = {width, height, out_width, out_height, step, alpha ? 1u : 0u,
        model_side, grid_side, model_kind, model_channels, inference_flip, refinement_mode};
    memcpy(config+12,inference_crop,sizeof(inference_crop));
    ID3D12DescriptorHeap* heaps[] = {heap.Get()}; list->SetDescriptorHeaps(1, heaps);
    list->SetComputeRootSignature(root.Get()); list->SetPipelineState(found->second.Get());
    list->SetComputeRoot32BitConstants(0, 16, config, 0);
    auto gpu_handle = heap->GetGPUDescriptorHandleForHeapStart();
    list->SetComputeRootDescriptorTable(1, gpu_handle);
    gpu_handle.ptr += 11 * descriptor_size; list->SetComputeRootDescriptorTable(2, gpu_handle);
    list->Dispatch((x + 15) / 16, (y + 15) / 16, 1);
    D3D12_RESOURCE_BARRIER barrier = {}; barrier.Type = D3D12_RESOURCE_BARRIER_TYPE_UAV;
    list->ResourceBarrier(1, &barrier); Submit();
  }
};

struct OrtSessionState {
  CoverGpuContext* context = nullptr;
  HMODULE library = nullptr, directml_library = nullptr;
  const OrtApi* api = nullptr;
  const OrtDmlApi* dml = nullptr;
  OrtEnv* env = nullptr; OrtSessionOptions* options = nullptr;
  OrtSession* session = nullptr; OrtMemoryInfo* memory = nullptr;
  OrtValue* input = nullptr; OrtValue* output = nullptr;
  OrtValue* extra_outputs[2] = {};
  OrtAllocator* allocator = nullptr;
  void* input_allocation = nullptr; void* output_allocation = nullptr;
  void* extra_allocations[2] = {};
  char* input_name = nullptr; char* output_name = nullptr;
  char* extra_names[2] = {};
  ComPtr<IDMLDevice> device;
  void Repeat(CoverGpuContext& gpu) {
    if (!session || gpu.model_kind==4) throw std::runtime_error("invalid_refinement_session");
    gpu.Begin(); gpu.Transition(gpu.input,D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    gpu.Transition(gpu.mask,D3D12_RESOURCE_STATE_UNORDERED_ACCESS); gpu.Submit();
    const OrtValue* inputs[] = {input};
    const char* names[] = {input_name}, *outputs[] = {output_name};
    CheckStatus(api->Run(session,nullptr,names,inputs,1,outputs,1,&output));
    gpu.Sync();
  }
  ~OrtSessionState() {
    
    
    try { if(context) context->Sync(); } catch(const std::exception&) {}
    if (api) {
      if (input_name && allocator) allocator->Free(allocator, input_name);
      if (output_name && allocator) allocator->Free(allocator, output_name);
      for (auto name : extra_names) if (name && allocator) allocator->Free(allocator, name);
      if (output) api->ReleaseValue(output);
      for (auto value : extra_outputs) if (value) api->ReleaseValue(value);
      if (input) api->ReleaseValue(input);
      if (session) api->ReleaseSession(session);
      if (input_allocation) { auto status = dml->FreeGPUAllocation(input_allocation); if (status) api->ReleaseStatus(status); }
      if (output_allocation) { auto status = dml->FreeGPUAllocation(output_allocation); if (status) api->ReleaseStatus(status); }
      for (auto allocation : extra_allocations) if (allocation) {
        auto status = dml->FreeGPUAllocation(allocation); if (status) api->ReleaseStatus(status);
      }
      if (memory) api->ReleaseMemoryInfo(memory);
      if (options) api->ReleaseSessionOptions(options);
      if (env) api->ReleaseEnv(env);
    }
    device.Reset();
  }
  void CheckStatus(OrtStatus* status) {
    if (!status) return;
    const std::string detail = api->GetErrorMessage(status);
    api->ReleaseStatus(status); throw std::runtime_error(detail);
  }
  void Run(const std::filesystem::path& root_path, const wchar_t* filename, CoverGpuContext& gpu) {
    context=&gpu;
    const auto modules = Modules(root_path);
    library = modules.ort; directml_library = modules.dml;
    using GetApiBase = const OrtApiBase*(ORT_API_CALL*)();
    auto base = reinterpret_cast<GetApiBase>(GetProcAddress(library, "OrtGetApiBase"));
    if (!base || !(api = base()->GetApi(ORT_API_VERSION))) throw std::runtime_error("ort_api_missing");
    const void* provider = nullptr;
    CheckStatus(api->GetExecutionProviderApi("DML", ORT_API_VERSION, &provider));
    dml = static_cast<const OrtDmlApi*>(provider);
    using CreateDml = HRESULT(WINAPI*)(ID3D12Device*, DML_CREATE_DEVICE_FLAGS, REFIID, void**);
    auto create = reinterpret_cast<CreateDml>(GetProcAddress(directml_library, "DMLCreateDevice"));
    if (!create) throw std::runtime_error("directml_device_api_missing");
    Check(create(gpu.device.Get(), DML_CREATE_DEVICE_FLAG_NONE, IID_PPV_ARGS(&device)), "directml_device");
    CheckStatus(api->CreateEnv(ORT_LOGGING_LEVEL_ERROR, "cover_gpu", &env));
    CheckStatus(api->DisableTelemetryEvents(env));
    CheckStatus(api->CreateSessionOptions(&options));
    CheckStatus(api->DisableMemPattern(options));
    CheckStatus(api->SetSessionExecutionMode(options, ORT_SEQUENTIAL));
    CheckStatus(api->SetIntraOpNumThreads(options, 1));
    CheckStatus(api->SetInterOpNumThreads(options, 1));
    CheckStatus(api->AddSessionConfigEntry(options, "session.intra_op.allow_spinning", "0"));
    CheckStatus(api->AddSessionConfigEntry(options, "session.inter_op.allow_spinning", "0"));
    CheckStatus(api->AddSessionConfigEntry(options, "session.disable_cpu_ep_fallback", "1"));
    if(gpu.model_kind==6) {
      
      
      
      CheckStatus(api->AddSessionConfigEntry(options, "ep.dml.disable_graph_fusion", "1"));
    }
    CheckStatus(dml->SessionOptionsAppendExecutionProvider_DML1(options, device.Get(), gpu.queue.Get()));
    const auto model = root_path / filename;
    try {
      CheckStatus(api->CreateSession(env, model.c_str(), options, &session));
    } catch (const std::exception& error) {
      throw std::runtime_error(Utf8(filename) + ":" + error.what());
    }
    CheckStatus(api->GetAllocatorWithDefaultOptions(&allocator));
    CheckStatus(api->SessionGetInputName(session, 0, allocator, &input_name));
    CheckStatus(api->SessionGetOutputName(session, 0, allocator, &output_name));
    CheckStatus(api->CreateMemoryInfo("DML", OrtDeviceAllocator, 0, OrtMemTypeDefault, &memory));
    CheckStatus(dml->CreateGPUAllocationFromD3DResource(gpu.input.resource.Get(), &input_allocation));
    CheckStatus(dml->CreateGPUAllocationFromD3DResource(gpu.mask.resource.Get(), &output_allocation));
    const int64_t input_shape[] = {1, 3, gpu.model_side, gpu.model_side};
    const int64_t output_shape[] = {1, gpu.model_channels, gpu.model_side, gpu.model_side};
    const int64_t person_shape[] = {1, 2704, 80};
    CheckStatus(api->CreateTensorWithDataAsOrtValue(memory, input_allocation,
        static_cast<size_t>(gpu.input.bytes), input_shape, 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &input));
    CheckStatus(api->CreateTensorWithDataAsOrtValue(memory, output_allocation,
        static_cast<size_t>(gpu.mask.bytes), gpu.model_kind == 4 ? person_shape : output_shape,
        gpu.model_kind == 4 ? 3 : 4, ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT, &output));
    gpu.Begin(); gpu.Transition(gpu.input, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    gpu.Transition(gpu.mask, D3D12_RESOURCE_STATE_UNORDERED_ACCESS); gpu.Submit();
    const OrtValue* inputs[] = {input};
    const char* input_names[] = {input_name}, *output_names[] = {output_name};
    if (gpu.model_kind == 4) {
      const UINT counts[] = {676,169};
      for (UINT i=0; i<2; ++i) {
        gpu.presence[i]=gpu.Create(static_cast<UINT64>(counts[i])*80*sizeof(float));
        CheckStatus(api->SessionGetOutputName(session,i+1,allocator,&extra_names[i]));
        CheckStatus(dml->CreateGPUAllocationFromD3DResource(gpu.presence[i].resource.Get(),&extra_allocations[i]));
        const int64_t shape[] = {1,counts[i],80};
        CheckStatus(api->CreateTensorWithDataAsOrtValue(memory,extra_allocations[i],
            static_cast<size_t>(gpu.presence[i].bytes),shape,3,ONNX_TENSOR_ELEMENT_DATA_TYPE_FLOAT,&extra_outputs[i]));
      }
      const char* names[] = {output_name,extra_names[0],extra_names[1]};
      OrtValue* values[] = {output,extra_outputs[0],extra_outputs[1]};
      CheckStatus(api->Run(session,nullptr,input_names,inputs,1,names,3,values));
    } else {
      CheckStatus(api->Run(session, nullptr, input_names, inputs, 1, output_names, 1, &output));
    }
    gpu.Sync();
  }
};

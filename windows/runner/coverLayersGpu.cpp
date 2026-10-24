#include <windows.h>
#include <d3d12.h>
#include <d3dcompiler.h>
#include <dxgi1_6.h>
#include <dxcore.h>
#include <wrl/client.h>

#include <algorithm>
#include <array>
#include <chrono>
#include <cstring>
#include <filesystem>
#include <map>
#include <memory>
#include <mutex>
#include <stdexcept>
#include <string>

#include "dml_provider_factory.h"

using Microsoft::WRL::ComPtr;
extern "C" IMAGE_DOS_HEADER __ImageBase;

namespace {
void Check(HRESULT hr, const char* operation) {
  if (FAILED(hr)) throw std::runtime_error(std::string(operation) + ":" + std::to_string(hr));
}
struct Buffer {
  ComPtr<ID3D12Resource> resource;
  UINT64 bytes = 0;
  D3D12_RESOURCE_STATES state = D3D12_RESOURCE_STATE_UNORDERED_ACCESS;
};
struct RuntimeModules { HMODULE ort = nullptr, dml = nullptr; };
RuntimeModules Modules(const std::filesystem::path& path) {
  
  
  
  static std::mutex mutex;
  static auto* modules = new std::map<std::wstring, RuntimeModules>();
  std::lock_guard<std::mutex> lock(mutex);
  const auto key = std::filesystem::absolute(path).lexically_normal().wstring();
  auto found = modules->find(key);
  if (found != modules->end()) return found->second;
  if (modules->size() >= 4) throw std::runtime_error("gpu_runtime_path_limit");
  RuntimeModules loaded;
  loaded.ort = LoadLibraryExW((path/L"onnxruntime.dll").c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  loaded.dml = LoadLibraryExW((path/L"DirectML.dll").c_str(), nullptr,
      LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  if (!loaded.ort || !loaded.dml) {
    if (loaded.ort) FreeLibrary(loaded.ort);
    if (loaded.dml) FreeLibrary(loaded.dml);
    throw std::runtime_error("directml_runtime_missing");
  }
  modules->emplace(key, loaded);
  return loaded;
}
std::string Utf8(const wchar_t* text) {
  const int length = static_cast<int>(wcslen(text));
  const int bytes = WideCharToMultiByte(CP_UTF8, 0, text, length, nullptr, 0, nullptr, nullptr);
  std::string result(bytes, 0);
  WideCharToMultiByte(CP_UTF8, 0, text, length, result.data(), bytes, nullptr, nullptr);
  return result;
}
ComPtr<ID3DBlob> Shader(const char* entry) {
  static std::mutex mutex;
  static std::map<std::string, ComPtr<ID3DBlob>> compiled;
  std::lock_guard<std::mutex> lock(mutex);
  auto found = compiled.find(entry);
  if (found != compiled.end()) return found->second;
  auto module = reinterpret_cast<HMODULE>(&__ImageBase);
  auto resource = FindResourceW(module, MAKEINTRESOURCEW(101), MAKEINTRESOURCEW(10));
  if (!resource) throw std::runtime_error("compute_shader_resource_missing");
  const auto data = LoadResource(module, resource);
  ComPtr<ID3DBlob> code, error;
  const HRESULT result = D3DCompile(LockResource(data), SizeofResource(module, resource),
      "cover_gpu_compute", nullptr, nullptr, entry, "cs_5_1",
      D3DCOMPILE_OPTIMIZATION_LEVEL3 | D3DCOMPILE_ENABLE_STRICTNESS, 0, &code, &error);
  if (FAILED(result)) throw std::runtime_error(error
      ? std::string(static_cast<const char*>(error->GetBufferPointer()), error->GetBufferSize())
      : "compute_shader_compile_failed");
  compiled.emplace(entry, code);
  return code;
}

#include "coverGpuRuntime.inc"

void WriteMessage(char* output, int capacity, const std::string& text) {
  if (!output || capacity < 1) return;
  const size_t length = std::min(text.size(), static_cast<size_t>(capacity - 1));
  memcpy(output, text.data(), length); output[length] = 0;
}

bool AuxiliaryMask(CoverGpuContext& gpu,const std::filesystem::path& root,
    const wchar_t* file,UINT kind,UINT side,std::string* error_output=nullptr) {
  if(!std::filesystem::is_regular_file(root/file)) return false;
  try {
    gpu.model_kind=kind; gpu.model_side=side; gpu.model_channels=kind==2 ? 2u : 1u;
    gpu.EnsureModelCapacity(side);
    const uint32_t clean[16]={0,0x3f800000};
    gpu.Upload(gpu.stats,clean); gpu.Dispatch("ReduceSource",gpu.width,gpu.height);
    gpu.Dispatch("Preprocess",side,side);
    { OrtSessionState model; model.Run(root,file,gpu); }
    gpu.Dispatch("ReduceMask",side,side);
    gpu.Dispatch("Resolve",gpu.grid_side,gpu.grid_side);
    std::array<uint32_t,16> stats={}; gpu.Read(gpu.stats,stats.data());
    float low,high; memcpy(&low,&stats[1],4); memcpy(&high,&stats[2],4);
    if(stats[6] || high-low<0.001f || high<(kind==0 ? 0.45f : 0.90f) || stats[5]<(kind==3 ? 128u : 256u)) {
      if(error_output) *error_output="mask_quality_rejected:"+std::to_string(low)+","+std::to_string(high)+",invalid="+std::to_string(stats[6])+",core="+std::to_string(stats[5]);
      return false;
    }
    gpu.Dispatch("Refine",gpu.grid_side,gpu.grid_side,0,1,0,false,1,0);
    if(kind==3) {
      
      
      
      const UINT radius=std::clamp(3u*stats[5]/std::max(1u,2u*stats[3]),4u,48u);
      const UINT step=(std::max(32u,radius)+3)/4;
      gpu.Dispatch("ExpandText",gpu.grid_side,gpu.grid_side,0,1,step,false,0,1);
      gpu.Dispatch("ExpandText",gpu.grid_side,gpu.grid_side,0,1,step,false,1,0);
    }
    return true;
  } catch(const std::exception& error) {
    if(error_output) *error_output=error.what();
    return false;
  }
}

UINT RepairWork(CoverGpuContext& gpu) {
  const uint32_t zero[16]={}; gpu.Upload(gpu.stats,zero);
  gpu.Dispatch("Seed",gpu.grid_side,gpu.grid_side);
  UINT labels=1;
  for(UINT step=256;step>0;step/=2) {
    gpu.Dispatch("Jump",gpu.grid_side,gpu.grid_side,labels,1-labels,step);
    labels=1-labels;
  }
  gpu.Dispatch("Fill",gpu.grid_side,gpu.grid_side,labels,1-labels);
  UINT fill=1;
  for(UINT step:{8u,4u,2u,1u,1u,1u}) {
    gpu.Dispatch("Diffuse",gpu.grid_side,gpu.grid_side,labels,1-labels,step,false,0,1,fill,1-fill);
    fill=1-fill;
  }
  return fill;
}

std::string PrepareScene(CoverGpuContext& gpu,const std::filesystem::path& root,bool alpha) {
  const UINT original_kind=gpu.model_kind;
  gpu.EnsureScene();
  gpu.Dispatch("SceneInit",gpu.grid_side,gpu.grid_side,0,1,0,alpha);
  if(!alpha && original_kind!=0 && AuxiliaryMask(gpu,root,L"u2netp.onnx",0,320)) {
    gpu.Dispatch("StoreObjects",gpu.grid_side,gpu.grid_side);
  }
  bool text=false;
  if(!alpha && (AuxiliaryMask(gpu,root,L"text-det-v5.onnx",3,512) ||
      AuxiliaryMask(gpu,root,L"text-det.onnx",3,512))) {
    
    
    gpu.Dispatch("StoreText",gpu.grid_side,gpu.grid_side); text=true;
  }
  std::array<uint32_t,16> text_stats={}; gpu.Read(gpu.stats,text_stats.data());
  float text_peak; memcpy(&text_peak,&text_stats[2],4);
  uint32_t ink_colour=0;
  std::array<uint32_t,2> text_coverage={};
  if(text && original_kind==3) gpu.Dispatch("RemoveTextObjects",gpu.grid_side,gpu.grid_side);
  if(text) {
    gpu.Dispatch("TextWork",gpu.grid_side,gpu.grid_side);
    std::swap(gpu.refined[0],gpu.refined[1]);
    const UINT fill=RepairWork(gpu);
    gpu.Copy(gpu.filled[fill],gpu.text_fill);
    const uint32_t zero[16]={}; gpu.Upload(gpu.stats,zero);
    gpu.Dispatch("AnalyzeInk",gpu.grid_side,gpu.grid_side);
    gpu.Dispatch("SetInkPolarity",gpu.grid_side,gpu.grid_side);
    gpu.Copy(gpu.filled[1],gpu.text_fill);
    gpu.Dispatch("InkHistogramClear",64,64);
    gpu.Dispatch("InkHistogram",gpu.grid_side,gpu.grid_side);
    gpu.Dispatch("InkHistogramMaximum",64,64);
    gpu.Dispatch("InkHistogramSelect",64,64);
    std::array<uint32_t,16> ink_stats={}; gpu.Read(gpu.stats,ink_stats.data());
    ink_colour=ink_stats[13];
    
    
    
    gpu.Dispatch("TextCandidate",gpu.grid_side,gpu.grid_side);
    std::swap(gpu.refined[0],gpu.refined[1]);
    gpu.Upload(gpu.stats,zero);
    gpu.Dispatch("EvaluateTextCandidate",gpu.grid_side,gpu.grid_side);
    std::array<uint32_t,16> coverage={}; gpu.Read(gpu.stats,coverage.data());
    text_coverage={coverage[14],coverage[12]};
    if(coverage[12]<64 || coverage[14]*10<coverage[12]*9 || coverage[15]<128) {
      
      
      if(original_kind==3) {
        gpu.Dispatch("PreserveCover",gpu.out_width,gpu.out_height);
        gpu.model_kind=original_kind;
        return ";subjects=0;text_layer=0;text_policy=attached;scene=0;text_quality="+
            std::to_string(coverage[14])+","+std::to_string(coverage[12])+
            ";text_ink="+std::to_string(ink_colour);
      }
      
      text=false; ink_colour=0;
      gpu.Dispatch("ClearText",gpu.grid_side,gpu.grid_side);
    } else {
      gpu.Dispatch("StoreText",gpu.grid_side,gpu.grid_side);
      const UINT local_fill=RepairWork(gpu);
      gpu.Copy(gpu.filled[local_fill],gpu.text_fill);
      gpu.Upload(gpu.stats,zero);
      gpu.Dispatch("AnalyzeInk",gpu.grid_side,gpu.grid_side);
      gpu.Dispatch("SetInkPolarity",gpu.grid_side,gpu.grid_side);
      gpu.Copy(gpu.filled[1],gpu.text_fill);
    }
  }
  gpu.inference_crop[0]=gpu.inference_crop[1]=0;
  gpu.inference_crop[2]=gpu.inference_crop[3]=1;
  gpu.Dispatch("SubjectInit",gpu.grid_side,gpu.grid_side);
  bool settled=false;
  for(UINT iteration=0;iteration<32;++iteration) {
    const uint32_t zero[16]={}; gpu.Upload(gpu.stats,zero);
    gpu.Dispatch("SubjectUnion",gpu.grid_side,gpu.grid_side,0,1);
    gpu.Dispatch("ComponentCompress",gpu.grid_side,gpu.grid_side,0,1);
    if(iteration%4==3) {
      std::array<uint32_t,16> result={}; gpu.Read(gpu.stats,result.data());
      if(!result[6]) { settled=true; break; }
    }
  }
  if(!settled) gpu.Dispatch("SubjectFallback",gpu.grid_side,gpu.grid_side);
  gpu.Copy(gpu.seeds[1],gpu.subject_labels);
  gpu.Dispatch("SceneComponentsClear",gpu.grid_side,gpu.grid_side);
  gpu.Dispatch("SceneComponentsCount",gpu.grid_side,gpu.grid_side);
  uint32_t ranking[16]={}; ranking[8]=ranking[9]=0xffffffff;
  ranking[13]=ink_colour;
  gpu.Upload(gpu.stats,ranking);
  gpu.Dispatch("RankMaximum",gpu.grid_side,gpu.grid_side);
  gpu.Dispatch("RankSelect",gpu.grid_side,gpu.grid_side);
  gpu.Read(gpu.stats,ranking);
  ranking[11]=0;
  gpu.Upload(gpu.stats,ranking);
  gpu.Dispatch("RankMaximum",gpu.grid_side,gpu.grid_side,0,1,1);
  gpu.Dispatch("RankSelect",gpu.grid_side,gpu.grid_side,0,1,1);
  gpu.Read(gpu.stats,ranking);
  gpu.Dispatch("PriorityFinish",gpu.out_width,gpu.out_height);
  if(!alpha) {
    gpu.Dispatch("SceneWork",gpu.grid_side,gpu.grid_side);
    std::swap(gpu.refined[0],gpu.refined[1]);
    const UINT fill=RepairWork(gpu);
    gpu.Dispatch("SceneBackgroundFinish",gpu.out_width,gpu.out_height,0,1,0,false,0,1,fill,1-fill);
  }
  gpu.model_kind=original_kind;
  return ";subjects="+std::to_string(ranking[12])+";text_layer="+(text ? "1" : "0")+
      ";text_quality="+std::to_string(text_coverage[0])+","+std::to_string(text_coverage[1])+
      ";text_ink="+std::to_string(ink_colour)+
      ";text_peak="+std::to_string(text_peak)+";text_core="+std::to_string(text_stats[5])+";scene=1";
}
}  

int PrepareCover(
    const wchar_t* runtime_directory, const uint8_t* rgba, int width, int height,
    uint8_t* mask_output, uint8_t* background_output, int out_width, int out_height,
    char* message, int capacity,uint8_t* priority_output=nullptr,uint8_t* text_output=nullptr,
    bool subject_draft=false) noexcept {
  const auto started=std::chrono::steady_clock::now();
  bool local_trial=false;
  try {
    if (!runtime_directory || !rgba || !mask_output || !background_output ||
        width < 2 || height < 2 || width > 2048 || height > 2048 ||
        out_width < 2 || out_height < 2 || out_width > ((priority_output || subject_draft) ? 2048 : 768) || out_height > ((priority_output || subject_draft) ? 2048 : 768)) {
      throw std::runtime_error("invalid_input");
    }
    local_trial=!subject_draft && std::filesystem::is_regular_file(
        std::filesystem::path(runtime_directory)/L"cover-layers-human123-best2.local-trial");
    CoverGpuContext gpu(width, height, out_width, out_height, subject_draft);
    gpu.Upload(gpu.source, rgba);
    const uint32_t initial[16] = {0, 0x3f800000};
    gpu.Upload(gpu.stats, initial);
    gpu.Dispatch("ReduceSource", width, height);
    std::array<uint32_t, 16> stats = {};
    gpu.Read(gpu.stats, stats.data());
    const uint64_t pixels = static_cast<uint64_t>(width) * height;
    const bool alpha = stats[3] > pixels * 8 / 100 && stats[4] > pixels * 6 / 100;
    UINT last_seeds = 0;
    std::string layer = "alpha", model_name = "source-alpha";
    UINT inference_passes=0;
    UINT edge_growth=8;
    UINT texture_density=0;
    bool ambiguous_person=false,body_consensus=false,attachment_consensus=false;
    bool person_components_settled=false;
    UINT person_component_passes=0;
    std::array<uint32_t,3> body_evidence={};
    std::array<uint32_t,3> attachment_evidence={};
    std::string attachment_error;
    std::string trial_failure;
    double inference_ms=0;
    if (!alpha) {
      struct Model { const wchar_t* file; UINT side, kind, channels; const char* layer; const char* name; };
      const Model models[] = {
        
        
        {L"cover-layers-human123-best2-512.onnx",512,6,1,"subject","human123-best2-512-probability"},
        {L"attachment-seg-fp16.onnx",1024,5,1,"subject","birefnet-lite-draft"},
        {L"anime-seg-fp16.onnx", 512, 1, 1, "person", "anime-isnet-fp16"},
        {L"human-seg.onnx", 192, 2, 2, "person", "pphumanseg"},
        {L"text-det.onnx", 512, 3, 1, "text", "ppocr-v4"},
        {L"u2netp.onnx", 320, 0, 1, "subject", "u2netp"},
      };
      bool accepted = false;
      std::unique_ptr<OrtSessionState> selected_inference;
      std::string failures;
      for (const auto& model : models) {
        if(model.kind==6 && !local_trial) continue;
        
        
        if(subject_draft ? (model.kind!=5 && model.kind!=0) : model.kind==5) continue;
        if (!std::filesystem::is_regular_file(std::filesystem::path(runtime_directory) / model.file)) {
          if(model.kind==6) trial_failure="candidate_missing";
          failures += std::string(model.name) + ":missing,"; continue;
        }
        try {
          if (model.kind == 2) {
            const uint32_t detection[16] = {stats[0], 0x3f800000};
            gpu.Upload(gpu.stats, detection);
            gpu.model_side=416; gpu.model_kind=4; gpu.model_channels=1;
            gpu.Dispatch("Preprocess",416,416);
            { OrtSessionState detector; detector.Run(runtime_directory,L"person-det.onnx",gpu); }
            gpu.model_channels=2704;
            gpu.Dispatch("PersonPresence",2704,1);
            for (UINT i=0; i<2; ++i) {
              gpu.model_channels = i==0 ? 676 : 169;
              gpu.Dispatch("PersonPresence",gpu.model_channels,1,0,1,0,false,0,1,0,1,&gpu.presence[i]);
            }
            gpu.Read(gpu.stats,stats.data());
            float confidence; memcpy(&confidence,&stats[2],4);
            if (confidence<0.35f) { failures += "person-det:absent,"; continue; }
          }
          gpu.model_side = model.side; gpu.model_kind = model.kind; gpu.model_channels = model.channels;
          gpu.EnsureModelCapacity(model.side);
          const uint32_t fresh[16] = {stats[0], 0x3f800000};
          gpu.Upload(gpu.stats, fresh);
          gpu.Dispatch("Preprocess", model.side, model.side);
          auto inference=std::make_unique<OrtSessionState>();
          const auto inference_start=std::chrono::steady_clock::now();
          inference->Run(runtime_directory, model.file, gpu);
          inference_ms+=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-inference_start).count();
          gpu.Dispatch("ReduceMask", model.side, model.side);
          gpu.Dispatch("Resolve", gpu.grid_side, gpu.grid_side);
          gpu.Read(gpu.stats, stats.data());
          float low, high; memcpy(&low, &stats[1], 4); memcpy(&high, &stats[2], 4);
          const UINT grid_pixels = gpu.grid_side * gpu.grid_side;
          const UINT minimum = model.kind == 3 ? 48 : grid_pixels / 125;
          const UINT confident = model.kind == 3 ? 16 : grid_pixels / 250;
          const float threshold = model.kind == 0 ? 0.45f : 0.90f;
          if (stats[6] || high < threshold || high - low < 0.001f ||
              stats[5] < minimum || stats[5] > grid_pixels * 97 / 100 || stats[7] < confident) {
            failures += std::string(model.name) + ":confidence,";
            if(model.kind==6) trial_failure="confidence:"+std::to_string(low)+","+std::to_string(high);
            continue;
          }
          layer = model.layer; model_name = model.name; accepted = true;
          ambiguous_person=model.kind==1 && stats[5]>std::max(4096u,stats[14]*4u);
          selected_inference=std::move(inference); inference_passes=1; break;
        } catch (const std::exception& error) {
          const HRESULT removed=gpu.device->GetDeviceRemovedReason();
          if(FAILED(removed)) {
            
            
            
            throw std::runtime_error(std::string("gpu_device_removed:model=")+model.name+
                ";reason="+std::to_string(removed)+";at="+error.what());
          }
          if(model.kind==6) trial_failure=std::string(error.what()).substr(0,300);
          
          failures += std::string(model.name) + ":" + error.what() + ",";
        }
      }
      if (!accepted) {
        WriteMessage(message, capacity, "mask_quality_rejected:" + failures); return 1;
      }
      gpu.Dispatch("Refine", gpu.grid_side, gpu.grid_side, 0, 1, 0, false, 1, 0);
      if (gpu.model_kind==1 || gpu.model_kind==2) {
        uint32_t analysis[16]={}; analysis[8]=analysis[9]=gpu.grid_side;
        gpu.Upload(gpu.stats,analysis);
        gpu.Dispatch("AnalyzeRefined",gpu.grid_side,gpu.grid_side);
        gpu.Read(gpu.stats,stats.data());
        const float x0=static_cast<float>(stats[8])/gpu.grid_side;
        const float y0=static_cast<float>(stats[9])/gpu.grid_side;
        const float x1=static_cast<float>(stats[10]+1)/gpu.grid_side;
        const float y1=static_cast<float>(stats[11]+1)/gpu.grid_side;
        const float area=std::max(0.0f,(x1-x0)*(y1-y0));
        const bool uncertain=stats[13]>std::max(256u,stats[12]/15u);
        texture_density=1000u*stats[14]/std::max(1u,stats[15]);
        if (stats[12]>128 && (area<0.50f || uncertain)) {
          const float margin=std::max(0.035f,std::max(x1-x0,y1-y0)*0.22f);
          gpu.inference_crop[0]=std::max(0.0f,x0-margin);
          gpu.inference_crop[1]=std::max(0.0f,y0-margin);
          gpu.inference_crop[2]=std::min(1.0f,x1+margin)-gpu.inference_crop[0];
          gpu.inference_crop[3]=std::min(1.0f,y1+margin)-gpu.inference_crop[1];
          gpu.inference_flip=1;
          gpu.refinement_mode=area<0.50f ? 1u : 2u;
          if (gpu.refinement_mode==2) {
            edge_growth=texture_density>=90 ? 0u : std::min(8u,(90u-texture_density)/5u);
          }
          try {
            gpu.Dispatch("Preprocess",gpu.model_side,gpu.model_side);
            selected_inference->Repeat(gpu);
            const uint32_t clean[16]={0,0x3f800000};
            gpu.Upload(gpu.stats,clean);
            gpu.Dispatch("ReduceMask",gpu.model_side,gpu.model_side);
            gpu.Read(gpu.stats,stats.data());
            float peak; memcpy(&peak,&stats[2],4);
            if (!stats[6] && peak>0.90f) {
              gpu.Dispatch("MergeRefinement",gpu.grid_side,gpu.grid_side);
              std::swap(gpu.refined[0],gpu.refined[1]); inference_passes=2;
            }
          } catch (const std::exception&) {
            
          }
          gpu.inference_flip=0;
          gpu.refinement_mode=0;
          gpu.inference_crop[0]=gpu.inference_crop[1]=0;
          gpu.inference_crop[2]=gpu.inference_crop[3]=1;
        }
      }
      selected_inference.reset();
      if(ambiguous_person) {
        const UINT kind=gpu.model_kind,side=gpu.model_side,channels=gpu.model_channels;
        gpu.Copy(gpu.refined[0],gpu.confidence);
        if(AuxiliaryMask(gpu,runtime_directory,L"human-seg.onnx",2,192)) {
          const uint32_t clean[16]={}; gpu.Upload(gpu.stats,clean);
          gpu.Dispatch("BodyAgreement",gpu.grid_side,gpu.grid_side,0,1,0,false,0,1,0,1,&gpu.confidence);
          gpu.Read(gpu.stats,stats.data());
          body_evidence={stats[12],stats[13],stats[14]};
          
          
          if(stats[12]>=256 && stats[13]*5>=stats[12]*4 &&
              stats[14]>stats[12]*3/2 && stats[14]<gpu.grid_side*gpu.grid_side*4/5) {
            gpu.Dispatch("MergeBodyConsensus",gpu.grid_side,gpu.grid_side,0,1,0,false,0,1,0,1,&gpu.confidence);
            std::swap(gpu.refined[0],gpu.refined[1]); body_consensus=true;
          } else gpu.Copy(gpu.confidence,gpu.refined[0]);
        } else gpu.Copy(gpu.confidence,gpu.refined[0]);
        gpu.model_kind=kind; gpu.model_side=side; gpu.model_channels=channels;
      }
      if (gpu.model_kind==1 || gpu.model_kind==2) {
        if(ambiguous_person && std::filesystem::is_regular_file(std::filesystem::path(runtime_directory)/L"attachment-seg-fp16.onnx")) {
          const UINT kind=gpu.model_kind,side=gpu.model_side,channels=gpu.model_channels;
          gpu.body_anchor=gpu.Create(gpu.refined[0].bytes);
          gpu.Copy(gpu.refined[0],gpu.body_anchor);
          
          
          
          gpu.inference_crop[0]=gpu.inference_crop[1]=0.05f;
          gpu.inference_crop[2]=gpu.inference_crop[3]=0.90f;
          if(AuxiliaryMask(gpu,runtime_directory,L"attachment-seg-fp16.onnx",5,1024,&attachment_error)) {
            const uint32_t clean[16]={}; gpu.Upload(gpu.stats,clean);
            gpu.Dispatch("BodyAgreement",gpu.grid_side,gpu.grid_side,0,1,0,false,0,1,0,1,&gpu.body_anchor);
            gpu.Read(gpu.stats,stats.data());
            attachment_evidence={stats[12],stats[13],stats[14]};
            if(stats[12]>=256 && stats[13]*10>=stats[12]*9 &&
                stats[14]>stats[12]*11/10 && stats[14]<gpu.grid_side*gpu.grid_side*97/100) {
              gpu.Dispatch("MergeAttachmentConsensus",gpu.grid_side,gpu.grid_side,0,1,0,false,0,1,0,1,&gpu.body_anchor);
              std::swap(gpu.refined[0],gpu.refined[1]); attachment_consensus=true;
            } else gpu.Copy(gpu.body_anchor,gpu.refined[0]);
          } else gpu.Copy(gpu.body_anchor,gpu.refined[0]);
          gpu.model_kind=kind; gpu.model_side=side; gpu.model_channels=channels;
          gpu.inference_crop[0]=gpu.inference_crop[1]=0;
          gpu.inference_crop[2]=gpu.inference_crop[3]=1;
        }
        gpu.Copy(gpu.refined[0],gpu.confidence);
        gpu.Dispatch("ComponentInit",gpu.grid_side,gpu.grid_side,0,1,attachment_consensus ? 500u : 0u);
        UINT labels=1;
        bool settled=false;
        const uint32_t zero[16] = {};
        for (UINT iteration=0; iteration<(attachment_consensus ? 64u : 24u); ++iteration) {
          gpu.Upload(gpu.stats,zero);
          gpu.Dispatch("ComponentUnion",gpu.grid_side,gpu.grid_side,0,labels);
          gpu.Dispatch("ComponentCompress",gpu.grid_side,gpu.grid_side,0,labels);
          person_component_passes=iteration+1;
          if (iteration%4==3) {
            gpu.Read(gpu.stats,stats.data());
            if (!stats[6]) { settled=true; break; }
          }
        }
        person_components_settled=settled;
        if (settled) {
          gpu.Dispatch("ComponentClear",gpu.grid_side,gpu.grid_side,labels,1-labels);
          if(attachment_consensus) {
            gpu.Dispatch("ComponentAnchorCount",gpu.grid_side,gpu.grid_side,labels,1-labels,
                body_consensus ? 650u : 930u,false,0,1,0,1,&gpu.body_anchor);
          } else gpu.Dispatch("ComponentCount",gpu.grid_side,gpu.grid_side,labels,1-labels);
          gpu.Dispatch("ComponentMaximum",gpu.grid_side,gpu.grid_side,1-labels,labels);
          gpu.Read(gpu.stats,stats.data());
          const UINT minimum=std::max(64u,stats[5]/40u);
          gpu.Dispatch("ComponentRetain",gpu.grid_side,gpu.grid_side,labels,1-labels,
              minimum,false,0,1,0,1,&gpu.seeds[1-labels]);
          std::swap(gpu.refined[0],gpu.refined[1]);
          for (UINT growth=0; growth<edge_growth; ++growth) {
            gpu.Dispatch("GrowEdges",gpu.grid_side,gpu.grid_side,0,1,0,false,0,1,0,1,&gpu.confidence);
            std::swap(gpu.refined[0],gpu.refined[1]);
          }
        } else if(attachment_consensus) {
          
          
          gpu.Copy(gpu.body_anchor,gpu.refined[0]);
          attachment_consensus=false;
          attachment_error="component_filter_not_converged";
        }
      }
      if (gpu.model_kind == 3) {
        const UINT radius = std::clamp(3u*stats[5]/std::max(1u,2u*stats[3]),4u,48u);
        const UINT step = (radius+3)/4;
        gpu.Dispatch("ExpandText", gpu.grid_side, gpu.grid_side, 0, 1, step, false, 0, 1);
        gpu.Dispatch("ExpandText", gpu.grid_side, gpu.grid_side, 0, 1, step, false, 1, 0);
      }
      const uint32_t cleared[16] = {};
      gpu.Upload(gpu.stats,cleared);
      gpu.Dispatch("Seed", gpu.grid_side, gpu.grid_side);
      gpu.Read(gpu.stats,stats.data());
      if (stats[3] < 128) {
        WriteMessage(message,capacity,"mask_quality_rejected:no_background_seeds"); return 1;
      }
      last_seeds = 1;
      for (UINT step = 256; step > 0; step /= 2) {
        gpu.Dispatch("Jump", gpu.grid_side, gpu.grid_side, last_seeds, 1 - last_seeds, step);
        last_seeds = 1 - last_seeds;
      }
      gpu.Dispatch("Fill", gpu.grid_side, gpu.grid_side, last_seeds, 1-last_seeds);
      UINT last_fill = 1;
      
      
      for (UINT step : {8u, 4u, 2u, 1u, 1u, 1u}) {
        gpu.Dispatch("Diffuse", gpu.grid_side, gpu.grid_side, last_seeds, 1-last_seeds,
            step, false, 0, 1, last_fill, 1-last_fill);
        last_fill = 1-last_fill;
      }
      gpu.Dispatch("Finish", out_width, out_height, last_seeds, 1-last_seeds,
          0, false, 0, 1, last_fill, 1-last_fill);
      gpu.Read(gpu.stats,stats.data());
      if (stats[5]<8 || stats[5]>static_cast<UINT>(out_width*out_height)*99/100) {
        WriteMessage(message,capacity,"mask_quality_rejected:final_matte"); return 1;
      }
    } else {
      gpu.Dispatch("Finish", out_width, out_height, 0, 1, 0, true);
    }
    std::string scene_detail;
    if(priority_output && text_output) {
      if(alpha || gpu.model_kind==1 || gpu.model_kind==2 || gpu.model_kind==6) {
        
        
        
        scene_detail=gpu.model_kind==6
            ? ";scene=0;layer_policy=visual-focus-trial;text_layer=0"
            : ";scene=0;layer_policy=person-only;text_layer=0";
      } else {
        scene_detail=PrepareScene(gpu,runtime_directory,alpha);
        if(scene_detail.find(";scene=1")!=std::string::npos) {
          gpu.Read(gpu.priority,priority_output); gpu.Read(gpu.text_repair,text_output);
        }
      }
    }
    gpu.Read(gpu.final_mask, mask_output); gpu.Read(gpu.background, background_output);
    WriteMessage(message, capacity, std::string("gpu:") + (gpu.integrated ? "integrated:" : "discrete:") +
        gpu.adapter + ";layer=" + layer + ";model=" + model_name +
        ";local_trial="+(local_trial ? "1" : "0")+
        ";trial_accepted="+(gpu.model_kind==6 ? "1" : "0")+
        ";graph_fusion="+(gpu.model_kind==6 ? "0" : "default")+
        ";trial_failure="+trial_failure+
        ";inference_with_session_ms="+std::to_string(inference_ms)+
        ";prepare_ms="+std::to_string(std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count())+
        ";passes=" + std::to_string(inference_passes) +
        ";texture=" + std::to_string(texture_density) +
        ";body_consensus="+(body_consensus ? "1" : "0")+
        ";attachment_consensus="+(attachment_consensus ? "1" : "0")+
        ";components_settled="+(person_components_settled ? "1" : "0")+
        ";component_passes="+std::to_string(person_component_passes)+
        ";attachment_evidence="+std::to_string(attachment_evidence[0])+","+std::to_string(attachment_evidence[1])+","+std::to_string(attachment_evidence[2])+
        ";attachment_error="+attachment_error+
        ";body_need="+(ambiguous_person ? "1" : "0")+
        ";body_evidence="+std::to_string(body_evidence[0])+","+std::to_string(body_evidence[1])+","+std::to_string(body_evidence[2])+
        scene_detail +
        ";cpu_fallback=0;preprocess=gpu;refine=gpu;fill=gpu");
    return 0;
  } catch (const std::exception& error) {
    WriteMessage(message, capacity, error.what()); return 2;
  } catch (...) {
    WriteMessage(message, capacity, "gpu_prepare_failed"); return 2;
  }
}

extern "C" __declspec(dllexport) const char* cover_layers_gpu_policy() noexcept {
#ifdef COVER_DEV_DISCRETE_DRAFTS
  return "development-discrete-drafts-integrated-runtime";
#else
  return "integrated-only-no-discrete-or-cpu-fallback";
#endif
}

extern "C" __declspec(dllexport) int cover_layers_prepare(
    const wchar_t* root,const uint8_t* rgba,int w,int h,uint8_t* mask,uint8_t* bg,
    int ow,int oh,char* message,int capacity) noexcept {
  return PrepareCover(root,rgba,w,h,mask,bg,ow,oh,message,capacity);
}
extern "C" __declspec(dllexport) int cover_layers_prepare_scene(
    const wchar_t* root,const uint8_t* rgba,int w,int h,uint8_t* mask,uint8_t* bg,
    uint8_t* priority,uint8_t* text,int ow,int oh,char* message,int capacity) noexcept {
  if(!priority || !text) { WriteMessage(message,capacity,"invalid_scene_output"); return 2; }
  return PrepareCover(root,rgba,w,h,mask,bg,ow,oh,message,capacity,priority,text);
}
extern "C" __declspec(dllexport) int cover_layers_prepare_subject_draft(
    const wchar_t* root,const uint8_t* rgba,int w,int h,uint8_t* mask,uint8_t* bg,
    int ow,int oh,char* message,int capacity) noexcept {
  return PrepareCover(root,rgba,w,h,mask,bg,ow,oh,message,capacity,nullptr,nullptr,true);
}

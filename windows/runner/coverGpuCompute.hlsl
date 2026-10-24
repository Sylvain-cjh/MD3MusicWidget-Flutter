cbuffer Config : register(b0) {
  uint Width, Height, OutWidth, OutHeight;
  uint JumpStep, AlphaMode, ModelSide, GridSide;
  uint ModelKind, ModelChannels, InferenceFlip, RefinementMode;
  float4 InferenceCrop;
};
ByteAddressBuffer Source : register(t0);
StructuredBuffer<float> Mask : register(t1);
StructuredBuffer<uint> Seeds : register(t2);
StructuredBuffer<float> Refined : register(t3);
StructuredBuffer<uint> Filled : register(t4);
StructuredBuffer<float> Actors : register(t5);
StructuredBuffer<float> Objects : register(t6);
StructuredBuffer<float> TextAreas : register(t7);
StructuredBuffer<uint> SubjectLabels : register(t8);
ByteAddressBuffer ComponentRead : register(t9);
StructuredBuffer<uint> TextFilled : register(t10);
RWStructuredBuffer<float> Input : register(u0);
RWByteAddressBuffer Stats : register(u1);
RWStructuredBuffer<uint> SeedsOut : register(u2);
RWStructuredBuffer<uint> FinalMask : register(u3);
RWStructuredBuffer<uint> FinalBackground : register(u4);
RWStructuredBuffer<float> RefinedOut : register(u5);
RWStructuredBuffer<uint> FilledOut : register(u6);
RWStructuredBuffer<uint> PriorityOut : register(u7);
RWStructuredBuffer<uint> TextRepairOut : register(u8);
RWStructuredBuffer<float> ActorsOut : register(u9);
RWStructuredBuffer<float> ObjectsOut : register(u10);
RWStructuredBuffer<float> TextAreasOut : register(u11);
RWByteAddressBuffer ComponentWrite : register(u12);

float4 Unpack(uint v) {
  return float4(v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24) / 255.0;
}
uint GridIndex(int2 p) {
  p = clamp(p, 0, int(GridSide)-1); return p.y * GridSide + p.x;
}
float2 ContentSize() {
  float2 size=float2(Width,Height)*InferenceCrop.zw;
  return max(1.0, floor(size*float(ModelSide)/max(size.x,size.y)));
}
float2 ModelUv(float2 uv) {
  uv=(uv-InferenceCrop.xy)/InferenceCrop.zw;
  if (InferenceFlip!=0) uv.x=1.0-uv.x;
  if (ModelKind != 1 && ModelKind != 3) return uv;
  float2 size = ContentSize();
  return (floor((ModelSide - size)*0.5) + uv*size) / ModelSide;
}
float RawMask(int2 p) {
  p = clamp(p, 0, int(ModelSide)-1);
  uint offset = ModelKind == 2 ? ModelSide*ModelSide : 0;
  float value=Mask[offset + p.y*ModelSide + p.x];
  return ModelKind==5 && isfinite(value) ? 1.0/(1.0+exp(-clamp(value,-20.0,20.0))) : value;
}
float RefinedMask(int2 p) { return Refined[GridIndex(p)]; }

float4 Pixel(int2 p) {
  p = clamp(p, int2(0, 0), int2(Width - 1, Height - 1));
  uint v = Source.Load((p.y * Width + p.x) * 4);
  return float4(v & 255, (v >> 8) & 255, (v >> 16) & 255, v >> 24) / 255.0;
}
float4 SampleSource(float2 uv) {
  float2 p = uv * float2(Width, Height) - 0.5;
  int2 a = int2(floor(p));
  float2 f = frac(p);
  return lerp(lerp(Pixel(a), Pixel(a + int2(1,0)), f.x),
              lerp(Pixel(a + int2(0,1)), Pixel(a + 1), f.x), f.y);
}
float NormalMask(int2 p) {
  float value = RawMask(p);
  
  
  if (ModelKind == 0) {
    float low = asfloat(Stats.Load(4)), high = asfloat(Stats.Load(8));
    value = (value-low) / max(0.000001, high-low);
  }
  return saturate(value);
}
float SampleMask(float2 uv) {
  if(any(uv<InferenceCrop.xy) || any(uv>InferenceCrop.xy+InferenceCrop.zw)) return 0;
  float2 q = ModelUv(uv)*ModelSide - 0.5;
  int2 p = int2(floor(q)); float2 f = frac(q);
  return lerp(lerp(NormalMask(p),NormalMask(p+int2(1,0)),f.x),
      lerp(NormalMask(p+int2(0,1)),NormalMask(p+1),f.x),f.y);
}
uint Pack(float4 c) {
  uint4 b = uint4(round(saturate(c) * 255.0));
  return b.x | (b.y << 8) | (b.z << 16) | (b.w << 24);
}

[numthreads(16,16,1)]
void ReduceSource(uint3 id : SV_DispatchThreadID) {
  if (id.x >= Width || id.y >= Height) return;
  uint v = Source.Load((id.y * Width + id.x) * 4);
  uint peak = max(v & 255, max((v >> 8) & 255, (v >> 16) & 255));
  uint ignored;
  Stats.InterlockedMax(0, peak, ignored);
  if ((v >> 24) < 16) Stats.InterlockedAdd(12, 1, ignored);
  if ((v >> 24) > 200) Stats.InterlockedAdd(16, 1, ignored);
}
[numthreads(16,16,1)]
void Preprocess(uint3 id : SV_DispatchThreadID) {
  if (id.x >= ModelSide || id.y >= ModelSide) return;
  float2 uv = (id.xy+0.5) / ModelSide;
  float3 rgb;
  if (ModelKind == 1 || ModelKind == 3 || ModelKind == 4) {
    float2 size = ContentSize(), padding = floor((ModelSide-size)*0.5);
    float2 q = (id.xy+0.5-padding) / size;
    if (InferenceFlip!=0) q.x=1.0-q.x;
    rgb = any(q < 0) || any(q > 1) ? 0 : SampleSource(InferenceCrop.xy+q*InferenceCrop.zw).rgb;
  } else {
    if (InferenceFlip!=0) uv.x=1.0-uv.x;
    rgb = SampleSource(InferenceCrop.xy+uv*InferenceCrop.zw).rgb;
  }
  if (ModelKind == 0) rgb /= max(0.000001, Stats.Load(0)/255.0);
  if (ModelKind == 4) rgb = (rgb.bgr*255.0-float3(103.53,116.28,123.675)) /
      float3(57.375,57.12,58.395);
  else if (ModelKind == 2) rgb = (rgb-0.5)/0.5;
  else if (ModelKind == 0 || ModelKind == 3 || ModelKind==5 || ModelKind==6) {
    if (ModelKind == 3) rgb = rgb.bgr;
    rgb = (rgb-float3(0.485,0.456,0.406)) / float3(0.229,0.224,0.225);
  }
  uint i = id.y*ModelSide+id.x, plane = ModelSide*ModelSide;
  Input[i]=rgb.x; Input[plane+i]=rgb.y; Input[plane*2+i]=rgb.z;
}
[numthreads(16,16,1)]
void PersonPresence(uint3 id : SV_DispatchThreadID) {
  if (id.x >= ModelChannels || id.y != 0) return;
  float score=Mask[id.x*80]; uint ignored;
  if (isfinite(score) && score>=0 && score<=1)
    Stats.InterlockedMax(8,asuint(score),ignored);
}
[numthreads(16,16,1)]
void ReduceMask(uint3 id : SV_DispatchThreadID) {
  if (id.x >= ModelSide || id.y >= ModelSide) return;
  float value = RawMask(id.xy);
  uint ignored;
  if (!isfinite(value) || value < -0.001 || value > 1.001) {
    Stats.InterlockedAdd(24, 1, ignored); return;
  }
  Stats.InterlockedMin(4, asuint(max(0,value)), ignored);
  Stats.InterlockedMax(8, asuint(max(0,value)), ignored);
}
[numthreads(16,16,1)]
void Resolve(uint3 id : SV_DispatchThreadID) {
  if (id.x >= GridSide || id.y >= GridSide) return;
  float value = SampleMask((id.xy+0.5)/GridSide);
  RefinedOut[id.y*GridSide+id.x] = value;
  uint ignored;
  if (value > 0.65) Stats.InterlockedAdd(20,1,ignored);
  if (value > 0.90) Stats.InterlockedAdd(28,1,ignored);
  if (value > 0.93) Stats.InterlockedAdd(56,1,ignored);
  if (ModelKind==3 && value>0.65) {
    float2 uv=(id.xy+0.5)/GridSide;
    float2 delta=float2(1.0/GridSide,0);
    if (SampleMask(uv+delta)<0.65 || SampleMask(uv-delta)<0.65 ||
        SampleMask(uv+delta.yx)<0.65 || SampleMask(uv-delta.yx)<0.65)
      Stats.InterlockedAdd(12,1,ignored);
  }
}
[numthreads(16,16,1)]
void AnalyzeRefined(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  float value=RefinedMask(id.xy); uint ignored;
  if (value>0.65) {
    Stats.InterlockedMin(32,id.x,ignored); Stats.InterlockedMin(36,id.y,ignored);
    Stats.InterlockedMax(40,id.x,ignored); Stats.InterlockedMax(44,id.y,ignored);
    Stats.InterlockedAdd(48,1,ignored);
  }
  if (value>0.04 && value<0.96) Stats.InterlockedAdd(52,1,ignored);
  if (value<0.04) {
    Stats.InterlockedAdd(60,1,ignored);
    float2 uv=(id.xy+0.5)/GridSide, dx=float2(1.0/GridSide,0);
    float3 horizontal=SampleSource(uv+dx).rgb-SampleSource(uv-dx).rgb;
    float3 vertical=SampleSource(uv+dx.yx).rgb-SampleSource(uv-dx.yx).rgb;
    if (max(dot(horizontal,horizontal),dot(vertical,vertical))>0.12)
      Stats.InterlockedAdd(56,1,ignored);
  }
}
[numthreads(16,16,1)]
void MergeRefinement(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  float2 uv=(id.xy+0.5)/GridSide;
  float first=RefinedMask(id.xy);
  float2 q=(uv-InferenceCrop.xy)/InferenceCrop.zw;
  if (any(q<0) || any(q>1)) {
    RefinedOut[id.y*GridSide+id.x]=first; return;
  }
  float second=SampleMask(uv);
  if (RefinementMode==2) {
    
    
    
    float value=min(first,second);
    if (first>0.985 && second>0.50) value=first;
    RefinedOut[id.y*GridSide+id.x]=value; return;
  }
  float weight=0.5+0.25*(1.0-abs(first-0.5)*2.0);
  float value=lerp(first,second,weight);
  if (second>0.95) value=lerp(first,second,0.90);
  if (first>0.97 && second>0.55) value=max(first,second);
  if (first<0.015 && second<0.65) value=0;
  RefinedOut[id.y*GridSide+id.x]=saturate(value);
}
[numthreads(16,16,1)]
void GrowEdges(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  float current=RefinedMask(id.xy), candidate=Mask[i];
  if (current>0 || candidate<0.20) { RefinedOut[i]=current; return; }
  float3 color=SampleSource((id.xy+0.5)/GridSide).rgb;
  bool connected=false;
  for (int y=-1; y<=1; ++y) {
    for (int x=-1; x<=1; ++x) {
      int2 p=int2(id.xy)+int2(x,y);
      float value=RefinedMask(p);
      float3 delta=SampleSource((p+0.5)/GridSide).rgb-color;
      if (value>0.20 && (candidate>0.985 || dot(delta,delta)<0.08)) connected=true;
    }
  }
  
  
  RefinedOut[i]=connected ? candidate : 0;
}
[numthreads(16,16,1)]
void BodyAgreement(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x,ignored;
  float anime=Mask[i],body=RefinedMask(id.xy);
  if(anime>0.93) {
    Stats.InterlockedAdd(48,1,ignored);
    if(body>0.50) Stats.InterlockedAdd(52,1,ignored);
  }
  if(body>0.65) Stats.InterlockedAdd(56,1,ignored);
}
[numthreads(16,16,1)]
void MergeBodyConsensus(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  
  
  float body=smoothstep(0.30,0.80,RefinedMask(id.xy));
  float anime=smoothstep(0.93,0.995,Mask[i]);
  RefinedOut[i]=max(body,anime);
}
[numthreads(16,16,1)]
void MergeAttachmentConsensus(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  RefinedOut[i]=max(RefinedMask(id.xy),smoothstep(0.93,0.995,Mask[i]));
}
[numthreads(16,16,1)]
void Refine(uint3 id : SV_DispatchThreadID) {
  if (id.x >= GridSide || id.y >= GridSide) return;
  float center=RefinedMask(id.xy), sum=0, weightSum=0, peak=center;
  float3 color=SampleSource((id.xy+0.5)/GridSide).rgb;
  for (int y=-2; y<=2; ++y) {
    for (int x=-2; x<=2; ++x) {
      int2 p=clamp(int2(id.xy)+int2(x,y),0,int(GridSide)-1);
      float value=RefinedMask(p);
      float3 delta=SampleSource((p+0.5)/GridSide).rgb-color;
      float weight=exp(-float(x*x+y*y)*0.45-dot(delta,delta)*48.0);
      sum+=value*weight; weightSum+=weight; peak=max(peak,value);
    }
  }
  float value=sum/max(weightSum,0.00001);
  
  value=ModelKind==3 ? smoothstep(0.20,0.60,max(value,peak*0.9)) : lerp(value,center,0.55);
  if (value<0.012) value=0;
  if (value>0.985) value=1;
  RefinedOut[id.y*GridSide+id.x]=saturate(value);
}
[numthreads(16,16,1)]
void ComponentInit(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  float threshold=JumpStep>0 ? float(JumpStep)/1000.0 : 0.93;
  SeedsOut[i]=RefinedMask(id.xy)>threshold ? i+1 : 0;
}
uint ComponentRoot(uint label) {
  for (uint step=0; step<32 && label>0; ++step) {
    uint parent=SeedsOut[label-1];
    if (parent==label || parent==0) break;
    label=parent;
  }
  return label;
}
[numthreads(16,16,1)]
void ComponentUnion(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  if (SeedsOut[i]==0) return;
  for (int y=0; y<=1; ++y) {
    for (int x=-1; x<=1; ++x) {
      if (y==0 && x<=0) continue;
      int2 q=int2(id.xy)+int2(x,y);
      if (any(q<0) || any(q>=int(GridSide))) continue;
      uint a=ComponentRoot(i+1), b=ComponentRoot(SeedsOut[q.y*GridSide+q.x]);
      if (a>0 && b>0 && a!=b) {
        uint old; InterlockedMin(SeedsOut[max(a,b)-1],min(a,b),old);
        if (old>min(a,b)) { uint ignored; Stats.InterlockedAdd(24,1,ignored); }
      }
    }
  }
}
[numthreads(16,16,1)]
void ComponentCompress(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x, label=SeedsOut[i];
  uint root=ComponentRoot(label);
  SeedsOut[i]=root;
  if (root!=label) { uint ignored; Stats.InterlockedAdd(24,1,ignored); }
}
[numthreads(16,16,1)]
void ComponentClear(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  SeedsOut[id.y*GridSide+id.x]=0;
}
[numthreads(16,16,1)]
void ComponentCount(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  uint label=Seeds[id.y*GridSide+id.x];
  if (label>0) { uint ignored; InterlockedAdd(SeedsOut[label-1],1,ignored); }
}
[numthreads(16,16,1)]
void ComponentAnchorCount(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x,label=Seeds[i];
  if(label>0 && Mask[i]>float(JumpStep)/1000.0) {
    uint ignored; InterlockedAdd(SeedsOut[label-1],1,ignored);
  }
}
[numthreads(16,16,1)]
void ComponentMaximum(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  uint ignored; Stats.InterlockedMax(20,Seeds[id.y*GridSide+id.x],ignored);
}
[numthreads(16,16,1)]
void ComponentRetain(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  
  
  bool reliable=false;
  for (int y=-4; y<=4; ++y) {
    for (int x=-4; x<=4; ++x) {
      uint label=Seeds[GridIndex(int2(id.xy)+int2(x,y))];
      if (label>0 && asuint(Mask[label-1])>=JumpStep) reliable=true;
    }
  }
  RefinedOut[id.y*GridSide+id.x]=reliable ? RefinedMask(id.xy) : 0;
}
[numthreads(16,16,1)]
void ExpandText(uint3 id : SV_DispatchThreadID) {
  if (id.x>=GridSide || id.y>=GridSide) return;
  float peak=0;
  
  
  for (int y=-2; y<=2; ++y)
    for (int x=-2; x<=2; ++x)
      peak=max(peak,RefinedMask(int2(id.xy)+int2(x,y)*int(JumpStep)));
  RefinedOut[id.y*GridSide+id.x]=peak;
}
[numthreads(16,16,1)]
void Seed(uint3 id : SV_DispatchThreadID) {
  if (id.x >= GridSide || id.y >= GridSide) return;
  float peak=0;
  
  for (int y=-1; y<=1; ++y)
    for (int x=-1; x<=1; ++x)
      peak=max(peak,RefinedMask(int2(id.xy)+int2(x,y)*3));
  bool known=peak<0.025;
  SeedsOut[id.y * GridSide + id.x] = known ? (id.x | (id.y << 16)) : 0xffffffff;
  if (known) { uint ignored; Stats.InterlockedAdd(12,1,ignored); }
}
[numthreads(16,16,1)]
void Jump(uint3 id : SV_DispatchThreadID) {
  if (id.x >= GridSide || id.y >= GridSide) return;
  uint best = 0xffffffff;
  float distance = 1e20;
  for (int y = -1; y <= 1; y++) {
    for (int x = -1; x <= 1; x++) {
      int2 p = int2(id.xy) + int2(x,y) * int(JumpStep);
      if (any(p < 0) || any(p >= int(GridSide))) continue;
      uint seed = Seeds[p.y * GridSide + p.x];
      if (seed == 0xffffffff) continue;
      float2 delta = float2(seed & 65535, seed >> 16) - id.xy;
      float d = dot(delta, delta);
      if (d < distance) { best = seed; distance = d; }
    }
  }
  SeedsOut[id.y * GridSide + id.x] = best;
}
[numthreads(16,16,1)]
void Fill(uint3 id : SV_DispatchThreadID) {
  if (id.x >= GridSide || id.y >= GridSide) return;
  uint seed=Seeds[id.y*GridSide+id.x];
  float4 source=SampleSource((id.xy+0.5)/GridSide);
  float4 filled=seed==0xffffffff ? source :
      SampleSource((float2(seed&65535,seed>>16)+0.5)/GridSide);
  FilledOut[id.y*GridSide+id.x]=Pack(filled);
}
[numthreads(16,16,1)]
void Diffuse(uint3 id : SV_DispatchThreadID) {
  if (id.x >= GridSide || id.y >= GridSide) return;
  uint i=id.y*GridSide+id.x, seed=Seeds[i];
  bool known=seed==(id.x|(id.y<<16));
  if (known) { FilledOut[i]=Pack(SampleSource((id.xy+0.5)/GridSide)); return; }
  float4 sum=0; float count=0;
  for (int y=-1; y<=1; ++y) {
    for (int x=-1; x<=1; ++x) {
      float weight=x==0 && y==0 ? 2 : 1;
      sum+=Unpack(Filled[GridIndex(int2(id.xy)+int2(x,y)*int(JumpStep))])*weight;
      count+=weight;
    }
  }
  FilledOut[i]=Pack(sum/count);
}
float4 BackgroundAt(float2 uv) {
  float2 q=uv*GridSide-0.5;
  int2 p=int2(floor(q)); float2 f=frac(q);
  return lerp(lerp(Unpack(Filled[GridIndex(p)]),Unpack(Filled[GridIndex(p+int2(1,0))]),f.x),
      lerp(Unpack(Filled[GridIndex(p+int2(0,1))]),Unpack(Filled[GridIndex(p+1)]),f.x),f.y);
}
[numthreads(16,16,1)]
void Finish(uint3 id : SV_DispatchThreadID) {
  if (id.x >= OutWidth || id.y >= OutHeight) return;
  float2 uv = (id.xy + 0.5) / float2(OutWidth, OutHeight);
  float4 source = SampleSource(uv);
  uint outIndex = id.y * OutWidth + id.x;
  if (AlphaMode != 0) {
    FinalMask[outIndex] = 0xffffffff;
    FinalBackground[outIndex] = 0; return;
  }
  float2 grid = uv * GridSide - 0.5;
  int2 base = int2(floor(grid));
  float2 fractional = frac(grid);
  float mask = 0, total = 0;
  
  
  for (int y = -1; y <= 2; y++) {
    for (int x = -1; x <= 2; x++) {
        int2 p = clamp(base + int2(x,y), 0, int(GridSide)-1);
        float3 delta = SampleSource((p + 0.5) / GridSide).rgb - source.rgb;
      float2 spatial = float2(x,y) - fractional;
        float weight = exp(-dot(spatial, spatial) * 0.7 - dot(delta, delta) * 48.0);
        mask += RefinedMask(p) * weight; total += weight;
    }
  }
  mask = saturate(mask / max(total, 0.00001));
  float4 background = BackgroundAt(uv);
  if (ModelKind == 3) {
    
    
    mask *= smoothstep(0.025,0.20,length(source.rgb-background.rgb));
  }
  uint a = uint(round(mask * 255.0));
  if (mask>0.5) { uint ignored; Stats.InterlockedAdd(20,1,ignored); }
  FinalMask[outIndex] = a | (a << 8) | (a << 16) | 0xff000000;
  background.rgb *= background.a;
  FinalBackground[outIndex] = Pack(background);
}

float GridValue(int kind,int2 p) {
  uint i=GridIndex(p);
  if(kind==0) return Actors[i];
  if(kind==1) return Objects[i];
  return TextAreas[i];
}
float SampleGrid(int kind,float2 uv) {
  float2 q=uv*GridSide-0.5; int2 p=int2(floor(q)); float2 f=frac(q);
  return lerp(lerp(GridValue(kind,p),GridValue(kind,p+int2(1,0)),f.x),
    lerp(GridValue(kind,p+int2(0,1)),GridValue(kind,p+1),f.x),f.y);
}
float CanonicalAt(float2 uv) {
  int2 p=clamp(int2(uv*float2(OutWidth,OutHeight)),0,int2(OutWidth-1,OutHeight-1));
  return (FinalMask[p.y*OutWidth+p.x]&255)/255.0;
}
[numthreads(16,16,1)]
void SceneInit(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x; float2 uv=(id.xy+0.5)/GridSide;
  float value=CanonicalAt(uv);
  bool character=ModelKind==1 || ModelKind==2 || AlphaMode!=0;
  if(AlphaMode!=0) value=SampleSource(uv).a>0.01 ? 1 : 0;
  ActorsOut[i]=character ? value : 0;
  ObjectsOut[i]=ModelKind==0 ? value : 0;
  TextAreasOut[i]=0;
}
[numthreads(16,16,1)]
void StoreObjects(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  ObjectsOut[i]=RefinedMask(id.xy)*(1.0-smoothstep(0.01,0.12,Actors[i]));
}
[numthreads(16,16,1)]
void StoreText(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  TextAreasOut[id.y*GridSide+id.x]=RefinedMask(id.xy);
}
[numthreads(16,16,1)]
void ClearText(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  TextAreasOut[id.y*GridSide+id.x]=0;
}
[numthreads(16,16,1)]
void TextWork(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  RefinedOut[id.y*GridSide+id.x]=TextAreas[id.y*GridSide+id.x];
}
[numthreads(16,16,1)]
void SubjectsWork(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  RefinedOut[i]=max(Actors[i],Objects[i]);
}
[numthreads(16,16,1)]
void SceneWork(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  RefinedOut[i]=max(max(Actors[i],Objects[i]),TextAreas[i]);
}
[numthreads(16,16,1)]
void RemoveTextObjects(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  ObjectsOut[i]=ObjectsOut[i]*(1.0-TextAreas[i]);
}
[numthreads(16,16,1)]
void SubjectInit(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  SeedsOut[i]=max(Actors[i],Objects[i])>0.35 ? i+1 : 0;
}
[numthreads(16,16,1)]
void SubjectUnion(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  if(SeedsOut[i]==0) return;
  bool actor=Actors[i]>0.35;
  for(int y=0;y<=1;++y) {
    for(int x=-1;x<=1;++x) {
      if(y==0 && x<=0) continue;
      int2 q=int2(id.xy)+int2(x,y);
      if(any(q<0) || any(q>=int(GridSide))) continue;
      uint n=q.y*GridSide+q.x;
      if((Actors[n]>0.35)!=actor) continue;
      uint a=ComponentRoot(i+1),b=ComponentRoot(SeedsOut[n]);
      if(a>0 && b>0 && a!=b) {
        uint old; InterlockedMin(SeedsOut[max(a,b)-1],min(a,b),old);
        if(old>min(a,b)) { uint ignored; Stats.InterlockedAdd(24,1,ignored); }
      }
    }
  }
}
[numthreads(16,16,1)]
void SubjectFallback(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  SeedsOut[i]=Actors[i]>0.35 ? 1 : (Objects[i]>0.35 ? 2 : 0);
}
[numthreads(16,16,1)]
void SceneComponentsClear(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint base=(id.y*GridSide+id.x)*16;
  ComponentWrite.Store4(base,uint4(0,0,0,0));
}
[numthreads(16,16,1)]
void SceneComponentsCount(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x,label=SubjectLabels[i];
  if(label==0) return;
  uint base=(label-1)*16,ignored;
  ComponentWrite.InterlockedAdd(base,1,ignored);
  ComponentWrite.InterlockedAdd(base+4,id.x,ignored);
  ComponentWrite.InterlockedAdd(base+8,id.y,ignored);
  if(Actors[i]>0.35) ComponentWrite.InterlockedAdd(base+12,1,ignored);
}
uint SubjectScore(uint i) {
  uint4 data=ComponentRead.Load4(i*16);
  if(data.x<48) return 0;
  float2 center=float2(data.y,data.z)/float(data.x)/GridSide;
  float centrality=1.0-0.30*saturate(length(center-0.5)*1.4142);
  float semantic=data.w>data.x/2 ? 1.30 : 0.90;
  return uint(sqrt(float(data.x))*centrality*semantic*1024);
}
[numthreads(16,16,1)]
void RankMaximum(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  if(JumpStep!=0 && i+1==Stats.Load(32)) return;
  uint score=SubjectScore(i),ignored;
  Stats.InterlockedMax(44,score,ignored);
}
[numthreads(16,16,1)]
void RankSelect(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  if(JumpStep!=0 && i+1==Stats.Load(32)) return;
  uint score=SubjectScore(i),ignored;
  if(score>0 && score==Stats.Load(44)) Stats.InterlockedMin(JumpStep==0 ? 32 : 36,i+1,ignored);
  if(JumpStep==0 && score>0) Stats.InterlockedAdd(48,1,ignored);
}
float4 TextBackdropAt(float2 uv) {
  float2 q=uv*GridSide-0.5; int2 p=int2(floor(q)); float2 f=frac(q);
  return lerp(lerp(Unpack(TextFilled[GridIndex(p)]),Unpack(TextFilled[GridIndex(p+int2(1,0))]),f.x),
    lerp(Unpack(TextFilled[GridIndex(p+int2(0,1))]),Unpack(TextFilled[GridIndex(p+1)]),f.x),f.y);
}
float InkCoverage(float3 colour,float3 backdrop,float3 ink) {
  float3 axis=ink-backdrop;
  float energy=dot(axis,axis);
  if(energy<0.01) return 0;
  float coverage=saturate(dot(colour-backdrop,axis)/energy);
  float residual=length(colour-lerp(backdrop,ink,coverage));
  return coverage*(1.0-smoothstep(0.035,0.12,residual));
}
float TextHole(float2 uv) {
  int2 p=int2(uv*GridSide);
  float peak=0;
  
  
  for(int y=-2;y<=2;++y)
    for(int x=-2;x<=2;++x) peak=max(peak,TextAreas[GridIndex(p+int2(x,y))]);
  return saturate(peak*4.0);
}
float TextAlpha(float2 uv) {
  
  
  return saturate(SampleGrid(2,uv));
}
[numthreads(16,16,1)]
void AnalyzeInk(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  float2 uv=(id.xy+0.5)/GridSide;
  if(SampleMask(uv)<0.65) return;
  float contrast=dot(SampleSource(uv).rgb-TextBackdropAt(uv).rgb,float3(0.2126,0.7152,0.0722));
  uint magnitude=uint(abs(contrast)*4096),ignored;
  Stats.InterlockedAdd(contrast>0 ? 56 : 60,magnitude,ignored);
}
[numthreads(16,16,1)]
void SetInkPolarity(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  uint i=id.y*GridSide+id.x;
  uint value=TextFilled[i]&0xffffff;
  if(Stats.Load(56)>=Stats.Load(60)) value|=0xff000000;
  FilledOut[i]=value;
}
[numthreads(16,16,1)]
void InkHistogramClear(uint3 id:SV_DispatchThreadID) {
  if(id.x>=64 || id.y>=64) return;
  ComponentWrite.Store((id.y*64+id.x)*16,0);
}
[numthreads(16,16,1)]
void InkHistogram(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  float2 uv=(id.xy+0.5)/GridSide;
  if(SampleGrid(2,uv)<0.65 || SampleMask(uv)<0.35) return;
  float3 colour=SampleSource(uv).rgb;
  float3 backdrop=TextBackdropAt(uv).rgb;
  float direction=Stats.Load(56)>=Stats.Load(60) ? 1.0 : -1.0;
  float contrast=dot(colour-backdrop,float3(0.2126,0.7152,0.0722))*direction;
  if(contrast<0.12) return;
  uint3 bin=uint3(round(saturate(colour)*15));
  uint key=(bin.r<<8)|(bin.g<<4)|bin.b,ignored;
  ComponentWrite.InterlockedAdd(key*16,uint(contrast*1024),ignored);
}
[numthreads(16,16,1)]
void InkHistogramMaximum(uint3 id:SV_DispatchThreadID) {
  if(id.x>=64 || id.y>=64) return;
  uint score=ComponentRead.Load((id.y*64+id.x)*16),ignored;
  Stats.InterlockedMax(0,score,ignored);
}
[numthreads(16,16,1)]
void InkHistogramSelect(uint3 id:SV_DispatchThreadID) {
  if(id.x>=64 || id.y>=64) return;
  uint key=id.y*64+id.x;
  if(ComponentRead.Load(key*16)!=Stats.Load(0) || Stats.Load(0)<4096) return;
  uint colour=Pack(float4(float3(key>>8,(key>>4)&15,key&15)/15.0,1)),ignored;
  Stats.InterlockedMax(52,colour,ignored);
}
[numthreads(16,16,1)]
void TextCandidate(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  float2 uv=(id.xy+0.5)/GridSide;
  float4 ink=Unpack(Stats.Load(52));
  float coverage=InkCoverage(SampleSource(uv).rgb,TextBackdropAt(uv).rgb,ink.rgb);
  RefinedOut[id.y*GridSide+id.x]=SampleGrid(2,uv)*coverage*ink.a;
}
[numthreads(16,16,1)]
void EvaluateTextCandidate(uint3 id:SV_DispatchThreadID) {
  if(id.x>=GridSide || id.y>=GridSide) return;
  float2 uv=(id.xy+0.5)/GridSide;
  float coverage=RefinedMask(id.xy); uint ignored;
  if(coverage>0.10) Stats.InterlockedAdd(60,1,ignored);
  if(SampleGrid(2,uv)<0.65) return;
  float luminance=dot(SampleSource(uv).rgb,float3(0.2126,0.7152,0.0722));
  float background=dot(TextBackdropAt(uv).rgb,float3(0.2126,0.7152,0.0722));
  
  
  if(abs(luminance-background)>0.18 && (luminance>0.70 || luminance<0.18)) {
    Stats.InterlockedAdd(48,1,ignored);
    if(coverage>0.15) Stats.InterlockedAdd(56,1,ignored);
  }
}
[numthreads(16,16,1)]
void PreserveCover(uint3 id:SV_DispatchThreadID) {
  if(id.x>=OutWidth || id.y>=OutHeight) return;
  uint i=id.y*OutWidth+id.x;
  float4 source=SampleSource((id.xy+0.5)/float2(OutWidth,OutHeight));
  source.rgb*=source.a;
  FinalMask[i]=0xffffffff;
  FinalBackground[i]=Pack(source);
}
[numthreads(16,16,1)]
void PriorityFinish(uint3 id:SV_DispatchThreadID) {
  if(id.x>=OutWidth || id.y>=OutHeight) return;
  uint i=id.y*OutWidth+id.x;
  float2 uv=(id.xy+0.5)/float2(OutWidth,OutHeight);
  float text=TextAlpha(uv);
  float subject=max(SampleGrid(0,uv),SampleGrid(1,uv));
  uint label=0;
  int2 p=int2(uv*GridSide);
  for(int y=-3;y<=3;++y) {
    for(int x=-3;x<=3;++x) {
      uint found=SubjectLabels[GridIndex(p+int2(x,y))];
      if(found>0 && (label==0 || found<label)) label=found;
    }
  }
  float3 tiers=0;
  if(label>0) {
    float value=subject;
    if(label==Stats.Load(32)) tiers.r=value;
    else if(label==Stats.Load(36)) tiers.g=value;
    else tiers.b=value;
  }
  float hole=max(subject,TextHole(uv));
  PriorityOut[i]=Pack(float4(tiers,hole));
  float4 repaired=TextBackdropAt(uv);
  repaired.a=text; repaired.rgb*=text;
  TextRepairOut[i]=Pack(repaired);
}
[numthreads(16,16,1)]
void SceneBackgroundFinish(uint3 id:SV_DispatchThreadID) {
  if(id.x>=OutWidth || id.y>=OutHeight) return;
  uint i=id.y*OutWidth+id.x;
  float2 uv=(id.xy+0.5)/float2(OutWidth,OutHeight);
  float4 original=SampleSource(uv),filled=BackgroundAt(uv);
  float hole=max(max(SampleGrid(0,uv),SampleGrid(1,uv)),TextHole(uv));
  float4 result=hole>0.01 ? filled : original;
  result.rgb*=result.a;
  FinalBackground[i]=Pack(result);
}

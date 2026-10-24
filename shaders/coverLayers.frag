#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uCrop;
uniform vec2 uPointer;
uniform float uReveal;
uniform vec2 uOriginalSize;
uniform vec2 uMaskSize;
uniform vec2 uBackgroundSize;
uniform float uHasScene;
uniform float uPixelScale;
uniform sampler2D uOriginal;
uniform sampler2D uMask;
uniform sampler2D uBackground;
uniform sampler2D uPriority;
uniform sampler2D uTextRepair;
out vec4 fragColor;
vec4 fetchPixel(int kind, vec2 uv) {
  if (kind == 0) return texture(uOriginal, uv);
  if (kind == 1) return texture(uMask, uv);
  if (kind == 2) return texture(uBackground, uv);
  if (kind == 3) return texture(uPriority,uv);
  return texture(uTextRepair,uv);
}
vec4 sampleSmooth(int kind, vec2 uv, vec2 size) {
  vec2 p = clamp(uv * size - 0.5, vec2(0.0), size - 1.0);
  vec2 base = floor(p), f = fract(p);
  vec2 a = (base + 0.5) / size;
  vec2 step = 1.0 / size;
  return mix(mix(fetchPixel(kind, a), fetchPixel(kind, a + vec2(step.x, 0.0)), f.x),
      mix(fetchPixel(kind, a + vec2(0.0, step.y)), fetchPixel(kind, a + step), f.x), f.y);
}
vec4 sampleColour(vec2 uv) {
  vec2 footprint=uCrop.zw/(uSize*max(uPixelScale,1.0));
  if(max(footprint.x*uOriginalSize.x,footprint.y*uOriginalSize.y)<1.2)
    return sampleSmooth(0,uv,uOriginalSize);
  vec2 offset=footprint/3.0;
  vec4 total=vec4(0.0);
  for(int y=-1;y<=1;y++) {
    for(int x=-1;x<=1;x++) {
      total+=sampleSmooth(0,uv+vec2(float(x),float(y))*offset,uOriginalSize);
    }
  }
  return total/9.0;
}
vec4 subjectLayer(vec2 uv,int tier) {
  vec4 priority=sampleSmooth(3,uv,uMaskSize);
  float matte=tier==0 ? priority.r : (tier==1 ? priority.g : priority.b);
  if(matte<0.00001) return vec4(0.0);
  vec4 source=sampleColour(uv);
  vec4 repair=sampleSmooth(4,uv,uMaskSize);
  float ink=smoothstep(0.002,0.025,repair.a);
  vec3 restored=repair.a>0.001 ? repair.rgb/max(repair.a,0.001) : source.rgb;
  source.rgb=mix(source.rgb,restored*source.a,ink);
  return source*matte;
}
void main() {
  vec2 q = FlutterFragCoord().xy / uSize;
  vec2 uv = uCrop.xy + q * uCrop.zw;
  
  
  vec2 pointer = uPointer * clamp(uReveal, 0.0, 1.0);
  float weight = smoothstep(0.0, 0.08, length(pointer));
  if (weight < 0.00001) { fragColor = sampleColour(uv); return; }
  if (uHasScene>0.5) {
    vec2 backUv=uv+pointer*0.004*uCrop.zw;
    float hole=sampleSmooth(3,backUv,uMaskSize).a;
    float repaired=smoothstep(0.01,0.06,hole);
    vec4 background;
    if(repaired<0.00001) background=sampleColour(backUv);
    else if(repaired>0.99999) background=sampleSmooth(2,backUv,uBackgroundSize);
    else background=mix(sampleColour(backUv),sampleSmooth(2,backUv,uBackgroundSize),repaired);
    vec4 farLayer=subjectLayer(uv-pointer*0.005*uCrop.zw,2);
    vec4 middle=subjectLayer(uv-pointer*0.011*uCrop.zw,1);
    vec4 mainLayer=subjectLayer(uv-pointer*0.019*uCrop.zw,0);
    vec2 inkUv=uv-pointer*0.025*uCrop.zw;
    vec4 inkRepair=sampleSmooth(4,inkUv,uMaskSize);
    float ink=inkRepair.a;
    vec4 lettering=vec4(0.0);
    if(ink>0.00001) {
      vec4 source=sampleColour(inkUv);
      vec3 backdrop=inkRepair.rgb/ink;
      
      
      float coverage=source.a*ink;
      vec3 colour=clamp(source.rgb-backdrop*source.a*(1.0-ink),
          vec3(0.0),vec3(coverage));
      lettering=vec4(colour,coverage);
    }
    vec4 scene=farLayer+background*(1.0-farLayer.a);
    scene=middle+scene*(1.0-middle.a);
    scene=mainLayer+scene*(1.0-mainLayer.a);
    scene=lettering+scene*(1.0-lettering.a);
    fragColor=weight>0.99999 ? scene : mix(sampleColour(uv),scene,weight); return;
  }
  vec2 frontUv = uv - pointer * 0.016 * uCrop.zw;
  vec2 backUv = uv + pointer * 0.004 * uCrop.zw;
  vec4 front = sampleColour(frontUv);
  float matte = sampleSmooth(1, frontUv, uMaskSize).r;
  vec4 edgeBackdrop = sampleSmooth(2, frontUv, uBackgroundSize);
  
  
  vec3 unmixed = clamp(front.rgb - edgeBackdrop.rgb * (1.0-matte),
      front.rgb*matte - vec3(0.10), front.rgb*matte + vec3(0.10));
  float edgeWeight = smoothstep(0.02,0.15,matte) * (1.0-smoothstep(0.85,0.99,matte));
  front.rgb = mix(front.rgb*matte, max(unmixed,vec3(0.0)), edgeWeight*0.65);
  front.a *= matte;
  front.rgb = clamp(front.rgb, vec3(0.0), vec3(front.a));
  vec4 background = sampleSmooth(2, backUv, uBackgroundSize);
  vec4 scene = front + background * (1.0 - front.a);
  
  
  fragColor = mix(sampleColour(uv), scene, weight);
}

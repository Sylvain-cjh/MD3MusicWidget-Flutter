#version 460 core
#include <flutter/runtime_effect.glsl>
uniform vec2 uSize;
uniform vec4 uCrop;
uniform vec2 uPointer;
uniform float uReveal;
uniform vec2 uOriginalSize;
uniform vec2 uMaskSize;
uniform vec2 uBackgroundSize;
uniform float uPixelScale;
uniform sampler2D uOriginal;
uniform sampler2D uMask;
uniform sampler2D uBackground;
out vec4 fragColor;
vec2 clampedUv(vec2 uv,vec2 size) {
  
  
  return (clamp(uv*size-0.5,vec2(0.0),size-1.0)+0.5)/size;
}
vec4 sampleColour(vec2 uv) {
  vec2 footprint=uCrop.zw/(uSize*max(uPixelScale,1.0));
  if(max(footprint.x*uOriginalSize.x,footprint.y*uOriginalSize.y)<1.2)
    return texture(uOriginal,clampedUv(uv,uOriginalSize));
  vec2 offset=footprint/3.0;
  vec4 total=vec4(0.0);
  for(int y=-1;y<=1;y++) {
    for(int x=-1;x<=1;x++) {
      total+=texture(uOriginal,clampedUv(uv+vec2(float(x),float(y))*offset,uOriginalSize));
    }
  }
  return total/9.0;
}
void main() {
  vec2 uv=uCrop.xy+FlutterFragCoord().xy/uSize*uCrop.zw;
  vec2 pointer=uPointer*clamp(uReveal,0.0,1.0);
  float weight=smoothstep(0.0,0.08,length(pointer));
  if(weight<0.00001) { fragColor=sampleColour(uv); return; }
  vec2 frontUv=uv-pointer*0.016*uCrop.zw;
  vec2 backUv=uv+pointer*0.004*uCrop.zw;
  vec4 front=sampleColour(frontUv);
  float matte=texture(uMask,clampedUv(frontUv,uMaskSize)).r;
  vec4 edgeBackdrop=texture(uBackground,clampedUv(frontUv,uBackgroundSize));
  vec3 unmixed=clamp(front.rgb-edgeBackdrop.rgb*(1.0-matte),
    front.rgb*matte-vec3(0.10),front.rgb*matte+vec3(0.10));
  float edgeWeight=smoothstep(0.02,0.15,matte)*(1.0-smoothstep(0.85,0.99,matte));
  front.rgb=mix(front.rgb*matte,max(unmixed,vec3(0.0)),edgeWeight*0.65);
  front.a*=matte;
  front.rgb=clamp(front.rgb,vec3(0.0),vec3(front.a));
  vec4 background=texture(uBackground,clampedUv(backUv,uBackgroundSize));
  vec4 scene=front+background*(1.0-front.a);
  fragColor=mix(sampleColour(uv),scene,weight);
}

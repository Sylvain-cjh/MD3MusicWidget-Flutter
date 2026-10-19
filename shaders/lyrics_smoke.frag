#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uAtlasSize;
uniform vec4 uWord;
uniform float uPhase;
uniform float uSeed;
uniform vec2 uInkBand;
uniform sampler2D uInk;
out vec4 fragColor;

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 345.45));
  p += dot(p, p + 34.345);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash21(i), hash21(i + vec2(1.0, 0.0)), f.x),
             mix(hash21(i + vec2(0.0, 1.0)), hash21(i + 1.0), f.x), f.y);
}

vec4 inkAt(vec2 p) {
  vec2 hi = uWord.xy + uWord.zw;
  float inside = step(uWord.x, p.x) * step(p.x, hi.x)
               * step(uWord.y, p.y) * step(p.y, hi.y)
               * step(0.0, p.x) * step(p.x, uAtlasSize.x)
               * step(0.0, p.y) * step(p.y, uAtlasSize.y);
  vec2 uv = p / uAtlasSize;
  uv.y = uInkBand.x + uv.y * uInkBand.y;
  return texture(uInk, uv) * inside;
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  float t = clamp(uPhase, 0.0, 1.0);
  float ease = 1.0 - pow(1.0 - t, 3.0);
  float h = uWord.w;
  vec2 q = (p - uWord.xy) / max(h, 1.0);
  vec2 drift = vec2((0.12 + 0.07 * sin(uSeed)) * h * ease,
                   -0.50 * h * ease);
  float curl = noise(q * 2.1 + vec2(uSeed, -t * 0.8));
  vec2 flow = vec2(sin(q.y * 3.0 + uSeed + t * 2.0), curl - 0.5);
  vec2 source = p - drift - flow * (h * 0.18 * t);
  float radius = h * 0.26 * t;
  vec4 ink = inkAt(source) * 0.20;
  ink += inkAt(source + vec2(radius, 0.0)) * 0.12;
  ink += inkAt(source - vec2(radius, 0.0)) * 0.12;
  ink += inkAt(source + vec2(0.0, radius)) * 0.12;
  ink += inkAt(source - vec2(0.0, radius)) * 0.12;
  vec2 diagonal = vec2(radius * 0.707);
  ink += inkAt(source + diagonal) * 0.08;
  ink += inkAt(source - diagonal) * 0.08;
  ink += inkAt(source + vec2(diagonal.x, -diagonal.y)) * 0.08;
  ink += inkAt(source + vec2(-diagonal.x, diagonal.y)) * 0.08;
  float veil = noise(q * 3.4 + vec2(uSeed, t * 0.35));
  float erosion = mix(1.0, smoothstep(t - 0.20, t + 0.20, veil),
                      smoothstep(0.08, 0.65, t));
  fragColor = ink * erosion * (1.0 - smoothstep(0.08, 1.0, t));
}

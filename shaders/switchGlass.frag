#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec4 uTrackRect;
uniform vec4 uKnobRect;
uniform vec3 uTrackColor;
uniform vec3 uSurround;
uniform vec3 uRest;
uniform float uPress;
uniform vec4 uSampleRect;
uniform float uSceneMix;
uniform vec2 uControlSize;
uniform float uValue;
uniform sampler2D uScene;
out vec4 fragColor;

const vec3 luma = vec3(0.2126, 0.7152, 0.0722);
const vec2 light = vec2(-0.48, -0.877);


vec3 capsule(vec2 p, vec4 bounds) {
  vec2 halfSize = bounds.zw * 0.5;
  vec2 local = p - bounds.xy - halfSize;
  float radius = halfSize.y;
  vec2 spine = vec2(clamp(local.x, radius - halfSize.x, halfSize.x - radius), 0.0);
  vec2 toEdge = local - spine;
  float depth = length(toEdge);
  return vec3(depth - radius, toEdge / max(depth, 0.001));
}

float shoulder(float sd, float width) {
  float t = clamp(1.0 + sd / width, 0.0, 1.0);
  return t * t * (2.0 - t);
}

vec3 sceneAt(vec2 p) {
  if (uSceneMix <= 0.001) return uSurround;
  vec2 uv = clamp(uSampleRect.xy + p / uControlSize * uSampleRect.zw, 0.0, 1.0);
  vec4 sampleColor = texture(uScene, uv);
  vec3 scene = sampleColor.rgb + uSurround * (1.0 - sampleColor.a);
  float luminance = dot(scene, luma);
  scene = clamp(scene + (scene - luminance) * 0.12, 0.0, 1.0);
  return mix(uSurround, scene, 0.74 * uSceneMix);
}

vec3 glassTrack(vec2 p, vec3 shape) {
  float edge = shoulder(shape.x, 7.0);
  vec3 scene = sceneAt(p + shape.yz * (4.8 * edge));
  float weight = (0.57 + 0.19 * uValue) - 0.20 * edge;
  vec3 base = mix(scene, uTrackColor, weight);
  float rim = 1.0 - smoothstep(0.12, 1.25, abs(shape.x));
  float exposure = dot(base, luma);
  float key = smoothstep(-0.10, 1.0, dot(shape.yz, light));
  return mix(base * (1.0 - edge * (1.0 - key) * 0.14),
             vec3(1.0), rim * key * mix(0.30, 0.14, exposure));
}

vec3 layersAt(vec2 p) {
  vec3 track = capsule(p, uTrackRect);
  if (track.x < -0.65) return glassTrack(p, track);
  vec3 scene = sceneAt(p);
  if (track.x > 0.65) return scene;
  return mix(glassTrack(p, track), scene, smoothstep(-0.65, 0.65, track.x));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec3 track = capsule(p, uTrackRect);
  vec3 knob = capsule(p, uKnobRect);
  if (knob.x > 1.8) {
    fragColor = vec4(glassTrack(p, track), 1.0);
    return;
  }
  vec3 base = glassTrack(p, track);
  float contact = smoothstep(-0.7, 1.0, knob.x)
                * (1.0 - smoothstep(0.8, 1.8, knob.x));
  base *= 1.0 - contact * (0.11 + uPress * 0.05);
  if (knob.x > 0.55 && track.x < -0.55) {
    fragColor = vec4(base, 1.0);
    return;
  }

  
  
  float edge = shoulder(knob.x, 7.6 + uPress * 2.1);
  vec2 center = uKnobRect.xy + uKnobRect.zw * 0.5;
  vec2 bend = p - (p - center) * (0.016 + 0.055 * uPress)
            + knob.yz * edge * (8.8 + 4.0 * uPress);
  vec3 optical = layersAt(bend);
  if (edge > 0.48) {
    vec2 split = knob.yz * edge * edge * (0.35 + 0.60 * uPress);
    optical.r = layersAt(bend + split).r;
    optical.b = layersAt(bend - split).b;
  }
  float exposure = dot(optical, luma);
  float key = smoothstep(0.0, 0.96, dot(knob.yz, light));
  float bounce = smoothstep(0.32, 1.0, dot(knob.yz, -light));
  float rim = 1.0 - smoothstep(0.04, 1.25, abs(knob.x));
  float lip = smoothstep(0.10, 0.54, edge) * (1.0 - smoothstep(0.65, 0.97, edge));
  vec3 glass = mix(optical, uRest, (0.46 - 0.21 * uPress) * (1.0 - 0.72 * edge));
  glass *= 1.0 - lip * (0.14 * key + 0.09 * bounce);
  glass = mix(glass, vec3(1.0),
              rim * (key * mix(0.59, 0.36, exposure) + bounce * 0.22)
              + lip * bounce * 0.13);
  
  float mask = track.x > 0.55 && knob.x < 0.55
             ? 1.0 : 1.0 - smoothstep(-0.55, 0.55, knob.x);
  fragColor = vec4(mix(base, glass, mask), 1.0);
}

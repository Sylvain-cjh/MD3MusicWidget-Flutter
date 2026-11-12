#version 460 core
#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform vec4 uSampleRect;
uniform vec4 uTint;
uniform float uRadius;
uniform float uPress;
uniform float uDark;
uniform vec4 uThumbOnTrack;
uniform vec2 uTrackSize;
uniform vec4 uTrackColor;
uniform float uTrackRadius;
uniform vec2 uTexelInset;
uniform float uHasGlyphs;
uniform float uTrackPass;
uniform sampler2D uBackdrop;
uniform sampler2D uGlyphs;
out vec4 fragColor;

float cornerLength(vec2 v) {
  vec2 v2 = v * v;
  return mix(length(v), sqrt(sqrt(dot(v2, v2))), 0.60);
}

vec4 sceneAt(vec2 uv) {
  return texture(uBackdrop, clamp(uv, uTexelInset, 1.0 - uTexelInset));
}

void main() {
  vec2 p = FlutterFragCoord().xy;
  vec2 halfSize = uSize * 0.5;
  vec2 centered = p - halfSize;
  vec2 q = abs(centered) - (halfSize - vec2(uRadius));
  vec2 corner = max(q, 0.0);
  vec2 squared = corner * corner;
  
  
  float cornerDist = cornerLength(corner);
  float distanceInside = max(0.0, uRadius - cornerDist - min(max(q.x, q.y), 0.0));
  float across = smoothstep(-1.8, 1.8, q.y - q.x);
  vec2 axis = vec2(1.0 - across, across);
  vec2 cornerNormal = mix(corner, squared / max(cornerDist, 0.001), 0.60);
  vec2 normal = normalize(mix(axis, cornerNormal, smoothstep(0.0, 1.8, cornerDist)))
              * sign(centered);

  
  
  bool trackPass = uTrackPass > 0.5;
  float bevelWidth = min(min(uSize.x, uSize.y) * 0.42,
                         trackPass ? 18.0 : 13.0 + 6.0 * uPress);
  float bevel = 1.0 - smoothstep(0.0, bevelWidth, distanceInside);
  vec3 surfaceNormal = normalize(vec3(normal * bevel * 2.1, 1.0));
  vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 1.0 / 1.48);
  vec2 lensBody = trackPass ? p : halfSize + centered * (0.975 - 0.08 * uPress);
  vec2 displaced = lensBody - (ray.xy / max(-ray.z, 0.2))
                 * (trackPass ? 26.0 : 30.0 + 20.0 * uPress);
  vec2 uvPerUnit = uSampleRect.zw / uSize;
  vec2 uv = uSampleRect.xy + displaced * uvPerUnit;
  vec4 under = sceneAt(uv);
  const vec3 lumaWeights = vec3(0.2126, 0.7152, 0.0722);
  if (trackPass) {
    
    vec2 blur = vec2(0.8, 1.15) * uvPerUnit;
    under = under * 0.60 + (sceneAt(uv + blur) + sceneAt(uv - blur)) * 0.20;
    vec3 scene = under.rgb + uTint.rgb * (1.0 - under.a);
    float brightness = dot(scene, lumaWeights);
    scene = clamp(scene + (scene - brightness) * 0.10, 0.0, 1.0);
    vec3 material = mix(scene, uTint.rgb, uTint.a * (1.0 - 0.38 * bevel));
    float light = dot(normal, vec2(-0.45, -0.89));
    float rim = 1.0 - smoothstep(0.12, 1.25, distanceInside);
    float highlight = mix(0.44, 0.16, brightness);
    material *= 1.0 - bevel * (1.0 - rim) * max(0.0, -light) * 0.12;
    material = mix(material, vec3(1.0), rim * smoothstep(-0.12, 0.94, light) * highlight);
    fragColor = vec4(material, 1.0);
    return;
  }
  
  
  float dispersion = smoothstep(0.25, 0.95, bevel) * (1.45 + 0.85 * uPress);
  if (dispersion > 0.04) {
    vec2 spread = normal * dispersion * uvPerUnit;
    under.r = sceneAt(uv + spread).r;
    under.b = sceneAt(uv - spread).b;
  }
  vec3 background = under.rgb + uTint.rgb * (1.0 - under.a);
  float ambient = dot(background, lumaWeights);
  float chroma = max(background.r, max(background.g, background.b))
               - min(background.r, min(background.g, background.b));
  float vibrancy = (0.07 + 0.09 * bevel) * (1.0 - smoothstep(0.26, 0.88, chroma));
  background = clamp(background + (background - ambient) * vibrancy, 0.0, 1.0);

  
  
  vec2 trackPoint = (uThumbOnTrack.xy
                   + displaced / uSize * uThumbOnTrack.zw) * uTrackSize;
  float trackRadius = min(uTrackRadius, min(uTrackSize.x, uTrackSize.y) * 0.5);
  vec2 trackQ = abs(trackPoint - uTrackSize * 0.5)
              - (uTrackSize * 0.5 - trackRadius);
  float trackEdge = cornerLength(max(trackQ, 0.0))
                  + min(max(trackQ.x, trackQ.y), 0.0) - trackRadius;
  float trackAlpha = uTrackColor.a * (0.60 - 0.36 * bevel)
                   * (1.0 - smoothstep(-0.7, 0.7, trackEdge));
  vec3 opticalScene = mix(background, uTrackColor.rgb, trackAlpha);
  vec3 surface = mix(opticalScene, uTint.rgb, uTint.a * (1.0 - bevel * 0.75));
  
  
  float value = dot(surface, lumaWeights);
  vec3 contrastBase = mix(vec3(0.98), vec3(0.07), uDark);
  float correction = mix(1.0 - smoothstep(0.34, 0.63, value),
                         smoothstep(0.30, 0.66, value), uDark);
  surface = mix(surface, contrastBase, correction * (0.54 - 0.39 * bevel));

  float specularAxis = dot(normal, vec2(-0.45, -0.89));
  float upper = smoothstep(0.16, 0.96, specularAxis);
  float lower = smoothstep(0.36, 1.0, -specularAxis);
  float rim = 1.0 - smoothstep(0.14, 1.32, distanceInside);
  float lightResponse = mix(0.49, 0.24, smoothstep(0.12, 0.76, ambient));
  float glint = rim * (upper * (lightResponse + 0.15 * uPress) + lower * 0.12);
  float caustic = smoothstep(0.27, 0.64, bevel)
                * (1.0 - smoothstep(0.69, 0.93, bevel));
  surface *= 1.0 - caustic * upper * (0.045 + ambient * 0.10);
  surface = mix(surface, vec3(1.0), glint + caustic * lower * (0.065 + 0.06 * uPress));
  if (uHasGlyphs > 0.5) {
    
    
    
    vec2 glyphPoint = mix(p, displaced, smoothstep(0.0, 0.88, uPress) * 0.88);
    vec2 glyphUv = uThumbOnTrack.xy + glyphPoint / uSize * uThumbOnTrack.zw;
    if (all(greaterThanEqual(glyphUv, vec2(0.0))) &&
        all(lessThan(glyphUv, vec2(1.0)))) {
      vec4 ink = texture(uGlyphs, glyphUv);
      surface = ink.rgb + surface * (1.0 - ink.a);
    }
  }
  fragColor = vec4(surface, 1.0);
}

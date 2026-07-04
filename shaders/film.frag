#version 460 core

// Shader màu phim của Doka App.
//
// Dùng ở 2 chế độ:
//  1. ImageFilter.shader (preview real-time): engine tự set u_size (2 float
//     đầu) và sampler đầu tiên = nội dung được filter.
//  2. Paint shader (bake ảnh full-res): phía Dart tự set toàn bộ uniform,
//     kể cả u_size và u_texture.
//
// Toàn bộ hiệu ứng là color-map theo từng pixel (không lấy mẫu lệch toạ độ),
// nên không bị ảnh hưởng bởi việc đảo trục Y trên backend GLES.
//
// Thứ tự float uniform phải khớp packFilmUniforms() trong
// lib/src/features/filters/film_shader.dart.

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;                 // float 0,1
uniform float u_exposure;            // float 2   (EV, -1..1)
uniform float u_contrast;            // float 3   (1.0 = trung tính)
uniform float u_saturation;          // float 4   (1.0 = trung tính, 0 = B&W)
uniform float u_temperature;         // float 5   (-1 lạnh .. 1 ấm)
uniform float u_tint;                // float 6   (-1 xanh lá .. 1 hồng tím)
uniform float u_fade;                // float 7   (0..1, nâng điểm đen kiểu phim)
uniform float u_vignette;            // float 8   (0..1)
uniform float u_grain;               // float 9   (0..1)
uniform float u_seed;                // float 10  (seed nhiễu hạt)
uniform vec3 u_shadow_tint;          // float 11,12,13
uniform float u_shadow_strength;     // float 14
uniform vec3 u_highlight_tint;       // float 15,16,17
uniform float u_highlight_strength;  // float 18
uniform sampler2D u_texture;

out vec4 frag_color;

float hash(vec2 p) {
  vec3 p3 = fract(vec3(p.xyx) * 0.1031);
  p3 += dot(p3, p3.yzx + 33.33);
  return fract((p3.x + p3.y) * p3.z);
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / u_size;
  vec3 c = texture(u_texture, uv).rgb;

  // Phơi sáng
  c *= exp2(u_exposure);

  // Cân bằng trắng đơn giản theo kênh
  c.r *= 1.0 + 0.10 * u_temperature;
  c.b *= 1.0 - 0.10 * u_temperature;
  c.g *= 1.0 - 0.07 * u_tint;

  // Tương phản quanh điểm xám kiểu phim
  c = (c - 0.46) * u_contrast + 0.46;

  // Bão hoà
  float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
  c = mix(vec3(luma), c, u_saturation);

  // Split-tone: ám màu vùng tối / vùng sáng
  float shadowW = 1.0 - smoothstep(0.0, 0.5, luma);
  float highW = smoothstep(0.5, 1.0, luma);
  c = mix(c, u_shadow_tint, shadowW * u_shadow_strength);
  c = mix(c, u_highlight_tint, highW * u_highlight_strength);

  // Fade: nâng điểm đen
  float lift = u_fade * 0.18;
  c = c * (1.0 - lift) + lift;

  // Vignette
  vec2 d = uv - 0.5;
  d.x *= u_size.x / max(u_size.y, 1.0);
  float v = smoothstep(0.35, 0.95, length(d));
  c *= 1.0 - u_vignette * 0.55 * v;

  // Hạt phim
  float n = hash(frag + vec2(u_seed, u_seed * 1.7));
  c += (n - 0.5) * u_grain * 0.10;

  frag_color = vec4(clamp(c, 0.0, 1.0), 1.0);
}

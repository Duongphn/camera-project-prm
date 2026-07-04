#version 460 core

// Shader làm mịn da (beauty) của Doka App.
//
// Cách hoạt động: mặt nạ tông màu da theo dải Cb/Cr (YCbCr), sau đó blur
// bilateral 12 tap chỉ trên vùng da — giữ cạnh (tóc, mắt, nền) sắc nét.
// Kernel đối xứng theo cả hai trục nên an toàn với backend GLES đảo trục Y.
//
// Dùng ở 2 chế độ như film.frag: ImageFilter.shader (preview) và
// Paint shader (bake). Thứ tự float uniform khớp packBeautyUniforms().

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform vec2 u_size;       // float 0,1
uniform float u_intensity; // float 2 (0..1)
uniform sampler2D u_texture;

out vec4 frag_color;

float lumaOf(vec3 c) {
  return dot(c, vec3(0.299, 0.587, 0.114));
}

// Mặt nạ da: Cb ~ [0.30, 0.50], Cr ~ [0.52, 0.68], không quá tối.
float skinMask(vec3 c) {
  float y = lumaOf(c);
  float cb = 0.5 - 0.168736 * c.r - 0.331264 * c.g + 0.5 * c.b;
  float cr = 0.5 + 0.5 * c.r - 0.418688 * c.g - 0.081312 * c.b;
  float mcb = smoothstep(0.29, 0.33, cb) * (1.0 - smoothstep(0.47, 0.51, cb));
  float mcr = smoothstep(0.50, 0.54, cr) * (1.0 - smoothstep(0.66, 0.70, cr));
  float my = smoothstep(0.12, 0.25, y);
  return mcb * mcr * my;
}

void tap(vec2 uv, vec2 offset, vec3 center, inout vec3 sum, inout float wsum) {
  vec3 s = texture(u_texture, uv + offset).rgb;
  float d = distance(s, center);
  float w = exp(-d * d * 60.0);
  sum += s * w;
  wsum += w;
}

void main() {
  vec2 frag = FlutterFragCoord().xy;
  vec2 uv = frag / u_size;
  vec3 center = texture(u_texture, uv).rgb;

  float mask = skinMask(center) * clamp(u_intensity, 0.0, 1.0);
  if (mask < 0.01) {
    frag_color = vec4(center, 1.0);
    return;
  }

  // Bán kính blur theo độ phân giải để preview và bake full-res trông giống nhau.
  vec2 texel = 1.0 / u_size;
  float radius = max(u_size.x, u_size.y) / 1080.0 * 3.5;
  vec2 s = texel * radius;

  vec3 sum = center;
  float wsum = 1.0;
  tap(uv, vec2(1.0, 0.0) * s, center, sum, wsum);
  tap(uv, vec2(-1.0, 0.0) * s, center, sum, wsum);
  tap(uv, vec2(0.0, 1.0) * s, center, sum, wsum);
  tap(uv, vec2(0.0, -1.0) * s, center, sum, wsum);
  tap(uv, vec2(0.7, 0.7) * s, center, sum, wsum);
  tap(uv, vec2(-0.7, 0.7) * s, center, sum, wsum);
  tap(uv, vec2(0.7, -0.7) * s, center, sum, wsum);
  tap(uv, vec2(-0.7, -0.7) * s, center, sum, wsum);
  tap(uv, vec2(2.0, 0.0) * s, center, sum, wsum);
  tap(uv, vec2(-2.0, 0.0) * s, center, sum, wsum);
  tap(uv, vec2(0.0, 2.0) * s, center, sum, wsum);
  tap(uv, vec2(0.0, -2.0) * s, center, sum, wsum);

  vec3 smoothed = sum / wsum;
  vec3 c = mix(center, smoothed, mask);
  c *= 1.0 + 0.05 * mask; // sáng da nhẹ

  frag_color = vec4(clamp(c, 0.0, 1.0), 1.0);
}

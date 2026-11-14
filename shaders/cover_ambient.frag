#version 460 core

precision highp float;

#include <flutter/runtime_effect.glsl>

uniform sampler2D u_texture;
uniform float u_time;
uniform float u_scale;
uniform vec3 u_tint;

out vec4 fragColor;

void main() {
  vec2 uv = FlutterFragCoord().xy * u_scale;
  vec4 tex = texture(u_texture, uv);

  float t = u_time * 0.1;
  float mask = 0.5 + 0.5 * sin(t * 2.0 + uv.x * 20.0 + uv.y * 14.0);
  vec3 color = tex.rgb;
  color = mix(color, u_tint, 0.25 * mask);
  color *= 0.75 + 0.4 * mask;

  fragColor = vec4(color, tex.a);
}

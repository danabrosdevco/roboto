shader_type sky;

uniform vec4 top_color : source_color = vec4(0.2, 0.4, 0.6, 1.0);   // Sky blue
uniform vec4 bottom_color : source_color = vec4(0.7, 0.7, 0.8, 1.0); // Horizon white/blue
uniform float horizon_falloff : hint_range(0.01, 5.0) = 1.5;

void sky() {
    float t = pow(clamp(SKY_COORDS.y * 0.5 + 0.5, 0.0, 1.0), horizon_falloff);
    COLOR = mix(bottom_color.rgb, top_color.rgb, t);
}

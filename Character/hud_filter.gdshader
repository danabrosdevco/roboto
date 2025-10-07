shader_type canvas_item;

uniform vec3 tint_color : source_color = vec3(1.0, 0.1, 0.1); // deep red
uniform float grit_strength : hint_range(0.0, 1.0) = 0.25; // noise intensity
uniform float scanline_strength : hint_range(0.0, 1.0) = 0.2; // horizontal grain
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float time_speed : hint_range(0.0, 5.0) = 1.0; // animation speed

// Simple 2D hash noise (very cheap)
float hash(vec2 p) {
    p = fract(p * vec2(123.34, 345.45));
    p += dot(p, p + 34.345);
    return fract(p.x * p.y);
}

void fragment() {
    vec2 uv = UV; // Built-in normalized coordinates (0–1 range)

    // Base red tint
    vec3 color = tint_color * brightness;

    // Scanline effect (horizontal intensity variation)
    float scan = sin(uv.y * 800.0) * 0.5 + 0.5; // 800.0 = number of lines
    color *= mix(1.0, scan, scanline_strength);

    // Animated gritty noise
    float t = TIME * time_speed;
    float grain = hash(uv * vec2(600.0, 400.0) + t) * 2.0 - 1.0;
    color += grain * grit_strength; // ✅ semicolon added here

    COLOR = vec4(clamp(color, 0.0, 1.0), 1.0);
}

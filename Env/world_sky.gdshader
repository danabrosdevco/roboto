shader_type sky;

// Flat or gradient sky colors
uniform vec3 zenith_color  : source_color = vec3(0.1, 0.2, 0.5);   // top color
uniform vec3 horizon_color : source_color = vec3(0.4, 0.6, 0.9);  // bottom color
uniform float horizon_sharpness = 1.5; // how smooth the blend is

void sky() {
    vec3 dir = normalize(EYEDIR);

    // simple gradient based on upward direction
    float t = clamp(dir.y * 0.5 + 0.5, 0.0, 1.0);
    float k = pow(t, horizon_sharpness);

    // blend between horizon and zenith colors
    vec3 color = mix(horizon_color, zenith_color, k);

    COLOR = color;
}

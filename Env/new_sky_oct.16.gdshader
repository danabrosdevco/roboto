shader_type sky;

uniform vec4 top_color : source_color = vec4(0.08, 0.13, 0.20, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.28, 0.30, 0.32, 1.0);

uniform vec4 fog_color : source_color = vec4(0.32, 0.34, 0.35, 1.0);

uniform float horizon_falloff : hint_range(0.01, 5.0) = 1.5;
uniform float fog_amount : hint_range(0.0, 1.0) = 0.45;
uniform float fog_falloff : hint_range(0.1, 10.0) = 3.0;

uniform float brightness : hint_range(0.0, 2.0) = 0.7;

void sky() {
    // Basic vertical sky gradient.
    float height = clamp(SKY_COORDS.y * 0.5 + 0.5, 0.0, 1.0);
    float t = pow(height, horizon_falloff);

    vec3 sky_color = mix(
        bottom_color.rgb,
        top_color.rgb,
        t
    );

    // Strongest fog/haze around the horizon.
    float horizon = 1.0 - abs(EYEDIR.y);
    float haze = pow(horizon, fog_falloff) * fog_amount;

    sky_color = mix(
        sky_color,
        fog_color.rgb,
        haze
    );

    // Globally reduce the brightness of the background.
    sky_color *= brightness;

    COLOR = sky_color;
}
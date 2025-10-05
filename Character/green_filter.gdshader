shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture,filter_linear_mipmap;
uniform float posterize_levels = 4.0;
uniform float contrast = 1.2;
uniform vec3 tint_color = vec3(0.145, 0.588, 0.745); // greenish tone
uniform float fog_strength = 1.0;
uniform float fog_depth_start = 0.2;
uniform float fog_depth_end = 0.8;

vec3 posterize(vec3 color, int levels) {
	color *= float(levels);
	color = floor(color);
	color /= float(levels - 1);
	return color;
}

float get_depth_fog(vec2 uv) {
	// vertical gradient fake fog
	return clamp((uv.y - fog_depth_start) / (fog_depth_end - fog_depth_start), 0.0, 1.0);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = texture(SCREEN_TEXTURE, uv).rgb;

	base = (base - 0.5) * contrast + 0.5;

	int levels = int(clamp(posterize_levels, 2.0, 16.0));
	vec3 color = posterize(base, levels);

	// Greenish fog blend
	float fog = get_depth_fog(uv);
	float brightness = dot(color, vec3(0.299, 0.587, 0.114));
	color = tint_color * brightness;
	COLOR = vec4(color, 1.0);
}

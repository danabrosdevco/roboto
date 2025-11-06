shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture,filter_linear_mipmap;
uniform float posterize_levels = 4.0;
uniform float contrast = 1.2;
uniform vec3 tint_color = vec3(0.145, 0.588, 0.745); // greenish tone

vec3 posterize(vec3 color, float levels) {
	color *= levels;
	color = floor(color);
	color /= (levels - 1.0);
	return color;
}


void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 base = texture(SCREEN_TEXTURE, uv).rgb;
	base = (base - 0.5) * contrast + 0.5;

	float levels = float(clamp(posterize_levels, 2.0, 16.0));
	vec3 color = posterize(base, levels);

	// Greenish fog blend
	float brightness = dot(color, vec3(0.299, 0.587, 0.114));
	color = tint_color * brightness;
	COLOR = vec4(color, 1.0);
}

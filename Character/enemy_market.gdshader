shader_type canvas_item;
uniform sampler2D SCREEN_TEXTURE: hint_screen_texture, filter_linear_mipmap;
uniform float thickness = 2.0;
uniform vec4 border_color : source_color = vec4(0.3, 0.3, 0.3, 0.8);

void fragment() {
	vec2 uv = UV;
	vec2 size = vec2(1.0); // ColorRect UVs go from 0 to 1

	// Distance from edge
	float min_dist = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));

	// Border check
	if (min_dist < thickness / max(1.0, SCREEN_PIXEL_SIZE.x * float(textureSize(SCREEN_TEXTURE, 0).x))) {
		COLOR = border_color;
	} else {
		discard;
	}
}

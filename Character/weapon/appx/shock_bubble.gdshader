shader_type spatial;
render_mode unshaded, blend_mix, cull_back, depth_draw_never, shadows_disabled;

// The air shock around a blast (shockwave.gd): a sphere that is clear in the
// middle and bends whatever is behind it at the rim, like the bonfire's heat
// haze. Drawn from the screen, so it reads against sand, sky and robots alike
// without needing a colour of its own that suits all three.
uniform sampler2D screen_texture : hint_screen_texture;
// How far the rim bends the view, in fractions of the screen.
uniform float strength = 0.035;
uniform vec4 tint : source_color = vec4(1.0, 0.95, 0.85, 1.0);
// 0 at the bang, 1 as it dies.
uniform float life : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, 2.0);
	float fade = 1.0 - life;
	// NORMAL is in view space, so its x and y point outward across the screen.
	vec2 bend = NORMAL.xy * strength * rim * fade;
	vec3 seen = texture(screen_texture, SCREEN_UV - bend).rgb;
	ALBEDO = mix(seen, tint.rgb, rim * 0.12 * fade);
	ALPHA = clamp(rim * 1.2, 0.0, 1.0) * fade;
}

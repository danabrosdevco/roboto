shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled;

// ─────────────────────────────────────────────
// EXIT BEACON
//
// The pulse on a level exit's posts and its volume. In the shader rather than
// in level_exit.gd because a marker that blinks should not cost the exit a
// per-frame tick — there are several in a level and they do nothing else until
// something walks into them.
//
// `volume` softens the faces you look through and keeps the edges lit, so the
// box reads as a gate you walk into rather than a solid block in the way.
// ─────────────────────────────────────────────

uniform vec3 tint : source_color = vec3(1.0, 0.68, 0.18);
uniform float pulse_hz : hint_range(0.0, 4.0) = 0.8;
uniform float low : hint_range(0.0, 1.0) = 0.35;
uniform float energy : hint_range(0.0, 4.0) = 1.6;
uniform float alpha : hint_range(0.0, 1.0) = 1.0;
// 1.0 for the walk-through volume: transparent face on, bright at a glance.
uniform float volume : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float wave = mix(low, 1.0, 0.5 + 0.5 * sin(TIME * pulse_hz * TAU));
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	// Edge-on stays solid, face-on goes see-through — only for the volume.
	float see_through = mix(1.0, 1.0 - facing * 0.8, volume);
	ALBEDO = tint;
	EMISSION = tint * energy * wave;
	ALPHA = clamp(alpha * wave * see_through, 0.0, 1.0);
}

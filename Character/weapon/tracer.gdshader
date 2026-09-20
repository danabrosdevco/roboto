shader_type spatial;
render_mode blend_mix, unshaded, cull_disabled, depth_draw_never;

// ─────────────────────────────────────────────
// TRACER
//
// The round drawn as a bolt rather than a white stick: a hot near-white head,
// the body in the round's own colour, and a tail that thins out behind, so a
// burst reads as direction and speed instead of a row of identical dashes.
//
// MIXED, NOT ADDED. The old material was blend_add over an unassigned texture,
// which is where the flat white came from — and additive light on the valley's
// pale sand is no light at all. There is no glow in the world environment to
// carry it either, so the bolt has to paint its own colour to read against
// both the sand and the sky.
//
// Driven by object space, not UV: the mesh is a unit BoxMesh scaled on Z, and
// each face carries its own UV island, so anything UV-driven breaks the moment
// tracer.gd stretches it. Forward is -Z, the way look_at leaves it. Nothing
// here may fade on the cross-section either: a box has no geometry down its
// own axis, so a radial falloff zeroes out exactly where its faces are, and
// the whole bolt disappears.
// ─────────────────────────────────────────────

uniform vec3 head_color : source_color = vec3(1.0, 0.97, 0.90);
uniform vec3 body_color : source_color = vec3(1.0, 0.62, 0.16);
uniform vec3 tail_color : source_color = vec3(0.80, 0.16, 0.05);
// How much of the length burns white, and where the body gives way to tail.
uniform float head_length : hint_range(0.0, 1.0) = 0.22;
uniform float tail_start : hint_range(0.0, 1.0) = 0.65;
// Extra light on the head, for the frames it crosses something dark.
uniform float energy : hint_range(0.0, 3.0) = 0.6;
uniform float opacity : hint_range(0.0, 1.0) = 0.95;
// Faces turned away from the eye carry less of it, which rounds the box off.
uniform float edge_softness : hint_range(0.0, 1.0) = 0.45;

varying vec3 local_pos;

void vertex() {
	local_pos = VERTEX;
}

void fragment() {
	// 0 at the tail, 1 at the head.
	float along = clamp(0.5 - local_pos.z, 0.0, 1.0);
	vec3 tint = mix(tail_color, body_color, smoothstep(0.0, tail_start, along));
	float head = smoothstep(1.0 - head_length, 1.0, along);
	tint = mix(tint, head_color, head);

	float taper = smoothstep(0.0, 0.35, along);
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float soft = mix(1.0 - edge_softness, 1.0, facing);

	ALBEDO = tint;
	EMISSION = tint * energy * head;
	ALPHA = clamp(taper * soft * opacity, 0.0, 1.0);
}

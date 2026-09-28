shader_type spatial;
render_mode blend_add, unshaded, cull_disabled, depth_draw_never, shadows_disabled;

// ─────────────────────────────────────────────
// CHASSIS HOLOGRAM
//
// The projection standing in a depot bay: scan lines climbing the frame, a lit
// silhouette, and the sweep that builds it back up when the bay is switched to
// another chassis.
//
// All of it is here rather than in chassis_hologram.gd because a bay is a
// display: it does nothing until somebody presses F on it, and four of them
// idling in the hall should not cost four per-frame ticks between them. The
// one thing the script drives is `reveal`, tweened 0 -> 1 on a switch.
//
// Height is measured in WORLD space from `base_y`, not per-mesh, so the scan
// line and the build sweep cross a rover's hull, wheels and turret as one
// plane rather than restarting on every piece.
// ─────────────────────────────────────────────

uniform vec3 tint : source_color = vec3(0.35, 0.82, 1.0);
uniform float energy : hint_range(0.0, 6.0) = 0.9;
/// World Y of the pad, and how far above it the frame reaches.
uniform float base_y = 0.0;
uniform float span : hint_range(0.5, 12.0) = 2.4;
/// How much of the frame has been projected, from the pad up.
uniform float reveal : hint_range(0.0, 1.0) = 1.0;
/// Scan lines per metre, and how fast they climb.
uniform float lines : hint_range(0.0, 40.0) = 7.0;
uniform float climb : hint_range(-4.0, 4.0) = 0.45;
uniform float flicker : hint_range(0.0, 1.0) = 0.12;
uniform float fade : hint_range(0.0, 1.0) = 1.0;

varying float world_y;

void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}

void fragment() {
	float up = (world_y - base_y) / max(span, 0.01);
	// Below the sweep the frame is solid; the sweep itself is a bright band.
	float front = reveal - up;
	float built = smoothstep(-0.015, 0.07, front);
	float band = exp(-abs(front) * 22.0) * step(0.001, 1.0 - reveal);
	float scan = 0.5 + 0.5 * sin((world_y * lines - TIME * climb) * TAU);
	// Edge-on is where a projection reads as a shape, so that is where it is
	// brightest — the same trick the exit beacon uses on its volume.
	float rim = pow(1.0 - abs(dot(normalize(NORMAL), normalize(VIEW))), 2.2);
	float wobble = 1.0 - flicker * (0.5 + 0.5 * sin(TIME * 31.0));

	ALBEDO = tint;
	EMISSION = tint * energy * (0.26 + 0.42 * scan + 0.80 * rim + 2.2 * band) * wobble;
	ALPHA = clamp((0.14 + 0.34 * scan + 0.48 * rim + band) * built * fade * wobble, 0.0, 1.0);
}

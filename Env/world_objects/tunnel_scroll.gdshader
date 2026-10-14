shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;

// ─────────────────────────────────────────────
// TUNNEL SCROLL — what passes the windows when the train moves.
//
// The train does not move. Moving it would mean moving the player, the squad
// and the physics with it, so instead a bar of light slides along the tunnel
// wall, 20 m out, and the eight window apertures a side turn that into motion.
// TERRAIN built the windows on a regular 4 m pitch for exactly this and says so
// in tools/block_railhead.gd. See docs/briefs/DEPARTURE_RIDE.md.
//
// BLEND_ADD, so a plate at rest adds literally nothing: `rate` gates the output
// and at 0 the shader contributes black to an additive blend, which is
// invisible without having to toggle the mesh. DEPTH_DRAW_NEVER, not
// no_depth_test — the car's own wall must still occlude this, or the streaks
// appear straight through the hull and the whole thing reads as a screen
// effect rather than something outside.
//
// Coordinates come from VERTEX, not UV. A QuadMesh's UV orientation depends on
// how the mesh was rotated to face inward, and getting it wrong scrolls the
// bars vertically; local vertex position cannot be wrong that way.
// ─────────────────────────────────────────────

// Metres of track gone past. One tween drives this, and with a fixed bar pitch
// it is the entire motion.
uniform float scroll = 0.0;
// 0 at a standstill, 1 at line speed. Gates brightness AND streak length.
uniform float rate = 0.0;
// Metres between tunnel lamp bars. TERRAIN's ribs are every 8 m, so the lights
// land between them rather than on them.
uniform float pitch = 8.0;
// A bar's width at a standstill, in metres, before streaking widens it.
uniform float bar_width = 0.9;
uniform vec4 tint : source_color = vec4(0.95, 0.80, 0.55, 1.0);
uniform float gain = 1.7;
// Half the plate's height, so the vertical falloff is independent of how big
// the plate was made.
uniform float half_height = 2.5;
// Where the falloff starts, as a fraction of half_height.
uniform float edge = 0.55;

varying vec3 lpos;

void vertex() {
	lpos = VERTEX;
}

void fragment() {
	// THE BAR WIDENS WITH RATE, which is what a pan does to a light: motion
	// blur. A bar of constant width only slides, and reads as a texture being
	// scrolled rather than as something going past at speed.
	float w = max(0.01, bar_width * (1.0 + rate * 3.5));
	float u = (lpos.x + scroll) / pitch;
	// Metres to the nearest bar centre.
	float d = abs(fract(u) - 0.5) * pitch;
	float bar = 1.0 - smoothstep(0.0, w * 0.5, d);
	// Soft top and bottom, so the lit band does not end in a hard line drawn
	// across a window aperture.
	float v = abs(lpos.y) / max(0.0001, half_height);
	float h = 1.0 - smoothstep(edge, 1.0, v);
	ALBEDO = tint.rgb * bar * h * rate * gain;
}

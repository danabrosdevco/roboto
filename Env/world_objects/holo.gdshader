shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// ─────────────────────────────────────────────
// HOLO — the material every piece of the operations table's projection wears.
//
// The board is not one mesh. It is a base plate, a node per site, a line per
// connection and a label or two, each its own MeshInstance3D. Left to
// themselves that reads as a pile of separate glowing objects sitting near
// each other, not as ONE projection.
//
// WHAT MAKES THEM ONE THING IS THE SCANLINES, and specifically that they are
// banded on WORLD HEIGHT rather than on each mesh's own UV. A band crossing
// the projection at a given height crosses every element at that height, so
// the whole thing is plainly being drawn by a single emitter underneath it.
// Band on UV instead and each node carries its own little set of stripes,
// which is the look of a dozen holograms rather than one.
//
// ADDITIVE, because it is projected light. It brightens what is behind it and
// has no substance of its own. The ops car is an interior, so unlike the
// transmit ring over daylight this does not need overdriving to be seen.
//
// Tinted per instance, so a node can carry its owner's faction colour out of
// HUDPalette while sharing this material's behaviour.
// ─────────────────────────────────────────────

uniform vec4 tint : source_color = vec4(0.40, 0.78, 0.95, 1.0);
/// Overall strength. One knob, the way transmit_ring has one.
uniform float intensity : hint_range(0.0, 3.0) = 1.0;

group_uniforms Scanlines;
/// Bands per metre of world height.
uniform float band_density = 14.0;
/// Metres per second the bands crawl upward. Slow: this is a readout holding
/// still, not a special effect.
uniform float band_speed = 0.12;
uniform float band_depth : hint_range(0.0, 1.0) = 0.35;

group_uniforms Body;
/// How much the grazing edge brightens. A hologram is thin, so its silhouette
/// is where most of the light ends up.
uniform float rim_power = 1.8;
uniform float rim_boost = 1.4;   // kept for callers that want it; see fragment
/// Floor under the fresnel so a face viewed head-on does not vanish — the same
/// correction the jammer shell needed, for the same reason.
uniform float face_floor : hint_range(0.0, 1.0) = 0.45;

group_uniforms Instability;
/// A slow brightness wander. Not a strobe: the projector is old, not broken.
uniform float flicker_amount : hint_range(0.0, 1.0) = 0.10;
uniform float flicker_speed = 7.0;
/// Horizontal tearing, in metres, applied in bands. 0 switches it off.
uniform float tear_amount = 0.0;

/// 0 hides the element, 1 draws it fully. Driven per node so a site can come
/// up as the board resolves rather than all of it appearing at once.
uniform float present : hint_range(0.0, 1.0) = 1.0;

varying vec3 world_pos;

float hash11(float p) {
	return fract(sin(p * 127.1) * 43758.5453);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	// Tearing displaces whole horizontal slices, which is what a bad projector
	// does. Done in the VERTEX stage so the geometry actually moves rather
	// than the texture sliding across a shape that stays put.
	if (tear_amount > 0.0) {
		float slice = floor(world_pos.y * 40.0);
		float on = step(0.97, hash11(slice + floor(TIME * 9.0)));
		VERTEX.x += on * tear_amount * (hash11(slice) - 0.5);
	}
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = mix(face_floor, 1.0, pow(1.0 - facing, rim_power));

	// THE SHARED BAND. world_pos.y, not UV — see the note at the top.
	float bands = sin((world_pos.y - TIME * band_speed) * band_density * 6.2831853);
	bands = 1.0 - band_depth * (0.5 - bands * 0.5);

	// Two sine rates that do not divide into each other, so the wander never
	// settles into a pulse you can count.
	float flick = 1.0 - flicker_amount * 0.5
		* (1.0 - sin(TIME * flicker_speed) * sin(TIME * flicker_speed * 0.37));

	// THE RIM GOES IN THE ALPHA, NOT THE COLOUR. Multiplying ALBEDO by the
	// fresnel pushed every tint toward white — additive, over a dark interior,
	// a tint at 2x clips — and the board lost the one thing its colours carry,
	// which is who holds the site. Home Command green, Swarm amber and the
	// unknown grey all came out the same pale cream. Brightness now varies
	// with the angle; hue does not.
	ALBEDO = tint.rgb;
	ALPHA = clamp(rim * bands * flick * intensity, 0.0, 1.0) * present;
}

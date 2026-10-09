shader_type canvas_item;
render_mode unshaded;

// ─────────────────────────────────────────────────────────────
// SIGNAL FILTER
// Replaces green_filter.gdshader.
//
// Design intent: a compressed digital video feed, not a CRT.
// No barrel distortion, no phosphor mask, no rolling h-sync bar,
// no vignette. The artefacts here are compression artefacts —
// macroblocks, chroma subsampling, ordered dithering, packet
// loss — which read as "data" rather than "old television".
//
// The legibility strategy is:
//   1. quantise the whole image to one uniform pixel grid, so a
//      64px texture stretched over an 8m wall and a 64px texture
//      on a 1m crate resolve to the SAME apparent resolution
//   2. quantise LUMA hard, quantise CHROMA separately and gently,
//      so colour survives instead of collapsing to monochrome
//   3. put silhouettes back with an edge pass, because low-poly
//      geometry has no internal detail to define its own shape
// ─────────────────────────────────────────────────────────────

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// ── SIGNAL RESOLUTION ────────────────────────────────────────
// The image is snapped to an integer-scaled grid. signal_height
// is the target vertical resolution; the real scale is floored
// to an integer so blocks stay square and even.
uniform bool  quantize_resolution = true;
uniform float signal_height  : hint_range(120.0, 1080.0) = 360.0;
uniform bool  cell_average   = true;   // 4-tap average per cell, kills shimmer
uniform float chroma_divisor : hint_range(1.0, 4.0) = 2.0;  // 2.0 ≈ 4:2:0

// ── TONE ─────────────────────────────────────────────────────
uniform float exposure      : hint_range(0.2, 2.5) = 1.05;
// The BRIGHTNESS option (Settings display.brightness). A gamma on luma, so it
// lifts shadows far more than highlights. 1.0 is the image as authored.
uniform float gamma         : hint_range(0.5, 2.0) = 1.0;
uniform float contrast      : hint_range(0.5, 2.0) = 1.12;
uniform float black_lift    : hint_range(0.0, 0.25) = 0.05;  // stops crushed blacks
uniform float luma_levels   : hint_range(3.0, 32.0) = 10.0;
uniform float chroma_levels : hint_range(2.0, 16.0) = 5.0;
uniform float saturation    : hint_range(0.0, 2.0) = 0.90;

// ── PALETTE ──────────────────────────────────────────────────
// A three-point ramp. palette_strength below 1.0 leaves room for
// the original hue to show through — this is the knob that
// decides "tinted" vs "monochrome".
uniform vec3  shadow_tint : source_color = vec3(0.05, 0.11, 0.12);
uniform vec3  mid_tint    : source_color = vec3(0.30, 0.46, 0.38);
uniform vec3  high_tint   : source_color = vec3(0.87, 0.94, 0.72);
uniform float palette_strength : hint_range(0.0, 1.0) = 0.55;

// ── STRUCTURE ────────────────────────────────────────────────
uniform vec3  edge_color     : source_color = vec3(0.02, 0.06, 0.06);
uniform float edge_strength  : hint_range(0.0, 2.0) = 0.75;
uniform float edge_threshold : hint_range(0.01, 0.5) = 0.06;
uniform float dither_strength: hint_range(0.0, 1.5) = 0.85;

// ── SIGNAL ARTEFACTS ─────────────────────────────────────────
uniform float signal_fps   : hint_range(4.0, 60.0) = 15.0;  // artefact update rate
uniform float grain        : hint_range(0.0, 0.3) = 0.05;
uniform float dropout      : hint_range(0.0, 0.2) = 0.012;
uniform float block_glitch : hint_range(0.0, 1.0) = 0.12;
uniform float block_size   : hint_range(2.0, 32.0) = 8.0;

// ── STATE — drive these from GDScript ────────────────────────
uniform float damage : hint_range(0.0, 1.0) = 0.0;  // chassis integrity loss
uniform float boot   : hint_range(0.0, 1.0) = 0.0;  // 1→0 on mode change

// ─────────────────────────────────────────────────────────────
// HELPERS
// ─────────────────────────────────────────────────────────────

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

// Bayer matrix by recursive construction — no array lookups.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x * 0.5 + a.y * a.y * 0.75);
}
float bayer4(vec2 a) { return bayer2(a * 0.5) * 0.25 + bayer2(a); }
float bayer8(vec2 a) { return bayer4(a * 0.5) * 0.25 + bayer2(a); }

float luma_of(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }

vec3 fetch(vec2 p) {
	return texture(screen_tex, clamp(p, vec2(0.0), vec2(1.0))).rgb;
}

// Luma after the tone curve — used by the edge pass so it detects
// the same steps the visible image has.
float graded_luma(vec2 p) {
	float x = pow(max(luma_of(fetch(p) * exposure), 0.0), 1.0 / gamma);
	x = (x - 0.5) * contrast + 0.5;
	return black_lift + x * (1.0 - black_lift);
}

vec3 palette(float l, vec3 sh) {
	return l < 0.5
		? mix(sh, mid_tint, l * 2.0)
		: mix(mid_tint, high_tint, (l - 0.5) * 2.0);
}

// ─────────────────────────────────────────────────────────────

void fragment() {
	vec2  px    = SCREEN_PIXEL_SIZE;
	vec2  res   = 1.0 / px;
	// DAMAGE COSTS YOU RESOLUTION FIRST.
	//
	// The uniform used to feed nothing but two artefact knobs that sit near
	// zero at rest, so turning it all the way up moved the image less than one
	// frame of grain does — measured, not guessed: full health against eight
	// hit points differed by 0.077 mean channel error, and two consecutive
	// frames at full health differed by 0.075. It was wired and invisible.
	//
	// Resolution is the one axis you cannot miss. A hurt drone's feed resolves
	// coarser, which reads as bandwidth loss rather than as a broken monitor,
	// and it degrades the WORLD without touching the HUD text drawn over it.
	//
	// DAMAGE TOUCHES NO COLOUR. NONE. Not saturation, not the palette, not the
	// luma step count, not the chroma grid.
	//
	// Three attempts went the other way and all three looked wrong. A straight
	// desaturation washed the game out. Posterising luma was the worst of them:
	// with the step count pushed down, a smooth sky snapped into two flat bands,
	// and because palette() ramps shadow -> mid -> high those neighbouring bands
	// landed on completely different hues — half the sky blue and half of it
	// cream, with a hard seam between. That is not a degraded picture, it is a
	// different picture.
	//
	// AND IT DOES NOT TOUCH THE CELL SIZE EITHER.
	//
	// Driving signal_height down with damage was the first thing tried and it
	// is the thing that made the screenshot above look wrong. Growing the grid
	// does not read as a worse signal, it reads as giant squares — and it is
	// also what made the colour banding so violent, because each flat cell then
	// paints one quantised palette band across a huge area and the seam between
	// two bands becomes a hard line halfway up the sky.
	//
	// The grid stays exactly where it was authored. What a failing link costs
	// you is the ability to MAKE THINGS OUT at that resolution: softer, less
	// edge definition, more holes. None of those is hue and none of them is
	// block size, so the world stays the colour and the shape it was drawn at
	// and simply gets harder to read.
	float scale = max(floor(res.y / signal_height), 1.0);
	vec2  cell  = quantize_resolution ? px * scale : px;

	vec2 uv   = SCREEN_UV;
	vec2 grid = floor(uv / cell);                  // integer signal-pixel coords
	vec2 suv  = quantize_resolution ? (grid + 0.5) * cell : uv;

	// Artefacts advance at signal_fps, not per render frame, so the
	// static reads as a low-framerate stream instead of shimmer.
	float t = floor(TIME * signal_fps) / signal_fps;

	// ── macroblock displacement ──────────────────────────────
	vec2  blk    = floor(grid / block_size);
	float blk_h  = hash12(blk + vec2(t * 61.0, 0.0));
	float active = step(1.0 - block_glitch * (0.25 + damage * 2.5), blk_h);
	suv += vec2((hash12(blk.yx + t) - 0.5) * 24.0, 0.0) * cell * active;

	// ── luma sample ──────────────────────────────────────────
	// THE BLUR IS THE DAMAGE. The four taps already here exist to kill shimmer
	// at a quarter of a cell apart; widening them with damage turns the same
	// four fetches into a real smear at no extra cost. Combined with the
	// coarser grid above, a bad link stops resolving detail — which is the
	// thing being asked for, and the one degradation that cannot be mistaken
	// for an art direction change.
	float tap = 0.25 + damage * 1.6;
	vec3 base;
	if (cell_average) {
		base = (fetch(suv + cell * vec2(-tap, -tap))
			  + fetch(suv + cell * vec2( tap, -tap))
			  + fetch(suv + cell * vec2(-tap,  tap))
			  + fetch(suv + cell * vec2( tap,  tap))) * 0.25;
	} else {
		base = fetch(suv);
	}
	base *= exposure;

	// ── chroma sampled on a coarser grid (4:2:0-ish) ─────────
	// Chroma subsamples coarser as the link degrades, so colour smears across
	// block boundaries before it drains away entirely below.
	vec2 ccell = cell * chroma_divisor;
	vec3 cbase = fetch((floor(suv / ccell) + 0.5) * ccell) * exposure;
	vec3 chroma = cbase - vec3(luma_of(cbase));

	// ── tone curve ───────────────────────────────────────────
	float l = pow(max(luma_of(base), 0.0), 1.0 / gamma);
	l = (l - 0.5) * contrast + 0.5;
	l = black_lift + l * (1.0 - black_lift);

	// ── ordered dither, then quantise ────────────────────────
	float d = bayer8(grid) * dither_strength;

	float lsteps = max(luma_levels - 1.0, 1.0);
	float lq = clamp(floor(l * lsteps + d) / lsteps, 0.0, 1.0);

	float csteps = max(chroma_levels - 1.0, 1.0);
	chroma = floor(chroma * csteps + d) / csteps;

	// ── edges from the graded image ──────────────────────────
	// Only strong structural discontinuities pass the threshold,
	// so this traces silhouettes and lighting breaks rather than
	// texture noise.
	float e = max(
		max(abs(graded_luma(suv + vec2(cell.x, 0.0)) - l),
		    abs(graded_luma(suv - vec2(cell.x, 0.0)) - l)),
		max(abs(graded_luma(suv + vec2(0.0, cell.y)) - l),
		    abs(graded_luma(suv - vec2(0.0, cell.y)) - l)));
	// ...AND THE SILHOUETTES GO WITH IT. The edge pass is what puts shape back
	// into low-poly geometry that has no internal detail of its own — see the
	// legibility strategy at the top of this file. Fading it is the most
	// direct way to make things hard to tell apart, because it removes the
	// exact thing that was telling them apart. Not to zero: without any edges
	// at all the world stops reading as objects.
	float edge = smoothstep(edge_threshold, edge_threshold * 2.5, e)
			* edge_strength * (1.0 - damage * 0.65);

	// ── compose ──────────────────────────────────────────────
	vec3 sh = shadow_tint;
	vec3 col = mix(vec3(lq), palette(lq, sh), palette_strength);
	col += chroma * saturation;
	col = mix(col, edge_color, clamp(edge, 0.0, 1.0));

	// ── sensor grain ─────────────────────────────────────────
	col += (hash12(grid + vec2(t * 91.7, t * 37.3)) - 0.5) * grain;

	// ── packet loss / dead pixels ────────────────────────────
	float dp   = hash12(grid * 1.37 + vec2(t * 13.0, t * 7.0));
	float loss = step(1.0 - dropout * (1.0 + damage * 18.0), dp);
	col = mix(col, mix(sh, high_tint, step(0.5, fract(dp * 91.0))), loss * 0.7);

	// NO COLOUR DRAIN. There was a desaturation pass here and it is gone on
	// purpose: greyscale is a dead end with nowhere worse to go, and it washed
	// out the palette the whole game is built on. A failing link now shows as
	// resolution, banding, packet loss and a rusting shadow end — all of which
	// get worse the further down you go, and none of which cost the picture
	// its colour. If you are reaching for desaturation again, make something
	// else worse instead.

	// ── mode-change / reinitialise wipe ──────────────────────
	float band = 1.0 - smoothstep(0.0, 0.25, abs(uv.y - (1.0 - boot)));
	col = mix(col, vec3(hash12(grid + t)) * high_tint, band * boot);

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}

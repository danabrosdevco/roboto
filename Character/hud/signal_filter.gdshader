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

vec3 palette(float l) {
	return l < 0.5
		? mix(shadow_tint, mid_tint, l * 2.0)
		: mix(mid_tint, high_tint, (l - 0.5) * 2.0);
}

// ─────────────────────────────────────────────────────────────

void fragment() {
	vec2  px    = SCREEN_PIXEL_SIZE;
	vec2  res   = 1.0 / px;
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
	float active = step(1.0 - block_glitch * (0.25 + damage), blk_h);
	suv += vec2((hash12(blk.yx + t) - 0.5) * 24.0, 0.0) * cell * active;

	// ── luma sample ──────────────────────────────────────────
	vec3 base;
	if (cell_average) {
		base = (fetch(suv + cell * vec2(-0.25, -0.25))
			  + fetch(suv + cell * vec2( 0.25, -0.25))
			  + fetch(suv + cell * vec2(-0.25,  0.25))
			  + fetch(suv + cell * vec2( 0.25,  0.25))) * 0.25;
	} else {
		base = fetch(suv);
	}
	base *= exposure;

	// ── chroma sampled on a coarser grid (4:2:0-ish) ─────────
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
	float edge = smoothstep(edge_threshold, edge_threshold * 2.5, e) * edge_strength;

	// ── compose ──────────────────────────────────────────────
	vec3 col = mix(vec3(lq), palette(lq), palette_strength);
	col += chroma * saturation;
	col = mix(col, edge_color, clamp(edge, 0.0, 1.0));

	// ── sensor grain ─────────────────────────────────────────
	col += (hash12(grid + vec2(t * 91.7, t * 37.3)) - 0.5) * grain;

	// ── packet loss / dead pixels ────────────────────────────
	float dp   = hash12(grid * 1.37 + vec2(t * 13.0, t * 7.0));
	float loss = step(1.0 - dropout * (1.0 + damage * 4.0), dp);
	col = mix(col, mix(shadow_tint, high_tint, step(0.5, fract(dp * 91.0))), loss * 0.7);
	// ── mode-change / reinitialise wipe ──────────────────────
	float band = 1.0 - smoothstep(0.0, 0.25, abs(uv.y - (1.0 - boot)));
	col = mix(col, vec3(hash12(grid + t)) * high_tint, band * boot);

	COLOR = vec4(clamp(col, vec3(0.0), vec3(1.0)), 1.0);
}

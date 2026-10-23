shader_type canvas_item;

// ─────────────────────────────────────────────
// ENTERING THE SIM.
//
// A full-screen wipe for the one door in the game that does not lead anywhere
// physical. Every other transition is a vehicle — the train out of the depot,
// the drop. The arena is a simulation the player's own hardware runs, so going
// in should read as going INTO the machine rather than travelling to it.
//
// A HORIZON WITH A GRID RUSHING OUT OF IT, scan bands over the top, and a
// digital tear worst at the midpoint — which is where the screen behind is
// swapped. Driven by `progress` off a Tween; see cyberspace_wipe.gd for why a
// tween and not a coroutine.
//
// THE LINES ARE DRAWN FROM THEIR OWN DERIVATIVE. The first version tested the
// distance to a line against a fixed epsilon, which is wrong under perspective:
// near the horizon one screen pixel spans many grid cells, every test passes,
// and the grid fills in to a solid sheet. Photographed, it was a flat blue
// field with a bright line across the middle. fwidth() gives the width of one
// pixel in grid space, so a line stays one pixel wide wherever it is — and
// where cells are smaller than a pixel the line simply fades.
// ─────────────────────────────────────────────

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 tint : source_color = vec4(0.35, 0.95, 0.85, 1.0);
uniform float seed = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

/// One grid line per unit of x, one pixel wide whatever the scale.
float line_at(float x) {
	float f = fract(x);
	float d = min(f, 1.0 - f);
	return 1.0 - smoothstep(0.0, fwidth(x) * 1.1 + 0.0002, d);
}

void fragment() {
	vec2 uv = UV;

	// HOW MUCH OF THE SCREEN THIS OWNS. In fast so the press feels answered,
	// out slower so the arena is readable as it clears.
	float cover = smoothstep(0.0, 0.30, progress) * (1.0 - smoothstep(0.72, 1.0, progress));

	vec2 c = uv - vec2(0.5);
	float ay = abs(c.y);

	// PERSPECTIVE FROM A DIVIDE, not a matrix: 1/y is a plane seen from on it,
	// mirrored above and below so there is a floor and a ceiling.
	float z = 0.35 / max(ay, 0.001);
	float across = c.x * z * 2.0;
	float along = z * 0.5 - (TIME * 1.1 + progress * 5.0);

	float grid = max(line_at(across), line_at(along));
	// Off at the horizon, where the cells are finer than a pixel, and easing
	// off toward the top and bottom edges so the frame does not end in a fence.
	grid *= smoothstep(0.0, 0.06, ay) * (1.0 - smoothstep(0.34, 0.5, ay) * 0.65);

	float horizon = smoothstep(0.009, 0.0, ay);
	float band = step(0.5, fract(uv.y * 150.0 + TIME * 4.0));

	// THE TEAR, worst in the middle: rows of the image jump a frame. This is
	// what sells it as a machine rather than a light show.
	float churn = 1.0 - abs(progress - 0.5) * 2.0;
	float tear = step(0.992 - churn * 0.04,
		hash(vec2(floor(uv.y * 90.0), floor(TIME * 20.0 + seed))));

	float lines = clamp(grid + horizon * 1.8 + tear * 0.55, 0.0, 1.0);
	// BLACK WHERE THERE ARE NO LINES, and nearly opaque regardless, so the
	// screen behind really does go away rather than showing through a wash.
	vec3 col = tint.rgb * lines + tint.rgb * (band * 0.05);
	COLOR = vec4(col, cover * max(lines, 0.90));
}

// ICON EDGES — turns the icon pass into line art. A pixel is a line where,
// across `radius` pixels either side of it:
//   the model starts or stops            (the outline),
//   the surface turns a corner           (creases: the pump, the magazine),
//   one part passes in front of another  (a jump in depth).
// Written straight through, not blended, so partly covered pixels keep a white
// colour instead of fading to grey against the empty background.
shader_type canvas_item;
render_mode blend_disabled;

uniform float radius = 2.5;
uniform float normal_threshold = 0.22;
uniform float depth_threshold = 0.07;
// A faint fill inside the outline; 0 for lines only.
uniform float fill = 0.0;

void fragment() {
	vec2 o = TEXTURE_PIXEL_SIZE * radius;
	vec4 c = texture(TEXTURE, UV);
	vec4 l = texture(TEXTURE, UV + vec2(-o.x, 0.0));
	vec4 r = texture(TEXTURE, UV + vec2(o.x, 0.0));
	vec4 u = texture(TEXTURE, UV + vec2(0.0, -o.y));
	vec4 d = texture(TEXTURE, UV + vec2(0.0, o.y));

	float outline = step(0.5, max(abs(l.a - r.a), abs(u.a - d.a)));
	// Creases and depth steps only count where both samples are on the model;
	// the outline already covers where one of them is not.
	float inside = step(0.5, min(min(l.a, r.a), min(u.a, d.a)));
	float crease = step(normal_threshold, max(length(l.rg - r.rg), length(u.rg - d.rg)));
	float stepped = step(depth_threshold, max(abs(l.b - r.b), abs(u.b - d.b)));
	float line = max(outline, inside * max(crease, stepped));

	COLOR = vec4(1.0, 1.0, 1.0, max(line, fill * step(0.5, c.a)));
}

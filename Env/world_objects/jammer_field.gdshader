shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// THE EDGE OF A DEAD ZONE, drawn so you can refuse to walk into it.
//
// A jammer that only showed up on the HUD would be a trap, not a decision:
// you would learn where they are by losing your squad, once per zone, forever.
// The whole value of the mechanic is that the boundary is a thing in the world
// you can stand next to and think about. So the volume is a cylinder you can
// see from across the valley, and what it does to the picture is the same
// thing it does to your sensors.
//
// MIXED, NOT ADDED. Additive is right for the transmit wavefront, which is
// emitted energy; it is wrong here, because half of what a 16 m column stands
// against is open sky and adding magenta to pale blue only ever gives white.
// The one thing the colour has to carry is WHOSE jammer this is, and the
// first cut threw that away everywhere above the horizon.
//
// THE WALL IS BRIGHT AND THE MIDDLE IS CLEAR. Fresnel, so the shell is almost
// invisible looked at face-on and intense at a glancing angle — which means
// from outside it reads as a column, and from inside it reads as a horizon
// you are enclosed by, without ever blocking what you need to shoot at.
uniform vec4 tint : source_color = vec4(0.69, 0.20, 0.47, 1.0);
// Scan bands running up the shell. Not decoration: the direction is what
// separates "a jammer" from "a smoke cloud" at a glance.
uniform float band_density = 26.0;
uniform float band_speed = 0.55;
// How hard the rim lights up. Higher = thinner, sharper wall.
uniform float rim_power = 3.0;
// Interference, strongest at the boundary where the field is thickest.
uniform float noise_amount = 0.35;

// Cheap value hash. No texture to load, and nothing for the NVIDIA particle
// path to object to — see signal_arc.gd for why that matters here.
float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	float facing = abs(dot(normalize(NORMAL), normalize(VIEW)));
	float rim = pow(1.0 - facing, rim_power);
	// A FLOOR UNDER THE FRESNEL. Pure rim lighting makes the wall disappear
	// when you look straight at it -- which is exactly the view you have from
	// the middle of the zone, so standing inside one looked like standing in
	// an ordinary field with a broken HUD. The base keeps the wall present
	// face-on without filling in the column when seen from outside. 0.16 was
	// still too little -- from the middle of the zone the wall came out as a
	// faint stain on the horizon and the player had no idea they were in one.
	float wall = mix(0.34, 1.0, rim);

	// UV.y runs up the cylinder. Bands climb it.
	float bands = sin((UV.y - TIME * band_speed) * band_density * 6.2831853);
	bands = smoothstep(0.1, 1.0, bands * 0.5 + 0.5);

	// Chunky noise that holds still for a few frames rather than boiling —
	// jamming should read as interference, not as television static.
	float n = hash(floor(vec2(UV.x * 90.0, UV.y * 40.0 - TIME * 6.0)));

	// Kept well under 1 and the albedo kept near the tint: the first cut
	// multiplied both up and the additive blend took the whole column to
	// white, which threw away the one thing the colour was carrying — whose
	// jammer it is.
	ALBEDO = tint.rgb * (0.85 + bands * 0.6);
	ALPHA = clamp(wall * (0.30 + bands * 0.40 + n * noise_amount), 0.0, 0.85);
}

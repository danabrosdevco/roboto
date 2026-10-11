shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, shadows_disabled;

// DEPTH TEST OFF, unlike shock_ring. A blast ring is dust lying on the floor
// and should be occluded by the floor. This is not on the floor — it is a
// readout of something passing through the air, and the ground is only there
// to give it a shape you can judge distance against. With the test on, a flat
// quad 45 m across sinks into every undulation in the terrain and arrives as
// three disconnected arcs; most of the ring was simply buried.
//
// The cost is that it also draws over robots standing in it. That reads as
// correct here — the wave goes through them too.

// THE WAVEFRONT OF A TRANSMISSION, running out along the ground from whoever
// keyed the radio. Drawn on a flat 2x2 plane scaled to the current reach, so
// the front is always at the mesh's rim and `scale` alone drives it outward —
// the same trick shock_ring uses, and for the same reason: one tween on a
// transform, nothing per frame.
//
// A SHADER OF ITS OWN RATHER THAN A PARAMETER ON shock_ring, because the blend
// mode is the whole difference. A shockwave is dust, which is matter, so it
// mixes. A transmission is emitted energy: it brightens what it crosses and
// vanishes over anything already bright. Additive is not a look here, it is
// the physics of the thing.
uniform vec4 wave : source_color = vec4(0.40, 0.78, 0.95, 1.0);
// 0 as it leaves the antenna, 1 as it dies.
uniform float life : hint_range(0.0, 1.0) = 0.0;
// Trailing bands behind the front, so it reads as a carrier with cycles in it
// rather than as one expanding hoop.
uniform float rings = 5.0;
// ONE KNOB FOR HOW LOUD THE THING LOOKS. 1.0 is the first tuning, which was
// too much -- it took over the frame indoors, where the floor is close and
// the whole ring is in view at once. Turn it up for a brighter carrier, down
// for a hint. Scales the colour and the alpha together so the front stays
// the brightest part of the wave at every setting.
uniform float intensity : hint_range(0.0, 2.0) = 0.65;

// AIMED OR NOT. (0,0) is a circle — every verb except ADVANCE. Anything else
// is the bearing the order points down, in the plane's own XZ.
uniform vec2 heading = vec2(0.0, 0.0);
// Cosine of the lobe's HALF angle. 1 is a pencil, -1 is a full circle.
uniform float cone_cos = -1.0;
// HOW MUCH THE FRONT STOPS BEING A RING. 0 leaves it an arc of a circle
// centred on the transmitter; 1 makes it a straight front perpendicular to
// the heading, travelling away down it.
//
// This is the difference between "a ring with a slice taken out" and "a wave
// going that way", and only the second one reads as aimed. A narrow arc is
// still visibly part of a circle drawn around you — the curvature gives it
// away, and the eye reads the centre, not the slice.
uniform float flatten : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float r = length(p);
	// Hard cut just inside the rim: past this the plane is not the wave, it is
	// the corners of the quad. Always radial — it is the mesh's edge, not the
	// wave's.
	float outer = 1.0 - smoothstep(0.97, 1.0, r);

	float d = r;
	float lobe = 1.0;
	if (dot(heading, heading) > 0.0001 && r > 0.001) {
		vec2 h = normalize(heading);
		float align = dot(p / r, h);
		// Tight edges. A soft falloff spread the lobe well past its nominal
		// angle and made a 120 degree cone look like most of a circle.
		lobe = smoothstep(cone_cos - 0.06, cone_cos + 0.03, align);
		// Distance measured ALONG the bearing rather than from the centre, so
		// the front is a line crossing the ground rather than an arc bending
		// around the player.
		d = mix(r, dot(p, h), flatten);
	}

	// THE FRONT IS WIDE, and it has to be. Seen from standing height the far
	// side of a 45 m wave is foreshortened to almost nothing: the first cut of
	// this was a 12%-of-radius band and it came out as a few pixels nobody
	// could find.
	float front = smoothstep(0.78, 0.97, d) * outer;
	// The wake: bands falling away behind it. These are what make the ground
	// the transmission has already crossed legible.
	float bands = pow(sin(d * rings * 6.2831853) * 0.5 + 0.5, 4.0);
	float wake = bands * smoothstep(0.0, 0.35, d) * outer;
	// And a wash under the lot, so the area already covered is readable as an
	// area rather than as a set of hoops.
	float wash = smoothstep(0.0, 0.25, d) * outer;
	ALBEDO = wave.rgb * (1.0 + 1.6 * intensity);
	ALPHA = clamp((front * 1.3 + wake * 0.6 + wash * 0.14) * intensity, 0.0, 1.0)
		* (1.0 - life) * lobe;
}

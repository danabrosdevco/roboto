shader_type spatial;
render_mode unshaded, blend_mix, cull_disabled, depth_draw_never, shadows_disabled;

// The ring a blast drives out along the ground (shockwave.gd), on a flat
// 2x2 plane scaled to the ring's radius. A band of dust with a pale leading
// edge: the dust reads on the valley's bright sand, the edge on a dark floor.
uniform vec4 dust : source_color = vec4(0.36, 0.3, 0.23, 1.0);
uniform vec4 edge : source_color = vec4(1.0, 0.93, 0.8, 1.0);
// 0 at the bang, 1 as it dies. Fades it, and thins the band as it spreads.
uniform float life : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	float r = length(UV * 2.0 - 1.0);
	float width = mix(0.45, 0.12, life);
	// Up across the band to the front at r = 0.97, and off sharply past it.
	float outer = 1.0 - smoothstep(0.97, 1.0, r);
	float band = smoothstep(0.97 - width, 0.97, r) * outer;
	float front = smoothstep(0.97 - width * 0.25, 0.97, r) * outer;
	ALBEDO = mix(dust.rgb, edge.rgb, front);
	ALPHA = band * (1.0 - life) * 0.85;
}

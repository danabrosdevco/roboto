// ─────────────────────────────────────────────
// WATER — the surface GeneratedTerrain draws over painted water. Dark, murky,
// faintly oily: whatever used to live in it is long gone.
//
// Depth comes in as vertex data (COLOR.r: 0 at the waterline … 1 deep), baked
// from the terrain under each vertex, so shallows, shoreline scum and deep
// water need no depth-buffer read — costly in the Compatibility renderer.
// Ripples are the Set4All water tile scrolled against itself; the normal is
// bent from the tile's slope, so no tangents are needed either.
//
// Visual only: nothing here, or in the meshes it draws, affects navigation or
// collision.
// ─────────────────────────────────────────────
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D surface_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform float texture_scale : hint_range(1.0, 128.0) = 14.0;
uniform float texture_strength : hint_range(0.0, 1.0) = 0.35;
// Drift of the two ripple layers, in texture tiles per second.
uniform vec2 flow = vec2(0.012, 0.006);
uniform float ripple_strength : hint_range(0.0, 1.0) = 0.25;

uniform vec4 shallow_colour : source_color = vec4(0.22, 0.21, 0.15, 1.0);
uniform vec4 deep_colour : source_color = vec4(0.03, 0.045, 0.045, 1.0);
uniform vec4 shore_colour : source_color = vec4(0.38, 0.36, 0.3, 1.0);
// How far out the shoreline scum reaches, in depth units (0…1).
uniform float shore_width : hint_range(0.0, 1.0) = 0.08;
uniform float shallow_alpha : hint_range(0.0, 1.0) = 0.55;
uniform float deep_alpha : hint_range(0.0, 1.0) = 0.94;
// Rainbow slick at grazing angles. Oil, or something worse.
uniform float oil_sheen : hint_range(0.0, 1.0) = 0.15;
uniform float roughness : hint_range(0.0, 1.0) = 0.12;
uniform float specular : hint_range(0.0, 1.0) = 0.5;

varying vec3 v_world;
varying float v_depth;

void vertex() {
	v_world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_depth = COLOR.r;
}

void fragment() {
	vec2 uv = v_world.xz / texture_scale;
	vec2 uv_a = uv + flow * TIME;
	vec2 uv_b = uv * 0.61 - flow.yx * TIME * 1.3 + vec2(0.37, 0.11);
	float a = texture(surface_texture, uv_a).r;
	float b = texture(surface_texture, uv_b).r;
	float pattern = (a + b) * 0.5;

	// Ripples: tilt the normal by the tile's slope along x and z.
	float ax = texture(surface_texture, uv_a + vec2(0.01, 0.0)).r;
	float az = texture(surface_texture, uv_a + vec2(0.0, 0.01)).r;
	vec3 n_world = normalize(vec3((a - ax) * ripple_strength * 4.0, 1.0, (a - az) * ripple_strength * 4.0));
	NORMAL = normalize((VIEW_MATRIX * vec4(n_world, 0.0)).xyz);

	float depth = clamp(v_depth, 0.0, 1.0);
	vec3 col = mix(shallow_colour.rgb, deep_colour.rgb, smoothstep(0.0, 1.0, depth));
	col = mix(col, col * (0.7 + pattern * 0.9), texture_strength);
	float shore = 1.0 - smoothstep(0.0, max(shore_width, 0.001), depth);
	col = mix(col, shore_colour.rgb, shore * (0.35 + pattern * 0.5));

	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	vec3 sheen = 0.5 + 0.5 * cos(6.2831 * (pattern * 1.7 + fres * 2.0 + vec3(0.0, 0.33, 0.67)));
	col += sheen * 0.12 * oil_sheen * fres;

	ALBEDO = col;
	ALPHA = mix(shallow_alpha, deep_alpha, smoothstep(0.0, 0.6, depth));
	ROUGHNESS = roughness;
	SPECULAR = specular;
}

// ─────────────────────────────────────────────
// TERRAIN — the look of every GeneratedTerrain. Dark, ashen, post-collapse.
//
// Everything per-terrain arrives as VERTEX data, not textures, so this one
// material is shared by every map and edits to it show up live everywhere:
//   COLOR  r road / path gravel, g scorch, b pad (flattened building ground),
//          a hollow (gullies and dips — darker, damper, rubble-strewn)
//   UV2    x border-mountain factor, y height within the map, 0…1
// A per-terrain texture would need a per-terrain copy of this material, and
// then editing the shared one would silently change nothing.
//
// Compatibility renderer: eight samplers (well under its per-material limit),
// no instance uniforms, no screen or depth reads.
//
// Filtering is nearest-with-mipmaps to match the PSX materials the brush levels
// use. Swap the hints to filter_linear_mipmap_anisotropic for a smoother look.
// ─────────────────────────────────────────────
shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

group_uniforms ground;
uniform sampler2D ground_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 ground_tint : source_color = vec4(0.34, 0.3, 0.25, 1.0);
uniform float ground_scale : hint_range(0.5, 64.0) = 7.0;

group_uniforms growth;
// Dead scrub and grass: patchy, only on gentle ground, never on the mountains.
uniform sampler2D growth_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 growth_tint : source_color = vec4(0.45, 0.42, 0.28, 1.0);
uniform float growth_scale : hint_range(0.5, 64.0) = 5.0;
uniform float growth_amount : hint_range(0.0, 1.0) = 0.3;
uniform float growth_max_slope : hint_range(1.0, 60.0) = 24.0;

group_uniforms rock;
// Cliffs and steep ground, projected from three sides so it never stretches.
uniform sampler2D rock_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 rock_tint : source_color = vec4(0.52, 0.52, 0.55, 1.0);
uniform float rock_scale : hint_range(0.5, 64.0) = 10.0;
uniform float rock_slope_start : hint_range(0.0, 90.0) = 24.0;
uniform float rock_slope_full : hint_range(0.0, 90.0) = 36.0;
// Extra bare rock on the border mountains, whatever their slope.
uniform float mountain_rock : hint_range(0.0, 1.0) = 0.75;

group_uniforms rubble;
uniform sampler2D rubble_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 rubble_tint : source_color = vec4(0.4, 0.38, 0.36, 1.0);
uniform float rubble_scale : hint_range(0.5, 64.0) = 4.0;
uniform float rubble_in_hollows : hint_range(0.0, 3.0) = 1.2;

group_uniforms paint;
uniform sampler2D road_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 road_tint : source_color = vec4(0.5, 0.48, 0.45, 1.0);
uniform float road_scale : hint_range(0.5, 64.0) = 3.0;
uniform sampler2D pad_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 pad_tint : source_color = vec4(0.45, 0.44, 0.42, 1.0);
uniform float pad_scale : hint_range(0.5, 64.0) = 4.0;
uniform sampler2D scorch_texture : source_color, filter_nearest_mipmap_anisotropic, repeat_enable;
uniform vec4 scorch_tint : source_color = vec4(1.0, 0.92, 0.85, 1.0);
uniform float scorch_scale : hint_range(0.5, 64.0) = 5.0;

group_uniforms grade;
// Large-scale patchiness, sampled at two scales so the tiling never lines up.
uniform sampler2D variation_noise : filter_linear_mipmap, repeat_enable;
uniform float variation_scale : hint_range(10.0, 2000.0) = 170.0;
uniform float variation_strength : hint_range(0.0, 1.0) = 0.35;
uniform float hollow_darkening : hint_range(0.0, 1.0) = 0.45;
uniform float hollow_wetness : hint_range(0.0, 1.0) = 0.3;
// Pale ash settles on the highest ground.
uniform vec4 ash_tint : source_color = vec4(0.6, 0.59, 0.57, 1.0);
uniform float peak_ash : hint_range(0.0, 1.0) = 0.25;
uniform float saturation : hint_range(0.0, 1.5) = 0.6;
uniform float brightness : hint_range(0.0, 2.0) = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.95;
uniform float specular : hint_range(0.0, 1.0) = 0.15;
group_uniforms;

varying vec3 v_world_pos;
varying vec3 v_world_normal;
varying vec4 v_paint;
varying vec2 v_zone;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
	v_paint = COLOR;
	v_zone = UV2;
}

vec3 triplanar(sampler2D tex, vec3 p, vec3 n, float scale) {
	vec3 w = abs(n);
	w *= w;
	w *= w;
	w /= max(w.x + w.y + w.z, 0.0001);
	return texture(tex, p.zy / scale).rgb * w.x
			+ texture(tex, p.xz / scale).rgb * w.y
			+ texture(tex, p.xy / scale).rgb * w.z;
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 p = v_world_pos;
	float mountain = v_zone.x;
	float height01 = v_zone.y;

	float vary = texture(variation_noise, p.xz / variation_scale).r * 0.65
			+ texture(variation_noise, p.xz / (variation_scale * 0.23) + vec2(0.31, 0.67)).r * 0.35;

	vec3 ground = mix(texture(ground_texture, p.xz / ground_scale).rgb,
			texture(ground_texture, p.xz / (ground_scale * 3.1) + vec2(0.5)).rgb, 0.45) * ground_tint.rgb;
	vec3 growth = texture(growth_texture, p.xz / growth_scale).rgb * growth_tint.rgb;
	vec3 rubble = texture(rubble_texture, p.xz / rubble_scale).rgb * rubble_tint.rgb;
	vec3 rock = triplanar(rock_texture, p, n, rock_scale) * rock_tint.rgb;
	vec3 road = texture(road_texture, p.xz / road_scale).rgb * road_tint.rgb;
	vec3 pad = texture(pad_texture, p.xz / pad_scale).rgb * pad_tint.rgb;
	vec3 scorch = texture(scorch_texture, p.xz / scorch_scale).rgb * scorch_tint.rgb;

	// Rock by slope, with the variation noise roughing up the line.
	float rock_w = 1.0 - smoothstep(cos(radians(rock_slope_full)), cos(radians(rock_slope_start)),
			n.y + (vary - 0.5) * 0.12);
	rock_w = max(rock_w, mountain * mountain_rock * smoothstep(0.25, 0.75, vary + mountain * 0.35));

	float flat_enough = smoothstep(cos(radians(growth_max_slope)), cos(radians(growth_max_slope * 0.5)), n.y);
	float growth_w = smoothstep(1.0 - growth_amount - 0.08, 1.0 - growth_amount + 0.08, vary)
			* flat_enough * (1.0 - mountain) * (1.0 - v_paint.a * 0.7);
	float rubble_w = clamp(v_paint.a * rubble_in_hollows, 0.0, 1.0);

	vec3 col = ground;
	col = mix(col, growth, growth_w);
	col = mix(col, rubble, rubble_w);
	col = mix(col, rock, clamp(rock_w, 0.0, 1.0));
	col = mix(col, col * 0.5 + ash_tint.rgb * 0.5, peak_ash * smoothstep(0.55, 1.0, height01));
	// Paint goes on last: roads, pads and burns sit over whatever is beneath.
	col = mix(col, road, v_paint.r);
	col = mix(col, pad, v_paint.b);
	col = mix(col, scorch, v_paint.g);

	col *= 1.0 + (vary - 0.5) * variation_strength;
	col *= 1.0 - v_paint.a * hollow_darkening;
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(lum), col, saturation) * brightness;

	ALBEDO = col;
	ROUGHNESS = mix(roughness, roughness * 0.45, v_paint.a * hollow_wetness);
	SPECULAR = specular;
}

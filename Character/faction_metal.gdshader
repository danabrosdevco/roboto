shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// ─────────────────────────────────────────────────────────────
// FACTION METAL
//
// GL Compatibility has no per-instance uniforms, so faction
// colour is a plain uniform and materials are shared PER FACTION
// — four ShaderMaterials total, not one per robot. Batching still
// works within a faction, which is the grouping that matters.
//
// Two channels carry the faction read:
//   ALBEDO   — panels tinted by multiply, so the texture's own
//              scratches and panel lines survive. Close range.
//   EMISSION — accent markers. These are what actually reads
//              through the signal filter at distance, because
//              bright saturated pixels land in their own chroma
//              bucket after quantisation.
//
// FactionLivery builds and caches those four materials and
// assigns them via material_override.
// ─────────────────────────────────────────────────────────────

uniform sampler2D albedo_tex : source_color, filter_nearest_mipmap;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap;
uniform bool  use_normal_map = false;
uniform float normal_scale : hint_range(0.0, 2.0) = 1.0;

// R = paintable panels, G = emissive markers.
// Leave unassigned to fall back to the derived mask below.
uniform sampler2D mask_tex : hint_default_white, filter_nearest_mipmap;
uniform bool  derive_mask_from_albedo = true;

// Fallback mask: paint the mid-tones only. Highlights stay
// neutral so the metal still reads as metal, and deep shadows
// stay neutral so the tint doesn't muddy the silhouette.
uniform float paint_band_center : hint_range(0.0, 1.0) = 0.45;
uniform float paint_band_width  : hint_range(0.05, 0.6) = 0.28;

uniform vec3  base_tint : source_color = vec3(1.0);
uniform float metallic  : hint_range(0.0, 1.0) = 0.85;
uniform float roughness : hint_range(0.0, 1.0) = 0.55;

// ── PER-FACTION ──────────────────────────────────────────────
uniform vec4  faction_color : source_color = vec4(0.85, 0.55, 0.15, 1.0);
uniform float paint_blend   : hint_range(0.0, 1.0) = 0.40;
uniform float marker_energy : hint_range(0.0, 6.0) = 2.2;
uniform float shutdown      : hint_range(0.0, 1.0) = 0.0;  // 1.0 = dead, markers dark

void fragment() {
	vec4 tex    = texture(albedo_tex, UV);
	vec3 albedo = tex.rgb * base_tint;
	float lum   = dot(albedo, vec3(0.2126, 0.7152, 0.0722));

	vec3  m           = texture(mask_tex, UV).rgb;
	float paint_mask  = m.r;
	float marker_mask = m.g;

	if (derive_mask_from_albedo) {
		paint_mask  = 1.0 - smoothstep(0.0, paint_band_width, abs(lum - paint_band_center));
		marker_mask = 0.0;
	}

	float p = paint_mask * paint_blend;

	// Multiply, don't replace — keeps every scratch and panel line.
	// The 2.0 compensates for multiply darkening a mid-grey base.
	albedo = mix(albedo, albedo * faction_color.rgb * 2.0, p);

	ALBEDO = clamp(albedo, vec3(0.0), vec3(1.0));

	// Painted panels are less bare metal and slightly rougher —
	// this small physical difference sells the tint as paint
	// rather than as a colour filter laid over the model.
	METALLIC  = metallic * (1.0 - p * 0.5);
	ROUGHNESS = mix(roughness, min(roughness + 0.25, 1.0), p);

	EMISSION = faction_color.rgb * marker_mask * marker_energy * (1.0 - shutdown);

	if (use_normal_map) {
		NORMAL_MAP       = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}

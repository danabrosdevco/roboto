shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, shadows_disabled;

// MUZZLE FLASH — heat, from a white star.
//
// The four flash textures are pure white shapes with a soft alpha fringe. Run
// through Sprite3D's own material that is exactly what you got: a grey-white
// smear, the same colour as everything else in a valley of grey robots. Powder
// does not burn white. It burns white in the middle and orange-red at the
// edge, and the edge is where the shape is.
//
// So the ramp keys on ALPHA, not on brightness: the texture has no brightness
// variation to key on — its shape lives entirely in the alpha channel. Solid
// middle goes white-hot, the falloff goes yellow then red, and additive
// blending means it only ever adds light to what is behind it.

uniform sampler2D flash : source_color, filter_linear, hint_default_white;
uniform vec3 edge_colour : source_color = vec3(0.90, 0.16, 0.03);
uniform vec3 mid_colour : source_color = vec3(1.0, 0.55, 0.08);
uniform vec3 core_colour : source_color = vec3(1.0, 0.94, 0.74);
/// Folded in from the Sprite3D's old modulate alpha, which material_override
/// no longer applies.
uniform float strength : hint_range(0.0, 3.0) = 0.8;

void vertex() {
	// BILLBOARD BY HAND. Sprite3D does this inside the material it generates,
	// and material_override replaces that material — so without this the flash
	// is a flat quad you see edge-on half the time. Same maths BaseMaterial3D
	// uses, scale kept off the view basis so the node's own scale still counts.
	mat4 facing = mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_MATRIX = VIEW_MATRIX * facing * mat4(
		vec4(length(MODEL_MATRIX[0].xyz), 0.0, 0.0, 0.0),
		vec4(0.0, length(MODEL_MATRIX[1].xyz), 0.0, 0.0),
		vec4(0.0, 0.0, length(MODEL_MATRIX[2].xyz), 0.0),
		vec4(0.0, 0.0, 0.0, 1.0));
}

void fragment() {
	float a = texture(flash, UV).a;
	vec3 heat = mix(edge_colour, mid_colour, smoothstep(0.03, 0.45, a));
	heat = mix(heat, core_colour, smoothstep(0.55, 0.96, a));
	ALBEDO = heat;
	ALPHA = a * strength;
}

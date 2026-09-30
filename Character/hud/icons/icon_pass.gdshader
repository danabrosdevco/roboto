// ICON PASS — paints every surface with what the edge filter needs to see:
// which way it faces (red/green = view-space normal) and how far away it is
// (blue = depth across the model, near to far). The Compatibility renderer
// hands no normal or depth buffer to a shader, so the icon studio renders its
// own. Never lit, never fogged: the colours are data, not a picture.
shader_type spatial;
render_mode unshaded, fog_disabled, shadows_disabled, cull_back;

// The model's nearest and farthest distance from the camera, set per icon.
uniform float near_d = 0.0;
uniform float far_d = 1.0;

varying float view_z;

void vertex() {
	view_z = -(MODELVIEW_MATRIX * vec4(VERTEX, 1.0)).z;
}

void fragment() {
	vec3 n = normalize(NORMAL);
	float d = clamp((view_z - near_d) / max(far_d - near_d, 0.0001), 0.0, 1.0);
	ALBEDO = vec3(n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, d);
}

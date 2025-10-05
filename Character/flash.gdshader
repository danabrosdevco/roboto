shader_type spatial;
render_mode blend_add, unshaded;

uniform sampler2D albedo_texture : source_color;

void fragment() {
    vec4 tex = texture(albedo_texture, UV);
    ALBEDO = tex.rgb;
    ALPHA = tex.a;
    EMISSION = tex.rgb * 4.0; // bright emission
}
shader_type spatial;
// Quaternius hair, beards and eyebrows re-colored per villager. The source
// texture's light/dark strands are kept; only the color changes.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float base_luminance = 0.12;
uniform float roughness_value = 0.75;

instance uniform vec4 hair_color : source_color = vec4(0.29, 0.18, 0.11, 1.0);

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	float lum = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = hair_color.rgb * clamp(lum / base_luminance, 0.3, 1.8);
	ROUGHNESS = roughness_value;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}

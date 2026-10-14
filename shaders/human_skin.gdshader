shader_type spatial;
// Skin for villagers wearing real clothes (OutfitKit): the head cut from the
// Quaternius base body and the hands that come with the outfit pieces.
// The texture is re-tinted to the villager's skin tone relative to its own
// average luminance, so painted details (lips, brows, shading) survive.
// skin_tint is an instance uniform, so everyone shares one material.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
uniform float skin_luminance = 0.36;
// Extra saturation so skin stays warm under the bluish sky light and ACES.
uniform float skin_saturation = 1.35;

instance uniform vec4 skin_tint : source_color = vec4(0.88, 0.70, 0.55, 1.0);

void fragment() {
	vec3 tex = texture(albedo_tex, UV).rgb;
	float lum = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	vec3 skin = skin_tint.rgb * clamp(lum / skin_luminance, 0.45, 1.25);
	float grey = dot(skin, vec3(0.2126, 0.7152, 0.0722));
	ALBEDO = max(mix(vec3(grey), skin, skin_saturation), vec3(0.0));
	ROUGHNESS = texture(rough_tex, UV).g * 0.9 + 0.1;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
}

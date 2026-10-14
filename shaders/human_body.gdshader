shader_type spatial;
// Quaternius base body with skin tone and painted-on clothing.
//
// The free Universal Base Characters ship without clothes, and the matching
// outfit pack isn't in the project yet, so clothing is painted on from smooth
// body coordinates that HumanModel bakes into COLOR when a body is loaded:
//   COLOR.r = position along the arm (0 shoulder, 0.5 elbow, 0.85 wrist,
//             1 fingertip; 0 for anything that isn't arm)
//   COLOR.g = rest height / body height (0 = soles, 1 = top of head)
//   COLOR.b = distance from the body's center line (meters / 0.5)
//   COLOR.a = 1 on the front of the body, 0 on the back
// Per-villager colors are instance uniforms, so every villager shares one
// material.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough_tex : hint_roughness_g, filter_linear_mipmap, repeat_enable;
// Average linear luminance of the skin in albedo_tex: skin is re-tinted
// relative to it so painted details (lips, brows, shading) survive.
uniform float skin_luminance = 0.36;

instance uniform vec4 skin_tint : source_color = vec4(0.88, 0.70, 0.55, 1.0);
instance uniform vec4 cloth_primary : source_color = vec4(0.48, 0.38, 0.28, 1.0);
instance uniform vec4 cloth_secondary : source_color = vec4(0.29, 0.23, 0.16, 1.0);
// 0 tunic, 1 robe, 2 gown, 3 armor, 4 apron, 5 fine
instance uniform float outfit = 0.0;

varying vec4 region_data;

void vertex() {
	region_data = COLOR;
}

float weave(vec2 uv) {
	vec2 w = abs(fract(uv * vec2(900.0, 900.0)) - 0.5);
	return 0.94 + 0.06 * smoothstep(0.1, 0.4, min(w.x, w.y));
}

void fragment() {
	float arm = region_data.r;
	float h = region_data.g;
	float side = region_data.b;
	bool front = region_data.a > 0.5;
	int style = int(round(outfit));

	vec3 boots = vec3(0.10, 0.065, 0.04);
	vec3 leather = vec3(0.16, 0.10, 0.06);
	vec3 mail = vec3(0.42, 0.44, 0.47);
	vec3 primary = cloth_primary.rgb;
	vec3 secondary = cloth_secondary.rgb;
	bool long_sleeves = style == 1 || style == 2 || style == 3 || style == 5;
	bool long_skirt = style == 1 || style == 2;

	float covered = 1.0;  // 0 = bare skin
	vec3 cloth = primary;
	float metal = 0.0;

	if (arm > 0.002) {
		if (arm > (long_sleeves ? 0.83 : 0.42)) { covered = 0.0; }
		if (style == 3) {
			cloth = arm > 0.5 ? leather : mail;
			metal = arm > 0.5 ? 0.0 : 0.55;
		}
		if (style == 5 && arm > 0.74) { cloth = secondary; }                     // cuffs
	} else {
		float neck = 0.835 - ((front && side < 0.1) ? (0.1 - side) * 0.5 : 0.0); // small V-neck
		if (h > neck) {
			covered = 0.0;                                                     // head and neck
		} else if (h > 0.47) {                                                 // torso
			if (style == 3 && side > 0.32) { cloth = mail; metal = 0.55; }      // mail around a tabard
			if (style == 4 && front && side < 0.36 && h < 0.75) { cloth = secondary; } // apron bib
			if (style == 5 && h > 0.80) { cloth = secondary; }                  // collar
			if (h > 0.535 && h < 0.565 && style != 2) {                          // belt
				cloth = (style == 1 || style == 5) ? secondary : leather;
				metal = 0.0;
			}
		} else {                                                               // legs
			bool skirt = long_skirt || h > 0.36;
			cloth = skirt ? primary : secondary;
			if (style == 3) { cloth = (side < 0.32 && h > 0.36) ? primary : secondary; }
			if (style == 5) { cloth = secondary; }
			if (style == 4 && front && side < 0.36 && h > 0.30) { cloth = secondary; } // apron
			if (long_skirt && h < 0.07) { cloth = secondary; }                  // hem
			if (!long_skirt && h < 0.16) { cloth = boots; }                     // boots
			if (long_skirt && h < 0.035) { cloth = boots; }
		}
	}

	vec3 tex = texture(albedo_tex, UV).rgb;
	float lum = dot(tex, vec3(0.2126, 0.7152, 0.0722));
	vec3 skin = skin_tint.rgb * clamp(lum / skin_luminance, 0.45, 1.25);
	// Soft shading inside folds so cloth doesn't look flat.
	float fold = mix(0.82, 1.0, smoothstep(0.0, 0.3, lum));
	vec3 cloth_col = cloth * weave(UV) * fold;

	ALBEDO = mix(skin, cloth_col, covered);
	ROUGHNESS = mix(texture(rough_tex, UV).g * 0.9 + 0.1, mix(0.88, 0.45, metal), covered);
	METALLIC = metal * covered;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = mix(1.0, 0.15, covered);
}

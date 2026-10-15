shader_type spatial;
render_mode cull_disabled;
// Charter banner cloth in a breeze. UV2.x holds the sway weight baked in
// Blender (0 where the cloth wraps the arm, 1 at the hem; gilt fittings 0),
// so only cloth, fringe and tassels move. The phase comes from world
// position, so neighbouring banners don't flap in lockstep.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap, repeat_enable;
uniform float roughness = 0.85;
uniform float sway = 0.06;   // meters of travel at the hem
uniform float speed = 1.5;
uniform float translucency = 0.55;  // sunlight through the cloth from behind

void vertex() {
	float w = UV2.x;
	if (w > 0.001) {
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float t = TIME * speed + wp.x * 0.31 + wp.z * 0.23;
		float ripple = sin(t + VERTEX.y * 2.2) * 0.7 + sin(t * 1.9 + (VERTEX.x + VERTEX.z) * 3.1) * 0.3;
		VERTEX += NORMAL * ripple * sway * w;
	}
}

void fragment() {
	vec3 albedo = texture(albedo_texture, UV).rgb;
	ALBEDO = albedo;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	// Cloth glows when the sun is behind it, so banners stay vivid from
	// both sides. The gilt fittings (the atlas's bottom strip) stay solid.
	BACKLIGHT = albedo * translucency * (1.0 - step(0.905, UV.y));
}

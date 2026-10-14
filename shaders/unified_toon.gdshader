// Unifies the look of models from any source (asset packs, AI generators,
// procedural primitives): every color is pulled toward the nearest color of
// one shared palette, and lighting uses the same soft toon ramp everywhere.
shader_type spatial;
render_mode diffuse_toon, specular_disabled;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap;
uniform bool use_texture = false;
// Multiply by per-vertex / per-instance colors (MultiMesh trees, crops...).
uniform bool use_vertex_color = false;
uniform bool vertex_color_is_srgb = true;
// Palette as an N x 1 texture (see data/art_style.json).
uniform sampler2D palette : source_color, filter_nearest;
uniform int palette_size = 1;
uniform float palette_strength : hint_range(0.0, 1.0) = 0.85;
uniform vec4 rim_color : source_color = vec4(1.0, 0.95, 0.85, 1.0);
uniform float rim_strength : hint_range(0.0, 1.0) = 0.25;

vec3 to_perceptual(vec3 c) {
	return pow(max(c, vec3(0.0)), vec3(1.0 / 2.2));
}

void fragment() {
	vec4 c = albedo_color;
	if (use_texture) {
		c *= texture(albedo_texture, UV);
	}
	if (use_vertex_color) {
		vec3 vc = COLOR.rgb;
		if (vertex_color_is_srgb) {
			vc = pow(vc, vec3(2.2));
		}
		c.rgb *= vc;
	}
	vec3 pc = to_perceptual(c.rgb);
	vec3 best = c.rgb;
	float best_d = 1e9;
	for (int i = 0; i < palette_size; i++) {
		vec3 p = texelFetch(palette, ivec2(i, 0), 0).rgb;
		vec3 d = pc - to_perceptual(p);
		float dist = dot(d * d, vec3(0.30, 0.59, 0.11));
		if (dist < best_d) {
			best_d = dist;
			best = p;
		}
	}
	ALBEDO = mix(c.rgb, best, palette_strength);
	ROUGHNESS = 1.0;
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	EMISSION = rim_color.rgb * rim * rim_strength * 0.3;
}

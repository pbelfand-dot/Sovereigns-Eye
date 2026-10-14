shader_type spatial;
render_mode cull_disabled;
// Trees, ground cover and rocks from the Quaternius Stylized Nature MegaKit,
// drawn as MultiMesh instances (NatureKit). Per instance, INSTANCE_CUSTOM
// carries a linear tint (rgb) and a wind phase (a). Tinted materials (the
// kit's white leaf maps, grass) take the tint; the mesh's vertex colors are
// baked ambient occlusion. Wind sways vertices more the higher they are.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform float tint_amount : hint_range(0.0, 1.0) = 0.0;
uniform float alpha_cutoff : hint_range(0.0, 1.0) = 0.2;
uniform float vertex_ao : hint_range(0.0, 1.0) = 0.7;
uniform float wind_strength = 0.0;
uniform float wind_height = 6.0;
uniform float wind_speed = 1.0;
uniform float roughness : hint_range(0.0, 1.0) = 0.9;
uniform float brightness = 1.0;
// Leaf cards light like a rounded crown: normals bend away from the canopy
// center (model space), so canopies read as soft volumes from above.
uniform float canopy_normals : hint_range(0.0, 1.0) = 0.0;
uniform vec3 canopy_center = vec3(0.0, 5.0, 0.0);

varying vec3 v_tint;

void vertex() {
	v_tint = mix(vec3(1.0), INSTANCE_CUSTOM.rgb, tint_amount);
	if (canopy_normals > 0.0) {
		NORMAL = normalize(mix(NORMAL, normalize(VERTEX - canopy_center), canopy_normals));
	}
	if (wind_strength > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		float phase = origin.x * 0.21 + origin.z * 0.17 + INSTANCE_CUSTOM.a * 6.2832;
		float bend = pow(clamp(VERTEX.y / wind_height, 0.0, 1.0), 2.0) * wind_strength;
		float gust = 0.75 + 0.25 * sin(TIME * wind_speed * 0.31 + origin.x * 0.02);
		VERTEX.x += sin(TIME * wind_speed + phase) * bend * gust;
		VERTEX.z += sin(TIME * wind_speed * 0.73 + phase * 1.37) * bend * gust * 0.6;
	}
}

void fragment() {
	vec4 tex = texture(albedo_tex, UV);
	ALBEDO = tex.rgb * v_tint * mix(vec3(1.0), COLOR.rgb, vertex_ao) * brightness;
	// Smaller mip levels blur the leaf alpha below the cutoff and canopies
	// thin out with distance; scale alpha up per mip level to keep coverage.
	vec2 texels = UV * vec2(textureSize(albedo_tex, 0));
	vec2 dx = dFdx(texels);
	vec2 dy = dFdy(texels);
	float mip = max(0.0, 0.5 * log2(max(dot(dx, dx), dot(dy, dy))));
	ALPHA = tex.a * (1.0 + mip * 0.25);
	ALPHA_SCISSOR_THRESHOLD = alpha_cutoff;
	ROUGHNESS = roughness;
	SPECULAR = 0.25;
}

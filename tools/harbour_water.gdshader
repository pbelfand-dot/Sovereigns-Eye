// The sea in the demo harbour (tools/harbour_demo.gd). Water belongs to the
// coast phase: this is only for showing the Harbour & Ships family, not a
// game system. Small waves from a few sines, see-through when looked into,
// opaque at grazing angles; runs on all three renderers.
shader_type spatial;
render_mode blend_mix, depth_draw_always, cull_back, diffuse_burley, specular_schlick_ggx;

uniform vec4 deep : source_color = vec4(0.12, 0.27, 0.30, 1.0);
uniform vec4 shallow : source_color = vec4(0.26, 0.42, 0.40, 1.0);
uniform float clarity : hint_range(0.0, 1.0) = 0.78;
uniform float wave_scale = 0.07;

void fragment() {
	vec2 p = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	float t = TIME * 0.6;
	vec2 w = vec2(sin(p.x * 0.9 + t) + 0.6 * sin(p.y * 1.3 - t * 1.1) + 0.3 * sin((p.x - p.y) * 2.7 + t * 1.7),
			cos(p.y * 0.8 + t * 0.7) + 0.4 * sin((p.x + p.y) * 1.7 + t) + 0.3 * cos(p.x * 3.1 - t * 1.3));
	// The ripples flatten with distance, before they alias into a pattern.
	float fade = 1.0 - smoothstep(25.0, 140.0, length(VERTEX));
	vec3 n = normalize(vec3(w.x * wave_scale * fade, 1.0, w.y * wave_scale * fade));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float facing = clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float fres = pow(1.0 - facing, 3.0);
	ALBEDO = mix(shallow.rgb, deep.rgb, 0.55 + 0.45 * fres);
	ROUGHNESS = 0.06;
	METALLIC = 0.0;
	SPECULAR = 0.6;
	ALPHA = mix(clarity, 1.0, fres);
}

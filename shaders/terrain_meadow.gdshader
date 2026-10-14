// Meadow ground. The terrain's vertex colors (sRGB) give the broad tint
// (forest edge, trodden centre, hills); world-space noise breaks it into sunlit
// and lush patches, grass clumps, fine grain, bare earth and a scatter of wild
// flowers. A baked wear mask wears the grass down along roads, around the
// square and in front of buildings. Values come from data/art_style.json.
shader_type spatial;
render_mode cull_disabled;

uniform vec3 lush_tint = vec3(0.86, 1.0, 0.82);
uniform vec3 dry_tint = vec3(1.22, 1.12, 0.72);
uniform float patch_scale = 26.0;
uniform float patch_strength : hint_range(0.0, 1.0) = 0.6;
uniform float clump_scale = 3.2;
uniform float clump_strength : hint_range(0.0, 1.0) = 0.2;
uniform float grain_scale = 0.35;
uniform float grain_strength : hint_range(0.0, 1.0) = 0.16;
uniform vec4 dirt_color : source_color = vec4(0.48, 0.38, 0.26, 1.0);
uniform float dirt_threshold : hint_range(0.0, 1.0) = 0.7;
uniform vec4 wear_color : source_color = vec4(0.56, 0.54, 0.35, 1.0);
uniform vec4 flower_a : source_color = vec4(0.95, 0.9, 0.63, 1.0);
uniform vec4 flower_b : source_color = vec4(0.91, 0.93, 0.95, 1.0);
uniform vec4 flower_c : source_color = vec4(0.79, 0.54, 0.82, 1.0);
uniform float flower_cell = 0.7;
uniform float flower_density : hint_range(0.0, 1.0) = 0.035;
uniform float flower_radius = 0.11;
// Flowers grow in drifts: only where this noise (scale in meters) is high.
uniform float flower_patch_scale = 9.0;
uniform float bump_strength : hint_range(0.0, 2.0) = 0.6;
uniform vec2 detail_fade = vec2(40.0, 140.0);
// Wear mask: R channel, 1 = bare trodden earth. Covers wear_origin .. +wear_size.
uniform sampler2D wear_mask : filter_linear, repeat_disable;
uniform vec2 wear_origin = vec2(-190.0);
uniform float wear_size = 380.0;
uniform bool use_wear = false;

varying vec3 world_pos;
varying vec3 world_normal;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec2 hash22(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.xx + p3.yz) * p3.zy);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	float s = 0.0;
	float amp = 0.5;
	mat2 turn = mat2(vec2(1.6, 1.2), vec2(-1.2, 1.6));
	for (int i = 0; i < 4; i++) {
		s += value_noise(p) * amp;
		p = turn * p;
		amp *= 0.5;
	}
	return s / 0.9375;
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 p = world_pos.xz;
	vec3 col = pow(COLOR.rgb, vec3(2.2));
	float detail = 1.0 - smoothstep(detail_fade.x, detail_fade.y, length(world_pos - CAMERA_POSITION_WORLD));

	// Sunlit, drier meadow vs lush, darker grass.
	float patches = fbm(p / patch_scale);
	float dry = smoothstep(0.3, 0.72, patches);
	col *= mix(vec3(1.0), mix(lush_tint, dry_tint, dry), patch_strength);

	// Clumps and fine grain.
	vec2 cp = p / clump_scale + vec2(41.7, 13.1);
	float clumps = fbm(cp);
	col *= 1.0 + (clumps - 0.5) * 2.0 * clump_strength;
	// Tufts catch the light: tilt the normal along the clump noise.
	float e = 0.15;
	vec2 slope = vec2(fbm(cp + vec2(e, 0.0)) - clumps, fbm(cp + vec2(0.0, e)) - clumps) / e;
	vec3 n = normalize(world_normal - vec3(slope.x, 0.0, slope.y) * bump_strength * mix(0.3, 1.0, detail));
	float grain = value_noise(p / grain_scale);
	col *= 1.0 + (grain - 0.5) * 2.0 * grain_strength * mix(0.35, 1.0, detail);

	// Trodden ground from the wear mask, ragged at the edges.
	float wear = 0.0;
	if (use_wear) {
		vec2 uv = (p - wear_origin) / wear_size;
		wear = texture(wear_mask, uv).r;
		wear = clamp(wear + (clumps - 0.5) * 0.5 + (grain - 0.5) * 0.25 * detail, 0.0, 1.0);
	}
	vec3 earth = dirt_color.rgb * (0.85 + grain * 0.3);
	col = mix(col, wear_color.rgb * (0.9 + clumps * 0.2), smoothstep(0.15, 0.55, wear) * 0.75);
	col = mix(col, earth, smoothstep(0.55, 0.85, wear));

	// Occasional bare patches out in the meadow.
	float bare = fbm(p / (patch_scale * 0.45) + vec2(-7.3, 22.9)) + (grain - 0.5) * 0.12;
	col = mix(col, earth, smoothstep(dirt_threshold, dirt_threshold + 0.1, bare) * 0.55);

	// Wild flowers: at most one dot per cell, only on grass and only up close.
	vec2 cell = floor(p / flower_cell);
	float drift = smoothstep(0.55, 0.75, fbm(p / flower_patch_scale + vec2(-19.4, 5.2)));
	float density = flower_density * drift;
	float pick = hash12(cell + vec2(3.1, 7.7));
	if (pick < density && detail > 0.0) {
		vec2 centre = (cell + 0.2 + hash22(cell) * 0.6) * flower_cell;
		float dot_mask = 1.0 - smoothstep(flower_radius * 0.55, flower_radius, length(p - centre));
		float which = hash12(cell + vec2(11.3, -4.1));
		vec3 petal = which < 0.4 ? flower_a.rgb : (which < 0.8 ? flower_b.rgb : flower_c.rgb);
		float on_grass = (1.0 - smoothstep(0.2, 0.5, wear)) * (1.0 - smoothstep(dirt_threshold - 0.04, dirt_threshold, bare));
		col = mix(col, petal, dot_mask * detail * on_grass);
	}

	ALBEDO = col;
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	ROUGHNESS = 1.0;
	SPECULAR = 0.15;
}

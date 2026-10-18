shader_type sky;
// The key art's sky (tools/key_art.gd only, not the game's): a late golden
// hour, deep blue overhead warming to gold at the horizon, brightest round
// the low sun, with drifting clouds lit gold on their sunward side.

uniform vec3 zenith : source_color = vec3(0.16, 0.24, 0.46);
uniform vec3 upper : source_color = vec3(0.42, 0.50, 0.70);
uniform vec3 horizon : source_color = vec3(0.98, 0.70, 0.42);
uniform vec3 sun_glow : source_color = vec3(1.0, 0.78, 0.45);
uniform vec3 cloud_lit : source_color = vec3(1.0, 0.80, 0.55);
uniform vec3 cloud_shade : source_color = vec3(0.42, 0.38, 0.52);
uniform vec3 ground : source_color = vec3(0.16, 0.15, 0.13);
uniform float cloud_cover : hint_range(0.0, 1.0) = 0.52;
uniform float exposure = 1.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), u.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float v = 0.0;
	float a = 0.5;
	for (int k = 0; k < 6; k++) {
		v += a * noise(p);
		p = p * 2.03 + vec2(1.7, 9.2);
		a *= 0.5;
	}
	return v;
}

void sky() {
	vec3 d = EYEDIR;
	vec3 sun = LIGHT0_ENABLED ? -LIGHT0_DIRECTION : vec3(0.0, 0.2, 1.0);
	float up = clamp(d.y, 0.0, 1.0);
	// Toward the sun the whole sky warms.
	float toward = clamp(dot(normalize(vec2(d.x, d.z)), normalize(vec2(sun.x, sun.z))) * 0.5 + 0.5, 0.0, 1.0);
	vec3 col = mix(horizon, upper, smoothstep(0.0, 0.28, up));
	col = mix(col, zenith, smoothstep(0.22, 0.85, up));
	col = mix(col, col * vec3(1.1, 0.95, 0.85) + sun_glow * 0.18, pow(toward, 3.0) * (1.0 - up));
	float s = max(dot(d, sun), 0.0);
	col += sun_glow * (pow(s, 6.0) * 0.45 + pow(s, 64.0) * 0.9);
	col += vec3(1.0, 0.92, 0.78) * smoothstep(0.9993, 0.9997, s) * 6.0;
	if (d.y > 0.0) {
		// Clouds on a high, flat layer: thin near the horizon.
		vec2 uv = d.xz / (d.y + 0.08) * 0.9;
		float n = fbm(uv * 1.2 + vec2(3.0, 1.0));
		float c = smoothstep(1.0 - cloud_cover, 1.0 - cloud_cover + 0.28, n);
		c *= smoothstep(0.02, 0.18, d.y);
		float lit = clamp(pow(s, 3.0) * 1.6 + toward * 0.45 + (fbm(uv * 1.2 + vec2(3.3, 1.2)) - n) * 2.5, 0.0, 1.0);
		vec3 cc = mix(cloud_shade, cloud_lit, lit);
		col = mix(col, cc, c * 0.85);
	} else {
		col = mix(horizon * 0.6, ground, smoothstep(0.0, 0.12, -d.y));
	}
	COLOR = col * exposure;
}

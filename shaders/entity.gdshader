shader_type spatial;
render_mode cull_back, diffuse_burley;

// Тварь: почти чёрный силуэт с пыльной кромкой, без бликов.
uniform vec3 body_color : source_color = vec3(0.020, 0.018, 0.016);
uniform float rim_power = 3.0;

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
			mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float n = vnoise(wpos.xz * 7.0 + vec2(TIME * 0.6, wpos.y * 3.0));
	float n2 = vnoise(wpos.xy * 19.0 - wpos.z);

	vec3 col = body_color * (0.55 + 0.9 * n + 0.25 * n2);
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), rim_power);

	ALBEDO = col;
	ROUGHNESS = 0.55;
	SPECULAR = 0.1;
	EMISSION = vec3(0.06, 0.055, 0.045) * rim * 2.2;
}

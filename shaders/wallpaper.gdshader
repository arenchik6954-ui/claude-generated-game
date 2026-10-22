shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Обои Уровня 0: мокрый жёлтый муар, полосы, потёки и грязь.
uniform vec3 base_color : source_color = vec3(0.70, 0.61, 0.29);
uniform vec3 light_stripe : source_color = vec3(0.84, 0.75, 0.40);
uniform vec3 grime_color : source_color = vec3(0.20, 0.17, 0.09);
uniform float stripe_count = 9.0;
uniform float pattern_scale = 0.35;
uniform float grime_amount = 0.95;

varying vec3 wpos;
varying vec3 wnorm;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float vnoise(vec2 p) {
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
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 5; i++) {
		v += amp * vnoise(p);
		p *= 2.03;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnorm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	float wall_mask = 1.0 - step(0.7, abs(wnorm.y));
	vec2 uv = mix(wpos.xz, vec2(wpos.x + wpos.z, wpos.y), wall_mask) * pattern_scale;

	float stripes = smoothstep(0.40, 0.5, abs(fract(uv.x * stripe_count) - 0.5));
	float fine = sin(uv.x * 220.0) * 0.5 + 0.5;

	vec3 col = mix(base_color, light_stripe, stripes * 0.30);
	col *= 0.93 + 0.07 * fine;

	float large = fbm(uv * 2.1);
	float small = fbm(uv * 10.0 + 4.0);

	float stain = smoothstep(0.50, 0.80, large) * grime_amount;
	col = mix(col, grime_color, stain * 0.5);
	col *= 0.88 + 0.12 * small;

	// тёмный плинтус и грязный стык с потолком
	float low_band = 1.0 - smoothstep(0.0, 0.65, wpos.y);
	col *= 1.0 - 0.32 * low_band * wall_mask;
	float high_band = smoothstep(2.1, 3.0, wpos.y);
	col *= 1.0 - 0.22 * high_band * wall_mask;

	// сколы и разводы
	float chips = step(0.94, fbm(uv * 5.5 + 17.0));
	col = mix(col, vec3(0.28, 0.25, 0.19), chips * 0.3);

	ALBEDO = col;
	ROUGHNESS = 0.94 - 0.18 * stain;
	SPECULAR = 0.22;
}

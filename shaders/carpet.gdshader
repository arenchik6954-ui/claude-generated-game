shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Влажный ковролин: ворс, пятна, блеск сырых участков.
uniform vec3 base_color : source_color = vec3(0.38, 0.31, 0.13);
uniform vec3 fiber_color : source_color = vec3(0.51, 0.42, 0.20);
uniform vec3 stain_color : source_color = vec3(0.12, 0.10, 0.05);
uniform float pattern_scale = 1.0;

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

float fbm(vec2 p) {
	float v = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		v += amp * vnoise(p);
		p *= 2.07;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz * pattern_scale;
	float fibers = vnoise(uv * 26.0);
	float coarse = fbm(uv * 1.6);

	vec3 col = mix(base_color, fiber_color, fibers * 0.55);
	float damp = smoothstep(0.48, 0.76, coarse);
	col = mix(col, stain_color, damp * 0.72);

	// редкие светлые ворсинки
	float fleck = step(0.985, hash12(floor(uv * 90.0)));
	col += fleck * 0.20;

	float near_wall = 1.0;
	ALBEDO = col;
	ROUGHNESS = mix(0.96, 0.38, damp);
	METALLIC = 0.0;
	SPECULAR = mix(0.15, 0.55, damp) * near_wall;
}

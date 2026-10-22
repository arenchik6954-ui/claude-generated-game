shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

// Подвесной потолок: плиты, швы, разводы и жёлтые пятна.
uniform vec3 tile_color : source_color = vec3(0.46, 0.43, 0.32);
uniform vec3 seam_color : source_color = vec3(0.10, 0.09, 0.06);
uniform vec3 stain_color : source_color = vec3(0.30, 0.24, 0.11);
uniform float tile_size = 0.62;

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
		p *= 2.11;
		amp *= 0.5;
	}
	return v;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz / tile_size;
	vec2 cell = floor(uv);
	vec2 local = fract(uv);

	float seam = max(1.0 - smoothstep(0.0, 0.035, local.x),
			1.0 - smoothstep(0.0, 0.035, local.y));
	seam = max(seam, max(1.0 - smoothstep(0.965, 1.0, local.x), 1.0 - smoothstep(0.965, 1.0, local.y)));

	vec3 col = tile_color;
	col *= 0.84 + 0.16 * hash12(cell * 1.7);

	float dirt = fbm(wpos.xz * 0.8 + cell * 0.4);
	col = mix(col, stain_color, smoothstep(0.52, 0.85, dirt) * 0.55);

	col *= 0.8 + 0.2 * vnoise(wpos.xz * 24.0);
	col = mix(col, seam_color, seam * 0.85);

	ALBEDO = col;
	ROUGHNESS = 0.95;
	SPECULAR = 0.1;
}

shader_type canvas_item;

// Финальный слой: VHS-зерно, виньетка, хроматическая аберрация,
// пульс страха и помехи джампскейра.
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;

uniform float fear : hint_range(0.0, 1.0) = 0.0;
uniform float static_amount : hint_range(0.0, 1.0) = 0.0;
uniform float hurt : hint_range(0.0, 1.0) = 0.0;
uniform float vignette_strength : hint_range(0.0, 2.0) = 1.0;
uniform float grain_strength : hint_range(0.0, 0.3) = 0.055;
uniform float aberration : hint_range(0.0, 0.01) = 0.0016;
uniform float vhs_strength : hint_range(0.0, 1.0) = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 centered = SCREEN_UV - 0.5;
	float r2 = dot(centered, centered);

	// лёгкая бочка, как у старой камеры
	vec2 uv = 0.5 + centered * (1.0 - 0.045 * vhs_strength * r2);

	// дрожание картинки от страха
	uv.x += sin(uv.y * 620.0 + TIME * 13.0) * 0.0009 * fear;

	float ca = aberration * (1.0 + fear * 3.0 + static_amount * 8.0);
	vec3 col;
	col.r = texture(screen_tex, uv + centered * ca).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - centered * ca).b;

	float grain = hash12(uv * vec2(1920.0, 1080.0) + fract(TIME) * 91.7);
	float scan = sin(uv.y * 1400.0) * 0.5 + 0.5;
	col += (grain - 0.5) * grain_strength * (1.0 + fear * 1.6 + static_amount * 4.0);
	col *= 1.0 - 0.035 * scan * vhs_strength;

	// виньетка
	float vig = 1.0 - smoothstep(0.10, 0.52, r2 * (1.0 + fear * 1.5));
	col *= mix(1.0, clamp(vig, 0.0, 1.0), vignette_strength);

	// страх гасит цвета
	float lum = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(lum) * vec3(0.88, 0.84, 0.62), fear * 0.38);

	float pulse = 0.5 + 0.5 * sin(TIME * 6.5);
	col *= 1.0 - fear * 0.10 * pulse;

	// полосы и цифровой шум (скример / глюк)
	float block = hash12(vec2(floor(uv.y * 80.0), floor(TIME * 24.0)));
	float glitch = step(0.74, block) * static_amount;
	col = mix(col, vec3(hash12(uv + TIME)), glitch * 0.6);
	col += (hash12(uv * 640.0 + TIME) - 0.5) * static_amount * 0.6;

	// красная пелена урона
	col = mix(col, vec3(0.55, 0.02, 0.02), hurt * 0.4);

	COLOR = vec4(col, 1.0);
}

shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

// «Манета» — тёплое золото с пульсирующим свечением.
uniform vec3 gold : source_color = vec3(1.0, 0.74, 0.22);
uniform float glow = 0.55;
uniform float pulse_speed = 2.2;

varying vec3 wpos;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	float rim = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.0);
	float grooves = sin(wpos.y * 140.0) * 0.5 + 0.5;
	float pulse = 0.75 + 0.25 * sin(TIME * pulse_speed);

	ALBEDO = gold * (0.82 + 0.18 * grooves);
	METALLIC = 0.92;
	ROUGHNESS = 0.22 + 0.12 * grooves;
	EMISSION = gold * (0.22 + rim * glow) * pulse;
}

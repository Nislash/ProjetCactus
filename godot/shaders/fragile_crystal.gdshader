shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

// L'opale fissurée — « ceci se brise ».
//
// La lecture doit être immédiate et tenir en quart d'écran : un corps
// laiteux, translucide, PARCOURU DE FISSURES SOMBRES. Le contraste
// fissure/corps est ce qui distingue ce cristal de tous les autres cristaux
// du niveau, qui sont pleins et émissifs.
//
// `fracture` monte quand le cristal encaisse : les fissures s'illuminent une
// fraction de seconde. C'est le feedback de visée, et il arrive AVANT la
// rupture — le joueur comprend qu'il a touché, pas seulement qu'il a gagné.

uniform vec3 body_color : source_color = vec3(0.72, 0.82, 0.88);
uniform vec3 crack_color : source_color = vec3(0.09, 0.16, 0.24);
uniform vec3 flash_color : source_color = vec3(0.40, 0.85, 1.00);
uniform float fracture : hint_range(0.0, 1.0) = 0.0;
uniform float crack_scale = 5.0;
uniform float crack_width : hint_range(0.01, 0.4) = 0.11;
uniform float body_alpha : hint_range(0.2, 1.0) = 0.88;

float hash21(vec2 p) {
	p = fract(p * vec2(123.34, 456.21));
	p += dot(p, p + 45.32);
	return fract(p.x * p.y);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

void fragment() {
	// Les fissures suivent la ligne de crête d'un bruit : des filons qui
	// courent, là où un seuil ne donnerait que des taches.
	float n = value_noise(UV * crack_scale) * 0.65
		+ value_noise(UV * crack_scale * 2.7) * 0.35;
	float ridge = abs(n - 0.5);
	float crack = 1.0 - smoothstep(0.0, crack_width, ridge);

	vec3 base = mix(body_color, crack_color, crack);
	ALBEDO = base;
	ROUGHNESS = mix(0.28, 0.65, crack);
	METALLIC = 0.0;
	// Translucide : on devine ce qu'il y a derrière, donc on comprend qu'il
	// barre le passage plutôt qu'il ne le termine.
	ALPHA = body_alpha;
	EMISSION = flash_color * crack * fracture * 3.0;
}

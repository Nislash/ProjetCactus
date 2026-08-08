shader_type canvas_item;

// Le fond de l'écran d'accueil — une caverne suggérée.
//
// Trois couches, de l'arrière vers l'avant :
//   1. un dégradé vertical, sombre en haut : on regarde vers le fond d'un trou
//   2. des veines de cristal qui pulsent lentement, plus denses en bas
//   3. une poussière de particules qui monte, très lente
//
// Tout est procédural : pas de texture à charger, pas d'asset à maintenir, et
// l'image reste nette à toutes les résolutions. La palette vient de l'art
// bible §3 — c'est le même bleu que la caverne, pour que le menu promette le
// jeu qu'on va lancer.

uniform vec3 deep_color : source_color = vec3(0.020, 0.031, 0.047);
uniform vec3 rock_color : source_color = vec3(0.055, 0.078, 0.114);
uniform vec3 crystal_color : source_color = vec3(0.400, 0.851, 1.000);
uniform float vein_intensity : hint_range(0.0, 2.0) = 0.55;
uniform float dust_intensity : hint_range(0.0, 1.0) = 0.35;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
	p += dot(p, p + 34.23);
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

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p *= 2.07;
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	vec2 uv = UV;
	float t = TIME * 0.05;

	// 1. La roche. Plus claire vers le bas : la lumière vient d'en bas, comme
	//    dans la caverne où ce sont les cristaux du sol qui éclairent.
	float depth = smoothstep(0.0, 1.0, uv.y);
	vec3 col = mix(deep_color, rock_color, depth);
	col += vec3(fbm(uv * vec2(3.0, 2.0)) * 0.045);

	// 2. Les veines. Ligne de crête d'un bruit, comme sur la roche du jeu :
	//    un seuil donnerait des taches, la crête donne des filons.
	float ridge = abs(fbm(uv * vec2(4.5, 3.0) + vec2(0.0, t)) - 0.5);
	float vein = 1.0 - smoothstep(0.0, 0.055, ridge);
	// Elles respirent, décalées les unes des autres pour que l'ensemble ne
	// clignote jamais d'un bloc.
	float breath = 0.55 + 0.45 * sin(TIME * 0.5 + uv.y * 4.0);
	// Denses en bas, absentes en haut : le regard est tiré vers le fond.
	vein *= smoothstep(0.05, 0.95, uv.y) * breath;
	col += crystal_color * vein * vein_intensity;

	// 3. La poussière qui monte. Elle donne l'échelle : sans elle, l'image
	//    pourrait être un mur à trente centimètres.
	vec2 dust_uv = uv * vec2(40.0, 22.0) + vec2(0.0, -TIME * 0.35);
	float dust = hash21(floor(dust_uv));
	dust = step(0.9975, dust);
	float dust_fade = smoothstep(0.0, 0.6, uv.y);
	col += crystal_color * dust * dust_intensity * dust_fade;

	// Vignette : elle referme l'image et fait que le titre, au centre, respire.
	float vignette = 1.0 - smoothstep(0.35, 1.05, length(uv - vec2(0.5)) * 1.4);
	col *= mix(0.45, 1.0, vignette);

	COLOR = vec4(col, 1.0);
}

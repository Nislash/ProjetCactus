shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Habillage du Boss Golem — roche sombre parcourue de veines de cristal.
//
// POURQUOI UN SHADER ET PAS UNE TEXTURE MESHY : le Golem emprunte le
// squelette et les dix animations du mannequin « Sentinel ». Lui générer un
// corps neuf voudrait dire le rigger et reciblage les anims — beaucoup de
// travail pour un risque élevé sur la hitbox. Un habillage procédural garde
// le rig, la collision et l'IA strictement intacts.
//
// POURQUOI PAS DE TRIPLANAIRE : la roche de la caverne est texturée en
// projection monde, ce qui est parfait pour du décor immobile. Sur un corps
// qui marche, la matière glisserait sur la peau à chaque pas. Ici tout est
// en espace UV : la matière est solidaire du personnage.
//
// LE CHAUD EST RÉSERVÉ AU DANGER (art bible §3) : les veines sont cyan
// `#66d9ff` au repos et virent vers `#f2b45c` quand `heat` monte. C'est le
// même vocabulaire que les telegraphs au sol, donc lisible même en quart
// d'écran : quand le Golem s'allume en orange, quelque chose arrive.

uniform vec3 deep_color : source_color = vec3(0.040, 0.055, 0.082);
uniform vec3 rock_color : source_color = vec3(0.118, 0.169, 0.243);
uniform vec3 rock_highlight : source_color = vec3(0.227, 0.290, 0.376);

// Cristal cyan — couleur signature du niveau.
uniform vec3 vein_color : source_color = vec3(0.400, 0.851, 1.000);
// Danger — réservé aux telegraphs boss.
uniform vec3 danger_color : source_color = vec3(0.949, 0.706, 0.361);

// 0 = repos (veines cyan), 1 = enrage (veines orange).
uniform float heat : hint_range(0.0, 1.0) = 0.0;
// Battement additionnel, piloté par le windup d'attaque.
uniform float pulse : hint_range(0.0, 2.0) = 0.0;

uniform float vein_scale = 6.0;
uniform float vein_width : hint_range(0.01, 0.5) = 0.09;
uniform float vein_energy : hint_range(0.0, 8.0) = 2.2;
uniform float rock_scale = 14.0;
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.82;

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

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p *= 2.03;
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	// Grain de roche : deux octaves suffisent à casser l'aplat, la caméra
	// n'approche jamais assez pour en demander plus.
	float grain = fbm(UV * rock_scale);
	vec3 rock = mix(deep_color, rock_color, grain);
	rock = mix(rock, rock_highlight, smoothstep(0.62, 0.95, grain));

	// Les veines : la ligne de crête d'un bruit, pas un seuil. Un seuil
	// donnerait des taches ; la crête donne des filons qui courent.
	float ridge = abs(fbm(UV * vein_scale) - 0.5);
	float vein = 1.0 - smoothstep(0.0, vein_width, ridge);

	vec3 glow = mix(vein_color, danger_color, heat);

	ALBEDO = mix(rock, glow * 0.35, vein);
	// Le cristal est lisse, la roche ne l'est pas.
	ROUGHNESS = mix(rock_roughness, 0.22, vein);
	METALLIC = 0.0;
	EMISSION = glow * vein * vein_energy * (1.0 + pulse);
}

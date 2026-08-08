shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, unshaded;

// Le lac de lave — la source de lumière du niveau 2.
//
// `unshaded` est délibéré : la lave n'est pas éclairée, **elle éclaire**.
// Lui appliquer un modèle d'ombrage la ferait réagir aux lampes de la salle,
// c'est-à-dire à sa propre lumière, et elle s'assombrirait dans les coins.
//
// Trois couches donnent le mouvement, sans aucune texture :
//   1. des CROÛTES sombres qui dérivent lentement — la roche refroidie
//   2. les FISSURES entre elles, incandescentes
//   3. une pulsation de fond, très lente, qui empêche l'image de se figer
//
// Le contraste croûte/fissure est ce qui rend la surface lisible en
// mouvement. Une nappe uniformément orange serait un aplat.

uniform vec3 crust_color : source_color = vec3(0.086, 0.043, 0.035);
uniform vec3 hot_color : source_color = vec3(1.000, 0.478, 0.184);
uniform vec3 core_color : source_color = vec3(1.000, 0.902, 0.596);
uniform float flow_speed = 0.035;
uniform float crust_scale = 0.055;

// LE SENS DU COURANT, en repère monde (XZ). La coulée descend d'ouest en est.
//
// Le motif dérivait auparavant dans deux directions contraires : ça vivait,
// mais ça ne COULAIT pas — une nappe qui bouillonne sur place se lit comme un
// lac, pas comme une rivière. On échantillonne donc le bruit en le décalant
// À CONTRE-COURANT, ce qui fait avancer la matière dans le sens voulu.
uniform vec2 flow_direction = vec2(1.0, 0.0);

// Vitesse du courant, distincte de `flow_speed` qui règle la vie interne des
// plaques. Les deux se règlent séparément parce qu'elles ne racontent pas la
// même chose : l'une est le débit, l'autre le refroidissement.
uniform float current_speed = 0.9;

// Étirement des plaques DANS le sens du courant. Une croûte charriée
// s'allonge ; des plaques rondes qui glissent ressemblent à un tapis roulant.
uniform float flow_stretch : hint_range(1.0, 6.0) = 2.6;

// 0 = nappe horizontale, 1 = CHUTE verticale.
//
// Le même shader sert aux deux parce que c'est la même matière ; seule change
// la coordonnée le long de laquelle elle s'écoule. Sur une chute, projeter en
// XZ comme sur une nappe donnerait des bandes horizontales figées : le plan
// vertical n'a presque pas d'étendue en XZ, donc le motif ne varierait pas sur
// la hauteur — exactement là où l'œil cherche le mouvement.
uniform int flow_plane : hint_range(0, 1) = 0;
uniform float emission_strength : hint_range(0.0, 12.0) = 5.5;

float hash21(vec2 p) {
	p = fract(p * vec2(127.1, 311.7));
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
		p *= 2.11;
		amp *= 0.5;
	}
	return sum;
}

void fragment() {
	// Projection MONDE et non UV : la nappe est bâtie quad par quad, ses UV
	// sont donc discontinus d'un quad à l'autre et le motif se briserait à
	// chaque maille.
	vec3 wpos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec2 world = wpos.xz;

	// Repère aligné sur le courant : X le long de l'écoulement, Y en travers.
	// C'est ce qui permet d'étirer les croûtes dans le bon sens quel que soit
	// l'azimut de la rivière — sans ça, l'étirement serait figé sur l'axe X du
	// monde et se verrait faux dès que la coulée tourne.
	vec2 dir = normalize(flow_direction);
	vec2 side = vec2(-dir.y, dir.x);
	vec2 along = vec2(dot(world, dir), dot(world, side));
	if (flow_plane == 1) {
		// Sur une chute, l'écoulement est la VERTICALE, descendante. La
		// coordonnée transversale reste la largeur de la nappe.
		along = vec2(-wpos.y, dot(world, side));
	}

	vec2 p = along * crust_scale * vec2(1.0 / flow_stretch, 1.0);
	// Décalage À CONTRE-COURANT : la matière avance donc vers l'aval.
	p.x -= TIME * current_speed * crust_scale;
	float t = TIME * flow_speed;

	// 1. Les plaques de croûte. Deux dérives contraires : elles se déforment
	//    l'une l'autre, ce qu'un simple défilement ne ferait jamais.
	float plates = fbm(p + vec2(t, -t * 0.6));
	float warp = fbm(p * 1.9 - vec2(t * 0.4, t * 0.9));
	plates = fbm(p + vec2(warp * 0.6, -warp * 0.4) + vec2(t * 0.3, 0.0));

	// 2. Les fissures : la ligne de crête entre deux plaques. C'est là que
	//    la lave affleure.
	float ridge = abs(plates - 0.5);
	float crack = 1.0 - smoothstep(0.0, 0.13, ridge);
	float core = 1.0 - smoothstep(0.0, 0.045, ridge);

	// 3. La respiration du bassin. Très lente : on la sent, on ne la voit pas.
	float breath = 0.85 + 0.15 * sin(TIME * 0.22 + world.x * 0.01);

	vec3 col = crust_color;
	col = mix(col, hot_color, crack);
	col = mix(col, core_color, core * 0.75);

	ALBEDO = col;
	EMISSION = col * emission_strength * breath * (0.25 + crack * 0.95);
}

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
	vec2 world = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xz;
	vec2 p = world * crust_scale;
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

shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

// Roche de caverne, projetée en TRI-PLANAIRE et générée procéduralement.
//
// POURQUOI TRI-PLANAIRE
// Le sol est un champ de hauteurs : ses UV sont planaires par construction. Sur
// les pentes — c'est-à-dire partout où le relief est intéressant — une texture
// en UV planaire s'étire proportionnellement à l'inclinaison. Les parois du bol
// d'arène (jusqu'à 44°) seraient les plus visiblement fausses. La projection
// tri-planaire échantillonne selon les trois axes du monde et mélange d'après
// la normale : aucun étirement, et aucune couture puisqu'il n'y a pas d'atlas.
//
// POURQUOI PROCÉDURAL PLUTÔT QU'UNE TEXTURE
// Le terrain est la plus grande surface du niveau. Une texture qui la couvrirait
// sans répétition visible coûterait cher en VRAM et en dépôt ; une petite,
// répétée, se lirait comme un damier sur 93 × 54 m. Le bruit procédural n'a ni
// coût mémoire, ni couture, ni période visible — et il suit gratuitement toute
// modification de la topographie, ce qui compte avec une review créative
// encore à venir.
//
// Palette : art bible §3, inflexion glaciaire (froid, très désaturé).

group_uniforms Couleur;
// Roche profonde (#0a0e15) : le fond des creux et des cavités.
uniform vec3 deep_color : source_color = vec3(0.039, 0.055, 0.082);
// Roche (#1e2b3e → #3a4a60) : la valeur dominante des parois.
uniform vec3 rock_color : source_color = vec3(0.118, 0.169, 0.243);
uniform vec3 rock_highlight : source_color = vec3(0.227, 0.290, 0.376);
// Glace/givre pâle qui s'accumule sur les surfaces horizontales.
uniform vec3 frost_color : source_color = vec3(0.663, 0.741, 0.812);

group_uniforms Relief;
// Échelle du grain principal, en mètres. Grand = larges plaques de roche.
uniform float macro_scale : hint_range(0.02, 1.0) = 0.09;
// Grain fin, celui qu'on lit à hauteur d'homme.
uniform float detail_scale : hint_range(0.1, 4.0) = 0.85;
uniform float detail_strength : hint_range(0.0, 1.0) = 0.45;
// Netteté du mélange tri-planaire. Haut = transitions franches entre les axes.
uniform float blend_sharpness : hint_range(1.0, 16.0) = 5.0;

group_uniforms Givre;
// Au-delà de cette pente (produit scalaire avec la verticale), plus de givre :
// le givre tient sur le plat, pas sur les parois.
uniform float frost_slope_threshold : hint_range(0.0, 1.0) = 0.72;
uniform float frost_amount : hint_range(0.0, 1.0) = 0.55;

group_uniforms Surface;
uniform float rock_roughness : hint_range(0.0, 1.0) = 0.92;
uniform float frost_roughness : hint_range(0.0, 1.0) = 0.55;

group_uniforms Diagnostic;
// 0 = rendu normal. Les autres modes rendent une grandeur brute EN NON-ECLAIRE,
// pour distinguer un probleme de materiau d'un probleme d'eclairage :
//   1 = albedo seul   2 = normale monde   3 = `value` (le bruit)   4 = masque de givre
uniform int debug_mode : hint_range(0, 4) = 0;

varying vec3 world_position;
varying vec3 world_normal;


// Bruit de valeur : hachage + interpolation trilinéaire. Suffisant et bon
// marché pour du grain de roche — on ne cherche pas un bruit parfait, on
// cherche à casser l'uniformité.
float hash13(vec3 p) {
	p = fract(p * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

float value_noise(vec3 p) {
	vec3 i = floor(p);
	vec3 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float n000 = hash13(i);
	float n100 = hash13(i + vec3(1.0, 0.0, 0.0));
	float n010 = hash13(i + vec3(0.0, 1.0, 0.0));
	float n110 = hash13(i + vec3(1.0, 1.0, 0.0));
	float n001 = hash13(i + vec3(0.0, 0.0, 1.0));
	float n101 = hash13(i + vec3(1.0, 0.0, 1.0));
	float n011 = hash13(i + vec3(0.0, 1.0, 1.0));
	float n111 = hash13(i + vec3(1.0, 1.0, 1.0));
	return mix(
		mix(mix(n000, n100, f.x), mix(n010, n110, f.x), f.y),
		mix(mix(n001, n101, f.x), mix(n011, n111, f.x), f.y),
		f.z);
}

// Trois octaves : assez pour que l'œil ne trouve pas de motif, assez peu pour
// rester gratuit sur 4 viewports.
float fbm(vec3 p) {
	return value_noise(p) * 0.5
		+ value_noise(p * 2.03) * 0.3
		+ value_noise(p * 4.11) * 0.2;
}


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	// Poids tri-planaires : chaque axe contribue selon l'orientation de la
	// normale, élevée à `blend_sharpness` pour resserrer les transitions.
	vec3 blend = pow(abs(world_normal), vec3(blend_sharpness));
	blend /= max(blend.x + blend.y + blend.z, 0.0001);

	// Le bruit est évalué en coordonnées MONDE, donc invariant par rotation ou
	// déplacement du mesh : deux morceaux de roche voisins ne se contredisent
	// jamais à leur jonction.
	vec3 macro_p = world_position * macro_scale;
	float macro = fbm(macro_p);

	vec3 detail_p = world_position * detail_scale;
	float detail = fbm(detail_p);

	// Le mélange tri-planaire s'applique au grain fin, qui est la composante
	// directionnelle : projeté selon chaque axe puis pondéré.
	float detail_x = fbm(vec3(detail_p.y, detail_p.z, 0.0));
	float detail_y = fbm(vec3(detail_p.x, detail_p.z, 7.3));
	float detail_z = fbm(vec3(detail_p.x, detail_p.y, 3.1));
	float detail_tri = detail_x * blend.x + detail_y * blend.y + detail_z * blend.z;
	detail = mix(detail, detail_tri, 0.7);

	// Valeur de base : des creux sombres aux arêtes plus claires.
	float value = clamp(macro * 0.7 + detail * detail_strength, 0.0, 1.0);
	vec3 albedo = mix(deep_color, rock_color, smoothstep(0.15, 0.55, value));
	albedo = mix(albedo, rock_highlight, smoothstep(0.6, 0.95, value));

	// Givre : uniquement sur les surfaces tournées vers le haut, et modulé par
	// le bruit pour qu'il s'accumule par plaques plutôt qu'en couche uniforme.
	float upward = clamp(world_normal.y, 0.0, 1.0);
	float frost_mask = smoothstep(frost_slope_threshold, 1.0, upward)
		* smoothstep(0.35, 0.75, macro) * frost_amount;
	albedo = mix(albedo, frost_color, frost_mask);

	// GDShader INTERDIT `return` dans une fonction de traitement (fragment,
	// vertex, light) : la compilation echoue silencieusement pour le rendu et
	// le shader n'expose plus AUCUN uniforme. Les materiaux se resauvegardent
	// alors vides et tournent sur les defauts du shader -- panne difficile a
	// voir, puisque rien ne casse visiblement. D'ou un if/else, jamais un
	// early-return.
	if (debug_mode != 0) {
		vec3 dbg = albedo;
		if (debug_mode == 2) { dbg = world_normal * 0.5 + 0.5; }
		if (debug_mode == 3) { dbg = vec3(value); }
		if (debug_mode == 4) { dbg = vec3(frost_mask); }
		ALBEDO = vec3(0.0);
		EMISSION = dbg;
		ROUGHNESS = 1.0;
		METALLIC = 0.0;
	} else {
		ALBEDO = albedo;
		ROUGHNESS = mix(rock_roughness, frost_roughness, frost_mask);
		METALLIC = 0.0;
		// Micro-relief : le bruit fin perturbe la normale, ce qui donne du
		// grain sans consommer une seule texture.
		NORMAL_MAP = normalize(vec3(
			(detail - 0.5) * 0.6,
			(detail_tri - 0.5) * 0.6,
			1.0)) * 0.5 + 0.5;
		NORMAL_MAP_DEPTH = 0.7;
	}
}

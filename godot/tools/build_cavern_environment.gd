extends SceneTree

## Écrit l'environnement PROVISOIRE du blockout de la caverne. Lancer via :
##   godot --headless --path godot --script tools/build_cavern_environment.gd
##
## Objectif limité : rendre le blockout VISIBLE pour le playtest E2. L'éclairage
## réel — glows muraux comme vraies sources, puits de jour volumétriques, brume
## branchée sur la mécanique de visibilité limitée — est le travail d'E3 (#18,
## #19), qui remplacera ce fichier.
##
## Palette : art bible §3, inflexion glaciaire (froid, très désaturé).

const OUTPUT_PATH := "res://data/levels/level01_cavern_environment.tres"


func _init() -> void:
	var env := Environment.new()

	# CIEL, et non une couleur unie. Les puits de voûte sont des TROUS : ce
	# qu'on voit à travers doit être le ciel, sinon le trou se confond avec la
	# roche et le landmark principal du niveau devient invisible (constaté en
	# capture : le puits P1 ne se lisait pas du tout).
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.55, 0.68, 0.82)
	sky_material.sky_horizon_color = Color(0.72, 0.80, 0.88)
	sky_material.ground_bottom_color = Color(0.50, 0.62, 0.76)
	sky_material.ground_horizon_color = Color(0.72, 0.80, 0.88)
	sky_material.sun_angle_max = 5.0
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Le ciel n'éclaire PAS la caverne : on est sous terre, la lumière entre par
	# deux trous, pas par le plafond entier. D'où ambient_light_sky_contribution
	# à 0 plus bas.
	env.background_energy_multiplier = 1.0

	# Lumière ambiante froide, faible : assez pour lire le relief au playtest,
	# assez sombre pour que les glows d'E3 aient encore quelque chose à faire.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.32, 0.42, 0.58)
	# 0,30 et non 0,55 : la passe precedente avait surcorrige. Une caverne doit
	# etre SOMBRE -- c'est ce qui donne leur valeur aux cristaux. Trop d'ambiante
	# ecrase tout en gris-bleu moyen et fait disparaitre le contraste.
	env.ambient_light_energy = 0.55
	# PIÈGE : `ambient_light_sky_contribution` vaut 1.0 par défaut, c'est-à-dire
	# « 100 % de l'ambiante vient du ciel ». Avec un fond de couleur unie il n'y
	# a PAS de ciel : la couleur ambiante ci-dessus est alors intégralement
	# ignorée et la scène rend en NOIR. Il faut le mettre à 0 explicitement.
	env.ambient_light_sky_contribution = 0.0

	# Brume : c'est elle qui portera la mécanique signature (visibilité
	# limitée). Réglée large ici — on veut voir la caverne au playtest, pas
	# encore la jouer. Les portées par zone de la spec (10 m en forêt, 35 m au
	# lac) arrivent en E3.
	env.fog_enabled = true
	# Brouillard SOMBRE. Il doit enfouir les lointains dans le noir, pas les
	# eclaircir : un brouillard clair sur un fond de ciel clair delave toute
	# l'image et annule la profondeur qu'il est cense creer.
	env.fog_light_color = Color(0.20, 0.27, 0.38)
	env.fog_light_energy = 0.25
	env.fog_density = 0.006
	env.fog_sky_affect = 0.0
	# 0 et non 0,3 : la perspective aerienne melange la couleur du CIEL dans le
	# brouillard. Le ciel est clair (il doit l'etre, on le voit par les trous),
	# donc chaque metre de brouillard tirait l'image vers le blanc.
	env.fog_aerial_perspective = 0.0

	# Brouillard VOLUMÉTRIQUE : c'est lui qui matérialise les puits de jour en
	# colonnes de lumière (spec §6). Sans lui, une lumière traversant un trou de
	# voûte n'éclaire que le sol, sans le faisceau qui fait l'image.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.52, 0.66, 0.82)
	env.volumetric_fog_emission = Color(0.04, 0.06, 0.09)
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_length = 90.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.2

	var error: int = ResourceSaver.save(env, OUTPUT_PATH)
	if error != OK:
		push_error("Échec de l'écriture de %s (code %d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("[env] écrit : %s" % OUTPUT_PATH)
	quit(0)

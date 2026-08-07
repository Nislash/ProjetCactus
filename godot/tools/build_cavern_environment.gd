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

	# Pas de ciel : on est sous terre. Le fond est la roche profonde de la
	# palette (#0a0e15), ce qui évite un halo bleu incohérent dans les trous
	# de voûte tant que les puits de jour ne sont pas montés en E3.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.039, 0.055, 0.082)

	# Lumière ambiante froide, faible : assez pour lire le relief au playtest,
	# assez sombre pour que les glows d'E3 aient encore quelque chose à faire.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.45, 0.60)
	env.ambient_light_energy = 0.55

	# Brume : c'est elle qui portera la mécanique signature (visibilité
	# limitée). Réglée large ici — on veut voir la caverne au playtest, pas
	# encore la jouer. Les portées par zone de la spec (10 m en forêt, 35 m au
	# lac) arrivent en E3.
	env.fog_enabled = true
	env.fog_light_color = Color(0.42, 0.52, 0.66)
	env.fog_light_energy = 0.7
	env.fog_density = 0.012
	env.fog_sky_affect = 0.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_white = 1.2

	var error: int = ResourceSaver.save(env, OUTPUT_PATH)
	if error != OK:
		push_error("Échec de l'écriture de %s (code %d)" % [OUTPUT_PATH, error])
		quit(1)
		return
	print("[env] écrit : %s" % OUTPUT_PATH)
	quit(0)

extends SceneTree

## Écrit `res://data/levels/level02_forge_environment.tres`.
##   godot --headless --path godot --script tools/build_forge_environment.gd
##
## ## Le principe : la lumière vient du BAS
##
## Au niveau 1, deux puits de jour percent la voûte et posent des colonnes de
## lumière ; l'ambiante est froide et faible, et ce sont les cristaux qui
## sculptent. Ici c'est l'inverse : **la seule source est le lac de lave**, au
## fond du gouffre. Tout ce qui est haut est sombre, tout ce qui est bas est
## incandescent — et un joueur sait donc où il est rien qu'à la luminosité de
## ce qu'il voit.
##
## Conséquences, toutes voulues :
## - pas de ciel : on est trop profond, un fond de ciel trahirait un extérieur
## - ambiante **chaude et très basse** : elle ne fait que déboucher les noirs
## - brume dense et sombre : la chaleur brouille l'air, et la profondeur du
##   gouffre doit se deviner plutôt que se mesurer

const OUTPUT_PATH := "res://data/levels/level02_forge_environment.tres"


func _init() -> void:
	var env := Environment.new()

	# PAS DE CIEL. Les cheminées de la voûte laissent SORTIR la lumière de la
	# lave, elles ne laissent rien entrer : ce qu'on voit à travers doit être
	# du noir, pas un dehors.
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.020, 0.014, 0.016)
	env.background_energy_multiplier = 1.0

	# Ambiante chaude, très basse. Elle ne modèle rien — elle empêche
	# seulement les faces détournées de la lave de tomber au noir absolu.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.35, 0.18, 0.12)
	env.ambient_light_energy = 0.30
	# Piège déjà payé au niveau 1 : sans ciel, cette contribution à 1 par
	# défaut annule purement et simplement la couleur ambiante ci-dessus.
	env.ambient_light_sky_contribution = 0.0

	# BRUME. Sombre et chaude : elle enfouit les lointains dans la suie. Plus
	# dense qu'au niveau 1 — l'air d'une forge est un obstacle, pas un voile.
	env.fog_enabled = true
	env.fog_light_color = Color(0.145, 0.075, 0.055)
	env.fog_light_energy = 0.35
	env.fog_density = 0.011
	env.fog_sky_affect = 0.0
	env.fog_aerial_perspective = 0.0

	# Brume VOLUMÉTRIQUE : c'est elle qui matérialise la chaleur montant du
	# bassin, et qui donne aux cheminées leurs colonnes de fumée.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.020
	env.volumetric_fog_albedo = Color(0.35, 0.24, 0.20)
	# Une émission propre, faible : l'air lui-même rougeoie près de la lave.
	env.volumetric_fog_emission = Color(0.14, 0.045, 0.020)
	env.volumetric_fog_emission_energy = 0.6
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_length = 70.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Blanc plus haut qu'au niveau 1 : la lave dépasse largement 1,0 et on ne
	# veut pas qu'elle s'écrase en aplat blanc.
	env.tonemap_white = 2.4

	# GLOW. Encore plus décisif qu'au niveau 1 : ici tout l'éclairage vient
	# d'une surface émissive, et sans halo elle resterait un autocollant
	# orange posé au fond d'un trou.
	env.glow_enabled = true
	env.glow_hdr_threshold = 0.95
	env.glow_hdr_scale = 2.0
	env.glow_intensity = 0.75
	env.glow_bloom = 0.12
	env.glow_strength = 1.15
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	# Halo très large : la chaleur ne fait pas de contour net.
	env.set_glow_level(0, 0.0)
	env.set_glow_level(1, 0.2)
	env.set_glow_level(2, 0.8)
	env.set_glow_level(3, 1.0)
	env.set_glow_level(4, 1.0)
	env.set_glow_level(5, 0.6)
	env.set_glow_level(6, 0.25)

	# SSAO : indispensable quand la lumière est rasante et vient d'en bas —
	# sans occlusion de contact, les paliers se confondent avec leurs parois.
	env.ssao_enabled = true
	env.ssao_radius = 1.4
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.5
	env.ssao_light_affect = 0.1

	# Saturation POUSSÉE, à l'inverse du niveau 1 qui désature. Le glaciaire
	# est un monde délavé ; la forge est un monde saturé, et c'est la
	# différence qu'on doit sentir en passant de l'un à l'autre.
	env.adjustment_enabled = true
	env.adjustment_brightness = 1.0
	env.adjustment_contrast = 1.12
	env.adjustment_saturation = 1.18

	if ResourceSaver.save(env, OUTPUT_PATH) != OK:
		push_error("Échec de l'écriture de %s" % OUTPUT_PATH)
		quit(1)
		return
	print("[forge] environnement écrit : %s" % OUTPUT_PATH)
	quit(0)

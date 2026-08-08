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

	# UN CIEL, et une lune rouge dedans.
	#
	# La Forge n'est plus une cavité : c'est un cirque ouvert. Le ciel est donc
	# la moitié de l'image, et il doit raconter quelque chose — un rouge très
	# sombre en haut, qui s'éclaircit vers l'horizon comme si l'incendie était
	# partout autour et pas seulement dans le trou.
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = Color(0.055, 0.020, 0.030)
	sky_material.sky_horizon_color = Color(0.235, 0.075, 0.075)
	sky_material.ground_bottom_color = Color(0.035, 0.016, 0.020)
	sky_material.ground_horizon_color = Color(0.196, 0.063, 0.063)
	# LA LUNE. Le disque du soleil procédural sert de lune : large, rouge,
	# aux bords flous — elle doit se lire comme un astre, pas comme une lampe.
	sky_material.sun_angle_max = 9.0
	sky_material.sun_curve = 0.22
	var sky := Sky.new()
	sky.sky_material = sky_material
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	# Le ciel n'éclaire presque pas : la lumière vient de la lave et de la lune
	# elle-même, deux sources ponctuelles. Un ciel qui éclairerait comme un
	# dôme aplatirait tout le relief du cirque.
	env.background_energy_multiplier = 1.5

	# Ambiante chaude, très basse. Elle ne modèle rien — elle empêche
	# seulement les faces détournées de la lave de tomber au noir absolu.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.22, 0.20)
	env.ambient_light_energy = 0.95
	# Un peu de ciel dans l'ambiante, maintenant qu'il y en a un — mais peu :
	# la nuit reste noire, c'est la lune qui découpe.
	env.ambient_light_sky_contribution = 0.40

	# BRUME. Chaude, et **six fois moins dense** qu'au premier réglage.
	#
	# Elle avalait tout : dans un cirque de 156 m, une densité de 0,011
	# éteignait la paroi d'en face et le château avec. Un premier correctif l'a
	# divisée par deux — encore trop, constaté en jeu.
	#
	# La leçon est de portée : un niveau à ciel ouvert n'a pas les mêmes
	# besoins qu'une caverne. Au niveau 1 la brume CACHE, c'est la mécanique
	# signature et sa densité est le sujet. Ici elle ne doit rien cacher du
	# tout — juste teinter les lointains pour qu'on sente la distance. La bonne
	# valeur est celle qu'on ne remarque pas.
	# Elle affecte MAINTENANT le ciel : sans ça, un horizon net trahirait que
	# le cirque est une boîte.
	env.fog_enabled = true
	env.fog_light_color = Color(0.235, 0.125, 0.095)
	env.fog_light_energy = 0.75
	env.fog_density = 0.0018
	env.fog_sky_affect = 0.15
	env.fog_aerial_perspective = 0.0

	# Brume VOLUMÉTRIQUE : c'est elle qui matérialise la chaleur montant du
	# bassin, et qui donne aux cheminées leurs colonnes de fumée.
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.004
	env.volumetric_fog_albedo = Color(0.35, 0.24, 0.20)
	# Une émission propre, faible : l'air lui-même rougeoie près de la lave.
	env.volumetric_fog_emission = Color(0.14, 0.045, 0.020)
	env.volumetric_fog_emission_energy = 1.1
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_length = 48.0

	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	# Blanc plus haut qu'au niveau 1 : la lave dépasse largement 1,0 et on ne
	# veut pas qu'elle s'écrase en aplat blanc.
	env.tonemap_white = 3.2

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
	env.adjustment_brightness = 1.15
	env.adjustment_contrast = 1.06
	env.adjustment_saturation = 1.18

	if ResourceSaver.save(env, OUTPUT_PATH) != OK:
		push_error("Échec de l'écriture de %s" % OUTPUT_PATH)
		quit(1)
		return
	print("[forge] environnement écrit : %s" % OUTPUT_PATH)
	quit(0)

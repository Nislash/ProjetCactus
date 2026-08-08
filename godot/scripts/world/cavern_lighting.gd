## Éclairage de la caverne — les deux sources diégétiques du plan (E3 #18).
##
## 1. LES PUITS DE JOUR — une lumière descend par chaque trou de voûte. Couplée
##    au brouillard volumétrique de l'environnement, elle produit la colonne de
##    lumière qui fait du puits P1 le landmark du niveau.
##
## 2. LES GLOWS DE CRISTAL — les formations cristallines ne sont pas décoratives :
##    ce sont les VRAIES sources qui guident dans les zones sombres. C'est la
##    colonne vertébrale de la mécanique « visibilité limitée » : le mat s'éteint
##    dans la brume, les émissifs portent loin, donc les cristaux SONT la
##    boussole (topographie §5).
##
## Les positions ne sont pas écrites ici : elles sont LUES dans la scène (les
## puits depuis [CavernTerrainData], les cristaux depuis les marqueurs de
## gameplay). Une correction de topographie déplace donc les lumières avec elle,
## sans édition manuelle — ce qui compte avec une review créative à venir.

class_name CavernLighting
extends Node3D

## Terrain de référence, pour connaître la position des puits de ciel.
@export_file("*.tres") var terrain_path: String = "res://data/levels/level01_cavern_terrain.tres"

## Sous-scènes de cristaux instanciées aux marqueurs de puzzle et de landmark.
@export var crystal_scene: PackedScene = preload("res://scenes/props/crystal_wall_a.tscn")
@export var spire_scene: PackedScene = preload("res://scenes/props/crystal_spire_b.tscn")
@export var monolith_scene: PackedScene = preload("res://scenes/props/crystal_monolith_landmark.tscn")

func _ready() -> void:
	var terrain: CavernTerrainData = load(terrain_path) as CavernTerrainData
	if terrain == null:
		push_error("CavernLighting : terrain introuvable (%s)." % terrain_path)
		return
	# Le terrain se construit dans son propre `_ready` : on attend une frame
	# pour que les marqueurs soient bien dans l'arbre.
	await get_tree().process_frame

	_build_fill_light()
	_build_sky_shafts(terrain)
	_build_crystal_glows()


# ---------------------------------------------------------------------------
# Source 0 — l'appoint directionnel
# ---------------------------------------------------------------------------

## Une lumière d'appoint très faible, venue d'en haut.
##
## Une caverne n'a pas de soleil, et la tentation est de n'utiliser que de
## l'ambiante. Mais une ambiante est UNIFORME : elle éclaire toutes les normales
## pareil, donc elle ne sculpte RIEN. Sans composante directionnelle, le relief
## d'un terrain vallonné disparaît et la roche se lit comme un aplat — c'est
## exactement ce que les premières captures montraient.
##
## Elle reste assez faible pour que les cristaux gardent le rôle de vraies
## sources, et ne porte pas d'ombres (budget art bible §5 : ombres réservées
## aux puits de jour).
func _build_fill_light() -> void:
	var fill := DirectionalLight3D.new()
	fill.name = "FillLight"
	# Presque à la verticale, légèrement inclinée : la lumière d'une caverne
	# vient du haut, mais un axe parfaitement vertical aplatirait les surfaces
	# horizontales, qui sont justement le sol qu'on veut lire.
	fill.rotation_degrees = Vector3(-62.0, 28.0, 0.0)
	fill.light_color = Color(0.52, 0.64, 0.84)
	fill.light_energy = 0.42
	fill.light_specular = 0.15
	fill.shadow_enabled = false
	# N'alimente pas le brouillard volumétrique : sinon toute la caverne baigne
	# dans une brume lumineuse et les faisceaux des puits ne se détachent plus.
	fill.light_volumetric_fog_energy = 0.0
	add_child(fill)


# ---------------------------------------------------------------------------
# Source 1 — les puits de jour
# ---------------------------------------------------------------------------

func _build_sky_shafts(terrain: CavernTerrainData) -> void:
	for well in terrain.sky_wells:
		var ground: float = CavernTerrainBuilder.sample_point(
			terrain.floor_field, well.center, _floor_noise(terrain))

		var light := SpotLight3D.new()
		light.name = "SkyShaft_%s" % well.label
		# Placée SOUS la voûte plutôt qu'au-dessus : une lumière au-dessus du
		# maillage de voûte serait bloquée par sa propre collision de plafond.
		light.position = Vector3(well.center.x, ground + terrain.max_headroom - 0.5, well.center.y)
		light.rotation_degrees = Vector3(-90.0, 0.0, 0.0)

		# Jour d'hiver filtré par la glace : froid, pâle, jamais chaud — le
		# chaud est réservé au danger (art bible §3).
		light.light_color = Color(0.81, 0.89, 0.95)
		light.light_energy = 9.0
		light.light_volumetric_fog_energy = 3.5
		# L'ouverture du cône suit le DIAMÈTRE du puits : un puits large fait une
		# flaque large, sans qu'on ait à régler quoi que ce soit à la main.
		light.spot_range = terrain.max_headroom + 6.0
		light.spot_angle = clampf(rad_to_deg(atan(well.diameter * 0.5 / 6.0)), 12.0, 45.0)
		light.spot_attenuation = 0.6
		# Ombres portées : réservées aux sources majeures (budget art bible §5).
		# Les deux puits en font partie — ce sont eux qui sculptent le volume.
		light.shadow_enabled = true
		add_child(light)


# ---------------------------------------------------------------------------
# Source 2 — les glows de cristal
# ---------------------------------------------------------------------------

## Instancie un cristal à chaque marqueur de puzzle et de landmark, et lui donne
## une lumière. La lumière vit AVEC le cristal : impossible d'avoir un cristal
## qui n'éclaire pas, ou une lueur sans source visible.
func _build_crystal_glows() -> void:
	var world: Node = get_parent()

	for entry in [
		{"path": "PuzzleCrystals/K1_Nid", "scene": spire_scene, "energy": 3.2, "range": 16.0},
		{"path": "PuzzleCrystals/K2_Lanterne", "scene": spire_scene, "energy": 3.2, "range": 16.0},
		{"path": "PuzzleCrystals/K3_Cuvette", "scene": crystal_scene, "energy": 2.4, "range": 13.0},
		{"path": "Landmarks/Monolith", "scene": monolith_scene, "energy": 5.0, "range": 34.0},
	]:
		var marker: Node3D = world.get_node_or_null(entry.path) as Node3D
		if marker == null:
			push_warning("CavernLighting : marqueur « %s » introuvable." % entry.path)
			continue

		var prop: Node3D = (entry.scene as PackedScene).instantiate() as Node3D
		marker.add_child(prop)

		var light := OmniLight3D.new()
		light.name = "Glow"
		# Au CŒUR du cristal, pas à sa base : la lueur doit sembler venir de la
		# pierre elle-même.
		light.position = Vector3(0.0, 1.2, 0.0)
		light.light_color = Color(0.40, 0.85, 1.0)
		light.light_energy = entry.energy
		light.omni_range = entry.range
		light.light_volumetric_fog_energy = 2.0
		# Pas d'ombres : le budget les réserve aux puits de jour. Un cristal qui
		# porte à 16 m sans ombre coûte une fraction de ce qu'il coûterait avec.
		light.shadow_enabled = false
		marker.add_child(light)


func _floor_noise(terrain: CavernTerrainData) -> FastNoiseLite:
	if terrain.floor_field.noise_amplitude <= 0.0:
		return null
	var noise := FastNoiseLite.new()
	noise.seed = terrain.floor_field.noise_seed
	noise.frequency = 1.0 / terrain.floor_field.noise_scale
	return noise

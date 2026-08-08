class_name ForgeLighting
extends Node3D

## L'éclairage de la Forge : **deux sources qui s'opposent**.
##
## **La lave, par en dessous.** Au fond du gouffre, chaude, mouvante. Elle
## éclaire les visages par en dessous et noie les surplombs — plus on descend,
## plus il fait clair. C'est elle qui dit l'altitude sans minimap.
##
## **La lune rouge, par au-dessus.** Rasante, froide dans son rouge, immobile.
## Elle ne fait presque pas de lumière : elle fait des OMBRES. C'est elle qui
## découpe la silhouette du château sur le ciel, et c'est son rayon qu'il
## faudra détourner pour ouvrir la porte.
##
## Les deux ne se mélangent jamais. Une surface est soit orange et vivante,
## soit rouge sombre et figée, et l'œil sait immédiatement laquelle des deux
## la touche. C'est ce qui rend le puzzle des miroirs lisible : dans un monde
## entièrement chaud, la lumière lunaire est la seule chose qui détonne.
##
## ## Ce qui remplace la couleur du danger
##
## Au niveau 1, l'ambre `#f2b45c` veut dire « esquive maintenant » et n'est
## utilisé que là. Ici la salle entière est ambre : la couleur ne peut plus
## rien signaler. C'est donc le **mouvement** qui alerte — la lave qui monte,
## les braises qui s'emballent. Les telegraphs du boss devront battre, pas
## rougir.

@export_file("*.tres") var terrain_data_path: String = "res://data/levels/level02_forge_terrain.tres"

## Nombre de lampes réparties sur le lac. Une seule au centre laisserait les
## bords du bassin dans l'ombre alors que c'est là qu'on se bat.
@export var lava_light_count: int = 8

## Portée des lampes du lac, en mètres.
@export var lava_light_range: float = 96.0
@export var lava_light_energy: float = 6.5

## La lueur d'ensemble qui remplit le cirque.
@export var fill_energy: float = 4.5
@export var fill_range: float = 200.0

## LA LUNE. Rouge — elle découpe, et maintenant elle éclaire aussi un peu.
@export var moon_color: Color = Color(0.88, 0.38, 0.34)
@export var moon_energy: float = 1.9
## Rasante : 20° au-dessus de l'horizon. Au zénith elle éclairerait le fond du
## gouffre et volerait son rôle à la lave.
@export var moon_direction_degrees: Vector3 = Vector3(-20.0, 35.0, 0.0)

const LAVA_CORE := Color(1.000, 0.545, 0.243)
const LAVA_DEEP := Color(1.000, 0.322, 0.114)

var _terrain: CavernTerrainData
var _pulses: Array[OmniLight3D] = []
var _moon: DirectionalLight3D = null
var _time: float = 0.0


func _ready() -> void:
	_terrain = load(terrain_data_path) as CavernTerrainData
	if _terrain == null:
		push_warning("ForgeLighting : terrain introuvable — aucune lumière posée.")
		return
	# Une frame : le terrain se construit d'abord, on s'accroche ensuite.
	await get_tree().process_frame
	_light_the_lava()
	_light_the_glow()
	_light_the_moon()


## La couronne de lampes sur le bassin. Réparties sur un anneau et non au
## centre : c'est le BORD du lac qui doit éclairer, puisque c'est le bord
## qu'on longe.
func _light_the_lava() -> void:
	var lava: CavernLake = _terrain.lake
	if lava == null:
		return
	for i in lava_light_count:
		var a: float = TAU * float(i) / float(lava_light_count)
		var at := Vector2(
			lava.center.x + cos(a) * lava.radii.x * 0.62,
			lava.center.y + sin(a) * lava.radii.y * 0.62)
		var light := OmniLight3D.new()
		light.name = "Lave_%d" % i
		# Alternance des deux oranges : une couronne monochrome se lirait
		# comme un néon, deux teintes donnent de la matière.
		light.light_color = LAVA_CORE if i % 2 == 0 else LAVA_DEEP
		light.light_energy = lava_light_energy
		light.omni_range = lava_light_range
		# Pas d'ombres : six sources ombrées coûteraient cher en 4-split, et
		# une lumière de lave est diffuse — elle ne découpe pas d'ombres nettes.
		light.shadow_enabled = false
		add_child(light)
		# Juste au-dessus de la nappe : posée dedans, la moitié de sa portée
		# serait perdue sous la surface.
		light.global_position = Vector3(at.x, lava.surface_altitude + 1.2, at.y)
		_pulses.append(light)


## LA LUEUR DU GOUFFRE. Une seule très grande lampe au-dessus du bassin, de
## portée démesurée et d'énergie modérée.
##
## Elle ne remplace pas la couronne — celle-ci donne le modelé des bords, où
## l'on se bat. Elle fait autre chose : elle **remplit** le cirque, pour que
## les falaises d'en face et le château cessent d'être des masses noires. Sans
## elle, tout ce qui n'était pas au bord du lac disparaissait.
func _light_the_glow() -> void:
	var lava: CavernLake = _terrain.lake
	if lava == null:
		return
	var glow := OmniLight3D.new()
	# Nommée « Lave… » à dessein : elle appartient au groupe de sources que le
	# test vérifie comme étant SOUS la crête. Une lampe de remplissage qui
	# échapperait à ce contrôle pourrait dériver vers le haut sans que rien ne
	# le dise — et c'est exactement ce qui s'est passé au premier jet.
	glow.name = "Lave_Lueur"
	glow.light_color = LAVA_CORE
	glow.light_energy = fill_energy
	glow.omni_range = fill_range
	glow.shadow_enabled = false
	# JUSTE au-dessus de la nappe, comme la couronne. Elle avait d'abord été
	# posée 26 m plus haut pour mieux porter — mais elle éclairait alors PAR LE
	# HAUT, ce qui détruit le renversement dont vit le biome. C'est sa portée
	# qui doit faire le travail, pas son altitude.
	add_child(glow)
	glow.global_position = Vector3(lava.center.x, lava.surface_altitude + 3.0, lava.center.y)


## LA LUNE. Une seule directionnelle, très rasante, avec des ombres.
##
## Elle est la seule source ombrée du niveau — les six lampes de la lave n'en
## portent pas, pour le coût. C'est donc elle qui donne au cirque son relief
## et au château sa silhouette : sans ombres, une forteresse noire sur un ciel
## noir n'est qu'un trou dans l'image.
##
## Rasante et non zénithale : une lune au zénith éclairerait le fond du
## gouffre et volerait son rôle à la lave. Basse, elle n'atteint que les
## crêtes — et laisse le fond à la lave, ce qui sépare nettement les deux
## territoires lumineux.
func _light_the_moon() -> void:
	var moon := DirectionalLight3D.new()
	moon.name = "LuneRouge"
	moon.light_color = moon_color
	moon.light_energy = moon_energy
	moon.shadow_enabled = true
	# Biais généreux : les falaises du cirque sont hautes et rasantes, terrain
	# de jeu idéal pour l'acné d'ombre.
	moon.shadow_bias = 0.09
	moon.shadow_normal_bias = 1.6
	moon.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	moon.directional_shadow_max_distance = 180.0
	add_child(moon)
	moon.rotation_degrees = moon_direction_degrees
	_moon = moon


## L'azimut de la lune, utilisé par le puzzle des miroirs pour savoir d'où
## vient le rayon. Une seule source de vérité : si la lune bouge, le puzzle
## suit.
func get_moon_direction() -> Vector3:
	if _moon == null:
		return Vector3(0.0, -0.34, -0.94).normalized()
	return -_moon.global_transform.basis.z


## La respiration du bassin. Chaque lampe pulse à sa propre cadence : en
## phase, l'ensemble clignoterait comme un stroboscope ; décalées, elles
## donnent l'impression d'une matière qui bouge.
func _process(delta: float) -> void:
	_time += delta
	for i in _pulses.size():
		var phase: float = _time * 0.55 + float(i) * 1.37
		_pulses[i].light_energy = lava_light_energy * (0.82 + 0.18 * sin(phase))

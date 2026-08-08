class_name ForgeLighting
extends Node3D

## L'éclairage de la Forge — **par le bas**.
##
## Au niveau 1, deux puits percent la voûte et la lumière tombe ; les glows
## muraux servent de boussole. Ici la seule source est le lac de lave, au fond
## du gouffre, et tout se renverse : les visages sont éclairés par en dessous,
## les surplombs sont noirs, et plus on descend plus il fait clair.
##
## Ce renversement est le biome. Un joueur qui lève les yeux voit du noir ; un
## joueur qui regarde ses pieds voit de l'or. C'est aussi ce qui lui dit où il
## est sans minimap : la luminosité EST l'altitude.
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
@export var lava_light_count: int = 6

## Portée des lampes du lac, en mètres.
@export var lava_light_range: float = 62.0
@export var lava_light_energy: float = 3.2

## Braises qui montent des cheminées : quelques lampes faibles très haut, pour
## que la voûte ne soit pas un plafond noir absolu.
@export var vent_light_energy: float = 0.7

const LAVA_CORE := Color(1.000, 0.545, 0.243)
const LAVA_DEEP := Color(1.000, 0.322, 0.114)

var _terrain: CavernTerrainData
var _pulses: Array[OmniLight3D] = []
var _time: float = 0.0


func _ready() -> void:
	_terrain = load(terrain_data_path) as CavernTerrainData
	if _terrain == null:
		push_warning("ForgeLighting : terrain introuvable — aucune lumière posée.")
		return
	# Une frame : le terrain se construit d'abord, on s'accroche ensuite.
	await get_tree().process_frame
	_light_the_lava()
	_light_the_vents()


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


## Les cheminées. Elles n'éclairent pas la salle — elles évitent seulement que
## la voûte soit un vide noir, et donnent une cible au regard quand on lève la
## tête.
func _light_the_vents() -> void:
	for opening in _terrain.sky_openings:
		var light := OmniLight3D.new()
		light.name = "Event_%s" % opening.label
		light.light_color = LAVA_DEEP
		light.light_energy = vent_light_energy
		light.omni_range = 30.0
		light.shadow_enabled = false
		add_child(light)
		light.global_position = Vector3(
			opening.center.x,
			_terrain.floor_field.base_altitude + _terrain.max_headroom - 2.0,
			opening.center.y)


## La respiration du bassin. Chaque lampe pulse à sa propre cadence : en
## phase, l'ensemble clignoterait comme un stroboscope ; décalées, elles
## donnent l'impression d'une matière qui bouge.
func _process(delta: float) -> void:
	_time += delta
	for i in _pulses.size():
		var phase: float = _time * 0.55 + float(i) * 1.37
		_pulses[i].light_energy = lava_light_energy * (0.82 + 0.18 * sin(phase))

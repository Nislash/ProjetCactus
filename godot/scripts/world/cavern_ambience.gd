class_name CavernAmbience
extends Node3D

## L'ambiance sonore de la caverne.
##
## ## Le principe : chaque son a une source qu'on peut voir
##
## Rien n'est diffusé « de partout » sauf le grondement de fond, qui EST le
## silence de la roche. Le vent sort des puits de voûte, le scintillement
## vient des cristaux, le clapot vient du lac.
##
## Ce n'est pas une coquetterie. La mécanique signature du niveau est la
## **visibilité limitée** : la brume coupe la vue à 10 m dans la forêt. Quand
## on n'y voit rien, l'oreille devient la boussole — mais seulement si les
## sons sont posés là où sont les choses. Une nappe stéréo omniprésente
## n'aurait rien appris au joueur perdu.
##
## ## L'atténuation est réglée pour le split-screen
##
## À quatre, quatre écouteurs se promènent dans le même monde et Godot mixe
## selon l'`AudioListener3D` de chaque viewport. Des portées trop longues
## empileraient les quatre points de vue en une bouillie ; elles sont donc
## courtes et le nombre d'émetteurs est borné.

const DRONE := "res://assets/audio/ambience/cave_drone.tres"
const WIND := "res://assets/audio/ambience/wind_shaft.tres"
const SHIMMER := "res://assets/audio/ambience/crystal_shimmer.tres"
const WATER := "res://assets/audio/ambience/water_lap.tres"

@export_file("*.tres") var terrain_data_path: String = "res://data/levels/level01_cavern_terrain.tres"

## Niveaux en dB. Le grondement est très bas : il doit se sentir, pas
## s'entendre.
@export var drone_db: float = -22.0
@export var wind_db: float = -12.0
@export var shimmer_db: float = -18.0
@export var water_db: float = -15.0

## Portées d'atténuation, en mètres.
@export var wind_range: float = 55.0
@export var shimmer_range: float = 18.0
@export var water_range: float = 40.0

## Plafond d'émetteurs de cristal. Le niveau en compte des dizaines ; les
## faire tous chanter coûterait cher et ne s'entendrait pas mieux.
@export var max_shimmer_sources: int = 8

var _terrain: CavernTerrainData
var _noise: FastNoiseLite
var _sources: Array[Node] = []


func _ready() -> void:
	_terrain = load(terrain_data_path) as CavernTerrainData
	if _terrain == null:
		push_warning("CavernAmbience : terrain introuvable — pas d'ambiance posée.")
		return
	_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)

	# Une frame : les cristaux et les structures du lac sont posés par
	# d'autres nœuds, on attend qu'ils existent pour s'accrocher dessus.
	await get_tree().process_frame

	_place_drone()
	_place_wind()
	_place_shimmer()
	_place_water()


## Le grondement est NON positionnel. Il n'a pas de source parce qu'il est la
## caverne elle-même ; lui donner un point d'origine ferait entendre au joueur
## qu'il s'en éloigne, ce qui n'a aucun sens.
func _place_drone() -> void:
	var stream: AudioStream = load(DRONE) as AudioStream
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.name = "Drone"
	p.stream = stream
	p.volume_db = drone_db
	p.autoplay = true
	add_child(p)
	_sources.append(p)


## Le vent sort des puits de voûte — les seuls endroits par où l'extérieur
## entre. C'est ce qui fait qu'on entend le dehors avant de le voir.
func _place_wind() -> void:
	var stream: AudioStream = load(WIND) as AudioStream
	if stream == null or _terrain.sky_openings.is_empty():
		return
	for opening in _terrain.sky_openings:
		var at: Vector2 = opening.center
		var floor_y: float = CavernTerrainBuilder.sample_point(_terrain.floor_field, at, _noise)
		# Placé HAUT, à l'aplomb du trou : le son doit venir d'au-dessus.
		_emit(stream, Vector3(at.x, floor_y + 12.0, at.y), wind_db, wind_range, "Vent_%s" % opening.label)


## Le scintillement s'accroche aux cristaux déjà posés dans la scène, plutôt
## que d'inventer des positions : un son de cristal sans cristal visible
## mentirait au joueur qui vient le chercher.
func _place_shimmer() -> void:
	var stream: AudioStream = load(SHIMMER) as AudioStream
	if stream == null:
		return
	var crystals: Array = get_tree().get_nodes_in_group(&"crystal_sources")
	var placed: int = 0
	for c in crystals:
		if placed >= max_shimmer_sources:
			break
		var node: Node3D = c as Node3D
		if node == null:
			continue
		_emit(stream, node.global_position + Vector3(0.0, 1.0, 0.0),
			shimmer_db, shimmer_range, "Cristal_%s" % node.name)
		placed += 1


## Le clapot suit l'emprise du lac : quelques points sur son pourtour, pas un
## seul au centre — une nappe d'eau de 1 870 m² n'a pas de « milieu » audible.
func _place_water() -> void:
	var stream: AudioStream = load(WATER) as AudioStream
	if stream == null or _terrain.lake == null:
		return
	var lake: CavernLake = _terrain.lake
	for i in 4:
		var a: float = TAU * float(i) / 4.0
		var at: Vector2 = lake.center + Vector2(cos(a) * lake.radii.x * 0.7, sin(a) * lake.radii.y * 0.7)
		_emit(stream, Vector3(at.x, lake.surface_altitude + 0.4, at.y),
			water_db, water_range, "Clapot_%d" % i)


func _emit(stream: AudioStream, at: Vector3, db: float, distance: float, node_name: String) -> void:
	var p := AudioStreamPlayer3D.new()
	p.name = node_name
	p.stream = stream
	p.volume_db = db
	p.autoplay = true
	p.max_distance = distance
	# Atténuation inverse-carré atténuée : la linéaire coupe trop net et fait
	# « apparaître » le son en marchant, l'inverse pure porte trop loin.
	p.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	p.unit_size = distance * 0.25
	add_child(p)
	p.global_position = at
	_sources.append(p)


## Lecture pour les tests : combien d'émetteurs ont réellement été posés.
func get_source_count() -> int:
	return _sources.size()

## Recale les marqueurs de gameplay sur le sol réellement généré.
##
## POURQUOI
## Les marqueurs (spawns, coffres, cristaux, boss) sont posés en X/Z dans la
## scène, mais leur altitude dépend du terrain — lequel est généré à
## l'exécution et change à chaque itération sur la topographie. Les coter à la
## main condamne à les recoter à chaque passe, et un oubli enterre l'objet sans
## que rien ne le signale : trois marqueurs l'ont été de 0,8 à 2,0 m sans qu'un
## seul test ne bronche.
##
## Ici, seul le X/Z est de la donnée d'auteur. L'altitude est déduite.
##
## Ne touche PAS aux marqueurs du groupe [constant GROUP_KEEP_ALTITUDE] : un
## cristal accroché en paroi ou une lumière suspendue ont une altitude voulue.

class_name CavernMarkerSnapper
extends Node

## Marqueurs de ce groupe : altitude laissée telle quelle.
const GROUP_KEEP_ALTITUDE := &"keep_altitude"

## Marqueurs de ce groupe : posés AU-DESSUS du sol, de
## [member spawn_clearance].
##
## Un joueur posé pile au niveau du sol commence sa première frame en contact
## avec le terrain, et la moindre irrégularité du champ de hauteurs suffit à le
## coincer. Le lâcher d'un mètre le laisse retomber et se poser proprement.
const GROUP_SPAWN_ABOVE_GROUND := &"spawn_above_ground"

## Racine sous laquelle chercher les marqueurs. Vide = le parent.
@export var markers_root_path: NodePath

## Terrain de référence.
@export_file("*.tres") var terrain_path: String = "res://data/levels/level01_cavern_terrain.tres"

## Décalage vertical appliqué après recalage, en mètres. Un objet posé
## exactement au sol s'y encastre visuellement d'un ou deux centimètres.
@export var ground_offset: float = 0.0

## Hauteur de lâcher des marqueurs du groupe [constant GROUP_SPAWN_ABOVE_GROUND].
@export var spawn_clearance: float = 1.0

## Émis après recalage, avec le nombre de marqueurs traités.
signal markers_snapped(count: int)


func _ready() -> void:
	# Le terrain se construit dans son propre `_ready` : on laisse passer une
	# frame pour ne pas recaler sur un monde à moitié bâti.
	await get_tree().process_frame
	snap_now()


## Recale tous les marqueurs et retourne leur nombre.
func snap_now() -> int:
	var terrain: CavernTerrainData = load(terrain_path) as CavernTerrainData
	if terrain == null:
		push_error("CavernMarkerSnapper : terrain introuvable (%s)." % terrain_path)
		return 0

	var root: Node = get_node_or_null(markers_root_path) if not markers_root_path.is_empty() else get_parent()
	if root == null:
		push_error("CavernMarkerSnapper : racine de marqueurs introuvable.")
		return 0

	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)
	var snapped: int = 0
	var outside: int = 0

	for marker in _all_markers(root):
		if marker.is_in_group(GROUP_KEEP_ALTITUDE):
			continue
		var position: Vector3 = marker.global_transform.origin
		var flat := Vector2(position.x, position.z)
		# Un marqueur hors du volume creusé serait dans la roche pleine : on le
		# signale plutôt que de le poser silencieusement dans un mur.
		if CavernTerrainBuilder.chamber_mask(terrain, flat) <= 0.0:
			push_warning("CavernMarkerSnapper : « %s » est hors de la caverne (%.0f, %.0f)."
				% [marker.name, flat.x, flat.y])
			outside += 1
			continue
		var ground: float = CavernTerrainBuilder.sample_point(terrain.floor_field, flat, noise)
		var offset: float = ground_offset
		if marker.is_in_group(GROUP_SPAWN_ABOVE_GROUND):
			offset += spawn_clearance
		marker.global_position = Vector3(position.x, ground + offset, position.z)
		snapped += 1

	if outside > 0:
		push_warning("CavernMarkerSnapper : %d marqueur(s) hors de la caverne." % outside)
	markers_snapped.emit(snapped)
	return snapped


func _all_markers(root: Node) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Marker3D:
			out.append(node as Marker3D)
	return out

class_name ForgeBridge
extends Node3D

## Le pont suspendu qui franchit les douves de lave vers le château.
##
## ## Pourquoi il existe
##
## Signalé en jeu : la porte s'ouvrait et **on ne pouvait pas entrer**. Le
## château était bâti de l'autre côté de la coulée, sans aucun passage — le
## puzzle récompensait donc par une porte ouverte sur rien.
##
## C'est un défaut de méthode plus que de code : j'avais vérifié que la porte
## s'ouvrait, jamais qu'on pouvait la franchir. Le test de traversabilité
## couvre maintenant le trajet complet, spawn → seuil du château.
##
## ## Ce qu'il apporte au niveau
##
## Un pont au-dessus d'une rivière de lave, c'est un **couloir sans couverture**
## dans un jeu où le tir ami est actif. À quatre, la traversée devient un
## moment de coordination — on ne se double pas sur une passerelle de six
## mètres de large.
##
## Il est droit et sans garde-corps : on doit voir la coulée passer dessous.
## Une rambarde pleine cacherait précisément ce qu'on vient regarder.

@export_file("*.tres") var terrain_data_path: String = "res://data/levels/level02_forge_terrain.tres"

## Les deux rives, en (X, Z). Du cirque vers le château.
@export var from_point: Vector2 = Vector2(0.0, 6.0)
@export var to_point: Vector2 = Vector2(0.0, -40.0)

@export var deck_width: float = 6.0
## Altitude du tablier. Au-dessus de la coulée, et de plain-pied avec les deux
## rives : un pont qu'il faut escalader n'est plus un pont.
@export var deck_altitude: float = 5.2

## Nombre de segments du tablier. Le pont s'incurve légèrement — un tablier
## parfaitement droit se lit comme une planche posée.
@export var segments: int = 14
@export var sag: float = 1.4

## Le dallage du tablier et la maçonnerie des pylônes d'ancrage. Deux matières
## distinctes parce qu'elles ne racontent pas la même chose : on MARCHE sur
## l'une, l'autre soutient. Cf `tools/build_forge_materials.gd`.
const DECK_PATH := "res://assets/level02/materials/forge_deck.tres"
const MASONRY_PATH := "res://assets/level02/materials/forge_masonry.tres"

const STONE := Color(0.075, 0.062, 0.068)
const CHAIN := Color(0.145, 0.118, 0.110)


func _ready() -> void:
	var terrain: CavernTerrainData = load(terrain_data_path) as CavernTerrainData
	if terrain == null:
		push_warning("ForgeBridge : terrain introuvable — pas de pont.")
		return
	await get_tree().process_frame
	_build()


func _build() -> void:
	var start := Vector3(from_point.x, deck_altitude, from_point.y)
	var end := Vector3(to_point.x, deck_altitude, to_point.y)
	var span: Vector3 = end - start
	var length: float = span.length()
	var heading: float = atan2(span.x, span.z)

	var deck_material: Material = _stone(DECK_PATH)
	var stone: Material = _stone(MASONRY_PATH)

	var chain_material := StandardMaterial3D.new()
	chain_material.albedo_color = CHAIN
	chain_material.roughness = 0.55
	chain_material.metallic = 0.6

	# LE TABLIER, en segments. La flèche est une parabole : elle plonge au
	# milieu, ce qui fait qu'on voit la lave de plus près à mi-parcours — au
	# moment exact où l'on est le plus exposé.
	var step: float = 1.0 / float(segments)
	for i in segments:
		var t0: float = float(i) * step
		var t1: float = float(i + 1) * step
		var p0: Vector3 = start.lerp(end, t0) - Vector3(0.0, _sag_at(t0), 0.0)
		var p1: Vector3 = start.lerp(end, t1) - Vector3(0.0, _sag_at(t1), 0.0)
		var mid: Vector3 = (p0 + p1) * 0.5
		var seg: Vector3 = p1 - p0

		var plank := MeshInstance3D.new()
		plank.name = "Tablier_%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(deck_width, 0.55, seg.length() + 0.25)
		plank.mesh = mesh
		plank.material_override = deck_material
		add_child(plank)
		plank.global_position = mid
		plank.rotation.y = heading
		# La planche suit la pente locale, sinon on verrait des marches.
		plank.rotate_object_local(Vector3.RIGHT, -atan2(seg.y, Vector2(seg.x, seg.z).length()))

		_add_collider("ColTablier_%d" % i, mesh.size, mid, plank.rotation)

	_build_rails(start, end, heading, chain_material)
	_build_pylons(start, end, heading, stone)


## Charge une matière de pierre, avec repli sur une teinte plate.
func _stone(path: String) -> Material:
	var material: StandardMaterial3D = load(path) as StandardMaterial3D
	if material != null:
		return material
	push_warning("ForgeBridge : matière absente (%s) — repli sur une teinte plate." % path)
	var flat := StandardMaterial3D.new()
	flat.albedo_color = STONE
	flat.roughness = 0.85
	return flat


## La flèche du tablier à l'abscisse `t`, en mètres.
func _sag_at(t: float) -> float:
	return sag * 4.0 * t * (1.0 - t)


## Les garde-corps : deux câbles bas, pas un mur.
##
## Ils empêchent de tomber par inadvertance sans rien cacher de la coulée —
## c'est elle qu'on vient voir, et une rambarde pleine la masquerait.
func _build_rails(start: Vector3, end: Vector3, heading: float, material: Material) -> void:
	for side in [-1.0, 1.0]:
		var offset: Vector3 = Vector3(cos(heading), 0.0, -sin(heading)) * (deck_width * 0.5) * side
		var lane: int = 0 if side < 0.0 else 1
		var step: float = 1.0 / float(segments)
		for i in segments:
			var t0: float = float(i) * step
			var t1: float = float(i + 1) * step
			var p0: Vector3 = start.lerp(end, t0) - Vector3(0.0, _sag_at(t0) - 1.0, 0.0) + offset
			var p1: Vector3 = start.lerp(end, t1) - Vector3(0.0, _sag_at(t1) - 1.0, 0.0) + offset
			var seg: Vector3 = p1 - p0

			var cable := MeshInstance3D.new()
			cable.name = "Cable_%d_%d" % [lane, i]
			var mesh := BoxMesh.new()
			mesh.size = Vector3(0.16, 0.16, seg.length() + 0.1)
			cable.mesh = mesh
			cable.material_override = material
			add_child(cable)
			cable.global_position = (p0 + p1) * 0.5
			cable.rotation.y = heading
			cable.rotate_object_local(Vector3.RIGHT,
				-atan2(seg.y, Vector2(seg.x, seg.z).length()))

			# Un montant sur deux : plus, ça ferait grille.
			if i % 2 == 0:
				var post := MeshInstance3D.new()
				post.name = "Montant_%d_%d" % [lane, i]
				var post_mesh := BoxMesh.new()
				post_mesh.size = Vector3(0.18, 1.1, 0.18)
				post.mesh = post_mesh
				post.material_override = material
				add_child(post)
				post.global_position = p0 - Vector3(0.0, 0.55, 0.0)


## Les deux pylônes d'ancrage. Ils tiennent les câbles et, surtout, ils
## ANNONCENT le pont de loin — deux masses verticales qui sortent de la brume
## et disent « on passe ici ».
func _build_pylons(start: Vector3, end: Vector3, heading: float, material: Material) -> void:
	var anchors: Array[Vector3] = [start, end]
	for a in anchors.size():
		var anchor: Vector3 = anchors[a]
		for side in [-1.0, 1.0]:
			var offset: Vector3 = Vector3(cos(heading), 0.0, -sin(heading)) \
				* (deck_width * 0.5 + 0.6) * side
			var pylon := MeshInstance3D.new()
			pylon.name = "Pylone_%d_%d" % [a, 0 if side < 0.0 else 1]
			var mesh := CylinderMesh.new()
			mesh.top_radius = 0.55
			mesh.bottom_radius = 0.95
			mesh.height = 9.5
			mesh.radial_segments = 6
			pylon.mesh = mesh
			pylon.material_override = material
			add_child(pylon)
			pylon.global_position = anchor + offset + Vector3(0.0, 3.2, 0.0)


## Chaque collider porte un nom UNIQUE.
##
## Godot ne suffixe pas les doublons : il jette le nom demandé et retombe sur
## « @StaticBody3D@3 ». Quatorze colliders nommés pareil devenaient donc treize
## nœuds anonymes — introuvables par nom, pour le test comme pour le code.
func _add_collider(collider_name: String, size: Vector3, at: Vector3,
		rotation: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = collider_name
	# Sur la couche du décor ET du navmesh : le pont est un sol, les ennemis
	# doivent pouvoir l'emprunter.
	body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER \
		| CavernTerrainBuilder.NAVMESH_SOURCE_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	body.rotation = rotation


## Le point d'arrivée du pont, côté château.
func get_far_end() -> Vector3:
	return Vector3(to_point.x, deck_altitude, to_point.y)

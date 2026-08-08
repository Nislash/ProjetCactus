class_name KeepSpiralRamp
extends Node3D

## La rampe hélicoïdale qui s'enroule autour du donjon, et redescend derrière
## lui jusqu'à l'arène du boss.
##
## ## Une RAMPE et non un escalier
##
## Un escalier à marches est plus joli et pratiquement injouable ici : le
## navmesh de Godot voxelise à 0,25 m et n'accepte que 0,5 m de marche, donc des
## marches lisibles à l'œil deviennent soit un mur pour les ennemis, soit un
## plan incliné déguisé. Une rampe continue en pas de vis monte au même endroit,
## se cuit proprement, et se franchit sans accrocher — c'est d'ailleurs la
## solution que le propriétaire avait lui-même proposée en repli.
##
## ## Pourquoi elle fait le tour PAR L'EXTÉRIEUR
##
## Parce qu'on doit la voir apparaître. Le levier est à soixante-dix mètres de
## là : si la récompense se déployait à l'intérieur de la tour, le joueur
## tirerait le levier et ne verrait rien. Une hélice qui sort des flancs du
## donjon est lisible depuis tout le cirque.
##
## ## Et la descente
##
## Le château n'a pas de porte, et c'est le sujet : on ne le traverse pas, on
## PASSE PAR-DESSUS. La rampe monte donc au sommet, puis redescend par l'arrière
## vers le tunnel qui mène à l'arène. C'est le seul chemin vers le boss.

signal deployed()

## Le donjon autour duquel on s'enroule.
@export var keep_centre: Vector3 = Vector3.ZERO
@export var keep_radius: float = 12.0

## Altitudes de départ (la terrasse) et d'arrivée (le sommet).
@export var bottom_altitude: float = 7.9
@export var top_altitude: float = 30.0

## Largeur de la bande. Assez pour se croiser à deux, pas plus : c'est un
## chemin, pas une place.
@export var ramp_width: float = 3.4

## Nombre de segments par tour. 24 donne des marches de 15° — invisibles à
## l'œil sur un rayon de douze mètres, et lisses pour le navmesh.
@export var segments_per_turn: int = 24

## Où la rampe redescend, côté arène.
@export var descent_target: Vector3 = Vector3(0.0, 6.0, -66.0)

const STONE_PATH := "res://assets/level02/materials/forge_masonry.tres"
const EDGE := Color(1.000, 0.478, 0.184)

var _pieces: Array[Node3D] = []
## Deux drapeaux et non un.
##
## `_deploying` garde contre un second appel ; `_deployed` ne bascule qu'une
## fois le dernier tronçon posé ET le navmesh recuit. Les confondre faisait dire
## « c'est prêt » à la première frame, alors que la rampe n'existait ni pour la
## navigation ni pour l'œil — un test qui s'y fiait mesurait donc le vide.
var _deploying: bool = false
var _deployed: bool = false


func _ready() -> void:
	_build()
	_set_visible(false)


func _build() -> void:
	var stone: Material = load(STONE_PATH) as Material
	if stone == null:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.055, 0.045, 0.050)
		flat.roughness = 0.9
		stone = flat

	# LA MONTÉE. Deux tours complets, ce qui donne une pente douce sur un rayon
	# de douze mètres : un seul tour ferait 22°, trois n'apporteraient qu'une
	# ascension plus longue sans rien changer à la lecture.
	var turns: float = 2.0
	var steps: int = int(float(segments_per_turn) * turns)
	var radius: float = keep_radius + ramp_width * 0.5
	for i in steps:
		var t0: float = float(i) / float(steps)
		var t1: float = float(i + 1) / float(steps)
		_span(stone,
			_helix(radius, t0 * turns, lerpf(bottom_altitude, top_altitude, t0)),
			_helix(radius, t1 * turns, lerpf(bottom_altitude, top_altitude, t1)),
			"Rampe_%d" % i)

	# LE PALIER du sommet : on doit pouvoir s'arrêter et regarder avant de
	# redescendre. Sans lui, l'ascension débouche sur une pente qui repart, et
	# le sommet n'existe pas comme lieu.
	var crown: Vector3 = _helix(radius, turns, top_altitude)
	_slab(stone, crown + Vector3(0.0, 0.0, 0.0),
		Vector3(ramp_width * 2.6, 0.5, ramp_width * 2.6), "Palier")

	# LA DESCENTE vers l'arène. Une volée droite, à l'opposé du cirque : on
	# tourne le dos à ce qu'on connaît, ce qui est exactement le sentiment
	# qu'on veut avant un boss.
	var descent_steps: int = 16
	for i in descent_steps:
		var t0: float = float(i) / float(descent_steps)
		var t1: float = float(i + 1) / float(descent_steps)
		_span(stone, crown.lerp(descent_target, t0), crown.lerp(descent_target, t1),
			"Descente_%d" % i)


## Un point de l'hélice. `turn` est en TOURS, pas en radians — c'est l'unité
## dans laquelle on raisonne quand on décide « deux tours autour de la tour ».
func _helix(radius: float, turn: float, altitude: float) -> Vector3:
	var a: float = TAU * turn + PI  # départ côté cirque, face au pont.
	return keep_centre + Vector3(cos(a) * radius, 0.0, sin(a) * radius) \
		+ Vector3(0.0, altitude - keep_centre.y, 0.0)


## Un tronçon de bande entre deux points, incliné selon sa propre pente.
func _span(material: Material, from_point: Vector3, to_point: Vector3,
		piece_name: String) -> void:
	var span: Vector3 = to_point - from_point
	var mid: Vector3 = (from_point + to_point) * 0.5
	var flat: float = Vector2(span.x, span.z).length()

	var piece := MeshInstance3D.new()
	piece.name = piece_name
	var mesh := BoxMesh.new()
	# Un peu plus long que l'écart : les tronçons se chevauchent, sinon on voit
	# le ciel entre eux dès que la pente change.
	mesh.size = Vector3(ramp_width, 0.45, span.length() + 0.5)
	piece.mesh = mesh
	piece.material_override = material
	add_child(piece)
	piece.global_position = mid
	piece.rotation.y = atan2(span.x, span.z)
	piece.rotate_object_local(Vector3.RIGHT, -atan2(span.y, flat))
	_pieces.append(piece)
	_collider(mesh.size, piece.global_position, piece.rotation, piece_name)


func _slab(material: Material, at: Vector3, size: Vector3, piece_name: String) -> void:
	var piece := MeshInstance3D.new()
	piece.name = piece_name
	var mesh := BoxMesh.new()
	mesh.size = size
	piece.mesh = mesh
	piece.material_override = material
	add_child(piece)
	piece.global_position = at
	_pieces.append(piece)
	_collider(size, at, Vector3.ZERO, piece_name)


func _collider(size: Vector3, at: Vector3, rotation: Vector3, piece_name: String) -> void:
	var body := StaticBody3D.new()
	body.name = "Col_%s" % piece_name
	# Source de navmesh : la rampe est un SOL. Sans ce bit, on y monterait mais
	# aucun ennemi ne pourrait suivre, et le boss se battrait seul dans son
	# arène pendant qu'on l'observe depuis le palier.
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
	_pieces.append(body)


## Sort de la tour. Les tronçons apparaissent DU BAS VERS LE HAUT, à un rythme
## qui laisse le temps de comprendre où ça mène — un déploiement instantané
## ferait juste apparaître un objet.
func deploy() -> void:
	if _deploying:
		return
	_deploying = true
	var delay: float = 0.0
	for piece in _pieces:
		var target: Node3D = piece
		get_tree().create_timer(delay).timeout.connect(func() -> void:
			if is_instance_valid(target):
				target.visible = true
				var body: StaticBody3D = target as StaticBody3D
				if body != null:
					body.process_mode = Node.PROCESS_MODE_INHERIT)
		# Les colliders n'ont pas à décaler la mise en scène : ils accompagnent
		# leur maillage. Les compter doublait la durée du déploiement sans rien
		# ajouter à ce qu'on voit.
		if piece is MeshInstance3D:
			delay += 0.03
	get_tree().create_timer(delay + 0.2).timeout.connect(func() -> void:
		_rebake()
		_deployed = true
		deployed.emit())
	print("[KeepSpiralRamp] la rampe sort du donjon.")


## Le navmesh est cuit AVANT que la rampe existe : sans nouvelle cuisson, elle
## resterait invisible à la navigation, et les ennemis ne l'emprunteraient
## jamais. C'est le genre d'oubli qui ne se voit qu'en combat.
func _rebake() -> void:
	# On cherche le FRÈRE, pas depuis `current_scene` : celle-ci est nulle
	# quand la scène est instanciée à la main (bancs, tests), et le recuisage
	# était alors silencieusement sauté — la rampe existait pour les joueurs et
	# pas pour la navigation.
	var navigation: Node = get_parent().get_node_or_null("Navigation")
	if navigation != null and navigation.has_method("bake_now"):
		navigation.call("bake_now")


func _set_visible(state: bool) -> void:
	for piece in _pieces:
		piece.visible = state
		var body: StaticBody3D = piece as StaticBody3D
		if body != null:
			# Désactivée tant qu'elle n'est pas sortie : une rampe invisible
			# mais solide serait un mur en plein ciel.
			body.process_mode = Node.PROCESS_MODE_INHERIT if state \
				else Node.PROCESS_MODE_DISABLED


## Le sommet RÉEL de la rampe — sur l'hélice, pas sur l'axe de la tour.
##
## L'axe est à douze mètres de la bande : viser le centre du donjon pour
## interroger la navigation revient à demander si l'on peut marcher dans la
## pierre.
func get_summit() -> Vector3:
	return _helix(keep_radius + ramp_width * 0.5, 2.0, top_altitude)


func is_deployed() -> bool:
	return _deployed

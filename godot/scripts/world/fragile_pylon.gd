class_name FragilePylon
extends Interactable

## Le pylône fissuré qu'on pousse pour qu'il tombe en travers de la coulée.
##
## ## Ce qu'il résout
##
## On atteint le levier en SAUTANT par-dessus la coulée. Un saut est un aller
## simple : refaire le saut dans l'autre sens depuis une plateforme basse ne
## marche pas, et sans issue le joueur reste coincé derrière une cascade avec
## un levier déjà tiré. Le pylône est le retour — et il n'existe qu'une fois
## qu'on l'a fait tomber, donc l'aller garde son risque.
##
## ## Pourquoi on le POUSSE plutôt que de le trouver déjà tombé
##
## Parce que le joueur doit comprendre qu'il vient de fabriquer son chemin.
## C'est la même différence qu'entre trouver une clé et forger la clé : le
## deuxième se raconte.
##
## ## Il tombe DANS la lave et reste praticable
##
## Un fût de basalte de trois mètres de diamètre à demi immergé dans une coulée
## reste solide — c'est la lecture qu'on veut, et elle tient parce que le
## tablier qu'il forme est au-dessus de la nappe. Le danger est de tomber À
## CÔTÉ, pas de marcher dessus.

signal fell()

## Où il tombe : la direction, en (X, Z). Il bascule dans ce sens.
@export var fall_direction: Vector2 = Vector2(0.0, 1.0)

@export var height: float = 22.0
@export var radius: float = 1.7

## Altitude où sa POINTE vient se poser, une fois abattu.
##
## Il ne tombe pas à plat : il tombe d'un palier haut vers une berge basse, et
## se couche donc en RAMPE. Un tablier horizontal partirait du palier et
## finirait vingt mètres au-dessus du sol — un pont vers le vide.
@export var deck_altitude: float = 2.9

const STONE_PATH := "res://data/levels/forge_rock_material.tres"
const CRACK := Color(1.000, 0.478, 0.184)

var _shaft: Node3D
var _fallen: bool = false
var _bridge_body: StaticBody3D


func _ready() -> void:
	super._ready()
	prompt_text = "Pousser le pylône"
	hold_duration = 1.1
	interaction_range = 4.0
	selection_priority = 10
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 4.5
	shape.shape = sphere
	shape.position = Vector3(0.0, 2.0, 0.0)
	add_child(shape)

	var rock: Material = load(STONE_PATH) as Material

	# Le pivot est AU PIED : c'est autour de sa base qu'un fût bascule, et
	# faire tourner le maillage autour de son centre le ferait s'enfoncer dans
	# le sol d'un côté en décollant de l'autre.
	_shaft = Node3D.new()
	_shaft.name = "Fut"
	add_child(_shaft)

	var column := MeshInstance3D.new()
	column.name = "Colonne"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.86
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 8
	column.mesh = mesh
	column.material_override = rock
	column.position = Vector3(0.0, height * 0.5, 0.0)
	_shaft.add_child(column)

	# LES FISSURES. Trois bagues incandescentes : c'est le seul signal qui
	# distingue ce pylône des piles du pont, et sans lui rien ne dit qu'on peut
	# le pousser. Un objet actionnable doit se voir avant d'être approché.
	for i in 3:
		var crack := MeshInstance3D.new()
		crack.name = "Fissure_%d" % i
		var ring := TorusMesh.new()
		ring.inner_radius = radius * 0.93
		ring.outer_radius = radius * 1.06
		ring.rings = 10
		crack.mesh = ring
		var glow := StandardMaterial3D.new()
		glow.albedo_color = CRACK.darkened(0.4)
		glow.emission_enabled = true
		glow.emission = CRACK
		glow.emission_energy_multiplier = 2.4
		crack.material_override = glow
		crack.position = Vector3(0.0, height * (0.28 + 0.22 * float(i)), 0.0)
		_shaft.add_child(crack)

	# Debout, il BLOQUE : sinon on le traverserait, et le fait de le pousser
	# perdrait tout son sens.
	var standing := StaticBody3D.new()
	standing.name = "ColDebout"
	standing.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER
	var standing_shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = radius
	cylinder.height = height
	standing_shape.shape = cylinder
	standing_shape.position = Vector3(0.0, height * 0.5, 0.0)
	standing.add_child(standing_shape)
	_shaft.add_child(standing)


func can_interact(_by_player: Node) -> bool:
	return not _fallen


func try_interact(_by_player: Node) -> bool:
	if _fallen:
		return false
	_fallen = true

	var heading: float = atan2(fall_direction.x, fall_direction.y)
	var tween: Tween = create_tween()
	# Il hésite, puis part. Une bascule à vitesse constante ressemble à une
	# porte qui s'ouvre ; l'accélération dit le poids.
	tween.tween_property(_shaft, "rotation:y", heading, 0.1)
	tween.tween_property(_shaft, "rotation:x", deg_to_rad(4.0), 0.45) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_property(_shaft, "rotation:x", _resting_pitch(), 0.9) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_lay_down)
	return true


## L'inclinaison à laquelle il s'arrête : celle où sa pointe touche le sol visé.
##
## `asin` du dénivelé sur la longueur, et non 90° : le fût pivote autour de sa
## base, qui reste en haut. S'il basculait jusqu'à l'horizontale il flotterait,
## et s'il continuait au-delà il traverserait la roche.
func _resting_pitch() -> float:
	var drop: float = global_position.y - deck_altitude
	var ratio: float = clampf(drop / maxf(height, 0.001), 0.0, 1.0)
	return deg_to_rad(90.0) - asin(ratio)


## La pente de la rampe une fois posée, en degrés. Le test la relit : au-delà
## de ce que le joueur descend, le pylône serait un toboggan sans retour.
func resting_slope_degrees() -> float:
	return rad_to_deg(asin(clampf((global_position.y - deck_altitude)
		/ maxf(height, 0.001), 0.0, 1.0)))


## Une fois couché, le fût cesse d'être un obstacle et devient un SOL.
##
## Les deux collisions sont séparées, et c'est nécessaire : un cylindre couché
## est une surface ronde sur laquelle on glisse. Le tablier qu'on pose dessus
## est un pavé plat, à peine plus étroit — on marche sur le dessus du fût, pas
## sur son flanc.
func _lay_down() -> void:
	var standing: StaticBody3D = _shaft.get_node_or_null("ColDebout") as StaticBody3D
	if standing != null:
		standing.queue_free()

	var along := Vector3(fall_direction.x, 0.0, fall_direction.y).normalized()
	var drop: float = global_position.y - deck_altitude
	var reach: float = sqrt(maxf(height * height - drop * drop, 0.0))
	var tip: Vector3 = global_position + along * reach - Vector3(0.0, drop, 0.0)
	var mid: Vector3 = (global_position + tip) * 0.5

	_bridge_body = StaticBody3D.new()
	_bridge_body.name = "ColTablierPylone"
	_bridge_body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER \
		| CavernTerrainBuilder.NAVMESH_SOURCE_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	# Un peu plus étroit que le fût, et plat : on marche sur le DESSUS d'un
	# cylindre couché, pas sur son flanc, où l'on glisserait.
	box.size = Vector3(radius * 1.7, 1.0, height)
	shape.shape = box
	_bridge_body.add_child(shape)
	add_child(_bridge_body)
	_bridge_body.global_position = mid + Vector3(0.0, radius * 0.55, 0.0)
	_bridge_body.rotation.y = atan2(along.x, along.z)
	# Le tablier suit la pente du fût couché : horizontal, il dépasserait
	# au-dessus à un bout et s'enfoncerait à l'autre.
	_bridge_body.rotate_object_local(Vector3.RIGHT, atan2(drop, maxf(reach, 0.001)))

	fell.emit()
	_rebake()
	print("[FragilePylon] le pylône est tombé — le passage est ouvert.")


## Le navmesh a été cuit avant la chute. Sans nouvelle cuisson, le pont existe
## pour les joueurs et pas pour les ennemis.
func _rebake() -> void:
	# On cherche le FRÈRE, pas depuis `current_scene` : celle-ci est nulle
	# quand la scène est instanciée à la main (bancs, tests), et le recuisage
	# était alors silencieusement sauté — la rampe existait pour les joueurs et
	# pas pour la navigation.
	var navigation: Node = get_parent().get_node_or_null("Navigation")
	if navigation != null and navigation.has_method("bake_now"):
		navigation.call("bake_now")


func has_fallen() -> bool:
	return _fallen

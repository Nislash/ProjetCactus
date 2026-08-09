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

## Où le fût vient se coucher, en (X, Z), et à quelle altitude sa surface
## marchable se retrouve.
##
## IL SE DÉTACHE DU PALIER. La version précédente le faisait pivoter sur sa
## base, qui restait en haut : il finissait en rampe raide, et on ne voyait
## jamais la lave qu'il était censé traverser. Il BASCULE maintenant dans le
## vide et retombe à plat dans la coulée, à demi immergé.
##
## Ce qui change pour le joueur : il saute vingt-deux mètres pour l'atteindre —
## le niveau n'inflige pas de dégâts de chute — puis marche le long du fût
## pendant que la lave lèche ses flancs.
@export var lands_at: Vector2 = Vector2.ZERO
@export var deck_altitude: float = 2.8

## Altitude des deux berges, dans l'ordre du sens de chute. Deux petites rampes
## y raccordent le tablier : sans elles, on bute sur un ressaut d'un mètre et
## « monter sur le pylône » devient une affaire de saut bien placé.
@export var bank_altitudes: Vector2 = Vector2(2.0, 1.2)

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
	var along := Vector3(fall_direction.x, 0.0, fall_direction.y).normalized()
	# Couché, le fût s'étend depuis son origine dans le sens de la chute : on
	# recule donc l'origine d'une demi-longueur pour qu'il se centre sur le
	# point d'arrivée.
	var resting: Vector3 = Vector3(lands_at.x, deck_altitude - radius * 0.75, lands_at.y) \
		- along * height * 0.5

	var tween: Tween = create_tween()
	# Il hésite, puis part. Une bascule à vitesse constante ressemble à une
	# porte qui s'ouvre ; l'accélération dit le poids.
	tween.tween_property(_shaft, "rotation:y", heading, 0.1)
	tween.tween_property(_shaft, "rotation:x", deg_to_rad(5.0), 0.45) \
		.set_trans(Tween.TRANS_SINE)
	tween.tween_property(_shaft, "rotation:x", deg_to_rad(90.0), 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(_shaft, "global_position", resting, 1.1) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_lay_down)
	return true


func _lay_down() -> void:
	var standing: StaticBody3D = _shaft.get_node_or_null("ColDebout") as StaticBody3D
	if standing != null:
		standing.queue_free()

	var along := Vector3(fall_direction.x, 0.0, fall_direction.y).normalized()
	var centre := Vector3(lands_at.x, deck_altitude, lands_at.y)

	# LE TABLIER. Un pavé plat sur le dessus du fût : un cylindre couché est
	# une surface ronde sur laquelle on glisse.
	_bridge_body = _slab("ColTablierPylone",
		Vector3(radius * 1.8, 0.8, height), centre - Vector3(0.0, 0.4, 0.0),
		atan2(along.x, along.z), 0.0)

	# LES DEUX RAMPES D'ACCÈS, une par berge. C'est ce qui permet de MONTER sur
	# le pylône : sans elles il reste un ressaut, et le pont ne sert qu'à ceux
	# qui pensent à sauter au bon endroit.
	for side in 2:
		var direction: float = -1.0 if side == 0 else 1.0
		var bank: float = bank_altitudes.x if side == 0 else bank_altitudes.y
		var foot: Vector3 = centre + along * (height * 0.5 + RAMP_RUN * 0.5) * direction
		var rise: float = deck_altitude - bank
		var ramp: StaticBody3D = _slab("RampePylone_%d" % side,
			Vector3(radius * 1.8, 0.6, RAMP_RUN),
			foot - Vector3(0.0, rise * 0.5 + 0.3, 0.0),
			atan2(along.x, along.z),
			atan2(rise, RAMP_RUN) * direction)
		ramp.name = "RampePylone_%d" % side

	fell.emit()
	_rebake()
	print("[FragilePylon] le pylône est tombé dans la coulée — on peut traverser.")


## Longueur des rampes d'accès, en mètres.
const RAMP_RUN: float = 5.0


func _slab(slab_name: String, size: Vector3, at: Vector3, heading: float,
		pitch: float) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = slab_name
	body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER \
		| CavernTerrainBuilder.NAVMESH_SOURCE_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	body.rotation.y = heading
	body.rotate_object_local(Vector3.RIGHT, pitch)

	var visual := MeshInstance3D.new()
	visual.name = "Mesh"
	var mesh := BoxMesh.new()
	mesh.size = size
	visual.mesh = mesh
	visual.material_override = load(STONE_PATH) as Material
	body.add_child(visual)
	return body


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

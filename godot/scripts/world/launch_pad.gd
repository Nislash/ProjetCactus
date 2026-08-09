class_name LaunchPad
extends Area3D

## La dalle à ressort du sommet de la tour : elle projette le joueur dans
## l'arène du boss, par les airs.
##
## ## Pourquoi une catapulte plutôt qu'un escalier
##
## L'arène est cent mètres derrière le château et vingt-cinq mètres plus bas.
## Y descendre à pied demanderait une rampe encore plus longue que celle qu'on
## vient de retirer, et surtout ça ferait de l'arrivée une formalité — on
## marche, on arrive, on se bat.
##
## Projeté, on ne choisit plus. On voit l'arène venir pendant deux secondes et
## demie sans pouvoir y changer quoi que ce soit, et on atterrit au milieu. Un
## combat de boss commence mieux par une chute que par un couloir.
##
## ## Ce qu'elle ne fait pas
##
## Elle ne se déclenche pas au contact : c'est le levier du sommet qui l'arme.
## Une dalle qui catapulte dès qu'on marche dessus est un piège, pas un choix —
## et à quatre joueurs, le premier arrivé enverrait tout le monde.

signal launched(who: Node3D)

## Où l'on doit atterrir, en monde. La vitesse initiale s'en déduit.
@export var target: Vector3 = Vector3.ZERO

## Durée du vol, en secondes. C'est elle qui décide de la hauteur de la
## trajectoire : plus long, plus haut, plus spectaculaire — et plus long à
## subir.
@export var flight_time: float = 2.5

@export var pad_radius: float = 3.6

const PLATE := Color(0.075, 0.062, 0.068)
const GLOW := Color(1.000, 0.478, 0.184)

var _armed: bool = false
var _plate: Node3D
var _light: OmniLight3D


func _ready() -> void:
	monitoring = true
	monitorable = false
	collision_layer = 0
	collision_mask = 0xFFFFFFFF
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var cylinder := CylinderShape3D.new()
	cylinder.radius = pad_radius
	cylinder.height = 2.4
	shape.shape = cylinder
	shape.position = Vector3(0.0, 1.2, 0.0)
	add_child(shape)

	_plate = Node3D.new()
	_plate.name = "Dalle"
	add_child(_plate)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = PLATE
	stone.roughness = 0.85

	var disc := MeshInstance3D.new()
	disc.name = "Plateau"
	var mesh := CylinderMesh.new()
	mesh.top_radius = pad_radius
	mesh.bottom_radius = pad_radius * 0.86
	mesh.height = 0.5
	mesh.radial_segments = 12
	disc.mesh = mesh
	disc.material_override = stone
	disc.position = Vector3(0.0, 0.25, 0.0)
	_plate.add_child(disc)

	# LES RESSORTS : trois arcs incandescents sous la dalle. C'est le seul
	# indice qu'elle n'est pas un socle — sans eux, on monte dessus et il ne se
	# passe rien de lisible.
	for i in 3:
		var a: float = TAU * float(i) / 3.0
		var coil := MeshInstance3D.new()
		coil.name = "Ressort_%d" % i
		var torus := TorusMesh.new()
		torus.inner_radius = 0.45
		torus.outer_radius = 0.72
		torus.rings = 8
		coil.mesh = torus
		var hot := StandardMaterial3D.new()
		hot.albedo_color = GLOW.darkened(0.5)
		hot.emission_enabled = true
		hot.emission = GLOW
		hot.emission_energy_multiplier = 1.4
		coil.mesh = torus
		coil.material_override = hot
		coil.position = Vector3(cos(a) * pad_radius * 0.55, -0.1, sin(a) * pad_radius * 0.55)
		coil.rotation.x = deg_to_rad(90.0)
		_plate.add_child(coil)

	var body := StaticBody3D.new()
	body.name = "ColDalle"
	body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER \
		| CavernTerrainBuilder.NAVMESH_SOURCE_LAYER
	var support := CollisionShape3D.new()
	var slab := CylinderShape3D.new()
	slab.radius = pad_radius
	slab.height = 0.5
	support.shape = slab
	support.position = Vector3(0.0, 0.25, 0.0)
	body.add_child(support)
	add_child(body)

	_light = OmniLight3D.new()
	_light.name = "Lueur"
	_light.light_color = GLOW
	_light.light_energy = 1.2
	_light.omni_range = 10.0
	_light.shadow_enabled = false
	_light.position = Vector3(0.0, 1.0, 0.0)
	add_child(_light)


## Le levier arme la dalle. Tant qu'elle ne l'est pas, on peut s'y tenir.
func arm() -> void:
	if _armed:
		return
	_armed = true
	var tween: Tween = create_tween()
	tween.tween_property(_plate, "position:y", -0.35, 0.25).set_trans(Tween.TRANS_BACK)
	tween.parallel().tween_property(_light, "light_energy", 5.0, 0.25)
	print("[LaunchPad] la dalle est armée.")


func is_armed() -> bool:
	return _armed


func _physics_process(_delta: float) -> void:
	if not _armed:
		return
	for body in get_overlapping_bodies():
		var character: CharacterBody3D = body as CharacterBody3D
		if character != null:
			_launch(character)


## La vitesse initiale d'un tir balistique qui touche `target` en `flight_time`.
##
## On la CALCULE plutôt que de la régler à la main : la cible et la dalle ont
## déjà bougé trois fois, et une vitesse écrite en dur aurait envoyé le joueur
## dans le décor à chaque déplacement de l'une ou de l'autre.
func _launch(who: CharacterBody3D) -> void:
	var gravity: float = ProjectSettings.get_setting(
		"physics/3d/default_gravity", 9.8) as float
	var span: Vector3 = target - who.global_position
	var horizontal := Vector3(span.x, 0.0, span.z) / flight_time
	var vertical: float = span.y / flight_time + 0.5 * gravity * flight_time
	who.velocity = horizontal + Vector3(0.0, vertical, 0.0)
	# On le décolle d'un mètre : au contact du sol, `move_and_slide` mangerait
	# la composante verticale à la première frame et le tir ferait un bond.
	who.global_position += Vector3(0.0, 1.0, 0.0)
	launched.emit(who)
	print("[LaunchPad] joueur projeté vers %s." % target)

class_name MoonMirror
extends Interactable

## Un miroir de basalte poli, qu'on fait pivoter pour dévier le rayon de la
## lune rouge.
##
## ## Le verbe du niveau 2
##
## Le niveau 1 demande de **rassembler** — quatre éclats, un mot à
## reconstituer. Celui-ci demande d'**orienter**. Deux niveaux qui
## demanderaient la même chose au joueur ne seraient qu'un seul niveau joué
## deux fois.
##
## ## Pourquoi ça se comprend sans explication
##
## Le rayon est **visible**. On voit d'où il vient, où il va, et où il s'arrête
## — donc on voit aussi pourquoi il n'arrive pas. Il n'y a rien à deviner :
## seulement à regarder, puis à tourner.
##
## Chaque interaction fait pivoter le miroir d'un **cran** fixe. Une rotation
## continue obligerait à viser au degré près, ce qui est pénible à la manette ;
## des crans font de l'orientation une suite de choix, pas un exercice
## d'adresse.
##
## ## L'échec ne coûte rien
##
## Un rayon qui rate ne casse rien et ne blesse personne. Dans un roguelike où
## rien ne persiste, une énigme punitive serait une double peine — on a déjà
## perdu son temps, on ne va pas en plus perdre sa run.

signal aimed(mirror: MoonMirror)

## Nombre de positions possibles. Vingt-quatre crans = 15° chacun.
##
## Douze avaient été essayés d'abord : le test a montré qu'AUCUNE combinaison
## n'ouvrait la porte. La raison est géométrique — un rayon réfléchi tourne
## DEUX FOIS plus vite que la normale du miroir, donc 30° de cran font 60° de
## balayage, et la cible passait systématiquement entre deux crans.
const STEPS: int = 24

## Le cran courant.
@export var step: int = 0

## Longueur maximale du rayon réfléchi, en mètres.
@export var beam_length: float = 90.0

const MOON := Color(0.85, 0.24, 0.26)
const MOON_HOT := Color(1.00, 0.55, 0.50)

var _disc: MeshInstance3D
var _beam: MeshInstance3D
var _beam_material: StandardMaterial3D
var _lit: bool = false
var _incoming: Vector3 = Vector3.ZERO


func _ready() -> void:
	super._ready()
	add_to_group(&"moon_mirrors")
	prompt_text = "Pivoter le miroir"
	hold_duration = 0.35
	interaction_range = 3.4
	selection_priority = 12
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.8
	shape.shape = sphere
	add_child(shape)

	# Le pied. Il tient le miroir à hauteur d'homme et l'ancre au sol : un
	# disque flottant se lirait comme un effet, pas comme un objet.
	var base := MeshInstance3D.new()
	base.name = "Pied"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.35
	base_mesh.bottom_radius = 0.75
	base_mesh.height = 1.9
	base_mesh.radial_segments = 6
	base.mesh = base_mesh
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.055, 0.045, 0.050)
	stone.roughness = 0.9
	base.material_override = stone
	base.position = Vector3(0.0, 0.95, 0.0)
	add_child(base)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = 1.9
	cyl.radius = 0.7
	col.shape = cyl
	col.position = Vector3(0.0, 0.95, 0.0)
	body.add_child(col)
	add_child(body)

	# LE MIROIR. Basalte poli, presque noir, très lisse : c'est sa BRILLANCE
	# qui dit qu'il réfléchit, pas sa couleur.
	_disc = MeshInstance3D.new()
	_disc.name = "Miroir"
	var disc_mesh := CylinderMesh.new()
	disc_mesh.top_radius = 1.35
	disc_mesh.bottom_radius = 1.35
	disc_mesh.height = 0.22
	disc_mesh.radial_segments = 8
	_disc.mesh = disc_mesh
	var polished := StandardMaterial3D.new()
	polished.albedo_color = Color(0.045, 0.040, 0.050)
	polished.roughness = 0.06
	polished.metallic = 0.85
	_disc.material_override = polished
	# Debout : couché, il renverrait la lune au ciel.
	_disc.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	_disc.position = Vector3(0.0, 2.3, 0.0)
	add_child(_disc)

	_build_beam()
	_apply_step()


## Le rayon réfléchi. Rendu non éclairé et sans ombre : c'est de la lumière,
## pas un objet — un cylindre qui projetterait une ombre trahirait tout.
func _build_beam() -> void:
	_beam = MeshInstance3D.new()
	_beam.name = "Rayon"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.16
	mesh.bottom_radius = 0.16
	mesh.height = 1.0
	mesh.radial_segments = 6
	_beam.mesh = mesh
	_beam_material = StandardMaterial3D.new()
	_beam_material.albedo_color = Color(MOON.r, MOON.g, MOON.b, 0.55)
	_beam_material.emission_enabled = true
	_beam_material.emission = MOON_HOT
	_beam_material.emission_energy_multiplier = 3.0
	_beam_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_beam_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_beam_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_beam.material_override = _beam_material
	_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_beam.visible = false
	add_child(_beam)


func can_interact(_by_player: Node) -> bool:
	return true


func try_interact(by_player: Node) -> bool:
	step = (step + 1) % STEPS
	_apply_step()
	aimed.emit(self)
	interaction_completed.emit(by_player)
	return true


func _apply_step() -> void:
	if _disc == null:
		return
	# Le disque tourne AUTOUR de la verticale : sa normale balaie l'horizon.
	_disc.rotation_degrees = Vector3(90.0, facing_degrees(), 0.0)


func facing_degrees() -> float:
	return 360.0 * float(step) / float(STEPS)


## La normale du miroir, en repère monde. C'est elle qui décide où part le
## rayon.
func get_normal() -> Vector3:
	var a: float = deg_to_rad(facing_degrees())
	return Vector3(sin(a), 0.0, cos(a)).normalized()


## Le centre du miroir — d'où part le rayon réfléchi.
func get_focus() -> Vector3:
	return global_position + Vector3(0.0, 2.3, 0.0)


## Allume ou éteint le rayon sortant. Piloté par [MoonPuzzle], qui est seul à
## savoir ce que chaque miroir reçoit.
func set_incoming(direction: Vector3, lit: bool) -> void:
	_incoming = direction
	_lit = lit
	_refresh_beam()


## La direction du rayon RÉFLÉCHI — loi de la réflexion, **rabattue dans le
## plan horizontal**.
##
## Le rabattement n'est pas une approximation, c'est une décision de design,
## et elle vient d'un échec mesuré. La lune est rasante (20° au-dessus de
## l'horizon, pour laisser le fond du gouffre à la lave) : un miroir purement
## vertical conserve donc l'inclinaison du rayon incident, qui repart vers le
## bas et plonge dans le sol vingt mètres plus loin. Aucune combinaison de
## crans n'ouvrait la porte, et le test l'a démontré par force brute.
##
## Les miroirs sont donc **taillés pour redresser** : ils captent une lumière
## rasante et la renvoient à l'horizontale. Le joueur ne raisonne alors qu'en
## azimut — ce qui est exactement ce qu'on veut à la manette, où viser en site
## est pénible.
func get_reflection() -> Vector3:
	if _incoming.length_squared() < 0.0001:
		return Vector3.ZERO
	var n: Vector3 = get_normal()
	var reflected: Vector3 = _incoming - 2.0 * _incoming.dot(n) * n
	reflected.y = 0.0
	if reflected.length_squared() < 0.0001:
		# Incidence pile de face : le rayon repartirait par où il est venu.
		return -Vector3(n.x, 0.0, n.z).normalized()
	return reflected.normalized()


func is_lit() -> bool:
	return _lit


## Trace le rayon sortant jusqu'à ce qu'il rencontre quelque chose.
func _refresh_beam() -> void:
	if _beam == null:
		return
	if not _lit:
		_beam.visible = false
		return
	var dir: Vector3 = get_reflection()
	if dir.length_squared() < 0.0001:
		_beam.visible = false
		return

	var origin: Vector3 = get_focus()
	var reach: float = beam_length
	var space: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(origin + dir * 0.6, origin + dir * beam_length)
	# Le décor seul : un rayon qui s'arrêterait sur un joueur clignoterait dès
	# que quelqu'un traverse.
	query.collision_mask = 1
	var hit: Dictionary = space.intersect_ray(query)
	if not hit.is_empty():
		reach = origin.distance_to(hit["position"])

	_beam.visible = true
	_beam.scale = Vector3(1.0, maxf(reach, 0.1), 1.0)
	_beam.position = Vector3(0.0, 2.3, 0.0) + dir * (reach * 0.5)
	# Un CylinderMesh pointe vers +Y : on l'aligne sur la direction du rayon.
	_beam.look_at_from_position(_beam.position + global_position,
		_beam.position + global_position + dir, Vector3.UP)
	_beam.rotate_object_local(Vector3.RIGHT, PI * 0.5)

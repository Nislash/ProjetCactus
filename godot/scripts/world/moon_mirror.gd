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

## Altitude ABSOLUE du plan optique, en mètres.
##
## Tous les miroirs portent leur disque à la même hauteur, sur un mât dont la
## longueur s'adapte au terrain. Ce n'est pas cosmétique : puisqu'ils
## redressent le rayon à l'horizontale, deux miroirs d'altitudes différentes ne
## peuvent PAS se voir — le rayon du premier passe au-dessus ou au-dessous du
## second, indéfiniment. Le premier jet les posait à 2,3 m du sol chacun, sur
## un terrain qui varie de douze mètres : aucune chaîne n'était possible, et
## le test l'a démontré par force brute.
@export var focus_altitude: float = 14.0

## Couche de collision des surfaces optiques — miroirs et sceau.
##
## Séparée du décor pour que le rayon sache CE QU'IL a touché. Un raycast qui
## ne rendrait qu'un point d'impact obligerait à retrouver le nœud par
## proximité, et c'est exactement le genre d'approximation qui rendait le
## comportement bizarre.
const OPTICS_LAYER: int = 16

const MOON := Color(0.85, 0.24, 0.26)
const MOON_HOT := Color(1.00, 0.55, 0.50)

var _disc: MeshInstance3D
var _optic: StaticBody3D
var _beam: MeshInstance3D
var _incoming_beam: MeshInstance3D
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

	# LE MÂT. Sa longueur rattrape le terrain pour que le disque tombe pile au
	# plan optique — c'est lui qui rend la chaîne possible.
	var mast: float = maxf(focus_altitude - global_position.y, 2.0)
	var base := MeshInstance3D.new()
	base.name = "Pied"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 0.35
	base_mesh.bottom_radius = 0.9
	base_mesh.height = mast
	base_mesh.radial_segments = 6
	base.mesh = base_mesh
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.055, 0.045, 0.050)
	stone.roughness = 0.9
	base.material_override = stone
	base.position = Vector3(0.0, mast * 0.5, 0.0)
	add_child(base)

	var body := StaticBody3D.new()
	var col := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.height = mast
	cyl.radius = 0.8
	col.shape = cyl
	col.position = Vector3(0.0, mast * 0.5, 0.0)
	body.add_child(col)
	add_child(body)

	# LA SURFACE OPTIQUE. Un vrai collider sur la couche des miroirs : c'est
	# lui que le rayon touche. Le puzzle ne calcule plus de distances à un axe
	# — il lance un rayon et regarde ce qu'il rencontre, comme la lumière.
	var optic := StaticBody3D.new()
	optic.name = "Surface"
	optic.collision_layer = OPTICS_LAYER
	# Il ne se met en travers de personne : ni du joueur, ni des tirs.
	optic.collision_mask = 0
	var optic_shape := CollisionShape3D.new()
	var plate := BoxShape3D.new()
	plate.size = Vector3(2.7, 2.7, 0.3)
	optic_shape.shape = plate
	optic.add_child(optic_shape)
	optic.position = Vector3(0.0, mast, 0.0)
	add_child(optic)
	_optic = optic

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
	_disc.position = Vector3(0.0, mast, 0.0)
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

	# Le rayon incident, plus fin et plus pâle : c'est de la lumière qui
	# voyage depuis très loin, pas un faisceau concentré.
	_incoming_beam = MeshInstance3D.new()
	_incoming_beam.name = "RayonIncident"
	var in_mesh := CylinderMesh.new()
	in_mesh.top_radius = 0.10
	in_mesh.bottom_radius = 0.10
	in_mesh.height = 1.0
	in_mesh.radial_segments = 6
	_incoming_beam.mesh = in_mesh
	var in_mat := StandardMaterial3D.new()
	in_mat.albedo_color = Color(MOON.r, MOON.g, MOON.b, 0.30)
	in_mat.emission_enabled = true
	in_mat.emission = MOON
	in_mat.emission_energy_multiplier = 1.8
	in_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	in_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	in_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_incoming_beam.material_override = in_mat
	_incoming_beam.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_incoming_beam.visible = false
	add_child(_incoming_beam)


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
	# La surface optique suit : si elle restait fixe, le rayon toucherait un
	# miroir orienté autrement que ce qu'on voit.
	if _optic != null:
		_optic.rotation_degrees = Vector3(0.0, facing_degrees(), 0.0)


func facing_degrees() -> float:
	return 360.0 * float(step) / float(STEPS)


## La normale du miroir, en repère monde. C'est elle qui décide où part le
## rayon.
func get_normal() -> Vector3:
	var a: float = deg_to_rad(facing_degrees())
	return Vector3(sin(a), 0.0, cos(a)).normalized()


## Le centre du miroir — d'où part le rayon réfléchi.
func get_focus() -> Vector3:
	return Vector3(global_position.x, focus_altitude, global_position.z)


## Allume ou éteint le rayon sortant. Piloté par [MoonPuzzle], qui est seul à
## savoir ce que chaque miroir reçoit.
func set_incoming(direction: Vector3, lit: bool) -> void:
	_incoming = direction
	_lit = lit
	if not lit:
		hide_segment()


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


## Dessine le segment de rayon qui part de ce miroir.
##
## C'est le PUZZLE qui fournit la longueur, parce que c'est lui qui a lancé le
## rayon. Le miroir traçait auparavant son propre segment avec son propre
## raycast : les deux calculs pouvaient diverger, et on voyait alors un trait
## s'arrêter là où la logique croyait qu'il continuait.
func draw_segment(direction: Vector3, length: float) -> void:
	if _beam == null:
		return
	if not _lit or length <= 0.05 or direction.length_squared() < 0.0001:
		_beam.visible = false
		return
	_beam.visible = true
	# La transform est CONSTRUITE, pas obtenue par `look_at`.
	#
	# `look_at` oriente l'axe -Z vers la cible, alors qu'un `CylinderMesh`
	# s'étend selon +Y : il faut donc une rotation de rattrapage, et celle qui
	# était appliquée allait dans le mauvais sens. Le rayon restait vertical —
	# c'est-à-dire dans l'orientation par défaut du cylindre, ce qui rendait le
	# bug invisible à la lecture : il ressemblait à un cas non traité plutôt
	# qu'à une rotation inversée.
	#
	# Une base explicite ne peut pas se tromper de sens, et elle gère le cas où
	# la direction est parallèle à la verticale — où `look_at` échoue en
	# silence et laisse la transform inchangée.
	var forward: Vector3 = direction.normalized()
	var up_ref: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var side: Vector3 = up_ref.cross(forward).normalized()
	var normal: Vector3 = forward.cross(side).normalized()
	# Colonnes : X = côté, Y = l'axe du cylindre le long du rayon, Z = normale.
	var basis := Basis(side, forward, normal)

	var mid: Vector3 = Vector3(0.0, focus_altitude - global_position.y, 0.0) \
		+ forward * (length * 0.5)
	_beam.transform = Transform3D(basis.scaled(Vector3(1.0, length, 1.0)), mid)


func hide_segment() -> void:
	if _beam != null:
		_beam.visible = false
	if _incoming_beam != null:
		_incoming_beam.visible = false


## Le rayon qui ARRIVE sur ce miroir, tracé vers le haut en direction de la
## lune.
##
## Il manquait, et son absence rendait le puzzle incompréhensible : on voyait
## un trait sortir d'un miroir sans savoir ce qui l'alimentait. Signalé en
## jeu — « le rayon ne vient pas de la lune ». Il vient de là, maintenant on
## le voit.
func draw_incoming(direction: Vector3, length: float) -> void:
	if _incoming_beam == null:
		return
	if not _lit or direction.length_squared() < 0.0001:
		_incoming_beam.visible = false
		return
	var forward: Vector3 = direction.normalized()
	var up_ref: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var side: Vector3 = up_ref.cross(forward).normalized()
	var normal: Vector3 = forward.cross(side).normalized()
	var basis := Basis(side, forward, normal)
	# Il ARRIVE : son milieu est en amont du miroir.
	var mid: Vector3 = Vector3(0.0, focus_altitude - global_position.y, 0.0) \
		- forward * (length * 0.5)
	_incoming_beam.visible = true
	_incoming_beam.transform = Transform3D(basis.scaled(Vector3(1.0, length, 1.0)), mid)

class_name ArenaBraziers
extends Node3D

## Les brasiers qui s'allument autour de l'arène quand on y arrive.
##
## ## Ce qu'ils font au combat
##
## L'arène est un bol de basalte noir sous une lune rouge : sans eux, on ne
## voit pas ses bords, donc on ne sait pas où l'on peut reculer. Un combat de
## boss où l'on ignore la forme du terrain se joue au hasard.
##
## Allumés en CHAÎNE plutôt que d'un coup, et dans le sens de la marche : le
## regard suit le feu qui court, et fait le tour de l'arène sans qu'on ait eu à
## le demander. C'est la façon la moins coûteuse de montrer un espace.
##
## ## Pourquoi ils ne s'allument pas d'avance
##
## Parce que l'arrivée doit être un moment. Une salle déjà éclairée quand on y
## tombe est une salle qu'on traverse ; une salle qui s'allume est une salle qui
## vous attendait.

signal lit()

@export var centre: Vector2 = Vector2.ZERO
@export var radius: float = 30.0
@export var count: int = 10

## Altitude du sol de l'arène. Les brasiers s'y posent.
@export var floor_altitude: float = 0.0

## Secondes entre deux allumages.
@export var chain_delay: float = 0.14

const FLAME := Color(1.000, 0.478, 0.184)
const STONE := Color(0.052, 0.044, 0.048)

var _flames: Array[Node3D] = []
var _lit: bool = false


func _ready() -> void:
	_build()


func _build() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.9

	for i in count:
		var a: float = TAU * float(i) / float(count)
		var at := Vector3(centre.x + cos(a) * radius, floor_altitude,
			centre.y + sin(a) * radius)

		var post := MeshInstance3D.new()
		post.name = "Pied_%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.42
		mesh.bottom_radius = 0.78
		mesh.height = 3.4
		mesh.radial_segments = 6
		post.mesh = mesh
		post.material_override = stone
		add_child(post)
		post.global_position = at + Vector3(0.0, 1.7, 0.0)

		var bowl := MeshInstance3D.new()
		bowl.name = "Vasque_%d" % i
		var bowl_mesh := CylinderMesh.new()
		bowl_mesh.top_radius = 1.05
		bowl_mesh.bottom_radius = 0.5
		bowl_mesh.height = 0.7
		bowl_mesh.radial_segments = 8
		bowl.mesh = bowl_mesh
		bowl.material_override = stone
		add_child(bowl)
		bowl.global_position = at + Vector3(0.0, 3.6, 0.0)

		# LA FLAMME. Elle est éteinte au départ : invisible ET sans lumière.
		# Masquer seulement le maillage laisserait la lampe éclairer une vasque
		# vide, ce qui se voit tout de suite.
		var flame := Node3D.new()
		flame.name = "Flamme_%d" % i
		add_child(flame)
		flame.global_position = at + Vector3(0.0, 4.1, 0.0)

		var fire := MeshInstance3D.new()
		fire.name = "Feu"
		var fire_mesh := SphereMesh.new()
		fire_mesh.radius = 0.85
		fire_mesh.height = 2.2
		fire_mesh.radial_segments = 10
		fire_mesh.rings = 6
		fire.mesh = fire_mesh
		var hot := StandardMaterial3D.new()
		hot.albedo_color = FLAME
		hot.emission_enabled = true
		hot.emission = Color(1.0, 0.78, 0.42)
		hot.emission_energy_multiplier = 4.0
		hot.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		fire.material_override = hot
		flame.add_child(fire)

		var light := OmniLight3D.new()
		light.name = "Lueur"
		light.light_color = FLAME
		light.light_energy = 0.0
		light.omni_range = 26.0
		light.shadow_enabled = false
		flame.add_child(light)

		flame.visible = false
		_flames.append(flame)


## Allume les brasiers l'un après l'autre, dans le sens de la marche.
func light_up() -> void:
	if _lit:
		return
	_lit = true
	for i in _flames.size():
		var flame: Node3D = _flames[i]
		get_tree().create_timer(float(i) * chain_delay).timeout.connect(
			func() -> void:
				if not is_instance_valid(flame):
					return
				flame.visible = true
				var light: OmniLight3D = flame.get_node_or_null("Lueur") as OmniLight3D
				if light == null:
					return
				var tween: Tween = flame.create_tween()
				# Un sursaut puis le régime : une flamme qui s'établit
				# proprement ressemble à un interrupteur.
				tween.tween_property(light, "light_energy", 5.5, 0.12)
				tween.tween_property(light, "light_energy", 3.2, 0.45))
	get_tree().create_timer(float(_flames.size()) * chain_delay + 0.6).timeout.connect(
		func() -> void: lit.emit())
	print("[ArenaBraziers] les brasiers s'allument.")


func is_lit() -> bool:
	return _lit

class_name FragileCrystal
extends StaticBody3D

## Le cristal laiteux « visiblement cassable » de l'Antichambre (B3, B4).
##
## Il fonde une grammaire qui servira tout le jeu : **opale veinée de
## fissures = ça se brise**. Elle s'apprend ici, sur un obstacle sans enjeu,
## pour être lue plus tard au premier coup d'œil.
##
## Il se construit lui-même — maillage, collision, jauge — pour que
## l'Antichambre puisse en semer où elle veut sans qu'aucune position ne soit
## écrite dans une scène. Les tools d'édition ne persistent pas les Vector3,
## et de toute façon un beat qu'on déplace ne doit pas demander de rouvrir
## Godot.

signal shattered(by: Node)

const MATERIAL_PATH := "res://data/levels/fragile_crystal_material.tres"

## Peu de PV : ce n'est pas un combat, c'est une porte. Un tir suffit.
@export var max_health: int = 1
@export var height: float = 2.6
@export var radius: float = 0.85

var _health: HealthComponent
var _material: ShaderMaterial
var _mesh_instance: MeshInstance3D


func _ready() -> void:
	add_to_group(&"fragile_crystals")
	_build_body()
	_build_health()


func _build_body() -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius * 0.35
	mesh.bottom_radius = radius
	mesh.height = height
	mesh.radial_segments = 7
	mesh.rings = 1

	_mesh_instance = MeshInstance3D.new()
	_mesh_instance.name = "Mesh"
	_mesh_instance.mesh = mesh
	_mesh_instance.position = Vector3(0.0, height * 0.5, 0.0)
	var mat: Resource = load(MATERIAL_PATH)
	if mat is ShaderMaterial:
		# Dupliqué : la fissuration de CE cristal ne doit pas fissurer les autres.
		_material = (mat as ShaderMaterial).duplicate() as ShaderMaterial
		_mesh_instance.material_override = _material
	add_child(_mesh_instance)

	var shape := CylinderShape3D.new()
	shape.height = height
	shape.radius = radius * 0.8
	var col := CollisionShape3D.new()
	col.name = "Shape"
	col.shape = shape
	col.position = Vector3(0.0, height * 0.5, 0.0)
	add_child(col)


func _build_health() -> void:
	# Un HealthComponent enfant suffit : c'est ce que les projectiles et le
	# hitscan cherchent pour savoir si une collision fait des dégâts.
	_health = HealthComponent.new()
	_health.name = "Health"
	_health.max_health = max_health
	_health.current_health = max_health
	add_child(_health)
	_health.died.connect(_on_died)
	_health.damaged.connect(_on_damaged)


## Le feedback de visée : le cristal scintille quand un tir l'effleure, avant
## même qu'il cède. C'est ce qui remplace un tutoriel de visée.
func _on_damaged(_amount: int, _source: Node) -> void:
	if _material == null:
		return
	var tw: Tween = create_tween()
	tw.tween_method(
		func(v: float) -> void: _material.set_shader_parameter("fracture", v),
		0.0, 1.0, 0.08)


func _on_died(source: Node) -> void:
	shattered.emit(source)
	_burst()


## La pluie d'éclats. Pas de système de particules configuré en scène : une
## poignée de fragments physiques se lit mieux et coûte moins qu'un VFX à
## régler, et ils disparaissent d'eux-mêmes.
func _burst() -> void:
	var parent: Node = get_parent()
	if parent == null:
		queue_free()
		return
	var origin: Vector3 = global_position + Vector3(0.0, height * 0.5, 0.0)
	for i in 9:
		var shard := MeshInstance3D.new()
		var m := BoxMesh.new()
		var s: float = randf_range(0.10, 0.26)
		m.size = Vector3(s, s * randf_range(1.5, 3.0), s)
		shard.mesh = m
		if _material != null:
			shard.material_override = _material
		parent.add_child(shard)
		shard.global_position = origin + Vector3(
			randf_range(-0.4, 0.4), randf_range(-0.8, 0.8), randf_range(-0.4, 0.4))
		var dir := Vector3(randf_range(-1.0, 1.0), randf_range(0.4, 1.0), randf_range(-1.0, 1.0)).normalized()
		var tw: Tween = shard.create_tween()
		tw.set_parallel(true)
		tw.tween_property(shard, "global_position",
			shard.global_position + dir * randf_range(1.5, 3.5), 0.7)
		tw.tween_property(shard, "scale", Vector3.ZERO, 0.7)
		tw.chain().tween_callback(shard.queue_free)
	queue_free()


func get_health() -> HealthComponent:
	return _health

class_name ForgeLedge
extends Node3D

## Une plateforme de roche posée sur le monde, avec sa collision et son
## navmesh.
##
## ## Pourquoi elle n'est pas dans le terrain
##
## Le palier de la cascade est au-dessus d'une coulée : le champ de hauteurs ne
## peut pas l'y mettre, puisqu'il ne connaît qu'une altitude par (X, Z) et que
## cette altitude est déjà celle du lit. Tenter de l'obtenir en relevant le
## terrain remplacerait la coulée par de la roche à cet endroit — on perdrait
## exactement ce qui fait que le saut compte.

@export var centre: Vector2 = Vector2.ZERO
@export var altitude: float = 0.0
@export var half_extent: Vector2 = Vector2(10.0, 7.0)
@export var thickness: float = 2.2

const ROCK_PATH := "res://data/levels/forge_rock_material.tres"


func _ready() -> void:
	var rock: Material = load(ROCK_PATH) as Material
	if rock == null:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = Color(0.048, 0.040, 0.044)
		flat.roughness = 0.93
		rock = flat

	var size := Vector3(half_extent.x * 2.0, thickness, half_extent.y * 2.0)
	var slab := MeshInstance3D.new()
	slab.name = "Dalle"
	var mesh := BoxMesh.new()
	mesh.size = size
	slab.mesh = mesh
	slab.material_override = rock
	add_child(slab)
	# Le DESSUS de la dalle est à `altitude` : c'est là qu'on marche, et c'est
	# donc ce que les autres objets doivent pouvoir viser sans corriger d'une
	# demi-épaisseur.
	slab.global_position = Vector3(centre.x, altitude - thickness * 0.5, centre.y)

	var body := StaticBody3D.new()
	body.name = "ColDalle"
	body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER \
		| CavernTerrainBuilder.NAVMESH_SOURCE_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = slab.global_position

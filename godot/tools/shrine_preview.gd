extends Node3D

## Aperçu des deux sanctuaires de cristal, côte à côte (E4).
##
## Les regarder isolément plutôt que de les chercher dans la caverne : on juge
## la silhouette, l'échelle relative au joueur et la lisibilité de la lueur sans
## que le décor ne s'en mêle.
##
## Lancer `tools/shrine_preview.tscn` depuis l'éditeur.

const RELIC_SHRINE := "res://scenes/world/relic_chest.tscn"
const WEAPON_SHRINE := "res://scenes/world/start_chest.tscn"
const ENVIRONMENT := "res://data/levels/level01_cavern_environment.tres"
const ROCK_MATERIAL := "res://data/levels/cavern_floor_material.tres"

## Repère d'échelle : un joueur mesure 1,8 m. Sans lui, impossible de juger si
## un sanctuaire est imposant ou ridicule.
const PLAYER_HEIGHT := 1.8


func _ready() -> void:
	_build_environment()
	_build_ground()
	_build_reference_figure(Vector3(-2.6, 0.0, 0.0))
	_place(RELIC_SHRINE, Vector3(0.0, 0.0, 0.0), "sorts / bonus")
	_place(WEAPON_SHRINE, Vector3(2.6, 0.0, 0.0), "armes")

	var camera := Camera3D.new()
	camera.current = true
	camera.fov = 50.0
	camera.position = Vector3(0.4, 1.7, 5.6)
	camera.look_at(Vector3(0.4, 1.0, 0.0), Vector3.UP)
	add_child(camera)


func _build_environment() -> void:
	var world_env := WorldEnvironment.new()
	world_env.environment = load(ENVIRONMENT) as Environment
	add_child(world_env)

	# Même appoint directionnel que la caverne : on juge les sanctuaires sous
	# l'éclairage où ils vivront, pas sous un éclairage de studio.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-62.0, 28.0, 0.0)
	fill.light_color = Color(0.52, 0.64, 0.84)
	fill.light_energy = 0.42
	fill.shadow_enabled = true
	add_child(fill)


func _build_ground() -> void:
	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(40.0, 40.0)
	ground.mesh = plane
	ground.material_override = load(ROCK_MATERIAL) as Material
	add_child(ground)


## Silhouette de la taille d'un joueur, en gris neutre.
func _build_reference_figure(at: Vector3) -> void:
	var figure := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = 0.4
	capsule.height = PLAYER_HEIGHT
	figure.mesh = capsule
	figure.position = at + Vector3(0.0, PLAYER_HEIGHT * 0.5, 0.0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.30, 0.32, 0.36)
	material.roughness = 0.9
	figure.material_override = material
	add_child(figure)


func _place(scene_path: String, at: Vector3, label: String) -> void:
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		push_error("Aperçu : scène introuvable %s" % scene_path)
		return
	var instance: Node3D = packed.instantiate() as Node3D
	add_child(instance)
	instance.position = at
	print("[aperçu] %s -> %s" % [label, scene_path.get_file()])

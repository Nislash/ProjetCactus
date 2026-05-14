extends Node

## Spawne des ennemis sur les EnemySpawnPoints du level au démarrage. M1 =
## un seul wave fixe, pas de respawn. M2+ : vagues, waves manager.
##
## Convention level : nodes Marker3D enfants d'un Node3D "EnemySpawnPoints".
## Le nom du marker préfixé "Boss" est traité comme boss spawn (M3),
## sinon mêlée par défaut. Les markers contenant "B" (Combat1) et "C"
## (Combat2) reçoivent une vague mixte mêlée + ranged.

@export var enemy_melee_scene: PackedScene = preload("res://scenes/enemies/enemy_melee.tscn")
@export var enemy_ranged_scene: PackedScene = preload("res://scenes/enemies/enemy_ranged.tscn")
@export var world_path: NodePath
## Si vrai, spawne au _ready. Sinon il faut appeler spawn_all() manuellement.
@export var auto_spawn: bool = true

var _world: Node3D


func _ready() -> void:
	_world = get_node_or_null(world_path) as Node3D
	if _world == null:
		_world = get_parent().get_node_or_null("World") as Node3D
	if auto_spawn:
		# Laisse une frame au level pour s'initialiser.
		await get_tree().process_frame
		spawn_all()


func spawn_all() -> void:
	if _world == null:
		push_warning("[EnemySpawner] Pas de World trouvé. Aucun ennemi spawné.")
		return
	var spawn_root: Node = _world.find_child("EnemySpawnPoints", true, false)
	if spawn_root == null:
		push_warning("[EnemySpawner] Pas d'EnemySpawnPoints dans le World.")
		return
	var spawned: int = 0
	for marker in spawn_root.get_children():
		if not (marker is Marker3D):
			continue
		var enemy_scene: PackedScene = _scene_for_marker(marker.name)
		if enemy_scene == null:
			continue
		var enemy: EnemyBase = enemy_scene.instantiate() as EnemyBase
		_world.add_child(enemy)
		enemy.global_position = (marker as Marker3D).global_position
		spawned += 1
	print("[EnemySpawner] Spawné %d ennemis." % spawned)


func _scene_for_marker(marker_name: String) -> PackedScene:
	# Conventions :
	# - "Boss*" : boss (M3, on n'a pas encore → on skip)
	# - "*B0", "*B1", ... : Room Combat1 — mêlée
	# - "*C0", "*C1", ... : Room Combat2 — ranged
	# - sinon : mêlée par défaut
	if marker_name.begins_with("Boss"):
		return null
	if marker_name.find("C") != -1 and marker_name.find("Boss") == -1:
		return enemy_ranged_scene
	return enemy_melee_scene

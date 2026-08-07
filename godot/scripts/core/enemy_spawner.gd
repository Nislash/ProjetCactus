extends Node

## Spawne des ennemis sur les EnemySpawnPoints du level au démarrage. M1 =
## un seul wave fixe, pas de respawn. M2+ : vagues, waves manager.
##
## Convention level : nodes Marker3D enfants d'un Node3D "EnemySpawnPoints".
##
## L'archétype se déclare de deux façons, la première primant :
##
## 1. PAR GROUPE (recommandé) — le marker appartient à `enemy_melee`,
##    `enemy_ranged` ou `enemy_boss`. Explicite, et le marker peut alors porter
##    un nom qui dit ce qu'il fait plutôt que ce qu'il spawne.
##
## 2. PAR NOM (hérité) — "Boss*" est ignoré, un nom contenant "C" donne du
##    ranged, tout le reste de la mêlée. Conservé pour `level_01_poc`, qui
##    l'utilise. Fragile par nature : n'importe quel "C" dans le nom bascule
##    l'archétype. Ne pas l'employer pour de nouveaux niveaux.

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
		var enemy_scene: PackedScene = _scene_for_marker(marker as Marker3D)
		if enemy_scene == null:
			continue
		var enemy: EnemyBase = enemy_scene.instantiate() as EnemyBase
		_world.add_child(enemy)
		enemy.global_position = (marker as Marker3D).global_position
		spawned += 1
	print("[EnemySpawner] Spawné %d ennemis." % spawned)


## Groupes d'archétype, prioritaires sur la convention de nommage héritée.
const GROUP_MELEE := &"enemy_melee"
const GROUP_RANGED := &"enemy_ranged"
const GROUP_BOSS := &"enemy_boss"


func _scene_for_marker(marker: Marker3D) -> PackedScene:
	# 1. Groupe explicite.
	if marker.is_in_group(GROUP_BOSS):
		return null
	if marker.is_in_group(GROUP_RANGED):
		return enemy_ranged_scene
	if marker.is_in_group(GROUP_MELEE):
		return enemy_melee_scene

	# 2. Repli sur la convention de nommage (cf entête).
	var marker_name: String = marker.name
	if marker_name.begins_with("Boss"):
		return null
	if marker_name.find("C") != -1:
		return enemy_ranged_scene
	return enemy_melee_scene

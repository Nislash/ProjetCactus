## DungeonBuilder — runtime async qui matérialise une [LevelLayout] en GridMap 3D.
##
## Usage typique côté lobby (cf scripts/core/lobby_controller.gd) :
##   var builder := DungeonBuilder.new()
##   add_child(builder)
##   builder.layout = load("res://data/levels/level_1.tres") as LevelLayout
##   builder.mesh_library = load("res://scenes/world/dungeon_mesh_library.tres")
##   await builder.build_async()
##
## Le builder construit :
##  - Une GridMap remplie avec les meshes de la MeshLibrary (autotiling natif).
##  - Un nœud "Entities" peuplé d'instances de scènes (spawn, ennemis, loot,
##    triggers puzzle, boss arena, fragment méta).
##
## Génération non-bloquante : `await get_tree().process_frame` toutes les
## `CELLS_PER_FRAME` cellules.
class_name DungeonBuilder
extends Node3D

## Tile IDs (synchro avec tools/dungeon_pipeline/export/godot_resource.py).
const TILE_VOID: int = 0
const TILE_FLOOR: int = 1
const TILE_WALL: int = 2
const TILE_CORRIDOR: int = 3
const TILE_SECRET: int = 4
const TILE_DOOR: int = 5
const TILE_BOSS_DOOR: int = 6
const TILE_SECRET_DOOR: int = 7
const TILE_STAIR_UP: int = 8
const TILE_STAIR_DOWN: int = 9
const TILE_DROP: int = 10
const TILE_DROP_LANDING: int = 11
const TILE_JUMP_PAD: int = 12
const TILE_DRIFT: int = 13

const CELLS_PER_FRAME: int = 200

## Resource produite par la pipeline.
@export var layout: LevelLayout

## MeshLibrary indexée par tile_id (Godot mappe naturellement set_cell_item).
@export var mesh_library: MeshLibrary

## Scènes pour le contenu instanciable. Chaque entrée = path vers une PackedScene.
@export var spawn_scene: PackedScene
@export var enemy_scenes: Dictionary = {}  ## hint_name -> PackedScene
@export var loot_scene: PackedScene
@export var puzzle_trigger_scenes: Dictionary = {}  ## "P1" -> PackedScene
@export var mini_boss_scene: PackedScene
@export var meta_fragment_scene: PackedScene
@export var checkpoint_scene: PackedScene
@export var boss_door_scene: PackedScene

signal build_completed
signal build_failed(reason: String)

var _gridmap: GridMap
var _entities_root: Node3D


func _ready() -> void:
	_gridmap = GridMap.new()
	_gridmap.name = "GridMap"
	add_child(_gridmap)

	_entities_root = Node3D.new()
	_entities_root.name = "Entities"
	add_child(_entities_root)


## Lance la construction. À await depuis l'appelant.
func build_async() -> void:
	if layout == null:
		emit_signal("build_failed", "layout absent")
		return
	if mesh_library == null:
		push_warning("DungeonBuilder: mesh_library absent — GridMap restera vide")
	_gridmap.cell_size = layout.cell_size
	if mesh_library != null:
		_gridmap.mesh_library = mesh_library

	await _build_cells_async()
	_spawn_entities()
	emit_signal("build_completed")


func _build_cells_async() -> void:
	var size: Vector3i = layout.grid_size
	var processed: int = 0
	for y in range(size.y):
		for z in range(size.z):
			for x in range(size.x):
				var tid: int = layout.get_tile(x, y, z)
				if tid != TILE_VOID:
					_gridmap.set_cell_item(Vector3i(x, y, z), tid)
				processed += 1
				if processed % CELLS_PER_FRAME == 0:
					await get_tree().process_frame


func _spawn_entities() -> void:
	# Spawn joueurs : marker au centre de la spawn_room (pas d'instanciation
	# d'un PlayerController ici, c'est le PlayerManager qui s'en charge).
	if layout.spawn_room in layout.rooms:
		var sr: Dictionary = layout.rooms[layout.spawn_room]
		var spawn_pos: Vector3 = _grid_to_world(
			sr["x"] + int(sr["w"]) / 2,
			sr["y"],
			sr["z"] + int(sr["d"]) / 2,
		)
		var spawn_marker := Marker3D.new()
		spawn_marker.name = "PlayerSpawn"
		spawn_marker.position = spawn_pos
		_entities_root.add_child(spawn_marker)
		if spawn_scene != null:
			var inst := spawn_scene.instantiate()
			inst.position = spawn_pos
			_entities_root.add_child(inst)

	# Boss doors : instancie une porte interactive là où le tile BOSS_DOOR est posé.
	for door in layout.doors:
		if not door.get("locked", false):
			continue
		if boss_door_scene == null:
			continue
		var inst := boss_door_scene.instantiate()
		inst.position = _grid_to_world(door["x"], door["y"], door["z"])
		if inst.has_method("setup"):
			inst.call("setup", door.get("unlock_keys", []))
		_entities_root.add_child(inst)

	# Contents par room : itère sur les rooms qui ont des entrées dans contents.
	for room_id in layout.contents.keys():
		var content: Dictionary = layout.contents[room_id]
		if not (room_id in layout.rooms):
			continue
		var rm: Dictionary = layout.rooms[room_id]
		var room_center: Vector3 = _grid_to_world(
			rm["x"] + int(rm["w"]) / 2,
			rm["y"],
			rm["z"] + int(rm["d"]) / 2,
		)
		_instance_if_present(content, "mini_boss", mini_boss_scene, room_center)
		_instance_if_present(content, "meta_fragment", meta_fragment_scene, room_center)
		_instance_if_present(content, "checkpoint", checkpoint_scene, room_center)
		if content.get("loot_major", 0) > 0 and loot_scene != null:
			var inst := loot_scene.instantiate()
			inst.position = room_center
			_entities_root.add_child(inst)
		for trig_id in content.get("puzzle_triggers", []):
			var s: PackedScene = puzzle_trigger_scenes.get(trig_id, null)
			if s != null:
				var inst2 := s.instantiate()
				inst2.position = room_center
				_entities_root.add_child(inst2)


func _instance_if_present(content: Dictionary, key: String, scene: PackedScene, pos: Vector3) -> void:
	if scene == null:
		return
	if not content.get(key, false):
		return
	var inst := scene.instantiate()
	inst.position = pos
	_entities_root.add_child(inst)


func _grid_to_world(x: int, y: int, z: int) -> Vector3:
	return Vector3(
		(float(x) + 0.5) * layout.cell_size.x,
		(float(y) + 0.5) * layout.cell_size.y,
		(float(z) + 0.5) * layout.cell_size.z,
	)

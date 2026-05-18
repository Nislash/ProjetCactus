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
		# Voie rapide test : MeshLibrary auto-générée en BoxMesh colorés.
		mesh_library = _make_default_mesh_library()
	_gridmap.cell_size = layout.cell_size
	_gridmap.mesh_library = mesh_library

	_add_default_lighting()
	await _build_cells_async()
	_spawn_entities()
	_add_floor_colliders()
	emit_signal("build_completed")


## Ajoute un éclairage minimaliste (sun + ambient) pour que la scène ne soit
## pas noire. À remplacer par un WorldEnvironment thématique par niveau plus
## tard (caverne sombre, dôme céleste, néon spatial, etc.).
func _add_default_lighting() -> void:
	# WorldEnvironment : ambient + sky de base.
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.35, 0.5, 0.7)
	sky_mat.sky_horizon_color = Color(0.7, 0.7, 0.65)
	sky_mat.ground_horizon_color = Color(0.3, 0.25, 0.2)
	sky_mat.ground_bottom_color = Color(0.1, 0.08, 0.06)
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.6, 0.6, 0.7)
	env.ambient_light_energy = 0.8
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var world_env := WorldEnvironment.new()
	world_env.name = "WorldEnvironment"
	world_env.environment = env
	add_child(world_env)

	# Soleil principal : DirectionalLight3D inclinée.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation_degrees = Vector3(-55, -30, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

	# Lumière d'appoint hémisphérique pour adoucir les ombres (juste un point
	# light en haut au centre du dungeon).
	var size: Vector3i = layout.grid_size
	var cs: Vector3 = layout.cell_size
	var fill := OmniLight3D.new()
	fill.name = "FillLight"
	fill.position = Vector3(
		size.x * cs.x * 0.5,
		size.y * cs.y + 10.0,
		size.z * cs.z * 0.5,
	)
	fill.omni_range = max(size.x * cs.x, size.z * cs.z) * 1.5
	fill.light_energy = 0.6
	fill.light_color = Color(0.95, 0.92, 0.85)
	add_child(fill)


## Génère une MeshLibrary minimaliste : 1 BoxMesh par tile_id, coloré pour
## qu'on distingue visuellement les types. Pour test/dev uniquement — à
## remplacer par une vraie MeshLibrary d'assets quand on aura les meshes.
func _make_default_mesh_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	# Couleurs par tile_id. Hauteurs : sols 0.2m, murs 3m (= cell_size.y).
	var defs := {
		TILE_FLOOR:       {"color": Color(0.7, 0.7, 0.7), "h": 0.1, "wall": false},
		TILE_WALL:        {"color": Color(0.35, 0.25, 0.2), "h": 3.0, "wall": true},
		TILE_CORRIDOR:    {"color": Color(0.55, 0.55, 0.6), "h": 0.1, "wall": false},
		TILE_SECRET:      {"color": Color(0.45, 0.3, 0.55), "h": 0.1, "wall": false},
		TILE_DOOR:        {"color": Color(0.3, 0.5, 0.8), "h": 0.3, "wall": false},
		TILE_BOSS_DOOR:   {"color": Color(0.85, 0.15, 0.15), "h": 3.0, "wall": true},
		TILE_SECRET_DOOR: {"color": Color(0.5, 0.2, 0.6), "h": 3.0, "wall": true},
		TILE_STAIR_UP:    {"color": Color(0.95, 0.85, 0.3), "h": 1.2, "wall": false},
		TILE_STAIR_DOWN:  {"color": Color(0.85, 0.55, 0.2), "h": 1.2, "wall": false},
		TILE_DROP:        {"color": Color(1.0, 0.4, 0.0), "h": 0.1, "wall": false},
		TILE_DROP_LANDING:{"color": Color(0.7, 0.3, 0.0), "h": 0.1, "wall": false},
		TILE_JUMP_PAD:    {"color": Color(0.2, 0.8, 0.2), "h": 0.3, "wall": false},
		TILE_DRIFT:       {"color": Color(0.3, 0.3, 0.55), "h": 0.1, "wall": false},
	}
	var cs := layout.cell_size
	for tid in defs.keys():
		var spec: Dictionary = defs[tid]
		var box := BoxMesh.new()
		var h: float = spec["h"]
		box.size = Vector3(cs.x * 0.98, h, cs.z * 0.98)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = spec["color"]
		mat.roughness = 0.85
		# Émission légère pour les transitions verticales (visibilité).
		if tid in [TILE_STAIR_UP, TILE_STAIR_DOWN, TILE_JUMP_PAD, TILE_DROP, TILE_BOSS_DOOR]:
			mat.emission_enabled = true
			mat.emission = spec["color"]
			mat.emission_energy_multiplier = 0.4
		box.material = mat
		var id := lib.get_last_unused_item_id()
		# Force un id explicite : on veut tid en clé exacte pour set_cell_item.
		lib.create_item(tid)
		lib.set_item_name(tid, _tile_name(tid))
		lib.set_item_mesh(tid, box)
		# Offset Y pour aligner le mesh à la cellule : sol au bas, mur centré.
		var y_offset: float = h * 0.5 - cs.y * 0.5
		if spec["wall"]:
			y_offset = 0.0  # centré dans la cellule
		var xform := Transform3D(Basis(), Vector3(0, y_offset, 0))
		lib.set_item_mesh_transform(tid, xform)
	return lib


func _tile_name(tid: int) -> String:
	match tid:
		TILE_FLOOR:       return "floor"
		TILE_WALL:        return "wall"
		TILE_CORRIDOR:    return "corridor"
		TILE_SECRET:      return "secret"
		TILE_DOOR:        return "door"
		TILE_BOSS_DOOR:   return "boss_door"
		TILE_SECRET_DOOR: return "secret_door"
		TILE_STAIR_UP:    return "stair_up"
		TILE_STAIR_DOWN:  return "stair_down"
		TILE_DROP:        return "drop"
		TILE_DROP_LANDING:return "drop_landing"
		TILE_JUMP_PAD:    return "jump_pad"
		TILE_DRIFT:       return "drift"
		_: return "tile_%d" % tid


## Ajoute des collisions box invisibles sur les murs pour que le player ne
## traverse pas. Solution rapide : un StaticBody3D par cellule WALL.
## Pas optimal pour la perf mais OK pour validation visuelle.
func _add_floor_colliders() -> void:
	var size: Vector3i = layout.grid_size
	var cs: Vector3 = layout.cell_size
	# Un grand sol invisible par strate pour empêcher de tomber.
	for y in range(size.y):
		var floor_body := StaticBody3D.new()
		floor_body.name = "FloorCollider_y%d" % y
		var shape_node := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(size.x * cs.x, 0.2, size.z * cs.z)
		shape_node.shape = shape
		shape_node.position = Vector3(
			size.x * cs.x * 0.5,
			y * cs.y - cs.y * 0.5 + 0.1,
			size.z * cs.z * 0.5,
		)
		floor_body.add_child(shape_node)
		add_child(floor_body)
	# Walls : un StaticBody3D par cellule WALL.
	var walls_body := StaticBody3D.new()
	walls_body.name = "Walls"
	add_child(walls_body)
	for y in range(size.y):
		for z in range(size.z):
			for x in range(size.x):
				var tid := layout.get_tile(x, y, z)
				if tid != TILE_WALL and tid != TILE_BOSS_DOOR and tid != TILE_SECRET_DOOR:
					continue
				var shape_node := CollisionShape3D.new()
				var shape := BoxShape3D.new()
				shape.size = Vector3(cs.x, cs.y, cs.z)
				shape_node.shape = shape
				shape_node.position = Vector3(
					(float(x) + 0.5) * cs.x,
					(float(y) + 0.5) * cs.y,
					(float(z) + 0.5) * cs.z,
				)
				walls_body.add_child(shape_node)


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
	# Spawn joueurs : crée la structure attendue par SplitScreenManager :
	# PlayerSpawnPoints/Spawn0..Spawn3 (cf split_screen_manager.gd).
	if layout.spawn_room in layout.rooms:
		var sr: Dictionary = layout.rooms[layout.spawn_room]
		var center: Vector3 = _grid_to_world(
			sr["x"] + int(sr["w"]) / 2,
			sr["y"],
			sr["z"] + int(sr["d"]) / 2,
		)
		# Léger Y au-dessus du sol pour pas spawner dans le mesh.
		center.y += 0.5
		var spawns_root := Node3D.new()
		spawns_root.name = "PlayerSpawnPoints"
		_entities_root.add_child(spawns_root)
		var offsets := [
			Vector3(-1.0, 0, -1.0),
			Vector3( 1.0, 0, -1.0),
			Vector3(-1.0, 0,  1.0),
			Vector3( 1.0, 0,  1.0),
		]
		for i in range(4):
			var m := Marker3D.new()
			m.name = "Spawn%d" % i
			m.position = center + offsets[i]
			spawns_root.add_child(m)

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

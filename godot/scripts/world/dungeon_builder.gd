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

## Chemins par défaut. Si non override par scène appelante, le builder utilise
## les paths suivants pour instancier les entités du niveau.
const DEFAULT_LEVER_SCENE := "res://scenes/world/lever.tscn"
const DEFAULT_ENEMY_MELEE := "res://scenes/enemies/enemy_melee.tscn"
const DEFAULT_ENEMY_RANGED := "res://scenes/enemies/enemy_ranged.tscn"
const DEFAULT_BOSS_SCENE := "res://scenes/boss/boss_golem.tscn"

## Scènes pour le contenu instanciable. Chaque entrée = path vers une PackedScene.
@export var spawn_scene: PackedScene
@export var loot_scene: PackedScene
@export var mini_boss_scene: PackedScene
@export var meta_fragment_scene: PackedScene
@export var checkpoint_scene: PackedScene
@export var boss_door_scene: PackedScene
## Si null → chargé depuis DEFAULT_BOSS_SCENE au _ready.
@export var boss_scene: PackedScene
## Si null → chargé depuis DEFAULT_LEVER_SCENE (cristaux à briser pour N1, etc.).
@export var puzzle_trigger_scene: PackedScene
## Si null → chargés depuis DEFAULT_ENEMY_MELEE/RANGED.
@export var enemy_melee_scene: PackedScene
@export var enemy_ranged_scene: PackedScene

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

	# Charge les scenes par défaut si non override.
	if puzzle_trigger_scene == null:
		puzzle_trigger_scene = load(DEFAULT_LEVER_SCENE) as PackedScene
	if enemy_melee_scene == null:
		enemy_melee_scene = load(DEFAULT_ENEMY_MELEE) as PackedScene
	if enemy_ranged_scene == null:
		enemy_ranged_scene = load(DEFAULT_ENEMY_RANGED) as PackedScene
	if boss_scene == null:
		boss_scene = load(DEFAULT_BOSS_SCENE) as PackedScene


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
	_add_stair_teleporters()
	emit_signal("build_completed")


## Pour chaque transition verticale (stairs/ladder/elevator/jump/drop),
## place une Area3D au-dessus de la cellule pos_from. Quand le joueur entre
## dedans, il est téléporté à la position pos_to (strate cible).
##
## Solution MVP : pas de vraies pentes 3D, c'est un téléport instantané.
## À remplacer par des MeshInstance3D inclinés + trous dans le sol plus tard.
func _add_stair_teleporters() -> void:
	var cs: Vector3 = layout.cell_size
	for stair in layout.stairs:
		var kind: String = stair.get("kind", "stairs")
		# zero_g_drift est aussi dans layout.stairs mais on ne le pose pas
		# comme téléporteur (déplacement libre en N8 par design).
		if kind == "zero_g_drift":
			continue

		var from_pos := Vector3(
			(float(stair["from_x"]) + 0.5) * cs.x,
			float(stair["from_y"]) * cs.y + 1.0,
			(float(stair["from_z"]) + 0.5) * cs.z,
		)
		var to_pos := Vector3(
			(float(stair["to_x"]) + 0.5) * cs.x,
			float(stair["to_y"]) * cs.y + 1.0,
			(float(stair["to_z"]) + 0.5) * cs.z,
		)
		_spawn_teleporter(from_pos, to_pos, "%s_%s_to_%s" % [kind, stair["from_room"], stair["to_room"]])
		# Bidirectionnel sauf one-way drop.
		if kind != "one_way_drop":
			_spawn_teleporter(to_pos, from_pos, "%s_%s_to_%s_back" % [kind, stair["to_room"], stair["from_room"]])


func _spawn_teleporter(from_pos: Vector3, to_pos: Vector3, label: String) -> void:
	var area := Area3D.new()
	area.name = "Teleport_" + label
	area.position = from_pos
	# Cooldown pour éviter un ping-pong infini.
	area.set_meta("target", to_pos)
	area.set_meta("cooldown_until", 0.0)
	var shape_node := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(layout.cell_size.x * 0.8, 2.5, layout.cell_size.z * 0.8)
	shape_node.shape = box
	area.add_child(shape_node)
	area.body_entered.connect(_on_teleporter_body_entered.bind(area))
	_entities_root.add_child(area)


func _on_teleporter_body_entered(body: Node, area: Area3D) -> void:
	# Évite la téléport en boucle : cooldown 0.5s après chaque téléport.
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < float(area.get_meta("cooldown_until", 0.0)):
		return
	if not (body is CharacterBody3D):
		return
	var target: Vector3 = area.get_meta("target", Vector3.ZERO)
	# Met le joueur au target. set_meta cooldown sur l'area cible aussi pour
	# éviter le ping-pong direct.
	body.global_position = target
	area.set_meta("cooldown_until", now + 0.5)
	# Cherche l'area opposée (même target en from_pos) pour la mettre aussi en cooldown.
	for sibling in _entities_root.get_children():
		if sibling is Area3D and sibling != area:
			var sib_from: Vector3 = (sibling as Area3D).global_position
			if sib_from.distance_to(target) < 1.0:
				(sibling as Area3D).set_meta("cooldown_until", now + 0.5)


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
		# Force un id explicite : on veut tid en clé exacte pour set_cell_item.
		lib.create_item(tid)
		lib.set_item_name(tid, _tile_name(tid))
		lib.set_item_mesh(tid, box)
		# Offset Y : aligne le BAS du mesh au plancher de la cellule
		#   (= y_idx * cs.y). Pour ça, on offset depuis le centre de la cellule
		#   (qui est à y_idx*cs.y + cs.y/2) de `h/2 - cs.y/2`.
		var y_offset: float = h * 0.5 - cs.y * 0.5
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


## Ajoute des colliders par cellule :
## - Cellules walkable (floor/corridor/secret/door/stair_*/drop/jump_pad/drift) :
##   une box plate à hauteur du mesh sol (top à y_idx*cs.y + 0.2).
## - Cellules murs (wall/boss_door/secret_door) : box pleine occupant toute
##   la cellule (de y_idx*cs.y à (y_idx+1)*cs.y).
##
## Le joueur marche donc sur le mesh visuellement (top du sol à 0.1m audessus
## du fond de la cellule) et les murs le bloquent latéralement.
func _add_floor_colliders() -> void:
	var size: Vector3i = layout.grid_size
	var cs: Vector3 = layout.cell_size

	var floors_body := StaticBody3D.new()
	floors_body.name = "FloorColliders"
	add_child(floors_body)

	var walls_body := StaticBody3D.new()
	walls_body.name = "WallColliders"
	add_child(walls_body)

	# Set de tiles qui sont "marchables" (le joueur a un sol à fouler dessus).
	var walkable_tiles := {
		TILE_FLOOR: true, TILE_CORRIDOR: true, TILE_SECRET: true,
		TILE_DOOR: true, TILE_STAIR_UP: true, TILE_STAIR_DOWN: true,
		TILE_DROP: true, TILE_DROP_LANDING: true, TILE_JUMP_PAD: true,
		TILE_DRIFT: true,
	}
	# Set de tiles qui sont "murs pleins" (bloquent le passage).
	var wall_tiles := {
		TILE_WALL: true, TILE_BOSS_DOOR: true, TILE_SECRET_DOOR: true,
	}

	for y in range(size.y):
		for z in range(size.z):
			for x in range(size.x):
				var tid := layout.get_tile(x, y, z)
				if walkable_tiles.has(tid):
					var fs := CollisionShape3D.new()
					var fbox := BoxShape3D.new()
					fbox.size = Vector3(cs.x, 0.2, cs.z)
					fs.shape = fbox
					# Top du collider à y_idx*cs.y + 0.2 → joueur posé au-dessus
					# du mesh sol (qui top à 0.1).
					fs.position = Vector3(
						(float(x) + 0.5) * cs.x,
						float(y) * cs.y + 0.1,
						(float(z) + 0.5) * cs.z,
					)
					floors_body.add_child(fs)
				elif wall_tiles.has(tid):
					var ws := CollisionShape3D.new()
					var wbox := BoxShape3D.new()
					wbox.size = Vector3(cs.x, cs.y, cs.z)
					ws.shape = wbox
					# Centre du mur à mi-hauteur de la cellule.
					ws.position = Vector3(
						(float(x) + 0.5) * cs.x,
						(float(y) + 0.5) * cs.y,
						(float(z) + 0.5) * cs.z,
					)
					walls_body.add_child(ws)


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
	_spawn_player_markers()
	_spawn_run_chest_markers()
	_spawn_puzzle_triggers_and_gate()
	_spawn_enemies()
	_spawn_boss()


## PlayerSpawnPoints/Spawn0..3 dans les COINS de la spawn_room (loin du
## téléporteur central si la spawn_room a une stair au centre).
func _spawn_player_markers() -> void:
	if not (layout.spawn_room in layout.rooms):
		return
	var sr: Dictionary = layout.rooms[layout.spawn_room]
	var cs: Vector3 = layout.cell_size
	var y_idx: int = sr["y"]
	var y_floor: float = float(y_idx) * cs.y + 1.0
	# Cellules walkables intérieures de la room : (rx+1..rx+w-2, rz+1..rz+d-2).
	var x0: int = int(sr["x"]) + 1
	var x1: int = int(sr["x"]) + int(sr["w"]) - 2
	var z0: int = int(sr["z"]) + 1
	var z1: int = int(sr["z"]) + int(sr["d"]) - 2
	# Coins de la zone walkable (donc loin du centre où peut être un téléporteur).
	var corners := [
		Vector2i(x0, z0),
		Vector2i(x1, z0),
		Vector2i(x0, z1),
		Vector2i(x1, z1),
	]
	var spawns_root := Node3D.new()
	spawns_root.name = "PlayerSpawnPoints"
	_entities_root.add_child(spawns_root)
	for i in range(4):
		var c: Vector2i = corners[i]
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		m.position = Vector3((float(c.x) + 0.5) * cs.x, y_floor, (float(c.y) + 0.5) * cs.z)
		spawns_root.add_child(m)


## Markers consommés par RunShell pour spawn coffres reliques + coffre début.
##   - 'relic_chest_spawns' (group) : un par room qui a 'loot_major' ou est
##     une room combat — RunShell tirera 4 au hasard.
##   - 'StartChestSpawn' (nom) : décalé du centre de la spawn_room (qui peut
##     être occupé par téléporteur).
func _spawn_run_chest_markers() -> void:
	var cs: Vector3 = layout.cell_size

	# StartChestSpawn : dans la spawn_room, décalé du centre.
	if layout.spawn_room in layout.rooms:
		var sr: Dictionary = layout.rooms[layout.spawn_room]
		var y_floor: float = float(sr["y"]) * cs.y + 1.0
		# 2 cellules avant le centre, contre un mur.
		var sx: int = int(sr["x"]) + 2
		var sz: int = int(sr["z"]) + 2
		var marker := Marker3D.new()
		marker.name = "StartChestSpawn"
		marker.position = Vector3((float(sx) + 0.5) * cs.x, y_floor, (float(sz) + 0.5) * cs.z)
		_entities_root.add_child(marker)

	# 4 markers relic_chest_spawns dans des rooms variées (entree, combat, etc.).
	# RunShell tire au hasard et les utilise.
	var candidate_rooms: Array = []
	for rid in layout.rooms.keys():
		var rm: Dictionary = layout.rooms[rid]
		var t: String = rm.get("type", "")
		if t in ["spawn", "combat_small", "combat_large", "loot", "secret"]:
			candidate_rooms.append(rid)
	for i in range(candidate_rooms.size()):
		var rid: String = candidate_rooms[i]
		var rm: Dictionary = layout.rooms[rid]
		var y_floor: float = float(rm["y"]) * cs.y + 1.0
		# Décalé du centre (où peut être un téléporteur).
		var cx: int = int(rm["x"]) + 1
		var cz: int = int(rm["z"]) + int(rm["d"]) - 2
		var m := Marker3D.new()
		m.name = "RelicChestSpawn_%s" % rid
		m.position = Vector3((float(cx) + 0.5) * cs.x, y_floor, (float(cz) + 0.5) * cs.z)
		m.add_to_group(&"relic_chest_spawns")
		_entities_root.add_child(m)


## Instancie les cristaux (Lever scenes) pour chaque puzzle_trigger Pn,
## crée un PuzzleGate node qui les wire à la boss_door.
func _spawn_puzzle_triggers_and_gate() -> void:
	if puzzle_trigger_scene == null:
		return
	var cs: Vector3 = layout.cell_size

	var levers: Array[NodePath] = []
	for room_id in layout.contents.keys():
		var content: Dictionary = layout.contents[room_id]
		var triggers: Array = content.get("puzzle_triggers", [])
		if triggers.is_empty():
			continue
		if not (room_id in layout.rooms):
			continue
		var rm: Dictionary = layout.rooms[room_id]
		var y_floor: float = float(rm["y"]) * cs.y + 1.0
		# Place le lever au coin opposé du centre pour ne pas chevaucher
		# d'éventuels téléporteurs.
		var lx: int = int(rm["x"]) + 1
		var lz: int = int(rm["z"]) + 1
		for trig_id in triggers:
			var lever = puzzle_trigger_scene.instantiate()
			lever.name = "Lever_%s_%s" % [room_id, trig_id]
			lever.position = Vector3((float(lx) + 0.5) * cs.x, y_floor, (float(lz) + 0.5) * cs.z)
			_entities_root.add_child(lever)
			levers.append(lever.get_path())
			lx += 1  # décale chaque lever d'1 cellule si plusieurs dans la même room

	if levers.is_empty():
		return

	# Cherche la boss_door pour la wirer comme cible du puzzle gate.
	# Le tile BOSS_DOOR est posé par le builder ; on récupère via layout.doors.
	# Pour le MVP : pas de scène Door instanciée — on désactivera les colliders
	# de tile BOSS_DOOR via _open_boss_door() au signal puzzle_solved.
	var gate := PuzzleGate.new()
	gate.name = "PuzzleGate"
	gate.lever_paths = levers
	# door_paths reste vide : on gère l'ouverture via _open_boss_door.
	gate.puzzle_solved.connect(_open_all_boss_doors)
	_entities_root.add_child(gate)


## Spawn ennemis dans les rooms combat. Mêlée par défaut, ranged si
## la room a un mini_boss (cf N1 : g2 = ranged + mini-boss).
func _spawn_enemies() -> void:
	var cs: Vector3 = layout.cell_size
	for rid in layout.rooms.keys():
		var rm: Dictionary = layout.rooms[rid]
		var t: String = rm.get("type", "")
		if t not in ["combat_small", "combat_large"]:
			continue
		var content: Dictionary = layout.contents.get(rid, {})
		var is_ranged: bool = content.get("mini_boss", false)
		var n_enemies: int = 3 if t == "combat_large" else 2
		var enemy_scene: PackedScene = enemy_ranged_scene if is_ranged else enemy_melee_scene
		if enemy_scene == null:
			continue
		var y_floor: float = float(rm["y"]) * cs.y + 1.0
		# Spawn aux 4 coins de la zone walkable (intérieur de la room).
		var x0: int = int(rm["x"]) + 1
		var x1: int = int(rm["x"]) + int(rm["w"]) - 2
		var z0: int = int(rm["z"]) + 1
		var z1: int = int(rm["z"]) + int(rm["d"]) - 2
		var positions := [
			Vector2i(x0, z0), Vector2i(x1, z0),
			Vector2i(x0, z1), Vector2i(x1, z1),
		]
		for i in range(min(n_enemies, positions.size())):
			var p: Vector2i = positions[i]
			var enemy = enemy_scene.instantiate()
			enemy.global_position = Vector3((float(p.x) + 0.5) * cs.x, y_floor, (float(p.y) + 0.5) * cs.z)
			# Note : add_child APRES setting position pour avoir un transform valide.
			_entities_root.add_child(enemy)


## Spawn le boss au centre de l'arène boss_arena.
func _spawn_boss() -> void:
	if boss_scene == null:
		return
	var cs: Vector3 = layout.cell_size
	for rid in layout.rooms.keys():
		var rm: Dictionary = layout.rooms[rid]
		if rm.get("type", "") != "boss_arena":
			continue
		var cx: int = int(rm["x"]) + int(rm["w"]) / 2
		var cz: int = int(rm["z"]) + int(rm["d"]) / 2
		var y_floor: float = float(rm["y"]) * cs.y + 1.0
		var boss := boss_scene.instantiate()
		boss.name = "Boss_%s" % rid
		_entities_root.add_child(boss)
		(boss as Node3D).global_position = Vector3(
			(float(cx) + 0.5) * cs.x, y_floor,
			(float(cz) + 0.5) * cs.z
		)


## Quand le PuzzleGate signale puzzle_solved, désactive tous les colliders
## de cellules tile BOSS_DOOR (rend la porte traversable).
func _open_all_boss_doors() -> void:
	print("[DungeonBuilder] Puzzle résolu → boss doors ouvertes")
	var walls_body: Node = get_node_or_null("WallColliders")
	if walls_body == null:
		return
	# Approche brute : pour chaque door dans layout.doors locked=true, retire
	# les CollisionShape3D dont la position correspond.
	var cs: Vector3 = layout.cell_size
	for door in layout.doors:
		if not door.get("locked", false):
			continue
		var dx: int = int(door["x"])
		var dy: int = int(door["y"])
		var dz: int = int(door["z"])
		# La door layout est un nœud 3x3 — on désactive les colliders de
		# toutes les cellules tile BOSS_DOOR sur ce range.
		for ox in range(3):
			for oz in range(3):
				var cell_x := dx + ox
				var cell_z := dz + oz
				if layout.get_tile(cell_x, dy, cell_z) != TILE_BOSS_DOOR:
					continue
				var pos := Vector3(
					(float(cell_x) + 0.5) * cs.x,
					(float(dy) + 0.5) * cs.y,
					(float(cell_z) + 0.5) * cs.z,
				)
				_disable_collider_at(walls_body, pos)


func _disable_collider_at(body: Node, target_pos: Vector3) -> void:
	for child in body.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).position.distance_to(target_pos) < 0.1:
			(child as CollisionShape3D).disabled = true


func _grid_to_world(x: int, y: int, z: int) -> Vector3:
	return Vector3(
		(float(x) + 0.5) * layout.cell_size.x,
		(float(y) + 0.5) * layout.cell_size.y,
		(float(z) + 0.5) * layout.cell_size.z,
	)

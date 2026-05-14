class_name SplitScreenManager
extends Control

## Crée et arrange dynamiquement les SubViewportContainer selon le nombre de
## joueurs inscrits dans PlayerManager.
##
## Architecture (cf docs/tech/split_screen.md) :
## - Le monde 3D (World) vit dans la scène parente et est UNIQUE
## - Chaque SubViewport partage `world_3d` avec le root viewport pour voir le
##   même monde
## - Au join : on instancie un player.tscn dans le World, et on reparent sa
##   Camera3D dans le SubViewport correspondant via player.attach_camera_to()
## - Layout adaptatif :
##   - 1 joueur : 1 viewport plein écran
##   - 2 joueurs : split horizontal (haut/bas) — vertical en futur si ratio écran
##   - 3-4 joueurs : 2×2 quadrants (slot 4 vide en mode 3)

const PLAYER_SCENE_PATH := "res://scenes/characters/player/player.tscn"
const MAX_PLAYERS: int = 4

@export var world_path: NodePath
@export var spawn_points: Array[NodePath] = []
@export var player_scene: PackedScene = preload(PLAYER_SCENE_PATH)

var _world: Node3D
var _grid: GridContainer
var _slots: Array = []  # Array of { container: SubViewportContainer, viewport: SubViewport, player: PlayerController }


func _ready() -> void:
	# Le manager occupe tout l'écran et héberge la grille de viewports.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_world = get_node(world_path)

	_grid = GridContainer.new()
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.add_theme_constant_override(&"h_separation", 0)
	_grid.add_theme_constant_override(&"v_separation", 0)
	add_child(_grid)

	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)

	# Si des joueurs sont déjà inscrits (cas reload), spawn-les tout de suite.
	for pid in PlayerManager.get_active_player_ids():
		var device_id: int = PlayerManager.get_device_id(pid)
		_spawn_slot(pid, device_id)
	_refresh_layout()


func _on_player_joined(player_id: int, device_id: int) -> void:
	_spawn_slot(player_id, device_id)
	_refresh_layout()


func _on_player_left(player_id: int) -> void:
	_despawn_slot(player_id)
	_refresh_layout()


func _spawn_slot(player_id: int, _device_id: int) -> void:
	if _find_slot(player_id) != null:
		return

	var container: SubViewportContainer = SubViewportContainer.new()
	container.stretch = true
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var viewport: SubViewport = SubViewport.new()
	viewport.handle_input_locally = false
	viewport.size_2d_override_stretch = true
	# Partage le world 3D du root pour voir la même scène 3D que les autres
	# viewports. Set juste après l'ajout au tree (world_3d nécessite le tree).
	container.add_child(viewport)

	_grid.add_child(container)
	viewport.world_3d = get_tree().root.world_3d

	var player: PlayerController = player_scene.instantiate() as PlayerController
	player.player_id = player_id
	_world.add_child(player)
	player.global_transform.origin = _get_spawn_position(player_id)
	player.attach_camera_to(viewport)

	_slots.append({
		"player_id": player_id,
		"container": container,
		"viewport": viewport,
		"player": player,
	})


func _despawn_slot(player_id: int) -> void:
	var slot: Dictionary = _find_slot(player_id)
	if slot.is_empty():
		return
	if is_instance_valid(slot.player):
		slot.player.queue_free()
	if is_instance_valid(slot.container):
		slot.container.queue_free()
	_slots = _slots.filter(func(s): return s.player_id != player_id)


func _find_slot(player_id: int) -> Dictionary:
	for slot in _slots:
		if slot.player_id == player_id:
			return slot
	return {}


func _get_spawn_position(player_id: int) -> Vector3:
	if player_id < spawn_points.size():
		var sp: Node3D = get_node_or_null(spawn_points[player_id]) as Node3D
		if sp != null:
			return sp.global_transform.origin
	# Fallback : positions par défaut autour de l'origine.
	var fallbacks: Array = [
		Vector3(-2, 1, 0),
		Vector3(2, 1, 0),
		Vector3(0, 1, -2),
		Vector3(0, 1, 2),
	]
	return fallbacks[player_id % fallbacks.size()]


func _refresh_layout() -> void:
	# Peut être appelé par NOTIFICATION_RESIZED avant que _grid soit créé
	# (set_anchors_and_offsets_preset déclenche un resize au début de _ready).
	if _grid == null:
		return

	var count: int = _slots.size()
	# Tri par player_id pour un layout déterministe (J1 top-left, etc.).
	_slots.sort_custom(func(a, b): return a.player_id < b.player_id)
	for i in _slots.size():
		_grid.move_child(_slots[i].container, i)

	var viewport_size: Vector2 = size
	if viewport_size == Vector2.ZERO:
		viewport_size = get_viewport_rect().size

	match count:
		0:
			_grid.columns = 1
		1:
			_grid.columns = 1
			_set_slot_size(_slots[0].container, viewport_size)
		2:
			_grid.columns = 1
			var half: Vector2 = Vector2(viewport_size.x, viewport_size.y * 0.5)
			for s in _slots:
				_set_slot_size(s.container, half)
		_:
			_grid.columns = 2
			var quad: Vector2 = Vector2(viewport_size.x * 0.5, viewport_size.y * 0.5)
			for s in _slots:
				_set_slot_size(s.container, quad)


func _set_slot_size(container: SubViewportContainer, slot_size: Vector2) -> void:
	container.custom_minimum_size = slot_size
	container.size = slot_size
	var viewport: SubViewport = container.get_child(0) as SubViewport
	if viewport != null:
		viewport.size = Vector2i(int(slot_size.x), int(slot_size.y))


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		_refresh_layout()

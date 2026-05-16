class_name BossArena
extends Node3D

## Lock d'arène boss. Une Area3D détecte les joueurs présents dans la salle.
## Quand tous les joueurs actifs (PlayerManager.get_active_player_ids) sont
## dans la zone, on engage le boss + on active un blocker à l'entrée.
##
## À la mort du boss (signal boss_defeated), on désactive le blocker pour
## permettre de ressortir.

@export var boss_path: NodePath
@export var trigger_zone_path: NodePath = NodePath("TriggerZone")
@export var entrance_blocker_path: NodePath = NodePath("EntranceBlocker")

var _boss: BossBase
var _trigger_zone: Area3D
var _blocker: StaticBody3D
var _players_inside: Dictionary = {}  # player_id -> bool


func _ready() -> void:
	_boss = get_node_or_null(boss_path) as BossBase
	_trigger_zone = get_node_or_null(trigger_zone_path) as Area3D
	_blocker = get_node_or_null(entrance_blocker_path) as StaticBody3D

	if _boss == null:
		push_warning("BossArena: boss_path non résolu (%s)" % boss_path)
	if _trigger_zone == null:
		push_warning("BossArena: trigger_zone_path non résolu (%s)" % trigger_zone_path)
		return

	_trigger_zone.body_entered.connect(_on_body_entered)
	_trigger_zone.body_exited.connect(_on_body_exited)

	if _blocker != null:
		_set_blocker_active(false)

	if _boss != null:
		_boss.boss_defeated.connect(_on_boss_defeated)


func _on_body_entered(body: Node) -> void:
	if not (body is PlayerController):
		return
	var p: PlayerController = body
	_players_inside[p.player_id] = true
	_check_all_in()


func _on_body_exited(body: Node) -> void:
	if not (body is PlayerController):
		return
	var p: PlayerController = body
	_players_inside.erase(p.player_id)


func _check_all_in() -> void:
	if _boss == null or _boss.is_engaged():
		return
	var active: Array = PlayerManager.get_active_player_ids()
	if active.is_empty():
		return
	for pid in active:
		if not _players_inside.has(pid):
			return
	# Tous présents → trigger.
	_set_blocker_active(true)
	_boss.engage()


func _on_boss_defeated(_damage_by_player: Dictionary, _duration: float) -> void:
	_set_blocker_active(false)


func _set_blocker_active(active: bool) -> void:
	if _blocker == null:
		return
	_blocker.process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	# Désactive aussi via collision_layer pour neutraliser les colliders.
	_blocker.collision_layer = 1 if active else 0
	_blocker.collision_mask = 1 if active else 0
	for c in _blocker.get_children():
		if c is CollisionShape3D:
			c.disabled = not active
		if c is MeshInstance3D:
			c.visible = active

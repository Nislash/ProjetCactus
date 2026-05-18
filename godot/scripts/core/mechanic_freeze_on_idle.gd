class_name MechanicFreezeOnIdle
extends Node

## Mécanique de niveau : gel des joueurs immobiles (N6 Montagne frozen).
## Si un joueur ne bouge pas pendant idle_threshold_sec, applique le status
## FREEZE via son StatusComponent. Reset le timer dès qu'il se déplace.
##
## Les zones "safe" (autour des feux camp / refuges) peuvent override en
## ajoutant des Area3D dans le groupe "warm_zone" — le freeze ne s'applique
## pas tant qu'un joueur est dans cette zone.

@export var idle_threshold_sec: float = 3.0
@export var freeze_duration_sec: float = 2.0
@export var move_epsilon: float = 0.5  ## delta XZ en m sous lequel = immobile

var _player_idle_time: Dictionary = {}  # player_id -> float
var _player_last_pos: Dictionary = {}   # player_id -> Vector3


func _process(delta: float) -> void:
	var players: Array = get_tree().get_nodes_in_group(&"players")
	for p in players:
		if not (p is PlayerController):
			continue
		var player: PlayerController = p
		var pid: int = player.player_id
		var pos: Vector3 = player.global_position
		var last: Vector3 = _player_last_pos.get(pid, pos)
		var moved_xz: float = Vector2(pos.x - last.x, pos.z - last.z).length()
		_player_last_pos[pid] = pos

		if moved_xz < move_epsilon * delta * 60.0:
			_player_idle_time[pid] = _player_idle_time.get(pid, 0.0) + delta
		else:
			_player_idle_time[pid] = 0.0

		if _player_idle_time.get(pid, 0.0) >= idle_threshold_sec:
			if _is_in_warm_zone(player):
				_player_idle_time[pid] = 0.0
				continue
			_apply_freeze(player)
			_player_idle_time[pid] = 0.0


func _is_in_warm_zone(player: PlayerController) -> bool:
	for zone in get_tree().get_nodes_in_group(&"warm_zone"):
		if not (zone is Area3D):
			continue
		var bodies = (zone as Area3D).get_overlapping_bodies()
		if player in bodies:
			return true
	return false


func _apply_freeze(player: PlayerController) -> void:
	# StatusComponent vit sous HealthComponent. Pas tous les joueurs n'ont
	# forcement un status (defensif).
	var health = player.get_node_or_null("Health")
	if health == null:
		return
	var status = null
	if health.has_method("get_status"):
		status = health.get_status()
	if status == null or not status.has_method("apply_status"):
		return
	# apply_status(id, duration_sec, magnitude, source). Magnitude n'est
	# pas utilisée pour freeze (juste un slow/stop), mais l'argument est requis.
	status.apply_status(StatusComponent.FREEZE, freeze_duration_sec, 1.0, self)

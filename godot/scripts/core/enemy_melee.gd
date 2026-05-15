extends EnemyBase

## Ennemi mêlée : poursuit le joueur le plus proche et inflige des dégâts au
## contact (à courte distance, déclenché par un cooldown).

@export var attack_damage: int = 8
@export var attack_range: float = 1.6
@export var attack_cooldown: float = 1.0

var _attack_cooldown_left: float = 0.0


func _enemy_tick(delta: float) -> void:
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left -= delta

	# Status freeze/stun → pas de mouvement, pas d'attaque
	var speed_mult: float = get_speed_multiplier()
	if speed_mult <= 0.0:
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		return

	var target: PlayerController = _find_closest_player()
	if target == null:
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		return

	var to_target: Vector3 = target.global_position - global_position
	to_target.y = 0.0
	var dist: float = to_target.length()

	if dist > attack_range:
		# Poursuite : applique speed_mult (slow ralenti la poursuite)
		_apply_horizontal_velocity(to_target * speed_mult, delta)
	else:
		# À portée : on freeze le mouvement horizontal et on tape.
		_apply_horizontal_velocity(Vector3.ZERO, delta)
		if _attack_cooldown_left <= 0.0 and can_act():
			_attack_cooldown_left = attack_cooldown
			target.get_health().take_damage(attack_damage, self)

	# Look at target (yaw uniquement pour ne pas pencher).
	if to_target.length() > 0.1:
		look_at(target.global_position * Vector3(1, 0, 1) + Vector3(0, global_position.y, 0), Vector3.UP)

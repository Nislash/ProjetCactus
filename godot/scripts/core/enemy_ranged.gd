extends EnemyBase

## Ennemi ranged : reste à distance idéale du joueur le plus proche, le vise,
## et tire des hitscan toutes les N secondes.

@export var attack_damage: int = 6
@export var ideal_distance: float = 7.0
@export var distance_tolerance: float = 1.5  ## ±tolerance autour d'ideal_distance = zone neutre
@export var attack_cooldown: float = 1.4
@export var attack_max_range: float = 25.0

var _attack_cooldown_left: float = 0.0


func _enemy_tick(delta: float) -> void:
	if _attack_cooldown_left > 0.0:
		_attack_cooldown_left -= delta

	# Status freeze/stun → pas de mouvement, pas de tir
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

	# Kiting : si trop près on recule, si trop loin on avance, sinon stop.
	var move_dir: Vector3 = Vector3.ZERO
	if dist > ideal_distance + distance_tolerance:
		move_dir = to_target.normalized()
	elif dist < ideal_distance - distance_tolerance:
		move_dir = -to_target.normalized()
	_apply_horizontal_velocity(move_dir * speed_mult, delta)

	if to_target.length() > 0.1:
		look_at(target.global_position * Vector3(1, 0, 1) + Vector3(0, global_position.y, 0), Vector3.UP)

	# Tir hitscan si dans la portée et cooldown OK et pas freeze/stun.
	if _attack_cooldown_left <= 0.0 and dist < attack_max_range and can_act():
		_shoot_at(target)
		_attack_cooldown_left = attack_cooldown


func _shoot_at(target: PlayerController) -> void:
	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = global_position + Vector3(0, 1.2, 0)
	var to: Vector3 = target.global_position + Vector3(0, 1.0, 0)
	var query := PhysicsRayQueryParameters3D.create(origin, to, 0xFFFFFFFF)
	query.exclude = [get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if result.is_empty():
		_spawn_ray(origin, to)
		return
	var hit_pos: Vector3 = result.get(&"position", to)
	var collider: Node = result.get(&"collider", null)
	# Si on touche le joueur visé directement, on applique les dégâts.
	if collider != null:
		var hc: HealthComponent = _find_health(collider)
		if hc != null and hc == target.get_health():
			hc.take_damage(attack_damage, self)
	_spawn_ray(origin, hit_pos)


func _find_health(node: Node) -> HealthComponent:
	var current: Node = node
	while current != null:
		for child in current.get_children():
			if child is HealthComponent:
				return child as HealthComponent
		current = current.get_parent()
	return null


func _spawn_ray(from_pos: Vector3, to_pos: Vector3) -> void:
	var segment: Vector3 = to_pos - from_pos
	var length: float = segment.length()
	if length < 0.01:
		return
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, length)
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.3, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.85, 0.3)
	mesh_instance.material_override = mat
	get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = (from_pos + to_pos) * 0.5
	mesh_instance.look_at(to_pos, Vector3.UP)
	var timer := get_tree().create_timer(0.08)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	)

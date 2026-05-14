class_name WeaponHitscan
extends Node3D

## Arme hitscan basique. Tir = raycast depuis la transform globale de ce node
## (typiquement enfant de la Camera3D ou du CameraPivot du player).
##
## - Si le ray touche une collision avec un HealthComponent dans la chaîne
##   parente, applique les dégâts.
## - Un ray visuel rouge est spawné pour matérialiser le tir (queue_free
##   après `ray_visible_duration`).
##
## Friendly fire actif : le ray ne filtre pas par player_id. C'est la
## couche au-dessus qui choisira d'exclure si besoin (`add_exception()`).

signal fired(hit: bool, hit_position: Vector3, target: Node)
signal ammo_changed(current: int, max: int)
signal reload_started()
signal reload_finished()

@export var max_range: float = 50.0
@export var damage: int = 10
@export var fire_rate: float = 4.0  ## Tirs par seconde
@export var ray_visible_duration: float = 0.06
@export var collision_mask: int = 0xFFFFFFFF

@export_group("Ammo")
@export var max_ammo: int = 12
@export var reload_time: float = 1.5

@export_group("Combo")
## Si défini, le tir spawne ce projectile au lieu du raycast hitscan. La
## signature gameplay (cf CLAUDE.md "doit se ressentir") : avec le combo
## Pistolet × Feu, on tire une boule de feu visible qui brûle l'ennemi à
## l'impact.
@export var combo_projectile_scene: PackedScene

## Node propriétaire de l'arme (typiquement le player). Sert à exclure son
## propre collider pour ne pas se tirer dessus, et à transmettre `source` au
## HealthComponent qui reçoit les dégâts.
@export var owner_body: NodePath

var current_ammo: int = 0
var is_reloading: bool = false


func _ready() -> void:
	current_ammo = max_ammo
	ammo_changed.emit(current_ammo, max_ammo)


func can_fire() -> bool:
	return _cooldown_left <= 0.0 and current_ammo > 0 and not is_reloading


func reload() -> void:
	if is_reloading or current_ammo >= max_ammo:
		return
	is_reloading = true
	reload_started.emit()
	var timer := get_tree().create_timer(reload_time)
	timer.timeout.connect(_on_reload_finished)


func _on_reload_finished() -> void:
	current_ammo = max_ammo
	is_reloading = false
	ammo_changed.emit(current_ammo, max_ammo)
	reload_finished.emit()


func shoot() -> void:
	if not can_fire():
		# Auto-reload si on n'a plus de munitions et qu'on essaie de tirer.
		if current_ammo == 0 and not is_reloading:
			reload()
		return
	_cooldown_left = 1.0 / fire_rate
	current_ammo -= 1
	ammo_changed.emit(current_ammo, max_ammo)
	if current_ammo == 0:
		reload()

	# Combo Pistolet × Feu : on bypass le hitscan et on spawn un projectile
	# qui vole + applique burn à l'impact (cf #17).
	if combo_projectile_scene != null:
		_shoot_combo_projectile()
		return

	var space_state := get_world_3d().direct_space_state
	var origin: Vector3 = global_transform.origin
	# La direction "forward" d'un Node3D dans Godot est -Z basis vector.
	var direction: Vector3 = -global_transform.basis.z.normalized()
	var end: Vector3 = origin + direction * max_range

	var query := PhysicsRayQueryParameters3D.create(origin, end, collision_mask)
	var owner_node: Node = get_node_or_null(owner_body)
	if owner_node is CollisionObject3D:
		query.exclude = [owner_node.get_rid()]

	var result: Dictionary = space_state.intersect_ray(query)
	var hit: bool = not result.is_empty()
	var hit_pos: Vector3 = result.get(&"position", end) if hit else end
	var target: Node = result.get(&"collider", null) if hit else null

	if hit and target != null:
		var hc: HealthComponent = _find_health_component(target)
		if hc != null:
			hc.take_damage(damage, owner_node)

	_spawn_ray_visual(origin, hit_pos)
	fired.emit(hit, hit_pos, target)


var _cooldown_left: float = 0.0


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta


func _shoot_combo_projectile() -> void:
	var origin: Vector3 = global_transform.origin
	var direction: Vector3 = -global_transform.basis.z.normalized()
	# Spawn un peu en avant de la caméra pour ne pas exploser à la face.
	var spawn_pos: Vector3 = origin + direction * 0.5
	var projectile: Node = combo_projectile_scene.instantiate()
	get_tree().current_scene.add_child(projectile)
	# La fireball expose setup(start_pos, dir, owner_to_exclude).
	if projectile.has_method(&"setup"):
		var owner_node: Node = get_node_or_null(owner_body)
		projectile.call(&"setup", spawn_pos, direction, owner_node)
	fired.emit(false, spawn_pos, null)


func _find_health_component(node: Node) -> HealthComponent:
	# Cherche un HealthComponent dans le node lui-même puis remonte ses parents.
	var current: Node = node
	while current != null:
		for child in current.get_children():
			if child is HealthComponent:
				return child as HealthComponent
		current = current.get_parent()
	return null


func _spawn_ray_visual(from_pos: Vector3, to_pos: Vector3) -> void:
	var segment: Vector3 = to_pos - from_pos
	var length: float = segment.length()
	if length < 0.01:
		return

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.04, 0.04, length)
	mesh_instance.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.2, 0.15, 1.0)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.3, 0.2)
	mat.emission_energy_multiplier = 2.0
	mesh_instance.material_override = mat

	# Le ray vit au niveau du World pour ne pas suivre la transform du tireur
	# après le tir.
	get_tree().current_scene.add_child(mesh_instance)
	var mid: Vector3 = (from_pos + to_pos) * 0.5
	mesh_instance.global_transform.origin = mid
	mesh_instance.look_at(to_pos, Vector3.UP)

	var timer := get_tree().create_timer(ray_visible_duration)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	)

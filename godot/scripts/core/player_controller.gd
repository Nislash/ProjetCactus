class_name PlayerController
extends CharacterBody3D

## Contrôleur FPS d'un joueur. Toutes les inputs passent par InputRouter.
##
## Le `player_id` doit être set par celui qui instancie la scène (SplitScreenManager
## ou code de spawn). Tant que `player_id` n'a pas de device assigné dans
## InputRouter, le contrôleur reste inerte (pas d'erreur, juste pas de move).

@export var player_id: int = 0

@export_group("Mouvement")
@export var move_speed: float = 7.0
@export var acceleration: float = 50.0
@export var friction: float = 60.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 20.0

@export_group("Caméra / Look")
@export var look_sensitivity: float = 3.0
@export var pitch_min_deg: float = -85.0
@export var pitch_max_deg: float = 85.0

@export_group("Dash")
@export var dash_speed: float = 18.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.8

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _camera_remote: RemoteTransform3D = $CameraPivot/CameraRemote
@onready var _weapon: WeaponHitscan = $CameraPivot/Weapon
@onready var _health: HealthComponent = $Health

signal died(source: Node)
signal respawned()
signal death_count_changed(count: int)

var death_count: int = 0
var _spawn_position: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO


func _ready() -> void:
	_health.died.connect(_on_died)


## Doit être appelé par celui qui spawn le player (SplitScreenManager) après
## avoir set la position. Stocke la position pour les respawns futurs.
func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos
	global_transform.origin = pos


func get_health() -> HealthComponent:
	return _health


func _on_died(source: Node) -> void:
	died.emit(source)
	# Respawn immédiat au spawn point d'origine. La PJ ne meurt pas vraiment :
	# on téléporte, on remet full HP, on incrémente le compteur (M2 ajoutera
	# le downed + revive proprement).
	velocity = Vector3.ZERO
	global_transform.origin = _spawn_position
	_yaw = 0.0
	_pitch = 0.0
	rotation.y = 0.0
	_camera_pivot.rotation.x = 0.0
	_health.reset()
	death_count += 1
	death_count_changed.emit(death_count)
	respawned.emit()


func _physics_process(delta: float) -> void:
	if not InputRouter.is_player_registered(player_id):
		return

	_update_look(delta)
	_update_dash_timers(delta)
	_update_shooting()
	_apply_movement(delta)
	move_and_slide()


func _update_shooting() -> void:
	# RT en hold : tire à la cadence définie par l'arme (auto-fire).
	if InputRouter.is_action_pressed(player_id, &"shoot") and _weapon.can_fire():
		_weapon.shoot()


func _update_look(delta: float) -> void:
	var look: Vector2 = InputRouter.get_look_vector(player_id)
	_yaw -= look.x * look_sensitivity * delta
	_pitch -= look.y * look_sensitivity * delta
	_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	rotation.y = _yaw
	_camera_pivot.rotation.x = _pitch


func _update_dash_timers(delta: float) -> void:
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left -= delta

	if (
		_dash_cooldown_left <= 0.0
		and _dash_time_left <= 0.0
		and InputRouter.is_action_just_pressed(player_id, &"dash")
	):
		var move_input: Vector2 = InputRouter.get_move_vector(player_id)
		var dir_local: Vector3 = Vector3(move_input.x, 0.0, move_input.y)
		if dir_local.length() < 0.1:
			dir_local = Vector3.FORWARD
		_dash_direction = (transform.basis * dir_local).normalized()
		_dash_time_left = dash_duration
		_dash_cooldown_left = dash_cooldown


func _apply_movement(delta: float) -> void:
	if _dash_time_left > 0.0:
		velocity.x = _dash_direction.x * dash_speed
		velocity.z = _dash_direction.z * dash_speed
		if not is_on_floor():
			velocity.y -= gravity * delta
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif InputRouter.is_action_just_pressed(player_id, &"jump"):
		velocity.y = jump_velocity

	var input_2d: Vector2 = InputRouter.get_move_vector(player_id)
	var direction: Vector3 = (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()

	var horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	if direction.length() > 0.0:
		var target: Vector2 = Vector2(direction.x, direction.z) * move_speed
		horizontal = horizontal.move_toward(target, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector2.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func get_camera() -> Camera3D:
	return _camera


## Reparente la Camera3D du player vers `viewport` et configure le
## RemoteTransform3D pour qu'elle suive la transform de `CameraPivot`.
##
## Utilisé par le SplitScreenManager au spawn. En mode solo, ne pas appeler
## cette méthode — la Camera3D reste dans le player.tscn et fonctionne
## directement.
func attach_camera_to(viewport: SubViewport) -> void:
	if _camera.get_parent() == viewport:
		return
	_camera.get_parent().remove_child(_camera)
	viewport.add_child(_camera)
	_camera.current = true
	# Le RemoteTransform3D vit dans le player (CameraPivot) et propage la
	# transform globale vers la Camera3D maintenant externe.
	_camera_remote.remote_path = _camera.get_path()

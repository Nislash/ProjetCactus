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

var _yaw: float = 0.0
var _pitch: float = 0.0
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO


func _physics_process(delta: float) -> void:
	if not InputRouter.is_player_registered(player_id):
		return

	_update_look(delta)
	_update_dash_timers(delta)
	_apply_movement(delta)
	move_and_slide()


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

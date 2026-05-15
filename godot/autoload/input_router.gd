extends Node

## Routage des inputs manette par `player_id` (0..3).
##
## Autoload registré sous le nom `InputRouter` (cf project.godot). Pas de
## `class_name` pour éviter un conflit avec le nom du singleton.
##
## À l'enregistrement d'un device, on clone le template de bindings en actions
## Godot suffixées `p{N}_<action>` avec `event.device = device_id`. Les scripts
## joueur appellent ensuite `InputRouter.is_action_pressed(player_id, "shoot")`
## qui wrap `Input.is_action_pressed("p{N}_shoot")`. On hérite gratuitement de
## `just_pressed`, `strength` et la deadzone Godot.
##
## API exclusive : tout autre `Input.is_action_pressed(...)` dans le code joueur
## est interdit (cf CLAUDE.md "Anti-patterns interdits").

const MAX_PLAYERS: int = 4
## Deadzone uniforme appliquée à toutes les manettes. Voir
## `docs/tech/input_drift_investigation.md` pour le contexte du drift Switch
## Pro Controller observé pendant le M1 — la solution n'est PAS dans cette
## constante, à investiguer séparément.
const DEADZONE: float = 0.2

const _BUTTON: StringName = &"button"
const _MOTION: StringName = &"motion"

# Template des bindings logiques → events manette Xbox-like.
# Mapping référence : docs/tech/input_system.md
const _BINDINGS: Dictionary = {
	&"shoot":            [{&"type": _MOTION, &"axis": JOY_AXIS_TRIGGER_RIGHT, &"value":  1.0}],
	&"cast_spell":       [{&"type": _MOTION, &"axis": JOY_AXIS_TRIGGER_LEFT,  &"value":  1.0}],
	&"combo_swap_left":  [{&"type": _BUTTON, &"button": JOY_BUTTON_LEFT_SHOULDER}],
	&"combo_swap_right": [{&"type": _BUTTON, &"button": JOY_BUTTON_RIGHT_SHOULDER}],
	&"jump":             [{&"type": _BUTTON, &"button": JOY_BUTTON_A}],
	&"dash":             [{&"type": _BUTTON, &"button": JOY_BUTTON_B}],
	&"interact":         [{&"type": _BUTTON, &"button": JOY_BUTTON_X}],
	&"pause":            [{&"type": _BUTTON, &"button": JOY_BUTTON_START}],
	&"lobby_join":       [{&"type": _BUTTON, &"button": JOY_BUTTON_START}],
	&"lobby_leave":      [{&"type": _BUTTON, &"button": JOY_BUTTON_BACK}],

	&"move_left":    [{&"type": _MOTION, &"axis": JOY_AXIS_LEFT_X, &"value": -1.0}],
	&"move_right":   [{&"type": _MOTION, &"axis": JOY_AXIS_LEFT_X, &"value":  1.0}],
	&"move_forward": [{&"type": _MOTION, &"axis": JOY_AXIS_LEFT_Y, &"value": -1.0}],
	&"move_back":    [{&"type": _MOTION, &"axis": JOY_AXIS_LEFT_Y, &"value":  1.0}],

	&"look_left":  [{&"type": _MOTION, &"axis": JOY_AXIS_RIGHT_X, &"value": -1.0}],
	&"look_right": [{&"type": _MOTION, &"axis": JOY_AXIS_RIGHT_X, &"value":  1.0}],
	&"look_up":    [{&"type": _MOTION, &"axis": JOY_AXIS_RIGHT_Y, &"value": -1.0}],
	&"look_down":  [{&"type": _MOTION, &"axis": JOY_AXIS_RIGHT_Y, &"value":  1.0}],
}

signal player_registered(player_id: int, device_id: int)
signal player_unregistered(player_id: int)

var _player_to_device: Dictionary = {}
var _device_to_player: Dictionary = {}


func register_device(device_id: int) -> int:
	if _device_to_player.has(device_id):
		return _device_to_player[device_id]
	for pid in range(MAX_PLAYERS):
		if not _player_to_device.has(pid):
			_player_to_device[pid] = device_id
			_device_to_player[device_id] = pid
			_create_actions_for_player(pid, device_id)
			player_registered.emit(pid, device_id)
			return pid
	return -1


func unregister_player(player_id: int) -> void:
	if not _player_to_device.has(player_id):
		return
	var device_id: int = _player_to_device[player_id]
	_remove_actions_for_player(player_id)
	_player_to_device.erase(player_id)
	_device_to_player.erase(device_id)
	player_unregistered.emit(player_id)


func unregister_device(device_id: int) -> void:
	if _device_to_player.has(device_id):
		unregister_player(_device_to_player[device_id])


func get_device_id(player_id: int) -> int:
	return _player_to_device.get(player_id, -1)


func get_player_id(device_id: int) -> int:
	return _device_to_player.get(device_id, -1)


func is_player_registered(player_id: int) -> bool:
	return _player_to_device.has(player_id)


func get_active_player_ids() -> Array[int]:
	var ids: Array[int] = []
	for pid in _player_to_device.keys():
		ids.append(pid)
	ids.sort()
	return ids


func get_active_player_count() -> int:
	return _player_to_device.size()


func is_action_pressed(player_id: int, action: StringName) -> bool:
	if not _player_to_device.has(player_id):
		return false
	return Input.is_action_pressed(_action_name(player_id, action))


func is_action_just_pressed(player_id: int, action: StringName) -> bool:
	if not _player_to_device.has(player_id):
		return false
	return Input.is_action_just_pressed(_action_name(player_id, action))


func is_action_just_released(player_id: int, action: StringName) -> bool:
	if not _player_to_device.has(player_id):
		return false
	return Input.is_action_just_released(_action_name(player_id, action))


func get_action_strength(player_id: int, action: StringName) -> float:
	if not _player_to_device.has(player_id):
		return 0.0
	return Input.get_action_strength(_action_name(player_id, action))


func get_axis(player_id: int, neg_action: StringName, pos_action: StringName) -> float:
	if not _player_to_device.has(player_id):
		return 0.0
	return Input.get_axis(
		_action_name(player_id, neg_action),
		_action_name(player_id, pos_action)
	)


func get_vector(
	player_id: int,
	neg_x: StringName, pos_x: StringName,
	neg_y: StringName, pos_y: StringName
) -> Vector2:
	if not _player_to_device.has(player_id):
		return Vector2.ZERO
	return Input.get_vector(
		_action_name(player_id, neg_x),
		_action_name(player_id, pos_x),
		_action_name(player_id, neg_y),
		_action_name(player_id, pos_y),
		DEADZONE
	)


func get_move_vector(player_id: int) -> Vector2:
	return get_vector(player_id, &"move_left", &"move_right", &"move_forward", &"move_back")


func get_look_vector(player_id: int) -> Vector2:
	return get_vector(player_id, &"look_left", &"look_right", &"look_up", &"look_down")


# Sondage global tous devices (utile pour le lobby où aucun joueur n'est encore
# enregistré). Retourne le device_id du premier joypad qui presse `action`, ou
# -1 si aucun. Ne tient pas compte de _player_to_device.
func poll_any_device_just_pressed(action: StringName) -> int:
	var binding_list: Array = _BINDINGS.get(action, [])
	for device_id in Input.get_connected_joypads():
		for binding in binding_list:
			if _binding_matches(binding, device_id):
				return device_id
	return -1


func _action_name(player_id: int, action: StringName) -> StringName:
	return StringName("p%d_%s" % [player_id, action])


func _create_actions_for_player(player_id: int, device_id: int) -> void:
	for action_name in _BINDINGS.keys():
		var full_name: StringName = _action_name(player_id, action_name)
		if InputMap.has_action(full_name):
			InputMap.erase_action(full_name)
		InputMap.add_action(full_name, DEADZONE)
		for binding in _BINDINGS[action_name]:
			var event: InputEvent = _make_event(binding, device_id)
			if event != null:
				InputMap.action_add_event(full_name, event)


func _remove_actions_for_player(player_id: int) -> void:
	for action_name in _BINDINGS.keys():
		var full_name: StringName = _action_name(player_id, action_name)
		if InputMap.has_action(full_name):
			InputMap.erase_action(full_name)


func _make_event(binding: Dictionary, device_id: int) -> InputEvent:
	match binding[&"type"]:
		_BUTTON:
			var ev_btn: InputEventJoypadButton = InputEventJoypadButton.new()
			ev_btn.button_index = binding[&"button"]
			ev_btn.device = device_id
			ev_btn.pressed = true
			return ev_btn
		_MOTION:
			var ev_motion: InputEventJoypadMotion = InputEventJoypadMotion.new()
			ev_motion.axis = binding[&"axis"]
			ev_motion.axis_value = binding[&"value"]
			ev_motion.device = device_id
			return ev_motion
	return null


# Polling brut pour le lobby : check si un binding spécifique est triggered sur
# un device donné, sans passer par l'action map (utilisé avant register).
func _binding_matches(binding: Dictionary, device_id: int) -> bool:
	match binding[&"type"]:
		_BUTTON:
			return Input.is_joy_button_pressed(device_id, binding[&"button"])
		_MOTION:
			var value: float = Input.get_joy_axis(device_id, binding[&"axis"])
			var target: float = binding[&"value"]
			if target > 0.0:
				return value >= DEADZONE
			return value <= -DEADZONE
	return false

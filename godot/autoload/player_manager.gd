extends Node

## Source de vérité de la composition de l'équipe pour un run :
## qui est inscrit, sur quelle manette, et quel état (lobby vs en jeu).
##
## Le lobby (scenes/ui/lobby/lobby.tscn) pilote l'enregistrement via
## `try_register_via_input(device_id)`. En jeu, le code peut requêter
## `get_active_players()` pour itérer.
##
## Hot-plug : abonné à `Input.joy_connection_changed`. Si une manette se
## déconnecte alors que le joueur est en jeu, on émet `player_disconnected`
## et c'est au gameplay code de décider quoi faire (pause auto, downed, etc.).

enum LobbyState { CLOSED, OPEN, STARTING }

signal player_joined(player_id: int, device_id: int)
signal player_left(player_id: int)
signal player_disconnected(player_id: int, device_id: int)
signal player_reconnected(player_id: int, device_id: int)
signal lobby_state_changed(new_state: LobbyState)

var _lobby_state: LobbyState = LobbyState.CLOSED
var _disconnected_players: Dictionary = {}


func _ready() -> void:
	Input.joy_connection_changed.connect(_on_joy_connection_changed)


func open_lobby() -> void:
	_lobby_state = LobbyState.OPEN
	lobby_state_changed.emit(_lobby_state)


func close_lobby() -> void:
	_lobby_state = LobbyState.CLOSED
	lobby_state_changed.emit(_lobby_state)


func start_run() -> void:
	if InputRouter.get_active_player_count() == 0:
		push_warning("PlayerManager.start_run() appelé sans joueur enregistré.")
		return
	_lobby_state = LobbyState.STARTING
	lobby_state_changed.emit(_lobby_state)


func get_lobby_state() -> LobbyState:
	return _lobby_state


# Essaye d'inscrire un device. Retourne le player_id (0..3) ou -1 si plein /
# déjà inscrit. Émet `player_joined` si nouveau.
func try_register_device(device_id: int) -> int:
	if not _is_device_connected(device_id):
		return -1
	var existing: int = InputRouter.get_player_id(device_id)
	if existing != -1:
		return existing
	var pid: int = InputRouter.register_device(device_id)
	if pid == -1:
		return -1
	player_joined.emit(pid, device_id)
	return pid


# Libère un slot. Inverse de try_register_device.
func unregister_player(player_id: int) -> void:
	if not InputRouter.is_player_registered(player_id):
		return
	InputRouter.unregister_player(player_id)
	player_left.emit(player_id)


# Polling pour le lobby : check si une manette non-inscrite vient d'appuyer
# Start. Si oui, l'inscrit et retourne le player_id. Sinon -1.
func poll_lobby_joins() -> int:
	if _lobby_state != LobbyState.OPEN:
		return -1
	var device_id: int = InputRouter.poll_any_device_just_pressed(&"lobby_join")
	if device_id == -1:
		return -1
	if InputRouter.get_player_id(device_id) != -1:
		return -1
	return try_register_device(device_id)


func get_active_player_ids() -> Array[int]:
	return InputRouter.get_active_player_ids()


func get_active_player_count() -> int:
	return InputRouter.get_active_player_count()


func get_device_id(player_id: int) -> int:
	return InputRouter.get_device_id(player_id)


func _is_device_connected(device_id: int) -> bool:
	for connected_id in Input.get_connected_joypads():
		if connected_id == device_id:
			return true
	return false


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	var player_id: int = InputRouter.get_player_id(device_id)

	if not connected:
		if player_id != -1:
			_disconnected_players[player_id] = device_id
			player_disconnected.emit(player_id, device_id)
		return

	# Reconnexion : si on attendait ce device, restaure le slot.
	for pid in _disconnected_players.keys():
		if _disconnected_players[pid] == device_id:
			_disconnected_players.erase(pid)
			player_reconnected.emit(pid, device_id)
			return

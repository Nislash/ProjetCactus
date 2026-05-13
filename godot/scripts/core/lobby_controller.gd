extends Control

## Pilote la scène lobby (scenes/ui/lobby/lobby.tscn).
##
## Boucle simple :
## - `PlayerManager.open_lobby()` à `_ready()`
## - chaque frame : `PlayerManager.poll_lobby_joins()` pour intercepter Start
##   d'une manette non-inscrite
## - chaque joueur inscrit peut appuyer `lobby_leave` (Back) pour quitter
## - quand 1+ joueur est ready, n'importe quel joueur peut faire `lobby_join`
##   (Start) une deuxième fois pour lancer le run (geste "ready")
##
## Au M1 on n'a pas encore d'écran "coffre", donc le start_run() émet juste
## un signal `run_requested` que la suite (M2) câblera.

signal run_requested(player_ids: Array[int])

const MAX_PLAYERS: int = 4

@onready var _slots: Array[LobbySlotUI] = [
	%Slot0 as LobbySlotUI,
	%Slot1 as LobbySlotUI,
	%Slot2 as LobbySlotUI,
	%Slot3 as LobbySlotUI,
]
@onready var _status_label: Label = %StatusLabel


func _ready() -> void:
	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)
	PlayerManager.open_lobby()
	_refresh_status()


func _process(_delta: float) -> void:
	PlayerManager.poll_lobby_joins()

	for pid in PlayerManager.get_active_player_ids():
		if InputRouter.is_action_just_pressed(pid, &"lobby_leave"):
			PlayerManager.unregister_player(pid)
			return

	# Un joueur appuie Start une 2e fois → ready / launch.
	for pid in PlayerManager.get_active_player_ids():
		if InputRouter.is_action_just_pressed(pid, &"lobby_join"):
			_launch_run()
			return


func _launch_run() -> void:
	var ids: Array[int] = PlayerManager.get_active_player_ids()
	if ids.is_empty():
		return
	PlayerManager.start_run()
	run_requested.emit(ids)
	_status_label.text = "Run lancé avec %d joueur(s)…" % ids.size()


func _on_player_joined(player_id: int, device_id: int) -> void:
	if player_id < _slots.size():
		_slots[player_id].set_joined(device_id)
	_refresh_status()


func _on_player_left(player_id: int) -> void:
	if player_id < _slots.size():
		_slots[player_id].set_empty()
	_refresh_status()


func _refresh_status() -> void:
	var count: int = PlayerManager.get_active_player_count()
	if count == 0:
		_status_label.text = "Appuyez sur Start pour rejoindre."
	else:
		_status_label.text = "%d/%d prêt — Start = lancer, Back = quitter le slot." % [count, MAX_PLAYERS]

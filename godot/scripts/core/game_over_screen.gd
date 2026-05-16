class_name GameOverScreen
extends Control

## Écran Game Over. S'affiche quand tous les joueurs sont morts (HP 0 sans
## possibilité de revive ou solo direct). N'importe quel input → retour
## au lobby.

const LOBBY_SCENE := "res://scenes/ui/lobby/lobby.tscn"

@onready var _title: Label = $Backdrop/VBox/Title
@onready var _hint: Label = $Backdrop/VBox/Hint

var _waiting_for_input: bool = false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func show_game_over() -> void:
	visible = true
	_title.text = "GAME OVER"
	_hint.text = "Appuyez sur n'importe quel bouton pour retourner au menu"
	_waiting_for_input = true


func _input(event: InputEvent) -> void:
	if not _waiting_for_input:
		return
	var consumed: bool = false
	if event is InputEventKey and event.pressed:
		consumed = true
	elif event is InputEventJoypadButton and event.pressed:
		consumed = true
	elif event is InputEventMouseButton and event.pressed:
		consumed = true
	if consumed:
		_waiting_for_input = false
		# Restaure le time_scale au cas où le boss était en slow-mo.
		Engine.time_scale = 1.0
		get_tree().change_scene_to_file(LOBBY_SCENE)

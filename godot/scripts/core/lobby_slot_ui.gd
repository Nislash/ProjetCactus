class_name LobbySlotUI
extends PanelContainer

## Slot visuel d'un joueur dans le lobby. Affiche soit "empty / press Start",
## soit "Player N — Device X". Pas de polish au M1 — juste un label.

@export var player_id: int = 0

@onready var _label: Label = $Label


func _ready() -> void:
	set_empty()


func set_empty() -> void:
	_label.text = "P%d — Press Start" % player_id


func set_joined(device_id: int) -> void:
	var joypad_name: String = Input.get_joy_name(device_id)
	if joypad_name.is_empty():
		joypad_name = "Joypad %d" % device_id
	_label.text = "P%d ✓\n%s" % [player_id, joypad_name]

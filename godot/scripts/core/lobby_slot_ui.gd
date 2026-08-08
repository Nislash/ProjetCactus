class_name LobbySlotUI
extends PanelContainer

## Emplacement d'un joueur sur l'écran d'accueil.
##
## Il prend la COULEUR DU JOUEUR dès qu'une manette le rejoint — la même que
## son HUD en jeu et que son cristal dans l'Antichambre. Un joueur doit
## reconnaître « sa » couleur du menu jusqu'au boss, sans qu'on la lui
## explique.
##
## Vide, il reste dessiné en creux : voir les quatre places libres est ce qui
## dit qu'on peut être quatre.

@export var player_id: int = 0

@onready var _label: Label = $Label


func _ready() -> void:
	set_empty()


## Appelé par le lobby au démarrage : le slot ne connaît pas son rang avant
## d'être placé dans la grille.
func apply_theme(index: int) -> void:
	player_id = index
	custom_minimum_size = Vector2(190, 108)
	if _label != null:
		_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_label.add_theme_font_size_override("font_size", 15)
	set_empty()


func set_empty() -> void:
	LobbyTheme.style_slot(self, false, LobbyTheme.slot_color(player_id))
	if _label != null:
		_label.add_theme_color_override("font_color", LobbyTheme.DIM)
	_label.text = "JOUEUR %d\n—\nStart" % (player_id + 1)


func set_joined(device_id: int) -> void:
	var colour: Color = LobbyTheme.slot_color(player_id)
	LobbyTheme.style_slot(self, true, colour)
	var joypad_name: String = Input.get_joy_name(device_id)
	if joypad_name.is_empty():
		joypad_name = "Manette %d" % device_id
	# Le nom de manette est souvent à rallonge ; on garde ce qui tient.
	if joypad_name.length() > 18:
		joypad_name = joypad_name.substr(0, 17) + "…"
	if _label != null:
		_label.add_theme_color_override("font_color", Color.WHITE)
	_label.text = "JOUEUR %d\n◆\n%s" % [player_id + 1, joypad_name]

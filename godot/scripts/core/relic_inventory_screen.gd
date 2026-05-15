class_name RelicInventoryScreen
extends PanelContainer

## Overlay d'inventaire des reliques. S'ouvre/ferme sur Y (toggle_inventory)
## via PlayerController.inventory_toggle_requested. Vit dans le SubViewport
## du joueur — les autres joueurs ne sont pas affectés.
##
## Affiche les 5 slots verticalement avec nom, tier, description, flavor,
## et un dump de la magnitude pour debug équilibrage. Slots vides = grisés.

const FADE_SEC := 0.18

var _inventory: RelicInventory = null
var _player: PlayerController = null
var _open: bool = false

@onready var _vbox: VBoxContainer = $Margin/VBox/Scroll/SlotsVBox
@onready var _title: Label = $Margin/VBox/Title
@onready var _hint: Label = $Margin/VBox/Hint


func _ready() -> void:
	modulate.a = 0.0
	visible = false


func bind(player: PlayerController) -> void:
	_player = player
	if player == null:
		return
	_inventory = player.relic_inventory
	if _inventory != null and not _inventory.inventory_changed.is_connected(_refresh):
		_inventory.inventory_changed.connect(_refresh)
	if not player.inventory_toggle_requested.is_connected(_toggle):
		player.inventory_toggle_requested.connect(_toggle)


func _toggle() -> void:
	if _open:
		_close()
	else:
		_open_panel()


func _open_panel() -> void:
	_open = true
	_refresh()
	visible = true
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 1.0, FADE_SEC)


func _close() -> void:
	_open = false
	var t: Tween = create_tween()
	t.tween_property(self, "modulate:a", 0.0, FADE_SEC)
	t.tween_callback(func() -> void: visible = false)


func _refresh() -> void:
	for child in _vbox.get_children():
		child.queue_free()

	if _inventory == null:
		return

	var relics: Array[RelicData] = _inventory.get_relics()
	var max_slots: int = _inventory.max_slots
	_title.text = "Inventaire des reliques  (%d / %d)" % [relics.size(), max_slots]
	_hint.text = "Appuie sur Y pour fermer"

	for i in range(max_slots):
		var has_relic: bool = i < relics.size()
		var card := _build_card(has_relic, relics[i] if has_relic else null, i + 1)
		_vbox.add_child(card)


func _build_card(filled: bool, data: RelicData, idx: int) -> PanelContainer:
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.09, 0.10, 0.13, 0.92) if filled else Color(0.06, 0.07, 0.09, 0.70)
	style.border_color = data.tier_color() if filled else Color(0.25, 0.27, 0.32, 1.0)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	panel.add_theme_stylebox_override(&"panel", style)

	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 14)
	panel.add_child(hbox)

	# Slot index label (gauche)
	var idx_label := Label.new()
	idx_label.text = str(idx)
	idx_label.custom_minimum_size = Vector2(28, 0)
	idx_label.add_theme_font_size_override(&"font_size", 24)
	idx_label.add_theme_color_override(&"font_color", Color(0.55, 0.55, 0.6))
	idx_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	hbox.add_child(idx_label)

	# Icône (placeholder lettre si icon=null)
	var icon_panel := PanelContainer.new()
	icon_panel.custom_minimum_size = Vector2(64, 64)
	var icon_style := StyleBoxFlat.new()
	icon_style.bg_color = Color(0.13, 0.14, 0.18, 1.0)
	icon_style.set_corner_radius_all(4)
	if filled:
		icon_style.border_color = data.tier_color()
		icon_style.set_border_width_all(1)
	icon_panel.add_theme_stylebox_override(&"panel", icon_style)
	hbox.add_child(icon_panel)

	if filled and data.icon != null:
		var tex := TextureRect.new()
		tex.texture = data.icon
		tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon_panel.add_child(tex)
	elif filled:
		var letter := Label.new()
		letter.text = data.display_name.substr(0, 1).to_upper()
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override(&"font_size", 32)
		letter.add_theme_color_override(&"font_color", data.tier_color())
		icon_panel.add_child(letter)

	# Colonne droite : nom, tier, description, flavor
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override(&"separation", 2)
	hbox.add_child(col)

	if not filled:
		var empty_label := Label.new()
		empty_label.text = "Slot vide"
		empty_label.add_theme_font_size_override(&"font_size", 18)
		empty_label.add_theme_color_override(&"font_color", Color(0.5, 0.5, 0.55))
		col.add_child(empty_label)
		return panel

	var name_label := Label.new()
	name_label.text = data.display_name
	name_label.add_theme_font_size_override(&"font_size", 20)
	name_label.add_theme_color_override(&"font_color", Color(0.95, 0.95, 0.85))
	col.add_child(name_label)

	var tier_label := Label.new()
	tier_label.text = data.tier_name()
	tier_label.add_theme_font_size_override(&"font_size", 14)
	tier_label.add_theme_color_override(&"font_color", data.tier_color())
	col.add_child(tier_label)

	var desc_label := Label.new()
	desc_label.text = data.description
	desc_label.add_theme_font_size_override(&"font_size", 14)
	desc_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(desc_label)

	if not data.flavor.is_empty():
		var flavor_label := Label.new()
		flavor_label.text = "« %s »" % data.flavor
		flavor_label.add_theme_font_size_override(&"font_size", 12)
		flavor_label.add_theme_color_override(&"font_color", Color(0.7, 0.7, 0.75))
		flavor_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(flavor_label)

	return panel

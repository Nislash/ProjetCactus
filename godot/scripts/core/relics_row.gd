class_name RelicsRow
extends Control

## Rangée HUD des reliques équipées (5 slots horizontaux). Bind à un
## RelicInventory et se rafraîchit sur inventory_changed.

const SLOT_COUNT := 5
const SLOT_SIZE := Vector2(56.0, 56.0)
const SLOT_SPACING := 6.0

var _inventory: RelicInventory = null
var _slot_panels: Array[PanelContainer] = []
var _slot_icons: Array[TextureRect] = []
var _slot_letters: Array[Label] = []


func _ready() -> void:
	# Construit les 5 slots procéduralement pour ne pas dupliquer la scène
	# (et garder un seul .tscn léger).
	custom_minimum_size = Vector2(
		SLOT_COUNT * SLOT_SIZE.x + (SLOT_COUNT - 1) * SLOT_SPACING,
		SLOT_SIZE.y
	)
	var hbox := HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", int(SLOT_SPACING))
	hbox.anchor_right = 1.0
	hbox.anchor_bottom = 1.0
	add_child(hbox)
	for i in range(SLOT_COUNT):
		var panel := PanelContainer.new()
		panel.custom_minimum_size = SLOT_SIZE
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.06, 0.07, 0.09, 0.85)
		style.border_color = Color(0.25, 0.27, 0.32, 1.0)
		style.set_border_width_all(2)
		style.set_corner_radius_all(6)
		panel.add_theme_stylebox_override(&"panel", style)
		hbox.add_child(panel)
		_slot_panels.append(panel)

		var icon := TextureRect.new()
		icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		icon.size_flags_vertical = Control.SIZE_EXPAND_FILL
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(icon)
		_slot_icons.append(icon)

		# Label placeholder : 1ère lettre du nom de la relique tant qu'on n'a
		# pas d'icônes (sprint art futur).
		var letter := Label.new()
		letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		letter.add_theme_font_size_override(&"font_size", 24)
		letter.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		letter.size_flags_vertical = Control.SIZE_EXPAND_FILL
		letter.mouse_filter = Control.MOUSE_FILTER_IGNORE
		panel.add_child(letter)
		_slot_letters.append(letter)

	_refresh()


func bind(inventory: RelicInventory) -> void:
	if _inventory != null and _inventory.inventory_changed.is_connected(_refresh):
		_inventory.inventory_changed.disconnect(_refresh)
	_inventory = inventory
	if _inventory != null:
		_inventory.inventory_changed.connect(_refresh)
	_refresh()


func _refresh() -> void:
	var relics: Array[RelicData] = []
	if _inventory != null:
		relics = _inventory.get_relics()
	for i in range(SLOT_COUNT):
		var has_relic: bool = i < relics.size()
		var panel: PanelContainer = _slot_panels[i]
		var icon: TextureRect = _slot_icons[i]
		var letter: Label = _slot_letters[i]
		if has_relic:
			var data: RelicData = relics[i]
			icon.texture = data.icon
			letter.text = "" if data.icon != null else _first_letter(data.display_name)
			letter.add_theme_color_override(&"font_color", data.tier_color())
			_set_border_color(panel, data.tier_color())
		else:
			icon.texture = null
			letter.text = ""
			_set_border_color(panel, Color(0.25, 0.27, 0.32, 1.0))


func _set_border_color(panel: PanelContainer, color: Color) -> void:
	var style: StyleBoxFlat = panel.get_theme_stylebox(&"panel") as StyleBoxFlat
	if style == null:
		return
	style = style.duplicate() as StyleBoxFlat
	style.border_color = color
	panel.add_theme_stylebox_override(&"panel", style)


func _first_letter(s: String) -> String:
	if s.is_empty():
		return "?"
	return s.substr(0, 1).to_upper()

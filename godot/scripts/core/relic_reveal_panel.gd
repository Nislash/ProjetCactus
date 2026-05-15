class_name RelicRevealPanel
extends PanelContainer

## Popup centrale qui s'affiche dans le SubViewport d'un joueur quand il
## ramasse une relique. Fade-in 0.3 s → hold ~3.3 s → fade-out 0.4 s.
## Si plusieurs reliques arrivent rapidement, on file d'attente.

const FADE_IN_SEC := 0.3
const FADE_OUT_SEC := 0.4

var _inventory: RelicInventory = null
var _queue: Array[RelicData] = []
var _showing: bool = false

@onready var _icon: TextureRect = $Margin/VBox/Header/Icon
@onready var _name_label: Label = $Margin/VBox/NameLabel
@onready var _tier_label: Label = $Margin/VBox/TierLabel
@onready var _desc_label: Label = $Margin/VBox/DescLabel
@onready var _flavor_label: Label = $Margin/VBox/FlavorLabel


func _ready() -> void:
	modulate.a = 0.0
	visible = false


func bind(inventory: RelicInventory) -> void:
	if _inventory != null and _inventory.relic_added.is_connected(_on_relic_added):
		_inventory.relic_added.disconnect(_on_relic_added)
	_inventory = inventory
	if _inventory != null:
		_inventory.relic_added.connect(_on_relic_added)


func _on_relic_added(data: RelicData) -> void:
	_queue.append(data)
	if not _showing:
		_show_next()


func _show_next() -> void:
	if _queue.is_empty():
		_showing = false
		return
	_showing = true
	var data: RelicData = _queue.pop_front()
	_apply(data)
	visible = true
	modulate.a = 0.0
	var hold_sec: float = 4.0 - FADE_IN_SEC - FADE_OUT_SEC
	var tween: Tween = create_tween()
	tween.tween_property(self, "modulate:a", 1.0, FADE_IN_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_interval(hold_sec)
	tween.tween_property(self, "modulate:a", 0.0, FADE_OUT_SEC) \
		.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
	tween.tween_callback(_on_finished)


func _on_finished() -> void:
	visible = false
	_show_next()


func _apply(data: RelicData) -> void:
	_icon.texture = data.icon
	_name_label.text = data.display_name
	_tier_label.text = data.tier_name()
	_tier_label.add_theme_color_override(&"font_color", data.tier_color())
	_desc_label.text = data.description
	if data.flavor.is_empty():
		_flavor_label.visible = false
	else:
		_flavor_label.visible = true
		_flavor_label.text = "« %s »" % data.flavor

class_name BossPostCombat
extends Control

## Écran de stats post-combat boss. Affiché à la mort du boss avec :
## - Temps de combat (mm:ss)
## - Camembert ou barres % des dégâts infligés par chaque joueur
## - Nom de la relique droppée
## - "Appuyez sur n'importe quel bouton pour continuer"
##
## Auto-bind : scan le group "bosses", écoute boss_defeated. À l'input, hide.

signal continued()

const _PLAYER_COLORS: Array = [
	Color(1.0, 0.35, 0.35, 1.0),   # P0 rouge
	Color(0.4, 0.65, 1.0, 1.0),    # P1 bleu
	Color(0.4, 1.0, 0.45, 1.0),    # P2 vert
	Color(1.0, 0.9, 0.35, 1.0),    # P3 jaune
]

@onready var _title: Label = $Panel/VBox/Title
@onready var _time_label: Label = $Panel/VBox/Time
@onready var _damage_container: VBoxContainer = $Panel/VBox/DamageStats
@onready var _relic_label: Label = $Panel/VBox/Relic
@onready var _hint_label: Label = $Panel/VBox/Hint

var _waiting_for_input: bool = false


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Scan régulier du group pour s'auto-bind quand un boss apparaît.
	get_tree().process_frame.connect(_try_bind)


func _try_bind() -> void:
	for node in get_tree().get_nodes_in_group(&"bosses"):
		if not (node is BossBase):
			continue
		var b: BossBase = node
		if not b.boss_defeated.is_connected(_on_boss_defeated):
			b.boss_defeated.connect(_on_boss_defeated)


func _on_boss_defeated(damage_by_player: Dictionary, fight_duration_sec: float, dropped_relic: RelicData) -> void:
	var relic_name: String = "—"
	if dropped_relic != null:
		relic_name = "%s  [Légendaire]" % dropped_relic.display_name
	_show(damage_by_player, fight_duration_sec, relic_name)


## Public si on veut driver l'affichage manuellement (ex: depuis le drop relique
## qui voudrait passer le nom de la relique en plus).
func show_with_relic(damage_by_player: Dictionary, fight_duration_sec: float, relic_name: String) -> void:
	_show(damage_by_player, fight_duration_sec, relic_name)


func _show(damage_by_player: Dictionary, fight_duration_sec: float, relic_name: String) -> void:
	_title.text = "VICTOIRE"
	_time_label.text = "Temps : %s" % _format_duration(fight_duration_sec)
	# Vide le container précédent.
	for child in _damage_container.get_children():
		child.queue_free()
	# Total dégâts pour calculer les %.
	var total: int = 0
	for v in damage_by_player.values():
		total += int(v)
	if total <= 0:
		total = 1
	# Trie par player_id croissant pour stabilité visuelle.
	var pids: Array = damage_by_player.keys()
	pids.sort()
	for pid in pids:
		var dmg: int = int(damage_by_player[pid])
		var pct: float = float(dmg) * 100.0 / float(total)
		_damage_container.add_child(_make_damage_row(int(pid), dmg, pct))
	if relic_name.is_empty():
		_relic_label.text = "Relique : —"
	else:
		_relic_label.text = "Relique : %s" % relic_name
	_hint_label.text = "Appuyez sur n'importe quel bouton pour continuer"
	visible = true
	_waiting_for_input = true


func _make_damage_row(player_id: int, damage: int, pct: float) -> Control:
	var hbox: HBoxContainer = HBoxContainer.new()
	hbox.add_theme_constant_override(&"separation", 8)
	var swatch: ColorRect = ColorRect.new()
	swatch.custom_minimum_size = Vector2(20, 20)
	swatch.color = _get_player_color(player_id)
	hbox.add_child(swatch)
	var lbl: Label = Label.new()
	lbl.text = "Player %d  —  %d dmg  (%.1f%%)" % [player_id + 1, damage, pct]
	hbox.add_child(lbl)
	var bar: ProgressBar = ProgressBar.new()
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar.max_value = 100
	bar.value = pct
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 18)
	hbox.add_child(bar)
	return hbox


func _get_player_color(player_id: int) -> Color:
	if player_id < 0 or player_id >= _PLAYER_COLORS.size():
		return Color.WHITE
	return _PLAYER_COLORS[player_id]


func _format_duration(sec: float) -> String:
	var total_s: int = int(sec)
	var m: int = total_s / 60
	var s: int = total_s % 60
	return "%02d:%02d" % [m, s]


func _input(event: InputEvent) -> void:
	if not _waiting_for_input:
		return
	# N'importe quel input (clavier, gamepad bouton, souris clic).
	if event is InputEventKey and event.pressed:
		_dismiss()
	elif event is InputEventJoypadButton and event.pressed:
		_dismiss()
	elif event is InputEventMouseButton and event.pressed:
		_dismiss()


func _dismiss() -> void:
	_waiting_for_input = false
	visible = false
	continued.emit()

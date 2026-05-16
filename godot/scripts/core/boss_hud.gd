class_name BossHUD
extends Control

## HUD boss global, au-dessus du split-screen. Une seule barre de vie en
## haut d'écran avec nom + indicateur de phase (3 dots), quel que soit le
## nombre de joueurs (1, 2, 3 ou 4).
##
## Auto-bind : scanne le group "bosses" au _process. Quand un boss devient
## engaged (boss_engaged émis), le HUD apparaît et se branche. À la mort,
## il se cache.

@onready var _name_label: Label = $Panel/VBox/Name
@onready var _hp_bar: ProgressBar = $Panel/VBox/HPBar
@onready var _phase_dot_1: ColorRect = $Panel/VBox/Phases/Dot1
@onready var _phase_dot_2: ColorRect = $Panel/VBox/Phases/Dot2
@onready var _phase_dot_3: ColorRect = $Panel/VBox/Phases/Dot3

var _boss: BossBase = null


func _ready() -> void:
	visible = false
	set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if _boss == null or not is_instance_valid(_boss):
		_try_find_boss()


func _try_find_boss() -> void:
	for node in get_tree().get_nodes_in_group(&"bosses"):
		if not (node is BossBase):
			continue
		var b: BossBase = node
		if not b.is_engaged():
			# Pas encore engagé — on écoute son engage signal.
			if not b.boss_engaged.is_connected(_on_boss_engaged.bind(b)):
				b.boss_engaged.connect(_on_boss_engaged.bind(b), CONNECT_ONE_SHOT)
			continue
		_bind_to(b)
		return


func _on_boss_engaged(b: BossBase) -> void:
	_bind_to(b)


func _bind_to(b: BossBase) -> void:
	if _boss != null:
		return
	_boss = b
	var hc: HealthComponent = b.get_health()
	if hc != null:
		_hp_bar.max_value = hc.max_health
		_hp_bar.value = hc.current_health
		hc.health_changed.connect(_on_health_changed)
	if b.boss_data != null:
		_name_label.text = b.boss_data.boss_name_display
	else:
		_name_label.text = "Boss"
	b.phase_changed.connect(_on_phase_changed)
	b.boss_defeated.connect(_on_boss_defeated)
	_update_phase_dots(b.get_current_phase())
	visible = true


func _on_health_changed(current: int, _maxv: int) -> void:
	_hp_bar.value = current


func _on_phase_changed(new_phase: int) -> void:
	_update_phase_dots(new_phase)


func _update_phase_dots(phase: int) -> void:
	# Couleur pleine = phase courante ou passée, terne = à venir.
	var active: Color = Color(1, 0.8, 0.2, 1)
	var dim: Color = Color(0.3, 0.3, 0.3, 1)
	# Mapping Phase enum -> index dots.
	# PHASE_1=1, TRANSITION_1_TO_2=2, PHASE_2=3, TRANSITION_2_TO_3=4, PHASE_3=5
	var reached_phase_2: bool = phase >= BossBase.Phase.PHASE_2
	var reached_phase_3: bool = phase >= BossBase.Phase.PHASE_3_ENRAGE
	_phase_dot_1.color = active
	_phase_dot_2.color = active if reached_phase_2 else dim
	_phase_dot_3.color = Color(1, 0.3, 0.2, 1) if reached_phase_3 else dim


func _on_boss_defeated(_damage_by_player: Dictionary, _duration: float, _dropped_relic: RelicData) -> void:
	# Fade-out simple (instantané pour le POC).
	visible = false
	_boss = null

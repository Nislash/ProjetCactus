extends Control

## HUD basique d'un joueur (M1). Affiche jauge HP + compteur de morts.
## Instancié dans le SubViewport du joueur par SplitScreenManager.bind_to_player(...).

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _deaths_label: Label = %DeathsLabel


func bind_to_player(player: PlayerController) -> void:
	var hc: HealthComponent = player.get_health()
	hc.health_changed.connect(_on_health_changed)
	player.death_count_changed.connect(_on_death_count_changed)
	_on_health_changed(hc.current_health, hc.max_health)
	_on_death_count_changed(player.death_count)


func _on_health_changed(current: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	_hp_label.text = "HP %d / %d" % [current, max_hp]


func _on_death_count_changed(count: int) -> void:
	_deaths_label.text = "Morts : %d" % count

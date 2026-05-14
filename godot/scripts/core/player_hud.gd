extends Control

## HUD d'un joueur (M1). Affiche HP, ammo, sort équipé, compteur morts,
## mini-map placeholder. Instancié dans le SubViewport du joueur par
## SplitScreenManager._spawn_slot().
##
## Layout :
## - Bas-gauche  : HP (bar + label) + compteur morts
## - Bas-droite  : ammo + indicateur RELOAD
## - Bas-centre  : sort équipé (placeholder M1)
## - Haut-droite : mini-map (placeholder M1)
## - Centre      : crosshair (4 traits + dot)

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _deaths_label: Label = %DeathsLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _reload_label: Label = %ReloadLabel
@onready var _spell_label: Label = %SpellLabel


func bind_to_player(player: PlayerController) -> void:
	var hc: HealthComponent = player.get_health()
	hc.health_changed.connect(_on_health_changed)
	player.death_count_changed.connect(_on_death_count_changed)
	_on_health_changed(hc.current_health, hc.max_health)
	_on_death_count_changed(player.death_count)

	var weapon: WeaponHitscan = player.get_weapon()
	if weapon != null:
		weapon.ammo_changed.connect(_on_ammo_changed)
		weapon.reload_started.connect(_on_reload_started)
		weapon.reload_finished.connect(_on_reload_finished)
		_on_ammo_changed(weapon.current_ammo, weapon.max_ammo)
		_reload_label.text = ""

	# M1 : pas de sort équipé. Slot placeholder qu'on remplira en M2
	# quand les `SpellData.tres` arriveront.
	_spell_label.text = "Sort : —"


func _on_health_changed(current: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	_hp_label.text = "HP %d / %d" % [current, max_hp]


func _on_death_count_changed(count: int) -> void:
	_deaths_label.text = "Morts : %d" % count


func _on_ammo_changed(current: int, max_ammo: int) -> void:
	_ammo_label.text = "%d / %d" % [current, max_ammo]


func _on_reload_started() -> void:
	_reload_label.text = "RECHARGEMENT…"


func _on_reload_finished() -> void:
	_reload_label.text = ""

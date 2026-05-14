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
@onready var _weapon_label: Label = %WeaponLabel

var _bound_player: PlayerController


func bind_to_player(player: PlayerController) -> void:
	_bound_player = player
	var hc: HealthComponent = player.get_health()
	hc.health_changed.connect(_on_health_changed)
	player.death_count_changed.connect(_on_death_count_changed)
	player.downed.connect(_on_downed)
	player.revived.connect(_on_revived)
	player.revive_progress_changed.connect(_on_revive_progress_changed)
	player.pickup_progress_changed.connect(_on_pickup_progress_changed)
	_on_health_changed(hc.current_health, hc.max_health)
	_on_death_count_changed(player.death_count)

	var weapon: WeaponHitscan = player.get_weapon()
	if weapon != null:
		weapon.ammo_changed.connect(_on_ammo_changed)
		weapon.reload_started.connect(_on_reload_started)
		weapon.reload_finished.connect(_on_reload_finished)
		weapon.weapon_name_changed.connect(_on_weapon_name_changed)
		_on_ammo_changed(weapon.current_ammo, weapon.max_ammo)
		_on_weapon_name_changed(weapon.get_display_name())
		_reload_label.text = ""

	# M1 : pas de sort équipé. Slot placeholder qu'on remplira en M2
	# quand les `SpellData.tres` arriveront.
	_spell_label.text = "Sort : —"


func _on_downed() -> void:
	# Surcharge le HP label pour signaler clairement l'état downed.
	_hp_label.text = "▼ À TERRE — Allié : maintenir X pour relever"
	_hp_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2, 1))


func _on_revived() -> void:
	_hp_label.remove_theme_color_override("font_color")
	# La valeur HP réelle sera réémise par health_changed lors du reset().


func _on_revive_progress_changed(target_player_id: int, progress: float) -> void:
	if progress <= 0.0:
		_spell_label.text = "Sort : —"
		return
	var pct: int = int(progress * 100.0)
	_spell_label.text = "Relève J%d… %d%%" % [target_player_id, pct]


func _on_health_changed(current: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	# Si le joueur est downed, on garde le label custom (set par _on_downed).
	if _bound_player != null and _bound_player.is_downed():
		return
	_hp_label.text = "HP %d / %d" % [current, max_hp]


func _on_death_count_changed(count: int) -> void:
	_deaths_label.text = "Morts : %d" % count


func _on_ammo_changed(current: int, max_ammo: int) -> void:
	_ammo_label.text = "%d / %d" % [current, max_ammo]


func _on_reload_started() -> void:
	_reload_label.text = "RECHARGEMENT…"


func _on_reload_finished() -> void:
	_reload_label.text = ""


func _on_weapon_name_changed(new_name: String) -> void:
	_weapon_label.text = new_name


## Le slot _spell_label sert aussi de message ramassage pendant un pickup.
## Quand le pickup est annulé, on revient au texte "Sort : —".
func _on_pickup_progress_changed(pickup_name: String, progress: float) -> void:
	if progress <= 0.0 or pickup_name.is_empty():
		_spell_label.text = "Sort : —"
		return
	var pct: int = int(progress * 100.0)
	_spell_label.text = "Ramasse %s… %d%%" % [pickup_name, pct]

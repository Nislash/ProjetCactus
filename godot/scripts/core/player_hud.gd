extends Control

## HUD d'un joueur. Instancié dans le SubViewport du joueur par
## SplitScreenManager._spawn_slot().
##
## Layout :
## - Bas-gauche  : HP bar + label + compteur morts
## - Bas-droite  : icône d'arme + nom + ammo + reload
## - Bas-centre  : sort équipé / prompt d'interaction
## - Haut-droite : mini-map (placeholder)
## - Centre      : crosshair
##
## L'icône d'arme est chargée dynamiquement depuis :
##   res://assets/textures/weapons/{kind}_{element}.png
## kind = "gun" ou "sword"
## element = "default" / "fire" / "ice" / "thunder" / "poison"
##
## Si le PNG n'existe pas (asset pas encore généré) le HUD ne plante pas —
## TextureRect reste vide, le label texte sert de fallback.

const WEAPON_ICON_DIR := "res://assets/textures/weapons/"

# Mapping nom de gemme affiché → element key utilisée dans le path d'asset.
# Si la gemme équipée n'est pas dans ce dict, on tombe sur "default".
const SPELL_NAME_TO_ELEMENT: Dictionary = {
	"": "default",
	"Feu": "fire",
	"Glace": "ice",
	"Foudre": "thunder",
	"Poison": "poison",
}

@onready var _hp_bar: ProgressBar = %HpBar
@onready var _hp_label: Label = %HpLabel
@onready var _deaths_label: Label = %DeathsLabel
@onready var _ammo_label: Label = %AmmoLabel
@onready var _reload_label: Label = %ReloadLabel
@onready var _spell_label: Label = %SpellLabel
@onready var _weapon_label: Label = %WeaponLabel
@onready var _weapon_icon: TextureRect = %WeaponIcon
@onready var _relics_row: RelicsRow = %RelicsRow if has_node("%RelicsRow") else null
@onready var _relic_reveal: RelicRevealPanel = %RelicRevealPanel if has_node("%RelicRevealPanel") else null
@onready var _relic_inventory_screen: RelicInventoryScreen = %RelicInventoryScreen if has_node("%RelicInventoryScreen") else null
@onready var _minimap_panel: Control = $MinimapPanel
@onready var _minimap_background: ColorRect = $MinimapPanel/Background
@onready var _minimap_player_dot: ColorRect = $MinimapPanel/PlayerDot
@onready var _minimap_container: SubViewportContainer = %MinimapViewportContainer
@onready var _minimap_viewport: SubViewport = %MinimapViewport
@onready var _minimap_camera: MinimapCamera = %MinimapCamera

# Panel STATS (haut-gauche) : labels mis à jour à chaque inventory_changed
# et toutes les STATS_REFRESH_SEC pour capter les buffs temporaires.
@onready var _stat_spd: Label = $StatsPanel/Grid/StatSpd
@onready var _stat_dmg: Label = $StatsPanel/Grid/StatDmg
@onready var _stat_crt: Label = $StatsPanel/Grid/StatCrt
@onready var _stat_fr: Label = $StatsPanel/Grid/StatFr
@onready var _stat_hp: Label = $StatsPanel/Grid/StatHp
@onready var _stat_reg: Label = $StatsPanel/Grid/StatReg
const STATS_REFRESH_SEC: float = 0.25
var _stats_refresh_accum: float = 0.0

enum MinimapState { MINI, FULL, HIDDEN }
var _minimap_state: MinimapState = MinimapState.MINI

# Tailles ortho de la caméra par état (plus grand = plus zoom-out).
const MINIMAP_ORTHO_MINI: float = 32.0
const MINIMAP_ORTHO_FULL: float = 80.0

var _bound_player: PlayerController = null
## Arme actuellement écoutée pour ammo/reload/name. Évite de double-bind
## les signaux à chaque switch d'arme.
var _bound_weapon: Node = null


func bind_to_player(player: PlayerController) -> void:
	_bound_player = player

	var hc: HealthComponent = player.get_health()
	hc.health_changed.connect(_on_health_changed)
	player.death_count_changed.connect(_on_death_count_changed)
	player.downed.connect(_on_downed)
	player.revived.connect(_on_revived)
	player.interaction_progress_changed.connect(_on_interaction_progress_changed)
	player.weapon_equipped.connect(_on_weapon_equipped)
	_on_health_changed(hc.current_health, hc.max_health)
	_on_death_count_changed(player.death_count)

	# État initial : aucune arme équipée tant que le joueur n'a pas ramassé
	# un WeaponPickup. equip_weapon_kind() émettra weapon_equipped quand
	# c'est fait.
	_set_no_weapon_state()
	_spell_label.text = "Sort : —"

	# Bind des éléments reliques (rangée + popup d'annonce + écran inventaire).
	if _relics_row != null and player.relic_inventory != null:
		_relics_row.bind(player.relic_inventory)
	if _relic_reveal != null and player.relic_inventory != null:
		_relic_reveal.bind(player.relic_inventory)
		player.relic_inventory.inventory_full_attempt.connect(_on_inventory_full_attempt)
	if _relic_inventory_screen != null:
		_relic_inventory_screen.bind(player)

	# Refresh immédiat sur changement d'inventaire (ajout/perte de relique).
	# Le _process se charge des buffs temporaires entre deux events.
	if player.relic_inventory != null \
		and not player.relic_inventory.inventory_changed.is_connected(_refresh_stats):
		player.relic_inventory.inventory_changed.connect(_refresh_stats)
	_refresh_stats()

	_setup_minimap(player)


func _process(delta: float) -> void:
	if _bound_player == null:
		return
	_stats_refresh_accum += delta
	if _stats_refresh_accum >= STATS_REFRESH_SEC:
		_stats_refresh_accum = 0.0
		_refresh_stats()


## Pull-stats du joueur → labels du StatsPanel. Format compact pour rester
## lisible en 4-split. DMG/FR sont des multiplicateurs (1.0 = base) affichés
## en delta (+X%). CRT en pourcentage absolu. SPD/HP/REG en valeurs absolues.
func _refresh_stats() -> void:
	if _bound_player == null:
		return
	_stat_spd.text = "%.1f" % _bound_player.get_move_speed()
	var dmg_delta: float = (_bound_player.get_damage_mult() - 1.0) * 100.0
	_stat_dmg.text = "%+d%%" % roundi(dmg_delta) if dmg_delta != 0.0 else "+0%"
	_stat_crt.text = "%d%%" % roundi(_bound_player.get_crit_chance() * 100.0)
	var fr_delta: float = (_bound_player.get_fire_rate_mult() - 1.0) * 100.0
	_stat_fr.text = "%+d%%" % roundi(fr_delta) if fr_delta != 0.0 else "+0%"
	_stat_hp.text = "%d" % _bound_player.get_max_hp()
	var reg: float = _bound_player.get_hp_regen_per_sec()
	_stat_reg.text = "%.1f/s" % reg if reg > 0.0 else "—"


## Branche le SubViewport minimap sur le world_3d partagé et fait suivre
## la caméra orthographique sur ce joueur. Appelé une fois au bind.
func _setup_minimap(player: PlayerController) -> void:
	# Le SubViewport doit partager le World3D du root (sinon il rend dans
	# un monde vide). Cf SplitScreenManager qui fait le même setup pour
	# les viewports principaux.
	_minimap_viewport.world_3d = get_tree().root.world_3d
	_minimap_camera.set_follow_target(player)
	# D-pad up cycle l'état de la minimap (MINI → FULL → HIDDEN → MINI).
	player.minimap_toggle_requested.connect(_cycle_minimap_state)
	# Le viewport doit pouvoir s'ajuster aux resizes du HUD (split-screen
	# layout change quand un joueur join/quit).
	resized.connect(_apply_minimap_layout)
	_apply_minimap_layout()


func _cycle_minimap_state() -> void:
	match _minimap_state:
		MinimapState.MINI:
			_minimap_state = MinimapState.FULL
		MinimapState.FULL:
			_minimap_state = MinimapState.HIDDEN
		MinimapState.HIDDEN:
			_minimap_state = MinimapState.MINI
	_apply_minimap_layout()


## Met à jour position/taille du panel + size du SubViewport + opacité du
## background selon l'état courant. La taille FULL est calculée depuis la
## taille du HUD (qui suit son SubViewport en split-screen — chaque joueur
## a sa propre échelle).
func _apply_minimap_layout() -> void:
	if _minimap_panel == null:
		return
	match _minimap_state:
		MinimapState.HIDDEN:
			_minimap_panel.visible = false
		MinimapState.MINI:
			_minimap_panel.visible = true
			# Coin haut-droite, 160×160
			_minimap_panel.anchor_left = 1.0
			_minimap_panel.anchor_top = 0.0
			_minimap_panel.anchor_right = 1.0
			_minimap_panel.anchor_bottom = 0.0
			_minimap_panel.offset_left = -184.0
			_minimap_panel.offset_top = 24.0
			_minimap_panel.offset_right = -24.0
			_minimap_panel.offset_bottom = 184.0
			_minimap_background.color.a = 0.85
			_minimap_container.set_deferred("offset_left", 4.0)
			_minimap_container.set_deferred("offset_top", 4.0)
			_minimap_container.set_deferred("offset_right", 156.0)
			_minimap_container.set_deferred("offset_bottom", 156.0)
			_minimap_viewport.size = Vector2i(152, 152)
			_minimap_camera.size = MINIMAP_ORTHO_MINI
		MinimapState.FULL:
			_minimap_panel.visible = true
			# Centré, 50% width × 60% height de la taille du HUD courant.
			# En split-screen, le HUD est dans le SubViewport du joueur,
			# donc size correspond bien à son quart d'écran.
			var hud_size: Vector2 = size
			var w: float = hud_size.x * 0.5
			var h: float = hud_size.y * 0.6
			_minimap_panel.anchor_left = 0.5
			_minimap_panel.anchor_top = 0.5
			_minimap_panel.anchor_right = 0.5
			_minimap_panel.anchor_bottom = 0.5
			_minimap_panel.offset_left = -w * 0.5
			_minimap_panel.offset_top = -h * 0.5
			_minimap_panel.offset_right = w * 0.5
			_minimap_panel.offset_bottom = h * 0.5
			_minimap_background.color.a = 0.35
			# Le viewport occupe toute la zone (- 4px de marge cohérence).
			_minimap_container.set_deferred("offset_left", 4.0)
			_minimap_container.set_deferred("offset_top", 4.0)
			_minimap_container.set_deferred("offset_right", w - 4.0)
			_minimap_container.set_deferred("offset_bottom", h - 4.0)
			_minimap_viewport.size = Vector2i(int(w - 8), int(h - 8))
			_minimap_camera.size = MINIMAP_ORTHO_FULL


func _on_downed() -> void:
	_hp_label.text = "▼ À TERRE — Allié : maintenir X pour relever"
	_hp_label.add_theme_color_override("font_color", Color(1, 0.3, 0.2, 1))


func _on_revived() -> void:
	_hp_label.remove_theme_color_override("font_color")


func _on_health_changed(current: int, max_hp: int) -> void:
	_hp_bar.max_value = max_hp
	_hp_bar.value = current
	if _bound_player != null and _bound_player.is_downed():
		return
	_hp_label.text = "HP %d / %d" % [current, max_hp]


func _on_death_count_changed(count: int) -> void:
	_deaths_label.text = "Morts : %d" % count


## Switch d'arme (joueur a ramassé un WeaponPickup). On débranche les
## signaux de l'ancienne arme et on rebranche sur la nouvelle.
func _on_weapon_equipped(kind: StringName) -> void:
	_unbind_current_weapon_signals()

	match kind:
		&"pistol":
			_bound_weapon = _bound_player.get_weapon()
			if _bound_weapon != null:
				_bind_pistol_signals(_bound_weapon as WeaponHitscan)
		&"melee":
			_bound_weapon = _bound_player.get_melee()
			if _bound_weapon != null:
				_bind_melee_signals(_bound_weapon as WeaponMelee)
		_:
			_bound_weapon = null
			_set_no_weapon_state()


func _unbind_current_weapon_signals() -> void:
	if _bound_weapon == null:
		return
	if _bound_weapon is WeaponHitscan:
		var w: WeaponHitscan = _bound_weapon as WeaponHitscan
		if w.ammo_changed.is_connected(_on_ammo_changed):
			w.ammo_changed.disconnect(_on_ammo_changed)
		if w.reload_started.is_connected(_on_reload_started):
			w.reload_started.disconnect(_on_reload_started)
		if w.reload_finished.is_connected(_on_reload_finished):
			w.reload_finished.disconnect(_on_reload_finished)
		if w.weapon_name_changed.is_connected(_on_weapon_name_changed):
			w.weapon_name_changed.disconnect(_on_weapon_name_changed)
	elif _bound_weapon is WeaponMelee:
		var m: WeaponMelee = _bound_weapon as WeaponMelee
		if m.weapon_name_changed.is_connected(_on_weapon_name_changed):
			m.weapon_name_changed.disconnect(_on_weapon_name_changed)


func _bind_pistol_signals(w: WeaponHitscan) -> void:
	w.ammo_changed.connect(_on_ammo_changed)
	w.reload_started.connect(_on_reload_started)
	w.reload_finished.connect(_on_reload_finished)
	w.weapon_name_changed.connect(_on_weapon_name_changed)
	_on_ammo_changed(w.current_ammo, w.max_ammo)
	_on_weapon_name_changed(w.get_display_name())
	_reload_label.text = ""


func _bind_melee_signals(m: WeaponMelee) -> void:
	m.weapon_name_changed.connect(_on_weapon_name_changed)
	_on_weapon_name_changed(m.get_display_name())
	_ammo_label.text = "—"
	_reload_label.text = ""


func _set_no_weapon_state() -> void:
	_weapon_label.text = "Sans arme"
	_ammo_label.text = "—"
	_reload_label.text = ""
	_weapon_icon.texture = null


func _on_ammo_changed(current: int, max_ammo: int) -> void:
	_ammo_label.text = "%d / %d" % [current, max_ammo]


func _on_reload_started() -> void:
	_reload_label.text = "RECHARGEMENT…"


func _on_reload_finished() -> void:
	_reload_label.text = ""


## Met à jour le nom + l'icône. Le nom passe par get_display_name() de
## l'arme, qui retourne soit "Pistolet" soit "Pistolet × Feu" selon la
## gemme équipée.
func _on_weapon_name_changed(new_name: String) -> void:
	_weapon_label.text = new_name
	_refresh_weapon_icon()


## Construit le path d'asset selon arme + gemme actuellement équipée et
## charge la texture si elle existe. Sinon laisse vide (graceful).
func _refresh_weapon_icon() -> void:
	if _bound_player == null:
		_weapon_icon.texture = null
		return
	var kind_str: String = _kind_to_string(_bound_player.get_equipped_weapon_kind())
	if kind_str.is_empty():
		_weapon_icon.texture = null
		return
	var element: String = _current_element_key()
	var path: String = "%s%s_%s.png" % [WEAPON_ICON_DIR, kind_str, element]
	if ResourceLoader.exists(path, "Texture2D"):
		_weapon_icon.texture = load(path) as Texture2D
	else:
		# Fallback : essaie l'asset default de la même arme
		var default_path: String = "%s%s_default.png" % [WEAPON_ICON_DIR, kind_str]
		if ResourceLoader.exists(default_path, "Texture2D"):
			_weapon_icon.texture = load(default_path) as Texture2D
		else:
			_weapon_icon.texture = null


func _kind_to_string(kind: StringName) -> String:
	match kind:
		&"pistol":
			return "gun"
		&"melee":
			return "sword"
		_:
			return ""


## Lit la gemme actuellement équipée sur l'arme courante. Pour le pistolet,
## c'est `equipped_spell_name`. La melee n'a pas encore de système de gemme,
## retourne toujours "default".
func _current_element_key() -> String:
	if _bound_weapon is WeaponHitscan:
		var name: String = (_bound_weapon as WeaponHitscan).equipped_spell_name
		return SPELL_NAME_TO_ELEMENT.get(name, "default")
	return "default"


## Le slot _spell_label sert aussi de message d'interaction pendant un hold.
func _on_interaction_progress_changed(prompt: String, progress: float) -> void:
	if progress <= 0.0 or prompt.is_empty():
		_spell_label.text = "Sort : —"
		return
	var pct: int = int(progress * 100.0)
	_spell_label.text = "%s… %d%%" % [prompt, pct]


## Petit toast quand l'inventaire de reliques est plein et que le joueur tente
## d'ouvrir un coffre. On réutilise le _spell_label pour ne pas ajouter de UI
## dédiée (auto-clear après 1.5 s).
var _full_toast_timer: SceneTreeTimer = null


func _on_inventory_full_attempt(_data) -> void:
	_spell_label.text = "Inventaire plein"
	if _full_toast_timer != null and _full_toast_timer.timeout.is_connected(_clear_full_toast):
		_full_toast_timer.timeout.disconnect(_clear_full_toast)
	_full_toast_timer = get_tree().create_timer(1.5)
	_full_toast_timer.timeout.connect(_clear_full_toast)


func _clear_full_toast() -> void:
	_spell_label.text = "Sort : —"

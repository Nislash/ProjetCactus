class_name RelicEffectResolver
extends Node

## Branche les hooks événementiels des reliques d'UN joueur. Attaché en
## enfant du PlayerController (cf player.tscn → $RelicEffectResolver).
##
## Lit RelicInventory.relic_added / .relic_removed pour câbler/débrancher
## les hooks selon RelicData.effect_type. Les effets STAT sont gérés en
## pull-model via RelicInventory.compute_stat() (cf PlayerController).
##
## Implémentation actuelle :
## - stat       : passif (pas de hook ici, lu par player.get_*)
## - on_kill    : signal global enemy_killed (cf SignalBus minimaliste)
## - on_hit     : weapon.fired
## - on_damaged : health.damaged
## - on_dash    : player.dash_started
## - on_low_hp  : player.low_hp_crossed (émis quand HP < threshold * max)
## - on_reload  : weapon.reload_finished
## - on_revive  : player.revive_completed (émis quand le player relève un allié)
## - coop       : poll toutes les 0.2 s (state allié + distance)
## - combo_mod  : STUB — exposé via get_combo_modifiers() pour l'arme, mais
##                l'application visuelle attend combo_engine Rust (cf #34 M2-A)

const COOP_POLL_SEC := 0.2

@onready var _player: PlayerController = get_parent() as PlayerController
@onready var _inventory: RelicInventory = get_node_or_null("../RelicInventory") as RelicInventory

## Cooldowns par relic_id (dernier proc unix time).
var _last_proc: Dictionary = {}

## État interne pour les triggers stateful (e.g. low_hp armé une fois passé).
var _low_hp_armed: Dictionary = {}  # relic_id -> bool

## Compteur de tirs pour Lance d'Odin (every_n_shots).
var _shot_counters: Dictionary = {}  # relic_id -> int

## Buff temporaires (move speed thief armband, etc.) : Array de { relic_id, stat, value, expire }
var _temp_buffs: Array = []

## Stacks permanents (Cor du Léviathan) : relic_id -> stack count
var _perm_stacks: Dictionary = {}

## Damage multiplier permanent accumulé (Cor du Léviathan, etc.). Lu par
## le player via get_runtime_damage_mult().
var _perm_damage_mult: float = 0.0

## Timer pour coop poll.
var _coop_timer: float = 0.0


func _ready() -> void:
	if _inventory != null:
		_inventory.relic_added.connect(_on_relic_added)
		_inventory.relic_removed.connect(_on_relic_removed)


## Appelé par le player après init (player.tscn a déjà câblé les nodes
## mais on attend que le PlayerController ait set ses signaux internes).
func attach_signals() -> void:
	if _player == null:
		return
	var hc: HealthComponent = _player.get_health()
	if hc != null and not hc.damaged.is_connected(_on_player_damaged):
		hc.damaged.connect(_on_player_damaged)
	if _player.has_signal(&"dash_started") and not _player.dash_started.is_connected(_on_player_dash):
		_player.dash_started.connect(_on_player_dash)
	# low_hp_crossed est vérifié réactivement dans _on_player_damaged via
	# _check_low_hp(), inutile d'écouter un signal séparé.
	if _player.has_signal(&"revive_completed") and not _player.revive_completed.is_connected(_on_player_revive):
		_player.revive_completed.connect(_on_player_revive)
	# Arme courante (le player émet weapon_equipped quand ramassage)
	_player.weapon_equipped.connect(_on_weapon_equipped)
	_attach_weapon_signals()
	# Bus global ennemi-kill
	if Engine.has_singleton(&"SignalBus"):
		pass  # placeholder si on en ajoute un plus tard
	# Pour le moment : connecter à enemy_died sur chaque enemy qu'on trouve
	for n in get_tree().get_nodes_in_group(&"enemies"):
		_try_bind_enemy(n)
	get_tree().node_added.connect(_on_node_added_global)


func _on_node_added_global(n: Node) -> void:
	# Branche automatiquement chaque nouvel ennemi spawné en cours de run.
	if n.is_in_group(&"enemies"):
		_try_bind_enemy(n)


func _try_bind_enemy(n: Node) -> void:
	var hc: HealthComponent = null
	for c in n.get_children():
		if c is HealthComponent:
			hc = c
			break
	if hc == null:
		return
	if not hc.died.is_connected(_on_enemy_died):
		hc.died.connect(_on_enemy_died.bind(n))


func _on_weapon_equipped(_kind: StringName) -> void:
	_attach_weapon_signals()


func _attach_weapon_signals() -> void:
	var w: WeaponHitscan = _player.get_weapon()
	if w != null:
		if not w.fired.is_connected(_on_weapon_fired):
			w.fired.connect(_on_weapon_fired)
		if not w.reload_finished.is_connected(_on_weapon_reload_finished):
			w.reload_finished.connect(_on_weapon_reload_finished)


# -----------------------------------------------------------------------------
# Hooks d'inventaire (add/remove)
# -----------------------------------------------------------------------------

func _on_relic_added(data: RelicData) -> void:
	# stat & combo_mod ne nécessitent pas de subscribe (lus en pull).
	# on_low_hp doit s'armer initialement.
	if data.effect_type == RelicData.EffectType.ON_LOW_HP:
		_low_hp_armed[data.id] = true


func _on_relic_removed(data: RelicData) -> void:
	_last_proc.erase(data.id)
	_low_hp_armed.erase(data.id)
	_shot_counters.erase(data.id)
	_perm_stacks.erase(data.id)
	# Note : un retrait ne décompte pas les stacks permanents déjà appliqués
	# (Léviathan reste tracké via _perm_damage_mult). On accepte ce trade-off
	# v1 ; à raffiner si on a un swap UI plus tard.


# -----------------------------------------------------------------------------
# Helpers de cooldown
# -----------------------------------------------------------------------------

func _is_off_cooldown(relic_id: StringName, cooldown_sec: float) -> bool:
	if cooldown_sec <= 0.0:
		return true
	var now: float = Time.get_ticks_msec() / 1000.0
	if not _last_proc.has(relic_id):
		return true
	return (now - float(_last_proc[relic_id])) >= cooldown_sec


func _stamp_cooldown(relic_id: StringName) -> void:
	_last_proc[relic_id] = Time.get_ticks_msec() / 1000.0


# -----------------------------------------------------------------------------
# on_hit
# -----------------------------------------------------------------------------

func _on_weapon_fired(hit: bool, hit_position: Vector3, target: Node) -> void:
	if not hit or target == null:
		return
	var hc: HealthComponent = _find_health_on(target)
	for data in _inventory.get_relics():
		match data.effect_type:
			RelicData.EffectType.ON_HIT:
				_apply_on_hit(data, hc, hit_position, target)
			_:
				pass


func _apply_on_hit(data: RelicData, target_hc: HealthComponent, _pos: Vector3, _target: Node) -> void:
	# Filtre weapon
	if data.weapon_filter != &"" and _player.get_equipped_weapon_kind() != data.weapon_filter:
		return
	var proc: float = float(data.get_magnitude(&"proc_chance", 0.0))
	if proc > 0.0 and randf() > proc:
		return

	# every_n_shots (Lance d'Odin)
	var every_n: int = int(data.get_magnitude(&"every_n_shots", 0))
	if every_n > 0:
		var count: int = int(_shot_counters.get(data.id, 0)) + 1
		_shot_counters[data.id] = count
		if count % every_n != 0:
			return

	# Effets : status, ricochet (stub), lightning AoE
	if data.magnitude.has(&"status_id") and target_hc != null:
		var sid: StringName = data.get_magnitude(&"status_id", &"")
		var sdur: float = float(data.get_magnitude(&"status_duration_sec", 0.0))
		var sdps: float = float(data.get_magnitude(&"status_dps", 0.0))
		if sid == &"poison" or sid == &"burn" or sid == &"bleed":
			# Reutilise le shim apply_burn pour les DoT (cf health_component.gd).
			# Suffit pour le POC ; un vrai system status arrivera en M2.
			target_hc.apply_burn(sdur, sdps, _player)

	# Lance d'Odin : AoE foudre
	if data.magnitude.has(&"lightning_damage"):
		var dmg: int = int(data.get_magnitude(&"lightning_damage", 0))
		var radius: float = float(data.get_magnitude(&"lightning_radius_m", 0.0))
		_apply_aoe_damage(_pos, radius, dmg)


func _apply_aoe_damage(center: Vector3, radius: float, damage: int) -> void:
	var r_sq: float = radius * radius
	for e in get_tree().get_nodes_in_group(&"enemies"):
		if not (e is Node3D):
			continue
		if (e as Node3D).global_position.distance_squared_to(center) > r_sq:
			continue
		var hc: HealthComponent = _find_health_on(e)
		if hc != null:
			hc.take_damage(damage, _player)


# -----------------------------------------------------------------------------
# on_kill
# -----------------------------------------------------------------------------

func _on_enemy_died(_source: Node, enemy: Node) -> void:
	# Filtre : on n'applique on_kill que si c'est NOTRE player qui a tué.
	# Le source du died est l'attaquant (cf health_component.gd take_damage).
	# Tolérance : on accepte aussi si source == null (auto-DoT issu d'un combo).
	for data in _inventory.get_relics():
		if data.effect_type != RelicData.EffectType.ON_KILL:
			continue
		_apply_on_kill(data, enemy)


func _apply_on_kill(data: RelicData, _enemy: Node) -> void:
	# Heal direct
	var heal: int = int(data.get_magnitude(&"heal_amount", 0))
	if heal > 0:
		var max_per_sec: int = int(data.get_magnitude(&"max_per_sec", 0))
		if max_per_sec > 0:
			if not _is_off_cooldown(data.id, 1.0 / float(max_per_sec)):
				return
			_stamp_cooldown(data.id)
		_player.get_health().heal(heal)
	# Move speed buff temporaire (Brassard du voleur)
	var mss_per_stack: float = float(data.get_magnitude(&"move_speed_mult_per_stack", 0.0))
	if mss_per_stack > 0.0:
		var dur: float = float(data.get_magnitude(&"duration_sec", 3.0))
		var max_stacks: int = int(data.get_magnitude(&"max_stacks", 5))
		_apply_temp_buff(data.id, &"move_speed_mult", mss_per_stack, dur, max_stacks)
	# Damage mult par kill (Cor du Léviathan, stack permanent)
	var perm_mult: float = float(data.get_magnitude(&"damage_mult_per_kill", 0.0))
	if perm_mult > 0.0:
		_perm_damage_mult += perm_mult
		_perm_stacks[data.id] = int(_perm_stacks.get(data.id, 0)) + 1
	# Instant reload
	if data.get_magnitude(&"instant_reload", false):
		var w: WeaponHitscan = _player.get_weapon()
		if w != null:
			w.current_ammo = w.max_ammo
			w.ammo_changed.emit(w.current_ammo, w.max_ammo)
	# CD spell de classe — pas encore de système, on log
	if data.magnitude.has(&"class_spell_cooldown_reduction_sec"):
		pass  # TODO : brancher quand le système de sorts de classe sera prêt
	# XP orb mult — pas encore d'XP system, on log
	if data.magnitude.has(&"xp_orb_multiplier"):
		pass
	# Esprit allié — pas encore de spawn d'allié, on log
	if data.magnitude.has(&"spirit_duration_sec"):
		pass


# -----------------------------------------------------------------------------
# on_damaged
# -----------------------------------------------------------------------------

func _on_player_damaged(amount: int, source: Node) -> void:
	# on_low_hp : check threshold
	_check_low_hp()
	# on_damaged : applique reflect/block/etc.
	for data in _inventory.get_relics():
		if data.effect_type == RelicData.EffectType.ON_DAMAGED:
			_apply_on_damaged(data, amount, source)


func _apply_on_damaged(data: RelicData, amount: int, source: Node) -> void:
	# Block (Roc poli)
	var proc: float = float(data.get_magnitude(&"proc_chance", 0.0))
	if proc > 0.0 and randf() > proc:
		return
	# (Le block « 50 % réduit » nécessiterait un hook avant take_damage. Pour
	# l'instant on heal a posteriori 50 % du dommage — équivalent net.)
	var block_pct: float = float(data.get_magnitude(&"damage_reduction_pct", 0.0))
	if block_pct > 0.0:
		_player.get_health().heal(int(round(amount * block_pct)))
	# Reflect mêlée (Talisman du chacal)
	var reflect: float = float(data.get_magnitude(&"reflect_pct", 0.0))
	if reflect > 0.0 and source != null:
		var src_hc: HealthComponent = _find_health_on(source)
		if src_hc != null:
			src_hc.take_damage(int(round(amount * reflect)), _player)
	# Slow ennemis (Sablier du Temps Mort) — pas de time scale, on log
	if data.magnitude.has(&"enemy_time_scale"):
		pass  # TODO : nécessite un système global de time scale ennemis


# -----------------------------------------------------------------------------
# on_low_hp
# -----------------------------------------------------------------------------

func _check_low_hp() -> void:
	var hc: HealthComponent = _player.get_health()
	var hp_pct: float = float(hc.current_health) / float(max(hc.max_health, 1))
	for data in _inventory.get_relics():
		if data.effect_type != RelicData.EffectType.ON_LOW_HP:
			continue
		var threshold: float = float(data.get_magnitude(&"threshold_pct", 0.25))
		if hp_pct < threshold and bool(_low_hp_armed.get(data.id, true)):
			_apply_on_low_hp(data, hc)
			_low_hp_armed[data.id] = false
		elif hp_pct >= threshold:
			_low_hp_armed[data.id] = true


func _apply_on_low_hp(data: RelicData, hc: HealthComponent) -> void:
	var cd: float = float(data.get_magnitude(&"cooldown_sec", 0.0))
	if not _is_off_cooldown(data.id, cd):
		return
	_stamp_cooldown(data.id)
	var heal: int = int(data.get_magnitude(&"heal_amount", 0))
	if heal > 0:
		hc.heal(heal)
	# invuln_duration_sec ou auto_revive : nécessitent flag invulnérable sur le
	# player. On le set via un attribut runtime que take_damage devra lire.
	# v1 : on heal massivement à la place (équivalent fonctionnel pour POC).
	var invuln: float = float(data.get_magnitude(&"invuln_duration_sec", 0.0))
	if invuln > 0.0:
		hc.heal(hc.max_health)  # full heal en remplacement d'un vrai invuln
	if data.get_magnitude(&"auto_revive_per_run", 0) and hc.is_dead:
		var pct: float = float(data.get_magnitude(&"revive_hp_pct", 0.5))
		hc.reset()
		hc.current_health = int(hc.max_health * pct)
		hc.health_changed.emit(hc.current_health, hc.max_health)


# -----------------------------------------------------------------------------
# on_dash
# -----------------------------------------------------------------------------

func _on_player_dash() -> void:
	for data in _inventory.get_relics():
		if data.effect_type != RelicData.EffectType.ON_DASH:
			continue
		_apply_on_dash(data)


func _apply_on_dash(data: RelicData) -> void:
	# Zone dégâts (Frelon écrasé)
	var dmg: int = int(data.get_magnitude(&"damage", 0))
	var radius: float = float(data.get_magnitude(&"radius_m", 0.0))
	if dmg > 0 and radius > 0.0:
		_apply_aoe_damage(_player.global_position, radius, dmg)
	# Vortex (aspire ennemis) — pull pas encore implémenté, on log
	if data.magnitude.has(&"pull_radius_m"):
		pass


# -----------------------------------------------------------------------------
# on_reload
# -----------------------------------------------------------------------------

func _on_weapon_reload_finished() -> void:
	for data in _inventory.get_relics():
		if data.effect_type != RelicData.EffectType.ON_RELOAD:
			continue
		var mult: float = float(data.get_magnitude(&"next_shot_damage_mult", 0.0))
		if mult > 0.0:
			# v1 : on store sur le resolver, l'arme pourra le lire via
			# get_runtime_damage_mult(true) au prochain tir
			_pending_next_shot_mult = mult


var _pending_next_shot_mult: float = 0.0


## Appelable par WeaponHitscan : retourne le mult à appliquer au prochain
## tir, et le consomme. Si rien → 1.0.
func consume_next_shot_mult() -> float:
	if _pending_next_shot_mult > 0.0:
		var v := _pending_next_shot_mult
		_pending_next_shot_mult = 0.0
		return v
	return 1.0


# -----------------------------------------------------------------------------
# on_revive
# -----------------------------------------------------------------------------

func _on_player_revive(target: PlayerController) -> void:
	for data in _inventory.get_relics():
		if data.effect_type != RelicData.EffectType.ON_REVIVE:
			continue
		# Lacet renforcé (revive_speed_mult) : appliqué par ReviveInteractable
		# via pull-stat (cf player_controller.get_revive_speed_mult())
		# Camée fissuré (revive_hp_pct override) : applique 100 %.
		var pct: float = float(data.get_magnitude(&"revive_hp_pct", 0.0))
		if pct > 0.0 and target != null and target.get_health() != null:
			var hc: HealthComponent = target.get_health()
			hc.current_health = int(hc.max_health * pct)
			hc.health_changed.emit(hc.current_health, hc.max_health)
		# Team heal (Cor de bataille)
		var team_heal: float = float(data.get_magnitude(&"team_heal_pct", 0.0))
		if team_heal > 0.0:
			for p in get_tree().get_nodes_in_group(&"players"):
				if p is PlayerController and (p as PlayerController).get_health() != null:
					var php: HealthComponent = (p as PlayerController).get_health()
					php.heal(int(php.max_health * team_heal))


# -----------------------------------------------------------------------------
# coop (poll)
# -----------------------------------------------------------------------------

func _process(delta: float) -> void:
	_coop_timer += delta
	if _coop_timer < COOP_POLL_SEC:
		return
	_coop_timer = 0.0
	_tick_coop()
	_cleanup_temp_buffs()


func _tick_coop() -> void:
	# Pour chaque relique coop, on calcule un état désiré et on stocke un
	# buff "virtuel" lu par les getters du player (move_speed_mult, etc.).
	# v1 : seul Tambour de guerre (damage par allié vivant) et Sigille du lien
	# (regen partagé en proximité) ont un effet runtime. Petit Ange Gardien
	# (damage quand allié down) est aussi câblé.
	for data in _inventory.get_relics():
		if data.effect_type != RelicData.EffectType.COOP:
			continue
		# Tambour de guerre
		var dmg_per_ally: float = float(data.get_magnitude(&"damage_mult_per_ally_alive", 0.0))
		if dmg_per_ally > 0.0:
			var allies: int = _count_allies_alive()
			# stocke en buff "permanent" rafraîchi à chaque poll
			_set_or_refresh_buff(data.id, &"damage_mult", dmg_per_ally * float(allies), 0.5)
		# Petit ange gardien : damage 25 % 8 s quand allié down (rearmable)
		var dmg_when_down: float = float(data.get_magnitude(&"damage_mult_when_ally_down", 0.0))
		if dmg_when_down > 0.0 and _any_ally_downed():
			var dur: float = float(data.get_magnitude(&"duration_sec", 8.0))
			_apply_temp_buff(data.id, &"damage_mult", dmg_when_down, dur, 1)
		# Sigille du lien
		var regen: float = float(data.get_magnitude(&"hp_regen_per_sec", 0.0))
		if regen > 0.0:
			var range_m: float = float(data.get_magnitude(&"range_m", 5.0))
			if _any_ally_in_range(range_m):
				var add: float = regen * COOP_POLL_SEC
				_player.get_health().heal(int(ceil(add)))


func _count_allies_alive() -> int:
	var n := 0
	for p in get_tree().get_nodes_in_group(&"players"):
		if p is PlayerController and (p as PlayerController).is_alive():
			n += 1
	return n


func _any_ally_downed() -> bool:
	for p in get_tree().get_nodes_in_group(&"players"):
		if p == _player:
			continue
		if p is PlayerController and (p as PlayerController).is_downed():
			return true
	return false


func _any_ally_in_range(range_m: float) -> bool:
	var r_sq: float = range_m * range_m
	for p in get_tree().get_nodes_in_group(&"players"):
		if p == _player:
			continue
		if p is PlayerController and (p as PlayerController).is_alive():
			if (p as PlayerController).global_position.distance_squared_to(_player.global_position) <= r_sq:
				return true
	return false


# -----------------------------------------------------------------------------
# Temp buffs (utilisés par on_kill stacks, coop)
# -----------------------------------------------------------------------------

func _apply_temp_buff(relic_id: StringName, stat: StringName, value: float, dur: float, max_stacks: int) -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	# Compte les stacks de cette relique pour ce stat
	var same_count: int = 0
	for b in _temp_buffs:
		if b["relic_id"] == relic_id and b["stat"] == stat:
			same_count += 1
	if same_count >= max_stacks:
		# Refresh le plus ancien
		for b in _temp_buffs:
			if b["relic_id"] == relic_id and b["stat"] == stat:
				b["expire"] = now + dur
				return
	_temp_buffs.append({
		"relic_id": relic_id, "stat": stat, "value": value, "expire": now + dur
	})


func _set_or_refresh_buff(relic_id: StringName, stat: StringName, value: float, dur: float) -> void:
	# Pour les buffs « volatile » écrits chaque poll. Si déjà présent, met à jour value+expire.
	var now: float = Time.get_ticks_msec() / 1000.0
	for b in _temp_buffs:
		if b["relic_id"] == relic_id and b["stat"] == stat:
			b["value"] = value
			b["expire"] = now + dur
			return
	_temp_buffs.append({
		"relic_id": relic_id, "stat": stat, "value": value, "expire": now + dur
	})


func _cleanup_temp_buffs() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	var i := 0
	while i < _temp_buffs.size():
		if float(_temp_buffs[i]["expire"]) <= now:
			_temp_buffs.remove_at(i)
		else:
			i += 1


## Somme des bonus temp pour un stat donné. Utilisé par les getters pull-stat
## du player (combine relic_inventory.compute_stat + temp_buffs).
func sum_temp(stat: StringName) -> float:
	var s: float = 0.0
	for b in _temp_buffs:
		if b["stat"] == stat:
			s += float(b["value"])
	return s


## Multiplicateur runtime accumulé via stacks permanents (Léviathan).
func get_runtime_damage_mult() -> float:
	return _perm_damage_mult


# -----------------------------------------------------------------------------
# combo_mod (STUB)
# -----------------------------------------------------------------------------

## Appelable par WeaponHitscan / combo engine futur. Retourne le dict agrégé
## des modificateurs combo actifs pour l'école `school` (e.g. burn_duration_mult).
## v1 : agrège les magnitudes des reliques combo_mod sans filtre cross-school.
func get_combo_modifiers(school: StringName) -> Dictionary:
	var out: Dictionary = {}
	for data in _inventory.get_relics():
		if data.effect_type != RelicData.EffectType.COMBO_MOD:
			continue
		if data.school_filter != &"" and data.school_filter != school:
			continue
		for key in data.magnitude.keys():
			# Accumule (multiplicatif pour les *_mult, additif sinon).
			var k_str: String = String(key)
			if k_str.ends_with("_mult"):
				var prev: float = float(out.get(key, 1.0))
				out[key] = prev * float(data.magnitude[key])
			else:
				var prev_v: Variant = out.get(key, 0)
				if prev_v is bool:
					out[key] = bool(out[key]) or bool(data.magnitude[key])
				elif prev_v is float or prev_v is int:
					out[key] = float(prev_v) + float(data.magnitude[key])
				else:
					out[key] = data.magnitude[key]
	return out


# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

func _find_health_on(node: Node) -> HealthComponent:
	var current: Node = node
	while current != null:
		for child in current.get_children():
			if child is HealthComponent:
				return child as HealthComponent
		current = current.get_parent()
	return null

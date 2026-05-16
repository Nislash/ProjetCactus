class_name BossBase
extends EnemyBase

## Boss générique. Étend EnemyBase avec :
## - 3 phases (P1 100→66%, P2 66→33%, P3 enrage 33→0% — seuils dans BossData)
## - Résistance status (configuré sur StatusComponent au _ready depuis BossData)
## - Weak point combo recipe (ex: freeze → thunder → stun 5s + 15% HP)
## - Damage tracking par joueur (pour l'écran post-combat)
## - Signaux pour HUD global + lock arène + écran post-combat
##
## L'IA (sélection d'attaque, cooldowns, déplacement contextuel) sera prise
## en charge par rust/src/boss_ai.rs (#62). Ici on expose juste la machine
## à états + les hooks que l'IA appellera.

signal phase_changed(new_phase: int)
signal combo_triggered(stun_duration: float, hp_lost: int)
signal boss_engaged()  ## émis quand le lock arène déclenche le combat
signal boss_defeated(damage_by_player: Dictionary, fight_duration_sec: float)

enum Phase { IDLE, PHASE_1, TRANSITION_1_TO_2, PHASE_2, TRANSITION_2_TO_3, PHASE_3_ENRAGE, STUNNED_COMBO, DEAD }

@export var boss_data: BossData

var _current_phase: int = Phase.IDLE
var _engaged: bool = false
var _engage_time_sec: float = 0.0
## player_id (int) -> dégâts cumulés (int). Source peut être un PlayerController
## ou un projectile owned par ce player.
var _damage_by_player: Dictionary = {}

## Track séquence weak point combo. Liste d'IDs dans l'ordre d'application,
## avec timestamps pour vider la fenêtre.
var _combo_sequence: Array = []
## Timestamps parallèles à _combo_sequence (en s, Time.get_ticks_msec/1000).
var _combo_timestamps: Array = []
var _combo_cooldown_end: float = 0.0


func _ready() -> void:
	super._ready()
	add_to_group(&"bosses")

	if boss_data == null:
		push_warning("BossBase sans boss_data — fallback valeurs par défaut")
		return

	# Configure HP depuis la data.
	_health.max_health = boss_data.max_health
	_health.current_health = boss_data.max_health
	# Vitesse.
	move_speed = boss_data.move_speed_base

	# Configure le StatusComponent pour la résistance.
	var status: StatusComponent = _health.get_status()
	if status != null:
		status.hit_threshold = boss_data.status_hit_threshold
		status.threshold_window = boss_data.status_threshold_window
		status.duration_multiplier = boss_data.status_duration_multiplier
		# Écoute les tentatives d'application pour la recette combo.
		status.status_application_attempt.connect(_on_status_application_attempt)

	# Track des dégâts par joueur (via signal damaged déjà émis par EnemyBase).
	damaged.connect(_on_damaged_for_tracking)


## Démarre le combat : passe Idle -> Phase 1. Appelé par le LockArena trigger
## quand tous les joueurs sont entrés.
func engage() -> void:
	if _engaged or _current_phase == Phase.DEAD:
		return
	_engaged = true
	_engage_time_sec = Time.get_ticks_msec() / 1000.0
	_set_phase(Phase.PHASE_1)
	boss_engaged.emit()


func get_current_phase() -> int:
	return _current_phase


func is_engaged() -> bool:
	return _engaged


## Renvoie la copie du tracking damage par player (lecture seule).
func get_damage_by_player() -> Dictionary:
	return _damage_by_player.duplicate()


func get_fight_duration_sec() -> float:
	if not _engaged:
		return 0.0
	return Time.get_ticks_msec() / 1000.0 - _engage_time_sec


func _set_phase(new_phase: int) -> void:
	if new_phase == _current_phase:
		return
	_current_phase = new_phase
	# Entrée en enrage : immunité stun + freeze (selon BossData).
	if new_phase == Phase.PHASE_3_ENRAGE and boss_data != null:
		var status: StatusComponent = _health.get_status()
		if status != null:
			for sid in boss_data.enrage_immune_status:
				status.set_immune(sid, true)
		# Vitesse enrage.
		move_speed = boss_data.move_speed_enrage
	phase_changed.emit(new_phase)


## Surcharge de _enemy_tick pour piloter les transitions HP. L'IA Rust (#62)
## sera plug-in plus tard via une méthode `set_ai_controller` ou en
## remplaçant ce tick directement.
func _enemy_tick(_delta: float) -> void:
	if not _engaged or boss_data == null or _health.is_dead:
		return
	var hp_ratio: float = float(_health.current_health) / float(_health.max_health)
	# Triggers de phase par HP %.
	match _current_phase:
		Phase.PHASE_1:
			if hp_ratio <= boss_data.phase_2_trigger:
				_set_phase(Phase.PHASE_2)
		Phase.PHASE_2:
			if hp_ratio <= boss_data.phase_3_trigger:
				_set_phase(Phase.PHASE_3_ENRAGE)
		_:
			pass
	# Pour le POC, pas d'IA d'attaque ici (sera #62 en Rust). Placeholder
	# `_attack_tick` à override par les sous-classes si besoin temporaire.
	_attack_tick(_delta)


## Hook pour sous-classes / placeholders d'IA. L'IA Rust finale remplacera ça.
func _attack_tick(_delta: float) -> void:
	pass


func _on_damaged_for_tracking(amount: int, source: Node) -> void:
	if source == null:
		return
	# Le source peut être un PlayerController direct, un projectile (qui
	# tient un owner_body), ou autre. On résout en remontant.
	var player_id: int = _resolve_player_id(source)
	if player_id < 0:
		return
	_damage_by_player[player_id] = int(_damage_by_player.get(player_id, 0)) + amount


func _resolve_player_id(source: Node) -> int:
	if source == null:
		return -1
	if source is PlayerController:
		return (source as PlayerController).player_id
	# Projectile ou helper avec champ `owner_body` (cf fireball.gd).
	if "owner_body" in source and source.owner_body is PlayerController:
		return (source.owner_body as PlayerController).player_id
	# Cherche en remontant le parent.
	var parent: Node = source.get_parent()
	if parent != null:
		return _resolve_player_id(parent)
	return -1


## Écoute les tentatives d'application status pour la recette combo. Les
## tentatives sont notifiées même si le threshold du status n'est pas
## encore atteint — c'est volontaire : le combo recipe vit en parallèle.
func _on_status_application_attempt(id: StringName, _source: Node) -> void:
	if boss_data == null or boss_data.weak_point_recipe.is_empty():
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	if now < _combo_cooldown_end:
		return
	# Drop les ingrédients hors fenêtre.
	while not _combo_timestamps.is_empty() and now - _combo_timestamps[0] > boss_data.weak_point_window:
		_combo_timestamps.pop_front()
		_combo_sequence.pop_front()
	# L'ingrédient attendu à l'index actuel de la séquence ?
	var expected_index: int = _combo_sequence.size()
	if expected_index >= boss_data.weak_point_recipe.size():
		return  # ne devrait pas arriver
	var expected: StringName = boss_data.weak_point_recipe[expected_index]
	if id != expected:
		# Mauvais ingrédient = on reset la séquence (sauf si c'est le 1er).
		_combo_sequence.clear()
		_combo_timestamps.clear()
		if id == boss_data.weak_point_recipe[0]:
			_combo_sequence.append(id)
			_combo_timestamps.append(now)
		return
	_combo_sequence.append(id)
	_combo_timestamps.append(now)
	# Séquence complète ?
	if _combo_sequence.size() >= boss_data.weak_point_recipe.size():
		_trigger_combo()


func _trigger_combo() -> void:
	if boss_data == null:
		return
	var now: float = Time.get_ticks_msec() / 1000.0
	_combo_cooldown_end = now + boss_data.combo_cooldown
	_combo_sequence.clear()
	_combo_timestamps.clear()
	# Dégâts instantanés (pourcentage HP max).
	var hp_lost: int = int(boss_data.max_health * boss_data.combo_hp_loss_percent)
	_health.take_damage(hp_lost, self)
	# Stun via StatusComponent (force-apply qui contourne le threshold via
	# `_active` direct ? Non — on passe par apply_status avec une fenêtre
	# temporairement neutre). Simpler : on bypass et on set le state.
	_set_phase(Phase.STUNNED_COMBO)
	combo_triggered.emit(boss_data.combo_stun_duration, hp_lost)
	# Reprend la phase après le stun (timer simple).
	get_tree().create_timer(boss_data.combo_stun_duration).timeout.connect(_on_combo_stun_end)


func _on_combo_stun_end() -> void:
	if _current_phase != Phase.STUNNED_COMBO or _health.is_dead:
		return
	# Reprend la phase correspondant au HP actuel.
	var hp_ratio: float = float(_health.current_health) / float(_health.max_health)
	if hp_ratio <= boss_data.phase_3_trigger:
		_set_phase(Phase.PHASE_3_ENRAGE)
	elif hp_ratio <= boss_data.phase_2_trigger:
		_set_phase(Phase.PHASE_2)
	else:
		_set_phase(Phase.PHASE_1)


## Override la mort : pas de queue_free immédiat — on émet d'abord les
## stats pour l'écran post-combat, et la scène fille gère le slow-mo / VFX.
func _on_died(source: Node) -> void:
	killed.emit(source)
	_set_phase(Phase.DEAD)
	var duration: float = get_fight_duration_sec()
	boss_defeated.emit(_damage_by_player.duplicate(), duration)
	# Pas de queue_free ici — la scène boss orchestre slow-mo + anim death
	# + drop avant de free.


## Stun-immunity check : pendant l'enrage, freeze et stun n'ont pas d'effet
## sur le mouvement. has_status renverra false donc EnemyBase.get_speed_multiplier
## ne ralentit pas. Mais on garde la logique de can_act() inchangée.
func can_act() -> bool:
	if _current_phase == Phase.STUNNED_COMBO:
		return false
	return super.can_act()

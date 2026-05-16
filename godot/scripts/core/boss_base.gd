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
signal boss_defeated(damage_by_player: Dictionary, fight_duration_sec: float, dropped_relic: RelicData)

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


# =============================================================================
# API appelée par BossAI Rust (cf rust/src/boss_ai/). Toutes les méthodes
# préfixées `ai_` sont des hooks que la lib Rust appelle via Node.call().
# =============================================================================

## Vitesse de déplacement courante demandée par l'IA. is_enrage = phase 3.
func get_ai_move_speed(is_enrage: bool) -> float:
	if boss_data == null:
		return 2.0
	return boss_data.move_speed_enrage if is_enrage else boss_data.move_speed_base


## Démarrage de telegraph d'attaque (l'IA Rust passe en AttackWindup). Spawne
## un decal AoE clignotant au sol pendant `duration` secondes.
func ai_on_attack_windup(attack_name: String, target_pos: Vector3, duration: float, radius: float) -> void:
	_spawn_aoe_telegraph(target_pos, radius, duration)
	# Hook pour les sous-classes (ex: BossGolem joue une anim d'amorce).
	if has_method("_on_attack_windup"):
		call("_on_attack_windup", attack_name, target_pos, duration, radius)


## Exécution effective d'une attaque. Applique l'effet (AoE damage pour
## slam/shockwave, projectiles pour throw_rocks/shards/beam, etc.).
func ai_on_attack_execute(attack_name: String, boss_pos: Vector3, target_pos: Vector3, radius: float, damage: float) -> void:
	match attack_name:
		"slam", "shockwave":
			# AoE centré sur target_pos (slam) ou sur le boss (shockwave).
			var center: Vector3 = target_pos if attack_name == "slam" else boss_pos
			_apply_aoe_damage(center, radius, int(damage))
		_:
			# Les autres attaques (throw_rocks, charge, shard_rain, crystal_beam)
			# seront implémentées en Phase 3. Stub pour l'instant.
			pass
	if has_method("_on_attack_execute"):
		call("_on_attack_execute", attack_name, boss_pos, target_pos, radius, damage)


## Spawne un decal au sol cylindrique rouge semi-transparent qui clignote
## pendant `duration` puis s'auto-free. Y posé à 0.05 au-dessus du sol pour
## éviter le z-fighting. Utilisé par les attaques zone (slam, shockwave).
func _spawn_aoe_telegraph(center: Vector3, radius: float, duration: float) -> void:
	var marker: MeshInstance3D = MeshInstance3D.new()
	var cyl: CylinderMesh = CylinderMesh.new()
	cyl.top_radius = radius
	cyl.bottom_radius = radius
	cyl.height = 0.05
	marker.mesh = cyl
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.25, 0.2, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.2, 0.15)
	mat.emission_energy_multiplier = 1.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = mat
	# Anchored sur le boss parent (= dans le World), à hauteur sol.
	get_parent().add_child(marker)
	marker.global_position = Vector3(center.x, center.y + 0.05, center.z)
	# Tween pulse alpha pour signaler le windup.
	var tween: Tween = marker.create_tween()
	tween.set_loops()
	tween.tween_property(marker, "material_override:albedo_color:a", 0.75, 0.2)
	tween.tween_property(marker, "material_override:albedo_color:a", 0.25, 0.2)
	# Free à la fin du windup.
	get_tree().create_timer(duration).timeout.connect(marker.queue_free)


## Inflige des dégâts à tous les PlayerControllers dans le rayon autour
## du centre (XZ uniquement, ignore Y).
func _apply_aoe_damage(center: Vector3, radius: float, damage: int) -> void:
	for n in get_tree().get_nodes_in_group(&"players"):
		if not (n is PlayerController):
			continue
		var p: PlayerController = n
		var dxz: Vector3 = p.global_position - center
		dxz.y = 0
		if dxz.length() <= radius:
			var hc: HealthComponent = p.get_health()
			if hc != null and not hc.is_dead:
				hc.take_damage(damage, self)


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


const _RELIC_DROP_SCENE: PackedScene = preload("res://scenes/pickups/boss_relic_drop.tscn")

## Override la mort : slow-mo + drop relique + signal post-combat. Pas de
## queue_free immédiat — un timer libère le mesh après l'anim de mort.
func _on_died(source: Node) -> void:
	killed.emit(source)
	_set_phase(Phase.DEAD)
	var duration: float = get_fight_duration_sec()
	var relic: RelicData = null
	if boss_data != null and boss_data.drops_legendary_relic:
		# Pool legendary uniquement (drop_pool boss_only = tier 3 dans le POC).
		relic = RelicLootTable.draw_with({RelicData.Tier.LEGENDARY: 1.0})
		if relic != null:
			_spawn_relic_drop(relic)
	boss_defeated.emit(_damage_by_player.duplicate(), duration, relic)
	# Slow-mo court (0.3x pendant 1s real-time = ~0.3s game-time).
	Engine.time_scale = 0.3
	get_tree().create_timer(1.0, true, false, true).timeout.connect(_end_slowmo)
	# Free le boss après une anim placeholder (2s).
	get_tree().create_timer(2.0).timeout.connect(queue_free)


func _end_slowmo() -> void:
	Engine.time_scale = 1.0


func _spawn_relic_drop(relic: RelicData) -> void:
	var drop: Node = _RELIC_DROP_SCENE.instantiate()
	if drop.has_method("set_relic"):
		drop.set_relic(relic)
	get_parent().add_child(drop)
	if drop is Node3D:
		(drop as Node3D).global_position = global_position


## Stun-immunity check : pendant l'enrage, freeze et stun n'ont pas d'effet
## sur le mouvement. has_status renverra false donc EnemyBase.get_speed_multiplier
## ne ralentit pas. Mais on garde la logique de can_act() inchangée.
func can_act() -> bool:
	if _current_phase == Phase.STUNNED_COMBO:
		return false
	return super.can_act()

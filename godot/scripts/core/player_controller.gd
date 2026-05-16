class_name PlayerController
extends CharacterBody3D

## Contrôleur FPS d'un joueur. Toutes les inputs passent par InputRouter.
##
## Le `player_id` doit être set par celui qui instancie la scène (SplitScreenManager
## ou code de spawn). Tant que `player_id` n'a pas de device assigné dans
## InputRouter, le contrôleur reste inerte (pas d'erreur, juste pas de move).

@export var player_id: int = 0

@export_group("Mouvement")
@export var move_speed: float = 7.0
@export var acceleration: float = 50.0
@export var friction: float = 60.0
@export var jump_velocity: float = 7.0
@export var gravity: float = 20.0

@export_group("Caméra / Look")
@export var look_sensitivity: float = 3.0
@export var pitch_min_deg: float = -85.0
@export var pitch_max_deg: float = 85.0

@export_group("Dash")
@export var dash_speed: float = 18.0
@export var dash_duration: float = 0.15
@export var dash_cooldown: float = 0.8

@export_group("Garde-fou")
## Altitude (Y) en dessous de laquelle on considère que le joueur est tombé
## dans le vide → respawn auto au spawn point (compte comme une mort).
@export var fall_threshold_y: float = -10.0

@export_group("Down & Revive")
## Multiplicateur de vitesse en état DOWNED (rampe lentement, ~ramper).
@export var downed_speed_multiplier: float = 0.3
## HP rendu au revive (en % du max_health). Distance + durée portées par le
## node ReviveInteractable enfant du player (cf player.tscn).
@export_range(0.1, 1.0) var revive_hp_ratio: float = 0.5

@export_group("Interaction")
## Distance maxi pour scanner les Interactables. Limite haute — chaque
## Interactable porte sa propre `interaction_range` plus stricte.
@export var interaction_scan_range: float = 5.0

@onready var _camera_pivot: Node3D = $CameraPivot
@onready var _camera: Camera3D = $CameraPivot/Camera3D
@onready var _camera_remote: RemoteTransform3D = $CameraPivot/CameraRemote
@onready var _weapon_hitscan: WeaponHitscan = $CameraPivot/Weapon
@onready var _weapon_melee: WeaponMelee = $CameraPivot/Melee if has_node("CameraPivot/Melee") else null
@onready var _health: HealthComponent = $Health
@onready var relic_inventory: RelicInventory = $RelicInventory if has_node("RelicInventory") else null
@onready var relic_effects: RelicEffectResolver = $RelicEffectResolver if has_node("RelicEffectResolver") else null

signal died(source: Node)
signal downed()
signal revived()
signal respawned()
signal death_count_changed(count: int)
signal interaction_progress_changed(prompt: String, progress: float)
signal weapon_equipped(weapon_kind: StringName)
## Émis quand le joueur appuie D-pad up pour cycler l'état de SA minimap.
## Le HUD écoute et bascule MINI → FULL → HIDDEN → MINI.
signal minimap_toggle_requested()
## Émis quand le joueur appuie Y (toggle_inventory). Le HUD ouvre/ferme la
## fiche d'inventaire de reliques dans SON SubViewport (les autres joueurs
## ne sont pas impactés).
signal inventory_toggle_requested()
## Émis quand un dash démarre (consommé par RelicEffectResolver pour on_dash).
signal dash_started()
## Émis quand le joueur termine un revive sur un allié (consommé pour on_revive).
signal revive_completed(target: PlayerController)

enum PlayerState { ALIVE, DOWNED }

var state: PlayerState = PlayerState.ALIVE
var death_count: int = 0
var _spawn_position: Vector3 = Vector3.ZERO
var _yaw: float = 0.0
var _pitch: float = 0.0
var _dash_time_left: float = 0.0
var _dash_cooldown_left: float = 0.0
var _dash_direction: Vector3 = Vector3.ZERO
var _interact_target: Interactable = null
var _interact_progress: float = 0.0
## Type d'arme actuellement equipee : "" (rien), "pistol", "melee".
## Set par equip_weapon_kind() (appele par WeaponPickup).
var _equipped_weapon: StringName = &""


func _ready() -> void:
	_health.died.connect(_on_died)
	# Permet aux ennemis (et autres systèmes) de retrouver les joueurs via
	# get_tree().get_nodes_in_group("players").
	add_to_group("players")
	# Au start, aucune arme equipee — le joueur doit ramasser un WeaponPickup.
	_set_weapon_visible(_weapon_hitscan, false)
	_set_weapon_visible(_weapon_melee, false)
	# Branche les hooks d'effets de reliques (après que les autoloads et
	# le HealthComponent sont prêts).
	if relic_effects != null:
		relic_effects.attach_signals()
	# Synchronise max_hp du HealthComponent quand une relique stat avec max_hp
	# est ajoutée ou retirée. Sans ça, get_max_hp() retournerait une valeur
	# correcte mais le HUD/health pool ne s'adapterait pas.
	if relic_inventory != null:
		relic_inventory.relic_added.connect(_on_relic_added_apply_passive)
		relic_inventory.relic_removed.connect(_on_relic_removed_apply_passive)


## Equipe une arme par son kind ("pistol" ou "melee"). Cache l'autre arme.
## Appele par WeaponPickup.try_interact() quand le joueur ramasse une arme.
func equip_weapon_kind(kind: StringName) -> void:
	_equipped_weapon = kind
	_set_weapon_visible(_weapon_hitscan, kind == &"pistol")
	_set_weapon_visible(_weapon_melee, kind == &"melee")
	weapon_equipped.emit(kind)


func _set_weapon_visible(node: Node, on: bool) -> void:
	if node == null:
		return
	if node is Node3D:
		(node as Node3D).visible = on
	node.set_process(on)
	node.set_physics_process(on)


## Doit être appelé par celui qui spawn le player (SplitScreenManager) après
## avoir set la position. Stocke la position pour les respawns futurs.
func set_spawn_position(pos: Vector3) -> void:
	_spawn_position = pos
	global_transform.origin = pos


func get_health() -> HealthComponent:
	return _health


## Retourne l'arme hitscan (Pistolet) — utilise par SpellPickup pour
## equiper une gemme via equip_spell(). Reste valable meme quand l'arme
## n'est pas l'arme equipee (la gemme attendra que le pistolet soit
## equipe pour avoir un effet).
func get_weapon() -> WeaponHitscan:
	return _weapon_hitscan


## Retourne l'arme melee (Epee). Sera utilisee par les SpellPickup pour
## equiper une gemme sur la lame quand les combos melee×gemme arriveront.
func get_melee() -> WeaponMelee:
	return _weapon_melee


## Type d'arme actuellement equipee (StringName : "" / "pistol" / "melee").
func get_equipped_weapon_kind() -> StringName:
	return _equipped_weapon


## Lu par CharacterAnimator (auto_read_combat_state) pour basculer sur les
## clips shoot_*. True si on tient RT avec un pistolet équipé.
func is_shooting() -> bool:
	if state != PlayerState.ALIVE:
		return false
	if _equipped_weapon != &"pistol":
		return false
	return InputRouter.is_action_pressed(player_id, &"shoot")


## À 0 HP : on passe en état DOWNED (cf CLAUDE.md "Friendly fire & revive").
## Le joueur peut ramper mais pas tirer ; un allié peut le relever en
## maintenant `interact` à proximité.
##
## En SOLO : pas d'allié → Game Over immédiat.
## En MULTI : DOWNED. Si TOUS les joueurs sont DOWNED simultanément →
## Game Over (plus personne pour revive).
func _on_died(source: Node) -> void:
	if state == PlayerState.DOWNED:
		return
	state = PlayerState.DOWNED
	velocity = Vector3.ZERO
	_dash_time_left = 0.0
	died.emit(source)
	downed.emit()
	_check_game_over()


## Vérifie si plus aucun joueur n'est en mesure de relever les autres
## (i.e. tous sont DOWNED). Si oui, déclenche le Game Over.
func _check_game_over() -> void:
	var any_alive: bool = false
	for n in get_tree().get_nodes_in_group(&"players"):
		if not (n is PlayerController):
			continue
		var p: PlayerController = n
		if p.state == PlayerState.ALIVE and not p._health.is_dead:
			any_alive = true
			break
	if not any_alive:
		_trigger_game_over()


func _trigger_game_over() -> void:
	var screen: GameOverScreen = get_tree().root.find_child("GameOverScreen", true, false) as GameOverScreen
	if screen != null:
		screen.show_game_over()


## Téléporte le joueur au spawn point d'origine et réinitialise tout.
## Utilisé pour la chute (kill plane) où on ne veut PAS passer par downed.
func _respawn() -> void:
	state = PlayerState.ALIVE
	velocity = Vector3.ZERO
	global_transform.origin = _spawn_position
	_yaw = 0.0
	_pitch = 0.0
	rotation.y = 0.0
	_camera_pivot.rotation.x = 0.0
	_health.reset()
	death_count += 1
	death_count_changed.emit(death_count)
	respawned.emit()


## Relève le joueur (appelé par un allié). HP rendu = revive_hp_ratio * max.
func revive_by(reviver: PlayerController) -> void:
	if state != PlayerState.DOWNED:
		return
	state = PlayerState.ALIVE
	_health.reset()
	_health.current_health = int(_health.max_health * revive_hp_ratio)
	_health.health_changed.emit(_health.current_health, _health.max_health)
	revived.emit()
	# Notifie le reviver pour les effets on_revive (Camée fissuré, Cor de
	# bataille, Lacet renforcé — ce dernier modifie en réalité la vitesse
	# via pull-stat sur ReviveInteractable, pas via ce signal).
	if reviver != null and reviver != self:
		reviver.revive_completed.emit(self)


func is_alive() -> bool:
	return state == PlayerState.ALIVE and not _health.is_dead


func is_downed() -> bool:
	return state == PlayerState.DOWNED


func _on_relic_added_apply_passive(data: RelicData) -> void:
	# Stat max_hp : ajuste le pool de vie (ADD direct sur max_health).
	if data.effect_type == RelicData.EffectType.STAT and data.magnitude.has(&"max_hp"):
		var bonus: int = int(data.get_magnitude(&"max_hp", 0))
		_health.max_health += bonus
		_health.current_health += bonus
		_health.health_changed.emit(_health.current_health, _health.max_health)
	# Stat max_hp_mult : applique en %.
	if data.effect_type == RelicData.EffectType.STAT and data.magnitude.has(&"max_hp_mult"):
		var pct: float = float(data.get_magnitude(&"max_hp_mult", 0.0))
		var delta_hp: int = int(round(_health.max_health * pct))
		_health.max_health += delta_hp
		_health.current_health = clamp(_health.current_health + delta_hp, 1, _health.max_health)
		_health.health_changed.emit(_health.current_health, _health.max_health)


func _on_relic_removed_apply_passive(data: RelicData) -> void:
	if data.effect_type == RelicData.EffectType.STAT and data.magnitude.has(&"max_hp"):
		var bonus: int = int(data.get_magnitude(&"max_hp", 0))
		_health.max_health = max(1, _health.max_health - bonus)
		_health.current_health = clamp(_health.current_health, 1, _health.max_health)
		_health.health_changed.emit(_health.current_health, _health.max_health)
	if data.effect_type == RelicData.EffectType.STAT and data.magnitude.has(&"max_hp_mult"):
		var pct: float = float(data.get_magnitude(&"max_hp_mult", 0.0))
		var delta_hp: int = int(round(_health.max_health * pct / (1.0 + pct)))
		_health.max_health = max(1, _health.max_health - delta_hp)
		_health.current_health = clamp(_health.current_health, 1, _health.max_health)
		_health.health_changed.emit(_health.current_health, _health.max_health)


func _physics_process(delta: float) -> void:
	if not InputRouter.is_player_registered(player_id):
		return

	# Kill plane : chute dans le vide = respawn direct (skip downed).
	if global_transform.origin.y < fall_threshold_y:
		_respawn()
		return

	_update_look(delta)
	_physics_process_regen(delta)

	# Toggle minimap (cycle MINI/FULL/HIDDEN). Disponible meme quand DOWNED.
	if InputRouter.is_action_just_pressed(player_id, &"toggle_map"):
		minimap_toggle_requested.emit()
	# Toggle écran inventaire reliques (Y). Disponible meme quand DOWNED.
	if InputRouter.is_action_just_pressed(player_id, &"toggle_inventory"):
		inventory_toggle_requested.emit()

	if state == PlayerState.DOWNED:
		_update_downed_movement(delta)
	else:
		_update_dash_timers(delta)
		_update_shooting()
		_update_interact(delta)
		_apply_movement(delta)

	move_and_slide()


func _update_shooting() -> void:
	# RT pilote l'arme equipee. Pistolet = auto-fire (hold). Epee = un swing
	# par appui (just_pressed pour eviter le spam).
	match _equipped_weapon:
		&"pistol":
			if InputRouter.is_action_pressed(player_id, &"shoot") and _weapon_hitscan.can_fire():
				_weapon_hitscan.shoot()
		&"melee":
			if _weapon_melee != null and InputRouter.is_action_just_pressed(player_id, &"shoot") and _weapon_melee.can_fire():
				_weapon_melee.swing()


## Boucle d'interaction tenue avec le bouton `interact`. Délègue entièrement
## au scan du groupe `"interactables"` — un pickup gemme, un levier, un
## coffre, un shop, ou le revive d'un allié downed (via ReviveInteractable
## enfant des players DOWNED, cf scenes/characters/player/player.tscn).
func _update_interact(delta: float) -> void:
	var holding: bool = InputRouter.is_action_pressed(player_id, &"interact")
	var candidate: Interactable = _find_interactable_in_range() if holding else null

	if candidate != null:
		if candidate != _interact_target:
			_interact_target = candidate
			_interact_progress = 0.0
			candidate.interaction_started.emit(self)
		_interact_progress += delta
		var ratio: float = _interact_progress / max(_interact_target.hold_duration, 0.001)
		interaction_progress_changed.emit(_interact_target.prompt_text, ratio)
		if _interact_progress >= _interact_target.hold_duration:
			var target: Interactable = _interact_target
			_interact_target = null
			_interact_progress = 0.0
			interaction_progress_changed.emit("", 0.0)
			target.try_interact(self)
		return

	# Pas d'interactable courant : reset state + cancel signal.
	if _interact_target != null:
		_interact_target.interaction_cancelled.emit()
		interaction_progress_changed.emit("", 0.0)
		_interact_target = null
		_interact_progress = 0.0


## Trouve le meilleur Interactable du groupe "interactables" à portée : on
## filtre par interaction_range propre à chaque objet, puis on choisit la
## priorité la plus haute (selection_priority), et en cas d'égalité le plus
## proche. can_interact() permet aux sous-classes de se cacher (gemme déjà
## ramassée, allié non-downed pour un futur ReviveInteractable, etc.).
func _find_interactable_in_range() -> Interactable:
	var scan_range_sq: float = interaction_scan_range * interaction_scan_range
	var best: Interactable = null
	var best_priority: int = -2147483648
	var best_dist: float = INF
	for node in get_tree().get_nodes_in_group("interactables"):
		if not (node is Interactable):
			continue
		var inter: Interactable = node
		if not inter.can_interact(self):
			continue
		var d: float = (inter.global_position - global_position).length_squared()
		if d > scan_range_sq:
			continue
		var inter_range_sq: float = inter.interaction_range * inter.interaction_range
		if d > inter_range_sq:
			continue
		if inter.selection_priority > best_priority or (inter.selection_priority == best_priority and d < best_dist):
			best_priority = inter.selection_priority
			best_dist = d
			best = inter
	return best



## Mouvement en état DOWNED : le joueur peut ramper lentement mais ne peut ni
## tirer ni dash ni sauter. La gravité s'applique normalement.
func _update_downed_movement(delta: float) -> void:
	if not is_on_floor():
		velocity.y -= gravity * delta
	var input_2d: Vector2 = InputRouter.get_move_vector(player_id)
	var direction: Vector3 = (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()
	var horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	if direction.length() > 0.0:
		var target: Vector2 = Vector2(direction.x, direction.z) * move_speed * downed_speed_multiplier
		horizontal = horizontal.move_toward(target, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector2.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func _update_look(delta: float) -> void:
	var look: Vector2 = InputRouter.get_look_vector(player_id)
	_yaw -= look.x * look_sensitivity * delta
	_pitch -= look.y * look_sensitivity * delta
	_pitch = clamp(_pitch, deg_to_rad(pitch_min_deg), deg_to_rad(pitch_max_deg))
	rotation.y = _yaw
	_camera_pivot.rotation.x = _pitch


func _update_dash_timers(delta: float) -> void:
	if _dash_time_left > 0.0:
		_dash_time_left -= delta
	if _dash_cooldown_left > 0.0:
		_dash_cooldown_left -= delta

	if (
		_dash_cooldown_left <= 0.0
		and _dash_time_left <= 0.0
		and InputRouter.is_action_just_pressed(player_id, &"dash")
	):
		var move_input: Vector2 = InputRouter.get_move_vector(player_id)
		var dir_local: Vector3 = Vector3(move_input.x, 0.0, move_input.y)
		if dir_local.length() < 0.1:
			dir_local = Vector3.FORWARD
		_dash_direction = (transform.basis * dir_local).normalized()
		_dash_time_left = dash_duration
		_dash_cooldown_left = dash_cooldown
		dash_started.emit()


func _apply_movement(delta: float) -> void:
	if _dash_time_left > 0.0:
		velocity.x = _dash_direction.x * dash_speed
		velocity.z = _dash_direction.z * dash_speed
		if not is_on_floor():
			velocity.y -= gravity * delta
		return

	if not is_on_floor():
		velocity.y -= gravity * delta
	elif InputRouter.is_action_just_pressed(player_id, &"jump"):
		velocity.y = jump_velocity

	var input_2d: Vector2 = InputRouter.get_move_vector(player_id)
	var direction: Vector3 = (transform.basis * Vector3(input_2d.x, 0.0, input_2d.y)).normalized()

	var horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	if direction.length() > 0.0:
		var target: Vector2 = Vector2(direction.x, direction.z) * move_speed
		horizontal = horizontal.move_toward(target, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector2.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y


func get_camera() -> Camera3D:
	return _camera


## Reparente la Camera3D du player vers `viewport` et configure le
## RemoteTransform3D pour qu'elle suive la transform de `CameraPivot`.
##
## Utilisé par le SplitScreenManager au spawn. En mode solo, ne pas appeler
## cette méthode — la Camera3D reste dans le player.tscn et fonctionne
## directement.
func attach_camera_to(viewport: SubViewport) -> void:
	if _camera.get_parent() == viewport:
		return
	_camera.get_parent().remove_child(_camera)
	viewport.add_child(_camera)
	_camera.current = true
	# Le RemoteTransform3D vit dans le player (CameraPivot) et propage la
	# transform globale vers la Camera3D maintenant externe.
	_camera_remote.remote_path = _camera.get_path()


# -----------------------------------------------------------------------------
# Pull-stat getters (combinent base + reliques + buffs temp)
#
# Convention : les magnitude keys du YAML sont alignées avec le 2e arg de
# compute_stat(). Mode.ADD pour les bonus absolus (HP, ammo), Mode.MULT pour
# les multiplicateurs (damage_mult = +12 % par relique → mult sommé).
# Les buffs temporaires (move_speed_mult sur kill, damage_mult coop) sont
# ajoutés via relic_effects.sum_temp(stat_id).
# -----------------------------------------------------------------------------

func _ri_compute(stat_id: StringName, base: float, mode: int) -> float:
	if relic_inventory == null:
		return base
	var v: float = relic_inventory.compute_stat(stat_id, base, mode)
	if relic_effects != null:
		match mode:
			RelicInventory.Mode.ADD:
				v += relic_effects.sum_temp(stat_id)
			RelicInventory.Mode.MULT:
				v = base * (1.0 + (v / base - 1.0) + relic_effects.sum_temp(stat_id)) \
					if base != 0.0 else v
	return v


func get_max_hp() -> int:
	if _health == null:
		return 0
	if relic_inventory == null:
		return _health.max_health
	return relic_inventory.compute_stat_int(&"max_hp", _health.max_health, RelicInventory.Mode.ADD)


func get_move_speed() -> float:
	return _ri_compute(&"move_speed_mult", move_speed, RelicInventory.Mode.MULT)


func get_dash_cooldown() -> float:
	# dash_cooldown_mult est négatif (−0.20 = −20 %).
	if relic_inventory == null:
		return dash_cooldown
	var mult_sum: float = relic_inventory.compute_stat(&"dash_cooldown_mult", 0.0, RelicInventory.Mode.ADD)
	return max(0.05, dash_cooldown * (1.0 + mult_sum))


func get_damage_mult() -> float:
	# Reliques + stacks permanents (Léviathan).
	var base_mult: float = 1.0
	if relic_inventory != null:
		var sum: float = relic_inventory.compute_stat(&"damage_mult", 0.0, RelicInventory.Mode.ADD)
		base_mult += sum
	if relic_effects != null:
		base_mult += relic_effects.sum_temp(&"damage_mult")
		base_mult += relic_effects.get_runtime_damage_mult()
	return base_mult


func get_crit_chance() -> float:
	if relic_inventory == null:
		return 0.0
	return relic_inventory.compute_stat(&"crit_chance", 0.0, RelicInventory.Mode.ADD)


func get_fire_rate_mult() -> float:
	if relic_inventory == null:
		return 1.0
	return 1.0 + relic_inventory.compute_stat(&"fire_rate_mult", 0.0, RelicInventory.Mode.ADD)


func get_mag_capacity_bonus() -> int:
	if relic_inventory == null:
		return 0
	return relic_inventory.compute_stat_int(&"mag_capacity_bonus", 0, RelicInventory.Mode.ADD)


func get_hp_regen_per_sec() -> float:
	if relic_inventory == null:
		return 0.0
	return relic_inventory.compute_stat(&"hp_regen_per_sec", 0.0, RelicInventory.Mode.ADD)


func get_dash_distance_mult() -> float:
	if relic_inventory == null:
		return 1.0
	return 1.0 + relic_inventory.compute_stat(&"dash_distance_mult", 0.0, RelicInventory.Mode.ADD)


func get_extra_dash_charges() -> int:
	if relic_inventory == null:
		return 0
	return relic_inventory.compute_stat_int(&"dash_charges_bonus", 0, RelicInventory.Mode.ADD)


func get_extra_air_jumps() -> int:
	if relic_inventory == null:
		return 0
	return relic_inventory.compute_stat_int(&"air_jumps_bonus", 0, RelicInventory.Mode.ADD)


# -----------------------------------------------------------------------------
# Régénération HP passive (Sang du sanglier, Sigille du lien)
# -----------------------------------------------------------------------------
var _regen_accumulator: float = 0.0


func _physics_process_regen(delta: float) -> void:
	var rate: float = get_hp_regen_per_sec()
	if rate <= 0.0 or _health == null or _health.is_dead:
		return
	_regen_accumulator += rate * delta
	if _regen_accumulator >= 1.0:
		var n: int = int(floor(_regen_accumulator))
		_regen_accumulator -= float(n)
		_health.heal(n)

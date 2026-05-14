class_name HealthComponent
extends Node

## Pool de HP générique attachable comme enfant d'une entité (player, enemy).
## Émet des signaux pour que le HUD et le gameplay code y réagissent sans
## coupling fort.

signal health_changed(current: int, max: int)
signal damaged(amount: int, source: Node)
signal healed(amount: int)
signal died(source: Node)
signal burn_started(duration: float, dps: float, source: Node)
signal burn_ended()

@export var max_health: int = 100
@export var start_full: bool = true

var current_health: int = 0
var is_dead: bool = false
## Burn status : tant que > 0 on tick le DoT en _process.
var _burn_time_left: float = 0.0
var _burn_dps: float = 0.0
var _burn_source: Node = null
var _burn_accumulator: float = 0.0


func _ready() -> void:
	if start_full:
		current_health = max_health
	health_changed.emit(current_health, max_health)


func _process(delta: float) -> void:
	if _burn_time_left <= 0.0 or is_dead:
		return
	_burn_time_left -= delta
	_burn_accumulator += _burn_dps * delta
	# Quand on a accumulé au moins 1 dmg, on l'applique en entier.
	# Évite take_damage(1) chaque frame qui spammerait le signal.
	if _burn_accumulator >= 1.0:
		var int_dmg: int = int(_burn_accumulator)
		_burn_accumulator -= float(int_dmg)
		take_damage(int_dmg, _burn_source)
	if _burn_time_left <= 0.0:
		_burn_time_left = 0.0
		_burn_dps = 0.0
		_burn_source = null
		_burn_accumulator = 0.0
		burn_ended.emit()


## Applique (ou rafraîchit) un status de brûlure. `duration` en secondes,
## `dps` en HP/sec. Si déjà en burn, on garde le dps le plus élevé et on
## reset la durée à `duration`.
func apply_burn(duration: float, dps: float, source: Node = null) -> void:
	if is_dead or duration <= 0.0 or dps <= 0.0:
		return
	_burn_dps = max(_burn_dps, dps)
	_burn_time_left = duration
	_burn_source = source
	burn_started.emit(duration, _burn_dps, source)


func is_burning() -> bool:
	return _burn_time_left > 0.0


## Inflige `amount` PV de dégâts. `source` est l'attaquant (peut être null
## pour les dégâts d'environnement). Émet `damaged` puis `died` si HP <= 0.
## Ne fait rien si déjà mort.
func take_damage(amount: int, source: Node = null) -> void:
	if is_dead or amount <= 0:
		return
	current_health = max(0, current_health - amount)
	damaged.emit(amount, source)
	health_changed.emit(current_health, max_health)
	if current_health <= 0:
		is_dead = true
		died.emit(source)


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	current_health = min(max_health, current_health + amount)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)


## Reset au plein HP (utile après respawn). Clear aussi les status (burn).
func reset() -> void:
	current_health = max_health
	is_dead = false
	if _burn_time_left > 0.0:
		burn_ended.emit()
	_burn_time_left = 0.0
	_burn_dps = 0.0
	_burn_source = null
	_burn_accumulator = 0.0
	health_changed.emit(current_health, max_health)

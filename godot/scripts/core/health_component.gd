class_name HealthComponent
extends Node

## Pool de HP générique attachable comme enfant d'une entité (player, enemy).
## Émet des signaux pour que le HUD et le gameplay code y réagissent sans
## coupling fort.
##
## Status effects (burn, slow, freeze, poison, stun) sont délégués à un
## StatusComponent enfant instancié au _ready. Les signaux burn_started /
## burn_ended et la méthode apply_burn restent comme shims pour les
## consommateurs existants (fireball.gd, enemy_base.gd).

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
var _status: StatusComponent = null


func _ready() -> void:
	_status = StatusComponent.new()
	_status.name = "Status"
	add_child(_status)
	_status.status_damage_tick.connect(_on_status_damage_tick)
	_status.status_started.connect(_on_status_started)
	_status.status_ended.connect(_on_status_ended)
	if start_full:
		current_health = max_health
	health_changed.emit(current_health, max_health)


func get_status() -> StatusComponent:
	return _status


## Applique (ou rafraîchit) un status de brûlure. `duration` en secondes,
## `dps` en HP/sec. Shim qui délègue à StatusComponent.
func apply_burn(duration: float, dps: float, source: Node = null) -> void:
	if is_dead:
		return
	_status.apply_status(StatusComponent.BURN, duration, dps, source)


func is_burning() -> bool:
	return _status != null and _status.has_status(StatusComponent.BURN)


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
		_status.clear_all()
		died.emit(source)


func heal(amount: int) -> void:
	if is_dead or amount <= 0:
		return
	current_health = min(max_health, current_health + amount)
	healed.emit(amount)
	health_changed.emit(current_health, max_health)


## Reset au plein HP (utile après respawn). Clear aussi les status.
func reset() -> void:
	current_health = max_health
	is_dead = false
	if _status != null:
		_status.clear_all()
	health_changed.emit(current_health, max_health)


func _on_status_damage_tick(amount: int, source: Node) -> void:
	take_damage(amount, source)


func _on_status_started(id: StringName, duration: float, magnitude: float, source: Node) -> void:
	if id == StatusComponent.BURN:
		burn_started.emit(duration, magnitude, source)


func _on_status_ended(id: StringName) -> void:
	if id == StatusComponent.BURN:
		burn_ended.emit()

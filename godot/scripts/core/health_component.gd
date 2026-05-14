class_name HealthComponent
extends Node

## Pool de HP générique attachable comme enfant d'une entité (player, enemy).
## Émet des signaux pour que le HUD et le gameplay code y réagissent sans
## coupling fort.

signal health_changed(current: int, max: int)
signal damaged(amount: int, source: Node)
signal healed(amount: int)
signal died(source: Node)

@export var max_health: int = 100
@export var start_full: bool = true

var current_health: int = 0
var is_dead: bool = false


func _ready() -> void:
	if start_full:
		current_health = max_health
	health_changed.emit(current_health, max_health)


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


## Reset au plein HP (utile après respawn).
func reset() -> void:
	current_health = max_health
	is_dead = false
	health_changed.emit(current_health, max_health)

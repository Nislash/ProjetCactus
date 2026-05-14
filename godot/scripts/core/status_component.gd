class_name StatusComponent
extends Node

## Composant generique d'effets de status (burn, slow, freeze, poison, stun…).
## Attachable comme enfant de HealthComponent (instancie automatiquement en
## _ready). Tick les durees + les DoT en _process, expose has/get_magnitude
## pour les consommateurs (player_controller pour le slow, enemy AI pour le
## stun/freeze, etc.).
##
## API minimale :
##   apply_status(id, duration, magnitude, source)
##   remove_status(id)
##   has_status(id) -> bool
##   get_magnitude(id) -> float
##   clear_all()
##
## Pour les DoT (burn / poison), magnitude = DPS. status_damage_tick est
## emis quand un dmg entier est pret a etre applique. HealthComponent ecoute
## ce signal et appelle take_damage().

signal status_started(id: StringName, duration: float, magnitude: float, source: Node)
signal status_ended(id: StringName)
signal status_damage_tick(amount: int, source: Node)

const BURN := &"burn"
const SLOW := &"slow"
const FREEZE := &"freeze"
const POISON := &"poison"
const STUN := &"stun"

## id -> {duration_left: float, magnitude: float, source: Node, accumulator: float}
var _active: Dictionary = {}


## Applique (ou rafraichit) un status. Si deja actif : on garde la magnitude
## la plus haute et on prend la duree max entre l'existante restante et la
## nouvelle (pas de stack additif pour le POC, simple max).
func apply_status(id: StringName, duration: float, magnitude: float, source: Node = null) -> void:
	if duration <= 0.0 or magnitude <= 0.0:
		return
	if _active.has(id):
		var ex: Dictionary = _active[id]
		ex.duration_left = max(ex.duration_left, duration)
		ex.magnitude = max(ex.magnitude, magnitude)
		ex.source = source
	else:
		_active[id] = {
			"duration_left": duration,
			"magnitude": magnitude,
			"source": source,
			"accumulator": 0.0,
		}
		status_started.emit(id, duration, magnitude, source)


func remove_status(id: StringName) -> void:
	if _active.erase(id):
		status_ended.emit(id)


func has_status(id: StringName) -> bool:
	return _active.has(id)


## Magnitude actuelle d'un status (DPS pour burn/poison, slow_factor pour
## slow, etc.). Retourne 0.0 si le status n'est pas actif.
func get_magnitude(id: StringName) -> float:
	var ex: Variant = _active.get(id, null)
	if ex == null:
		return 0.0
	return ex.magnitude


## Duree restante d'un status. 0.0 si pas actif.
func get_duration_left(id: StringName) -> float:
	var ex: Variant = _active.get(id, null)
	if ex == null:
		return 0.0
	return ex.duration_left


func clear_all() -> void:
	var ids: Array = _active.keys()
	_active.clear()
	for id in ids:
		status_ended.emit(id)


func _process(delta: float) -> void:
	if _active.is_empty():
		return
	var to_remove: Array = []
	# Iteration sur une copie des cles pour pouvoir muter _active dans la
	# boucle si besoin.
	for id in _active.keys():
		var ex: Dictionary = _active[id]
		ex.duration_left -= delta
		# DoT ticks : burn et poison. magnitude = DPS.
		if id == BURN or id == POISON:
			ex.accumulator += ex.magnitude * delta
			if ex.accumulator >= 1.0:
				var dmg: int = int(ex.accumulator)
				ex.accumulator -= float(dmg)
				status_damage_tick.emit(dmg, ex.source)
		if ex.duration_left <= 0.0:
			to_remove.append(id)
	for id in to_remove:
		remove_status(id)

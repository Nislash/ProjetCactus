class_name RelicInventory
extends Node

## Inventaire des reliques d'UN joueur. Attaché en enfant du PlayerController
## (cf player.tscn → $RelicInventory). 5 slots max par défaut.
##
## Le RelicEffectResolver (autre enfant du player) écoute relic_added /
## relic_removed pour brancher les hooks événementiels. Pour les effets
## passifs (stat), le player tire via compute_stat() en pull-model.

signal relic_added(data: RelicData)
signal relic_removed(data: RelicData)
signal inventory_full_attempt(data: RelicData)
signal inventory_changed()

@export var max_slots: int = 5

enum Mode { ADD, MULT }

var _slots: Array[RelicData] = []


func try_add(data: RelicData) -> bool:
	if data == null:
		return false
	if _slots.size() >= max_slots:
		inventory_full_attempt.emit(data)
		return false
	_slots.append(data)
	relic_added.emit(data)
	inventory_changed.emit()
	return true


func remove(id: StringName) -> bool:
	for i in range(_slots.size()):
		if _slots[i].id == id:
			var data: RelicData = _slots[i]
			_slots.remove_at(i)
			relic_removed.emit(data)
			inventory_changed.emit()
			return true
	return false


func has(id: StringName) -> bool:
	for r in _slots:
		if r.id == id:
			return true
	return false


func get_relics() -> Array[RelicData]:
	return _slots.duplicate()


func is_full() -> bool:
	return _slots.size() >= max_slots


func get_count() -> int:
	return _slots.size()


## Combine la base avec tous les bonus stockés dans les magnitudes des
## reliques. La clé `stat_id` doit matcher la convention du YAML.
##
## - Mode.ADD  : retourne `base + somme(magnitude[stat_id])`
## - Mode.MULT : retourne `base * (1 + somme(magnitude[stat_id]))`
##                (chaque relique exprime son bonus en proportion : 0.12 = +12 %)
func compute_stat(stat_id: StringName, base: float, mode: int = Mode.ADD) -> float:
	var sum: float = 0.0
	for r in _slots:
		var v: Variant = r.get_magnitude(stat_id, null)
		if v == null:
			continue
		sum += float(v)
	match mode:
		Mode.ADD:
			return base + sum
		Mode.MULT:
			return base * (1.0 + sum)
	return base


## Variante stat int — convenience pour HP / capacités munitions.
func compute_stat_int(stat_id: StringName, base: int, mode: int = Mode.ADD) -> int:
	return int(round(compute_stat(stat_id, float(base), mode)))

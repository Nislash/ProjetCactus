extends Node

## Table de butin globale des reliques. Autoload `RelicLootTable`.
##
## Au _ready() scanne `res://resources/relics/*.tres` et range les RelicData
## par tier dans tier_pools. Expose des helpers de tirage pondéré.
##
## Conventions de probas (cf docs/design/relics.yaml + plan d'inventaire) :
## - draw_standard()      : 70 % commun, 25 % rare, 5 % épique (legendary 0 % par défaut)
## - draw_with(probs)     : override paramétrable (boss, shop, tuto)
## - draw_excluding(have) : évite les doublons en filtrant le pool
##
## Note tuto : les coffres du level_01_poc utilisent draw_standard() étendu pour
## inclure aussi les légendaires (cf relic_chest.gd → TIER_PROBS_TUTO).

const RELICS_DIR := "res://resources/relics"

var all_relics: Array[RelicData] = []
var tier_pools: Dictionary = {}  # int (RelicData.Tier) -> Array[RelicData]

const TIER_PROBS_STANDARD: Dictionary = {
	RelicData.Tier.COMMON: 0.70,
	RelicData.Tier.RARE: 0.25,
	RelicData.Tier.EPIC: 0.05,
	RelicData.Tier.LEGENDARY: 0.0,
}


func _ready() -> void:
	_scan_pool()
	print("[RelicLootTable] %d reliques chargées : %d commun / %d rare / %d épique / %d légendaire" % [
		all_relics.size(),
		(tier_pools.get(RelicData.Tier.COMMON, []) as Array).size(),
		(tier_pools.get(RelicData.Tier.RARE, []) as Array).size(),
		(tier_pools.get(RelicData.Tier.EPIC, []) as Array).size(),
		(tier_pools.get(RelicData.Tier.LEGENDARY, []) as Array).size(),
	])


func _scan_pool() -> void:
	all_relics.clear()
	tier_pools = {
		RelicData.Tier.COMMON: [] as Array[RelicData],
		RelicData.Tier.RARE: [] as Array[RelicData],
		RelicData.Tier.EPIC: [] as Array[RelicData],
		RelicData.Tier.LEGENDARY: [] as Array[RelicData],
	}
	var dir := DirAccess.open(RELICS_DIR)
	if dir == null:
		push_warning("[RelicLootTable] Dossier inaccessible : %s" % RELICS_DIR)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".tres"):
			var path := "%s/%s" % [RELICS_DIR, entry]
			var res: Resource = load(path)
			if res is RelicData:
				var data: RelicData = res
				all_relics.append(data)
				var pool: Array = tier_pools[data.tier]
				pool.append(data)
		entry = dir.get_next()
	dir.list_dir_end()


## Tire une relique standard. Si `tier_probs` omis, utilise TIER_PROBS_STANDARD.
## Retourne null si aucun pool ne peut fournir.
func draw_standard(tier_probs: Dictionary = TIER_PROBS_STANDARD) -> RelicData:
	return _draw_internal(tier_probs, [])


## Comme draw_standard mais filtre les ids déjà possédés.
func draw_excluding(owned: Array, tier_probs: Dictionary = TIER_PROBS_STANDARD) -> RelicData:
	var owned_ids: Array[StringName] = []
	for r in owned:
		if r is RelicData:
			owned_ids.append((r as RelicData).id)
	return _draw_internal(tier_probs, owned_ids)


## Override complet : caller fournit la map { Tier: poids }.
func draw_with(tier_probs: Dictionary) -> RelicData:
	return _draw_internal(tier_probs, [])


func _draw_internal(tier_probs: Dictionary, exclude_ids: Array[StringName]) -> RelicData:
	# Pondération sur les tiers non vides après filtrage exclude.
	var total: float = 0.0
	var weights: Array = []  # Array of [tier_int, weight] preserving order
	for tier in tier_probs.keys():
		var w: float = float(tier_probs[tier])
		if w <= 0.0:
			continue
		var pool: Array = _filtered_pool(tier, exclude_ids)
		if pool.is_empty():
			continue
		weights.append([tier, w])
		total += w
	if total <= 0.0 or weights.is_empty():
		# Fallback : retombe sur n'importe quel commun non exclu.
		var fallback: Array = _filtered_pool(RelicData.Tier.COMMON, exclude_ids)
		if fallback.is_empty():
			return null
		return fallback[randi() % fallback.size()]
	var roll: float = randf() * total
	var cumul: float = 0.0
	for entry in weights:
		cumul += float(entry[1])
		if roll <= cumul:
			var pool: Array = _filtered_pool(int(entry[0]), exclude_ids)
			return pool[randi() % pool.size()]
	# Floating-point safety : retourne le dernier non-vide.
	var last_pool: Array = _filtered_pool(int(weights[-1][0]), exclude_ids)
	return last_pool[randi() % last_pool.size()]


func _filtered_pool(tier: int, exclude_ids: Array[StringName]) -> Array:
	var base: Array = tier_pools.get(tier, [])
	if exclude_ids.is_empty():
		return base
	var out: Array = []
	for r in base:
		if r is RelicData and not exclude_ids.has((r as RelicData).id):
			out.append(r)
	return out


## Helper utilitaire pour les tests / debug : taille totale du pool.
func size() -> int:
	return all_relics.size()

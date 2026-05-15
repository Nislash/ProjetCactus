extends SceneTree

## Tests standalone des reliques. Lancer via :
##   godot --headless --path godot --script tests/test_relics.gd
##
## Pas de framework GUT requis. En mode --script les autoloads ne sont pas
## chargés, donc on instancie _loot manuellement.

const SAMPLE_COUNT := 10000

var _loot: Node = null


func _init() -> void:
	# Instancie manuellement _loot (mode --script saute les autoloads).
	_loot = preload("res://autoload/relic_loot_table.gd").new()
	_loot._ready()

	var failed: int = 0
	failed += _test_inventory_basic()
	failed += _test_inventory_full()
	failed += _test_inventory_compute_stat()
	failed += _test_loot_table_size()
	failed += _test_loot_table_distribution()
	failed += _test_loot_table_excluding()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — tous les tests passent")
		quit(0)


func _test_inventory_basic() -> int:
	var inv := RelicInventory.new()
	inv.max_slots = 3
	var d1 := _mock_relic(&"r1", 0)
	var d2 := _mock_relic(&"r2", 0)
	var ok1: bool = inv.try_add(d1)
	var ok2: bool = inv.try_add(d2)
	if not ok1 or not ok2:
		print("[FAIL] inventory_basic : try_add devrait passer")
		return 1
	if not inv.has(&"r1") or not inv.has(&"r2"):
		print("[FAIL] inventory_basic : has() devrait retourner true")
		return 1
	if inv.get_count() != 2:
		print("[FAIL] inventory_basic : get_count() != 2")
		return 1
	if not inv.remove(&"r1"):
		print("[FAIL] inventory_basic : remove devrait passer")
		return 1
	if inv.has(&"r1"):
		print("[FAIL] inventory_basic : has(r1) devrait être false après remove")
		return 1
	print("[OK] inventory_basic")
	return 0


func _test_inventory_full() -> int:
	var inv := RelicInventory.new()
	inv.max_slots = 2
	var d1 := _mock_relic(&"a", 0)
	var d2 := _mock_relic(&"b", 0)
	var d3 := _mock_relic(&"c", 0)
	inv.try_add(d1)
	inv.try_add(d2)
	var ok3: bool = inv.try_add(d3)
	if ok3:
		print("[FAIL] inventory_full : try_add devrait échouer quand plein")
		return 1
	if not inv.is_full():
		print("[FAIL] inventory_full : is_full() devrait être true")
		return 1
	print("[OK] inventory_full")
	return 0


func _test_inventory_compute_stat() -> int:
	var inv := RelicInventory.new()
	var d1 := _mock_relic(&"hp1", 0)
	d1.magnitude = {&"max_hp": 20}
	var d2 := _mock_relic(&"hp2", 0)
	d2.magnitude = {&"max_hp": 30}
	inv.try_add(d1)
	inv.try_add(d2)
	var combined: int = inv.compute_stat_int(&"max_hp", 100, RelicInventory.Mode.ADD)
	if combined != 150:
		print("[FAIL] compute_stat ADD : attendu 150, obtenu %d" % combined)
		return 1

	var d3 := _mock_relic(&"dmg", 0)
	d3.magnitude = {&"damage_mult": 0.12}
	var d4 := _mock_relic(&"dmg2", 0)
	d4.magnitude = {&"damage_mult": 0.08}
	inv.try_add(d3)
	inv.try_add(d4)
	var dmg: float = inv.compute_stat(&"damage_mult", 10.0, RelicInventory.Mode.MULT)
	if abs(dmg - 12.0) > 0.001:
		print("[FAIL] compute_stat MULT : attendu 12.0, obtenu %f" % dmg)
		return 1
	print("[OK] compute_stat (ADD + MULT)")
	return 0


func _test_loot_table_size() -> int:
	if _loot.size() != 50:
		print("[FAIL] loot_table_size : attendu 50, obtenu %d" % _loot.size())
		return 1
	print("[OK] loot_table_size = 50")
	return 0


func _test_loot_table_distribution() -> int:
	# Tire SAMPLE_COUNT fois et compare aux probas TIER_PROBS_STANDARD
	# (commun 70 % / rare 25 % / épique 5 %, legendary 0 %).
	# Tolérance ±2 % pour absorber le bruit.
	var counts: Dictionary = {
		RelicData.Tier.COMMON: 0,
		RelicData.Tier.RARE: 0,
		RelicData.Tier.EPIC: 0,
		RelicData.Tier.LEGENDARY: 0,
	}
	for i in range(SAMPLE_COUNT):
		var d: RelicData = _loot.draw_standard()
		if d == null:
			print("[FAIL] loot_table_distribution : draw retourne null")
			return 1
		counts[d.tier] = int(counts[d.tier]) + 1

	var ratios: Dictionary = {}
	for tier in counts.keys():
		ratios[tier] = float(counts[tier]) / float(SAMPLE_COUNT)

	var common_r: float = ratios[RelicData.Tier.COMMON]
	var rare_r: float = ratios[RelicData.Tier.RARE]
	var epic_r: float = ratios[RelicData.Tier.EPIC]
	var legend_r: float = ratios[RelicData.Tier.LEGENDARY]

	print("[INFO] Distribution : commun=%.3f / rare=%.3f / épique=%.3f / légend=%.3f" % [
		common_r, rare_r, epic_r, legend_r
	])
	var tol: float = 0.02
	if abs(common_r - 0.70) > tol:
		print("[FAIL] commun ratio %.3f hors [0.68, 0.72]" % common_r)
		return 1
	if abs(rare_r - 0.25) > tol:
		print("[FAIL] rare ratio %.3f hors [0.23, 0.27]" % rare_r)
		return 1
	if abs(epic_r - 0.05) > tol:
		print("[FAIL] épique ratio %.3f hors [0.03, 0.07]" % epic_r)
		return 1
	if legend_r > 0.001:
		print("[FAIL] légendaire devrait être 0 mais ratio = %.3f" % legend_r)
		return 1
	print("[OK] loot_table_distribution (±%.0f%%)" % (tol * 100.0))
	return 0


func _test_loot_table_excluding() -> int:
	# Vérifie que draw_excluding ne tire jamais un id déjà possédé.
	var all_commons: Array = _loot.tier_pools[RelicData.Tier.COMMON]
	if all_commons.is_empty():
		print("[FAIL] excluding : pool commun vide")
		return 1
	var owned: Array = [all_commons[0]]
	for i in range(1000):
		var d: RelicData = _loot.draw_excluding(
			owned,
			{RelicData.Tier.COMMON: 1.0}
		)
		if d != null and d.id == owned[0].id:
			print("[FAIL] excluding : id banni a été tiré")
			return 1
	print("[OK] loot_table_excluding (1000 tirages)")
	return 0


func _mock_relic(rid: StringName, tier: int) -> RelicData:
	var r := RelicData.new()
	r.id = rid
	r.display_name = "Mock " + str(rid)
	r.tier = tier
	r.effect_type = RelicData.EffectType.STAT
	r.trigger = RelicData.Trigger.PASSIVE
	r.magnitude = {}
	return r

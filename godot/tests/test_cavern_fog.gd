extends SceneTree

## Brume par zone (E3 #19). Lancer via :
##   godot --headless --path godot --script tests/test_cavern_fog.gd
##
## La brume porte la mécanique signature du niveau : elle doit VARIER, et varier
## dans le bon sens. Une brume mal réglée ne plante jamais — elle rend juste le
## niveau illisible ou plat, ce qu'aucune erreur ne signale.

const SCENE_PATH := "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"

var _fog: CavernFogZones


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var root_node: Node3D = (load(SCENE_PATH) as PackedScene).instantiate() as Node3D
	root.add_child(root_node)
	for i in 6:
		await process_frame
	_fog = root_node.get_node_or_null("World/FogZones") as CavernFogZones

	var failed: int = 0
	failed += _test_node_exists()
	failed += _test_zones_match_the_brief()
	failed += _test_contrast_is_the_point()
	failed += _test_density_is_derived_from_metres()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la brume varie comme la spec le demande")
		quit(0)


func _test_node_exists() -> int:
	if _fog == null:
		print("[FAIL] brume : nœud FogZones absent de la caverne")
		return 1
	print("[OK] node_exists")
	return 0


## Chaque zone doit rendre la portée annoncée par la spec, à sa position.
func _test_zones_match_the_brief() -> int:
	var probes: Array = [
		["Galerie centrale", Vector2(-54.0, -44.0), 28.0],
		["Poche du Loot", Vector2(-128.0, 8.0), 14.0],
		["Jardin de Givre", Vector2(-86.0, 34.0), 18.0],
		["Salle du Lac", Vector2(-4.0, 36.0), 65.0],
		["Bol de l'Arène", Vector2(100.0, -52.0), 32.0],
	]
	for probe in probes:
		var measured: float = _fog._view_distance_at(probe[1])
		# Tolérance large : les zones se mélangent aux frontières, c'est voulu.
		if absf(measured - probe[2]) > probe[2] * 0.35:
			print("[FAIL] zone « %s » : %.0f m mesurés, %.0f attendus" % [probe[0], measured, probe[2]])
			return 1
	print("[OK] zones_match_the_brief (%d zones sondées)" % probes.size())
	return 0


## LE test qui compte : c'est le CONTRASTE qui produit l'effet, pas les valeurs
## absolues. Sortir du boyau pour déboucher sur le lac doit multiplier la
## portée, sinon le soulagement ne se ressent pas.
func _test_contrast_is_the_point() -> int:
	var cramped: float = _fog._view_distance_at(Vector2(-128.0, 8.0))
	var open: float = _fog._view_distance_at(Vector2(-4.0, 36.0))
	var ratio: float = open / maxf(cramped, 0.001)

	if ratio < 3.0:
		print("[FAIL] contraste : le lac n'ouvre que ×%.1f sur le boyau — l'effet ne se sentira pas" % ratio)
		return 1
	print("[OK] contrast_is_the_point (le lac ouvre ×%.1f sur le boyau)" % ratio)
	return 0


## La densité doit être DÉRIVÉE de la portée en mètres, pas réglée au jugé :
## c'est ce qui rend les valeurs de la spec créative directement utilisables.
func _test_density_is_derived_from_metres() -> int:
	var environment: Environment = load(_fog.environment_path) as Environment
	if environment == null:
		print("[FAIL] densité : environnement introuvable")
		return 1

	for view_distance in [14.0, 28.0, 65.0]:
		_fog._apply(view_distance)
		var expected: float = 3.0 / view_distance
		if absf(environment.fog_density - expected) > 0.0005:
			print("[FAIL] densité : %.4f pour %.0f m, attendu %.4f"
				% [environment.fog_density, view_distance, expected])
			return 1
		if environment.volumetric_fog_density >= environment.fog_density:
			print("[FAIL] densité : le volumétrique est aussi dense que le brouillard — il noierait les colonnes de lumière")
			return 1
	print("[OK] density_is_derived_from_metres")
	return 0

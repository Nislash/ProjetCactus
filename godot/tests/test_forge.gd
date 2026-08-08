extends SceneTree

## La Forge (niveau 2). Lancer via :
##   godot --headless --path godot --script tests/test_forge.gd
##
## Le niveau 2 réutilise le générateur du niveau 1 : ce sont les **données**
## qui font le biome. Ce test défend ce qui, du coup, peut casser en silence —
## une donnée manquante ne lève aucune erreur, elle produit un niveau vide.
##
## Il vérifie aussi les deux promesses du biome, qui sont géométriques et donc
## mesurables : **on descend** (le sol du centre est plus bas que celui du
## pourtour), et **la lumière vient du bas** (les sources sont au niveau de la
## lave, pas de la voûte).

const SCENE_PATH := "res://scenes/levels/level_02_forge/level_02_forge.tscn"
const TERRAIN_PATH := "res://data/levels/level02_forge_terrain.tres"

var _root: Node3D
var _world: Node3D
var _terrain: CavernTerrainData
var _noise: FastNoiseLite


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_terrain = load(TERRAIN_PATH) as CavernTerrainData
	if _terrain == null:
		print("[FAIL] terrain introuvable — lancer tools/build_forge_terrain.gd")
		quit(1)
		return
	_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)

	var failed: int = 0
	failed += _test_the_floor_funnels_down()
	failed += _test_the_lava_is_at_the_bottom()
	failed += _test_slopes_stay_walkable()

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		print("[FAIL] scène introuvable : %s" % SCENE_PATH)
		quit(1)
		return
	_root = packed.instantiate() as Node3D
	root.add_child(_root)
	for i in 12:
		await process_frame
	_world = _root.get_node_or_null("World") as Node3D

	failed += _test_the_terrain_actually_builds()
	failed += _test_the_light_comes_from_below()
	failed += _test_spawns_are_on_the_rim()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la Forge descend vers sa lave")
		quit(0)


func _ground(at: Vector2) -> float:
	return CavernTerrainBuilder.sample_point(_terrain.floor_field, at, _noise)


## LA PROMESSE DU BIOME : on descend. Si le centre n'était pas plus bas que le
## pourtour, la Forge ne serait qu'une salle ronde de plus.
func _test_the_floor_funnels_down() -> int:
	var rim: float = _ground(Vector2(0.0, 48.0))
	var mid: float = _ground(Vector2(0.0, 30.0))
	var low: float = _ground(Vector2(0.0, 14.0))

	if not (rim > mid and mid > low):
		print("[FAIL] entonnoir : altitudes %.1f → %.1f → %.1f, ça ne descend pas"
			% [rim, mid, low])
		return 1
	var drop: float = rim - low
	if drop < 5.0:
		print("[FAIL] entonnoir : seulement %.1f m de dénivelé — on ne le sentira pas" % drop)
		return 1
	print("[OK] the_floor_funnels_down (%.1f m de la crête au bord du bassin)" % drop)
	return 0


func _test_the_lava_is_at_the_bottom() -> int:
	var lava: CavernLake = _terrain.lake
	if lava == null:
		print("[FAIL] lave : aucune nappe déclarée")
		return 1
	# Elle doit être SOUS le sol du pourtour, sinon elle déborderait dans les
	# galeries d'accès.
	var rim: float = _ground(Vector2(0.0, 48.0))
	if lava.surface_altitude >= rim:
		print("[FAIL] lave : à %.1f m alors que la crête est à %.1f m — elle déborde"
			% [lava.surface_altitude, rim])
		return 1
	# Et son fond doit être plat, sinon la nappe se réduit à une flaque.
	var flat_enough: bool = false
	for basin in _terrain.floor_field.basins:
		if basin.flat_bottom >= 0.35:
			flat_enough = true
	if not flat_enough:
		print("[FAIL] lave : aucun bassin à fond plat — la nappe sera une flaque")
		return 1
	print("[OK] the_lava_is_at_the_bottom (%.1f m, crête à %.1f m)"
		% [lava.surface_altitude, rim])
	return 0


## Les paliers doivent rester marchables. Un `smoothstep` pique à 1,5 fois sa
## pente moyenne — la faute qu'on a déjà payée au niveau 1.
func _test_slopes_stay_walkable() -> int:
	var worst: float = 0.0
	var worst_at := Vector2.ZERO
	var step: float = 2.0
	var r: float = 4.0
	while r < 56.0:
		var a: float = 0.0
		while a < TAU:
			var at := Vector2(cos(a) * r, sin(a) * r)
			var h: float = _ground(at)
			var hx: float = _ground(at + Vector2(step, 0.0))
			var hz: float = _ground(at + Vector2(0.0, step))
			var slope: float = rad_to_deg(atan(maxf(absf(hx - h), absf(hz - h)) / step))
			if slope > worst:
				worst = slope
				worst_at = at
			a += 0.35
		r += 3.0

	if worst > _terrain.max_slope_degrees + 2.0:
		print("[FAIL] pentes : %.1f° en (%.0f, %.0f), au-delà du plafond de %.0f°"
			% [worst, worst_at.x, worst_at.y, _terrain.max_slope_degrees])
		return 1
	print("[OK] slopes_stay_walkable (max %.1f°)" % worst)
	return 0


func _test_the_terrain_actually_builds() -> int:
	var terrain_node: Node = _world.get_node_or_null("ForgeTerrain")
	if terrain_node == null or terrain_node.get_child_count() == 0:
		print("[FAIL] terrain : rien n'a été construit dans la scène")
		return 1
	var lava_node: Node = _world.find_child("Lake", true, false)
	if lava_node == null:
		print("[FAIL] lave : la nappe n'apparaît pas dans la scène")
		return 1
	print("[OK] the_terrain_actually_builds (%d chunks)" % terrain_node.get_child_count())
	return 0


## LA DEUXIÈME PROMESSE : la lumière vient d'en bas. C'est le renversement qui
## fait le biome — si les lampes finissaient sous la voûte, on aurait refait la
## caverne en orange.
func _test_the_light_comes_from_below() -> int:
	var lights: Array[OmniLight3D] = []
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var l: OmniLight3D = n as OmniLight3D
		if l != null and l.name.begins_with("Lave"):
			lights.append(l)

	if lights.size() < 4:
		print("[FAIL] lumière : %d sources sur la lave, attendu au moins 4" % lights.size())
		return 1

	var rim: float = _ground(Vector2(0.0, 48.0))
	for l in lights:
		if l.global_position.y > rim:
			print("[FAIL] lumière : une source est à %.1f m, au-dessus de la crête (%.1f m)"
				% [l.global_position.y, rim])
			return 1
	print("[OK] the_light_comes_from_below (%d sources, toutes sous la crête)" % lights.size())
	return 0


func _test_spawns_are_on_the_rim() -> int:
	var spawns: Node = _world.get_node_or_null("PlayerSpawnPoints")
	if spawns == null or spawns.get_child_count() < 4:
		print("[FAIL] spawns : absents ou incomplets")
		return 1
	# On doit arriver EN HAUT : voir le gouffre avant d'y descendre est toute
	# la mise en scène du niveau.
	var low: float = _ground(Vector2(0.0, 14.0))
	for child in spawns.get_children():
		var m: Node3D = child as Node3D
		if m == null:
			continue
		if m.global_position.y < low + 4.0:
			print("[FAIL] spawn « %s » : à %.1f m, on n'arrive pas par le haut"
				% [m.name, m.global_position.y])
			return 1
	print("[OK] spawns_are_on_the_rim")
	return 0

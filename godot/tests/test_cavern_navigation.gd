extends SceneTree

## Traversabilité de la caverne (E2 #12). Lancer via :
##   godot --headless --path godot --script tests/test_cavern_navigation.gd
##
## L'étanchéité (#11) prouve qu'on ne peut ni sortir ni tomber. Elle ne prouve
## PAS qu'on peut aller quelque part : un volume parfaitement clos peut être
## parfaitement infranchissable. C'est ce test qui répond à « peut-on aller de A
## à B », en interrogeant le NavigationServer sur le relief réellement cuit.
##
## Le navmesh est l'autorité, pas la pente maximale du champ de hauteurs : les
## flancs des rampes creusées dans le bol d'arène sont raides, mais s'ils ne
## bloquent aucun chemin, ils ne sont qu'un décor.

const SCENE_PATH := "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"

## Écart maximal toléré entre un point du chemin et le navmesh sous lui.
##
## On ne peut PAS détecter une discontinuité en plafonnant la longueur des
## segments : `map_get_path` optimisé relie des COINS, donc une ligne droite de
## 30 m à travers le lac est légitimement un seul segment. On échantillonne
## donc le long du chemin et on vérifie que le sol est bien là — c'est la
## question qu'on se posait vraiment.
const MAX_OFF_MESH := 1.5

## Pas d'échantillonnage le long des segments, en mètres.
const SAMPLE_STEP := 2.0

## Distance maximale entre la destination demandée et le dernier point atteint.
## Au-delà, le NavigationServer a rendu un chemin tronqué — il ne mène pas là.
const MAX_DESTINATION_ERROR := 3.0

var _root: Node3D
var _map: RID


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		print("[FAIL] scène introuvable : %s" % SCENE_PATH)
		quit(1)
		return

	_root = packed.instantiate() as Node3D
	root.add_child(_root)

	# Laisse le terrain se construire, le navmesh cuire, puis le
	# NavigationServer synchroniser sa carte (il travaille en différé).
	for i in 20:
		await process_frame

	var region: NavigationRegion3D = _root.get_node_or_null("World/Navigation") as NavigationRegion3D
	if region == null:
		print("[FAIL] nœud World/Navigation absent de la scène")
		quit(1)
		return
	_map = region.get_navigation_map()

	var failed: int = 0
	failed += _test_navmesh_baked(region)
	failed += _test_spawns_are_on_navmesh()
	failed += _test_every_poi_reachable_from_every_spawn()
	failed += _test_full_traversal_spawn_to_boss()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la caverne est traversable")
		quit(0)


func _test_navmesh_baked(region: NavigationRegion3D) -> int:
	var mesh: NavigationMesh = region.navigation_mesh
	if mesh == null or mesh.get_polygon_count() == 0:
		print("[FAIL] navmesh : aucun polygone cuit")
		return 1
	print("[OK] navmesh_baked (%d polygones)" % mesh.get_polygon_count())
	return 0


## Un spawn hors navmesh, c'est un joueur qui apparaît là où aucune IA ne peut
## le rejoindre — le genre de bug qui ne se voit qu'au playtest à 4.
func _test_spawns_are_on_navmesh() -> int:
	for point in _spawns():
		var snapped: Vector3 = NavigationServer3D.map_get_closest_point(_map, point[1])
		var drift: float = snapped.distance_to(point[1])
		if drift > 2.0:
			print("[FAIL] spawn « %s » : à %.1f m du navmesh le plus proche" % [point[0], drift])
			return 1
	print("[OK] spawns_are_on_navmesh (%d spawns)" % _spawns().size())
	return 0


## Le cœur du test : chaque POI doit être atteignable depuis CHAQUE spawn.
## Tester depuis un seul spawn masquerait un îlot qui n'isole qu'un joueur.
func _test_every_poi_reachable_from_every_spawn() -> int:
	var failures: int = 0
	for spawn in _spawns():
		for poi in _points_of_interest():
			var report: Dictionary = _path_report(spawn[1], poi[1])
			if not report.ok:
				print("[FAIL] chemin « %s » → « %s » : %s" % [spawn[0], poi[0], report.reason])
				failures += 1
	if failures > 0:
		return 1
	print("[OK] every_poi_reachable_from_every_spawn (%d couples)"
		% (_spawns().size() * _points_of_interest().size()))
	return 0


## La boucle complète du plan : explorer → puzzle → boss. Vérifie que le
## parcours nominal s'enchaîne, pas seulement que les points sont accessibles.
func _test_full_traversal_spawn_to_boss() -> int:
	var legs: Array = [
		["spawn", Vector3(-104.0, 9.0, -38.0)],
		["poche du loot", Vector3(-126.0, 9.0, 6.0)],
		["anse sud-ouest", Vector3(-84.0, 3.0, 30.0)],
		["lac gelé", Vector3(-6.0, -1.0, 36.0)],
		["nef centre", Vector3(-16.0, 4.5, -38.0)],
		["crête du seuil", Vector3(42.0, 6.0, -47.0)],
		["arène (boss)", Vector3(100.0, -3.0, -52.0)],
	]
	var total: float = 0.0
	for i in legs.size() - 1:
		var report: Dictionary = _path_report(legs[i][1], legs[i + 1][1])
		if not report.ok:
			print("[FAIL] traversée « %s » → « %s » : %s" % [legs[i][0], legs[i + 1][0], report.reason])
			return 1
		total += report.length
	print("[OK] full_traversal_spawn_to_boss (%d étapes, %.0f m parcourus)" % [legs.size() - 1, total])
	return 0


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

## Calcule un chemin et vérifie qu'il est exploitable : non vide, sans saut
## entre deux points consécutifs, et arrivant effectivement à destination.
func _path_report(from: Vector3, to: Vector3) -> Dictionary:
	var start: Vector3 = NavigationServer3D.map_get_closest_point(_map, from)
	var finish: Vector3 = NavigationServer3D.map_get_closest_point(_map, to)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(_map, start, finish, true)

	if path.size() < 2:
		return {"ok": false, "reason": "aucun chemin", "length": 0.0}

	var length: float = 0.0
	for i in path.size() - 1:
		var gap: float = path[i].distance_to(path[i + 1])
		# Échantillonnage le long du segment : chaque point intermédiaire doit
		# reposer sur le navmesh. Un segment qui survole un trou trahit deux
		# îlots que le pathfinder a reliés alors que le joueur ne peut pas.
		var steps: int = maxi(int(gap / SAMPLE_STEP), 1)
		for s in range(1, steps):
			var probe: Vector3 = path[i].lerp(path[i + 1], float(s) / float(steps))
			var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(_map, probe)
			if on_mesh.distance_to(probe) > MAX_OFF_MESH:
				return {
					"ok": false,
					"reason": "le chemin survole le vide en (%.0f, %.0f, %.0f)" % [probe.x, probe.y, probe.z],
					"length": length,
				}
		length += gap

	var arrival_error: float = path[path.size() - 1].distance_to(finish)
	if arrival_error > MAX_DESTINATION_ERROR:
		return {
			"ok": false,
			"reason": "chemin tronqué, s'arrête à %.1f m de la destination" % arrival_error,
			"length": length,
		}
	return {"ok": true, "reason": "", "length": length}


func _spawns() -> Array:
	return [
		["Spawn0", Vector3(-104.0, 9.0, -44.0)],
		["Spawn1", Vector3(-100.0, 9.0, -38.0)],
		["Spawn2", Vector3(-104.0, 9.0, -32.0)],
		["Spawn3", Vector3(-108.0, 9.0, -38.0)],
	]


## Les 6 POI de la spec créative, plus l'arène. Coordonnées :
## docs/design/level01_topography.md §8.
func _points_of_interest() -> Array:
	return [
		["Lac gelé", Vector3(-6.0, -1.0, 36.0)],
		["Poche du Loot", Vector3(-126.0, 9.0, 6.0)],
		["Anse Sud-Ouest", Vector3(-84.0, 3.0, 30.0)],
		["Nef centre", Vector3(-16.0, 4.5, -38.0)],
		["Crête du Seuil", Vector3(42.0, 6.0, -47.0)],
		["Arène (boss)", Vector3(100.0, -3.0, -52.0)],
	]

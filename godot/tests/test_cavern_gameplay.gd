extends SceneTree

## Boucle de jeu de la caverne (E6 #29). Lancer via :
##   godot --headless --path godot --script tests/test_cavern_gameplay.gd
##
## Vérifie que la CHAÎNE du mécanisme secret tient de bout en bout :
##
##   3 cristaux éveillés → la Serrure s'illumine → elle devient interactive
##                       → la Porte s'effondre → le Fragment se révèle
##
## Chaque maillon est un signal branché à la main dans `CavernGameplay`. Un
## `connect` oublié ne casse rien au chargement : il produit une caverne où le
## joueur résout le puzzle et où **rien ne se passe**. Ce test transforme ce
## silence en échec.

const SCENE_PATH := "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"

var _root: Node3D
var _world: Node3D


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
	# Terrain, snapper, puis instanciation du gameplay.
	for i in 10:
		await process_frame
	_world = _root.get_node_or_null("World") as Node3D

	var failed: int = 0
	failed += _test_crystals_exist()
	failed += _test_secret_mechanism_exists()
	failed += _test_boss_is_in_the_arena()
	failed += await _test_puzzle_chain()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la boucle de jeu est câblée")
		quit(0)


func _find(type_name: String) -> Node:
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node.get_class() == "Node3D" or node is Node:
			var script: Script = node.get_script() as Script
			if script != null and script.get_global_name() == type_name:
				return node
	return null


func _find_all(type_name: String) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		var script: Script = node.get_script() as Script
		if script != null and script.get_global_name() == type_name:
			out.append(node)
	return out


func _test_crystals_exist() -> int:
	var crystals: Array[Node] = _find_all("PuzzleCrystal")
	if crystals.size() != 3:
		print("[FAIL] cristaux : %d posés au lieu de 3 — le puzzle serait insoluble" % crystals.size())
		return 1
	# Ils doivent être dispersés : trois cristaux côte à côte ne feraient pas
	# explorer la caverne, ce qui est tout l'objet du puzzle.
	for i in crystals.size():
		for j in range(i + 1, crystals.size()):
			var a: Vector3 = (crystals[i] as Node3D).global_position
			var b: Vector3 = (crystals[j] as Node3D).global_position
			if a.distance_to(b) < 40.0:
				print("[FAIL] cristaux : deux d'entre eux à %.0f m — trop proches pour faire explorer"
					% a.distance_to(b))
				return 1
	print("[OK] crystals_exist (3 cristaux, bien dispersés)")
	return 0


func _test_secret_mechanism_exists() -> int:
	for type_name in ["FrostLock", "CollapsedDoor", "MetaFragment"]:
		if _find(type_name) == null:
			print("[FAIL] mécanisme secret : « %s » absent" % type_name)
			return 1
	print("[OK] secret_mechanism_exists (serrure, porte, fragment)")
	return 0


## Le boss doit être DANS le bol, pas posé sur son bord : la révélation depuis
## la crête n'aurait aucun sens si le Golem se tenait au niveau du seuil.
func _test_boss_is_in_the_arena() -> int:
	var boss: Node3D = _world.get_node_or_null("BossGolem") as Node3D
	if boss == null:
		print("[FAIL] boss : aucun BossGolem instancié")
		return 1
	if boss.global_position.y > 0.0:
		print("[FAIL] boss : à l'altitude %.1f — il devrait être au fond du bol (négatif)"
			% boss.global_position.y)
		return 1
	print("[OK] boss_is_in_the_arena (altitude %.1f m)" % boss.global_position.y)
	return 0


## LE test de la chaîne : on éveille les cristaux un par un et on vérifie que
## chaque maillon réagit.
func _test_puzzle_chain() -> int:
	var crystals: Array[Node] = _find_all("PuzzleCrystal")
	var lock: Node = _find("FrostLock")
	var door: Node = _find("CollapsedDoor")
	var fragment: Node = _find("MetaFragment")
	if crystals.is_empty() or lock == null or door == null or fragment == null:
		print("[FAIL] chaîne : pièces manquantes, test impossible")
		return 1

	# La serrure ne doit RIEN accepter tant que le puzzle n'est pas fini.
	if lock.can_interact(null):
		print("[FAIL] chaîne : la serrure est interactive avant le puzzle — le secret n'en est pas un")
		return 1
	if fragment.visible:
		print("[FAIL] chaîne : le fragment est visible à travers la porte")
		return 1

	for i in crystals.size():
		var crystal: Node = crystals[i]
		if not crystal.can_interact(null):
			print("[FAIL] chaîne : le cristal %d refuse l'interaction" % i)
			return 1
		crystal.try_interact(null)
		await process_frame
		# Un cristal éveillé ne se ré-éveille pas : sinon un seul suffirait à
		# résoudre le puzzle en l'activant trois fois.
		if crystal.can_interact(null):
			print("[FAIL] chaîne : le cristal %d est réactivable" % i)
			return 1

		var expect_unlocked: bool = (i == crystals.size() - 1)
		if lock.can_interact(null) != expect_unlocked:
			print("[FAIL] chaîne : après %d/%d cristaux, serrure interactive = %s"
				% [i + 1, crystals.size(), lock.can_interact(null)])
			return 1

	lock.try_interact(null)
	await process_frame
	await process_frame

	if not fragment.visible:
		print("[FAIL] chaîne : la porte est tombée mais le fragment reste caché")
		return 1
	if lock.can_interact(null):
		print("[FAIL] chaîne : la serrure reste interactive après usage")
		return 1

	print("[OK] puzzle_chain (3 cristaux → serrure → porte → fragment)")
	return 0

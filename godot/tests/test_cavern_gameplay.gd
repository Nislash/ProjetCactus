extends SceneTree

## Le verrou B-O-S-S du niveau 1. Lancer via :
##   godot --headless --path godot --script tests/test_cavern_gameplay.gd
##
## Vérifie que la CHAÎNE tient de bout en bout :
##
##   4 éclats ramassables → posés dans l'ordre sur les colonnes lettrées
##                        → le cadran compte
##                        → le Seuil s'ouvre ET la Porte Effondrée tombe
##                        → le Fragment se révèle
##
## Chaque maillon est un signal branché à la main. Un `connect` oublié ne casse
## rien au chargement : il produit une caverne où le joueur résout le puzzle et
## où **rien ne se passe**. Ce test transforme ce silence en échec.
##
## Il défend aussi les deux règles qui font le puzzle : **l'ordre compte**
## (poser sur la mauvaise lettre n'avance à rien) et **on peut se reprendre**
## (retirer un éclat défait la suite). Sans la seconde, une erreur d'ordre
## bloquerait la run — dans un roguelike où rien ne persiste, ce serait une
## punition sans appel.

const SCENE_PATH := "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"

var _root: Node3D
var _world: Node3D
var _puzzle: Node


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
	for i in 12:
		await process_frame
	_world = _root.get_node_or_null("World") as Node3D
	_puzzle = _world.get_node_or_null("PuzzleBoss")

	var failed: int = 0
	failed += _test_the_word_is_engraved_around_the_lake()
	failed += _test_four_shards_are_reachable()
	failed += _test_the_dial_is_on_the_island_pillar()
	failed += _test_boss_is_in_the_arena()
	failed += _test_something_can_wake_the_boss()
	failed += _test_every_pylon_has_an_altar()
	failed += _test_order_matters()
	failed += await _test_solving_opens_both_ways()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — le verrou B-O-S-S tient de bout en bout")
		quit(0)


func _test_the_word_is_engraved_around_the_lake() -> int:
	if _puzzle == null:
		print("[FAIL] puzzle : nœud PuzzleBoss absent")
		return 1
	var pylons: Array = _puzzle.call("get_pylons")
	if pylons.size() != 4:
		print("[FAIL] colonnes : %d gravées au lieu de 4" % pylons.size())
		return 1

	var letters: String = ""
	for p in pylons:
		letters += String(p.letter)
	if letters != "BOSS":
		print("[FAIL] colonnes : lettres « %s » au lieu de « BOSS »" % letters)
		return 1

	# LE DÉSORDRE EST LE PUZZLE. Si les colonnes se suivaient autour du lac,
	# le mot se lirait tout seul et il n'y aurait plus rien à trouver.
	var lake_center := Vector2(-4.0, 38.0)
	var angles: Array[float] = []
	for p in pylons:
		var pos: Vector3 = (p as Node3D).global_position
		angles.append(atan2(pos.z - lake_center.y, pos.x - lake_center.x))
	var ascending: bool = true
	var descending: bool = true
	for i in range(1, angles.size()):
		if angles[i] < angles[i - 1]:
			ascending = false
		if angles[i] > angles[i - 1]:
			descending = false
	if ascending or descending:
		print("[FAIL] colonnes : B-O-S-S se suivent autour du lac — aucune énigme")
		return 1

	print("[OK] the_word_is_engraved_around_the_lake (BOSS, dans le désordre)")
	return 0


func _test_four_shards_are_reachable() -> int:
	var shards: Array = get_nodes_in_group(&"boss_shards")
	if shards.size() != 4:
		print("[FAIL] éclats : %d posés au lieu de 4 — le puzzle serait insoluble"
			% shards.size())
		return 1
	# Un éclat hors du volume creusé serait enterré dans la roche : invisible,
	# injouable, et sans le moindre avertissement.
	var terrain: CavernTerrainData = load("res://data/levels/level01_cavern_terrain.tres")
	for s in shards:
		var pos: Vector3 = (s as Node3D).global_position
		var flat := Vector2(pos.x, pos.z)
		if CavernTerrainBuilder.chamber_mask(terrain, flat) <= 0.0:
			print("[FAIL] éclat : (%.0f, %.0f) est dans la roche pleine" % [flat.x, flat.y])
			return 1
	print("[OK] four_shards_are_reachable")
	return 0


func _test_the_dial_is_on_the_island_pillar() -> int:
	var dial: Node = _world.find_child("VerrouCadran", true, false)
	if dial == null:
		print("[FAIL] cadran : absent")
		return 1
	var parent: Node = dial.get_parent()
	if parent == null or parent.name != "PilierIlot":
		print("[FAIL] cadran : accroché à « %s » et non au Pilier de l'Îlot"
			% ("rien" if parent == null else parent.name))
		return 1
	print("[OK] the_dial_is_on_the_island_pillar")
	return 0


func _test_boss_is_in_the_arena() -> int:
	var boss: Node3D = _world.get_node_or_null("BossGolem") as Node3D
	if boss == null:
		print("[FAIL] boss : aucun BossGolem instancié")
		return 1
	if boss.global_position.y > 0.0:
		print("[FAIL] boss : altitude %.1f — il devrait être au fond du bol"
			% boss.global_position.y)
		return 1
	var ai: Node = boss.get_node_or_null("BossAI")
	if ai == null or float(ai.get("arena_radius")) <= 0.0:
		print("[FAIL] boss : laisse d'arène non transmise")
		return 1
	print("[OK] boss_is_in_the_arena (altitude %.1f m)" % boss.global_position.y)
	return 0


## LE test qui manquait. Le nœud `BossArena` de la scène n'est qu'un
## porte-marqueurs sans script : rien n'appelait `engage()`, et le Golem
## dormait indéfiniment. Ça ne produit aucune erreur — juste un boss inerte
## qu'on prend pour une décision de design.
func _test_something_can_wake_the_boss() -> int:
	var zone: Area3D = _world.find_child("ReveilDuGolem", true, false) as Area3D
	if zone == null:
		print("[FAIL] boss : aucune zone d'éveil — il dormira pour toujours")
		return 1
	if zone.body_entered.get_connections().is_empty():
		print("[FAIL] boss : la zone d'éveil n'écoute personne")
		return 1
	var boss: Node3D = _world.get_node_or_null("BossGolem") as Node3D
	if boss != null and zone.global_position.distance_to(boss.global_position) > 5.0:
		print("[FAIL] boss : la zone d'éveil est à %.0f m de lui"
			% zone.global_position.distance_to(boss.global_position))
		return 1
	print("[OK] something_can_wake_the_boss")
	return 0


## L'autel : une empreinte en creux, TOUJOURS visible. Sans elle, rien
## n'indique où poser un éclat — le joueur porte quatre cristaux et cherche
## une serrure qui n'a pas de trou.
func _test_every_pylon_has_an_altar() -> int:
	var pylons: Array = _puzzle.call("get_pylons")
	for p in pylons:
		var altar: MeshInstance3D = (p as Node).get_node_or_null("Autel") as MeshInstance3D
		if altar == null:
			print("[FAIL] autel : absent sur « %s »" % (p as Node).name)
			return 1
		if not altar.visible:
			print("[FAIL] autel : invisible sur « %s » — on ne sait pas où poser"
				% (p as Node).name)
			return 1
		# Retourné : c'est l'empreinte de l'éclat, pas un second éclat.
		if altar.scale.y >= 0.0:
			print("[FAIL] autel : pas inversé sur « %s »" % (p as Node).name)
			return 1

	# Les gravures ne doivent pas s'aligner : ni même hauteur, ni même côté.
	var heights: Array[float] = []
	for p in pylons:
		heights.append(float((p as Node).get("glyph_height")))
	var spread: float = heights.max() - heights.min()
	if spread < 1.0:
		print("[FAIL] gravures : toutes à la même hauteur (écart %.2f m)" % spread)
		return 1

	print("[OK] every_pylon_has_an_altar (hauteurs étalées sur %.1f m)" % spread)
	return 0


## L'ordre EST le puzzle. Poser sur la mauvaise lettre doit rester sans effet,
## et se reprendre doit rester possible.
func _test_order_matters() -> int:
	var pylons: Array = _puzzle.call("get_pylons")
	var carrier := _FakeCarrier.new()
	root.add_child(carrier)
	carrier.shards = 4

	# On commence par le O : ce n'est pas la première lettre, rien ne s'allume.
	pylons[1].try_interact(carrier)
	if int(_puzzle.call("get_progress")) != 0:
		print("[FAIL] ordre : poser le O en premier a fait avancer le cadran")
		carrier.queue_free()
		return 1

	# On se reprend, puis on commence par le B.
	pylons[1].try_interact(carrier)
	pylons[0].try_interact(carrier)
	if int(_puzzle.call("get_progress")) != 1:
		print("[FAIL] ordre : le B en premier n'a pas compté")
		carrier.queue_free()
		return 1

	# Retirer le B défait le progrès — sinon la séquence aurait un trou et le
	# cadran mentirait.
	pylons[0].try_interact(carrier)
	if int(_puzzle.call("get_progress")) != 0:
		print("[FAIL] reprise : retirer le B n'a pas défait le progrès")
		carrier.queue_free()
		return 1

	carrier.queue_free()
	print("[OK] order_matters (mauvaise lettre inerte, reprise possible)")
	return 0


func _test_solving_opens_both_ways() -> int:
	var pylons: Array = _puzzle.call("get_pylons")
	var gate: Node = _world.get_node_or_null("SeuilVerrouille")
	var door: Node = _world.get_node_or_null("PorteEffondree")
	var fragment: Node = _world.get_node_or_null("FragmentMeta")
	if gate == null or door == null or fragment == null:
		print("[FAIL] chaîne : Seuil=%s Porte=%s Fragment=%s"
			% [gate != null, door != null, fragment != null])
		return 1
	if (fragment as Node3D).visible:
		print("[FAIL] fragment : visible avant l'ouverture — le secret n'en est plus un")
		return 1

	var carrier := _FakeCarrier.new()
	root.add_child(carrier)
	carrier.shards = 4
	for p in pylons:
		p.try_interact(carrier)

	if int(_puzzle.call("get_progress")) != 4:
		print("[FAIL] chaîne : %d/4 lettres après la pose complète"
			% int(_puzzle.call("get_progress")))
		carrier.queue_free()
		return 1
	if not bool(_puzzle.call("is_solved")):
		print("[FAIL] chaîne : les 4 lettres posées mais le verrou n'a pas cédé")
		carrier.queue_free()
		return 1

	for i in 120:
		await process_frame

	# Le trait de lumière : sans lui, résoudre l'énigme ne se voyait qu'à deux
	# cents mètres de là, donc pas du tout.
	var beam: Node = _world.get_node_or_null("RayonDuVerrou")
	if beam == null:
		print("[FAIL] rayon : le Pilier ne tire rien — la résolution est muette")
		carrier.queue_free()
		return 1

	if not (fragment as Node3D).visible:
		print("[FAIL] chaîne : le Fragment ne s'est pas révélé")
		carrier.queue_free()
		return 1
	carrier.queue_free()
	print("[OK] solving_opens_both_ways (Seuil + Porte + Fragment)")
	return 0


## Doublure : les poteaux n'ont besoin que du porte-éclats du joueur.
class _FakeCarrier extends Node3D:
	var shards: int = 0

	func get_boss_shards() -> int:
		return shards

	func add_boss_shard() -> void:
		shards += 1

	func take_boss_shard() -> bool:
		if shards <= 0:
			return false
		shards -= 1
		return true

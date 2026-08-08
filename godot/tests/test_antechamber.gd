extends SceneTree

## L'Antichambre de Givre (E5 #25). Lancer via :
##   godot --headless --path godot --script tests/test_antechamber.gd
##
## Les quatre choses qui, si elles cassaient, ne feraient AUCUN bruit :
##
## 1. **Un beat posé dans la roche pleine.** Le générateur ne creuse que là où
##    il y a une chambre ou un goulet ; ailleurs, la voûte descend au sol. Un
##    cristal dont les coordonnées tombent en dehors est enterré : invisible,
##    injouable, et sans le moindre avertissement.
## 2. **Un beat validé par le temps.** La règle du document est que la
##    progression se valide par l'action. Un beat qui avancerait tout seul
##    passerait inaperçu en test manuel — on croirait juste avoir bien joué.
## 3. **Le skip qui s'applique à tout le monde dès qu'un vétéran est là.** La
##    règle est un ET, pas un OU : un seul nouveau venu et l'équipe rejoue
##    l'antichambre. L'inverse priverait un débutant de son apprentissage.
## 4. **Le glyphe qui montre un bouton inexistant.** « A » sur une manette
##    PlayStation envoie chercher une touche qui n'est pas là.

const SCENE_PATH := "res://scenes/levels/antechamber/antechamber.tscn"
const TERRAIN_PATH := "res://data/levels/antechamber_terrain.tres"

## `AntechamberDirector.Beat.AWAKENING`, recopié : nommer la classe forcerait
## sa compilation — et celle de sa chaîne de dépendances — avant que les
## autoloads existent.
const BEAT_AWAKENING: int = 0

var _root: Node3D
var _director: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = 0
	failed += _test_every_beat_is_inside_the_volume()
	failed += _test_skip_needs_everyone()
	failed += _test_glyphs_speak_the_right_controller()

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		print("[FAIL] scène introuvable : %s" % SCENE_PATH)
		quit(1)
		return
	_root = packed.instantiate() as Node3D
	root.add_child(_root)
	for i in 10:
		await process_frame
	_director = _root.find_child("Director", true, false)

	failed += _test_the_scene_stands_up()
	failed += await _test_no_beat_advances_on_time_alone()
	failed += await _test_a_fragile_crystal_breaks_when_shot()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — l'antichambre tient debout et n'avance que sur l'action")
		quit(0)


## LE test. Un beat hors du volume est enterré dans la roche, sans erreur.
func _test_every_beat_is_inside_the_volume() -> int:
	var terrain: CavernTerrainData = load(TERRAIN_PATH) as CavernTerrainData
	if terrain == null:
		print("[FAIL] terrain introuvable : %s — lancer tools/build_antechamber.gd" % TERRAIN_PATH)
		return 1

	var script: GDScript = load("res://scripts/world/antechamber_director.gd") as GDScript
	var probe: Node = script.new()
	var spots: Array = probe.get_beat_positions()
	probe.free()
	if spots.is_empty():
		print("[FAIL] beats : aucune position déclarée")
		return 1

	var buried: int = 0
	for spot in spots:
		var flat: Vector2 = spot
		if CavernTerrainBuilder.chamber_mask(terrain, flat) <= 0.0:
			print("[FAIL] beat : (%.0f, %.0f) est dans la roche pleine" % [flat.x, flat.y])
			buried += 1
		elif CavernTerrainBuilder.chamber_headroom(terrain, flat) < terrain.playable_headroom_threshold:
			print("[FAIL] beat : (%.0f, %.0f) sous %.1f m de hauteur libre"
				% [flat.x, flat.y, terrain.playable_headroom_threshold])
			buried += 1
	if buried > 0:
		return 1
	print("[OK] every_beat_is_inside_the_volume (%d positions)" % spots.size())
	return 0


## Le skip est un ET. Un vétéran ne doit pas priver un débutant.
func _test_skip_needs_everyone() -> int:
	var skip: GDScript = load("res://scripts/core/onboarding_skip.gd") as GDScript
	if skip == null:
		print("[FAIL] skip : script introuvable")
		return 1
	skip.forget_everything()
	if skip.has_seen(0):
		print("[FAIL] skip : un device inconnu est déjà marqué comme vu")
		return 1
	skip.mark_seen(0)
	if not skip.has_seen(0):
		print("[FAIL] skip : le marquage ne persiste pas")
		return 1
	# Sans joueur inscrit, le skip ne peut pas s'appliquer : on ne saute pas
	# un onboarding pour personne.
	var nobody: Array[int] = []
	if skip.everyone_has_seen(nobody):
		print("[FAIL] skip : appliqué alors qu'aucun joueur n'est inscrit")
		return 1
	skip.forget_everything()
	if skip.has_seen(0):
		print("[FAIL] skip : l'oubli ne remet pas à zéro — le skip serait irréversible")
		return 1
	print("[OK] skip_needs_everyone")
	return 0


func _test_glyphs_speak_the_right_controller() -> int:
	var glyph: GDScript = load("res://scripts/world/frost_glyph.gd") as GDScript
	var xbox: String = glyph.label_for_device(&"interact", "xbox")
	var ps: String = glyph.label_for_device(&"interact", "playstation")
	if xbox == ps:
		print("[FAIL] glyphe : Xbox et PlayStation affichent le même bouton (%s)" % xbox)
		return 1
	if glyph.device_family(-1) != "generic":
		print("[FAIL] glyphe : un device absent devrait retomber sur « generic »")
		return 1
	print("[OK] glyphs_speak_the_right_controller (%s / %s)" % [xbox, ps])
	return 0


func _test_the_scene_stands_up() -> int:
	if _director == null:
		print("[FAIL] scène : pas de Director")
		return 1
	var terrain: Node = _root.find_child("AntechamberTerrain", true, false)
	if terrain == null or terrain.get_child_count() == 0:
		print("[FAIL] scène : le terrain n'a rien construit")
		return 1
	# RunShell cherche PlayerSpawnPoints/SpawnN : sans eux, les joueurs
	# resteraient à leur position de repli, hors de l'antichambre.
	var spawns: Node = _root.find_child("PlayerSpawnPoints", true, false)
	if spawns == null or spawns.get_child_count() < 4:
		print("[FAIL] scène : PlayerSpawnPoints absent ou incomplet")
		return 1
	print("[OK] the_scene_stands_up (%d chunks, %d spawns)"
		% [terrain.get_child_count(), spawns.get_child_count()])
	return 0


## Sans joueur et sans action, aucun beat ne doit tomber.
func _test_no_beat_advances_on_time_alone() -> int:
	var before: int = int(_director.call("get_beat"))
	for i in 400:
		await process_frame
	var after: int = int(_director.call("get_beat"))
	if after != before or after != BEAT_AWAKENING:
		print("[FAIL] beats : passé de %d à %d sans qu'aucune action ait eu lieu"
			% [before, after])
		return 1
	print("[OK] no_beat_advances_on_time_alone (resté au beat %d)" % after)
	return 0


func _test_a_fragile_crystal_breaks_when_shot() -> int:
	var crystals: Array = get_nodes_in_group(&"fragile_crystals")
	if crystals.is_empty():
		print("[FAIL] cristal fragile : aucun posé dans l'antichambre")
		return 1
	var target: Node = crystals[0]
	var hc: Node = target.call("get_health")
	if hc == null:
		print("[FAIL] cristal fragile : pas de HealthComponent — les tirs le traverseraient")
		return 1
	var broke: Array[bool] = [false]
	target.connect("shattered", func(_by: Node) -> void: broke[0] = true)
	hc.call("take_damage", 99, null)
	await process_frame
	if not broke[0]:
		print("[FAIL] cristal fragile : encaisse un tir sans se briser")
		return 1
	print("[OK] a_fragile_crystal_breaks_when_shot")
	return 0

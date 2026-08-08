extends SceneTree

## Ce que le HUD doit MONTRER. Lancer via :
##   godot --headless --path godot --script tests/test_hud_feedback.gd
##
## Trois retours de playtest, tous de la même famille : le jeu réagissait, mais
## le joueur ne le voyait pas. Un retour qu'on ne trouve pas ne compte pas.
##
## 1. **La jauge d'interaction** s'écrivait dans le panneau « Sort », en bas à
##    droite. Le joueur, lui, regarde le centre de l'écran — là où il vise. Il
##    a maintenu le bouton en croyant qu'il ne se passait rien.
## 2. **L'inventaire d'éclats** était au bord droit, choisi pour éviter la
##    barre de vie et la minimap. Personne ne l'y a cherché : l'autre
##    inventaire du jeu (les reliques) est en bas à gauche.
## 3. **La carte** cycle sur TROIS états, dont un « cachée ». Deux appuis
##    depuis l'état initial la font disparaître — ce qui se lit comme une
##    panne. Le cycle doit au moins revenir à son point de départ.

const HUD_SCENE := "res://scenes/ui/hud/player_hud.tscn"

var _hud: Control


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed: PackedScene = load(HUD_SCENE) as PackedScene
	if packed == null:
		print("[FAIL] HUD introuvable : %s" % HUD_SCENE)
		quit(1)
		return
	_hud = packed.instantiate() as Control
	root.add_child(_hud)
	await process_frame

	var failed: int = 0
	failed += _test_the_interaction_gauge_is_in_the_line_of_sight()
	failed += _test_the_shard_inventory_sits_with_the_other_one()
	failed += _test_the_map_cycle_comes_back()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — le HUD montre ce qu'il doit montrer")
		quit(0)


func _test_the_interaction_gauge_is_in_the_line_of_sight() -> int:
	# On simule le signal que le joueur émet en maintenant le bouton.
	_hud.call("_on_interaction_progress_changed", "Prendre l'éclat", 0.42)
	var label: Label = _hud.find_child("InteractPrompt", true, false) as Label
	var bar: ProgressBar = _hud.find_child("InteractBar", true, false) as ProgressBar
	if label == null or bar == null:
		print("[FAIL] jauge : ni texte ni barre — le joueur ne voit rien")
		return 1
	if not label.visible or not bar.visible:
		print("[FAIL] jauge : construite mais invisible pendant un maintien")
		return 1
	if not label.text.contains("42"):
		print("[FAIL] jauge : le pourcentage n'apparaît pas (« %s »)" % label.text)
		return 1
	# Centrée horizontalement et proche du bas : dans l'axe du regard.
	if label.anchor_left != 0.0 or label.anchor_right != 1.0:
		print("[FAIL] jauge : pas centrée sur la largeur")
		return 1
	if label.anchor_top != 1.0 or label.offset_top > -60.0:
		print("[FAIL] jauge : pas ancrée au bas de l'écran")
		return 1

	# Et elle disparaît quand on relâche.
	_hud.call("_on_interaction_progress_changed", "", 0.0)
	if label.visible or bar.visible:
		print("[FAIL] jauge : reste affichée après le relâchement")
		return 1

	print("[OK] the_interaction_gauge_is_in_the_line_of_sight")
	return 0


func _test_the_shard_inventory_sits_with_the_other_one() -> int:
	var row: Control = ShardRow.new()
	_hud.add_child(row)
	await_ready(row)
	if row.get_child_count() != BossPuzzle.SHARD_COUNT:
		print("[FAIL] inventaire : %d emplacements au lieu de %d"
			% [row.get_child_count(), BossPuzzle.SHARD_COUNT])
		return 1
	# En bas à gauche, comme la rangée de reliques (ancrée à gauche, bas).
	if row.anchor_left != 0.0 or row.anchor_top != 1.0:
		print("[FAIL] inventaire : pas ancré en bas à gauche")
		return 1
	if row.offset_left < 0.0:
		print("[FAIL] inventaire : hors de l'écran à gauche")
		return 1
	# Au-dessus des reliques (-180 → -120), donc plus haut que -180.
	if row.offset_bottom > -180.0:
		print("[FAIL] inventaire : chevauche la rangée de reliques")
		return 1
	print("[OK] the_shard_inventory_sits_with_the_other_one")
	return 0


## Le cycle doit refermer la boucle : sinon un joueur qui appuie deux fois
## perd sa carte et croit à une panne.
func _test_the_map_cycle_comes_back() -> int:
	var start: int = int(_hud.get("_minimap_state"))
	var seen: Array[int] = [start]
	for i in 8:
		_hud.call("_cycle_minimap_state")
		var now: int = int(_hud.get("_minimap_state"))
		if now == start:
			print("[OK] the_map_cycle_comes_back (%d états)" % (i + 1))
			return 0
		seen.append(now)
	print("[FAIL] carte : le cycle ne revient jamais à son état de départ (%s)" % [seen])
	return 1


func await_ready(node: Node) -> void:
	if not node.is_node_ready():
		node.notification(Node.NOTIFICATION_READY)

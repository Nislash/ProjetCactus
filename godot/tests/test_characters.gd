extends SceneTree

## Le catalogue de personnages et le repli d'animations. Lancer via :
##   godot --headless --path godot --script tests/test_characters.gd
##
## Ce qu'on éprouve ici tient en une phrase : **aucune animation n'est
## obligatoire**. Un personnage livré avec trois clips doit rester jouable, sans
## quoi il faudrait produire trente animations avant de pouvoir seulement le
## voir bouger — et personne n'essaierait jamais un nouveau personnage.


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = 0
	failed += _test_every_character_loads()
	failed += await _test_missing_animations_fall_back()
	failed += _test_the_roster_wraps_around()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — les personnages tiennent, même incomplets")
		quit(0)


## Chaque entrée du catalogue doit charger. Une entrée morte se traduit par un
## personnage vide à l'écran de choix, sans message.
func _test_every_character_loads() -> int:
	var roster: Array = load("res://autoload/character_roster.gd").ROSTER
	if roster.is_empty():
		print("[FAIL] catalogue : vide")
		return 1
	for entry in roster:
		var set_data: CharacterAnimSet = load(entry["set"]) as CharacterAnimSet
		if set_data == null:
			print("[FAIL] catalogue : %s introuvable" % entry["set"])
			return 1
		if set_data.model_scene == null:
			print("[FAIL] %s : aucun modèle" % entry["name"])
			return 1
		if set_data.available_states().is_empty():
			print("[FAIL] %s : aucune animation" % entry["name"])
			return 1
	print("[OK] every_character_loads (%d personnages)" % roster.size())
	return 0


## LE CŒUR DU TEST. Chaque état que l'animateur peut demander doit se résoudre
## vers quelque chose de jouable, pour CHAQUE personnage.
func _test_missing_animations_fall_back() -> int:
	# Une frame d'attente par personnage : `CharacterVisual` bâtit son
	# squelette et sa bibliothèque dans son `_ready`, qui ne s'exécute pas
	# avant que la racine soit elle-même prête.
	# Tout ce que `CharacterAnimator._pick_state()` peut produire.
	var demanded: Array[StringName] = [
		&"idle", &"walk", &"run",
		&"run_back", &"run_left", &"run_right",
		&"run_forward_left", &"run_forward_right",
		&"shoot_idle", &"shoot_walk_forward", &"shoot_walk_back", &"shoot_run",
		&"death",
	]
	var roster: Array = load("res://autoload/character_roster.gd").ROSTER
	for entry in roster:
		var set_data: CharacterAnimSet = load(entry["set"]) as CharacterAnimSet
		var visual := CharacterVisual.new()
		visual.anim_set = set_data
		root.add_child(visual)
		await process_frame
		for wanted in demanded:
			var resolved: StringName = visual.resolve_state(wanted)
			if resolved == &"":
				print("[FAIL] %s : « %s » ne se résout vers rien" % [entry["name"], wanted])
				visual.queue_free()
				return 1
		visual.queue_free()
	print("[OK] missing_animations_fall_back (%d états × %d personnages)"
		% [demanded.size(), roster.size()])
	return 0


## Le catalogue BOUCLE. Une liste qui bute à ses extrémités oblige à se rappeler
## où l'on est ; à la manette, avant chaque partie, c'est une friction inutile.
func _test_the_roster_wraps_around() -> int:
	var script: GDScript = load("res://autoload/character_roster.gd")
	var roster: Array = script.ROSTER
	var instance: Node = script.new()
	instance.select(0)
	instance.step(-1)
	if instance.current_index() != roster.size() - 1:
		print("[FAIL] catalogue : il ne boucle pas vers l'arrière")
		instance.free()
		return 1
	instance.step(1)
	if instance.current_index() != 0:
		print("[FAIL] catalogue : il ne boucle pas vers l'avant")
		instance.free()
		return 1
	instance.free()
	print("[OK] the_roster_wraps_around")
	return 0

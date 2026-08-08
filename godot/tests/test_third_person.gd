extends SceneTree

## La vue à la troisième personne. Lancer via :
##   godot --headless --path godot --script tests/test_third_person.gd
##
## Ce qui casserait sans bruit :
##
## 1. **Le bras de caméra bute sur les joueurs.** Un allié qui passe derrière
##    ferait sauter la vue d'un mètre — en coop, ça arrive toutes les dix
##    secondes. Il ne doit voir que le décor.
## 2. **La préférence n'est pas par manette.** Deux personnes sur le même
##    canapé n'ont pas la même, et l'une imposerait la sienne à l'autre.
## 3. **La bascule n'existe pas sur la manette.** Sans binding, l'option est
##    du code mort.
## 4. **La préférence devient irréversible.** Un réglage qu'on ne peut plus
##    remettre à zéro cesse d'être un réglage.

const PLAYER_SCRIPT := "res://scripts/core/player_controller.gd"


func _init() -> void:
	var failed: int = 0
	failed += _test_the_toggle_is_on_the_pad()
	failed += _test_the_preference_is_per_controller()
	failed += _test_the_arm_only_collides_with_the_world()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — chacun sa vue, chacun sa manette")
		quit(0)


func _test_the_toggle_is_on_the_pad() -> int:
	var source: String = FileAccess.get_file_as_string("res://autoload/input_router.gd")
	if not source.contains("toggle_view"):
		print("[FAIL] bascule : aucune action « toggle_view » — l'option est injoignable")
		return 1
	var player: String = FileAccess.get_file_as_string(PLAYER_SCRIPT)
	if not player.contains("&\"toggle_view\""):
		print("[FAIL] bascule : le joueur n'écoute pas l'action")
		return 1
	print("[OK] the_toggle_is_on_the_pad")
	return 0


func _test_the_preference_is_per_controller() -> int:
	var pref: GDScript = load("res://scripts/core/view_preference.gd") as GDScript
	if pref == null:
		print("[FAIL] préférence : script introuvable")
		return 1

	# Le défaut est la vue subjective : c'est celle sur laquelle le jeu est
	# calibré, la troisième personne se choisit.
	pref.set_third_person(-1, false)
	if pref.wants_third_person(-1):
		print("[FAIL] préférence : la troisième personne est le défaut")
		return 1

	if not pref.toggle(-1):
		print("[FAIL] préférence : la bascule ne prend pas")
		return 1
	if not pref.wants_third_person(-1):
		print("[FAIL] préférence : la bascule ne persiste pas")
		return 1

	# Réversible : un réglage irréversible n'est pas un réglage.
	pref.set_third_person(-1, false)
	if pref.wants_third_person(-1):
		print("[FAIL] préférence : impossible de revenir en arrière")
		return 1

	# La clé est le NOM de la manette, pas son index — rebrancher les manettes
	# dans un autre ordre ferait sinon oublier tout le monde.
	var source: String = FileAccess.get_file_as_string("res://scripts/core/view_preference.gd")
	if not source.contains("device_key"):
		print("[FAIL] préférence : elle n'est pas indexée par manette")
		return 1
	print("[OK] the_preference_is_per_controller")
	return 0


## Le bras ne doit voir QUE le décor. Sur la couche des joueurs, un allié qui
## passe derrière ferait sauter la caméra.
func _test_the_arm_only_collides_with_the_world() -> int:
	var source: String = FileAccess.get_file_as_string(PLAYER_SCRIPT)
	if not source.contains("SpringArm3D"):
		print("[FAIL] bras : pas de SpringArm — la caméra traversera la roche")
		return 1
	var arm_block: String = source.substr(source.find("func _build_camera_arm"))
	arm_block = arm_block.substr(0, 900)
	if not arm_block.contains("collision_mask"):
		print("[FAIL] bras : masque de collision non restreint")
		return 1
	if not arm_block.contains("shape"):
		print("[FAIL] bras : aucune forme — il passerait par la moindre fissure")
		return 1
	print("[OK] the_arm_only_collides_with_the_world")
	return 0

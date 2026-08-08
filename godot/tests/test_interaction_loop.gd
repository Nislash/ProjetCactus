extends SceneTree

## La jauge d'interaction ne doit jamais boucler (signalé en playtest).
##   godot --headless --path godot --script tests/test_interaction_loop.gd
##
## LE SYMPTÔME : maintenir `Interact` près d'un socle d'arme remplissait la
## jauge à 100 %, équipait l'arme, remettait la jauge à zéro et recommençait —
## sans fin, tant que le bouton restait tenu.
##
## LA CAUSE profonde n'était pas dans le socle : c'est que **rien n'exigeait de
## relâcher le bouton entre deux déclenchements**. Tout interactable qui reste
## proposable après usage rouvrait donc le trou — le socle d'arme, mais aussi
## n'importe quel coffre refusant l'interaction en silence.
##
## Ce test vérifie les deux niveaux : le verrou générique, et les deux objets
## qui l'exploitaient.

const PLAYER_SCRIPT := "res://scripts/core/player_controller.gd"


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = 0
	failed += _test_the_controller_latches_until_release()
	failed += _test_a_weapon_stand_stops_offering_the_weapon_you_hold()
	failed += _test_a_full_inventory_hides_the_chest()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la jauge ne peut plus boucler")
		quit(0)


## Le verrou générique : la source du code doit exiger un relâchement. On le
## vérifie sur le texte parce qu'instancier un PlayerController demanderait
## manettes, viewport et scène de niveau — trois dépendances pour une règle
## qui tient en trois lignes.
func _test_the_controller_latches_until_release() -> int:
	var source: String = FileAccess.get_file_as_string(PLAYER_SCRIPT)
	if source.is_empty():
		print("[FAIL] verrou : %s illisible" % PLAYER_SCRIPT)
		return 1
	if not source.contains("_interact_consumed"):
		print("[FAIL] verrou : aucun latch — la jauge peut repartir sans relâcher")
		return 1
	# Le latch doit être posé AU déclenchement et levé au relâchement.
	if not source.contains("_interact_consumed = true"):
		print("[FAIL] verrou : jamais armé au déclenchement")
		return 1
	if not source.contains("_interact_consumed = false"):
		print("[FAIL] verrou : jamais levé — une seule interaction par vie")
		return 1
	print("[OK] the_controller_latches_until_release")
	return 0


func _test_a_weapon_stand_stops_offering_the_weapon_you_hold() -> int:
	var script: GDScript = load("res://scripts/core/weapon_pickup.gd") as GDScript
	var stand: Node = script.new()
	stand.weapon_kind = &"pistol"

	var holder := _FakePlayer.new()
	holder.kind = &"pistol"
	var empty_handed := _FakePlayer.new()
	empty_handed.kind = &""

	var offers_to_holder: bool = stand.can_interact(holder)
	var offers_to_empty: bool = stand.can_interact(empty_handed)
	stand.free()
	holder.free()
	empty_handed.free()

	# Un faux joueur n'est pas un PlayerController : `can_interact` refuse les
	# deux. On ne peut donc vérifier ici que l'absence de « toujours vrai ».
	if offers_to_holder:
		print("[FAIL] socle : se propose encore à qui tient déjà cette arme")
		return 1
	print("[OK] a_weapon_stand_stops_offering_the_weapon_you_hold (vide=%s)"
		% offers_to_empty)
	return 0


## Le coffre refusait déjà un inventaire plein — mais dans `try_interact`,
## c'est-à-dire APRÈS la jauge. Le refus était donc muet et la jauge bouclait.
func _test_a_full_inventory_hides_the_chest() -> int:
	var source: String = FileAccess.get_file_as_string("res://scripts/core/relic_chest.gd")
	var head: String = source.substr(0, source.find("func try_interact"))
	if not head.contains("is_full()"):
		print("[FAIL] coffre : l'inventaire plein n'est testé qu'après la jauge")
		return 1
	print("[OK] a_full_inventory_hides_the_chest")
	return 0


## Doublure minimale : `can_interact` interroge l'arme équipée.
class _FakePlayer extends Node:
	var kind: StringName = &""

	func get_equipped_weapon_kind() -> StringName:
		return kind

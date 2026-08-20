extends SceneTree

## Le menu de pause. Lancer via :
##   godot --headless --path godot --script tests/test_pause_menu.gd
##
## Quatre choses qui casseraient sans bruit, et dont on ne s'apercevrait qu'une
## manette à la main :
##
## 1. **Le menu n'est pas dans le run.** Le script peut être parfait : s'il
##    n'est instancié nulle part, Start ne fait rien.
## 2. **Start n'est plus routé.** L'action `pause` existe dans le template de
##    l'InputRouter ; si elle disparaît ou change de bouton, le menu devient
##    inatteignable.
## 3. **La pause ne gèle pas, ou ne dégèle pas.** Le second cas est le pire :
##    on rend la main sur un jeu figé, et la seule sortie est de tuer le
##    processus.
## 4. **Deux écrans écoutent le même bouton.** Le game over et l'écran de stats
##    de boss attendent « n'importe quel appui » : le menu de pause ne doit pas
##    s'ouvrir par dessus.

const PAUSE_MENU_SCENE := "res://scenes/ui/hud/pause_menu.tscn"
const RUN_SHELL_SCENE := "res://scenes/run/run_shell.tscn"
const GAME_OVER_SCENE := "res://scenes/ui/hud/game_over_screen.tscn"
const SOURCE := "res://scripts/core/pause_menu.gd"

var _holder: Node
var _menu: CanvasLayer
var _game_over: Control


func _init() -> void:
	# Les autoloads (InputRouter, RunState) ne sont ajoutés à l'arbre qu'après
	# `_init` : tout script qui les nomme échouerait à compiler si on chargeait
	# les scènes tout de suite.
	_run.call_deferred()


func _run() -> void:
	# Les réglages vivent dans le dossier utilisateur de la machine, et sont
	# ceux du joueur qui lance les tests. On les remet en place à la fin.
	var saved_volume: float = GameSettings.master_volume()
	var saved_sensitivity: float = GameSettings.look_sensitivity()

	var packed: PackedScene = load(PAUSE_MENU_SCENE) as PackedScene
	if packed == null:
		print("[FAIL] menu de pause introuvable : %s" % PAUSE_MENU_SCENE)
		quit(1)
		return

	# Un parent commun : c'est là que le menu cherche les écrans qui pourraient
	# déjà attendre un appui, exactement comme dans run_shell.tscn.
	_holder = Node.new()
	root.add_child(_holder)
	_menu = packed.instantiate() as CanvasLayer
	_holder.add_child(_menu)
	_game_over = (load(GAME_OVER_SCENE) as PackedScene).instantiate() as Control
	_holder.add_child(_game_over)
	await process_frame

	var failed: int = 0
	failed += _test_the_run_carries_the_menu()
	failed += _test_start_reaches_every_registered_pad()
	failed += _test_opening_freezes_and_closing_thaws()
	failed += _test_it_stays_out_of_the_way_of_the_end_screens()
	failed += _test_the_classic_entries_are_there()
	failed += _test_the_settings_are_kept_and_clamped()
	failed += _test_inputs_go_through_the_router()

	# Ne jamais rendre la main sur un arbre gelé, même après un échec.
	paused = false
	GameSettings.set_master_volume(saved_volume)
	GameSettings.set_look_sensitivity(saved_sensitivity)

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la pause gèle, dégèle, et se laisse piloter")
		quit(0)


## Un menu jamais instancié est un menu qui n'existe pas pour le joueur.
func _test_the_run_carries_the_menu() -> int:
	var text: String = FileAccess.get_file_as_string(RUN_SHELL_SCENE)
	if not text.contains("pause_menu.tscn"):
		print("[FAIL] run_shell.tscn n'instancie pas le menu de pause")
		return 1
	print("[OK] the_run_carries_the_menu")
	return 0


## Start doit être branché POUR CHAQUE manette inscrite : c'est ce qui permet
## de nommer le joueur qui a mis en pause, et ce qui empêche la manette 2
## d'ouvrir le menu au nom de la 1.
func _test_start_reaches_every_registered_pad() -> int:
	# L'autoload se récupère par son chemin : un script lancé via `--script`
	# est compilé AVANT que les singletons ne soient déclarés, et le nommer
	# directement empêcherait le test de se charger.
	var router: Node = root.get_node_or_null(^"/root/InputRouter")
	if router == null:
		print("[FAIL] Start : autoload InputRouter absent")
		return 1
	var player_id: int = router.register_device(7)
	if player_id < 0:
		print("[FAIL] Start : impossible d'inscrire une manette de test")
		return 1
	var action: StringName = StringName("p%d_pause" % player_id)
	if not InputMap.has_action(action):
		router.unregister_player(player_id)
		print("[FAIL] Start : l'action « %s » n'existe pas" % action)
		return 1
	var on_start: bool = false
	for event in InputMap.action_get_events(action):
		var button := event as InputEventJoypadButton
		if button != null and button.button_index == JOY_BUTTON_START and button.device == 7:
			on_start = true
	router.unregister_player(player_id)
	if not on_start:
		print("[FAIL] Start : « %s » n'est pas sur le bouton Start de la manette" % action)
		return 1
	print("[OK] start_reaches_every_registered_pad")
	return 0


## Le cœur du sujet : le monde s'arrête, et il repart.
func _test_opening_freezes_and_closing_thaws() -> int:
	if not _menu.call("open", 0):
		print("[FAIL] pause : le menu refuse de s'ouvrir sur une partie normale")
		return 1
	if not paused:
		print("[FAIL] pause : l'arbre continue de tourner, menu ouvert")
		return 1
	if not _menu.call("is_open"):
		print("[FAIL] pause : le menu ne se déclare pas ouvert")
		return 1
	var screen: Control = _menu.get_node_or_null(^"Screen") as Control
	if screen == null or not screen.visible:
		print("[FAIL] pause : rien ne s'affiche à l'écran")
		return 1

	# Une seconde ouverture ne doit pas empiler d'états ni regeler autre chose.
	if _menu.call("open", 1):
		print("[FAIL] pause : le menu se rouvre alors qu'il est déjà ouvert")
		return 1

	_menu.call("close")
	if paused:
		print("[FAIL] pause : l'arbre reste gelé après fermeture — jeu bloqué")
		return 1
	if screen.visible:
		print("[FAIL] pause : l'écran reste affiché après fermeture")
		return 1
	print("[OK] opening_freezes_and_closing_thaws")
	return 0


## Game over et stats de boss attendent « n'importe quel appui ». Deux écrans
## sur le même bouton, c'est un des deux qui gagne au hasard.
func _test_it_stays_out_of_the_way_of_the_end_screens() -> int:
	_game_over.call("show_game_over")
	var opened: bool = _menu.call("open", 0)
	_game_over.visible = false
	if opened:
		_menu.call("close")
		print("[FAIL] écrans de fin : le menu s'ouvre par dessus le game over")
		return 1
	if paused:
		print("[FAIL] écrans de fin : refus d'ouverture mais arbre gelé quand même")
		return 1
	print("[OK] it_stays_out_of_the_way_of_the_end_screens")
	return 0


## Un menu de pause sans « Reprendre » n'est pas un menu de pause. Les quatre
## entrées attendues sont celles que tout joueur cherche sans lire.
func _test_the_classic_entries_are_there() -> int:
	var wanted: Array[String] = ["Reprendre", "Réglages", "Retour au menu", "Quitter le jeu"]
	var found: Array[String] = []
	_collect_button_texts(_menu, found)
	for label in wanted:
		if not found.has(label):
			print("[FAIL] entrées : « %s » absente (trouvées : %s)" % [label, ", ".join(found)])
			return 1
	print("[OK] the_classic_entries_are_there (%d boutons)" % found.size())
	return 0


func _collect_button_texts(node: Node, out: Array[String]) -> void:
	var button := node as Button
	if button != null and not button.text.is_empty():
		out.append(button.text)
	for child in node.get_children():
		_collect_button_texts(child, out)


## Les réglages se changent en pleine partie : ils doivent survivre au run, et
## une valeur aberrante ne doit pas rendre la visée injouable.
func _test_the_settings_are_kept_and_clamped() -> int:
	GameSettings.set_master_volume(0.42)
	if not is_equal_approx(GameSettings.master_volume(), 0.42):
		print("[FAIL] réglages : le volume ne se relit pas (%f)" % GameSettings.master_volume())
		return 1
	GameSettings.set_master_volume(4.0)
	if GameSettings.master_volume() > 1.0:
		print("[FAIL] réglages : volume au dessus du maximum")
		return 1
	GameSettings.set_look_sensitivity(999.0)
	if GameSettings.look_sensitivity() > GameSettings.SENSITIVITY_MAX:
		print("[FAIL] réglages : sensibilité au dessus du maximum")
		return 1
	GameSettings.set_look_sensitivity(-5.0)
	if GameSettings.look_sensitivity() < GameSettings.SENSITIVITY_MIN:
		print("[FAIL] réglages : sensibilité en dessous du minimum — caméra morte")
		return 1
	print("[OK] the_settings_are_kept_and_clamped")
	return 0


## Règle du projet (CLAUDE.md) : rien ne lit les manettes en direct, tout passe
## par l'InputRouter — sinon la manette 1 mettrait en pause au nom de tout le
## monde, et on ne saurait plus qui a appuyé.
func _test_inputs_go_through_the_router() -> int:
	var source: String = FileAccess.get_file_as_string(SOURCE)
	if source.contains("Input.is_action"):
		print("[FAIL] input : lecture directe de Input.is_action dans le menu")
		return 1
	if not source.contains("InputRouter.is_action_just_pressed"):
		print("[FAIL] input : le menu ne lit Start nulle part")
		return 1
	print("[OK] inputs_go_through_the_router")
	return 0

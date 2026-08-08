extends SceneTree

## L'écran d'accueil. Lancer via :
##   godot --headless --path godot --script tests/test_lobby.gd
##
## C'est le premier écran qu'un joueur voit, et c'est aussi celui qu'aucun
## test ne regardait. Trois choses qui casseraient sans bruit :
##
## 1. **Le shader de fond ne compile plus.** Un shader cassé n'annonce rien :
##    le matériau tourne sur ses valeurs par défaut et le fond redevient un
##    aplat. On a déjà payé ce piège deux fois sur ce projet.
## 2. **Un niveau de la liste n'existe pas.** Le menu le proposerait quand
##    même, et le jeu planterait au lancement — après le choix, donc au pire
##    moment.
## 3. **Le bouton Tutoriel revient**, ou la liste se repeuple de niveaux
##    inachevés. Une liste où presque tout déçoit n'est pas un choix.

const LOBBY_SCENE := "res://scenes/ui/lobby/lobby.tscn"
const BACKDROP_SHADER := "res://shaders/lobby_backdrop.gdshader"
const TITLE_FONT := "res://assets/fonts/october_crow.ttf"


func _init() -> void:
	var failed: int = 0
	failed += _test_the_backdrop_shader_compiles()
	failed += _test_every_offered_level_exists()
	failed += _test_the_tutorial_button_is_gone()
	failed += _test_the_title_font_is_there()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — l'écran d'accueil tient")
		quit(0)


func _test_the_backdrop_shader_compiles() -> int:
	var shader: Shader = load(BACKDROP_SHADER) as Shader
	if shader == null:
		print("[FAIL] fond : shader introuvable")
		return 1
	var uniforms: Array = shader.get_shader_uniform_list()
	if uniforms.is_empty():
		print("[FAIL] fond : 0 uniforme exposé — le shader ne compile pas")
		return 1
	var names: Array[String] = []
	for u in uniforms:
		names.append(String(u["name"]))
	for required in ["crystal_color", "vein_intensity"]:
		if not names.has(required):
			print("[FAIL] fond : uniforme « %s » absent" % required)
			return 1
	print("[OK] the_backdrop_shader_compiles (%d uniformes)" % uniforms.size())
	return 0


## Un niveau proposé mais absent plante APRÈS le choix du joueur.
func _test_every_offered_level_exists() -> int:
	# On lit le SOURCE plutôt que la constante : `get()` ne voit pas les
	# constantes d'un script, et `get_script_constant_map()` revient vide tant
	# que le script n'a pas été rechargé. Le texte, lui, est toujours là.
	var source: String = FileAccess.get_file_as_string("res://scripts/core/lobby_controller.gd")
	var levels_block: String = source.substr(source.find("const LEVELS"))
	levels_block = levels_block.substr(0, levels_block.find("\n]"))

	var paths: Array[String] = []
	for line in levels_block.split("\n"):
		var key: int = line.find("\"path\": \"")
		if key < 0:
			continue
		var rest: String = line.substr(key + 9)
		paths.append(rest.substr(0, rest.find("\"")))

	if paths.is_empty():
		print("[FAIL] niveaux : aucune entrée trouvée")
		return 1
	for path in paths:
		if not ResourceLoader.exists(path):
			print("[FAIL] niveau proposé mais absent : %s" % path)
			return 1
	print("[OK] every_offered_level_exists (%d niveaux)" % paths.size())
	return 0


func _test_the_tutorial_button_is_gone() -> int:
	var packed: PackedScene = load(LOBBY_SCENE) as PackedScene
	if packed == null:
		print("[FAIL] lobby : scène introuvable")
		return 1
	var state: SceneState = packed.get_state()
	for i in state.get_node_count():
		if state.get_node_name(i) == "BtnTuto":
			print("[FAIL] lobby : le bouton Tutoriel est revenu")
			return 1

	var source: String = FileAccess.get_file_as_string("res://scripts/core/lobby_controller.gd")
	if source.contains("TUTORIAL_PATH"):
		print("[FAIL] lobby : le chemin du tutoriel traîne encore dans le code")
		return 1
	# Les niveaux inachevés ne doivent pas revenir dans la liste.
	for banned in ["[GEN]", "[archive]"]:
		if source.contains(banned):
			print("[FAIL] lobby : des niveaux « %s » sont de nouveau proposés" % banned)
			return 1
	print("[OK] the_tutorial_button_is_gone")
	return 0


func _test_the_title_font_is_there() -> int:
	if not ResourceLoader.exists(TITLE_FONT):
		print("[FAIL] titre : police absente (%s)" % TITLE_FONT)
		return 1
	print("[OK] the_title_font_is_there")
	return 0

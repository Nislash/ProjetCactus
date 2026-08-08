extends Node

## Écran entre le jeu et l'outillage d'agent (`addons/godot_mcp`).
##
## ## Le problème que ce fichier règle
##
## Le plugin `godot_mcp` enregistre lui-même un autoload `MCPRuntime` qui, au
## démarrage, **ouvre une connexion WebSocket vers `ws://127.0.0.1:6505`** et
## expose de quoi lire l'arbre de scène, capturer l'écran et **injecter des
## entrées**. C'est exactement ce qu'il faut pendant le développement, et
## exactement ce qu'il ne faut pas dans un binaire distribué : un jeu livré
## qui écoute un port local et accepte des commandes n'est pas un jeu, c'est
## une porte.
##
## Exclure le dossier du plugin au moment de l'export ne suffit pas : la
## déclaration d'autoload, elle, reste dans `project.godot`, et le jeu
## exporté planterait au démarrage sur un script introuvable.
##
## Ce pont est donc déclaré à la place de `MCPRuntime`. Il n'instancie le vrai
## runtime **que dans l'éditeur**. Dans un build, il ne fait rien du tout, et
## le dossier `addons/` peut être exclu sans rien casser.
##
## ## Pourquoi un test de fonctionnalité et pas un `if` sur un booléen
##
## `OS.has_feature("editor")` est décidé au moment de l'export, pas à
## l'exécution : impossible de l'activer par accident dans un binaire livré.
## C'est le seul garde-fou qui ne dépend de la vigilance de personne.

const RUNTIME_SCRIPT := "res://addons/godot_mcp/runtime/mcp_runtime.gd"

var _runtime: Node


func _ready() -> void:
	if not OS.has_feature("editor"):
		# Build livré : rien ne s'ouvre, rien n'écoute.
		return
	if not ResourceLoader.exists(RUNTIME_SCRIPT):
		# Le plugin n'est pas installé sur cette machine : ce n'est pas une
		# erreur, juste un poste sans outillage d'agent.
		return
	var script: GDScript = load(RUNTIME_SCRIPT) as GDScript
	if script == null:
		push_warning("MCPBridge : %s illisible — outillage d'agent indisponible." % RUNTIME_SCRIPT)
		return
	_runtime = script.new()
	_runtime.name = "MCPRuntime"
	add_child(_runtime)


## Vrai si l'outillage tourne réellement. Le test s'en sert pour vérifier que
## le pont est bien fermé quand il doit l'être.
func is_tooling_active() -> bool:
	return _runtime != null and is_instance_valid(_runtime)

extends Node

## Shell d'execution d'un run. Charge dynamiquement la scene de niveau
## indiquee par RunState.selected_level_path dans le node $World, puis laisse
## le SplitScreenManager / EnemySpawner faire leur boulot habituel.
##
## Le scene fichier (run_shell.tscn) ne contient PAS de level prebake : il
## est totalement vide cote World, et c'est uniquement ici qu'on instancie
## le level choisi par le lobby. Permet de switcher Tuto / Run / autre sans
## dupliquer la scene wrapper.
##
## Si selected_level_path est vide (cas de lancement direct sans passer par
## le lobby) on tombe en fallback sur level_01_poc pour ne pas crasher.

const FALLBACK_LEVEL := "res://scenes/levels/level_01_poc/level_01_poc.tscn"

@onready var _world: Node3D = $World


func _ready() -> void:
	var level_path: String = RunState.selected_level_path
	if level_path.is_empty():
		push_warning("[RunShell] RunState.selected_level_path vide — fallback sur %s" % FALLBACK_LEVEL)
		level_path = FALLBACK_LEVEL
	_load_level(level_path)


func _load_level(path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("[RunShell] Impossible de charger %s" % path)
		return
	var instance: Node = scene.instantiate()
	_world.add_child(instance)

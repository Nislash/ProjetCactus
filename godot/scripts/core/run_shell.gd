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
##
## En plus du level, RunShell instancie 4 coffres de reliques à des positions
## tirées au hasard parmi les Marker3D du group "relic_chest_spawns" présents
## dans le niveau (cf level_01_poc → RelicChestSpawnPoints).

const FALLBACK_LEVEL := "res://scenes/levels/level_01_poc/level_01_poc.tscn"
const RELIC_CHEST_SCENE := "res://scenes/world/relic_chest.tscn"
const RELIC_CHESTS_PER_LEVEL := 4

@onready var _world: Node3D = $World


func _ready() -> void:
	var level_path: String = RunState.selected_level_path
	if level_path.is_empty():
		push_warning("[RunShell] RunState.selected_level_path vide — fallback sur %s" % FALLBACK_LEVEL)
		level_path = FALLBACK_LEVEL
	_load_level(level_path)
	_spawn_relic_chests()


func _load_level(path: String) -> void:
	var scene: PackedScene = load(path)
	if scene == null:
		push_error("[RunShell] Impossible de charger %s" % path)
		return
	var instance: Node = scene.instantiate()
	_world.add_child(instance)


## Pioche RELIC_CHESTS_PER_LEVEL markers parmi le group relic_chest_spawns
## (présents dans le level que vient d'instancier _load_level), et y instancie
## un relic_chest.tscn. Les markers non utilisés sont free.
func _spawn_relic_chests() -> void:
	# Le get_tree().get_nodes_in_group() n'est pas immédiat après add_child :
	# il faut un await frame pour que les nodes du level soient bien dans le
	# tree et que les groupes soient enregistrés.
	await get_tree().process_frame

	var markers: Array = get_tree().get_nodes_in_group(&"relic_chest_spawns")
	if markers.is_empty():
		push_warning("[RunShell] Aucun spawn point de coffre trouvé (group relic_chest_spawns)")
		return

	var chest_scene: PackedScene = load(RELIC_CHEST_SCENE)
	if chest_scene == null:
		push_error("[RunShell] Impossible de charger %s" % RELIC_CHEST_SCENE)
		return

	markers.shuffle()
	var spawn_count: int = min(RELIC_CHESTS_PER_LEVEL, markers.size())
	for i in range(spawn_count):
		var marker: Node3D = markers[i] as Node3D
		if marker == null:
			continue
		var chest: Node3D = chest_scene.instantiate() as Node3D
		_world.add_child(chest)
		chest.global_transform = marker.global_transform
	# Free les markers (utilisés ou non) — on n'en aura plus besoin et leur
	# présence dans le scene tree est inutile.
	for marker in markers:
		marker.queue_free()
	print("[RunShell] %d coffres de reliques placés (sur %d markers candidats)" % [spawn_count, markers.size()])

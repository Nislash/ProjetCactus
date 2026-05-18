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
const START_CHEST_SCENE := "res://scenes/world/start_chest.tscn"

@onready var _world: Node3D = $World


func _ready() -> void:
	var level_path: String = RunState.selected_level_path
	if level_path.is_empty():
		push_warning("[RunShell] RunState.selected_level_path vide — fallback sur %s" % FALLBACK_LEVEL)
		level_path = FALLBACK_LEVEL
	# Await pour les niveaux .tres qui ont une coroutine build_async dans le
	# DungeonBuilder. Pour les .tscn, _load_level retourne immédiatement
	# (await sur void = no-op).
	await _load_level(level_path)
	_spawn_relic_chests()
	_spawn_start_chest()


func _load_level(path: String) -> void:
	# Dispatch : .tres = LevelLayout généré par la pipeline → DungeonBuilder
	#           .tscn = ancienne scène pré-construite → load+instance direct
	if path.ends_with(".tres"):
		_load_generated_level(path)
		return

	var scene: PackedScene = load(path)
	if scene == null:
		push_error("[RunShell] Impossible de charger %s" % path)
		return
	var instance: Node = scene.instantiate()
	_world.add_child(instance)


func _load_generated_level(path: String) -> void:
	var layout_res: LevelLayout = load(path) as LevelLayout
	if layout_res == null:
		push_error("[RunShell] Impossible de charger LevelLayout %s" % path)
		return
	var builder := DungeonBuilder.new()
	builder.name = "DungeonBuilder"
	builder.layout = layout_res
	_world.add_child(builder)
	await builder.build_async()
	print("[RunShell] DungeonBuilder OK pour %s (level %s)" % [path, layout_res.level_name])
	# SplitScreenManager.spawn_slot a déjà spawné les joueurs aux fallback
	# positions (Vector3(-2,1,0) etc.) avant que les markers existent. On
	# les téléporte maintenant aux PlayerSpawnPoints/SpawnN que le builder
	# vient de créer.
	_relocate_players_to_dungeon_spawns()


func _relocate_players_to_dungeon_spawns() -> void:
	var spawn_root: Node = _world.find_child("PlayerSpawnPoints", true, false)
	if spawn_root == null:
		push_warning("[RunShell] PlayerSpawnPoints non trouvé — joueurs restent en fallback positions.")
		return
	for pid in PlayerManager.get_active_player_ids():
		var player: PlayerController = _find_player_controller(pid)
		if player == null:
			continue
		var marker: Node3D = spawn_root.get_node_or_null("Spawn%d" % pid) as Node3D
		if marker != null:
			player.set_spawn_position(marker.global_transform.origin)


func _find_player_controller(player_id: int) -> PlayerController:
	# Cherche un PlayerController dans _world avec le bon player_id.
	for child in _world.get_children():
		if child is PlayerController and (child as PlayerController).player_id == player_id:
			return child
		# Au cas où ils sont sous un autre node, recherche récursive.
		var found := _find_player_in_subtree(child, player_id)
		if found != null:
			return found
	return null


func _find_player_in_subtree(root: Node, player_id: int) -> PlayerController:
	for c in root.get_children():
		if c is PlayerController and (c as PlayerController).player_id == player_id:
			return c
		var deep := _find_player_in_subtree(c, player_id)
		if deep != null:
			return deep
	return null


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


## Place le coffre de début de run sur le Marker3D "StartChestSpawn" du
## level (si present). Le coffre, au try_interact, equipe tous les joueurs
## d'une arme + sort tirés au sort. Sans Marker, on log un warning : le
## level joue sans arme (mode test).
func _spawn_start_chest() -> void:
	await get_tree().process_frame
	var marker: Node3D = _world.find_child("StartChestSpawn", true, false) as Node3D
	if marker == null:
		push_warning("[RunShell] Pas de Marker3D 'StartChestSpawn' dans le level — pas de coffre de début. Les joueurs spawnent sans arme.")
		return
	var scene: PackedScene = load(START_CHEST_SCENE)
	if scene == null:
		push_error("[RunShell] Impossible de charger %s" % START_CHEST_SCENE)
		return
	var chest: Node3D = scene.instantiate() as Node3D
	_world.add_child(chest)
	chest.global_transform = marker.global_transform
	marker.queue_free()
	print("[RunShell] Coffre de début placé.")

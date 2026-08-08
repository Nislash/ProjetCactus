extends SceneTree

## Contrat de niveau de la caverne (E2 #13). Lancer via :
##   godot --headless --path godot --script tests/test_cavern_contract.gd
##
## Deux garanties, toutes deux apprises à la dure :
##
## 1. LE CONTRAT RUNSHELL EST HONORÉ. `run_shell.gd` et `enemy_spawner.gd`
##    cherchent des nœuds par NOM et par GROUPE (`PlayerSpawnPoints/SpawnN`,
##    `EnemySpawnPoints`, `StartChestSpawn`, groupe `relic_chest_spawns`). Une
##    faute de frappe ne casse rien au chargement : elle produit un warning et
##    un niveau silencieusement amputé — pas d'arme, pas de coffre, pas
##    d'ennemi. Ce test transforme ce silence en échec.
##
## 2. AUCUN MARQUEUR N'EST ENTERRÉ. Les marqueurs ont d'abord été posés aux
##    altitudes NOMINALES de la spec créative, alors que le sol généré s'en
##    écarte (ondulations, fondus qui se recouvrent). Trois l'étaient de 0,8 à
##    2,0 m — invisible sur un blockout gris, fatal en jeu. Le sol fait
##    désormais foi.

const SCENE_PATH := "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"
const TERRAIN_PATH := "res://data/levels/level01_cavern_terrain.tres"

## Écart vertical maximal toléré entre un marqueur et le sol sous lui.
## Couvre l'amplitude des ondulations sans laisser passer un enterrement.
const MAX_GROUND_OFFSET := 0.6

## Marqueurs volontairement décollés du sol : ceux posés sur un PROP (chaussée,
## îlot, pilier) et non sur le terrain. Le groupe est le même que celui du
## snapper — une seule source de vérité, sinon les deux divergent.
const GROUP_KEEP_ALTITUDE := &"keep_altitude"

var _scene_root: Node3D
var _world: Node3D
var _terrain: CavernTerrainData
var _noise: FastNoiseLite


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_terrain = load(TERRAIN_PATH) as CavernTerrainData
	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if _terrain == null or packed == null:
		print("[FAIL] terrain ou scène introuvable")
		quit(1)
		return

	if _terrain.floor_field.noise_amplitude > 0.0:
		_noise = FastNoiseLite.new()
		_noise.seed = _terrain.floor_field.noise_seed
		_noise.frequency = 1.0 / _terrain.floor_field.noise_scale

	_scene_root = packed.instantiate() as Node3D
	root.add_child(_scene_root)
	await process_frame
	_world = _scene_root.get_node_or_null("World") as Node3D

	var failed: int = 0
	failed += _test_world_node_exists()
	failed += _test_player_spawns()
	failed += _test_start_chest_spawn()
	failed += _test_relic_chest_spawns()
	failed += _test_enemy_spawns()
	failed += _test_environment_loaded()
	failed += _test_all_markers_are_grounded()
	failed += _test_markers_inside_bounds()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — le contrat de niveau est honoré")
		quit(0)


# ---------------------------------------------------------------------------
# Contrat RunShell / EnemySpawner
# ---------------------------------------------------------------------------

func _test_world_node_exists() -> int:
	if _world == null:
		print("[FAIL] world : nœud « World » absent — RunShell instancie le niveau dedans")
		return 1
	print("[OK] world_node_exists")
	return 0


## `SplitScreenManager._get_spawn_position` cherche « PlayerSpawnPoints » puis
## un enfant « SpawnN » par joueur. Sans eux, les 4 joueurs apparaissent aux
## positions de repli, autour de l'origine — c'est-à-dire au fond du lac.
func _test_player_spawns() -> int:
	var spawn_root: Node = _world.find_child("PlayerSpawnPoints", true, false)
	if spawn_root == null:
		print("[FAIL] spawns joueurs : nœud « PlayerSpawnPoints » introuvable")
		return 1
	for i in 4:
		if spawn_root.get_node_or_null("Spawn%d" % i) == null:
			print("[FAIL] spawns joueurs : « Spawn%d » manquant (le joueur %d tomberait au repli)" % [i, i])
			return 1
	print("[OK] player_spawns (4 spawns)")
	return 0


## Sans ce marqueur, `RunShell._spawn_start_chest` warn et la run démarre SANS
## ARME : le coffre de départ est ce qui tire la classe et l'arme.
func _test_start_chest_spawn() -> int:
	if _world.find_child("StartChestSpawn", true, false) == null:
		print("[FAIL] coffre de départ : « StartChestSpawn » introuvable — run sans arme")
		return 1
	print("[OK] start_chest_spawn")
	return 0


func _test_relic_chest_spawns() -> int:
	var markers: Array = _markers_in_group(&"relic_chest_spawns")
	if markers.is_empty():
		print("[FAIL] coffres de reliques : aucun marqueur dans le groupe « relic_chest_spawns »")
		return 1
	# RunShell en pioche 4 au hasard. En fournir plus fait varier la run d'une
	# partie à l'autre, ce qu'un roguelike doit faire.
	if markers.size() < 4:
		print("[FAIL] coffres de reliques : %d marqueurs, RunShell en tire 4" % markers.size())
		return 1
	print("[OK] relic_chest_spawns (%d candidats pour 4 tirages)" % markers.size())
	return 0


## Vérifie que chaque marqueur d'ennemi résout bien vers l'archétype voulu.
## Le repli par nom est fragile (n'importe quel « C » bascule en ranged) : ce
## test constate que les groupes explicites prennent effectivement le dessus.
func _test_enemy_spawns() -> int:
	var spawn_root: Node = _world.find_child("EnemySpawnPoints", true, false)
	if spawn_root == null:
		print("[FAIL] ennemis : nœud « EnemySpawnPoints » introuvable — niveau vide")
		return 1

	var melee: int = 0
	var ranged: int = 0
	for child in spawn_root.get_children():
		if not (child is Marker3D):
			continue
		var in_melee: bool = child.is_in_group(&"enemy_melee")
		var in_ranged: bool = child.is_in_group(&"enemy_ranged")
		var in_boss: bool = child.is_in_group(&"enemy_boss")
		if not (in_melee or in_ranged or in_boss):
			print("[FAIL] ennemis : « %s » n'a pas de groupe d'archétype (repli par nom, fragile)" % child.name)
			return 1
		if in_melee and in_ranged:
			print("[FAIL] ennemis : « %s » est à la fois mêlée et ranged" % child.name)
			return 1
		if in_melee:
			melee += 1
		elif in_ranged:
			ranged += 1

	if melee + ranged == 0:
		print("[FAIL] ennemis : aucun spawn exploitable")
		return 1
	print("[OK] enemy_spawns (%d mêlée, %d ranged)" % [melee, ranged])
	return 0


## Sans environnement, la caverne est un volume noir : le playtest est
## impossible et le bug se lit comme « le niveau ne charge pas ».
func _test_environment_loaded() -> int:
	var node: WorldEnvironment = _world.find_child("WorldEnvironment", true, false) as WorldEnvironment
	if node == null:
		print("[FAIL] environnement : nœud WorldEnvironment absent — caverne noire")
		return 1
	if node.environment == null:
		print("[FAIL] environnement : ressource non chargée — caverne noire")
		return 1
	print("[OK] environment_loaded")
	return 0


# ---------------------------------------------------------------------------
# Ancrage au sol
# ---------------------------------------------------------------------------

## LE test qui aurait attrapé les trois marqueurs enterrés. Chaque marqueur de
## gameplay doit reposer sur le sol RÉELLEMENT généré, pas sur l'altitude
## nominale que la spec créative annonce.
func _test_all_markers_are_grounded() -> int:
	var worst_name: String = ""
	var worst_offset: float = 0.0
	var checked: int = 0

	for marker in _all_gameplay_markers():
		if marker.is_in_group(GROUP_KEEP_ALTITUDE):
			continue
		var position: Vector3 = marker.global_transform.origin
		var ground: float = CavernTerrainBuilder.sample_point(
			_terrain.floor_field, Vector2(position.x, position.z), _noise)
		var offset: float = position.y - ground
		checked += 1
		if absf(offset) > absf(worst_offset):
			worst_offset = offset
			worst_name = marker.name
		if absf(offset) > MAX_GROUND_OFFSET:
			var verdict: String = "enterré" if offset < 0.0 else "en lévitation"
			print("[FAIL] marqueur « %s » %s de %.2f m (y=%.2f, sol=%.2f)"
				% [marker.name, verdict, absf(offset), position.y, ground])
			return 1

	print("[OK] all_markers_are_grounded (%d marqueurs, pire écart %.2f m sur « %s »)"
		% [checked, worst_offset, worst_name])
	return 0


## Un marqueur hors emprise serait dans la roche, hors du volume clos.
func _test_markers_inside_bounds() -> int:
	for marker in _all_gameplay_markers():
		var position: Vector3 = marker.global_transform.origin
		if position.x < _terrain.bounds_min.x or position.x > _terrain.bounds_max.x \
				or position.z < _terrain.bounds_min.y or position.z > _terrain.bounds_max.y:
			print("[FAIL] marqueur « %s » hors de l'emprise jouable (%.1f, %.1f)"
				% [marker.name, position.x, position.z])
			return 1
	print("[OK] markers_inside_bounds")
	return 0


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

## Tous les Marker3D du niveau, hors ceux du terrain généré (il n'en produit
## pas) — c'est-à-dire les points de gameplay posés à la main.
func _all_gameplay_markers() -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is Marker3D:
			out.append(node as Marker3D)
	return out


func _markers_in_group(group: StringName) -> Array[Marker3D]:
	var out: Array[Marker3D] = []
	for marker in _all_gameplay_markers():
		if marker.is_in_group(group):
			out.append(marker)
	return out

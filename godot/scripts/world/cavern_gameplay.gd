## Câble la boucle de jeu du niveau 1 sur les marqueurs de la caverne.
##
## LE PRINCIPE : la scène ne contient que des MARQUEURS. Tout ce qui vit —
## cristaux, porte, boss, fragment — est instancié ici, à l'exécution.
##
## C'est ce qui permet à la topographie de bouger sans casser le gameplay : les
## marqueurs sont recalés sur le terrain généré par le snapper, et les objets
## suivent. Poser les objets à la main dans la scène condamnerait à tout
## repositionner à chaque itération de layout — et on en a fait plusieurs.
##
## La boucle, telle que la spec la décrit (`level01_topography.md` §6) :
##
##   3 cristaux éveillés  →  la Serrure de Givre s'illumine
##                        →  interagir avec elle fait tomber la Porte Effondrée
##                        →  le Passage s'ouvre : raccourci vers le lac
##                           ET accès au Fragment méta
##
## Le boss, lui, ne dépend pas du puzzle : on peut aller le défier directement.
## Le puzzle récompense l'exploration, il ne la taxe pas.

class_name CavernGameplay
extends Node

const PUZZLE_CRYSTAL_SCENE := "res://scenes/world/puzzle_crystal.tscn"
const BOSS_SCENE := "res://scenes/boss/boss_golem.tscn"

## Marqueurs des cristaux du puzzle, sous `World/PuzzleCrystals`.
@export var crystal_marker_names: Array[String] = ["K1_Nid", "K2_Lanterne", "K3_Cuvette"]

## Si faux, le boss n'est pas instancié (utile pour explorer sans combat).
@export var spawn_boss: bool = true

## Rayon (m, horizontal) au-delà duquel le Golem refuse de suivre un joueur.
##
## Le bol de l'arène fait 38 × 30 m de rayons, et ses parois sont marchables
## (37°, sous le seuil de glissement) : sans cette laisse, on sort le boss de
## son arène simplement en remontant la pente. La valeur tient le combat dans
## le fond du bol, là où la mise en scène a été pensée.
@export var boss_leash_radius: float = 24.0

@export_file("*.tres") var rock_material_path: String = "res://data/levels/cavern_wall_material.tres"

## Émis quand les trois cristaux sont éveillés.
signal puzzle_completed()

var _world: Node3D
var _crystals: Array[PuzzleCrystal] = []
var _awakened: int = 0
var _frost_lock: FrostLock


func _ready() -> void:
	_world = get_parent() as Node3D
	if _world == null:
		push_error("CavernGameplay : doit être enfant du nœud World.")
		return

	# Deux frames : le terrain se construit, puis le snapper recale les
	# marqueurs. Instancier avant reviendrait à poser les objets dans le vide.
	await get_tree().process_frame
	await get_tree().process_frame

	_spawn_puzzle_crystals()
	_spawn_secret_mechanism()
	if spawn_boss:
		_spawn_boss()


# ---------------------------------------------------------------------------
# Le puzzle
# ---------------------------------------------------------------------------

func _spawn_puzzle_crystals() -> void:
	var root: Node = _world.get_node_or_null("PuzzleCrystals")
	if root == null:
		push_warning("CavernGameplay : nœud PuzzleCrystals introuvable.")
		return

	var packed: PackedScene = load(PUZZLE_CRYSTAL_SCENE) as PackedScene
	if packed == null:
		push_error("CavernGameplay : %s introuvable." % PUZZLE_CRYSTAL_SCENE)
		return

	for marker_name in crystal_marker_names:
		var marker: Node3D = root.get_node_or_null(marker_name) as Node3D
		if marker == null:
			push_warning("CavernGameplay : marqueur « %s » introuvable." % marker_name)
			continue
		var crystal: PuzzleCrystal = packed.instantiate() as PuzzleCrystal
		crystal.name = "Crystal_%s" % marker_name
		_world.add_child(crystal)
		crystal.global_position = marker.global_transform.origin
		crystal.activated.connect(_on_crystal_awakened)
		_crystals.append(crystal)

	print("[CavernGameplay] %d cristaux de puzzle posés." % _crystals.size())


func _on_crystal_awakened(_by_player: Node) -> void:
	_awakened += 1
	print("[CavernGameplay] cristal %d/%d éveillé." % [_awakened, _crystals.size()])
	if _frost_lock != null:
		_frost_lock.set_progress(_awakened, _crystals.size())
	if _awakened >= _crystals.size():
		puzzle_completed.emit()


# ---------------------------------------------------------------------------
# Le mécanisme secret
# ---------------------------------------------------------------------------

## La Serrure, la Porte et le Fragment. Le fragment n'est PAS posé maintenant :
## il apparaît quand la porte tombe, sinon on le verrait à travers l'obstacle
## et le secret n'en serait plus un.
func _spawn_secret_mechanism() -> void:
	var arena: Node = _world.get_node_or_null("BossArena")
	if arena == null:
		return

	var rock: Material = load(rock_material_path) as Material

	var door_marker: Node3D = arena.get_node_or_null("CollapsedDoor") as Node3D
	var lock_marker: Node3D = arena.get_node_or_null("FrostLock") as Node3D
	var fragment_marker: Node3D = arena.get_node_or_null("MetaFragment") as Node3D
	if door_marker == null or lock_marker == null:
		push_warning("CavernGameplay : marqueurs du mécanisme secret incomplets.")
		return

	var door := CollapsedDoor.new()
	door.name = "PorteEffondree"
	door.rock_material = rock
	_world.add_child(door)
	door.global_position = door_marker.global_transform.origin

	_frost_lock = FrostLock.new()
	_frost_lock.name = "SerrureDeGivre"
	_frost_lock.rock_material = rock
	_frost_lock.required_count = _crystals.size()
	_world.add_child(_frost_lock)
	_frost_lock.global_position = lock_marker.global_transform.origin
	# La Serrure commande la Porte, pas l'inverse : c'est le joueur qui décide
	# du moment où le passage s'ouvre, une fois qu'il en a gagné le droit.
	_frost_lock.unlocked.connect(door.collapse)

	if fragment_marker != null:
		var fragment := MetaFragment.new()
		fragment.name = "FragmentMeta"
		_world.add_child(fragment)
		fragment.global_position = fragment_marker.global_transform.origin + Vector3(0.0, 1.4, 0.0)
		fragment.visible = false
		door.collapsed.connect(func() -> void: fragment.reveal())


# ---------------------------------------------------------------------------
# Le boss
# ---------------------------------------------------------------------------

func _spawn_boss() -> void:
	var marker: Node3D = _world.get_node_or_null("BossArena/BossSpawn") as Node3D
	if marker == null:
		push_warning("CavernGameplay : BossSpawn introuvable — pas de boss.")
		return
	var packed: PackedScene = load(BOSS_SCENE) as PackedScene
	if packed == null:
		push_error("CavernGameplay : %s introuvable." % BOSS_SCENE)
		return
	var boss: Node3D = packed.instantiate() as Node3D
	boss.name = "BossGolem"
	_world.add_child(boss)
	boss.global_position = marker.global_transform.origin

	# La laisse : l'IA Rust ne connaît pas la topographie, on lui donne le
	# centre et le rayon de son territoire. Sans ça, elle suit sa cible
	# jusque dans la Grande Nef.
	var ai: Node = boss.get_node_or_null("BossAI")
	if ai != null and ai.has_method("set_arena"):
		ai.call("set_arena", boss.global_position, boss_leash_radius)
	else:
		push_warning("CavernGameplay : BossAI/set_arena introuvable — pas de laisse d'arène.")

	print("[CavernGameplay] boss posé en %v (laisse %.0f m)." % [boss.global_position, boss_leash_radius])

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
##   4 éclats ramassés  →  posés dans l'ordre B-O-S-S sur les colonnes du lac
##                      →  le cadran du Pilier de l'Îlot s'allume, lettre après
##                         lettre
##                      →  le Seuil s'ouvre (l'arène du Golem) ET la Porte
##                         Effondrée tombe (le Fragment méta)
##
## ## Pourquoi une seule mécanique de puzzle et non deux
##
## Il y en avait deux : trois cristaux à éveiller commandaient une Serrure de
## Givre, pendant que le boss restait accessible directement. En jeu, personne
## ne pouvait dire lequel des cristaux de la caverne servait à quoi, ni ce que
## comptaient les trois glyphes de la Serrure. Deux systèmes à moitié lus valent
## moins qu'un seul qu'on comprend : le puzzle B-O-S-S les remplace tous les
## deux, et son cadran est gravé sur le pilier le plus visible du niveau.

class_name CavernGameplay
extends Node

const BOSS_SCENE := "res://scenes/boss/boss_golem.tscn"

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

## Émis quand le mot B-O-S-S est complet.
signal puzzle_completed()

var _world: Node3D
var _boss_puzzle: BossPuzzle


func _ready() -> void:
	_world = get_parent() as Node3D
	if _world == null:
		push_error("CavernGameplay : doit être enfant du nœud World.")
		return

	# Deux frames : le terrain se construit, puis le snapper recale les
	# marqueurs. Instancier avant reviendrait à poser les objets dans le vide.
	await get_tree().process_frame
	await get_tree().process_frame

	_spawn_secret_mechanism()
	if spawn_boss:
		_spawn_boss()


# ---------------------------------------------------------------------------
# Le puzzle
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
	var fragment_marker: Node3D = arena.get_node_or_null("MetaFragment") as Node3D
	var gate_marker: Node3D = arena.get_node_or_null("PuzzleGate") as Node3D

	var door: CollapsedDoor = null
	if door_marker != null:
		door = CollapsedDoor.new()
		door.name = "PorteEffondree"
		door.rock_material = rock
		_world.add_child(door)
		door.global_position = door_marker.global_transform.origin

	# Le Seuil barré. C'est LUI qui rend le puzzle obligatoire : sans barrage,
	# « résoudre pour ouvrir l'arène » ne serait qu'une phrase de design.
	var gate: CollapsedDoor = null
	if gate_marker != null:
		gate = CollapsedDoor.new()
		gate.name = "SeuilVerrouille"
		gate.rock_material = rock
		_world.add_child(gate)
		gate.global_position = gate_marker.global_transform.origin

	var fragment: MetaFragment = null
	if fragment_marker != null:
		fragment = MetaFragment.new()
		fragment.name = "FragmentMeta"
		_world.add_child(fragment)
		fragment.global_position = fragment_marker.global_transform.origin + Vector3(0.0, 1.4, 0.0)
		fragment.visible = false
		if door != null:
			door.collapsed.connect(func() -> void: fragment.reveal())

	# Le puzzle commande les deux. On le crée après les obstacles pour que ses
	# connexions ne pointent jamais vers un nœud qui n'existe pas encore.
	_boss_puzzle = BossPuzzle.new()
	_boss_puzzle.name = "PuzzleBoss"
	_world.add_child(_boss_puzzle)
	_boss_puzzle.progress_changed.connect(_on_puzzle_progress)
	_boss_puzzle.solved.connect(func() -> void:
		if gate != null:
			gate.collapse()
		if door != null:
			door.collapse()
		puzzle_completed.emit())


func _on_puzzle_progress(lit: int, total: int) -> void:
	print("[CavernGameplay] verrou du boss : %d/%d lettres." % [lit, total])


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

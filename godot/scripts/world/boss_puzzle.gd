class_name BossPuzzle
extends Node

## Le verrou de l'arène : écrire **B O S S** autour du lac.
##
## ## La règle, et pourquoi elle tient sans un mot d'explication
##
## Quatre éclats identiques sont dispersés dans la caverne. Quatre colonnes du
## lac portent une lettre gravée — B, O, S, S — **dans le désordre**. Il faut
## alimenter les colonnes dans l'ordre du mot : d'abord celle qui porte le B,
## puis le O, puis les deux S.
##
## Les éclats étant interchangeables, la seule question est l'ordre. Y répondre
## demande d'avoir fait le tour du lac pour lire les lettres — la topographie
## devient l'énigme, ce qu'elle n'était nulle part ailleurs dans le niveau.
##
## Un éclat posé sur la mauvaise colonne **reste posé, mais éteint**. C'est le
## seul retour dont le joueur a besoin : il voit que ça ne prend pas, il
## reprend son éclat, il essaie ailleurs. Aucun texte, aucune pénalité.
##
## ## Ce que la résolution ouvre
##
## Les deux à la fois : **l'arène du Golem** (le blocage à l'entrée du Seuil
## disparaît) **et le Passage Effondré** vers le fragment du puzzle méta. Le
## puzzle est donc obligatoire, ce qui justifie que son cadran soit gravé en
## grand sur le pilier le plus visible du niveau.

signal progress_changed(lit: int, total: int)
signal solved()

const WORD := "BOSS"
const SHARD_COUNT := 4

## Où poser les éclats à ramasser, en (X, Z). Répartis sur le parcours : deux
## sur le chemin obligatoire, deux à l'écart — l'exploration doit payer, mais
## la run ne doit pas bloquer sur un éclat introuvable.
const SHARD_SPOTS: Array[Vector2] = [
	Vector2(-96.0, -30.0),   # Forêt de cristaux, près du chemin
	Vector2(-58.0, 54.0),    # Poche du Loot, à l'écart
	Vector2(6.0, 20.0),      # Rive sud du lac, sur le passage
	Vector2(-30.0, -58.0),   # Anse sud-ouest, à l'écart
]

@export_file("*.tres") var terrain_data_path: String = "res://data/levels/level01_cavern_terrain.tres"

## Si faux, rien n'est posé — utile pour visiter la caverne sans le puzzle.
@export var build_puzzle: bool = true

var _world: Node3D
var _terrain: CavernTerrainData
var _noise: FastNoiseLite
var _pylons: Array[LetterPylon] = []
var _indicator: BossLockIndicator
## Les colonnes validées, dans leur ordre de validation. Reprendre un éclat
## invalide tout ce qui a été posé APRÈS lui — sinon la séquence aurait des
## trous, et le cadran mentirait.
var _sequence: Array[LetterPylon] = []
var _solved: bool = false


func _ready() -> void:
	_world = get_parent() as Node3D
	if _world == null:
		push_error("BossPuzzle : doit être enfant du nœud World.")
		return
	_terrain = load(terrain_data_path) as CavernTerrainData
	if _terrain == null:
		push_error("BossPuzzle : terrain introuvable (%s)." % terrain_data_path)
		return
	_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)

	if not build_puzzle:
		return

	# Trois frames : le terrain, puis les structures du lac (les colonnes sur
	# lesquelles on grave), puis nous. Graver avant qu'elles existent ne
	# produirait rien — et ne dirait rien non plus.
	for i in 3:
		await get_tree().process_frame

	_engrave_pylons()
	_scatter_shards()
	_mount_indicator()
	_publish_progress()


func _ground(at: Vector2) -> Vector3:
	if _terrain == null:
		return Vector3(at.x, 0.0, at.y)
	return Vector3(at.x, CavernTerrainBuilder.sample_point(_terrain.floor_field, at, _noise), at.y)


# ---------------------------------------------------------------------------
# Les colonnes lettrées
# ---------------------------------------------------------------------------

## Grave les lettres sur des colonnes **déjà là** plutôt que d'en planter de
## nouvelles. La colonnade existe et soutient la voûte effondrée ; y ajouter
## quatre poteaux de puzzle les ferait lire comme du mobilier de jeu posé sur
## un décor. Gravées, elles deviennent le décor ET l'énigme.
func _engrave_pylons() -> void:
	var columns: Array[Node3D] = _find_lake_columns()
	if columns.size() < WORD.length():
		push_warning("BossPuzzle : %d colonnes trouvées pour %d lettres — puzzle incomplet."
			% [columns.size(), WORD.length()])
		if columns.is_empty():
			return

	# LE DÉSORDRE EST LE PUZZLE. Les colonnes sont ordonnées par angle autour
	# du lac ; on choisit un entrelacement fixe pour que B, O, S, S ne se
	# suivent jamais. Fixe et non aléatoire : une énigme qui change à chaque
	# run ne se raconte pas entre joueurs, et le niveau est un cadeau qu'on
	# montre.
	const SCRAMBLE: Array[int] = [2, 0, 3, 1]
	for i in mini(WORD.length(), columns.size()):
		var column: Node3D = columns[SCRAMBLE[i] % columns.size()]
		var pylon := LetterPylon.new()
		pylon.name = "Pylone_%s_%d" % [WORD[i], i]
		pylon.letter = WORD[i]
		column.add_child(pylon)
		pylon.position = Vector3.ZERO
		pylon.shard_placed.connect(_on_shard_placed)
		pylon.shard_removed.connect(_on_shard_removed)
		_pylons.append(pylon)


## Les colonnes de la couronne du lac, triées par angle pour que l'entrelacement
## soit reproductible. L'Îlot est écarté : son pilier porte le cadran.
func _find_lake_columns() -> Array[Node3D]:
	var out: Array[Node3D] = []
	var structures: Node = _world.find_child("LakeStructures", true, false)
	if structures == null:
		structures = _world
	for child in structures.get_children():
		var node: Node3D = child as Node3D
		if node == null or not node.name.begins_with("Colonne_"):
			continue
		out.append(node)
	var center: Vector2 = _terrain.lake.center if _terrain.lake != null else Vector2.ZERO
	out.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var pa: float = atan2(a.global_position.z - center.y, a.global_position.x - center.x)
		var pb: float = atan2(b.global_position.z - center.y, b.global_position.x - center.x)
		return pa < pb)
	return out


# ---------------------------------------------------------------------------
# Les éclats
# ---------------------------------------------------------------------------

func _scatter_shards() -> void:
	for i in SHARD_SPOTS.size():
		var at: Vector2 = SHARD_SPOTS[i]
		if CavernTerrainBuilder.chamber_mask(_terrain, at) <= 0.0:
			push_warning("BossPuzzle : éclat %d hors de la caverne (%.0f, %.0f)." % [i, at.x, at.y])
			continue
		var shard := BossShard.new()
		shard.name = "Eclat_%d" % i
		_world.add_child(shard)
		shard.global_position = _ground(at)


# ---------------------------------------------------------------------------
# Le cadran
# ---------------------------------------------------------------------------

func _mount_indicator() -> void:
	_indicator = BossLockIndicator.new()
	_indicator.name = "VerrouCadran"
	var pillar: Node3D = _world.find_child("PilierIlot", true, false) as Node3D
	if pillar != null:
		pillar.add_child(_indicator)
		# Sorti du fût : un tore centré sur l'axe serait à moitié dans la
		# pierre. Le fût fait 2,6 m de rayon en bas — on dégage un peu plus.
		_indicator.position = Vector3(0.0, 0.0, 2.9)
	else:
		push_warning("BossPuzzle : PilierIlot introuvable — cadran posé à la racine.")
		_world.add_child(_indicator)
		_indicator.global_position = _ground(Vector2(4.0, 28.0))


# ---------------------------------------------------------------------------
# La séquence
# ---------------------------------------------------------------------------

func _on_shard_placed(pylon: LetterPylon, _by_player: Node) -> void:
	# Le rang attendu est la longueur de la séquence déjà validée.
	var rank: int = _sequence.size()
	if rank < WORD.length() and pylon.letter == WORD[rank]:
		pylon.set_validated(true)
		_sequence.append(pylon)
	# Sinon : l'éclat reste posé, mais éteint. Le joueur le voit.
	_publish_progress()


func _on_shard_removed(pylon: LetterPylon, _by_player: Node) -> void:
	var index: int = _sequence.find(pylon)
	if index >= 0:
		# Tout ce qui a été validé APRÈS lui perd son rang : une séquence
		# trouée n'est plus une séquence.
		for i in range(_sequence.size() - 1, index - 1, -1):
			_sequence[i].set_validated(false)
			_sequence.remove_at(i)
	_publish_progress()


func _publish_progress() -> void:
	var lit: int = _sequence.size()
	if _indicator != null:
		_indicator.refresh(lit, WORD.length())
	progress_changed.emit(lit, WORD.length())
	if lit >= WORD.length() and not _solved:
		_solved = true
		if _indicator != null:
			_indicator.play_unlock()
		solved.emit()


func is_solved() -> bool:
	return _solved


func get_progress() -> int:
	return _sequence.size()


## Lecture pour les tests : les colonnes gravées, dans l'ordre du mot.
func get_pylons() -> Array[LetterPylon]:
	return _pylons

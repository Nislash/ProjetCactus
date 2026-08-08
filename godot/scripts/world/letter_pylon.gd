class_name LetterPylon
extends Interactable

## Un poteau du lac, gravé d'une lettre, qui peut recevoir un éclat.
##
## Les quatre lettres **B O S S** sont réparties dans le désordre sur les
## colonnes qui bordent le lac. Lire le mot demande donc d'en faire le tour —
## et c'est le seul moment du niveau où la topographie sert d'énigme plutôt
## que de décor.
##
## L'interaction est une BASCULE : poser si on porte un éclat et que le poteau
## est vide, reprendre si le poteau est servi. Reprendre doit rester possible,
## sinon une erreur d'ordre bloquerait la run — dans un roguelike où rien ne
## persiste, ce serait une punition sans appel.

signal shard_placed(pylon: LetterPylon, by_player: Node)
signal shard_removed(pylon: LetterPylon, by_player: Node)

## La lettre gravée. Une seule majuscule.
@export var letter: String = "B"

## Hauteur de la gravure sur le fût, en mètres.
@export var glyph_height: float = 3.2

var _filled: bool = false
## Vrai si l'éclat posé ici a bien été placé au bon rang de la séquence.
var _validated: bool = false

var _glyph: Label3D
var _socket_mesh: MeshInstance3D
var _socket_material: StandardMaterial3D
var _glow: OmniLight3D


func _ready() -> void:
	super._ready()
	add_to_group(&"letter_pylons")
	prompt_text = "Placer l'éclat"
	hold_duration = 0.6
	interaction_range = 3.2
	selection_priority = 12
	_build()
	_refresh()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.6
	shape.shape = sphere
	add_child(shape)

	# La gravure. Un Label3D et non une géométrie : la lettre doit rester
	# lisible de l'autre rive, à trente mètres et à travers la brume.
	_glyph = Label3D.new()
	_glyph.name = "Gravure"
	_glyph.text = letter
	_glyph.font_size = 256
	_glyph.pixel_size = 0.010
	_glyph.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_glyph.shaded = false
	_glyph.no_depth_test = false
	_glyph.modulate = CrystalGrammar.COLOR_BOSS_LOCK
	_glyph.outline_size = 24
	_glyph.outline_modulate = Color(0.02, 0.06, 0.10, 0.9)
	_glyph.position = Vector3(0.0, glyph_height, 0.0)
	add_child(_glyph)

	# Le berceau : une coupelle à hauteur de main, vide au départ. Sa présence
	# dit « quelque chose se pose ici » avant qu'on ait le moindre éclat.
	_socket_mesh = MeshInstance3D.new()
	_socket_mesh.name = "Berceau"
	_socket_mesh.mesh = CrystalGrammar.boss_shard_mesh()
	_socket_material = CrystalGrammar.make_material(CrystalGrammar.COLOR_BOSS_LOCK, 0.0)
	_socket_mesh.material_override = _socket_material
	# Même échelle que l'éclat au sol : ce qu'on pose doit être RECONNU comme
	# ce qu'on portait.
	_socket_mesh.scale = Vector3.ONE * 0.55
	_socket_mesh.position = Vector3(0.0, 1.35, 0.0)
	add_child(_socket_mesh)

	_glow = CrystalGrammar.make_glow(CrystalGrammar.COLOR_BOSS_LOCK, 0.0, 8.0)
	_glow.position = Vector3(0.0, 1.6, 0.0)
	add_child(_glow)


## Vide : le berceau n'est qu'un creux sombre. Servi mais hors séquence :
## l'éclat est là, éteint — on voit qu'il ne « prend » pas. Validé : il brille.
##
## Ces trois états sont ce qui permet de résoudre l'énigme par tâtonnement
## plutôt qu'en devinant, et sans qu'aucun texte n'explique la règle.
func _refresh() -> void:
	if _socket_mesh == null:
		return
	_socket_mesh.visible = _filled
	var energy: float = 0.0
	if _filled:
		energy = 3.4 if _validated else 0.35
	if _socket_material != null:
		_socket_material.emission_energy_multiplier = energy
	if _glow != null:
		_glow.light_energy = 2.6 if _validated else (0.4 if _filled else 0.0)
	if _glyph != null:
		_glyph.modulate = CrystalGrammar.COLOR_BOSS_LOCK if _validated \
			else CrystalGrammar.COLOR_BOSS_LOCK.darkened(0.45)
	prompt_text = "Reprendre l'éclat" if _filled else "Placer l'éclat"


## Le contrat attendu d'un porteur d'éclats. On le teste par ses méthodes et
## non par son type : le poteau n'a pas besoin de savoir qu'il parle à un
## PlayerController, seulement que son interlocuteur sait tenir un éclat.
static func _carries_shards(node: Node) -> bool:
	return node != null \
		and node.has_method(&"get_boss_shards") \
		and node.has_method(&"add_boss_shard") \
		and node.has_method(&"take_boss_shard")


func can_interact(by_player: Node) -> bool:
	if not _carries_shards(by_player):
		return false
	if _filled:
		# Reprendre : seulement si le joueur a de la place.
		return int(by_player.call(&"get_boss_shards")) < BossPuzzle.SHARD_COUNT
	return int(by_player.call(&"get_boss_shards")) > 0


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	var player: Node = by_player
	if _filled:
		_filled = false
		_validated = false
		player.add_boss_shard()
		_refresh()
		shard_removed.emit(self, player)
	else:
		_filled = true
		player.take_boss_shard()
		_refresh()
		shard_placed.emit(self, player)
	interaction_completed.emit(player)
	return true


## Appelé par [BossPuzzle] : l'éclat posé ici occupe-t-il le bon rang ?
func set_validated(value: bool) -> void:
	_validated = value
	_refresh()


func is_filled() -> bool:
	return _filled


func is_validated() -> bool:
	return _validated

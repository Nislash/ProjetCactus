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

## Cotes du fût, renseignées par [BossPuzzle] depuis la colonne réelle. Sans
## elles, la gravure était posée sur l'AXE du poteau — c'est-à-dire à
## l'intérieur de la pierre, invisible.
@export var shaft_bottom_radius: float = 2.6
@export var shaft_top_radius: float = 1.7
@export var shaft_height: float = 16.0

## Angle de la gravure autour du fût, en degrés.
##
## Tiré au sort **une fois**, à partir d'une graine fixe : chaque colonne porte
## sa lettre à un endroit différent, donc il faut vraiment en faire le tour —
## mais l'énigme reste la même d'une run à l'autre, ce qui permet de la
## raconter à quelqu'un.
@export var glyph_angle_degrees: float = 0.0

var _filled: bool = false
## Vrai si l'éclat posé ici a bien été placé au bon rang de la séquence.
var _validated: bool = false

var _glyph: MeshInstance3D
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

	_build_glyph()

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


## La gravure, POSÉE SUR LA PAROI et non sur l'axe.
##
## Elle était un `Label3D` en billboard, placé à `(0, h, 0)` — c'est-à-dire au
## centre du fût, donc **enfermée dans la pierre**. Un billboard tourné vers la
## caméra ne pouvait de toute façon pas se lire comme une gravure : il aurait
## flotté devant le poteau.
##
## Elle est maintenant un texte EXTRUDÉ, plaqué sur la surface à un angle tiré
## au sort, orienté vers l'extérieur. C'est de la géométrie posée sur de la
## roche : elle prend la lumière du lieu, elle se cache quand on est du mauvais
## côté, et il faut tourner autour du poteau pour la trouver.
func _build_glyph() -> void:
	var angle: float = deg_to_rad(glyph_angle_degrees)
	var radius: float = _shaft_radius_at(glyph_height)
	var outward := Vector3(sin(angle), 0.0, cos(angle))

	# LE CARTOUCHE. Une dalle sombre encastrée dans le fût, sur laquelle la
	# lettre est gravée. Sans elle, le texte flottait sur la roche brute et se
	# lisait comme un sous-titre ; avec elle, c'est un ouvrage — quelqu'un a
	# taillé cette pierre, et c'est ce qui donne envie de faire le tour.
	var plaque := MeshInstance3D.new()
	plaque.name = "Cartouche"
	var slab := BoxMesh.new()
	slab.size = Vector3(1.9, 2.3, 0.18)
	plaque.mesh = slab
	var stone := StandardMaterial3D.new()
	stone.albedo_color = Color(0.055, 0.085, 0.125)
	stone.roughness = 0.85
	stone.metallic = 0.0
	plaque.material_override = stone
	plaque.position = outward * (radius - 0.02) + Vector3(0.0, glyph_height, 0.0)
	plaque.rotation.y = angle
	add_child(plaque)

	var mesh := TextMesh.new()
	mesh.text = letter
	mesh.font_size = 160
	mesh.pixel_size = 0.011
	# Extrusion faible : une gravure affleure, elle ne saille pas.
	mesh.depth = 0.06
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var glyph := MeshInstance3D.new()
	glyph.name = "Gravure"
	glyph.mesh = mesh
	# Émission basse : DISCRÈTE. Une lettre qui brille autant que le berceau
	# ferait croire qu'elle est le mécanisme, alors qu'elle est l'indice.
	glyph.material_override = CrystalGrammar.make_material(
		CrystalGrammar.COLOR_BOSS_LOCK, 1.1)

	# Posée sur le cartouche, très légèrement en avant pour ne pas z-fighter.
	glyph.position = outward * (radius + 0.08) + Vector3(0.0, glyph_height, 0.0)
	glyph.rotation.y = angle
	add_child(glyph)
	_glyph = glyph


## Rayon du fût à cette hauteur — la colonne est conique.
func _shaft_radius_at(height: float) -> float:
	var t: float = clampf(height / maxf(shaft_height, 0.001), 0.0, 1.0)
	return lerpf(shaft_bottom_radius, shaft_top_radius, t)


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
	if _glyph != null and _glyph.material_override is StandardMaterial3D:
		# La lettre s'affirme quand son rang est pris : c'est la confirmation
		# la plus discrète possible, et elle suffit.
		(_glyph.material_override as StandardMaterial3D).emission_energy_multiplier = \
			3.0 if _validated else 1.1
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

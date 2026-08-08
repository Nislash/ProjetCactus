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

## Police du lettrage — October Crow, tracée à la main (licence libre, cf
## `assets/fonts/october_crow_LICENSE.txt`).
const FONT_PATH := "res://assets/fonts/october_crow.ttf"

## Épaisseur du trait gravé, en mètres.
const GLYPH_DEPTH := 0.05

## Fraction de l'épaisseur laissée sous la surface. Au-delà de 1, la lettre
## disparaît entièrement ; à 0, elle ressort pleine et cesse d'être discrète.
const GLYPH_SINK := 0.42

## Nombre de pans du fût. La colonnade est un PRISME, pas un cylindre : c'est
## ce qui permet de coller la gravure sur une face plane au lieu de la faire
## flotter devant une arête.
const SHAFT_FACES := 9

## Hauteur de la console qui porte l'éclat, en mètres. À portée de main.
const ALTAR_HEIGHT := 1.35

## Dimensions de la niche creusée dans le fût, en mètres.
const NICHE_WIDTH := 1.15
const NICHE_HEIGHT := 1.55

## Nombre d'éclats de roche autour de l'ouverture.
const NICHE_RIM_CHUNKS := 9

## La lettre gravée. Une seule majuscule.
@export var letter: String = "B"

## Hauteur de la gravure sur le fût, en mètres. Tirée au sort par
## [BossPuzzle] : à hauteur constante, les quatre lettres formaient une
## ceinture régulière autour du lac et se cherchaient toutes au même niveau.
@export var glyph_height: float = 3.2

## Hauteur du SOL au-dessus de la base du fût, en mètres.
##
## Les colonnes plongent jusqu'au lit du lac, plusieurs mètres sous la rive.
## Sans cette correction, une gravure « à 2,2 m » était comptée depuis le lit
## et se retrouvait donc **enterrée** sous le sol où marche le joueur — c'est
## ce qui est arrivé au O.
@export var ground_offset: float = 0.0

## Cotes du fût, renseignées par [BossPuzzle] depuis la colonne réelle. Sans
## elles, la gravure était posée sur l'AXE du poteau — c'est-à-dire à
## l'intérieur de la pierre, invisible.
@export var shaft_bottom_radius: float = 2.6
@export var shaft_top_radius: float = 1.7
@export var shaft_height: float = 16.0

## Sur quel pan du fût la gravure est taillée (0 à 8).
##
## Tiré au sort **une fois**, à partir d'une graine fixe : chaque colonne porte
## sa lettre sur un pan différent, donc il faut vraiment en faire le tour —
## mais l'énigme reste la même d'une run à l'autre, ce qui permet de la
## raconter à quelqu'un.
##
## Un pan et non un angle libre : sur un prisme, entre le milieu d'une face et
## une arête il y a 14 cm d'écart de rayon, soit trois fois l'épaisseur de la
## gravure. À angle libre, elle était tantôt enfouie, tantôt décollée.
@export var glyph_face: int = 0

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

	var facing: Vector3 = _face_normal()
	var reach: float = _face_distance(_altar_y())

	# LA NICHE — un trou creusé à même le fût.
	#
	# Une tablette en saillie avait été essayée d'abord : elle se lisait comme
	# du mobilier posé contre la colonne, alors que tout le reste du niveau est
	# taillé dans la masse. Un creux appartient à la pierre.
	#
	# Godot n'a pas de soustraction booléenne, et on ne peut pas non plus
	# « regarder dans » une boîte enfoncée : le fût est opaque et l'occlut
	# toujours (essayé — on ne voyait que de la roche).
	#
	# La cavité est donc PEINTE : un fond noir mat posé à ras de la paroi,
	# entouré d'éclats de roche qui saillent. Le contraste et le relief du
	# pourtour suffisent à l'œil pour lire un creux — c'est ce que font tous
	# les jeux qui n'ont pas de découpe booléenne, et ça coûte deux triangles.

	var cavity := MeshInstance3D.new()
	cavity.name = "Niche"
	var hole := QuadMesh.new()
	hole.size = Vector2(NICHE_WIDTH, NICHE_HEIGHT)
	cavity.mesh = hole
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color(0.008, 0.014, 0.024)
	# Non éclairé : une surface qui répond à la lumière trahit qu'elle est
	# plate. Un fond de cavité reste noir quoi qu'il arrive.
	dark.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	cavity.material_override = dark
	cavity.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	cavity.position = facing * (reach + 0.015) + Vector3(0.0, _altar_y(), 0.0)
	cavity.rotation.y = _face_angle()
	add_child(cavity)

	# L'OURLET DE ROCHE. Quelques éclats irréguliers autour de l'ouverture :
	# c'est ce qui fait que le trou a été CREUSÉ et non découpé. Tailles et
	# inclinaisons varient avec la lettre, pour que deux colonnes ne portent
	# pas le même encadrement.
	var rim_rng := RandomNumberGenerator.new()
	rim_rng.seed = hash(letter) + glyph_face * 977
	var rim_material := StandardMaterial3D.new()
	rim_material.albedo_color = Color(0.070, 0.098, 0.140)
	rim_material.roughness = 0.95
	for i in NICHE_RIM_CHUNKS:
		var a: float = TAU * (float(i) + rim_rng.randf_range(-0.18, 0.18)) \
			/ float(NICHE_RIM_CHUNKS)
		var chunk := MeshInstance3D.new()
		chunk.name = "Ourlet_%d" % i
		var block := BoxMesh.new()
		var scale: float = rim_rng.randf_range(0.16, 0.34)
		block.size = Vector3(scale, scale * rim_rng.randf_range(0.7, 1.6), scale * 0.8)
		chunk.mesh = block
		chunk.material_override = rim_material
		# Sur l'ellipse du contour, avec un peu de désordre : un anneau régulier
		# ferait joint de fenêtre.
		var local := Vector3(
			cos(a) * (NICHE_WIDTH * 0.5 + rim_rng.randf_range(0.02, 0.12)),
			sin(a) * (NICHE_HEIGHT * 0.5 + rim_rng.randf_range(0.02, 0.12)),
			rim_rng.randf_range(0.02, 0.14))
		chunk.position = facing * reach + Vector3(0.0, _altar_y(), 0.0) \
			+ Basis(Vector3.UP, _face_angle()) * local
		chunk.rotation = Vector3(
			rim_rng.randf_range(-0.5, 0.5),
			_face_angle() + rim_rng.randf_range(-0.6, 0.6),
			rim_rng.randf_range(-0.5, 0.5))
		add_child(chunk)

	# L'AUTEL. Un cristal RETOURNÉ, pointe en bas, suspendu DANS la niche —
	# l'empreinte en creux de l'éclat qui doit venir s'y loger.
	#
	# Il est TOUJOURS visible, même vide. C'est tout l'intérêt : sans lui, rien
	# n'indiquait où poser, et le joueur qui portait ses éclats devait deviner
	# que ces colonnes-là les acceptaient. Une forme en creux dit « il manque
	# quelque chose ici » sans un mot.
	var altar := MeshInstance3D.new()
	altar.name = "Autel"
	altar.mesh = CrystalGrammar.boss_shard_mesh()
	altar.scale = Vector3(0.42, -0.42, 0.42)
	var hollow := StandardMaterial3D.new()
	hollow.albedo_color = Color(0.045, 0.070, 0.100)
	hollow.roughness = 0.9
	hollow.metallic = 0.0
	altar.material_override = hollow
	# Suspendu depuis le haut de la niche : renversé, le mesh descend depuis
	# son origine.
	# Devant le fond noir : c'est ce détachement qui donne la profondeur.
	altar.position = facing * (reach + 0.30) \
		+ Vector3(0.0, _altar_y() + NICHE_HEIGHT * 0.44, 0.0)
	add_child(altar)

	# L'éclat posé, qui vient combler l'empreinte.
	_socket_mesh = MeshInstance3D.new()
	_socket_mesh.name = "Berceau"
	_socket_mesh.mesh = CrystalGrammar.boss_shard_mesh()
	_socket_material = CrystalGrammar.make_material(CrystalGrammar.COLOR_BOSS_LOCK, 0.0)
	_socket_mesh.material_override = _socket_material
	# Même échelle que l'éclat au sol : ce qu'on pose doit être RECONNU comme
	# ce qu'on portait. Posé pointe en haut, il comble l'empreinte inversée.
	_socket_mesh.scale = Vector3.ONE * 0.42
	# Logé dans la niche, pointe en haut : il vient combler l'empreinte.
	_socket_mesh.position = facing * (reach + 0.30) \
		+ Vector3(0.0, _altar_y() - NICHE_HEIGHT * 0.42, 0.0)
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
## Elle est maintenant un texte EXTRUDÉ, plaqué **à même la roche** à un angle
## tiré au sort. Pas de cartouche, pas de dalle : une plaque encadrée aurait
## crié « objet de jeu ici » et donné la réponse avant la question. C'est une
## énigme — la lettre doit être trouvée, pas signalée.
##
## Elle est GRAVÉE EN CREUX : le glyphe est enfoncé dans le fût, si bien que
## seules ses arêtes affleurent. On ne lit donc pas une lettre pleine mais un
## **tracé au trait**, comme une marque faite au burin — beaucoup plus discret,
## et impossible à confondre avec un élément d'interface.
##
## Elle est invisible du mauvais côté du fût. Ce qu'on cherche, on le cherche.
func _build_glyph() -> void:
	var mesh := TextMesh.new()
	mesh.text = letter
	# La police du jeu : lettrage tracé à la main, irrégulier. Une grotesque
	# propre se serait lue comme une signalétique ; celle-ci passe pour une
	# marque laissée par quelqu'un.
	var face: Font = load(FONT_PATH) as Font
	if face != null:
		mesh.font = face
	mesh.font_size = 220
	mesh.pixel_size = 0.010
	# L'extrusion donne son épaisseur au trait : c'est elle qu'on voit, puisque
	# la face avant reste dans la pierre.
	mesh.depth = GLYPH_DEPTH
	mesh.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	mesh.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var glyph := MeshInstance3D.new()
	glyph.name = "Gravure"
	glyph.mesh = mesh
	# Assez pour distinguer la lettre en s'approchant, trop faible pour
	# l'apercevoir de l'autre rive : sinon les quatre lettres se liraient d'un
	# seul point de vue et le tour du lac ne servirait à rien.
	#
	# L'albedo est éclairci séparément de l'émission. Avec le matériau commun
	# (corps sombre, émission forte), seuls les BORDS du texte accrochaient la
	# lumière : la lettre se lisait comme un artefact de rendu plutôt que comme
	# une gravure.
	var ink := StandardMaterial3D.new()
	ink.albedo_color = CrystalGrammar.COLOR_BOSS_LOCK.darkened(0.45)
	ink.emission_enabled = true
	ink.emission = CrystalGrammar.COLOR_BOSS_LOCK
	ink.emission_energy_multiplier = 1.3
	ink.roughness = 0.55
	# Culling désactivé : selon le sens d'extrusion du TextMesh, la face avant
	# du glyphe peut regarder à l'opposé de la caméra. On ne voyait alors que
	# les tranches latérales — un contour filaire, pas une lettre.
	ink.cull_mode = BaseMaterial3D.CULL_DISABLED
	glyph.material_override = ink

	# ENFONCÉ, volontairement. Le glyphe est reculé d'une fraction de son
	# épaisseur : sa face avant reste sous la surface, seules les arêtes
	# ressortent. Sorti complètement, on obtiendrait une lettre pleine et
	# lumineuse — lisible de partout, donc plus une énigme.
	var glyph_y: float = ground_offset + glyph_height
	glyph.position = _face_normal() * (_face_distance(glyph_y) - GLYPH_DEPTH * GLYPH_SINK) \
		+ Vector3(0.0, glyph_y, 0.0)
	glyph.rotation.y = _face_angle()
	add_child(glyph)
	_glyph = glyph


## Altitude de la niche, comptée DEPUIS LE SOL et non depuis la base du fût.
func _altar_y() -> float:
	return ground_offset + ALTAR_HEIGHT


## L'angle du milieu du pan choisi. Décalé d'un demi-pas pour viser le centre
## de la face et non son arête.
func _face_angle() -> float:
	return TAU * (float(glyph_face % SHAFT_FACES) + 0.5) / float(SHAFT_FACES)


func _face_normal() -> Vector3:
	var a: float = _face_angle()
	return Vector3(sin(a), 0.0, cos(a))


## Distance de l'axe au MILIEU d'une face, à cette hauteur. C'est elle qui
## compte pour poser quelque chose à plat, et non le rayon circonscrit — qui
## ne vaut que sur les arêtes.
func _face_distance(height: float) -> float:
	return _shaft_radius_at(height) * cos(PI / float(SHAFT_FACES))


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
			3.4 if _validated else 1.3
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

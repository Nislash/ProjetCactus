class_name MoonPuzzle
extends Node

## Le puzzle du niveau 2 : conduire la lumière de la lune rouge jusqu'au sceau
## du château.
##
## ## La règle
##
## La lune éclaire le **premier** miroir — celui qui est en vue dégagée sur la
## crête. Chaque miroir touché renvoie son rayon selon la loi de la réflexion.
## Quand un rayon atteint le sceau de la porte, la coulée fige et la porte
## s'ouvre.
##
## ## Ce qui fait que ça se comprend sans un mot
##
## Le rayon est visible sur toute sa longueur, et il **s'arrête là où il
## bute**. Un joueur qui tourne un miroir voit immédiatement l'effet : le trait
## balaie la falaise. Il n'y a pas d'indice à trouver, seulement une
## trajectoire à lire — et personne n'a besoin qu'on lui explique comment se
## comporte un miroir.
##
## ## Pourquoi la chaîne est recalculée entièrement à chaque coup
##
## Trois miroirs, un rayon chacun : le coût est nul, et une mise à jour
## incrémentale aurait introduit des états faux dès qu'on tourne un miroir
## situé en amont d'un autre. Recalculer tout est ici à la fois plus simple et
## plus juste.

signal solved()
signal beam_progress(mirrors_lit: int, total: int)

## Couche du décor. Le rayon s'arrête dessus — c'est ce qui manquait à la
## première version, qui traversait les falaises.
const WORLD_LAYER: int = 1

## Tolérance de visée, en mètres. Volontairement large : viser au degré près à
## la manette serait une épreuve d'adresse, pas une énigme. Elle doit aussi
## rester cohérente avec le pas des crans — à 30 m, 7 m couvrent 13°, soit
## presque la moitié d'un cran de réflexion.
@export var target_radius: float = 7.0

## Portée d'un segment de rayon.
@export var segment_length: float = 90.0

var _mirrors: Array[MoonMirror] = []
var _castle: ForgeCastle
var _lighting: ForgeLighting
var _solved: bool = false


func setup(mirrors: Array[MoonMirror], castle: ForgeCastle, lighting: ForgeLighting) -> void:
	_mirrors = mirrors
	_castle = castle
	_lighting = lighting
	for m in _mirrors:
		m.aimed.connect(_on_mirror_aimed)
	_recompute()


func _on_mirror_aimed(_mirror: MoonMirror) -> void:
	_recompute()


## Suit le rayon de miroir en miroir, **par de vrais raycasts physiques**.
##
## La première version calculait des distances à un axe : elle ignorait donc
## le décor. Un rayon traversait une falaise pour atteindre un miroir situé
## derrière, et le joueur voyait un trait s'arrêter contre la roche pendant que
## la logique, elle, continuait — d'où un comportement qui paraissait
## arbitraire.
##
## Maintenant chaque segment est un `intersect_ray` sur le décor ET sur les
## surfaces optiques. Ce que le rayon rencontre EN PREMIER décide de la suite :
## un miroir le renvoie, le sceau ouvre la porte, la roche l'arrête. Le trait
## affiché est celui qui a été lancé — les deux ne peuvent plus diverger.
func _recompute() -> void:
	if _mirrors.is_empty():
		return

	for m in _mirrors:
		m.set_incoming(Vector3.ZERO, false)

	var space: PhysicsDirectSpaceState3D = _mirrors[0].get_world_3d().direct_space_state
	# La lune arrive de biais et vers le bas ; le premier miroir la redresse.
	var direction: Vector3 = _moon_direction()
	var current: MoonMirror = _mirrors[0]
	var lit: int = 0
	var visited: Array[MoonMirror] = []

	# Bornée : deux miroirs qui se renverraient l'un l'autre feraient une
	# boucle infinie, et c'est une configuration que le joueur trouvera en
	# cinq minutes.
	for _hop in _mirrors.size() + 2:
		if current == null or visited.has(current):
			break
		visited.append(current)
		current.set_incoming(direction, true)
		# D'où vient la lumière. Sur le premier miroir c'est la lune elle-même,
		# tracée jusqu'au ciel ; sur les suivants, le miroir d'avant.
		current.draw_incoming(direction, 60.0 if lit == 0 else 8.0)
		lit += 1

		var origin: Vector3 = current.get_focus()
		var reflected: Vector3 = current.get_reflection()
		if reflected.length_squared() < 0.0001:
			break

		var query := PhysicsRayQueryParameters3D.create(
			origin + reflected * 1.6, origin + reflected * segment_length)
		# Décor ET optiques. Le décor arrête ; les optiques renvoient ou
		# ouvrent.
		query.collision_mask = WORLD_LAYER | MoonMirror.OPTICS_LAYER
		var hit: Dictionary = space.intersect_ray(query)

		if hit.is_empty():
			# Rien devant : le rayon part à l'infini.
			current.draw_segment(reflected, segment_length)
			break

		var distance: float = origin.distance_to(hit["position"])
		current.draw_segment(reflected, distance)

		var collider: Node = hit.get("collider") as Node
		var next: MoonMirror = _mirror_of(collider)
		if next != null:
			direction = reflected
			current = next
			continue

		if _is_gate_target(collider):
			_solve()
		break

	beam_progress.emit(lit, _mirrors.size())


## Le miroir auquel appartient un collider touché. On remonte les parents :
## la surface optique est un enfant du miroir.
func _mirror_of(collider: Node) -> MoonMirror:
	var node: Node = collider
	while node != null:
		var mirror: MoonMirror = node as MoonMirror
		if mirror != null:
			return mirror
		node = node.get_parent()
	return null


func _is_gate_target(collider: Node) -> bool:
	if _castle == null or _castle.is_open():
		return false
	var node: Node = collider
	while node != null:
		if node == _castle:
			return true
		node = node.get_parent()
	return false


## D'où vient la lune. Une seule source de vérité : si l'éclairage change son
## azimut, le puzzle suit sans qu'on y touche.
func _moon_direction() -> Vector3:
	if _lighting != null and _lighting.has_method("get_moon_direction"):
		return (_lighting.get_moon_direction() as Vector3).normalized()
	return Vector3(0.0, -0.34, -0.94).normalized()


func _solve() -> void:
	if _solved:
		return
	_solved = true
	if _castle != null:
		_castle.open_gate()
	solved.emit()
	print("[MoonPuzzle] le rayon atteint le sceau — la porte cède.")


func is_solved() -> bool:
	return _solved


func get_mirrors() -> Array[MoonMirror]:
	return _mirrors

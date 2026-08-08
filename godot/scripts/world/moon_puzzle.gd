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


## Suit le rayon de miroir en miroir. Le premier reçoit la lune ; chacun des
## suivants ne s'allume que s'il est effectivement touché.
func _recompute() -> void:
	if _mirrors.is_empty():
		return

	# Tous éteints, puis on rallume ce que le rayon atteint réellement. Sans ce
	# reset, un miroir resté allumé d'un coup précédent continuerait d'émettre
	# dans le vide.
	for m in _mirrors:
		m.set_incoming(Vector3.ZERO, false)

	# La lune arrive de biais et vers le bas ; le premier miroir la redresse.
	var direction: Vector3 = _moon_direction()
	var current: MoonMirror = _mirrors[0]
	var lit: int = 0
	var visited: Array[MoonMirror] = []

	# Bornée au nombre de miroirs : deux miroirs qui se renvoient l'un l'autre
	# feraient sinon une boucle infinie, et c'est une configuration que le
	# joueur trouvera en cinq minutes.
	for _hop in _mirrors.size() + 1:
		if current == null or visited.has(current):
			break
		visited.append(current)
		current.set_incoming(direction, true)
		lit += 1

		var origin: Vector3 = current.get_focus()
		var reflected: Vector3 = current.get_reflection()
		if reflected.length_squared() < 0.0001:
			break

		# Le sceau d'abord : s'il est sur la trajectoire, c'est gagné, même si
		# un miroir se trouve plus loin dans le même axe.
		if _castle != null and not _castle.is_open():
			if _hits_target(origin, reflected, _castle.get_gate_target()):
				_solve()
				break

		var next: MoonMirror = _first_mirror_along(origin, reflected, visited)
		if next == null:
			break
		direction = reflected
		current = next

	beam_progress.emit(lit, _mirrors.size())


## D'où vient la lune. Une seule source de vérité : si l'éclairage change son
## azimut, le puzzle suit sans qu'on y touche.
func _moon_direction() -> Vector3:
	if _lighting != null and _lighting.has_method("get_moon_direction"):
		return (_lighting.get_moon_direction() as Vector3).normalized()
	return Vector3(0.0, -0.34, -0.94).normalized()


## Le premier miroir rencontré le long du rayon, dans la tolérance de visée.
func _first_mirror_along(origin: Vector3, direction: Vector3,
		visited: Array[MoonMirror]) -> MoonMirror:
	var best: MoonMirror = null
	var best_distance: float = INF
	for m in _mirrors:
		if visited.has(m):
			continue
		var to_mirror: Vector3 = m.get_focus() - origin
		var along: float = to_mirror.dot(direction)
		if along <= 1.0 or along > segment_length:
			continue
		# Distance HORIZONTALE à l'axe : les miroirs renvoient à plat (cf
		# `MoonMirror.get_reflection`), donc comparer en trois dimensions
		# ferait rater toute cible qui n'est pas exactement à la même hauteur.
		var offset: float = _flat(to_mirror - direction * along).length()
		if offset > target_radius:
			continue
		if along < best_distance:
			best_distance = along
			best = m
	return best


func _hits_target(origin: Vector3, direction: Vector3, target: Vector3) -> bool:
	var to_target: Vector3 = target - origin
	var along: float = to_target.dot(direction)
	if along <= 1.0 or along > segment_length:
		return false
	# Horizontale, pour la même raison : le sceau est à sept mètres du sol et
	# le rayon voyage à hauteur de miroir.
	return _flat(to_target - direction * along).length() <= target_radius


func _flat(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


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

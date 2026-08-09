class_name LavaHazard
extends Area3D

## La lave tue.
##
## ## Pourquoi ce n'est pas juste « beaucoup de dégâts »
##
## Une mort instantanée dans une rivière de lave laisserait le corps AU FOND de
## la rivière. Le jeu relève les alliés à terre en maintenant `Interact` à leur
## contact (cf `CLAUDE.md`, « Down + revive ») : un joueur tombé dans la coulée
## serait donc irrécupérable, et à quatre joueurs ça transforme une erreur de
## saut en joueur éliminé pour la run.
##
## D'où l'ordre des opérations : on ÉJECTE d'abord sur la berge la plus proche,
## on inflige la mort ensuite. Le joueur meurt bien — c'est ce qu'on veut qu'il
## comprenne — mais son corps reste atteignable. C'est la même logique que la
## lave des jeux de plateforme : elle punit, elle ne supprime pas la partie.
##
## ## Ce qu'elle touche
##
## Tout ce qui a un [HealthComponent] : joueurs ET ennemis. Un ennemi qui
## poursuit un joueur sur le pont et rate son virage doit brûler comme lui.
## L'asymétrie serait immédiatement lisible, et injuste dans le mauvais sens.

signal burned(victim: Node3D)

## De combien la zone dangereuse dépasse la surface, vers le haut.
##
## Le collider de la nappe s'arrête à la surface ; un joueur qui la touche a ses
## pieds AU niveau, pas dedans. Sans cette marge, on peut courir sur la lave
## sans jamais déclencher la zone.
@export var surface_margin: float = 1.2

## Profondeur de la zone sous la surface.
@export var depth: float = 12.0

## Marge d'éjection au-delà du bord de la coulée, en mètres. Assez pour que le
## corps ne retombe pas dedans, assez peu pour qu'il reste au bord — un allié
## doit voir où aller.
@export var eject_margin: float = 3.5

var _lake: CavernLake
var _terrain: CavernTerrainData
var _noise: FastNoiseLite
## Les victimes déjà traitées. Sans ça, la zone re-tue à chaque frame un corps
## qui n'a pas fini de s'éjecter, et le signal part vingt fois.
var _burning: Dictionary = {}


func setup(terrain: CavernTerrainData) -> void:
	_terrain = terrain
	_lake = terrain.lake
	if _lake == null:
		push_warning("LavaHazard : aucune nappe — la lave ne tuera personne.")
		return
	_noise = CavernTerrainBuilder.make_noise(terrain.floor_field)

	# On surveille les corps, on n'en est pas un : la zone ne doit rien pousser.
	monitoring = true
	monitorable = false
	collision_layer = 0
	# Joueurs et ennemis vivent sur les couches de personnages ; le décor ne
	# nous intéresse pas.
	collision_mask = 0xFFFFFFFF

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(_lake.radii.x * 2.0, depth + surface_margin, _lake.radii.y * 2.0)
	shape.shape = box
	add_child(shape)
	global_position = Vector3(
		_lake.center.x,
		_lake.surface_altitude + surface_margin - (depth + surface_margin) * 0.5,
		_lake.center.y)


func _physics_process(_delta: float) -> void:
	if _lake == null:
		return
	for body in get_overlapping_bodies():
		_touch(body)


func _touch(body: Node3D) -> void:
	if body == null or _burning.has(body):
		return
	var health: HealthComponent = _health_of(body)
	if health == null or health.is_dead:
		return

	# La boîte de la zone est un pavé ; la coulée est une ellipse. Sans ce
	# second contrôle, on brûlerait aux quatre coins du pavé, c'est-à-dire sur
	# la roche sèche.
	if not _inside_lava(Vector2(body.global_position.x, body.global_position.z)):
		return

	_burning[body] = true
	_eject(body)
	# La brûlure AVANT la mort : elle ne changera rien à l'issue, mais elle
	# habille le coup — l'écran vire au rouge et le son part, donc on comprend
	# de quoi on est mort plutôt que de voir sa barre tomber d'un coup.
	health.apply_burn(2.0, 10.0, self)
	health.take_damage(health.max_health * 10, self)
	burned.emit(body)
	# Rendu réarmable : un joueur relevé qui retombe dedans doit rebrûler.
	get_tree().create_timer(1.5).timeout.connect(func() -> void:
		_burning.erase(body))


## Repousse le corps hors de la coulée, sur la berge la plus proche.
##
## On sort PERPENDICULAIREMENT au lit, pas vers le centre de l'ellipse : sur une
## rivière longue et étroite, viser le centre renverrait quelqu'un tombé au
## milieu à trente mètres en amont au lieu de le poser sur la rive d'en face.
func _eject(body: Node3D) -> void:
	var at := Vector2(body.global_position.x, body.global_position.z)
	var local: Vector2 = at - _lake.center
	var side: float = signf(local.y)
	if is_zero_approx(side):
		side = 1.0
	var bank_y: float = _lake.center.y + side * (_lake.radii.y + eject_margin)
	var landing := Vector2(clampf(at.x, _lake.center.x - _lake.radii.x + 4.0,
		_lake.center.x + _lake.radii.x - 4.0), bank_y)

	var altitude: float = CavernTerrainBuilder.ground_at(_terrain, landing, _noise) + 1.2
	body.global_position = Vector3(landing.x, altitude, landing.y)
	var character: CharacterBody3D = body as CharacterBody3D
	if character != null:
		character.velocity = Vector3.ZERO


func _inside_lava(at: Vector2) -> bool:
	var local: Vector2 = at - _lake.center
	return Vector2(local.x / maxf(_lake.radii.x, 0.001),
		local.y / maxf(_lake.radii.y, 0.001)).length() <= 1.0


## Le [HealthComponent] d'un corps, quel que soit son nom de nœud. On passe par
## `get_health()` quand il existe — le joueur l'expose — et on retombe sur une
## recherche d'enfant pour les ennemis, qui ne partagent pas son interface.
func _health_of(body: Node) -> HealthComponent:
	if body.has_method("get_health"):
		return body.call("get_health") as HealthComponent
	for child in body.get_children():
		var health: HealthComponent = child as HealthComponent
		if health != null:
			return health
	return null

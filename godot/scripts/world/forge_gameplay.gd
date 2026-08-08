class_name ForgeGameplay
extends Node

## Câble la boucle de jeu de la Forge (niveau 2).
##
## Même principe qu'au niveau 1 : la scène ne contient que des **marqueurs**,
## tout ce qui vit est instancié ici, après que le terrain a été généré et que
## les marqueurs ont été recalés au sol. C'est ce qui permet de retoucher la
## topographie sans repositionner quoi que ce soit à la main.
##
## ## Ce qui diffère du niveau 1
##
## **Un autre verbe.** La Caverne demande de *rassembler* — quatre éclats,
## quatre serrures, un mot à reconstituer. La Forge demande d'*orienter* :
## trois miroirs de basalte à faire pivoter pour conduire la lumière de la
## lune rouge jusqu'au sceau du château. Deux niveaux qui demanderaient la
## même chose au joueur ne seraient qu'un seul niveau joué deux fois.
##
## **Et la solution est visible.** Le rayon se voit sur toute sa longueur et
## s'arrête là où il bute : il n'y a rien à deviner, seulement une trajectoire
## à lire. Personne n'a besoin qu'on lui explique comment se comporte un
## miroir.
##
## Le danger n'est plus signalé par la couleur — toute la salle est ambre — mais
## par le **mouvement** : la lave qui monte pendant le combat, et qui reprend
## un anneau à chaque phase du boss.

const BOSS_SCENE := "res://scenes/boss/boss_golem.tscn"

## Si faux, le boss n'est pas instancié (utile pour visiter).
@export var spawn_boss: bool = true

## Rayon de la laisse d'arène. L'arène du Golem fait 34 m de demi-grand axe :
## la laisse la couvre sans déborder dans le tunnel, sinon le boss suivrait
## un fuyard jusqu'au cirque.
@export var boss_leash_radius: float = 32.0

## Rayon de la zone d'éveil, en mètres. NETTEMENT plus petit que la laisse.
##
## Les deux étaient confondus, et le boss se réveillait donc dès qu'on entrait
## dans son rayon de poursuite — soit, dans la version précédente, avant même
## d'avoir fini de descendre le cirque. Il faut pénétrer dans l'arène pour le
## réveiller ; il peut ensuite y poursuivre plus loin qu'on ne l'a réveillé.
@export var boss_wake_radius: float = 18.0

signal boss_awakened()

## Où poser les trois miroirs, en (X, Z).
##
## Le premier est sur la crête, en vue dégagée : c'est lui que la lune touche,
## et il doit être la première chose qu'on croise en arrivant. Les deux autres
## descendent vers le château — le rayon suit donc le chemin du joueur, ce qui
## fait de la trajectoire une carte.
## Les distances comptent autant que les positions : plus une cible est loin,
## plus la tolérance angulaire se resserre, et plus le puzzle devient un
## exercice d'adresse. Les sauts font ici entre vingt et trente mètres.
const MIRROR_SPOTS: Array[Vector2] = [
	Vector2(-26.0, 34.0),
	Vector2(30.0, 22.0),
	Vector2(22.0, -2.0),
]

var _world: Node3D
var _boss: Node3D
var _castle: ForgeCastle
var _bridge: ForgeBridge
var _puzzle: MoonPuzzle

## Où se cache le levier : derrière le rideau de la cascade amont, sur la rive
## nord. Assez loin du bord pour qu'on ne l'aperçoive pas depuis la corniche —
## il faut sauter pour le découvrir.
## Le chiffre est CONTRAINT, pas choisi : la corniche s'arrête à X = -42, le
## palier commence à -61+9 = -52-9 = -61… et l'écart entre les deux est le saut.
## Cinq mètres au-dessus de la coulée : franchissable d'un élan, impossible par
## mégarde. Déplacer l'un des deux sans l'autre casse le niveau en silence,
## d'où le test qui mesure cet écart.
const LEVER_SPOT := Vector2(-72.0, -5.0)

## Longueur du pylône. Elle doit franchir l'intervalle entre le palier et la
## corniche : c'est ce chiffre, et lui seul, qui décide si le retour existe.
const PYLON_SPAN: float = 24.0


func _ready() -> void:
	_world = get_parent() as Node3D
	if _world == null:
		push_error("ForgeGameplay : doit être enfant du nœud World.")
		return

	# Deux frames : le terrain se construit, puis le snapper recale les
	# marqueurs. Instancier avant reviendrait à poser les objets dans le vide.
	await get_tree().process_frame
	await get_tree().process_frame

	_build_castle()
	_build_bridge()
	_build_lava_hazard()
	_build_lava_falls()
	_build_twist_chain()
	_build_moon_puzzle()

	if spawn_boss:
		_spawn_boss()


func _spawn_boss() -> void:
	var marker: Node3D = _world.get_node_or_null("BossArena/BossSpawn") as Node3D
	if marker == null:
		push_warning("ForgeGameplay : BossSpawn introuvable — pas de boss.")
		return
	var packed: PackedScene = load(BOSS_SCENE) as PackedScene
	if packed == null:
		push_error("ForgeGameplay : %s introuvable." % BOSS_SCENE)
		return

	_boss = packed.instantiate() as Node3D
	_boss.name = "BossGolem"
	_world.add_child(_boss)
	_boss.global_position = marker.global_transform.origin

	var ai: Node = _boss.get_node_or_null("BossAI")
	if ai != null and ai.has_method("set_arena"):
		ai.call("set_arena", _boss.global_position, boss_leash_radius)

	_build_arena_lock()
	print("[ForgeGameplay] boss posé en %v." % _boss.global_position)


## La zone d'éveil. Le niveau 1 n'en avait pas et son boss dormait
## indéfiniment sans que rien ne le signale — on ne refait pas l'erreur.
func _build_arena_lock() -> void:
	var zone := Area3D.new()
	zone.name = "ReveilDuGolem"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = boss_wake_radius
	shape.shape = sphere
	zone.add_child(shape)
	_world.add_child(zone)
	zone.global_position = _boss.global_position

	zone.body_entered.connect(func(body: Node) -> void:
		if not (body is PlayerController):
			return
		if _boss.has_method("is_engaged") and bool(_boss.call("is_engaged")):
			return
		if _boss.has_method("engage"):
			_boss.call("engage")
			boss_awakened.emit()
			print("[ForgeGameplay] le Golem s'éveille dans la Forge."))


func get_boss() -> Node3D:
	return _boss


# ---------------------------------------------------------------------------
# Le château et son verrou
# ---------------------------------------------------------------------------

## LA LAVE TUE. Une coulée décorative apprend au joueur qu'il peut la traverser,
## et tout le pont ne sert plus à rien.
func _build_lava_hazard() -> void:
	var terrain: CavernTerrainData = load(
		"res://data/levels/level02_forge_terrain.tres") as CavernTerrainData
	if terrain == null:
		push_warning("ForgeGameplay : terrain introuvable — la lave sera inoffensive.")
		return
	var hazard := LavaHazard.new()
	hazard.name = "LaveMortelle"
	_world.add_child(hazard)
	hazard.setup(terrain)


## LES DEUX CHUTES. Elles donnent à la coulée un amont et un aval, donc un sens
## de lecture — et le même que celui du courant dans le shader.
func _build_lava_falls() -> void:
	var terrain: CavernTerrainData = load(
		"res://data/levels/level02_forge_terrain.tres") as CavernTerrainData
	if terrain == null or terrain.lake == null:
		push_warning("ForgeGameplay : pas de nappe — pas de cascades.")
		return
	var lava: CavernLake = terrain.lake

	# AMONT, à l'ouest : la cascade qui arrive de la montagne. Elle porte le
	# contrefort, parce que c'est elle qui a besoin d'une paroi d'où tomber.
	var source := LavaFall.new()
	source.name = "CascadeAmont"
	source.at = Vector2(lava.center.x - lava.radii.x, lava.center.y)
	# Le sommet du rempart, et non plus 21 m : la lave doit déborder DU HAUT de
	# la montagne, comme un cratère qui déverse.
	source.top_altitude = 34.0
	source.bottom_altitude = lava.surface_altitude
	source.width = 15.0
	source.facing = Vector2(1.0, 0.0)
	source.buttress = true
	_world.add_child(source)

	# AVAL, à l'est : la nappe s'arrête au bord de son ellipse alors que la
	# roche, elle, continue de descendre. Ce décrochement EST la lèvre — rien à
	# bâtir, seulement un rideau à y accrocher.
	var sink := LavaFall.new()
	sink.name = "CascadeAval"
	sink.at = Vector2(lava.center.x + lava.radii.x, lava.center.y)
	# Le rideau démarre AU-DESSUS de la nappe, pour masquer par l'avant la
	# silhouette en escalier de son bord.
	sink.top_altitude = lava.surface_altitude + 1.4
	sink.bottom_altitude = -4.0
	# PLUS LARGE que le lit (16 m) : la nappe principale s'arrête sur la limite
	# de son ellipse, quantifiée sur la grille de quads, et cette limite se
	# termine en escalier au-dessus du vide. Le rideau doit la couvrir, pas
	# l'effleurer.
	sink.width = 26.0
	sink.facing = Vector2(1.0, 0.0)
	# Le bassin qui couvre le relief en marches au pied de la chute.
	sink.pool_radius = 26.0
	sink.pool_stretch = 2.6
	_world.add_child(sink)


## LA CHAÎNE DU DÉTOUR : levier derrière la cascade, rampe autour du donjon,
## pylône qu'on abat pour rentrer.
##
## Les trois objets sont posés ensemble parce qu'ils ne veulent rien dire
## séparément : le levier ouvre une rampe qu'on ne peut pas encore atteindre, et
## le pylône n'est un chemin que pour revenir de là où le levier se trouve.
func _build_twist_chain() -> void:
	var terrain: CavernTerrainData = load(
		"res://data/levels/level02_forge_terrain.tres") as CavernTerrainData
	if terrain == null or _castle == null:
		push_warning("ForgeGameplay : pas de terrain ou de château — pas de détour.")
		return
	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)
	var lava: CavernLake = terrain.lake

	# LE PALIER DERRIÈRE LA CASCADE, côté aval du rideau. On y arrive en
	# sautant depuis la corniche : c'est le seul saut obligatoire du niveau, et
	# il se fait au-dessus de la coulée, donc il se réfléchit.
	var ledge_at := Vector2(LEVER_SPOT.x, LEVER_SPOT.y)
	var ledge_altitude: float = maxf(
		CavernTerrainBuilder.sample_point(terrain.floor_field, ledge_at, noise),
		lava.surface_altitude + 1.4)
	var ledge := ForgeLedge.new()
	ledge.name = "PalierDeLaCascade"
	ledge.centre = ledge_at
	ledge.altitude = ledge_altitude
	# 9,5 et non 8 : la brèche mouille la berge de X = -66 à -58, et le palier
	# doit s'avancer assez pour que l'écart tombe à cinq mètres et demi. C'est
	# ce chiffre-là que le test surveille, pas la taille du palier.
	ledge.half_extent = Vector2(9.5, 6.0)
	_world.add_child(ledge)

	var lever := ForgeLever.new()
	lever.name = "LevierCache"
	_world.add_child(lever)
	lever.global_position = Vector3(ledge_at.x, ledge_altitude, ledge_at.y)

	# LA RAMPE. Le donjon est un cylindre : son rayon vaut `keep_width * 0.52`,
	# et on s'enroule juste au-delà.
	# TOUTES ses cotes AVANT `add_child`.
	#
	# `add_child` déclenche `_ready`, donc la construction : régler les
	# propriétés après revenait à bâtir la rampe avec ses valeurs par défaut.
	# Elle s'enroulait autour de l'origine du monde, à quarante-cinq mètres du
	# château, et le navmesh la cuisait consciencieusement là où elle ne servait
	# à rien.
	var ramp := KeepSpiralRamp.new()
	ramp.name = "RampeDuDonjon"
	ramp.keep_centre = Vector3(_castle.footprint_center.x,
		_castle.get_threshold_altitude(), _castle.footprint_center.y)
	ramp.keep_radius = _castle.keep_width * 0.52 + 1.2
	ramp.bottom_altitude = _castle.get_threshold_altitude()
	ramp.top_altitude = _castle.get_threshold_altitude() + _castle.keep_height * 0.92
	ramp.descent_target = Vector3(0.0,
		CavernTerrainBuilder.sample_point(terrain.floor_field, Vector2(0.0, -66.0), noise) + 1.0,
		-66.0)
	_world.add_child(ramp)

	# LE PYLÔNE, sur le palier, orienté vers la corniche : il tombe en travers
	# de la coulée, donc du côté d'où l'on est venu.
	var pylon := FragilePylon.new()
	pylon.name = "PyloneFragile"
	pylon.fall_direction = Vector2(1.0, 0.0)
	pylon.height = PYLON_SPAN
	pylon.deck_altitude = lava.surface_altitude + 1.0
	_world.add_child(pylon)
	pylon.global_position = Vector3(ledge_at.x + 6.0, ledge_altitude, ledge_at.y)

	lever.pulled.connect(func() -> void: ramp.deploy())


func _build_castle() -> void:
	_castle = ForgeCastle.new()
	_castle.name = "Chateau"
	# Reculé derrière les douves : c'est le pont qui l'atteint, plus le sol.
	_castle.footprint_center = Vector2(0.0, -46.0)
	_world.add_child(_castle)


## LE PONT. Il manquait, et son absence rendait le puzzle absurde : la porte
## s'ouvrait sur un château qu'aucun chemin n'atteignait.
func _build_bridge() -> void:
	_bridge = ForgeBridge.new()
	_bridge.name = "PontSuspendu"
	_bridge.from_point = Vector2(0.0, 6.0)
	# Il accoste le BORD de la terrasse, pas un point choisi à l'œil : sinon
	# ses derniers segments s'enfoncent dans la dalle et le joueur bute.
	_bridge.to_point = Vector2(0.0, _castle.get_threshold_edge_z())
	_bridge.to_altitude = _castle.get_threshold_altitude()
	_world.add_child(_bridge)


func _build_moon_puzzle() -> void:
	var terrain: CavernTerrainData = load(
		"res://data/levels/level02_forge_terrain.tres") as CavernTerrainData
	if terrain == null:
		push_warning("ForgeGameplay : terrain introuvable — pas de miroirs.")
		return
	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)

	var mirrors: Array[MoonMirror] = []
	for i in MIRROR_SPOTS.size():
		var at: Vector2 = MIRROR_SPOTS[i]
		var mirror := MoonMirror.new()
		mirror.name = "Miroir_%d" % i
		# Chaque miroir démarre à un cran différent — sinon les trois seraient
		# alignés d'entrée et le puzzle serait résolu avant d'exister.
		mirror.step = (i * 5) % MoonMirror.STEPS
		_world.add_child(mirror)
		mirror.global_position = Vector3(
			at.x, CavernTerrainBuilder.sample_point(terrain.floor_field, at, noise), at.y)
		mirrors.append(mirror)

	_puzzle = MoonPuzzle.new()
	_puzzle.name = "PuzzleLune"
	_world.add_child(_puzzle)

	var lighting: Node = _world.get_node_or_null("Lighting")
	# Deux frames de plus : la lune est posée par l'éclairage, et le puzzle a
	# besoin de son azimut pour savoir d'où vient le rayon.
	await get_tree().process_frame
	_puzzle.setup(mirrors, _castle, lighting as ForgeLighting)
	_puzzle.solved.connect(func() -> void:
		print("[ForgeGameplay] le sceau a cédé."))


func get_castle() -> ForgeCastle:
	return _castle


func get_puzzle() -> MoonPuzzle:
	return _puzzle

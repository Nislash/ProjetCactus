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

## LE BELVÉDÈRE, au bout du sentier : l'éperon nord qui surplombe le déversoir.
## LE FOND DE LA FOSSE creusée derrière le point d'apparition : le vrai départ.
## Le fond de la fosse, au NORD de celle-ci.
##
## Au nord et pas au centre : le sentier sort par le sud, et le placer au fond
## lui laisse seize mètres pour remonter les cinq mètres de paroi. Posé au
## milieu, il n'en avait que huit et grimpait à 35° — ce n'est plus une pente
## douce, c'est un mur.
## Le fond de la fosse, à son extrémité NORD.
##
## Au nord et pas au centre : le sentier sort par le sud, et le placer au fond
## lui laisse quatorze mètres pour remonter les cinq mètres de paroi. Posé au
## milieu, il n'en avait que huit et grimpait à 35° — ce n'est plus une pente
## douce, c'est un mur.
##
## Z = 74 et pas 79 : le domaine s'arrête à 78, et la fosse débordait dans le
## vide — son bord nord tombait hors de la carte.
const PIT_FLOOR := Vector2(-24.0, 72.0)

const BELVEDERE := Vector2(-58.0, -4.0)
const LEDGE_ALTITUDE: float = 29.0

## LE PALIER DU LEVIER, l'éperon d'en face. Quatre mètres plus bas — on saute
## vers le bas, on ne remonte pas.
##
## Les deux Z sont contraints l'un par l'autre : le belvédère s'avance jusqu'à
## Z = -10, le palier commence à Z = -16. Six mètres de vide, et la coulée
## vingt-sept mètres plus bas. Déplacer l'un sans l'autre casse le saut en
## silence, d'où le test qui mesure l'écart.
const LEVER_SPOT := Vector2(-58.0, -23.0)
const LEVER_ALTITUDE: float = 25.0

## LE PYLÔNE. Il bascule depuis le palier et sa pointe va TREMPER DANS LA
## COULÉE, vingt-trois mètres plus bas.
##
## Il ne se pose pas sur une berge : il se couche en travers de la lave, à demi
## immergé. On saute dessus depuis le palier, on marche le long du fût pendant
## qu'il baigne, et on ressort sur l'autre rive. C'est le seul endroit du niveau
## où l'on traverse la lave au ras — un pont de fortune qui n'en est pas un.
##
## Sa longueur n'est pas décorative : vingt-quatre mètres, c'est la largeur de
## la coulée à cette latitude plus ce qu'il faut pour poser ses deux bouts sur
## la roche. Plus court, il finirait dans la lave et le retour n'existerait pas.
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
	_rebake_navigation()

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
## RECUIRE LE NAVMESH une fois tout le décor posé.
##
## La navigation se cuit à la frame 1, le gameplay bâtit à la frame 2 : pont,
## terrasse, sentier, paliers et pylônes arrivaient donc APRÈS, et n'existaient
## pour aucun ennemi. Les joueurs, eux, marchaient dessus — c'est une collision,
## pas une navigation — d'où un défaut invisible tant qu'on joue seul.
##
## Deux frames d'attente avant de recuire : les objets bâtis dans leur propre
## `_ready` (le château, le pont) ne sont pas encore là quand celui-ci rend la
## main.
func _rebake_navigation() -> void:
	await get_tree().process_frame
	await get_tree().process_frame
	var navigation: Node = _world.get_node_or_null("Navigation")
	if navigation == null or not navigation.has_method("bake_now"):
		push_warning("ForgeGameplay : pas de navigation à recuire.")
		return
	var polygons: int = navigation.call("bake_now")
	print("[ForgeGameplay] navmesh recuit sur le décor complet — %d polygones." % polygons)


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


## LA CHAÎNE DU DÉTOUR : sentier de montagne, saut par-dessus le déversoir,
## levier, rampe autour du donjon, pylône qu'on abat pour rentrer.
##
## Les pièces sont posées ensemble parce qu'elles ne veulent rien dire
## séparément. Le levier ouvre une rampe qu'on ne peut pas encore atteindre ; le
## pylône n'est un chemin que pour revenir de là où le levier se trouve ; et le
## sentier n'a d'intérêt que parce qu'il finit sur un saut.
func _build_twist_chain() -> void:
	var terrain: CavernTerrainData = load(
		"res://data/levels/level02_forge_terrain.tres") as CavernTerrainData
	if terrain == null or _castle == null:
		push_warning("ForgeGameplay : pas de terrain ou de château — pas de détour.")
		return
	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)

	_build_mountain_trail(terrain, noise)
	_build_jump_and_lever(terrain, noise)
	_build_keep_ramp(terrain, noise)


## LE SENTIER. Il part DERRIÈRE le point d'apparition, sur la gauche, et monte
## la montagne ouest en lacets jusqu'au haut de la cascade.
func _build_mountain_trail(terrain: CavernTerrainData, noise: FastNoiseLite) -> void:
	# LA PLATEFORME DU DÉPART, au fond de la fosse creusée derrière le point
	# d'apparition. On tombe dedans, on ne s'y promène pas : ses parois font
	# six mètres et demi, et le sentier est la seule sortie.
	var pit_floor: float = CavernTerrainBuilder.ground_at(terrain, PIT_FLOOR, noise)
	var landing := ForgeLedge.new()
	landing.name = "PlateformeDuDepart"
	landing.centre = PIT_FLOOR
	landing.altitude = pit_floor + 0.6
	landing.half_extent = Vector2(5.0, 5.0)
	_world.add_child(landing)

	# UNE BRAISE AU FOND. La fosse est un trou noir vue du bord : sans elle on
	# ne distingue pas s'il y a un sol cinq mètres plus bas ou vingt.
	#
	# Faible et sans ombre — juste assez pour qu'on devine une surface. Une
	# lampe franche ferait signal, et l'intérêt de ce départ est qu'il ne se
	# signale pas.
	var ember := OmniLight3D.new()
	ember.name = "BraiseDeLaFosse"
	ember.light_color = Color(1.000, 0.478, 0.184)
	ember.light_energy = 1.6
	ember.omni_range = 16.0
	ember.shadow_enabled = false
	_world.add_child(ember)
	ember.global_position = Vector3(PIT_FLOOR.x, pit_floor + 2.4, PIT_FLOOR.y)

	var trail := MountainTrail.new()
	trail.name = "SentierDeLaMontagne"
	# LE COULOIR EST CONTRAINT PAR LA ROCHE, pas choisi pour sa beauté.
	#
	# Le rempart ouest monte à 47 m et sa face est verticale — 80° mesurés.
	# Chaque point de passage a été relevé sur le SOL RÉEL avant d'être posé :
	# la version précédente utilisait les altitudes du plancher seul, qui
	# ignorent le rempart, et le sentier s'était retrouvé enfoui dans la
	# falaise. Visible à la caméra, inatteignable à pied.
	trail.waypoints = [
		Vector3(PIT_FLOOR.x, pit_floor + 0.6, PIT_FLOOR.y),
		Vector3(-24.0, 8.0, 58.0),
		Vector3(-22.0, 12.0, 50.0),
		Vector3(-19.0, 15.0, 48.0),
		# LE PINCEMENT. Le rempart avance jusqu'à X = -16 à cette latitude :
		# le sentier doit s'écarter vers l'est, sinon il rentre dans la roche.
		# Relevé, pas deviné — c'est en croyant la voie libre qu'on l'y avait
		# enfoui la première fois.
		Vector3(-13.0, 18.0, 42.0),
		Vector3(-20.0, 21.0, 36.0),
		Vector3(-31.0, 23.0, 30.0),
		Vector3(-39.0, 25.0, 24.0),
		Vector3(-46.0, 26.5, 16.0),
		Vector3(-52.0, 28.0, 6.0),
		# Arrivée À PLAT sur le belvédère : une rampe qui débouche en pente sur
		# une dalle horizontale crée une arête, et c'est là que la navigation
		# se coupait dans les versions précédentes.
		Vector3(BELVEDERE.x, LEDGE_ALTITUDE, BELVEDERE.y + 8.0),
		Vector3(BELVEDERE.x, LEDGE_ALTITUDE, BELVEDERE.y),
	]
	_world.add_child(trail)


## LE SAUT ET LE LEVIER.
##
## Deux éperons de roche qui s'avancent au-dessus du déversoir, l'un en face de
## l'autre. Entre leurs pointes, six mètres de vide et vingt-cinq mètres plus
## bas, la coulée.
##
## Le palier du levier est QUATRE MÈTRES PLUS BAS que le belvédère : on saute
## donc en descendant, ce qui se franchit, et on ne peut pas repartir en sens
## inverse. C'est ça qui rend le pylône nécessaire plutôt que décoratif — un
## saut symétrique en ferait un ornement.
func _build_jump_and_lever(terrain: CavernTerrainData, noise: FastNoiseLite) -> void:
	var belvedere := ForgeLedge.new()
	belvedere.name = "BelvedereDeLaCascade"
	belvedere.centre = BELVEDERE
	belvedere.altitude = LEDGE_ALTITUDE
	belvedere.half_extent = Vector2(7.0, 6.0)
	_world.add_child(belvedere)

	var perch := ForgeLedge.new()
	perch.name = "PalierDuLevier"
	perch.centre = LEVER_SPOT
	perch.altitude = LEVER_ALTITUDE
	perch.half_extent = Vector2(9.0, 7.0)
	_world.add_child(perch)

	var lever := ForgeLever.new()
	lever.name = "LevierCache"
	_world.add_child(lever)
	lever.global_position = Vector3(LEVER_SPOT.x - 4.0, LEVER_ALTITUDE, LEVER_SPOT.y - 2.0)

	# LE PYLÔNE, au bord nord du palier. Il bascule vers le cirque et retombe
	# en RAMPE : sa base reste haut, sa pointe touche la berge d'en bas. Un
	# tablier horizontal finirait en l'air, vingt mètres au-dessus du sol.
	var pylon := FragilePylon.new()
	pylon.name = "PyloneFragile"
	pylon.fall_direction = Vector2(0.0, 1.0)
	pylon.height = PYLON_SPAN
	# Il se couche EN TRAVERS de la coulée, centré sur elle, avec son tablier
	# quatre-vingt-dix centimètres au-dessus de la nappe : assez pour qu'on
	# marche au sec, assez peu pour que la lave lèche ses flancs.
	pylon.lands_at = Vector2(LEVER_SPOT.x, -13.0)
	pylon.deck_altitude = _lava_surface() + 0.9
	pylon.bank_altitudes = Vector2(
		CavernTerrainBuilder.ground_at(terrain, Vector2(LEVER_SPOT.x, -26.0), noise),
		CavernTerrainBuilder.ground_at(terrain, Vector2(LEVER_SPOT.x, 0.0), noise))
	_world.add_child(pylon)
	pylon.global_position = Vector3(LEVER_SPOT.x + 4.0, LEVER_ALTITUDE, LEVER_SPOT.y - 5.0)

	lever.pulled.connect(func() -> void:
		var ramp: KeepSpiralRamp = _world.get_node_or_null("RampeDuDonjon") as KeepSpiralRamp
		if ramp != null:
			ramp.deploy())


## L'altitude de la coulée. Lue sur la nappe plutôt que recopiée : elle a déjà
## bougé deux fois, et un chiffre en double finit toujours par diverger.
func _lava_surface() -> float:
	var terrain: CavernTerrainData = load(
		"res://data/levels/level02_forge_terrain.tres") as CavernTerrainData
	if terrain == null or terrain.lake == null:
		return 1.9
	return terrain.lake.surface_altitude


func _build_keep_ramp(terrain: CavernTerrainData, noise: FastNoiseLite) -> void:
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
	ramp.inner_radius = _castle.keep_width * 0.46 - 3.4
	ramp.hall_altitude = _castle.get_hall_altitude()
	_world.add_child(ramp)


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

extends SceneTree

## La Forge (niveau 2). Lancer via :
##   godot --headless --path godot --script tests/test_forge.gd
##
## Le niveau 2 réutilise le générateur du niveau 1 : ce sont les **données**
## qui font le biome. Ce test défend ce qui, du coup, peut casser en silence —
## une donnée manquante ne lève aucune erreur, elle produit un niveau vide.
##
## Il vérifie aussi les deux promesses du biome, qui sont géométriques et donc
## mesurables : **on descend** (le sol du centre est plus bas que celui du
## pourtour), et **la lumière vient du bas** (les sources sont au niveau de la
## lave, pas de la voûte).

const SCENE_PATH := "res://scenes/levels/level_02_forge/level_02_forge.tscn"
const TERRAIN_PATH := "res://data/levels/level02_forge_terrain.tres"

var _root: Node3D
var _world: Node3D
var _terrain: CavernTerrainData
var _noise: FastNoiseLite


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	_terrain = load(TERRAIN_PATH) as CavernTerrainData
	if _terrain == null:
		print("[FAIL] terrain introuvable — lancer tools/build_forge_terrain.gd")
		quit(1)
		return
	_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)

	var failed: int = 0
	failed += _test_the_floor_funnels_down()
	failed += _test_the_lava_is_at_the_bottom()
	failed += _test_slopes_stay_walkable()

	var packed: PackedScene = load(SCENE_PATH) as PackedScene
	if packed == null:
		print("[FAIL] scène introuvable : %s" % SCENE_PATH)
		quit(1)
		return
	_root = packed.instantiate() as Node3D
	root.add_child(_root)
	for i in 12:
		await process_frame
	_world = _root.get_node_or_null("World") as Node3D

	failed += _test_the_terrain_actually_builds()
	failed += _test_the_light_comes_from_below()
	failed += _test_spawns_are_on_the_rim()
	failed += _test_the_sky_is_open()
	failed += _test_the_castle_closes_the_pit()
	failed += _test_the_moon_puzzle_is_solvable()
	failed += _test_the_boss_waits_behind_the_gate()
	failed += _test_the_castle_can_be_reached()
	failed += _test_the_stone_is_textured()
	failed += _test_nothing_spawns_in_the_lava()
	failed += await _test_the_lava_kills()
	failed += _test_you_can_go_around_and_under_the_bridge()
	failed += await _test_the_detour_opens_the_tower()
	failed += await _test_the_gate_opens_onto_a_room()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — la Forge descend vers sa lave")
		quit(0)


func _ground(at: Vector2) -> float:
	return CavernTerrainBuilder.sample_point(_terrain.floor_field, at, _noise)


## LA PROMESSE DU BIOME : on descend. Si le centre n'était pas plus bas que le
## pourtour, la Forge ne serait qu'une salle ronde de plus.
func _test_the_floor_funnels_down() -> int:
	var rim: float = _ground(Vector2(0.0, 48.0))
	var mid: float = _ground(Vector2(0.0, 30.0))
	var low: float = _ground(Vector2(0.0, 14.0))

	if not (rim > mid and mid > low):
		print("[FAIL] entonnoir : altitudes %.1f → %.1f → %.1f, ça ne descend pas"
			% [rim, mid, low])
		return 1
	var drop: float = rim - low
	if drop < 5.0:
		print("[FAIL] entonnoir : seulement %.1f m de dénivelé — on ne le sentira pas" % drop)
		return 1
	print("[OK] the_floor_funnels_down (%.1f m de la crête au bord du bassin)" % drop)
	return 0


func _test_the_lava_is_at_the_bottom() -> int:
	var lava: CavernLake = _terrain.lake
	if lava == null:
		print("[FAIL] lave : aucune nappe déclarée")
		return 1
	# Elle doit être SOUS le sol du pourtour, sinon elle déborderait dans les
	# galeries d'accès.
	var rim: float = _ground(Vector2(0.0, 48.0))
	if lava.surface_altitude >= rim:
		print("[FAIL] lave : à %.1f m alors que la crête est à %.1f m — elle déborde"
			% [lava.surface_altitude, rim])
		return 1
	# Et son fond doit être plat, sinon la nappe se réduit à une flaque.
	var flat_enough: bool = false
	for basin in _terrain.floor_field.basins:
		if basin.flat_bottom >= 0.35:
			flat_enough = true
	if not flat_enough:
		print("[FAIL] lave : aucun bassin à fond plat — la nappe sera une flaque")
		return 1
	# ET SURTOUT : la nappe doit ÉMERGER du lit.
	#
	# C'est le contrôle qui manquait. La nappe était à -2,2 alors que le lit ne
	# descend jamais sous +1,18 : elle était enterrée de trois mètres, donc
	# invisible. Aucun test ne l'a vu parce qu'ils regardaient tous la nappe
	# par rapport à la CRÊTE, jamais par rapport au FOND. Une coulée qu'on ne
	# voit pas n'est pas une coulée.
	var wet: int = 0
	var samples: int = 0
	var deepest: float = 0.0
	for i in 61:
		var x: float = -60.0 + float(i) * 2.0
		var bed: float = _ground(Vector2(x, lava.center.y))
		samples += 1
		if bed < lava.surface_altitude:
			wet += 1
			deepest = maxf(deepest, lava.surface_altitude - bed)
	var wet_ratio: float = float(wet) / float(samples)
	if wet_ratio < 0.35:
		print("[FAIL] lave : seulement %.0f %% de l'axe est immergé — la coulée est enterrée"
			% (wet_ratio * 100.0))
		return 1
	if deepest < lava.minimum_depth:
		print("[FAIL] lave : %.2f m au plus profond, sous le minimum de %.2f m"
			% [deepest, lava.minimum_depth])
		return 1

	print("[OK] the_lava_is_at_the_bottom (%.1f m, crête à %.1f m, %.0f %% de l'axe immergé, %.2f m au plus profond)"
		% [lava.surface_altitude, rim, wet_ratio * 100.0, deepest])
	return 0


## Les paliers doivent rester marchables. Un `smoothstep` pique à 1,5 fois sa
## pente moyenne — la faute qu'on a déjà payée au niveau 1.
func _test_slopes_stay_walkable() -> int:
	var worst: float = 0.0
	var worst_at := Vector2.ZERO
	var worst_bank: float = 0.0
	var banks: int = 0
	var lava: CavernLake = _terrain.lake
	var step: float = 2.0
	var r: float = 4.0
	while r < 56.0:
		var a: float = 0.0
		while a < TAU:
			var at := Vector2(cos(a) * r, sin(a) * r)
			var h: float = _ground(at)
			var hx: float = _ground(at + Vector2(step, 0.0))
			var hz: float = _ground(at + Vector2(0.0, step))
			var slope: float = rad_to_deg(atan(maxf(absf(hx - h), absf(hz - h)) / step))
			# LES BERGES DE LA COULÉE ONT LEUR PROPRE PLAFOND.
			#
			# Une berge raide n'est pas un défaut, c'est ce qui empêche de
			# descendre par mégarde dans de la lave qui tue. Lui appliquer la
			# règle des chemins reviendrait à exiger qu'on puisse marcher dans
			# le danger.
			#
			# Mais elle reste PLAFONNÉE, et c'est ce qui distingue ce contrôle
			# d'une exemption : une paroi verticale au bord de la coulée ferait
			# encore échouer le test, et le nombre de points concernés est
			# affiché pour qu'il ne puisse pas grossir en silence.
			if _near_lava(at, lava):
				banks += 1
				worst_bank = maxf(worst_bank, slope)
			elif slope > worst:
				worst = slope
				worst_at = at
			a += 0.35
		r += 3.0

	if worst > _terrain.max_slope_degrees + 2.0:
		print("[FAIL] pentes : %.1f° en (%.0f, %.0f), au-delà du plafond de %.0f°"
			% [worst, worst_at.x, worst_at.y, _terrain.max_slope_degrees])
		return 1
	if worst_bank > BANK_MAX_SLOPE:
		print("[FAIL] berges : %.1f°, au-delà du plafond de berge de %.0f°"
			% [worst_bank, BANK_MAX_SLOPE])
		return 1
	print("[OK] slopes_stay_walkable (max %.1f° ; berges %.1f° sur %d points)"
		% [worst, worst_bank, banks])
	return 0


## Un point est « sur la berge » s'il touche la coulée à moins de cette
## distance de son bord, en mètres.
const BANK_REACH: float = 5.0

## Plafond propre aux berges. Elles ont le droit d'être raides — pas d'être
## verticales : une paroi franche se lit comme un mur invisible.
const BANK_MAX_SLOPE: float = 52.0


func _near_lava(at: Vector2, lava: CavernLake) -> bool:
	if lava == null:
		return false
	var local: Vector2 = at - lava.center
	var d: float = Vector2(local.x / maxf(lava.radii.x - BANK_REACH, 0.001),
		local.y / maxf(lava.radii.y - BANK_REACH, 0.001)).length()
	return d <= 1.0 + BANK_REACH / maxf(lava.radii.y, 0.001)


func _test_the_terrain_actually_builds() -> int:
	var terrain_node: Node = _world.get_node_or_null("ForgeTerrain")
	if terrain_node == null or terrain_node.get_child_count() == 0:
		print("[FAIL] terrain : rien n'a été construit dans la scène")
		return 1
	var lava_node: Node = _world.find_child("Lake", true, false)
	if lava_node == null:
		print("[FAIL] lave : la nappe n'apparaît pas dans la scène")
		return 1
	print("[OK] the_terrain_actually_builds (%d chunks)" % terrain_node.get_child_count())
	return 0


## LA DEUXIÈME PROMESSE : la lumière vient d'en bas. C'est le renversement qui
## fait le biome — si les lampes finissaient sous la voûte, on aurait refait la
## caverne en orange.
func _test_the_light_comes_from_below() -> int:
	var lights: Array[OmniLight3D] = []
	var stack: Array[Node] = [_world]
	while not stack.is_empty():
		var n: Node = stack.pop_back()
		for c in n.get_children():
			stack.append(c)
		var l: OmniLight3D = n as OmniLight3D
		if l != null and l.name.begins_with("Lave"):
			lights.append(l)

	if lights.size() < 4:
		print("[FAIL] lumière : %d sources sur la lave, attendu au moins 4" % lights.size())
		return 1

	var rim: float = _ground(Vector2(0.0, 48.0))
	for l in lights:
		if l.global_position.y > rim:
			print("[FAIL] lumière : une source est à %.1f m, au-dessus de la crête (%.1f m)"
				% [l.global_position.y, rim])
			return 1
	print("[OK] the_light_comes_from_below (%d sources, toutes sous la crête)" % lights.size())
	return 0


func _test_spawns_are_on_the_rim() -> int:
	var spawns: Node = _world.get_node_or_null("PlayerSpawnPoints")
	if spawns == null or spawns.get_child_count() < 4:
		print("[FAIL] spawns : absents ou incomplets")
		return 1
	# On doit arriver EN HAUT : voir le gouffre avant d'y descendre est toute
	# la mise en scène du niveau.
	var low: float = _ground(Vector2(0.0, 14.0))
	for child in spawns.get_children():
		var m: Node3D = child as Node3D
		if m == null:
			continue
		if m.global_position.y < low + 4.0:
			print("[FAIL] spawn « %s » : à %.1f m, on n'arrive pas par le haut"
				% [m.name, m.global_position.y])
			return 1
	print("[OK] spawns_are_on_the_rim")
	return 0


## À CIEL OUVERT : aucune voûte ne doit avoir été construite. Le générateur en
## bâtit une par défaut, et c'est exactement ce qu'on ne veut pas ici — un
## couvercle sur un niveau qu'on veut ouvert.
##
## L'enceinte est alors le SOL qui monte : on vérifie que les falaises
## existent, sinon le joueur sortirait par les côtés.
func _test_the_sky_is_open() -> int:
	if not _terrain.open_sky:
		print("[FAIL] ciel : le terrain n'est pas déclaré ouvert")
		return 1

	var vault: Node = _world.find_child("Vault", true, false)
	if vault != null and vault.get_child_count() > 0:
		print("[FAIL] ciel : %d tuiles de voûte construites — le niveau est couvert"
			% vault.get_child_count())
		return 1

	# Les falaises. Hors des chambres, le sol doit être nettement plus haut que
	# le sol jouable — sinon rien ne borne le cirque.
	#
	# On CHERCHE un point hors chambre au lieu d'en supposer un : le premier
	# essai mesurait à (0, 74), qui tombe en plein dans la Galerie Nord — donc
	# à l'intérieur du volume, là où par construction il n'y a pas de falaise.
	var inside: float = _ground_with_rim(Vector2(0.0, 30.0))
	var outside: float = -INF
	var probe := Vector2.ZERO
	var r: float = 60.0
	while r < 76.0:
		var a: float = 0.0
		while a < TAU:
			var at := Vector2(cos(a) * r, sin(a) * r)
			if CavernTerrainBuilder.chamber_mask(_terrain, at) > 0.01:
				a += 0.2
				continue
			var h: float = _ground_with_rim(at)
			if h > outside:
				outside = h
				probe = at
			a += 0.2
		r += 4.0

	if outside == -INF:
		print("[FAIL] falaises : aucun point hors chambre — le cirque déborde du domaine")
		return 1
	if outside - inside < 15.0:
		print("[FAIL] falaises : %.1f m en (%.0f, %.0f) — on sortirait du cirque"
			% [outside - inside, probe.x, probe.y])
		return 1
	print("[OK] the_sky_is_open (falaises à +%.0f m, aucune voûte)" % (outside - inside))
	return 0


## Le sol tel qu'on le foule, falaises comprises.
func _ground_with_rim(at: Vector2) -> float:
	var base: float = _ground(at)
	var mask: float = CavernTerrainBuilder.chamber_mask(_terrain, at)
	return base + (1.0 - mask) * _terrain.open_sky_rim_height


func _test_the_castle_closes_the_pit() -> int:
	var castle: Node3D = _world.get_node_or_null("Chateau") as Node3D
	if castle == null:
		print("[FAIL] château : absent")
		return 1
	# Il doit dominer la crête : c'est ce qu'on voit en arrivant.
	var top: float = 0.0
	for child in castle.get_children():
		var mesh: Node3D = child as Node3D
		if mesh != null and mesh.name.begins_with("Tour"):
			top = maxf(top, mesh.global_position.y)
	var rim: float = _ground(Vector2(0.0, 48.0))
	if top < rim + 10.0:
		print("[FAIL] château : sommet à %.1f m, la crête est à %.1f m — invisible en arrivant"
			% [top, rim])
		return 1
	# Et sa porte doit être scellée au départ.
	if castle.call("is_open"):
		print("[FAIL] château : la porte est déjà ouverte")
		return 1
	print("[OK] the_castle_closes_the_pit (tours à %.0f m, crête à %.0f m)" % [top, rim])
	return 0


## LE PUZZLE DOIT ÊTRE SOLUBLE. Un puzzle de réflexion mal placé n'échoue pas
## bruyamment : il reste simplement insoluble, et le joueur tourne des miroirs
## pendant vingt minutes en croyant qu'il n'a pas compris.
##
## On l'essaie par la force : toutes les combinaisons de crans, jusqu'à en
## trouver une qui ouvre la porte. Trois miroirs à douze crans font 1728
## essais — négligeable pour une machine, impossible pour un joueur, et c'est
## bien la preuve qu'on cherche : qu'AU MOINS une solution existe.
func _test_the_moon_puzzle_is_solvable() -> int:
	var puzzle: Node = _world.get_node_or_null("PuzzleLune")
	if puzzle == null:
		print("[FAIL] puzzle : absent")
		return 1
	var mirrors: Array = puzzle.call("get_mirrors")
	if mirrors.size() < 3:
		print("[FAIL] puzzle : %d miroirs au lieu de 3" % mirrors.size())
		return 1

	# Il ne doit PAS être résolu d'entrée : une énigme déjà faite n'en est pas
	# une.
	if bool(puzzle.call("is_solved")):
		print("[FAIL] puzzle : résolu dès le départ")
		return 1

	var steps: int = MoonMirror.STEPS
	var found: Array[int] = []
	for a in steps:
		for b in steps:
			for c in steps:
				mirrors[0].step = a
				mirrors[1].step = b
				mirrors[2].step = c
				for m in mirrors:
					m._apply_step()
				puzzle.call("_recompute")
				if bool(puzzle.call("is_solved")):
					found = [a, b, c]
					break
			if not found.is_empty():
				break
		if not found.is_empty():
			break

	if found.is_empty():
		print("[FAIL] puzzle : AUCUNE combinaison n'ouvre la porte — insoluble")
		return 1
	print("[OK] the_moon_puzzle_is_solvable (crans %s)" % [found])
	return 0


## LE BOSS NE DOIT PAS S'ÉVEILLER DEPUIS LE CIRQUE.
##
## Il se tenait au bord du bassin, à vingt-deux mètres du centre, avec une zone
## d'éveil de trente : il attaquait donc pendant qu'on descendait encore, et le
## puzzle perdait tout son sens puisqu'on se battait avant de l'avoir résolu.
##
## On vérifie les deux causes séparément — sa distance, et le rayon de sa zone.
func _test_the_boss_waits_behind_the_gate() -> int:
	var boss: Node3D = _world.get_node_or_null("BossGolem") as Node3D
	if boss == null:
		print("[FAIL] boss : absent")
		return 1

	# Loin du cirque, où le joueur passe l'essentiel de son temps.
	var to_pit: float = Vector2(boss.global_position.x, boss.global_position.z).length()
	if to_pit < 60.0:
		print("[FAIL] boss : à %.0f m du centre du cirque — trop près" % to_pit)
		return 1

	var zone: Area3D = _world.find_child("ReveilDuGolem", true, false) as Area3D
	if zone == null:
		print("[FAIL] boss : aucune zone d'éveil")
		return 1
	var shape: CollisionShape3D = null
	for child in zone.get_children():
		shape = child as CollisionShape3D
		if shape != null:
			break
	if shape == null or not (shape.shape is SphereShape3D):
		print("[FAIL] boss : zone d'éveil sans forme")
		return 1
	var radius: float = (shape.shape as SphereShape3D).radius

	# Elle ne doit pas déborder jusqu'au cirque : sinon on réveille le Golem
	# en s'approchant de la porte, avant même de l'avoir ouverte.
	var reach: float = to_pit - radius
	if reach < 35.0:
		print("[FAIL] boss : sa zone d'éveil arrive à %.0f m du cirque" % reach)
		return 1
	print("[OK] the_boss_waits_behind_the_gate (%.0f m du cirque, éveil à %.0f m)"
		% [to_pit, radius])
	return 0


## ON DOIT POUVOIR ENTRER.
##
## Signalé en jeu : la porte s'ouvrait et le château restait inaccessible — il
## était bâti de l'autre côté de la coulée, sans aucun passage. Le puzzle
## récompensait par une porte ouverte sur rien.
##
## C'est un défaut de méthode : j'avais vérifié que la porte s'ouvrait, jamais
## qu'on pouvait la franchir. Ce test couvre le trajet, pas l'événement.
func _test_the_castle_can_be_reached() -> int:
	var bridge: Node3D = _world.get_node_or_null("PontSuspendu") as Node3D
	if bridge == null:
		print("[FAIL] accès : aucun pont — le château est une île")
		return 1

	# Le pont doit ENJAMBER les douves : une extrémité de chaque côté.
	var lava: CavernLake = _terrain.lake
	var near := Vector2(bridge.from_point.x, bridge.from_point.y)
	var far := Vector2(bridge.to_point.x, bridge.to_point.y)
	if _in_lava(near, lava) or _in_lava(far, lava):
		print("[FAIL] pont : une extrémité tombe dans la lave")
		return 1
	var crosses: bool = false
	for i in 20:
		var t: float = float(i) / 19.0
		if _in_lava(near.lerp(far, t), lava):
			crosses = true
			break
	if not crosses:
		print("[FAIL] pont : il ne franchit pas les douves")
		return 1

	# Et son tablier doit passer AU-DESSUS de la coulée SUR TOUTE SA LONGUEUR.
	#
	# On testait l'altitude nominale, une constante. Le tablier a maintenant une
	# pente et une flèche : c'est son point BAS qui décide s'il trempe, et ce
	# point n'est nulle part écrit dans les données.
	var lowest: float = 999.0
	var lowest_at: float = 0.0
	for i in 41:
		var t: float = float(i) / 40.0
		var y: float = bridge.deck_altitude_at(t)
		if y < lowest:
			lowest = y
			lowest_at = t
	if lowest < lava.surface_altitude + 1.6:
		print("[FAIL] pont : point bas à %.2f m (t=%.2f), la lave est à %.2f m"
			% [lowest, lowest_at, lava.surface_altitude])
		return 1

	# ET ON DOIT POUVOIR Y MONTER.
	#
	# Signalé en jeu : 1,75 m de marche au sud. Un `CharacterBody3D` ne gravit
	# pas ça — le pont était un décor.
	var near_ground: float = _ground(near)
	var far_ground: float = bridge.to_altitude
	var step_near: float = absf(bridge.get_near_end().y - near_ground)
	if step_near > ForgeBridge.MAX_STEP_UP + 0.01:
		print("[FAIL] pont : %.2f m de marche à l'entrée sud — infranchissable" % step_near)
		return 1
	var step_far: float = absf(bridge.get_far_end().y - far_ground)
	if step_far > ForgeBridge.MAX_STEP_UP + 0.01:
		print("[FAIL] pont : %.2f m d'écart avec le seuil du château" % step_far)
		return 1

	# Il doit arriver près du château, sinon il ne mène nulle part.
	var castle: Node3D = _world.get_node_or_null("Chateau") as Node3D
	if castle == null:
		print("[FAIL] accès : pas de château")
		return 1
	var gap: float = far.distance_to(Vector2(castle.global_position.x, castle.global_position.z))
	if gap > 24.0:
		print("[FAIL] pont : il s'arrête à %.0f m du château" % gap)
		return 1

	# Le tablier doit être un vrai sol : sans collision, on le traverse.
	var decks: int = 0
	for child in bridge.get_children():
		var body: StaticBody3D = child as StaticBody3D
		if body != null and body.name.begins_with("ColTablier"):
			decks += 1
	if decks < 5:
		print("[FAIL] pont : %d segments de collision — on passerait au travers" % decks)
		return 1

	# ET LE VRAI TEST : un chemin de navigation existe, du spawn au seuil.
	# La géométrie ci-dessus prouve qu'un pont est là ; seul le NavigationServer
	# prouve qu'on peut le prendre.
	var region: NavigationRegion3D = _world.get_node_or_null("Navigation") as NavigationRegion3D
	if region == null:
		print("[FAIL] accès : pas de région de navigation")
		return 1
	var map: RID = region.get_navigation_map()
	var spawn: Node3D = _world.get_node_or_null("PlayerSpawnPoints/Spawn0") as Node3D
	if spawn == null:
		print("[FAIL] accès : Spawn0 introuvable")
		return 1

	var threshold: Vector3 = bridge.get_far_end()
	var start: Vector3 = NavigationServer3D.map_get_closest_point(map, spawn.global_position)
	var finish: Vector3 = NavigationServer3D.map_get_closest_point(map, threshold)
	if finish.distance_to(threshold) > 4.0:
		print("[FAIL] accès : le bout du pont n'est pas sur le navmesh (%.1f m)"
			% finish.distance_to(threshold))
		return 1

	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, start, finish, true)
	if path.size() < 2:
		print("[FAIL] accès : aucun chemin du spawn au château")
		return 1
	var arrival: float = path[path.size() - 1].distance_to(finish)
	if arrival > 3.0:
		print("[FAIL] accès : chemin tronqué, s'arrête à %.1f m du seuil" % arrival)
		return 1

	# Et ce chemin doit PASSER PAR LE PONT. Sinon le pathfinder a trouvé un
	# contournement — ce qui voudrait dire que le pont ne sert à rien, ou pire,
	# que le navmesh enjambe la lave par un raccourci qui n'existe pas en jeu.
	var over_bridge: bool = false
	for point in path:
		if _in_lava(Vector2(point.x, point.z), lava):
			over_bridge = true
			break
	if not over_bridge:
		print("[FAIL] accès : le chemin évite le pont — il franchit les douves ailleurs")
		return 1

	var length: float = 0.0
	for i in path.size() - 1:
		length += path[i].distance_to(path[i + 1])
	print("[OK] the_castle_can_be_reached (pont de %.0f m, %d segments, chemin de %.0f m)"
		% [near.distance_to(far), decks, length])
	return 0


func _in_lava(at: Vector2, lava: CavernLake) -> bool:
	if lava == null:
		return false
	var local: Vector2 = at - lava.center
	return Vector2(local.x / maxf(lava.radii.x, 0.001),
		local.y / maxf(lava.radii.y, 0.001)).length() <= 1.0


## LA PIERRE EST DE LA PIERRE, PAS UNE COULEUR.
##
## Le repli est silencieux par conception : si la matière manque, le château se
## bâtit quand même en gris plat et le niveau reste jouable. C'est le bon
## comportement en jeu, et exactement ce qui ferait passer une régression
## inaperçue — d'où ce test.
func _test_the_stone_is_textured() -> int:
	var subjects: Array = [
		["château", _world.get_node_or_null("Chateau"), ["Donjon", "Terrasse", "Tour_0"]],
		["pont", _world.get_node_or_null("PontSuspendu"), ["Tablier_0", "Tablier_7"]],
	]
	for subject in subjects:
		var owner: Node = subject[1]
		if owner == null:
			print("[FAIL] matière : « %s » absent" % subject[0])
			return 1
		for part_name in subject[2]:
			var part: MeshInstance3D = owner.get_node_or_null(part_name) as MeshInstance3D
			if part == null:
				print("[FAIL] matière : %s/%s introuvable" % [subject[0], part_name])
				return 1
			var material: StandardMaterial3D = part.material_override as StandardMaterial3D
			if material == null or material.albedo_texture == null:
				print("[FAIL] matière : %s/%s est une couleur plate" % [subject[0], part_name])
				return 1
			# Sans triplanaire, des UV de boîte étireraient la texture sur les
			# faces et laisseraient une couture à chaque arête.
			if not material.uv1_triplanar:
				print("[FAIL] matière : %s/%s n'est pas en triplanaire" % [subject[0], part_name])
				return 1
			if material.normal_texture == null or material.roughness_texture == null:
				print("[FAIL] matière : %s/%s n'a pas ses cartes PBR" % [subject[0], part_name])
				return 1

	# Le tablier et les murs ne portent PAS la même matière : on marche sur
	# l'un, l'autre soutient.
	var deck: MeshInstance3D = (_world.get_node_or_null("PontSuspendu") as Node) \
		.get_node_or_null("Tablier_0") as MeshInstance3D
	var wall: MeshInstance3D = (_world.get_node_or_null("Chateau") as Node) \
		.get_node_or_null("Donjon") as MeshInstance3D
	if (deck.material_override as StandardMaterial3D).albedo_texture \
			== (wall.material_override as StandardMaterial3D).albedo_texture:
		print("[FAIL] matière : le tablier et les murs partagent la même pierre")
		return 1

	print("[OK] the_stone_is_textured (maçonnerie + dallage, triplanaires, PBR complet)")
	return 0


## RIEN NE DOIT APPARAÎTRE DANS LA COULÉE.
##
## Signalé en jeu : un coffre à reliques gisait au fond de la lave, côté est. Il
## n'y était pas tombé — il avait toujours été là, à -1,94 m, et c'est la nappe
## qui est montée par-dessus quand on l'a remontée à +1,9.
##
## C'est le mode de panne des marqueurs posés à la main : ils sont justes le
## jour où on les pose, et rien ne les revérifie quand le terrain bouge. Ce test
## les revérifie tous, y compris ceux qu'on ajoutera demain.
func _test_nothing_spawns_in_the_lava() -> int:
	var lava: CavernLake = _terrain.lake
	var drowned: Array[String] = []
	for marker in _all_markers(_world):
		var at := Vector2(marker.global_position.x, marker.global_position.z)
		if not _in_lava(at, lava):
			continue
		if _ground(at) < lava.surface_altitude:
			drowned.append(marker.name)
	if not drowned.is_empty():
		print("[FAIL] noyés : %s" % ", ".join(drowned))
		return 1
	print("[OK] nothing_spawns_in_the_lava (%d marqueurs vérifiés)"
		% _all_markers(_world).size())
	return 0


func _all_markers(from: Node) -> Array[Marker3D]:
	var found: Array[Marker3D] = []
	for child in from.get_children():
		var marker: Marker3D = child as Marker3D
		if marker != null:
			found.append(marker)
		found.append_array(_all_markers(child))
	return found


## LA LAVE TUE — ET LAISSE LE CORPS RÉCUPÉRABLE.
##
## Les deux moitiés comptent autant l'une que l'autre. Tuer sans éjecter
## laisserait le corps au fond de la coulée : le jeu relève les alliés à leur
## contact, donc un joueur tombé dedans serait perdu pour la run. Éjecter sans
## tuer ferait de la lave un trampoline.
func _test_the_lava_kills() -> int:
	var hazard: LavaHazard = _world.get_node_or_null("LaveMortelle") as LavaHazard
	if hazard == null:
		print("[FAIL] lave : aucune zone mortelle — on la traverserait à pied")
		return 1

	var lava: CavernLake = _terrain.lake
	var victim := CharacterBody3D.new()
	victim.name = "Cobaye"
	var health := HealthComponent.new()
	health.name = "Health"
	victim.add_child(health)
	_world.add_child(victim)
	await process_frame

	# En plein milieu de la coulée.
	var middle := Vector2(lava.center.x, lava.center.y)
	victim.global_position = Vector3(middle.x, lava.surface_altitude, middle.y)
	hazard._touch(victim)

	var died: bool = health.is_dead
	var landed := Vector2(victim.global_position.x, victim.global_position.z)
	var out: bool = not _in_lava(landed, lava)
	var above: bool = victim.global_position.y > lava.surface_altitude
	victim.queue_free()

	if not died:
		print("[FAIL] lave : le cobaye en est sorti vivant")
		return 1
	if not out:
		print("[FAIL] lave : le corps reste dans la coulée — irrécupérable")
		return 1
	if not above:
		print("[FAIL] lave : le corps est éjecté SOUS la surface")
		return 1
	print("[OK] the_lava_kills (mort, corps posé sur la berge à %.0f m du lit)"
		% absf(landed.y - lava.center.y))
	return 0


## ON DOIT POUVOIR CONTOURNER LE PONT, ET PASSER DESSOUS.
##
## Demandé en jeu : « le joueur peut passer à droite et à gauche du pont pour
## explorer en dessous ». C'est ce qui interdit d'en faire une chaussée
## continue : un ouvrage qui traverse tout le cirque le coupe en deux, et
## l'espace sous lui cesse d'exister.
##
## Deux choses à prouver, donc — qu'on passe À CÔTÉ, et qu'il y a quelque chose
## SOUS lui où poser les pieds.
func _test_you_can_go_around_and_under_the_bridge() -> int:
	var bridge: ForgeBridge = _world.get_node_or_null("PontSuspendu") as ForgeBridge
	var region: NavigationRegion3D = _world.get_node_or_null("Navigation") as NavigationRegion3D
	if bridge == null or region == null:
		print("[FAIL] contournement : pont ou navigation absents")
		return 1
	var map: RID = region.get_navigation_map()

	# 1. LA CORNICHE existe et porte : elle doit être sèche, et sur le navmesh.
	var lava: CavernLake = _terrain.lake
	var ledge := Vector2(0.0, -3.8)
	var ledge_ground: float = _ground(ledge)
	if ledge_ground < lava.surface_altitude + 0.5:
		print("[FAIL] corniche : à %.2f m, la lave est à %.2f m — noyée"
			% [ledge_ground, lava.surface_altitude])
		return 1
	var ledge_point := Vector3(ledge.x, ledge_ground, ledge.y)
	var on_mesh: Vector3 = NavigationServer3D.map_get_closest_point(map, ledge_point)
	if on_mesh.distance_to(ledge_point) > 2.5:
		print("[FAIL] corniche : à %.1f m du navmesh — on n'y accède pas"
			% on_mesh.distance_to(ledge_point))
		return 1

	# 2. Elle passe bien SOUS le tablier, et avec de la hauteur pour un joueur.
	var deck_here: float = bridge.deck_altitude_at(
		clampf((bridge.from_point.y - ledge.y)
			/ maxf(bridge.from_point.y - bridge.to_point.y, 0.001), 0.0, 1.0))
	var headroom: float = deck_here - ledge_ground
	if headroom < 1.9:
		print("[FAIL] corniche : %.2f m sous le tablier — on ne tient pas debout" % headroom)
		return 1

	# 3. ON PASSE À CÔTÉ : un chemin d'une rive à l'autre du pont qui ne monte
	#    jamais dessus. Sans ce contrôle, le pont pourrait devenir le seul
	#    passage sans que rien ne le signale.
	var west := Vector3(-22.0, _ground(Vector2(-22.0, 6.0)), 6.0)
	var east := Vector3(22.0, _ground(Vector2(22.0, 6.0)), 6.0)
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map,
		NavigationServer3D.map_get_closest_point(map, west),
		NavigationServer3D.map_get_closest_point(map, east), true)
	if path.size() < 2:
		print("[FAIL] contournement : aucun chemin d'une rive à l'autre")
		return 1
	# Le critère n'est PAS l'altitude : au sud, le tablier est au niveau du sol
	# par construction, donc « plus haut que le pont » ne distingue pas marcher
	# sur l'ouvrage de marcher devant. Le critère est de ne pas SURVOLER la
	# coulée — seul le pont permet ça.
	for point in path:
		if _in_lava(Vector2(point.x, point.z), lava):
			print("[FAIL] contournement : le chemin survole la coulée — il emprunte le pont")
			return 1

	print("[OK] you_can_go_around_and_under_the_bridge (corniche à %.2f m, %.2f m sous le tablier)"
		% [ledge_ground, headroom])
	return 0


## LE DÉTOUR MÈNE QUELQUE PART.
##
## La chaîne n'a de sens que bout à bout : le sentier ne sert que parce qu'il
## finit sur un saut, le levier ouvre une rampe qu'on ne peut pas encore
## atteindre, et le pylône ne fabrique un chemin que pour revenir de là où le
## levier se trouve. Tester chaque pièce séparément laisserait passer le seul
## défaut qui compte — qu'elles ne s'enchaînent pas.
func _test_the_detour_opens_the_tower() -> int:
	var trail: MountainTrail = _world.get_node_or_null("SentierDeLaMontagne") as MountainTrail
	var belvedere: ForgeLedge = _world.get_node_or_null("BelvedereDeLaCascade") as ForgeLedge
	var perch: ForgeLedge = _world.get_node_or_null("PalierDuLevier") as ForgeLedge
	var lever: ForgeLever = _world.get_node_or_null("LevierCache") as ForgeLever
	var ramp: KeepSpiralRamp = _world.get_node_or_null("RampeDuDonjon") as KeepSpiralRamp
	var pylon: FragilePylon = _world.get_node_or_null("PyloneFragile") as FragilePylon
	if trail == null or belvedere == null or perch == null or lever == null \
			or ramp == null or pylon == null:
		print("[FAIL] détour : pièce manquante (sentier/belvédère/palier/levier/rampe/pylône)")
		return 1

	# 1. LE SENTIER se monte. Une pente au-delà de ce que le joueur gravit en
	#    ferait un décor, et rien dans le jeu ne le dirait.
	var steepest: float = trail.steepest_slope()
	if steepest > MountainTrail.MAX_SLOPE_DEGREES:
		print("[FAIL] sentier : %.1f° au plus raide, au-delà de %.0f°"
			% [steepest, MountainTrail.MAX_SLOPE_DEGREES])
		return 1

	# 2. IL PART DERRIÈRE LE POINT D'APPARITION. C'est ce qui en fait une
	#    découverte : un sentier devant soi est un couloir.
	var spawn: Node3D = _world.get_node_or_null("PlayerSpawnPoints/Spawn0") as Node3D
	var head: Vector3 = trail.waypoints[0]
	if head.z < spawn.global_position.z:
		print("[FAIL] sentier : il démarre devant le spawn (z=%.0f contre %.0f)"
			% [head.z, spawn.global_position.z])
		return 1

	# 3. ON PEUT Y POSER LES PIEDS, SUR TOUTE SA LONGUEUR.
	#
	# On l'éprouve par la PHYSIQUE et non par le navmesh, et c'est un choix.
	# Les joueurs marchent par collision ; le navmesh ne sert qu'aux ennemis, et
	# il n'y en a pas là-haut. Or ce sentier se cuit en îlot — les blocs posés
	# sur le terrain forment une surface que Recast ne raccorde pas à celle du
	# sol —, ce qui n'empêche personne de le gravir mais ferait échouer un test
	# de navigation. Mesurer ce qu'on ne joue pas est le meilleur moyen de
	# corriger ce qui n'était pas cassé.
	var space: PhysicsDirectSpaceState3D = _world.get_world_3d().direct_space_state
	var line: PackedVector3Array = trail.call("_smoothed")
	for i in line.size():
		var above: Vector3 = line[i] + Vector3(0.0, 2.0, 0.0)
		var query := PhysicsRayQueryParameters3D.create(above,
			line[i] - Vector3(0.0, 1.2, 0.0))
		query.collision_mask = CavernTerrainBuilder.WORLD_COLLISION_LAYER
		var hit: Dictionary = space.intersect_ray(query)
		if hit.is_empty():
			print("[FAIL] sentier : rien sous les pieds au point %d %s" % [i, line[i]])
			return 1
		var normal: Vector3 = hit["normal"]
		var tilt: float = rad_to_deg(acos(clampf(normal.dot(Vector3.UP), -1.0, 1.0)))
		if tilt > 45.0:
			print("[FAIL] sentier : %.0f° sous les pieds au point %d — on y glisse"
				% [tilt, i])
			return 1

	# 3. LE SAUT. Ni un pas, ni un gouffre — et vers le BAS, sinon on repart en
	#    sens inverse et le pylône ne sert à rien.
	var gap: float = (perch.centre.y + perch.half_extent.y) \
		- (belvedere.centre.y - belvedere.half_extent.y)
	gap = absf(gap)
	if gap < 3.0 or gap > 7.5:
		print("[FAIL] saut : %.1f m — hors de ce qu'on franchit d'un élan" % gap)
		return 1
	var fall: float = belvedere.altitude - perch.altitude
	if fall < 2.0:
		print("[FAIL] saut : %.1f m de dénivelé — on pourrait revenir en sautant" % fall)
		return 1

	var region: NavigationRegion3D = _world.get_node_or_null("Navigation") as NavigationRegion3D
	var map: RID = region.get_navigation_map()

	# 4. LE SENTIER DÉBOUCHE SUR LE BELVÉDÈRE. Il doit finir DESSUS, pas à côté
	#    — un sentier qui s'arrête trois mètres avant est un cul-de-sac.
	var last: Vector3 = line[line.size() - 1]
	var belvedere_point := Vector3(belvedere.centre.x, belvedere.altitude, belvedere.centre.y)
	if absf(last.x - belvedere_point.x) > belvedere.half_extent.x \
			or absf(last.z - belvedere_point.z) > belvedere.half_extent.y \
			or absf(last.y - belvedere_point.y) > 0.6:
		print("[FAIL] sentier : il finit en %s, le belvédère est en %s"
			% [last, belvedere_point])
		return 1

	# 5. LE PALIER EST ISOLÉ : rien ne le touche, seul le saut y mène.
	var perch_point := Vector3(perch.centre.x, perch.altitude, perch.centre.y)

	# 6. LA RAMPE est cachée tant que le levier n'a pas été tiré.
	if ramp.is_deployed():
		print("[FAIL] rampe : déjà déployée avant le levier")
		return 1
	if not lever.try_interact(null):
		print("[FAIL] levier : il ne répond pas")
		return 1
	if not pylon.try_interact(null):
		print("[FAIL] pylône : il ne tombe pas")
		return 1

	# On attend en TEMPS RÉEL, pas en frames : en headless elles défilent bien
	# plus vite que 1/60 s, et compter des frames revenait à ne pas attendre.
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 12000 \
			and not (ramp.is_deployed() and pylon.has_fallen()):
		await process_frame
	if not ramp.is_deployed():
		print("[FAIL] rampe : le levier ne l'a pas déployée")
		return 1
	if not pylon.has_fallen():
		print("[FAIL] pylône : il n'est pas tombé")
		return 1

	# 7. LE PYLÔNE COUCHÉ SE DESCEND. Il tombe d'un palier haut vers une berge
	#    basse : c'est une rampe, et une rampe trop raide est un précipice.
	var slope: float = pylon.resting_slope_degrees()
	if slope > 45.0:
		print("[FAIL] pylône : %.0f° une fois couché — indescendable" % slope)
		return 1
	if pylon.get_node_or_null("ColTablierPylone") == null:
		print("[FAIL] pylône : aucun tablier après la chute")
		return 1

	# 8. ET LA RAMPE MÈNE AU BOSS. C'est la promesse du détour tout entier.
	await process_frame
	await process_frame
	var top: Vector3 = ramp.get_summit()
	var arena: Node3D = _world.get_node_or_null("BossArena/BossSpawn") as Node3D
	var to_top: Vector3 = NavigationServer3D.map_get_closest_point(map, top)
	if to_top.distance_to(top) > 4.0:
		print("[FAIL] rampe : le sommet est à %.0f m du navmesh" % to_top.distance_to(top))
		return 1
	var path: PackedVector3Array = NavigationServer3D.map_get_path(map, to_top,
		NavigationServer3D.map_get_closest_point(map, arena.global_position), true)
	if path.size() < 2:
		print("[FAIL] rampe : aucun chemin du sommet vers l'arène")
		return 1

	print("[OK] the_detour_opens_the_tower (sentier %.0f°, saut de %.1f m en descendant de %.0f m, pylône à %.0f°)"
		% [steepest, gap, fall, slope])
	return 0


## LA PORTE DONNE SUR UNE SALLE.
##
## Signalé en jeu : « le sceau descend mais aucun passage ne s'ouvre ». Le
## donjon était un cylindre plein — un seul collider en boîte — et le mécanisme
## des miroirs récompensait donc par une animation devant un mur.
##
## On vérifie les deux moitiés : que le sceau S'EFFACE vraiment (collision
## comprise, pas seulement la couleur), et qu'il y a quelque chose derrière.
func _test_the_gate_opens_onto_a_room() -> int:
	var _castle: ForgeCastle = _world.get_node_or_null("Chateau") as ForgeCastle
	if _castle == null:
		print("[FAIL] salle : pas de château")
		return 1

	# Un intérieur creux : des murs par pans, et un vide au sud.
	var walls: int = 0
	for child in _castle.get_children():
		var body: StaticBody3D = child as StaticBody3D
		if body != null and body.name.begins_with("Col_Pan_"):
			walls += 1
	if walls == 0:
		print("[FAIL] salle : le donjon est plein — la porte ouvre sur un mur")
		return 1
	if walls >= 8:
		print("[FAIL] salle : %d pans, aucun n'est ouvert — on ne peut pas entrer" % walls)
		return 1

	if _castle.get_node_or_null("SolDuDonjon") == null:
		print("[FAIL] salle : aucun sol — on tomberait au travers")
		return 1

	# ET LE SCEAU S'EFFACE. C'est sa collision qui compte : un battant devenu
	# transparent mais toujours solide serait le même défaut sous un autre nom.
	_castle.open_gate()
	var started: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - started < 8000:
		await process_frame
		var blocking: bool = false
		for child in _castle.get_children():
			var body: StaticBody3D = child as StaticBody3D
			if body != null and body.name.begins_with("Col_Sceau"):
				blocking = true
		if not blocking:
			print("[OK] the_gate_opens_onto_a_room (%d pans, un ouvert, sceau effacé)" % walls)
			return 0

	print("[FAIL] sceau : sa collision est toujours là après l'ouverture")
	return 1

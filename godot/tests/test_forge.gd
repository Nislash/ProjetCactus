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
			if slope > worst:
				worst = slope
				worst_at = at
			a += 0.35
		r += 3.0

	if worst > _terrain.max_slope_degrees + 2.0:
		print("[FAIL] pentes : %.1f° en (%.0f, %.0f), au-delà du plafond de %.0f°"
			% [worst, worst_at.x, worst_at.y, _terrain.max_slope_degrees])
		return 1
	print("[OK] slopes_stay_walkable (max %.1f°)" % worst)
	return 0


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

	# Et son tablier doit passer AU-DESSUS de la coulée, pas dedans.
	if bridge.deck_altitude < lava.surface_altitude + 3.0:
		print("[FAIL] pont : tablier à %.1f m, la lave est à %.1f m"
			% [bridge.deck_altitude, lava.surface_altitude])
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

	var threshold := Vector3(far.x, bridge.deck_altitude, far.y)
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

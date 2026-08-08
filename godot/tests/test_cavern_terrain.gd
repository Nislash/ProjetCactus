extends SceneTree

## Tests du générateur de terrain de la caverne. Lancer via :
##   godot --headless --path godot --script tests/test_cavern_terrain.gd
##
## Pas de framework GUT (convention du projet, cf tests/test_relics.gd).
##
## Ces tests portent sur les FONCTIONS PURES du générateur, indépendamment de
## toute scène : la silhouette, les primitives de relief, la fermeture du volume
## et l'orientation des faces. Les contraintes dures du plan sont des assertions
## sur des nombres — c'est précisément pour ça que le terrain est généré depuis
## de la donnée plutôt que sculpté.

const EPSILON := 0.001


func _init() -> void:
	var failed: int = 0
	failed += _test_dimensions()
	failed += _test_plateau_altitude()
	failed += _test_ramp_interpolation()
	failed += _test_basin_is_rimmed()
	failed += _test_basin_flat_bottom()
	failed += _test_min_falloff_rule()
	failed += _test_chamber_mask_defines_the_volume()
	failed += _test_corridor_joins_two_rooms()
	failed += _test_volume_closes_outside_chambers()
	failed += _test_sky_opening_is_elliptical()
	failed += _test_surfaces_face_the_right_way()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — tous les tests passent")
		quit(0)


# ---------------------------------------------------------------------------
# Fabriques
# ---------------------------------------------------------------------------

func _make_terrain(spec: CavernHeightfieldSpec) -> CavernTerrainData:
	var terrain := CavernTerrainData.new()
	terrain.bounds_min = Vector2(-20.0, -20.0)
	terrain.bounds_max = Vector2(20.0, 20.0)
	terrain.cell_size = 1.0
	terrain.floor_field = spec
	terrain.chambers = [_room(Vector2.ZERO, Vector2(15.0, 15.0), 12.0, 4.0)]
	return terrain


func _flat_spec(altitude: float) -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	spec.base_altitude = altitude
	return spec


func _room(center: Vector2, radii: Vector2, headroom: float, softness: float) -> CavernChamber:
	var c := CavernChamber.new()
	c.center = center
	c.radii = radii
	c.headroom = headroom
	c.edge_softness = softness
	return c


# ---------------------------------------------------------------------------
# Grille et primitives de relief
# ---------------------------------------------------------------------------

func _test_dimensions() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	var dims: Vector2i = CavernTerrainBuilder.grid_dimensions(terrain)
	if dims != Vector2i(41, 41):
		print("[FAIL] dimensions : attendu 41x41, obtenu %s" % dims)
		return 1
	if CavernTerrainBuilder.sample_field(terrain, terrain.floor_field).size() != 41 * 41:
		print("[FAIL] dimensions : taille du champ incohérente")
		return 1
	if not CavernTerrainBuilder.sample_position(terrain, 40, 40).is_equal_approx(Vector2(20.0, 20.0)):
		print("[FAIL] dimensions : coin max mal placé")
		return 1
	print("[OK] dimensions")
	return 0


func _test_plateau_altitude() -> int:
	var spec := _flat_spec(0.0)
	var plateau := CavernPlateau.new()
	plateau.center = Vector2.ZERO
	plateau.half_extent = Vector2(5.0, 5.0)
	plateau.altitude = 6.0
	plateau.falloff = 5.0
	spec.plateaus = [plateau]

	if absf(CavernTerrainBuilder.sample_point(spec, Vector2.ZERO, null) - 6.0) > EPSILON:
		print("[FAIL] plateau : le centre n'est pas à l'altitude déclarée")
		return 1
	if absf(CavernTerrainBuilder.sample_point(spec, Vector2(30.0, 0.0), null)) > EPSILON:
		print("[FAIL] plateau : influence au-delà du falloff")
		return 1
	# Zone de fondu : strictement entre les deux, donc pas de marche.
	var mid: float = CavernTerrainBuilder.sample_point(spec, Vector2(7.5, 0.0), null)
	if mid <= EPSILON or mid >= 6.0 - EPSILON:
		print("[FAIL] plateau : fondu à %.3f, attendu strictement entre 0 et 6" % mid)
		return 1
	print("[OK] plateau_altitude")
	return 0


func _test_ramp_interpolation() -> int:
	var spec := _flat_spec(0.0)
	var ramp := CavernRamp.new()
	ramp.from_point = Vector2(-10.0, 0.0)
	ramp.to_point = Vector2(10.0, 0.0)
	ramp.from_altitude = 0.0
	ramp.to_altitude = 10.0
	ramp.width = 4.0
	ramp.falloff = 2.0
	spec.ramps = [ramp]

	for probe in [[Vector2(-10.0, 0.0), 0.0], [Vector2(0.0, 0.0), 5.0], [Vector2(10.0, 0.0), 10.0]]:
		if absf(CavernTerrainBuilder.sample_point(spec, probe[0], null) - probe[1]) > EPSILON:
			print("[FAIL] rampe : altitude incorrecte en %s" % probe[0])
			return 1
	# Pas d'extrapolation au-delà de l'arrivée.
	if CavernTerrainBuilder.sample_point(spec, Vector2(18.0, 0.0), null) > 10.0 + EPSILON:
		print("[FAIL] rampe : extrapolation au-delà de l'arrivée")
		return 1
	print("[OK] ramp_interpolation")
	return 0


## LE test anti-chute : autour d'un creux, le terrain doit REMONTER au-dessus du
## niveau environnant avant de redescendre.
func _test_basin_is_rimmed() -> int:
	var spec := _flat_spec(0.0)
	var basin := CavernBasin.new()
	basin.center = Vector2.ZERO
	basin.radii = Vector2(6.0, 6.0)
	basin.depth = 2.0
	basin.rim_height = 0.5
	basin.rim_width = 3.0
	spec.basins = [basin]

	if absf(CavernTerrainBuilder.sample_point(spec, Vector2.ZERO, null) + 2.0) > EPSILON:
		print("[FAIL] cuvette : profondeur incorrecte")
		return 1
	if CavernTerrainBuilder.sample_point(spec, Vector2(6.2, 0.0), null) <= 0.0:
		print("[FAIL] cuvette NON BORDÉE : pas de margelle, chute possible")
		return 1
	if absf(CavernTerrainBuilder.sample_point(spec, Vector2(12.0, 0.0), null)) > EPSILON:
		print("[FAIL] cuvette : la margelle ne retombe pas")
		return 1

	# Profil monotone du fond vers le bord : pas de contre-pente qui piégerait
	# un joueur dans un sous-creux.
	var previous: float = -2.0
	for i in range(1, 61):
		var h: float = CavernTerrainBuilder.sample_point(spec, Vector2(float(i) * 0.1, 0.0), null)
		if h < previous - EPSILON:
			print("[FAIL] cuvette : contre-pente à r=%.1f" % (float(i) * 0.1))
			return 1
		previous = h
	print("[OK] basin_is_rimmed")
	return 0


## Un lac exige un LIT PLAT. Sans fond plat, la cuvette descend en pointe et la
## nappe posée dessus se réduit à une flaque.
func _test_basin_flat_bottom() -> int:
	var spec := _flat_spec(0.0)
	var basin := CavernBasin.new()
	basin.center = Vector2.ZERO
	basin.radii = Vector2(10.0, 10.0)
	basin.depth = 3.0
	basin.rim_height = 0.5
	basin.rim_width = 3.0
	basin.flat_bottom = 0.6
	spec.basins = [basin]

	# Tout l'intérieur du fond plat est à la profondeur pleine.
	for r in [0.0, 2.0, 4.0, 5.9]:
		if absf(CavernTerrainBuilder.sample_point(spec, Vector2(r, 0.0), null) + 3.0) > EPSILON:
			print("[FAIL] fond plat : r=%.1f n'est pas à -3.0" % r)
			return 1
	# Et il remonte au-delà.
	if CavernTerrainBuilder.sample_point(spec, Vector2(8.0, 0.0), null) <= -3.0 + EPSILON:
		print("[FAIL] fond plat : ne remonte pas au-delà de la zone plate")
		return 1
	print("[OK] basin_flat_bottom")
	return 0


## Verrouille la règle de dimensionnement : le fondu des primitives est un
## smoothstep, dont la pente MAXIMALE vaut 1,5 fois la pente moyenne.
func _test_min_falloff_rule() -> int:
	for target_slope in [15.0, 22.0, 30.0]:
		var spec := _flat_spec(0.0)
		var plateau := CavernPlateau.new()
		plateau.center = Vector2.ZERO
		plateau.half_extent = Vector2(3.0, 3.0)
		plateau.altitude = 6.0
		plateau.falloff = CavernTerrainBuilder.min_falloff_for(6.0, target_slope)
		spec.plateaus = [plateau]

		var worst: float = 0.0
		var step: float = 0.05
		var previous: float = CavernTerrainBuilder.sample_point(spec, Vector2(3.0, 0.0), null)
		var r: float = 3.0 + step
		while r <= 3.0 + plateau.falloff:
			var h: float = CavernTerrainBuilder.sample_point(spec, Vector2(r, 0.0), null)
			worst = maxf(worst, rad_to_deg(atan2(absf(h - previous), step)))
			previous = h
			r += step

		if worst > target_slope + 0.5:
			print("[FAIL] min_falloff_for(%.0f°) : pente réelle %.1f°" % [target_slope, worst])
			return 1
	print("[OK] min_falloff_rule")
	return 0


# ---------------------------------------------------------------------------
# Silhouette et fermeture du volume
# ---------------------------------------------------------------------------

## La caverne existe là où une chambre la déclare, et NULLE PART ailleurs.
func _test_chamber_mask_defines_the_volume() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	terrain.chambers = [_room(Vector2(0.0, 0.0), Vector2(10.0, 6.0), 12.0, 5.0)]

	if CavernTerrainBuilder.chamber_mask(terrain, Vector2.ZERO) < 1.0 - EPSILON:
		print("[FAIL] masque : le centre d'une chambre doit valoir 1")
		return 1
	if CavernTerrainBuilder.chamber_mask(terrain, Vector2(60.0, 0.0)) > EPSILON:
		print("[FAIL] masque : la roche pleine doit valoir 0")
		return 1
	# La transition est continue : ni marche, ni saut.
	var boundary: float = CavernTerrainBuilder.chamber_mask(terrain, Vector2(12.0, 0.0))
	if boundary <= EPSILON or boundary >= 1.0 - EPSILON:
		print("[FAIL] masque : la bordure vaut %.3f, attendu strictement entre 0 et 1" % boundary)
		return 1

	# Une ellipse tournée doit suivre sa rotation, sinon toutes les salles
	# seraient alignées sur les axes.
	var rotated := _room(Vector2.ZERO, Vector2(10.0, 3.0), 12.0, 1.0)
	rotated.rotation_degrees = 90.0
	terrain.chambers = [rotated]
	if CavernTerrainBuilder.chamber_mask(terrain, Vector2(0.0, 8.0)) <= 0.0:
		print("[FAIL] masque : la rotation de l'ellipse n'est pas appliquée")
		return 1
	if CavernTerrainBuilder.chamber_mask(terrain, Vector2(8.0, 0.0)) > 0.0:
		print("[FAIL] masque : la rotation de l'ellipse est appliquée à l'envers")
		return 1
	print("[OK] chamber_mask_defines_the_volume")
	return 0


## Un goulet doit VRAIMENT relier : le point milieu entre deux salles disjointes
## doit appartenir au volume, sinon les joueurs sont enfermés.
func _test_corridor_joins_two_rooms() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	var west := _room(Vector2(-30.0, 0.0), Vector2(8.0, 8.0), 12.0, 3.0)
	var east := _room(Vector2(30.0, 0.0), Vector2(8.0, 8.0), 12.0, 3.0)

	terrain.chambers = [west, east]
	if CavernTerrainBuilder.chamber_mask(terrain, Vector2.ZERO) > EPSILON:
		print("[FAIL] goulet : les deux salles ne devraient PAS se toucher sans couloir")
		return 1

	var corridor := CavernChamber.new()
	corridor.is_corridor = true
	corridor.center = Vector2(-24.0, 0.0)
	corridor.to_center = Vector2(24.0, 0.0)
	corridor.radii = Vector2(5.0, 5.0)
	corridor.headroom = 10.0
	corridor.edge_softness = 3.0
	terrain.chambers = [west, east, corridor]

	for x in [-20.0, -10.0, 0.0, 10.0, 20.0]:
		if CavernTerrainBuilder.chamber_mask(terrain, Vector2(x, 0.0)) < 1.0 - EPSILON:
			print("[FAIL] goulet : interruption du volume en x=%.0f" % x)
			return 1
	# Et il reste étroit : un couloir qui déborde n'est plus un couloir.
	if CavernTerrainBuilder.chamber_mask(terrain, Vector2(0.0, 20.0)) > EPSILON:
		print("[FAIL] goulet : le couloir déborde latéralement")
		return 1
	print("[OK] corridor_joins_two_rooms")
	return 0


## LA garantie d'étanchéité de la nouvelle architecture : hors des chambres, la
## hauteur libre vaut ZÉRO, donc voûte = sol et le volume se referme tout seul.
## Il n'y a plus de parois à générer ni de jonction à surveiller.
func _test_volume_closes_outside_chambers() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	terrain.chambers = [_room(Vector2.ZERO, Vector2(8.0, 8.0), 12.0, 4.0)]
	terrain.min_headroom = 10.0
	terrain.max_headroom = 15.0

	var dims: Vector2i = CavernTerrainBuilder.grid_dimensions(terrain)
	var floor_h: PackedFloat32Array = CavernTerrainBuilder.sample_field(terrain, terrain.floor_field)
	var vault_h: PackedFloat32Array = CavernTerrainBuilder.compose_vault(terrain, floor_h)

	var inside_ok: bool = false
	for iz in dims.y:
		for ix in dims.x:
			var i: int = iz * dims.x + ix
			var p: Vector2 = CavernTerrainBuilder.sample_position(terrain, ix, iz)
			var clearance: float = vault_h[i] - floor_h[i]
			var mask: float = CavernTerrainBuilder.chamber_mask(terrain, p)

			if mask <= 0.0 and clearance > EPSILON:
				print("[FAIL] fermeture : volume ouvert dans la roche pleine en (%.0f, %.0f)" % [p.x, p.y])
				return 1
			if mask >= 1.0:
				inside_ok = true
				if clearance < terrain.min_headroom - EPSILON or clearance > terrain.max_headroom + EPSILON:
					print("[FAIL] fermeture : hauteur libre %.2f m hors de [%.0f, %.0f] au cœur d'une chambre"
						% [clearance, terrain.min_headroom, terrain.max_headroom])
					return 1

	if not inside_ok:
		print("[FAIL] fermeture : aucun point au cœur d'une chambre — test vide")
		return 1
	print("[OK] volume_closes_outside_chambers")
	return 0


func _test_sky_opening_is_elliptical() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	var opening := CavernSkyOpening.new()
	opening.center = Vector2(5.0, -3.0)
	opening.radii = Vector2(8.0, 3.0)
	opening.rotation_degrees = 0.0
	terrain.sky_openings = [opening]

	if not CavernTerrainBuilder.is_in_sky_opening(terrain, Vector2(12.0, -3.0)):
		print("[FAIL] ouverture : le grand axe n'est pas respecté")
		return 1
	if CavernTerrainBuilder.is_in_sky_opening(terrain, Vector2(5.0, 1.0)):
		print("[FAIL] ouverture : le petit axe n'est pas respecté")
		return 1

	opening.rotation_degrees = 90.0
	if CavernTerrainBuilder.is_in_sky_opening(terrain, Vector2(12.0, -3.0)):
		print("[FAIL] ouverture : la rotation n'est pas appliquée")
		return 1
	if not CavernTerrainBuilder.is_in_sky_opening(terrain, Vector2(5.0, 3.0)):
		print("[FAIL] ouverture : la rotation est appliquée à l'envers")
		return 1
	print("[OK] sky_opening_is_elliptical")
	return 0


## Le sol doit présenter ses faces vers le HAUT et la voûte vers le BAS. Sinon
## le culling arrière les rend invisibles et on voit le fond à travers.
##
## Ce défaut a survécu à toute la suite de tests parce qu'ils vérifiaient la
## GÉOMÉTRIE et jamais l'ORIENTATION — et la collision, indépendante du
## maillage, laissait marcher sur un sol qu'on ne voyait pas.
func _test_surfaces_face_the_right_way() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	var builder := CavernTerrainBuilder.new()
	builder.data = terrain
	builder.build_on_ready = false
	root.add_child(builder)
	builder.build()

	for probe in [["Floor", 1.0], ["Vault", -1.0]]:
		var surface: Node = builder.get_node_or_null(probe[0])
		if surface == null or surface.get_child_count() == 0:
			print("[FAIL] orientation : aucune tuile sous « %s »" % probe[0])
			builder.queue_free()
			return 1

		var mesh_instance: MeshInstance3D = surface.get_child(0).get_node_or_null("Mesh") as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			print("[FAIL] orientation : maillage introuvable sous « %s »" % probe[0])
			builder.queue_free()
			return 1

		var arrays: Array = (mesh_instance.mesh as ArrayMesh).surface_get_arrays(0)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var sampled: int = 0
		var i: int = 0
		while i + 2 < vertices.size() and sampled < 300:
			# CONVENTION : Godot considère comme face avant celle dont les
			# sommets tournent dans le sens HORAIRE vue de face — l'inverse de
			# la règle de la main droite. La normale est donc (c-a) × (b-a).
			var winding: Vector3 = (vertices[i + 2] - vertices[i]).cross(vertices[i + 1] - vertices[i])
			if winding.length_squared() > 0.000001:
				sampled += 1
				if signf(winding.normalized().y) != probe[1]:
					var direction: String = "le haut" if probe[1] > 0.0 else "le bas"
					print("[FAIL] orientation « %s » : faces tournées à l'opposé de %s" % [probe[0], direction])
					builder.queue_free()
					return 1
				# Contrôle croisé : la normale que Godot a lui-même dérivée de
				# l'ordre des sommets doit pointer dans le même sens. Si les
				# deux divergent, c'est la convention ci-dessus qui est fausse.
				if normals.size() > i and signf(normals[i].y) != signf(winding.normalized().y):
					print("[FAIL] orientation « %s » : la convention du test contredit ARRAY_NORMAL" % probe[0])
					builder.queue_free()
					return 1
			i += 3

		if sampled == 0:
			print("[FAIL] orientation : aucun triangle exploitable sous « %s »" % probe[0])
			builder.queue_free()
			return 1

	builder.queue_free()
	print("[OK] surfaces_face_the_right_way (sol vers le haut, voûte vers le bas)")
	return 0

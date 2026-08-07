extends SceneTree

## Tests du générateur de terrain de la caverne (E2 #9/#11). Lancer via :
##   godot --headless --path godot --script tests/test_cavern_terrain.gd
##
## Pas de framework GUT (convention du projet, cf tests/test_relics.gd).
##
## Ces tests portent sur le CHAMP DE HAUTEURS, pas sur le rendu : les
## contraintes dures du plan (« aucune chute possible », « pentes praticables »,
## « voûte 10-15 m ») sont des assertions sur des nombres, et c'est exactement
## pour ça que le terrain est généré depuis de la donnée plutôt que sculpté.

const EPSILON := 0.001


func _init() -> void:
	var failed: int = 0
	failed += _test_dimensions()
	failed += _test_plateau_altitude()
	failed += _test_ramp_interpolation()
	failed += _test_basin_is_rimmed()
	failed += _test_slope_stays_walkable()
	failed += _test_sky_well_detection()
	failed += _test_min_falloff_rule()

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
	terrain.vault_field = spec
	return terrain


func _flat_spec(altitude: float) -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	spec.base_altitude = altitude
	return spec


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

func _test_dimensions() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	var dims: Vector2i = CavernTerrainBuilder.grid_dimensions(terrain)
	if dims != Vector2i(41, 41):
		print("[FAIL] dimensions : attendu 41x41, obtenu %s" % dims)
		return 1
	var heights: PackedFloat32Array = CavernTerrainBuilder.sample_field(terrain, terrain.floor_field)
	if heights.size() != 41 * 41:
		print("[FAIL] dimensions : champ de taille %d au lieu de %d" % [heights.size(), 41 * 41])
		return 1
	# Les bornes doivent tomber exactement sur les coins de l'emprise.
	if not CavernTerrainBuilder.sample_position(terrain, 0, 0).is_equal_approx(Vector2(-20.0, -20.0)):
		print("[FAIL] dimensions : origine mal placée")
		return 1
	if not CavernTerrainBuilder.sample_position(terrain, 40, 40).is_equal_approx(Vector2(20.0, 20.0)):
		print("[FAIL] dimensions : coin max mal placé")
		return 1
	print("[OK] dimensions")
	return 0


func _test_plateau_altitude() -> int:
	var spec := _flat_spec(0.0)
	var plateau := CavernPlateau.new()
	plateau.label = "test"
	plateau.center = Vector2.ZERO
	plateau.half_extent = Vector2(5.0, 5.0)
	plateau.altitude = 6.0
	plateau.falloff = 5.0
	spec.plateaus = [plateau]

	# Au centre : l'altitude du plateau, exactement.
	var at_center: float = CavernTerrainBuilder.sample_point(spec, Vector2.ZERO, null)
	if absf(at_center - 6.0) > EPSILON:
		print("[FAIL] plateau : centre à %.3f au lieu de 6.0" % at_center)
		return 1

	# Bien au-delà du falloff : retour au terrain de base.
	var far: float = CavernTerrainBuilder.sample_point(spec, Vector2(30.0, 0.0), null)
	if absf(far) > EPSILON:
		print("[FAIL] plateau : loin = %.3f au lieu de 0.0" % far)
		return 1

	# Dans la zone de fondu : strictement entre les deux, donc pas de marche.
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

	var start: float = CavernTerrainBuilder.sample_point(spec, Vector2(-10.0, 0.0), null)
	var middle: float = CavernTerrainBuilder.sample_point(spec, Vector2(0.0, 0.0), null)
	var finish: float = CavernTerrainBuilder.sample_point(spec, Vector2(10.0, 0.0), null)

	if absf(start) > EPSILON:
		print("[FAIL] rampe : départ à %.3f au lieu de 0.0" % start)
		return 1
	if absf(middle - 5.0) > EPSILON:
		print("[FAIL] rampe : milieu à %.3f au lieu de 5.0" % middle)
		return 1
	if absf(finish - 10.0) > EPSILON:
		print("[FAIL] rampe : arrivée à %.3f au lieu de 10.0" % finish)
		return 1

	# Au-delà de l'arrivée, l'altitude est bornée (pas d'extrapolation).
	var beyond: float = CavernTerrainBuilder.sample_point(spec, Vector2(18.0, 0.0), null)
	if beyond > 10.0 + EPSILON:
		print("[FAIL] rampe : extrapolation au-delà de l'arrivée (%.3f)" % beyond)
		return 1
	print("[OK] ramp_interpolation")
	return 0


## LE test anti-chute : une cuvette doit être bordée. Autour du creux, le
## terrain doit REMONTER au-dessus du niveau environnant avant de redescendre.
func _test_basin_is_rimmed() -> int:
	var spec := _flat_spec(0.0)
	var basin := CavernBasin.new()
	basin.center = Vector2.ZERO
	basin.radii = Vector2(6.0, 6.0)
	basin.depth = 2.0
	basin.rim_height = 0.5
	basin.rim_width = 3.0
	spec.basins = [basin]

	var bottom: float = CavernTerrainBuilder.sample_point(spec, Vector2.ZERO, null)
	if absf(bottom + 2.0) > EPSILON:
		print("[FAIL] cuvette : fond à %.3f au lieu de -2.0" % bottom)
		return 1

	# Juste à l'extérieur du bord : la margelle culmine.
	var rim: float = CavernTerrainBuilder.sample_point(spec, Vector2(6.2, 0.0), null)
	if rim <= 0.0:
		print("[FAIL] cuvette NON BORDÉE : margelle à %.3f, attendu > 0 (chute possible)" % rim)
		return 1

	# La margelle retombe au niveau du terrain une fois passée sa largeur.
	var beyond: float = CavernTerrainBuilder.sample_point(spec, Vector2(12.0, 0.0), null)
	if absf(beyond) > EPSILON:
		print("[FAIL] cuvette : la margelle ne retombe pas (%.3f)" % beyond)
		return 1

	# Le profil doit être monotone du fond vers le bord : pas de contre-pente
	# qui piégerait un joueur dans un sous-creux.
	var previous: float = bottom
	for i in range(1, 61):
		var r: float = float(i) * 0.1
		var h: float = CavernTerrainBuilder.sample_point(spec, Vector2(r, 0.0), null)
		if h < previous - EPSILON:
			print("[FAIL] cuvette : contre-pente à r=%.1f (%.3f < %.3f)" % [r, h, previous])
			return 1
		previous = h
	print("[OK] basin_is_rimmed")
	return 0


## Vérifie qu'un relief configuré selon la spec créative reste praticable :
## aucune pente ne dépasse le plafond déclaré dans les données.
func _test_slope_stays_walkable() -> int:
	var spec := _flat_spec(0.0)

	# Cas représentatif de ce qu'on authore vraiment : une zone haute, une rampe
	# qui en descend, et une cuvette bordée à l'écart. Toutes les transitions
	# sont dimensionnées par `min_falloff_for`, jamais à l'œil.
	# Cible de transition volontairement SOUS le plafond de 25° : les ondulations
	# de surface ajoutent leur propre gradient par-dessus. Dimensionner les
	# transitions pile au plafond garantit de le dépasser une fois le bruit posé.
	const TARGET := 16.0

	var plateau := CavernPlateau.new()
	plateau.center = Vector2(-14.0, 0.0)
	plateau.half_extent = Vector2(3.0, 4.0)
	plateau.altitude = 3.0
	plateau.falloff = CavernTerrainBuilder.min_falloff_for(3.0, TARGET)
	spec.plateaus = [plateau]

	var ramp := CavernRamp.new()
	ramp.from_point = Vector2(-6.0, 0.0)
	ramp.to_point = Vector2(4.0, 0.0)
	ramp.from_altitude = 3.0
	ramp.to_altitude = 0.0
	ramp.width = 8.0
	ramp.falloff = CavernTerrainBuilder.min_falloff_for(3.0, TARGET)
	spec.ramps = [ramp]

	# Cuvette posée à l'écart de la rampe : les cuvettes s'AJOUTENT au relief
	# (les plateaux et rampes, eux, se fondent vers une cible). Superposer une
	# cuvette à une pente cumule donc les deux -- c'est le piège d'authoring que
	# ce test a levé, consigné dans l'ADR.
	var basin := CavernBasin.new()
	basin.center = Vector2(13.0, 0.0)
	var basin_span: float = CavernTerrainBuilder.min_falloff_for(1.0 + 0.4, TARGET)
	basin.radii = Vector2(basin_span, basin_span)
	basin.depth = 1.0
	basin.rim_height = 0.4
	basin.rim_width = CavernTerrainBuilder.min_falloff_for(0.4, TARGET)
	spec.basins = [basin]

	spec.noise_amplitude = 0.2
	spec.noise_scale = 12.0

	var terrain := _make_terrain(spec)
	terrain.max_slope_degrees = 25.0
	var heights: PackedFloat32Array = CavernTerrainBuilder.sample_field(terrain, spec)
	var dims: Vector2i = CavernTerrainBuilder.grid_dimensions(terrain)

	var worst: float = 0.0
	var worst_at := Vector2i.ZERO
	for iz in dims.y:
		for ix in dims.x:
			var h: float = heights[iz * dims.x + ix]
			if ix + 1 < dims.x:
				var slope_x: float = _slope_degrees(h, heights[iz * dims.x + ix + 1], terrain.cell_size)
				if slope_x > worst:
					worst = slope_x
					worst_at = Vector2i(ix, iz)
			if iz + 1 < dims.y:
				var slope_z: float = _slope_degrees(h, heights[(iz + 1) * dims.x + ix], terrain.cell_size)
				if slope_z > worst:
					worst = slope_z
					worst_at = Vector2i(ix, iz)

	if worst > terrain.max_slope_degrees:
		print("[FAIL] pente : %.1f° en %s, plafond %.1f°" % [worst, worst_at, terrain.max_slope_degrees])
		return 1
	print("[OK] slope_stays_walkable (pente max %.1f°)" % worst)
	return 0


func _slope_degrees(h_a: float, h_b: float, run: float) -> float:
	return rad_to_deg(atan2(absf(h_b - h_a), run))


## Verrouille la règle de dimensionnement : un fondu calculé par
## `min_falloff_for` doit effectivement tenir sous le plafond de pente visé.
func _test_min_falloff_rule() -> int:
	for target_slope in [15.0, 22.0, 30.0]:
		var delta: float = 6.0
		var spec := _flat_spec(0.0)
		var plateau := CavernPlateau.new()
		plateau.center = Vector2.ZERO
		plateau.half_extent = Vector2(3.0, 3.0)
		plateau.altitude = delta
		plateau.falloff = CavernTerrainBuilder.min_falloff_for(delta, target_slope)
		spec.plateaus = [plateau]

		# Échantillonnage fin le long du fondu, là où la pente est maximale.
		var worst: float = 0.0
		var step: float = 0.05
		var previous: float = CavernTerrainBuilder.sample_point(spec, Vector2(3.0, 0.0), null)
		var r: float = 3.0 + step
		while r <= 3.0 + plateau.falloff:
			var h: float = CavernTerrainBuilder.sample_point(spec, Vector2(r, 0.0), null)
			worst = maxf(worst, _slope_degrees(previous, h, step))
			previous = h
			r += step

		if worst > target_slope + 0.5:
			print("[FAIL] min_falloff_for(%.0f°) : pente réelle %.1f°" % [target_slope, worst])
			return 1
	print("[OK] min_falloff_rule")
	return 0


func _test_sky_well_detection() -> int:
	var terrain := _make_terrain(_flat_spec(0.0))
	var well := CavernSkyWell.new()
	well.label = "P1"
	well.center = Vector2(5.0, -3.0)
	well.diameter = 8.0
	terrain.sky_wells = [well]

	if not CavernTerrainBuilder.is_in_sky_well(terrain, Vector2(5.0, -3.0)):
		print("[FAIL] puits : le centre devrait être dans le puits")
		return 1
	if not CavernTerrainBuilder.is_in_sky_well(terrain, Vector2(8.5, -3.0)):
		print("[FAIL] puits : un point à 3,5 m du centre devrait être dedans (rayon 4)")
		return 1
	if CavernTerrainBuilder.is_in_sky_well(terrain, Vector2(10.0, -3.0)):
		print("[FAIL] puits : un point à 5 m du centre devrait être dehors (rayon 4)")
		return 1
	print("[OK] sky_well_detection")
	return 0

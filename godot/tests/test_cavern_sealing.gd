extends SceneTree

## Étanchéité du volume de la caverne (E2 #11). Lancer via :
##   godot --headless --path godot --script tests/test_cavern_sealing.gd
##
## Prouve, sur le terrain RÉELLEMENT généré (`level01_cavern_terrain.tres`), les
## deux contraintes dures du plan que personne ne peut vérifier à l'œil :
##   1. VOLUME FERMÉ  — impossible de sortir
##   2. AUCUNE CHUTE  — impossible de tomber dans le vide
##
## Le choix d'un champ de hauteurs rend ces deux propriétés *structurelles*
## plutôt qu'accidentelles (cf ADR `docs/tech/level01_terrain.md`) : il reste à
## le démontrer, parce qu'une garantie non testée n'est qu'une intention.

const TERRAIN_PATH := "res://data/levels/level01_cavern_terrain.tres"

## Dénivelé maximal toléré entre deux échantillons voisins. Au-delà, c'est une
## falaise : on ne peut pas en mourir (il y a du sol en bas) mais on peut y
## rester coincé, et ce n'est pas ce que « praticable partout » veut dire.
const MAX_STEP_METERS := 1.4

## Part maximale d'échantillons autorisée au-dessus du plafond de pente. Les
## parois du bol d'arène en font partie : ce sont des murs, pas du sol, et un
## champ de hauteurs ne sait pas les distinguer. On borne donc leur étendue au
## lieu d'exiger zéro.
const MAX_OVER_CAP_RATIO := 0.02

var _terrain: CavernTerrainData
var _floor: PackedFloat32Array
var _vault: PackedFloat32Array
var _dims: Vector2i


func _init() -> void:
	_terrain = load(TERRAIN_PATH) as CavernTerrainData
	if _terrain == null:
		print("[FAIL] terrain introuvable : %s" % TERRAIN_PATH)
		print("       Générer d'abord : godot --headless --path godot --script tools/build_cavern_terrain.gd")
		quit(1)
		return

	_dims = CavernTerrainBuilder.grid_dimensions(_terrain)
	_floor = CavernTerrainBuilder.sample_field(_terrain, _terrain.floor_field)
	_vault = CavernTerrainBuilder.compose_vault(_terrain, _floor)

	var failed: int = 0
	failed += _test_ground_everywhere()
	failed += _test_no_cliff()
	failed += _test_headroom_within_bounds()
	failed += _test_every_basin_is_rimmed()
	failed += _test_slope_over_cap_is_marginal()
	failed += _test_sky_wells_are_sealed()
	failed += _test_key_altitudes_match_spec()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — le volume est clos et praticable")
		quit(0)


## AUCUNE CHUTE, partie 1 : il y a du sol sous chaque point de l'emprise.
## Trivial avec un champ de hauteurs — et c'est précisément l'argument de l'ADR.
## Le test vérifie qu'aucune valeur n'est absente ou aberrante (NaN/infini),
## seul moyen pour un champ de hauteurs de produire un trou.
func _test_ground_everywhere() -> int:
	var expected: int = _dims.x * _dims.y
	if _floor.size() != expected:
		print("[FAIL] sol : %d échantillons au lieu de %d" % [_floor.size(), expected])
		return 1
	for i in _floor.size():
		var h: float = _floor[i]
		if is_nan(h) or is_inf(h):
			print("[FAIL] sol : altitude invalide (%f) à l'index %d" % [h, i])
			return 1
	print("[OK] ground_everywhere (%d échantillons, aucun trou possible)" % expected)
	return 0


## AUCUNE CHUTE, partie 2 : pas de falaise entre deux points voisins.
func _test_no_cliff() -> int:
	var worst: float = 0.0
	var worst_at := Vector2.ZERO
	for iz in _dims.y:
		for ix in _dims.x:
			var h: float = _floor[iz * _dims.x + ix]
			if ix + 1 < _dims.x:
				var dx: float = absf(_floor[iz * _dims.x + ix + 1] - h)
				if dx > worst:
					worst = dx
					worst_at = CavernTerrainBuilder.sample_position(_terrain, ix, iz)
			if iz + 1 < _dims.y:
				var dz: float = absf(_floor[(iz + 1) * _dims.x + ix] - h)
				if dz > worst:
					worst = dz
					worst_at = CavernTerrainBuilder.sample_position(_terrain, ix, iz)

	if worst > MAX_STEP_METERS:
		print("[FAIL] falaise : dénivelé de %.2f m en (%.0f, %.0f), plafond %.2f m"
			% [worst, worst_at.x, worst_at.y, MAX_STEP_METERS])
		return 1
	print("[OK] no_cliff (dénivelé max entre voisins : %.2f m)" % worst)
	return 0


## VOLUME FERMÉ, partie 1 : la hauteur libre reste dans la fourchette dure.
## Garantie par construction (la voûte est composée comme `sol + hauteur libre`
## bornée) — on le vérifie pour que la garantie reste vraie si quelqu'un touche
## à la composition.
func _test_headroom_within_bounds() -> int:
	var lo := INF
	var hi := -INF
	for i in _floor.size():
		var clearance: float = _vault[i] - _floor[i]
		lo = minf(lo, clearance)
		hi = maxf(hi, clearance)

	if lo < _terrain.min_headroom - 0.01 or hi > _terrain.max_headroom + 0.01:
		print("[FAIL] hauteur libre : %.2f → %.2f m, hors de [%.1f, %.1f]"
			% [lo, hi, _terrain.min_headroom, _terrain.max_headroom])
		return 1
	print("[OK] headroom_within_bounds (%.1f → %.1f m)" % [lo, hi])
	return 0


## AUCUNE CHUTE, partie 3 : chaque creux déclaré est effectivement BORDÉ, et
## son rayon couvre son dénivelé sans dépasser le plafond de pente.
func _test_every_basin_is_rimmed() -> int:
	for basin in _terrain.floor_field.basins:
		if basin.rim_height <= 0.0:
			print("[FAIL] cuvette « %s » : margelle nulle → chute possible" % basin.label)
			return 1
		var required: float = CavernTerrainBuilder.min_falloff_for(
			basin.depth + basin.rim_height, _terrain.max_slope_degrees)
		var smallest: float = minf(basin.radii.x, basin.radii.y)
		if smallest < required - 0.01:
			print("[FAIL] cuvette « %s » : rayon %.1f m < %.1f m requis (paroi trop raide)"
				% [basin.label, smallest, required])
			return 1
	print("[OK] every_basin_is_rimmed (%d cuvettes)" % _terrain.floor_field.basins.size())
	return 0


func _test_slope_over_cap_is_marginal() -> int:
	var over: int = 0
	var total: int = 0
	var worst: float = 0.0
	for iz in _dims.y:
		for ix in _dims.x:
			var h: float = _floor[iz * _dims.x + ix]
			if ix + 1 < _dims.x:
				var sx: float = _slope(h, _floor[iz * _dims.x + ix + 1])
				worst = maxf(worst, sx)
				total += 1
				if sx > _terrain.max_slope_degrees:
					over += 1
			if iz + 1 < _dims.y:
				var sz: float = _slope(h, _floor[(iz + 1) * _dims.x + ix])
				worst = maxf(worst, sz)
				total += 1
				if sz > _terrain.max_slope_degrees:
					over += 1

	var ratio: float = float(over) / maxf(float(total), 1.0)
	if ratio > MAX_OVER_CAP_RATIO:
		print("[FAIL] pente : %.2f %% du terrain au-dessus de %.0f° (max toléré %.2f %%)"
			% [ratio * 100.0, _terrain.max_slope_degrees, MAX_OVER_CAP_RATIO * 100.0])
		return 1
	# 45° est le `floor_max_angle` par défaut du CharacterBody3D : au-delà, le
	# joueur glisse au lieu de marcher, et « praticable » devient un mensonge.
	if worst >= 45.0:
		print("[FAIL] pente : %.1f° atteint, le joueur glisserait (floor_max_angle 45°)" % worst)
		return 1
	print("[OK] slope_over_cap_is_marginal (max %.1f°, %.2f %% au-dessus de %.0f°)"
		% [worst, ratio * 100.0, _terrain.max_slope_degrees])
	return 0


## VOLUME FERMÉ, partie 2 : les puits de ciel sont des trous dans le MAILLAGE
## de la voûte, jamais dans sa collision. C'est ce qui permet de voir le ciel
## sans pouvoir sortir — sans avoir à poser un seul bouchon invisible.
func _test_sky_wells_are_sealed() -> int:
	if _terrain.sky_wells.is_empty():
		print("[FAIL] puits : la spec en exige au moins un (landmark visible de loin)")
		return 1

	for well in _terrain.sky_wells:
		# Sous le centre du puits, la voûte doit exister et rester dans la
		# fourchette : la collision est pleine, seul le maillage est percé.
		var ix: int = int(round((well.center.x - _terrain.bounds_min.x) / _terrain.cell_size))
		var iz: int = int(round((well.center.y - _terrain.bounds_min.y) / _terrain.cell_size))
		if ix < 0 or iz < 0 or ix >= _dims.x or iz >= _dims.y:
			print("[FAIL] puits « %s » : hors de l'emprise" % well.label)
			return 1
		var clearance: float = _vault[iz * _dims.x + ix] - _floor[iz * _dims.x + ix]
		if clearance < _terrain.min_headroom - 0.01:
			print("[FAIL] puits « %s » : hauteur libre %.2f m sous le minimum" % [well.label, clearance])
			return 1
	print("[OK] sky_wells_are_sealed (%d puits, collision de voûte pleine)" % _terrain.sky_wells.size())
	return 0


## Le terrain généré doit correspondre à la spec créative. Sans ce test, on
## pourrait « réussir » toutes les contraintes dures en construisant une
## caverne qui n'a rien à voir avec ce que Fable a conçu.
func _test_key_altitudes_match_spec() -> int:
	# (libellé, position, altitude attendue par docs/design/level01_topography.md)
	var probes: Array = [
		["Z1 spawn", Vector2(-41.0, 0.0), 6.0],
		["Z3 lac", Vector2(0.0, 0.0), 0.0],
		["Z4 K1", Vector2(22.0, 20.0), 4.0],
		["Z5 lanterne", Vector2(14.0, -21.0), 3.0],
		["Z6 crête", Vector2(27.0, 0.0), 3.0],
		["Z6 arène", Vector2(42.0, 0.0), -3.0],
	]
	# Tolérance : l'amplitude des ondulations de surface, qui est voulue.
	var tolerance: float = _terrain.floor_field.noise_amplitude + 0.5
	var noise: FastNoiseLite = _make_noise(_terrain.floor_field)

	for probe in probes:
		var actual: float = CavernTerrainBuilder.sample_point(_terrain.floor_field, probe[1], noise)
		if absf(actual - probe[2]) > tolerance:
			print("[FAIL] altitude « %s » : %.2f m au lieu de %.1f m (tolérance %.2f)"
				% [probe[0], actual, probe[2], tolerance])
			return 1
	print("[OK] key_altitudes_match_spec (%d points, tolérance %.2f m)" % [probes.size(), tolerance])
	return 0


func _make_noise(spec: CavernHeightfieldSpec) -> FastNoiseLite:
	if spec.noise_amplitude <= 0.0:
		return null
	var n := FastNoiseLite.new()
	n.seed = spec.noise_seed
	n.frequency = 1.0 / maxf(spec.noise_scale, 0.001)
	return n


func _slope(h_a: float, h_b: float) -> float:
	return rad_to_deg(atan2(absf(h_b - h_a), _terrain.cell_size))

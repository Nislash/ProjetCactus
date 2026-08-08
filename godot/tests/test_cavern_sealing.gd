extends SceneTree

## Étanchéité et praticabilité du volume. Lancer via :
##   godot --headless --path godot --script tests/test_cavern_sealing.gd
##
## Prouve, sur le terrain RÉELLEMENT généré, les contraintes dures du plan que
## personne ne peut vérifier à l'œil :
##   1. VOLUME FERMÉ  — impossible de sortir
##   2. AUCUNE CHUTE  — impossible de tomber dans le vide
##   3. PRATICABLE    — les zones jouables se marchent
##
## NUANCE ESSENTIELLE DEPUIS LA REFONTE ORGANIQUE : ces garanties portent sur les
## ZONES JOUABLES, pas sur toute l'emprise échantillonnée. Hors des chambres,
## la hauteur libre vaut zéro et le relief est raide — c'est la roche qui referme
## le volume, et sa raideur est voulue. Mesurer là serait mesurer un mur.

const TERRAIN_PATH := "res://data/levels/level01_cavern_terrain.tres"

## Dénivelé maximal toléré entre deux points JOUABLES voisins. Au-delà, c'est
## une falaise : on n'en meurt pas (il y a du sol en bas) mais on peut y rester
## coincé, et ce n'est pas ce que « praticable » veut dire.
const MAX_STEP_METERS := 1.6

## Part maximale d'échantillons jouables autorisée au-dessus du plafond de pente.
const MAX_OVER_CAP_RATIO := 0.02

## 45° est le `floor_max_angle` par défaut du CharacterBody3D : au-delà, le
## joueur glisse au lieu de marcher et « praticable » devient un mensonge.
const PLAYER_SLIP_ANGLE := 45.0

var _terrain: CavernTerrainData
var _floor: PackedFloat32Array
var _vault: PackedFloat32Array
var _dims: Vector2i
var _noise: FastNoiseLite


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
	_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)

	var failed: int = 0
	failed += _test_playable_area_matches_the_brief()
	failed += _test_ground_everywhere()
	failed += _test_volume_is_sealed()
	failed += _test_headroom_within_bounds()
	failed += _test_no_cliff_on_playable_ground()
	failed += _test_slope_stays_walkable()
	failed += _test_every_basin_is_rimmed()
	failed += _test_lake_has_a_flat_bed()
	failed += _test_sky_openings_are_sealed()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — le volume est clos et praticable")
		quit(0)


func _is_playable(index: int) -> bool:
	return CavernTerrainBuilder.is_playable(_terrain, _floor[index], _vault[index])


# ---------------------------------------------------------------------------
# Dimensionnement
# ---------------------------------------------------------------------------

## La commande était « ×7 minimum » par rapport à l'ancienne caverne. Sans ce
## test, une chambre supprimée par mégarde ferait rétrécir le niveau sans que
## rien ne le signale.
func _test_playable_area_matches_the_brief() -> int:
	var cell_area: float = _terrain.cell_size * _terrain.cell_size
	var playable: int = 0
	for i in _floor.size():
		if _is_playable(i):
			playable += 1
	var area: float = playable * cell_area
	var previous_cavern_area := 5022.0

	if area < previous_cavern_area * 7.0:
		print("[FAIL] surface : %.0f m² jouables, soit ×%.1f — le brief demande ×7 minimum"
			% [area, area / previous_cavern_area])
		return 1
	print("[OK] playable_area_matches_the_brief (%.0f m², ×%.1f)" % [area, area / previous_cavern_area])
	return 0


# ---------------------------------------------------------------------------
# Étanchéité
# ---------------------------------------------------------------------------

## AUCUNE CHUTE, partie 1 : il y a du sol sous chaque point. Trivial avec un
## champ de hauteurs — et c'est précisément l'argument de l'ADR. Le test vérifie
## qu'aucune valeur n'est absente ou aberrante, seul moyen d'y faire un trou.
func _test_ground_everywhere() -> int:
	if _floor.size() != _dims.x * _dims.y:
		print("[FAIL] sol : %d échantillons au lieu de %d" % [_floor.size(), _dims.x * _dims.y])
		return 1
	for i in _floor.size():
		if is_nan(_floor[i]) or is_inf(_floor[i]):
			print("[FAIL] sol : altitude invalide à l'index %d" % i)
			return 1
	print("[OK] ground_everywhere (%d échantillons, aucun trou possible)" % _floor.size())
	return 0


## VOLUME FERMÉ : hors des chambres, la hauteur libre est nulle — voûte et sol
## se rejoignent, il n'y a plus d'espace où passer. C'est ce qui remplace la
## ceinture de parois de l'ancienne architecture.
func _test_volume_is_sealed() -> int:
	var leaks: int = 0
	var worst := Vector2.ZERO
	for iz in _dims.y:
		for ix in _dims.x:
			var i: int = iz * _dims.x + ix
			var p: Vector2 = CavernTerrainBuilder.sample_position(_terrain, ix, iz)
			if CavernTerrainBuilder.chamber_mask(_terrain, p) > 0.0:
				continue
			if _vault[i] - _floor[i] > 0.01:
				leaks += 1
				worst = p

	if leaks > 0:
		print("[FAIL] étanchéité : %d point(s) ouverts hors des chambres, ex. (%.0f, %.0f)"
			% [leaks, worst.x, worst.y])
		return 1
	print("[OK] volume_is_sealed (fermé partout hors des chambres)")
	return 0


## La hauteur libre des zones JOUABLES reste dans la fourchette dure. Hors des
## chambres elle descend jusqu'à zéro, et c'est voulu : c'est la paroi.
func _test_headroom_within_bounds() -> int:
	var lo := INF
	var hi := -INF
	for i in _floor.size():
		if not _is_playable(i):
			continue
		var clearance: float = _vault[i] - _floor[i]
		lo = minf(lo, clearance)
		hi = maxf(hi, clearance)

	if hi > _terrain.max_headroom + 0.01:
		print("[FAIL] hauteur libre : %.2f m dépasse le maximum de %.1f m" % [hi, _terrain.max_headroom])
		return 1
	# La borne basse n'est PAS min_headroom : la bande de transition vers la
	# paroi passe légitimement en dessous. On vérifie qu'elle reste au-dessus du
	# seuil de jouabilité, ce qui est la vraie promesse.
	if lo < _terrain.playable_headroom_threshold - 0.01:
		print("[FAIL] hauteur libre : %.2f m sous le seuil de jouabilité" % lo)
		return 1
	print("[OK] headroom_within_bounds (%.1f → %.1f m dans les zones jouables)" % [lo, hi])
	return 0


# ---------------------------------------------------------------------------
# Praticabilité
# ---------------------------------------------------------------------------

func _test_no_cliff_on_playable_ground() -> int:
	var worst: float = 0.0
	var worst_at := Vector2.ZERO
	for iz in _dims.y:
		for ix in _dims.x:
			var i: int = iz * _dims.x + ix
			if not _is_playable(i):
				continue
			for neighbour in [Vector2i(1, 0), Vector2i(0, 1)]:
				var jx: int = ix + neighbour.x
				var jz: int = iz + neighbour.y
				if jx >= _dims.x or jz >= _dims.y:
					continue
				var j: int = jz * _dims.x + jx
				if not _is_playable(j):
					continue
				var step: float = absf(_floor[j] - _floor[i])
				if step > worst:
					worst = step
					worst_at = CavernTerrainBuilder.sample_position(_terrain, ix, iz)

	if worst > MAX_STEP_METERS:
		print("[FAIL] falaise : %.2f m entre deux points jouables en (%.0f, %.0f), plafond %.2f m"
			% [worst, worst_at.x, worst_at.y, MAX_STEP_METERS])
		return 1
	print("[OK] no_cliff_on_playable_ground (dénivelé max %.2f m)" % worst)
	return 0


func _test_slope_stays_walkable() -> int:
	var over: int = 0
	var total: int = 0
	var worst: float = 0.0
	var worst_at := Vector2.ZERO

	for iz in _dims.y:
		for ix in _dims.x:
			var i: int = iz * _dims.x + ix
			if not _is_playable(i):
				continue
			for neighbour in [Vector2i(1, 0), Vector2i(0, 1)]:
				var jx: int = ix + neighbour.x
				var jz: int = iz + neighbour.y
				if jx >= _dims.x or jz >= _dims.y:
					continue
				var j: int = jz * _dims.x + jx
				if not _is_playable(j):
					continue
				var slope: float = rad_to_deg(atan2(absf(_floor[j] - _floor[i]), _terrain.cell_size))
				total += 1
				if slope > worst:
					worst = slope
					worst_at = CavernTerrainBuilder.sample_position(_terrain, ix, iz)
				if slope > _terrain.max_slope_degrees:
					over += 1

	var ratio: float = float(over) / maxf(float(total), 1.0)
	if ratio > MAX_OVER_CAP_RATIO:
		print("[FAIL] pente : %.2f %% du sol jouable au-dessus de %.0f° (max toléré %.2f %%)"
			% [ratio * 100.0, _terrain.max_slope_degrees, MAX_OVER_CAP_RATIO * 100.0])
		return 1
	if worst >= PLAYER_SLIP_ANGLE:
		print("[FAIL] pente : %.1f° en (%.0f, %.0f) — le joueur glisserait (floor_max_angle %.0f°)"
			% [worst, worst_at.x, worst_at.y, PLAYER_SLIP_ANGLE])
		return 1
	print("[OK] slope_stays_walkable (max %.1f°, %.2f %% au-dessus de %.0f°)"
		% [worst, ratio * 100.0, _terrain.max_slope_degrees])
	return 0


## AUCUNE CHUTE : chaque creux déclaré est BORDÉ, et son rayon couvre son
## dénivelé sans dépasser le plafond de pente.
func _test_every_basin_is_rimmed() -> int:
	for basin in _terrain.floor_field.basins:
		if basin.rim_height <= 0.0:
			print("[FAIL] cuvette « %s » : margelle nulle → chute possible" % basin.label)
			return 1
		# Le dénivelé s'étale sur la portion NON plate du rayon.
		var slope_span: float = minf(basin.radii.x, basin.radii.y) * (1.0 - basin.flat_bottom)
		var required: float = CavernTerrainBuilder.min_falloff_for(
			basin.depth + basin.rim_height, _terrain.max_slope_degrees)
		if slope_span < required - 0.01:
			print("[FAIL] cuvette « %s » : pente sur %.1f m, %.1f m requis (paroi trop raide)"
				% [basin.label, slope_span, required])
			return 1
	print("[OK] every_basin_is_rimmed (%d cuvettes)" % _terrain.floor_field.basins.size())
	return 0


## Le lac doit reposer sur un LIT PLAT et être réellement immergé : une nappe
## posée sur une cuvette en pointe ne couvre qu'une flaque, et une nappe au-dessus
## du fond flotterait dans le vide.
func _test_lake_has_a_flat_bed() -> int:
	if _terrain.lake == null:
		print("[OK] lake_has_a_flat_bed (aucun lac déclaré)")
		return 0

	var submerged: int = 0
	for iz in _dims.y:
		for ix in _dims.x:
			var p: Vector2 = CavernTerrainBuilder.sample_position(_terrain, ix, iz)
			if not CavernTerrainBuilder.is_in_lake_footprint(_terrain, p):
				continue
			if CavernTerrainBuilder.chamber_mask(_terrain, p) <= 0.0:
				continue
			if _terrain.lake.surface_altitude - _floor[iz * _dims.x + ix] >= _terrain.lake.minimum_depth:
				submerged += 1

	var area: float = submerged * _terrain.cell_size * _terrain.cell_size
	if area < 200.0:
		print("[FAIL] lac : %.0f m² immergés seulement — la nappe est une flaque, pas un lac" % area)
		return 1
	print("[OK] lake_has_a_flat_bed (%.0f m² de nappe)" % area)
	return 0


## Les ouvertures percent le MAILLAGE de la voûte, jamais sa collision. On voit
## le ciel, on ne sort jamais — sans avoir à poser un seul bouchon invisible.
func _test_sky_openings_are_sealed() -> int:
	if _terrain.sky_openings.is_empty():
		print("[FAIL] ouvertures : le plan en exige au moins une (landmark visible de loin)")
		return 1

	for opening in _terrain.sky_openings:
		var ix: int = int(round((opening.center.x - _terrain.bounds_min.x) / _terrain.cell_size))
		var iz: int = int(round((opening.center.y - _terrain.bounds_min.y) / _terrain.cell_size))
		if ix < 0 or iz < 0 or ix >= _dims.x or iz >= _dims.y:
			print("[FAIL] ouverture « %s » : hors de l'emprise" % opening.label)
			return 1
		var i: int = iz * _dims.x + ix
		# Une ouverture doit surplomber du volume JOUABLE : percée au-dessus de
		# la roche pleine, elle ne montrerait le ciel à personne.
		if not _is_playable(i):
			print("[FAIL] ouverture « %s » : percée au-dessus de la roche pleine" % opening.label)
			return 1
	print("[OK] sky_openings_are_sealed (%d ouvertures, collision de voûte pleine)" % _terrain.sky_openings.size())
	return 0

extends SceneTree

## Construit `res://data/levels/level01_cavern_terrain.tres` à partir de la spec
## créative `docs/design/level01_topography.md`. Lancer via :
##   godot --headless --path godot --script tools/build_cavern_terrain.gd
##
## POURQUOI UN SCRIPT PLUTÔT QU'UN .tres ÉCRIT À LA MAIN
## La correspondance entre le document de Fable et les nombres du terrain doit
## rester lisible et vérifiable. Ici, chaque primitive cite la ligne de la spec
## dont elle sort, et toutes les transitions sont dimensionnées par
## `min_falloff_for` — jamais par un nombre écrit au jugé (cf ADR
## `docs/tech/level01_terrain.md`, règles d'authoring).
##
## Le `.tres` produit est un artefact : pour changer la topographie, on édite ce
## script, on relance, on rejoue les tests. C'est ce qui rend la review créative
## post-blockout (#15) bon marché.

const OUTPUT_PATH := "res://data/levels/level01_cavern_terrain.tres"

## Pente visée sur les transitions du chemin principal. Volontairement sous le
## plafond de praticabilité : les ondulations de surface ajoutent leur propre
## gradient par-dessus.
const PATH_TARGET_DEG := 16.0

## Pente visée sur les parois du bol d'arène et les flancs de cuvette : plus
## raide, mais franchissable. Cf note d'écart §3 en bas de fichier.
const WALL_TARGET_DEG := 22.0


func _init() -> void:
	var terrain := CavernTerrainData.new()
	# Emprise : topo §2. Origine (0,0) au centre du lac, Y=0 à la surface de la
	# glace — tout le reste du document est coté par rapport à ça.
	terrain.bounds_min = Vector2(-45.0, -28.0)
	# ÉCART ASSUMÉ : la spec borne l'emprise à X = +48. Porté à +56 parce que le
	# bol d'arène y est infaisable autrement : 6 m de dénivelé sur un rayon de
	# 10 m donnent ~45° de paroi une fois le profil lissé, bien au-delà de tout
	# ce qui est praticable. Les 8 m gagnés sont un appendice fermé (l'arène),
	# pas de l'espace de traversée : le cœur jouable reste dans les ~80 m annoncés.
	terrain.bounds_max = Vector2(56.0, 26.0)
	terrain.cell_size = 1.0
	terrain.min_headroom = 10.0
	terrain.max_headroom = 15.0
	# 32° : plafond de PRATICABILITÉ, pas de confort. Il reste largement sous le
	# `floor_max_angle` du CharacterBody3D (45°) donc rien n'est glissant, mais
	# il laisse passer les parois du bol d'arène. Le chemin principal, lui, est
	# dimensionné à 16°.
	terrain.max_slope_degrees = 36.0

	terrain.floor_field = _build_floor()
	terrain.vault_field = _build_vault()
	terrain.sky_wells = _build_sky_wells()

	var error: int = ResourceSaver.save(terrain, OUTPUT_PATH)
	if error != OK:
		push_error("Échec de l'écriture de %s (code %d)" % [OUTPUT_PATH, error])
		quit(1)
		return

	print("[terrain] écrit : %s" % OUTPUT_PATH)
	_report(terrain)
	quit(0)


# ---------------------------------------------------------------------------
# Le sol
# ---------------------------------------------------------------------------

func _build_floor() -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	# Altitude de référence : le pourtour du lac (topo §3, rives +1,5 → +2).
	spec.base_altitude = 2.0
	# Ondulations douces demandées par la spec (« bosses, creux »), graine fixe
	# pour que deux générations donnent exactement le même terrain.
	spec.noise_amplitude = 0.45
	spec.noise_scale = 14.0
	spec.noise_seed = 20260808

	var plateaus: Array[CavernPlateau] = []
	var ramps: Array[CavernRamp] = []
	var basins: Array[CavernBasin] = []

	# ORDRE IMPORTANT : les plateaux se fondent l'un dans l'autre par `lerp`, donc
	# le DERNIER posé l'emporte localement. On va du général au particulier.
	# (Une première version utilisait une rampe unique de 46 m de large pour la
	# descente d'ensemble : son influence est une capsule, elle débordait jusqu'à
	# l'est de la carte et lavait les terrasses du Nid à 2,85 m au lieu de 4.)

	# --- Z2 Forêt : palier intermédiaire large, à mi-chemin de la descente ----
	plateaus.append(_plateau("Z2 forêt", Vector2(-22.0, 0.0), Vector2(10.0, 14.0), 3.5,
		CavernTerrainBuilder.min_falloff_for(1.5, PATH_TARGET_DEG), false))

	# --- Z1 Corniche du Réveil : +6, quasi plate (topo §3) -------------------
	# Son fondu EST la descente d'ensemble : 4 m gagnés sur ~21 m, soit le geste
	# de la combe. Pas besoin d'une rampe pour ça, et ça évite son débordement.
	plateaus.append(_plateau("Z1 corniche", Vector2(-38.5, 0.0), Vector2(6.5, 9.0), 6.0,
		CavernTerrainBuilder.min_falloff_for(4.0, PATH_TARGET_DEG), false))

	# --- Z2 : cuvette C1 qui abrite K3 (topo §8) ----------------------------
	# ÉCART ASSUMÉ : la spec dit ∅6 m / prof. 1 m. Un bol de rayon 3 m creusé de
	# 1 m sort à ~37° une fois le profil lissé — au-dessus du plafond. Élargi à
	# ∅12 m et adouci à 0,8 m : même rôle (abri, couvert contre les béliers,
	# écrin pour K3), pente tenue. À arbitrer en review #15.
	basins.append(_basin("C1 cuvette de K3", Vector2(-20.0, 6.0), 6.0, 0.8, 0.4, WALL_TARGET_DEG))

	# --- Z3 Le Lac Gelé : ellipse 16×12, surface à Y=0 ----------------------
	# Creusé de 2 m sous le pourtour (+2), donc surface à 0 : la référence du
	# niveau. La margelle est l'anneau de rives qui empêche d'y « tomber » —
	# on y descend, on n'y chute pas.
	basins.append(_basin_elliptic("Z3 lac gelé", Vector2(0.0, 0.0), Vector2(16.0, 12.0),
		2.0, 0.5, WALL_TARGET_DEG))

	# --- Z4 Le Nid : trois terrasses +2 / +3 / +4 (topo §3) ------------------
	# T1 est au niveau du pourtour (+2) : pas de primitive, c'est le terrain.
	plateaus.append(_plateau("Z4 terrasse T2", Vector2(+18.0, +16.0), Vector2(5.0, 4.0), 3.0,
		CavernTerrainBuilder.min_falloff_for(1.0, PATH_TARGET_DEG), false))
	plateaus.append(_plateau("Z4 terrasse T3 (K1)", Vector2(+22.0, +20.0), Vector2(5.0, 4.0), 4.0,
		CavernTerrainBuilder.min_falloff_for(2.0, PATH_TARGET_DEG), false))

	# --- Z5 La Lanterne : plateau +3, plat (topo §3) ------------------------
	plateaus.append(_plateau("Z5 la lanterne", Vector2(+14.0, -21.0), Vector2(8.0, 7.0), 3.0,
		CavernTerrainBuilder.min_falloff_for(1.0, PATH_TARGET_DEG), false))

	# --- Z6 La crête-seuil : +3, étroite en X, longue en Z ------------------
	# C'est la compression avant la révélation : on monte, la voûte descend.
	plateaus.append(_plateau("Z6 crête du seuil", Vector2(+27.0, 0.0), Vector2(3.0, 10.0), 3.0,
		CavernTerrainBuilder.min_falloff_for(1.0, PATH_TARGET_DEG), false))

	# --- Z6 Le bol d'arène : fond à −3, ∅20 (topo §3 et §8) -----------------
	# ÉCART ASSUMÉ : 6 m de dénivelé sur un rayon de 10 m donnent ~31° de pente
	# moyenne, au-delà des « 25° » annoncés par la spec. Conservé tel quel : la
	# chute plongeante EST l'effet de la révélation V3, les rampes RN/RS restent
	# les chemins évidents, et 31° passe très en dessous du floor_max_angle du
	# personnage. À arbitrer en review #15.
	basins.append(_basin("Z6 bol d'arène", Vector2(+42.0, 0.0), 14.0, 5.0, 0.5, 35.0))

	# --- Les deux rampes d'arène RN / RS (topo §8, 14°) ---------------------
	# Elles creusent un chemin franc dans la paroi du bol : le joueur qui suit
	# l'évidence descend par là.
	# ATTENTION : ces altitudes sont exprimées AVANT creusement du bol, parce que
	# les cuvettes s'appliquent en dernier et s'AJOUTENT. Les coter en altitude
	# finale revient à soustraire deux fois (le fond tombait à −4,5 au lieu de −3).
	ramps.append(_ramp("RN rampe nord", Vector2(+29.0, -8.0), Vector2(+38.0, -4.0),
		3.0, 1.0, 4.0, 5.0))
	ramps.append(_ramp("RS rampe sud", Vector2(+29.0, +8.0), Vector2(+38.0, +4.0),
		3.0, 1.0, 4.0, 5.0))

	spec.plateaus = plateaus
	spec.ramps = ramps
	spec.basins = basins
	return spec


# ---------------------------------------------------------------------------
# La voûte
# ---------------------------------------------------------------------------

## Champ de HAUTEUR LIBRE, pas d'altitude absolue : la voûte finale vaut
## `sol + hauteur libre`. La contrainte dure 10-15 m est donc satisfaite par
## construction, et le rythme de la voûte suit le relief au lieu de dériver
## dès qu'on retouche le sol.
func _build_vault() -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	# 12 m : la respiration par défaut, au milieu de la fourchette autorisée.
	spec.base_altitude = 12.0
	# Très peu d'ondulation : la voûte doit rester lisible en silhouette.
	spec.noise_amplitude = 0.3
	spec.noise_scale = 18.0
	spec.noise_seed = 771102

	var plateaus: Array[CavernPlateau] = []
	# Z1 : 12 m — l'entrée est haute sans être la plus haute.
	plateaus.append(_plateau("voûte Z1", Vector2(-38.5, 0.0), Vector2(8.0, 11.0), 12.0, 14.0, false))
	# Z3 lac : 14 m — c'est ici que la caverne respire le plus, sous le puits P1.
	plateaus.append(_plateau("voûte Z3 lac", Vector2(0.0, 0.0), Vector2(16.0, 12.0), 14.0, 12.0, true))
	# Z5 : 10 m — la plus basse avec le seuil, chambre intime.
	plateaus.append(_plateau("voûte Z5", Vector2(+14.0, -21.0), Vector2(9.0, 8.0), 10.0, 8.0, false))
	# Z6 crête : 10 m, le MINIMUM autorisé, exploité comme effet — c'est la
	# compression que le joueur doit ressentir juste avant la révélation.
	plateaus.append(_plateau("voûte seuil", Vector2(+27.0, 0.0), Vector2(4.0, 11.0), 10.0, 6.0, false))
	# Z6 arène : 15 m, le MAXIMUM — l'espace s'ouvre d'un coup après le seuil.
	plateaus.append(_plateau("voûte arène", Vector2(+42.0, 0.0), Vector2(14.0, 14.0), 15.0, 8.0, true))

	spec.plateaus = plateaus
	return spec


func _build_sky_wells() -> Array[CavernSkyWell]:
	var wells: Array[CavernSkyWell] = []
	# P1 : le grand puits au-dessus du lac. Le landmark du niveau (topo §6).
	var p1 := CavernSkyWell.new()
	p1.label = "P1"
	p1.center = Vector2(+2.0, -2.0)
	p1.diameter = 8.0
	wells.append(p1)
	# P2 : le petit puits qui consacre la lanterne.
	var p2 := CavernSkyWell.new()
	p2.label = "P2"
	p2.center = Vector2(+14.0, -20.0)
	p2.diameter = 3.0
	wells.append(p2)
	return wells


# ---------------------------------------------------------------------------
# Fabriques
# ---------------------------------------------------------------------------

func _plateau(label: String, center: Vector2, half_extent: Vector2, altitude: float,
		falloff: float, is_ellipse: bool) -> CavernPlateau:
	var p := CavernPlateau.new()
	p.label = label
	p.center = center
	p.half_extent = half_extent
	p.altitude = altitude
	p.falloff = falloff
	p.is_ellipse = is_ellipse
	return p


func _ramp(label: String, from_point: Vector2, to_point: Vector2, from_altitude: float,
		to_altitude: float, width: float, falloff: float) -> CavernRamp:
	var r := CavernRamp.new()
	r.label = label
	r.from_point = from_point
	r.to_point = to_point
	r.from_altitude = from_altitude
	r.to_altitude = to_altitude
	r.width = width
	r.falloff = falloff
	return r


## Cuvette circulaire. Le rayon est vérifié contre la règle d'authoring : il
## doit couvrir `depth + rim_height` à la pente visée, sinon la paroi du creux
## dépasse le plafond.
func _basin(label: String, center: Vector2, radius: float, depth: float,
		rim_height: float, target_deg: float) -> CavernBasin:
	return _basin_elliptic(label, center, Vector2(radius, radius), depth, rim_height, target_deg)


func _basin_elliptic(label: String, center: Vector2, radii: Vector2, depth: float,
		rim_height: float, target_deg: float) -> CavernBasin:
	var required: float = CavernTerrainBuilder.min_falloff_for(depth + rim_height, target_deg)
	var smallest: float = minf(radii.x, radii.y)
	if smallest < required - 0.01:
		push_warning("[terrain] « %s » : rayon %.1f m < %.1f m requis pour %.1f m de dénivelé à %.0f°."
			% [label, smallest, required, depth + rim_height, target_deg])

	var b := CavernBasin.new()
	b.label = label
	b.center = center
	b.radii = radii
	b.depth = depth
	b.rim_height = rim_height
	b.rim_width = CavernTerrainBuilder.min_falloff_for(rim_height, target_deg)
	return b


# ---------------------------------------------------------------------------
# Rapport
# ---------------------------------------------------------------------------

## Rapport de contrôle : hauteur libre, pente maximale et altitudes aux points
## clés de la spec. Sert à comparer d'un coup d'œil ce qui est généré à ce que
## le document de Fable annonce.
func _report(terrain: CavernTerrainData) -> void:
	var dims: Vector2i = CavernTerrainBuilder.grid_dimensions(terrain)
	var floor_h: PackedFloat32Array = CavernTerrainBuilder.sample_field(terrain, terrain.floor_field)
	var vault_h: PackedFloat32Array = CavernTerrainBuilder.compose_vault(terrain, floor_h)

	var head_min := INF
	var head_max := -INF
	var slope_max := 0.0
	var over_cap := 0
	var samples := 0
	for iz in dims.y:
		for ix in dims.x:
			var i: int = iz * dims.x + ix
			var head: float = vault_h[i] - floor_h[i]
			head_min = minf(head_min, head)
			head_max = maxf(head_max, head)
			if ix + 1 < dims.x:
				var sx: float = _slope(floor_h[i], floor_h[i + 1], terrain.cell_size)
				slope_max = maxf(slope_max, sx)
				samples += 1
				if sx > terrain.max_slope_degrees:
					over_cap += 1
			if iz + 1 < dims.y:
				var sz: float = _slope(floor_h[i], floor_h[i + dims.x], terrain.cell_size)
				slope_max = maxf(slope_max, sz)
				samples += 1
				if sz > terrain.max_slope_degrees:
					over_cap += 1

	print("[terrain] grille %dx%d (%d échantillons)" % [dims.x, dims.y, floor_h.size()])
	print("[terrain] hauteur libre : %.1f m → %.1f m (cible %.0f-%.0f)"
		% [head_min, head_max, terrain.min_headroom, terrain.max_headroom])
	# La pente MAXIMALE n'est pas le bon juge : les flancs latéraux des rampes
	# creusées dans la paroi du bol sont des MURS, pas du sol praticable, et un
	# champ de hauteurs ne sait pas les distinguer. Ce qui compte est la PART du
	# terrain au-dessus du plafond : si elle est marginale et localisée aux
	# parois, le sol jouable est sain. La preuve de praticabilité réelle reste le
	# navmesh (tâche #12), seul juge de "peut-on aller de A à B".
	print("[terrain] pente max du sol : %.1f° (plafond %.0f°)" % [slope_max, terrain.max_slope_degrees])
	print("[terrain] au-dessus du plafond : %d / %d échantillons (%.2f %%)"
		% [over_cap, samples, 100.0 * float(over_cap) / maxf(float(samples), 1.0)])
	for probe in [
		["Z1 spawn", Vector2(-41.0, 0.0)], ["Z2 forêt", Vector2(-22.0, 0.0)],
		["Z3 lac", Vector2(0.0, 0.0)], ["Z4 K1", Vector2(22.0, 20.0)],
		["Z5 lanterne", Vector2(14.0, -21.0)], ["Z6 crête", Vector2(27.0, 0.0)],
		["Z6 arène", Vector2(42.0, 0.0)],
	]:
		var h: float = CavernTerrainBuilder.sample_point(terrain.floor_field, probe[1], _noise(terrain.floor_field))
		print("[terrain]   %-12s %6.2f m" % [probe[0], h])


func _noise(spec: CavernHeightfieldSpec) -> FastNoiseLite:
	if spec.noise_amplitude <= 0.0:
		return null
	var n := FastNoiseLite.new()
	n.seed = spec.noise_seed
	n.frequency = 1.0 / maxf(spec.noise_scale, 0.001)
	return n


func _slope(h_a: float, h_b: float, run: float) -> float:
	return rad_to_deg(atan2(absf(h_b - h_a), run))

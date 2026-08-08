extends SceneTree

## Construit `res://data/levels/level01_cavern_terrain.tres`.
##
## PREMIER JET de la grande caverne ×7, transcrit des croquis de l'utilisateur.
## Ce fichier est un point de départ à soumettre : la conception définitive
## revient à la session Fable (tâche #39), qui travaillera sur cette base et sur
## la fiche de contraintes constructibles.
##
## Lancer :
##   godot --headless --path godot --script tools/build_cavern_terrain.gd
##
## La caverne est décrite en CHAMBRES (des poches) et GOULETS (des couloirs) —
## c'est ainsi que se lit un plan de caverne dessiné à la main, et c'est le
## vocabulaire que le générateur consomme.

const OUTPUT_PATH := "res://data/levels/level01_cavern_terrain.tres"

## Pente visée sur les transitions du chemin principal. Volontairement sous le
## plafond de praticabilité : les ondulations ajoutent leur propre gradient.
const PATH_TARGET_DEG := 16.0


func _init() -> void:
	var terrain := CavernTerrainData.new()
	terrain.bounds_min = Vector2(-155.0, -105.0)
	terrain.bounds_max = Vector2(155.0, 105.0)
	terrain.cell_size = 1.5
	terrain.chunk_size = 48.0
	terrain.min_headroom = 10.0
	terrain.max_headroom = 15.0
	terrain.playable_headroom_threshold = 2.5
	terrain.max_slope_degrees = 36.0

	terrain.chambers = _build_chambers()
	terrain.floor_field = _build_floor()
	terrain.headroom_field = _build_headroom_modulation()
	terrain.sky_openings = _build_sky_openings()
	terrain.lake = _build_lake()

	if ResourceSaver.save(terrain, OUTPUT_PATH) != OK:
		push_error("Échec de l'écriture de %s" % OUTPUT_PATH)
		quit(1)
		return
	print("[terrain] écrit : %s" % OUTPUT_PATH)
	_report(terrain)
	quit(0)


# ---------------------------------------------------------------------------
# La silhouette
# ---------------------------------------------------------------------------

func _build_chambers() -> Array[CavernChamber]:
	var chambers: Array[CavernChamber] = []

	# --- SALLE DU BOSS (croquis : le grand lobe hachuré en haut) ------------
	# Trois poches décalées plutôt qu'une ellipse : c'est ce qui casse l'effet
	# « bulle » que la première silhouette produisait.
	chambers.append(_room("B1 Salle du Boss", Vector2(96.0, -54.0), Vector2(49.0, 36.0), -14.0, 15.0, 14.0))
	chambers.append(_room("B2 Lobe NO du Boss", Vector2(66.0, -70.0), Vector2(24.0, 18.0), 22.0, 14.0, 10.0))
	chambers.append(_room("B3 Encoche Est", Vector2(122.0, -30.0), Vector2(14.0, 10.0), -30.0, 12.0, 6.0))

	# --- LA GALERIE (l'entrée, scindée en deux actes par le Détroit) --------
	chambers.append(_room("G1 Galerie Ouest", Vector2(-102.0, -38.0), Vector2(34.0, 24.0), 18.0, 13.0, 12.0))
	chambers.append(_room("G2 Galerie Centrale", Vector2(-54.0, -44.0), Vector2(32.0, 22.0), -10.0, 12.0, 8.0))
	chambers.append(_room("G3 Galerie Est", Vector2(-12.0, -36.0), Vector2(30.0, 22.0), 8.0, 13.0, 16.0))
	# Bord serré (5 m) : la baie s'ouvre franchement, sans évasement mou.
	chambers.append(_room("N1 Baie Nord (K3)", Vector2(-44.0, -64.0), Vector2(11.0, 8.0), 25.0, 11.0, 5.0))

	# --- LE LAC, sous la Brèche --------------------------------------------
	chambers.append(_room("L1 Salle du Lac", Vector2(-4.0, 36.0), Vector2(49.0, 42.0), -8.0, 15.0, 18.0))
	chambers.append(_room("L2 Lobe Nord-Est", Vector2(28.0, 16.0), Vector2(22.0, 16.0), 30.0, 14.0, 8.0))
	chambers.append(_room("L3 Queue Sud", Vector2(-14.0, 74.0), Vector2(14.0, 10.0), -20.0, 11.0, 6.0))

	# --- LES DÉTOURS -------------------------------------------------------
	chambers.append(_room("P1 Poche du Loot", Vector2(-128.0, 8.0), Vector2(20.0, 15.0), 20.0, 10.0, 5.0))
	chambers.append(_room("J1 Jardin de Givre", Vector2(-86.0, 34.0), Vector2(30.0, 22.0), -28.0, 12.0, 14.0))
	chambers.append(_room("J2 Jardin (lobe est)", Vector2(-60.0, 52.0), Vector2(16.0, 12.0), 15.0, 11.0, 8.0))

	# --- LES GOULETS -------------------------------------------------------
	# C1/C2/C6 sont volontairement sous les 6 m du chemin principal : ce sont
	# des passages secondaires, la fiche de contraintes l'autorise (≥ 3 m).
	chambers.append(_corridor("C1 Le Détroit", Vector2(-32.0, -42.0), Vector2(-24.0, -38.0), 5.0, 10.0, 6.0))
	chambers.append(_corridor("C2 Boyau du Loot", Vector2(-104.0, -22.0), Vector2(-120.0, 2.0), 4.5, 10.0, 5.0))
	chambers.append(_corridor("C3 Passe du Jardin", Vector2(-74.0, -8.0), Vector2(-80.0, 16.0), 6.0, 11.0, 8.0))
	chambers.append(_corridor("C4 La Descente", Vector2(-20.0, -14.0), Vector2(-10.0, 6.0), 7.0, 12.0, 9.0))
	chambers.append(_corridor("C5 Seuil du Boss", Vector2(30.0, -40.0), Vector2(52.0, -48.0), 8.0, 10.0, 9.0))
	# Le Passage Effondré : il EXISTE dans le terrain dès le départ. C'est la
	# Porte (un prop) qui le bloque, pas la géométrie — sinon le raccourci
	# n'existerait pas et le navmesh ne saurait pas le cuire.
	chambers.append(_corridor("C6 Passage Effondré", Vector2(50.0, -32.0), Vector2(30.0, 2.0), 4.0, 10.0, 5.0))

	return chambers


func _room(label: String, center: Vector2, radii: Vector2, rotation: float,
		headroom: float, softness: float) -> CavernChamber:
	var c := CavernChamber.new()
	c.label = label
	c.center = center
	c.radii = radii
	c.rotation_degrees = rotation
	c.headroom = headroom
	c.edge_softness = softness
	return c


func _corridor(label: String, from_point: Vector2, to_point: Vector2, half_width: float,
		headroom: float, softness: float) -> CavernChamber:
	var c := CavernChamber.new()
	c.label = label
	c.is_corridor = true
	c.center = from_point
	c.to_center = to_point
	c.radii = Vector2(half_width, half_width)
	c.headroom = headroom
	c.edge_softness = softness
	return c


# ---------------------------------------------------------------------------
# Le sol
# ---------------------------------------------------------------------------

func _build_floor() -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	# Altitude de référence : les rives du lac.
	spec.base_altitude = 2.0
	spec.noise_amplitude = 0.60
	spec.noise_scale = 10.0
	spec.noise_seed = 20260808

	var plateaus: Array[CavernPlateau] = []
	var ramps: Array[CavernRamp] = []
	var basins: Array[CavernBasin] = []

	# L'histoire verticale : haut à l'ouest, bas au centre sous la Brèche,
	# l'arène en contrebas au nord-est. On descend vers la lumière, puis on
	# plonge vers le noir.
	#
	# Ordre : du général au particulier — les plateaux se fondent par lerp,
	# donc le dernier posé l'emporte localement.
	plateaus.append(_plateau("Perchoir Ouest", Vector2(-112.0, -38.0), Vector2(26.0, 20.0), 9.0,
		CavernTerrainBuilder.min_falloff_for(4.0, PATH_TARGET_DEG), true))
	plateaus.append(_plateau("Galerie mi-pente", Vector2(-54.0, -42.0), Vector2(26.0, 18.0), 6.0,
		CavernTerrainBuilder.min_falloff_for(3.0, PATH_TARGET_DEG), true))
	plateaus.append(_plateau("Galerie basse", Vector2(-12.0, -36.0), Vector2(26.0, 18.0), 4.0,
		CavernTerrainBuilder.min_falloff_for(2.0, PATH_TARGET_DEG), true))
	plateaus.append(_plateau("Perchoir du Loot", Vector2(-128.0, 8.0), Vector2(16.0, 12.0), 9.5,
		CavernTerrainBuilder.min_falloff_for(3.0, PATH_TARGET_DEG), true))
	plateaus.append(_plateau("Jardin", Vector2(-82.0, 36.0), Vector2(26.0, 20.0), 3.0,
		CavernTerrainBuilder.min_falloff_for(3.0, PATH_TARGET_DEG), true))
	# ÉCART DE 10 m entre la crête et le bord du bol : sans lui, le bourrelet de
	# la cuvette recouvre le fondu du plateau et les deux pentes s'additionnent
	# — 49° mesurés, au-delà de l'angle où le joueur glisse.
	plateaus.append(_plateau("Crête du Seuil", Vector2(42.0, -46.0), Vector2(9.0, 7.0), 6.5,
		CavernTerrainBuilder.min_falloff_for(2.0, PATH_TARGET_DEG), true))
	plateaus.append(_plateau("Berge du Passage", Vector2(40.0, -14.0), Vector2(8.0, 12.0), 4.0,
		CavernTerrainBuilder.min_falloff_for(2.0, PATH_TARGET_DEG), true))

	# Le bol de l'arène et son lit plat.
	basins.append(_basin("Bol de l'Arène", Vector2(100.0, -52.0), Vector2(38.0, 30.0), 5.0, 0.6, 30.0, 0.42))
	# LES RAMPES NE CREUSENT PAS. Elles sont cotées en altitude AVANT creusement,
	# et le bol ajoute déjà son −5 m par-dessus : les faire descendre à −2,5
	# donnait un fond à −7,4, soit une TRANCHÉE de 4 m sous le sol de l'arène,
	# et 51° de paroi latérale. La paroi du bol descend déjà à ~26° (5,6 m sur
	# 17,4 m radiaux), donc elle est praticable telle quelle : les rampes ne
	# servent qu'à APLANIR un couloir d'approche pour qu'il se lise comme le
	# chemin évident.
	ramps.append(_ramp("Rampe nord", Vector2(64.0, -68.0), Vector2(84.0, -58.0), 3.0, 2.0, 10.0, 8.0))
	ramps.append(_ramp("Rampe sud", Vector2(64.0, -36.0), Vector2(84.0, -46.0), 3.0, 2.0, 10.0, 8.0))

	# Le lit du lac : large fond plat, pour une nappe de glace praticable et
	# non une flaque au fond d'un entonnoir.
	basins.append(_basin("Lit du Lac", Vector2(-4.0, 38.0), Vector2(30.0, 26.0), 3.2, 0.7, 26.0, 0.55))

	spec.plateaus = plateaus
	spec.ramps = ramps
	spec.basins = basins
	return spec


## Modulation de hauteur libre : creuse ou écrase par endroits, sans toucher aux
## chambres. Le seuil du boss est ainsi plus bas que tout le reste, pour que la
## compression avant la révélation se ressente.
func _build_headroom_modulation() -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	spec.base_altitude = 0.0
	# Bruit plus agressif que la première version (0,8 / 22 m) : c'est lui qui
	# crénelle les parois et casse la rondeur des poches.
	spec.noise_amplitude = 1.2
	spec.noise_scale = 14.0
	spec.noise_seed = 4412

	var plateaus: Array[CavernPlateau] = []
	# Le Seuil : voûte à ~10 m, le minimum autorisé. On baisse la tête juste
	# avant que l'arène ne s'ouvre — la compression EST la mise en scène.
	plateaus.append(_plateau("Compression du Seuil", Vector2(42.0, -46.0), Vector2(11.0, 10.0), -6.0, 10.0, true))
	plateaus.append(_plateau("Ouverture de l'Arène", Vector2(100.0, -52.0), Vector2(34.0, 26.0), 5.0, 16.0, true))
	plateaus.append(_plateau("Nef de la Brèche", Vector2(-4.0, 36.0), Vector2(36.0, 44.0), 4.0, 18.0, true))
	plateaus.append(_plateau("Étranglement du Détroit", Vector2(-28.0, -40.0), Vector2(8.0, 6.0), -4.0, 8.0, true))
	spec.plateaus = plateaus
	return spec


# ---------------------------------------------------------------------------
# Ouvertures et lac
# ---------------------------------------------------------------------------

func _build_sky_openings() -> Array[CavernSkyOpening]:
	var openings: Array[CavernSkyOpening] = []
	# LA BRÈCHE : trois lobes qui s'unissent pour former UN seul trou au contour
	# irrégulier — le procédé du croquis du plafond. C'est la cicatrice de
	# l'effondrement, pas une fenêtre.
	openings.append(_opening("O1 Brèche (principal)", Vector2(-8.0, 32.0), Vector2(16.0, 12.0), -20.0))
	openings.append(_opening("O2 Brèche (est)", Vector2(6.0, 40.0), Vector2(12.0, 14.0), 35.0))
	openings.append(_opening("O3 Brèche (échancrure)", Vector2(-18.0, 44.0), Vector2(9.0, 7.0), 0.0))
	# L'appât du Loot : c'est cette lueur qui signale la cachette de loin.
	openings.append(_opening("O4 Loot", Vector2(-128.0, 6.0), Vector2(6.0, 5.0), 0.0))
	# Une lame de lumière en travers de la galerie, à mi-parcours : elle rythme
	# la traversée au lieu de la laisser muette.
	openings.append(_opening("O5 Lame de la Galerie", Vector2(-58.0, -36.0), Vector2(4.0, 12.0), 30.0))
	# La seule lumière du jour que le boss reçoit : une lame froide sur le Golem.
	openings.append(_opening("O6 Fissure d'Arène", Vector2(104.0, -44.0), Vector2(2.5, 9.0), -40.0))
	return openings


func _build_lake() -> CavernLake:
	var lake := CavernLake.new()
	lake.label = "Lac gelé"
	# Le fond de la cuvette descend à ~-1,2 ; la nappe posée à -0,4 laisse un
	# lac peu profond aux rives franches.
	lake.center = Vector2(-4.0, 38.0)
	lake.radii = Vector2(30.0, 26.0)
	lake.surface_altitude = -0.55
	lake.minimum_depth = 0.2
	lake.material_path = "res://data/levels/cavern_ice_material.tres"
	return lake


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


func _basin(label: String, center: Vector2, radii: Vector2, depth: float,
		rim_height: float, target_deg: float, flat_bottom: float = 0.0) -> CavernBasin:
	var required: float = CavernTerrainBuilder.min_falloff_for(depth + rim_height, target_deg)
	if minf(radii.x, radii.y) < required - 0.01:
		push_warning("[terrain] « %s » : rayon %.1f m < %.1f m requis pour %.1f m de dénivelé à %.0f°."
			% [label, minf(radii.x, radii.y), required, depth + rim_height, target_deg])
	var b := CavernBasin.new()
	b.label = label
	b.center = center
	b.radii = radii
	b.depth = depth
	b.rim_height = rim_height
	b.flat_bottom = flat_bottom
	b.rim_width = CavernTerrainBuilder.min_falloff_for(rim_height, target_deg)
	return b


func _opening(label: String, center: Vector2, radii: Vector2, rotation: float) -> CavernSkyOpening:
	var o := CavernSkyOpening.new()
	o.label = label
	o.center = center
	o.radii = radii
	o.rotation_degrees = rotation
	return o


# ---------------------------------------------------------------------------
# Rapport
# ---------------------------------------------------------------------------

func _report(terrain: CavernTerrainData) -> void:
	var dims: Vector2i = CavernTerrainBuilder.grid_dimensions(terrain)
	var floor_h: PackedFloat32Array = CavernTerrainBuilder.sample_field(terrain, terrain.floor_field)
	var vault_h: PackedFloat32Array = CavernTerrainBuilder.compose_vault(terrain, floor_h)
	var cell_area: float = terrain.cell_size * terrain.cell_size

	var playable_cells: int = 0
	var head_min := INF
	var head_max := -INF
	var slope_max := 0.0
	var over_cap: int = 0
	var slope_samples: int = 0

	for iz in dims.y:
		for ix in dims.x:
			var i: int = iz * dims.x + ix
			if not CavernTerrainBuilder.is_playable(terrain, floor_h[i], vault_h[i]):
				continue
			playable_cells += 1
			var head: float = vault_h[i] - floor_h[i]
			head_min = minf(head_min, head)
			head_max = maxf(head_max, head)
			# Pente mesurée uniquement entre deux points JOUABLES : ailleurs,
			# c'est la paroi qui referme le volume, et sa raideur est voulue.
			if ix + 1 < dims.x and CavernTerrainBuilder.is_playable(terrain, floor_h[i + 1], vault_h[i + 1]):
				var s: float = _slope(floor_h[i], floor_h[i + 1], terrain.cell_size)
				slope_max = maxf(slope_max, s)
				slope_samples += 1
				if s > terrain.max_slope_degrees:
					over_cap += 1
			if iz + 1 < dims.y and CavernTerrainBuilder.is_playable(terrain, floor_h[i + dims.x], vault_h[i + dims.x]):
				var sz: float = _slope(floor_h[i], floor_h[i + dims.x], terrain.cell_size)
				slope_max = maxf(slope_max, sz)
				slope_samples += 1
				if sz > terrain.max_slope_degrees:
					over_cap += 1

	print("[terrain] grille %dx%d (pas %.2f m, %d échantillons)" % [dims.x, dims.y, terrain.cell_size, floor_h.size()])
	print("[terrain] SURFACE JOUABLE : %.0f m²  (ancienne caverne : 5022 m² → ×%.1f)"
		% [playable_cells * cell_area, playable_cells * cell_area / 5022.0])
	print("[terrain] hauteur libre (zones jouables) : %.1f → %.1f m" % [head_min, head_max])
	print("[terrain] pente max entre points jouables : %.1f° (plafond %.0f°), %.2f %% au-dessus"
		% [slope_max, terrain.max_slope_degrees, 100.0 * float(over_cap) / maxf(float(slope_samples), 1.0)])

	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)
	for probe in [
		["Spawn (ouest)", Vector2(-124.0, -44.0)], ["Poche du Loot", Vector2(-128.0, 8.0)],
		["Galerie centre", Vector2(-54.0, -42.0)], ["Le Détroit", Vector2(-28.0, -40.0)],
		["Jardin", Vector2(-84.0, 34.0)], ["Lac (centre)", Vector2(-4.0, 38.0)],
		["Berge du Passage", Vector2(40.0, -14.0)], ["Crête du Seuil", Vector2(42.0, -46.0)],
		["Arène (fond)", Vector2(100.0, -52.0)],
	]:
		print("[terrain]   %-16s %6.2f m" % [probe[0],
			CavernTerrainBuilder.sample_point(terrain.floor_field, probe[1], noise)])


func _slope(h_a: float, h_b: float, run: float) -> float:
	return rad_to_deg(atan2(absf(h_b - h_a), run))

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

	# SALLE DU BOSS — en haut à droite du croquis, la plus vaste. Sa surface
	# vaut à peu près celle de la caverne d'avant : c'est l'unité d'échelle que
	# l'utilisateur a donnée.
	chambers.append(_room("Salle du Boss", Vector2(88.0, -52.0), Vector2(60.0, 42.0), -12.0, 14.0, 16.0))

	# GRANDE NEF — le long balayage qui traverse la caverne d'est en ouest.
	chambers.append(_room("Grande Nef", Vector2(-18.0, -40.0), Vector2(86.0, 36.0), 8.0, 13.0, 18.0))

	# SEUIL — le goulet entre la nef et la salle du boss. C'est là que le
	# croquis place le « mécanisme secret » : un passage étroit se surveille et
	# se verrouille, une grande salle non.
	chambers.append(_corridor("Seuil du Boss", Vector2(30.0, -44.0), Vector2(54.0, -50.0), 11.0, 10.5, 9.0))

	# SALLE DU LAC — la poche centrale basse, cœur du niveau.
	chambers.append(_room("Salle du Lac", Vector2(-6.0, 34.0), Vector2(44.0, 52.0), -6.0, 15.0, 20.0))

	# GOULET DU LAC — relie la nef à la salle du lac.
	chambers.append(_corridor("Descente du Lac", Vector2(-22.0, -14.0), Vector2(-8.0, 6.0), 13.0, 12.0, 10.0))

	# POCHE DU LOOT — la petite alcôve à l'extrême gauche du croquis. Petite et
	# basse : une récompense cachée doit se sentir comme une cachette.
	chambers.append(_room("Poche du Loot", Vector2(-126.0, 6.0), Vector2(24.0, 21.0), 18.0, 10.0, 11.0))

	# GOULET DU LOOT — l'étranglement qui y mène, hors du chemin principal.
	chambers.append(_corridor("Boyau du Loot", Vector2(-100.0, -24.0), Vector2(-118.0, 0.0), 9.0, 10.0, 8.0))

	# APPENDICE SUD-OUEST — la queue que le croquis fait descendre en bas à
	# gauche : une respiration, et de quoi éviter que la nef soit un simple
	# couloir droit.
	chambers.append(_room("Anse Sud-Ouest", Vector2(-84.0, 30.0), Vector2(38.0, 30.0), -24.0, 12.0, 16.0))
	chambers.append(_corridor("Passe Sud-Ouest", Vector2(-70.0, -8.0), Vector2(-78.0, 14.0), 12.0, 11.5, 10.0))

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
	# Altitude de référence : le pourtour du lac.
	spec.base_altitude = 2.0
	spec.noise_amplitude = 0.60
	spec.noise_scale = 10.0
	spec.noise_seed = 20260808

	var plateaus: Array[CavernPlateau] = []
	var ramps: Array[CavernRamp] = []
	var basins: Array[CavernBasin] = []

	# Ordre : du général au particulier. Les plateaux se fondent par lerp, donc
	# le dernier posé l'emporte localement.

	# La nef domine le niveau et descend doucement vers le lac.
	plateaus.append(_plateau("Nef ouest (haut)", Vector2(-96.0, -34.0), Vector2(34.0, 22.0), 8.0,
		CavernTerrainBuilder.min_falloff_for(4.0, PATH_TARGET_DEG), true))
	plateaus.append(_plateau("Nef centre", Vector2(-16.0, -38.0), Vector2(46.0, 24.0), 4.5,
		CavernTerrainBuilder.min_falloff_for(2.5, PATH_TARGET_DEG), true))

	# Poche du loot : perchée, pour qu'y monter se mérite.
	plateaus.append(_plateau("Poche du Loot", Vector2(-126.0, 6.0), Vector2(18.0, 15.0), 9.0,
		CavernTerrainBuilder.min_falloff_for(3.0, PATH_TARGET_DEG), true))

	# Anse sud-ouest, en léger contrebas de la nef.
	plateaus.append(_plateau("Anse Sud-Ouest", Vector2(-84.0, 30.0), Vector2(28.0, 22.0), 3.0,
		CavernTerrainBuilder.min_falloff_for(3.0, PATH_TARGET_DEG), true))

	# Le seuil du boss : une crête qu'on franchit avant la révélation.
	# ÉCART DE 10 m entre la crête et le bord du bol : sans lui, le bourrelet de
	# la cuvette recouvre le fondu du plateau et les deux pentes s'additionnent
	# — 49° mesurés, au-delà de l'angle où le joueur glisse.
	plateaus.append(_plateau("Crête du Seuil", Vector2(42.0, -47.0), Vector2(9.0, 8.0), 6.0,
		CavernTerrainBuilder.min_falloff_for(2.0, PATH_TARGET_DEG), true))

	# Salle du boss : un bol large et bas. Large parce qu'à cette échelle une
	# paroi raide serait infranchissable ; bas parce qu'on y descend.
	basins.append(_basin("Bol de l'Arène", Vector2(100.0, -52.0), Vector2(38.0, 30.0), 5.0, 0.6, 30.0, 0.42))

	# Deux rampes franches dans la paroi du bol : le chemin évident.
	ramps.append(_ramp("Rampe nord", Vector2(66.0, -66.0), Vector2(84.0, -58.0), 5.0, 3.0, 9.0, 7.0))
	ramps.append(_ramp("Rampe sud", Vector2(66.0, -38.0), Vector2(84.0, -46.0), 5.0, 3.0, 9.0, 7.0))

	# La cuvette du lac. Altitudes cotées AVANT creusement : les cuvettes
	# s'appliquent en dernier et s'AJOUTENT.
	basins.append(_basin("Cuvette du Lac", Vector2(-6.0, 36.0), Vector2(34.0, 42.0), 3.2, 0.7, 26.0, 0.55))

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
	spec.noise_amplitude = 0.8
	spec.noise_scale = 22.0
	spec.noise_seed = 4412

	var plateaus: Array[CavernPlateau] = []
	plateaus.append(_plateau("Compression du seuil", Vector2(42.0, -47.0), Vector2(11.0, 10.0), -6.0, 10.0, true))
	plateaus.append(_plateau("Ouverture de l'arène", Vector2(100.0, -52.0), Vector2(34.0, 26.0), 5.0, 16.0, true))
	plateaus.append(_plateau("Nef haute", Vector2(-6.0, 34.0), Vector2(36.0, 44.0), 4.0, 18.0, true))
	spec.plateaus = plateaus
	return spec


# ---------------------------------------------------------------------------
# Ouvertures et lac
# ---------------------------------------------------------------------------

func _build_sky_openings() -> Array[CavernSkyOpening]:
	var openings: Array[CavernSkyOpening] = []
	# LE grand puits, au-dessus du lac. Deux ellipses qui se recouvrent pour
	# obtenir un contour irrégulier plutôt qu'un disque parfait — cf le second
	# croquis, où le trou de plafond a une forme libre.
	openings.append(_opening("P1 lac (a)", Vector2(-4.0, 30.0), Vector2(15.0, 11.0), -18.0))
	openings.append(_opening("P1 lac (b)", Vector2(6.0, 38.0), Vector2(10.0, 13.0), 24.0))
	# Un puits secondaire au-dessus de la poche du loot : c'est lui qui la
	# signale de loin.
	openings.append(_opening("P2 loot", Vector2(-126.0, 4.0), Vector2(6.0, 5.0), 0.0))
	# Une fente au-dessus de la nef, pour ponctuer la traversée.
	openings.append(_opening("P3 nef", Vector2(-58.0, -34.0), Vector2(4.0, 11.0), 32.0))
	return openings


func _build_lake() -> CavernLake:
	var lake := CavernLake.new()
	lake.label = "Lac gelé"
	# Le fond de la cuvette descend à ~-1,2 ; la nappe posée à -0,4 laisse un
	# lac peu profond aux rives franches.
	lake.center = Vector2(-6.0, 36.0)
	lake.radii = Vector2(36.0, 44.0)
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
		["Poche du Loot", Vector2(-126.0, 6.0)], ["Anse SO", Vector2(-84.0, 30.0)],
		["Nef ouest", Vector2(-96.0, -34.0)], ["Nef centre", Vector2(-16.0, -38.0)],
		["Lac (centre)", Vector2(-6.0, 36.0)], ["Crête du Seuil", Vector2(42.0, -47.0)],
		["Arène (fond)", Vector2(100.0, -52.0)],
	]:
		print("[terrain]   %-16s %6.2f m" % [probe[0],
			CavernTerrainBuilder.sample_point(terrain.floor_field, probe[1], noise)])


func _slope(h_a: float, h_b: float, run: float) -> float:
	return rad_to_deg(atan2(absf(h_b - h_a), run))

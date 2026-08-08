extends SceneTree

## Rend la caverne en VUE DE DESSUS, sous forme d'image PNG.
##
##   godot --headless --path godot --script tools/render_cavern_map.gd
##   -> res://addons/godot_mcp/cache/screenshots/cavern_map.png
##
## Pourquoi une carte plutôt qu'une capture 3D : une silhouette, un découpage en
## zones et une circulation se jugent d'un seul regard à plat. En 3D, la brume
## et l'horizon cachent précisément ce qu'on cherche à évaluer.
##
## Lecture de la carte :
##   - roche pleine : gris très sombre
##   - sol jouable  : dégradé d'altitude (sombre = bas, clair = haut)
##   - parois       : la bande où la hauteur libre tombe sous le seuil jouable
##   - lac          : cyan
##   - ouvertures de voûte : liseré blanc
##   - repères      : croix + étiquette au centre de chaque chambre

const TERRAIN_PATH := "res://data/levels/level01_cavern_terrain.tres"
const OUTPUT_PATH := "res://addons/godot_mcp/cache/screenshots/cavern_map.png"

## Le rendu sert aussi à l'antichambre. `--terrain=<res://...>` et
## `--map-out=<res://...>` changent la cible sans dupliquer l'outil : juger un
## layout par une vue de dessus vaut mieux que par la 3D, quel que soit le
## layout.

## Pixels par mètre. 3 donne ~930 × 630 px sur l'emprise : assez pour lire les
## goulets, assez petit pour tenir à l'écran.
const PIXELS_PER_METER := 3

const COLOR_ROCK := Color(0.055, 0.065, 0.085)
const COLOR_WALL := Color(0.13, 0.16, 0.21)
const COLOR_LOW := Color(0.16, 0.24, 0.34)
const COLOR_HIGH := Color(0.72, 0.80, 0.88)
const COLOR_LAKE := Color(0.25, 0.62, 0.78)
const COLOR_OPENING := Color(1.0, 1.0, 1.0)
const COLOR_MARK := Color(1.0, 0.72, 0.36)


func _init() -> void:
	var terrain_path: String = _arg("--terrain=", TERRAIN_PATH)
	var output_path: String = _arg("--map-out=", OUTPUT_PATH)
	var terrain: CavernTerrainData = load(terrain_path) as CavernTerrainData
	if terrain == null:
		push_error("Terrain introuvable : %s" % TERRAIN_PATH)
		quit(1)
		return

	var span: Vector2 = terrain.bounds_max - terrain.bounds_min
	var width: int = int(span.x) * PIXELS_PER_METER
	var height: int = int(span.y) * PIXELS_PER_METER
	var image := Image.create_empty(width, height, false, Image.FORMAT_RGB8)

	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)
	var head_noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.headroom_field)

	# Première passe : bornes d'altitude sur les zones jouables uniquement,
	# sinon la roche pleine écraserait le dégradé.
	var low := INF
	var high := -INF
	for py in height:
		for px in width:
			var p: Vector2 = _to_world(terrain, px, py, width, height)
			if CavernTerrainBuilder.chamber_mask(terrain, p) <= 0.0:
				continue
			var h: float = CavernTerrainBuilder.sample_point(terrain.floor_field, p, noise)
			low = minf(low, h)
			high = maxf(high, h)

	for py in height:
		for px in width:
			var p: Vector2 = _to_world(terrain, px, py, width, height)
			image.set_pixel(px, py, _color_at(terrain, p, noise, head_noise, low, high))

	_draw_openings(image, terrain, width, height)
	_draw_chamber_marks(image, terrain, width, height)

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(output_path).get_base_dir())
	if image.save_png(ProjectSettings.globalize_path(output_path)) != OK:
		push_error("Échec d'écriture de la carte")
		quit(1)
		return
	print("[carte] écrite : %s (%d × %d px, %.0f × %.0f m)" % [output_path, width, height, span.x, span.y])
	print("[carte] altitudes jouables : %.1f → %.1f m" % [low, high])
	quit(0)


func _to_world(terrain: CavernTerrainData, px: int, py: int, width: int, height: int) -> Vector2:
	# +Z pointe vers le BAS de l'image, comme sur un plan vu du dessus.
	return Vector2(
		lerpf(terrain.bounds_min.x, terrain.bounds_max.x, float(px) / float(width - 1)),
		lerpf(terrain.bounds_min.y, terrain.bounds_max.y, float(py) / float(height - 1)))


func _color_at(terrain: CavernTerrainData, p: Vector2, noise: FastNoiseLite,
		head_noise: FastNoiseLite, low: float, high: float) -> Color:
	var mask: float = CavernTerrainBuilder.chamber_mask(terrain, p)
	if mask <= 0.0:
		return COLOR_ROCK

	var floor_height: float = CavernTerrainBuilder.sample_point(terrain.floor_field, p, noise)
	var target: float = CavernTerrainBuilder.chamber_headroom(terrain, p)
	if terrain.headroom_field != null:
		target += CavernTerrainBuilder.sample_point(terrain.headroom_field, p, head_noise)
	var clearance: float = clampf(target, terrain.min_headroom, terrain.max_headroom) * mask

	if clearance < terrain.playable_headroom_threshold:
		# Paroi : on la teinte selon sa progression vers la roche, pour que
		# l'épaisseur des murs se lise.
		return COLOR_ROCK.lerp(COLOR_WALL, clearance / maxf(terrain.playable_headroom_threshold, 0.001))

	if terrain.lake != null and CavernTerrainBuilder.is_in_lake_footprint(terrain, p) \
			and terrain.lake.surface_altitude - floor_height >= terrain.lake.minimum_depth:
		var depth: float = terrain.lake.surface_altitude - floor_height
		return COLOR_LAKE.darkened(clampf(depth * 0.06, 0.0, 0.35))

	var t: float = inverse_lerp(low, high, floor_height)
	return COLOR_LOW.lerp(COLOR_HIGH, clampf(t, 0.0, 1.0))


func _draw_openings(image: Image, terrain: CavernTerrainData, width: int, height: int) -> void:
	for py in height:
		for px in width:
			var p: Vector2 = _to_world(terrain, px, py, width, height)
			if not CavernTerrainBuilder.is_in_sky_opening(terrain, p):
				continue
			# Contour seulement : un disque plein masquerait le sol dessous.
			var edge: bool = false
			for offset in [Vector2(1.2, 0.0), Vector2(-1.2, 0.0), Vector2(0.0, 1.2), Vector2(0.0, -1.2)]:
				if not CavernTerrainBuilder.is_in_sky_opening(terrain, p + offset):
					edge = true
					break
			if edge:
				image.set_pixel(px, py, COLOR_OPENING)


func _draw_chamber_marks(image: Image, terrain: CavernTerrainData, width: int, height: int) -> void:
	for chamber in terrain.chambers:
		var anchor: Vector2 = chamber.center
		if chamber.is_corridor:
			anchor = (chamber.center + chamber.to_center) * 0.5
		var px: int = int(round(inverse_lerp(terrain.bounds_min.x, terrain.bounds_max.x, anchor.x) * float(width - 1)))
		var py: int = int(round(inverse_lerp(terrain.bounds_min.y, terrain.bounds_max.y, anchor.y) * float(height - 1)))
		for d in range(-5, 6):
			_plot(image, px + d, py, width, height)
			_plot(image, px, py + d, width, height)


func _plot(image: Image, px: int, py: int, width: int, height: int) -> void:
	if px < 0 or py < 0 or px >= width or py >= height:
		return
	image.set_pixel(px, py, COLOR_MARK)


## Lit une option de ligne de commande, ou retourne la valeur par défaut.
func _arg(prefix: String, fallback: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	for a in OS.get_cmdline_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback

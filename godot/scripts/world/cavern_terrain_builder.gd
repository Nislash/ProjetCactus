## Générateur du terrain de la caverne (niveau 1).
##
## Consomme une [CavernTerrainData] et produit un volume clos de forme
## organique. Cf ADR `docs/tech/level01_terrain.md`.
##
## LE PRINCIPE, EN UNE PHRASE : la caverne est creusée dans de la roche pleine.
## Le masque des chambres dit où elle existe ; partout ailleurs la hauteur libre
## vaut zéro, donc la voûte descend au contact du sol et le volume SE REFERME
## TOUT SEUL. Il n'y a ni parois à générer séparément, ni jonction à surveiller :
## l'étanchéité est une propriété de la construction.
##
## Structure produite sous ce nœud :
##   CavernTerrain
##   ├── Floor/Chunk_x_z   MeshInstance3D + StaticBody3D (HeightMapShape3D)
##   ├── Vault/Chunk_x_z   idem, maillage TROUÉ aux ouvertures, collision PLEINE
##   └── Lake              nappe plane, sans collision
##
## Le découpage en tuiles n'est pas cosmétique : à cette échelle, un maillage
## unique serait toujours dessiné en entier et le frustum culling ne servirait
## plus à rien.
##
## Les fonctions d'échantillonnage sont STATIQUES ET PURES, pour que les tests
## les appellent sans construire de scène.

class_name CavernTerrainBuilder
extends Node3D

## Couche physique du monde.
const WORLD_COLLISION_LAYER: int = 1

## Bit porté UNIQUEMENT par le sol praticable, pour que la cuisson du navmesh
## sache quoi parser. Godot avertit que parser des maillages VISUELS exige un
## readback GPU — coûteux, et inopérant en headless donc intestable en CI.
## Parser les collisions est la voie recommandée, et le masque de collision en
## est le seul filtre.
const NAVMESH_SOURCE_LAYER: int = 128

const DEFAULT_DATA_PATH := "res://data/levels/level01_cavern_terrain.tres"

@export var data: CavernTerrainData
@export_file("*.tres") var data_path: String = DEFAULT_DATA_PATH

@export var floor_material: Material
@export var vault_material: Material
@export_file("*.tres") var floor_material_path: String = "res://data/levels/cavern_floor_material.tres"
@export_file("*.tres") var vault_material_path: String = "res://data/levels/cavern_vault_material.tres"

@export var build_on_ready: bool = true

## Émis quand la construction est terminée, avec le nombre de tuiles produites.
signal terrain_built(chunk_count: int)


func _ready() -> void:
	if build_on_ready:
		build()


func _resolve_data() -> void:
	if data == null and not data_path.is_empty():
		data = load(data_path) as CavernTerrainData
	if floor_material == null:
		floor_material = load(floor_material_path) as Material
	if vault_material == null:
		vault_material = load(vault_material_path) as Material


## Reconstruit intégralement le terrain. Idempotent.
func build() -> void:
	_resolve_data()
	assert(data != null, "CavernTerrainBuilder : aucune CavernTerrainData assignée.")
	assert(data.floor_field != null, "CavernTerrainBuilder : floor_field manquant.")

	for child in get_children():
		child.queue_free()

	var dims: Vector2i = grid_dimensions(data)
	var floor_heights: PackedFloat32Array = sample_field(data, data.floor_field)
	var vault_heights: PackedFloat32Array = compose_vault(data, floor_heights)

	var chunks := Vector2i(
		maxi(int(ceil((data.bounds_max.x - data.bounds_min.x) / data.chunk_size)), 1),
		maxi(int(ceil((data.bounds_max.y - data.bounds_min.y) / data.chunk_size)), 1))

	var floor_root := _make_root("Floor")
	var vault_root := _make_root("Vault")
	var built: int = 0

	for cz in chunks.y:
		for cx in chunks.x:
			var range_x := _chunk_range(cx, chunks.x, dims.x)
			var range_z := _chunk_range(cz, chunks.y, dims.y)
			if range_x.y <= range_x.x or range_z.y <= range_z.x:
				continue
			# Une tuile entièrement dans la roche pleine n'a aucune surface
			# jouable : la générer coûterait de la géométrie pour rien.
			if not _chunk_has_volume(floor_heights, vault_heights, dims, range_x, range_z):
				continue
			_build_chunk(floor_root, "Floor", cx, cz, floor_heights, dims, range_x, range_z,
				floor_material, false, WORLD_COLLISION_LAYER | NAVMESH_SOURCE_LAYER, false)
			_build_chunk(vault_root, "Vault", cx, cz, vault_heights, dims, range_x, range_z,
				vault_material, true, WORLD_COLLISION_LAYER, true)
			built += 1

	_build_lake(floor_heights, dims)
	terrain_built.emit(built)


# ---------------------------------------------------------------------------
# Silhouette : le masque des chambres
# ---------------------------------------------------------------------------

## Appartenance au volume en un point : 1 au cœur d'une chambre, 0 dans la roche
## pleine, dégradé sur `edge_softness` entre les deux. Les chambres s'unissent
## par le MAXIMUM — deux poches qui se recouvrent forment une seule salle, sans
## sur-creusement à leur intersection.
static func chamber_mask(terrain: CavernTerrainData, p: Vector2) -> float:
	var best: float = 0.0
	for chamber in terrain.chambers:
		best = maxf(best, _chamber_weight(chamber, p))
		if best >= 1.0:
			return 1.0
	return best


## Hauteur libre visée par les chambres en un point, pondérée par leur
## appartenance. Une salle basse voisine d'une nef haute donne une transition
## continue plutôt qu'une marche.
static func chamber_headroom(terrain: CavernTerrainData, p: Vector2) -> float:
	var total_weight: float = 0.0
	var total_headroom: float = 0.0
	for chamber in terrain.chambers:
		var w: float = _chamber_weight(chamber, p)
		if w <= 0.0:
			continue
		total_weight += w
		total_headroom += chamber.headroom * w
	if total_weight <= 0.0:
		return 0.0
	return total_headroom / total_weight


static func _chamber_weight(chamber: CavernChamber, p: Vector2) -> float:
	var outside: float = _chamber_distance_outside(chamber, p)
	if outside <= 0.0:
		return 1.0
	if chamber.edge_softness <= 0.0:
		return 0.0
	return smoothstep(1.0, 0.0, clampf(outside / chamber.edge_softness, 0.0, 1.0))


## Distance en mètres entre le point et le bord de la chambre (0 à l'intérieur).
static func _chamber_distance_outside(chamber: CavernChamber, p: Vector2) -> float:
	var rx: float = maxf(chamber.radii.x, 0.001)

	if chamber.is_corridor:
		# Capsule : distance au segment, moins la demi-largeur.
		var axis: Vector2 = chamber.to_center - chamber.center
		var length_sq: float = axis.length_squared()
		var closest: Vector2 = chamber.center
		if length_sq > 0.0001:
			closest = chamber.center + axis * clampf((p - chamber.center).dot(axis) / length_sq, 0.0, 1.0)
		return maxf(p.distance_to(closest) - rx, 0.0)

	# Ellipse orientée : on ramène le point dans le repère de l'ellipse, on
	# normalise par les rayons, puis on reconvertit l'écart en mètres via le
	# plus PETIT rayon — sinon l'adoucissement changerait de largeur selon la
	# direction, et une ellipse allongée aurait des bords incohérents.
	var rz: float = maxf(chamber.radii.y, 0.001)
	var local: Vector2 = (p - chamber.center).rotated(-deg_to_rad(chamber.rotation_degrees))
	var norm: float = Vector2(local.x / rx, local.y / rz).length()
	if norm <= 1.0:
		return 0.0
	return (norm - 1.0) * minf(rx, rz)


# ---------------------------------------------------------------------------
# Champs de hauteurs
# ---------------------------------------------------------------------------

static func grid_dimensions(terrain: CavernTerrainData) -> Vector2i:
	var span: Vector2 = terrain.bounds_max - terrain.bounds_min
	return Vector2i(
		int(round(span.x / terrain.cell_size)) + 1,
		int(round(span.y / terrain.cell_size)) + 1)


static func sample_position(terrain: CavernTerrainData, ix: int, iz: int) -> Vector2:
	return terrain.bounds_min + Vector2(float(ix), float(iz)) * terrain.cell_size


## Adoucissement MINIMAL pour qu'une transition d'altitude reste praticable.
##
## Le fondu des primitives utilise un `smoothstep`, dont la pente maximale vaut
## 1,5 fois la pente moyenne. Dimensionner à l'œil sur `delta / falloff`
## sous-estime donc la pente réelle de 50 %.
static func min_falloff_for(delta_altitude: float, max_slope_degrees: float) -> float:
	var slope: float = tan(deg_to_rad(clampf(max_slope_degrees, 1.0, 89.0)))
	return 1.5 * absf(delta_altitude) / maxf(slope, 0.001)


static func sample_field(terrain: CavernTerrainData, spec: CavernHeightfieldSpec) -> PackedFloat32Array:
	var dims: Vector2i = grid_dimensions(terrain)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(dims.x * dims.y)
	var noise: FastNoiseLite = make_noise(spec)
	for iz in dims.y:
		for ix in dims.x:
			heights[iz * dims.x + ix] = sample_point(spec, sample_position(terrain, ix, iz), noise)
	return heights


static func make_noise(spec: CavernHeightfieldSpec) -> FastNoiseLite:
	if spec == null or spec.noise_amplitude <= 0.0:
		return null
	var noise := FastNoiseLite.new()
	noise.seed = spec.noise_seed
	noise.frequency = 1.0 / maxf(spec.noise_scale, 0.001)
	return noise


static func sample_point(spec: CavernHeightfieldSpec, p: Vector2, noise: FastNoiseLite) -> float:
	var height: float = spec.base_altitude

	for plateau in spec.plateaus:
		var w: float = _plateau_weight(plateau, p)
		if w > 0.0:
			height = lerpf(height, plateau.altitude, w)

	for ramp in spec.ramps:
		var result: Array = _ramp_weight_and_altitude(ramp, p)
		if result[0] > 0.0:
			height = lerpf(height, result[1], result[0])

	# Le bruit est appliqué AVANT les cuvettes : les margelles doivent rester
	# des bordures nettes, sinon la garantie anti-chute devient statistique.
	if noise != null:
		height += noise.get_noise_2d(p.x, p.y) * spec.noise_amplitude

	for basin in spec.basins:
		height += _basin_offset(basin, p)

	return height


## Compose la voûte : `sol + hauteur libre`, la hauteur libre étant celle des
## chambres, modulée puis bornée, et RAMENÉE À ZÉRO hors de la silhouette.
##
## C'est ici que le volume se referme. Là où le masque vaut 0, voûte = sol : il
## n'y a plus d'espace, donc plus de caverne, donc rien à sceller.
static func compose_vault(terrain: CavernTerrainData, floor_heights: PackedFloat32Array) -> PackedFloat32Array:
	var dims: Vector2i = grid_dimensions(terrain)
	var modulation: PackedFloat32Array = PackedFloat32Array()
	if terrain.headroom_field != null:
		modulation = sample_field(terrain, terrain.headroom_field)

	var vault: PackedFloat32Array = PackedFloat32Array()
	vault.resize(floor_heights.size())
	for iz in dims.y:
		for ix in dims.x:
			var i: int = iz * dims.x + ix
			var p: Vector2 = sample_position(terrain, ix, iz)
			var mask: float = chamber_mask(terrain, p)
			if mask <= 0.0:
				vault[i] = floor_heights[i]
				continue
			var target: float = chamber_headroom(terrain, p)
			if not modulation.is_empty():
				target += modulation[i]
			target = clampf(target, terrain.min_headroom, terrain.max_headroom)
			# Le masque multiplie APRÈS le bornage : la hauteur libre décroît
			# donc continûment de sa valeur intérieure à zéro sur la largeur de
			# l'adoucissement, ce qui dessine la paroi.
			vault[i] = floor_heights[i] + target * mask
	return vault


## Vrai si le point appartient au volume JOUABLE (assez de hauteur libre pour
## s'y tenir), par opposition à la paroi qui le referme.
static func is_playable(terrain: CavernTerrainData, floor_height: float, vault_height: float) -> bool:
	return (vault_height - floor_height) >= terrain.playable_headroom_threshold


## Vrai si le point est dans l'emprise du lac. Sans ce filtre, tout point bas de
## la caverne se retrouverait sous l'eau.
static func is_in_lake_footprint(terrain: CavernTerrainData, p: Vector2) -> bool:
	if terrain.lake == null:
		return false
	var rx: float = maxf(terrain.lake.radii.x, 0.001)
	var rz: float = maxf(terrain.lake.radii.y, 0.001)
	var d: Vector2 = p - terrain.lake.center
	return Vector2(d.x / rx, d.y / rz).length() <= 1.0


## Ramène un point sur le BORD des ouvertures s'il est à l'intérieur.
##
## Sans cela, le contour du trou suit la grille d'échantillonnage : à 1,5 m de
## pas, on obtient un escalier de 1,5 m de marche, et une ouverture censée être
## ronde se lit comme un polygone taillé à la hache.
##
## En poussant les sommets intérieurs sur l'ellipse, le bord épouse exactement
## la forme voulue quelle que soit la résolution du terrain — et le trou peut
## même être plus petit qu'une maille.
##
## Itéré : projeter hors d'une ellipse peut faire tomber dans une voisine, et
## les ouvertures se recouvrent exprès pour composer un contour irrégulier.
static func project_out_of_openings(terrain: CavernTerrainData, p: Vector2) -> Vector2:
	var point: Vector2 = p
	for _pass in 4:
		var deepest: CavernSkyOpening = null
		var deepest_norm: float = 1.0
		for opening in terrain.sky_openings:
			var rx: float = maxf(opening.radii.x, 0.001)
			var rz: float = maxf(opening.radii.y, 0.001)
			var local: Vector2 = (point - opening.center).rotated(-deg_to_rad(opening.rotation_degrees))
			var norm: float = Vector2(local.x / rx, local.y / rz).length()
			if norm < deepest_norm:
				deepest_norm = norm
				deepest = opening
		if deepest == null:
			return point

		var rx2: float = maxf(deepest.radii.x, 0.001)
		var rz2: float = maxf(deepest.radii.y, 0.001)
		var angle: float = deg_to_rad(deepest.rotation_degrees)
		var local2: Vector2 = (point - deepest.center).rotated(-angle)
		var norm2: float = Vector2(local2.x / rx2, local2.y / rz2).length()
		if norm2 < 0.0001:
			# Pile au centre : aucune direction de sortie, on en choisit une.
			local2 = Vector2(rx2, 0.0)
		else:
			local2 /= norm2
		point = deepest.center + local2.rotated(angle)
	return point


static func is_in_sky_opening(terrain: CavernTerrainData, p: Vector2) -> bool:
	for opening in terrain.sky_openings:
		var local: Vector2 = (p - opening.center).rotated(-deg_to_rad(opening.rotation_degrees))
		var rx: float = maxf(opening.radii.x, 0.001)
		var rz: float = maxf(opening.radii.y, 0.001)
		if Vector2(local.x / rx, local.y / rz).length() <= 1.0:
			return true
	return false


# ---------------------------------------------------------------------------
# Primitives de relief
# ---------------------------------------------------------------------------

static func _plateau_weight(plateau: CavernPlateau, p: Vector2) -> float:
	var d: Vector2 = (p - plateau.center).abs()
	var outside: float
	if plateau.is_ellipse:
		var rx: float = maxf(plateau.half_extent.x, 0.001)
		var rz: float = maxf(plateau.half_extent.y, 0.001)
		outside = (Vector2(d.x / rx, d.y / rz).length() - 1.0) * minf(rx, rz)
	else:
		outside = Vector2(
			maxf(d.x - plateau.half_extent.x, 0.0),
			maxf(d.y - plateau.half_extent.y, 0.0)).length()
	if outside <= 0.0:
		return 1.0
	if plateau.falloff <= 0.0:
		return 0.0
	return smoothstep(1.0, 0.0, clampf(outside / plateau.falloff, 0.0, 1.0))


static func _ramp_weight_and_altitude(ramp: CavernRamp, p: Vector2) -> Array:
	var axis: Vector2 = ramp.to_point - ramp.from_point
	var length_sq: float = axis.length_squared()
	if length_sq < 0.0001:
		return [0.0, ramp.from_altitude]

	var t: float = clampf((p - ramp.from_point).dot(axis) / length_sq, 0.0, 1.0)
	var altitude: float = lerpf(ramp.from_altitude, ramp.to_altitude, t)
	var lateral: float = p.distance_to(ramp.from_point + axis * t)
	var half_width: float = ramp.width * 0.5

	if lateral <= half_width:
		return [1.0, altitude]
	if ramp.falloff <= 0.0:
		return [0.0, altitude]
	return [smoothstep(1.0, 0.0, clampf((lateral - half_width) / ramp.falloff, 0.0, 1.0)), altitude]


## Décalage dû à une cuvette : négatif au fond, POSITIF sur la margelle. C'est
## ce bourrelet qui interdit la chute. La crête de la margelle EST le bord :
## sans ça, l'offset sauterait de 0 à `rim_height` d'un échantillon à l'autre.
static func _basin_offset(basin: CavernBasin, p: Vector2) -> float:
	var rx: float = maxf(basin.radii.x, 0.001)
	var rz: float = maxf(basin.radii.y, 0.001)
	var norm: float = Vector2((p.x - basin.center.x) / rx, (p.y - basin.center.y) / rz).length()

	if norm <= 1.0:
		# Fond plat au centre, puis remontée vers la crête de la margelle. La
		# crête EST le bord : sans ça, l'offset sauterait de 0 à `rim_height`
		# d'un échantillon à l'autre et créerait une falaise invisible.
		if norm <= basin.flat_bottom:
			return -basin.depth
		var t: float = inverse_lerp(basin.flat_bottom, 1.0, norm)
		return lerpf(-basin.depth, basin.rim_height, smoothstep(0.0, 1.0, t))
	if basin.rim_width <= 0.0 or basin.rim_height <= 0.0:
		return 0.0
	var outside_m: float = (norm - 1.0) * minf(rx, rz)
	if outside_m >= basin.rim_width:
		return 0.0
	return basin.rim_height * smoothstep(1.0, 0.0, clampf(outside_m / basin.rim_width, 0.0, 1.0))


# ---------------------------------------------------------------------------
# Construction de la géométrie
# ---------------------------------------------------------------------------

func _make_root(surface_name: String) -> Node3D:
	var root := Node3D.new()
	root.name = surface_name
	add_child(root)
	root.owner = owner
	return root


## Bornes d'index d'une tuile, avec UN échantillon de recouvrement sur la
## dernière colonne/ligne : sans lui, deux tuiles voisines laisseraient une
## fente d'un pas entre elles.
func _chunk_range(chunk_index: int, chunk_count: int, sample_count: int) -> Vector2i:
	var per_chunk: int = maxi(int(ceil(float(sample_count - 1) / float(chunk_count))), 1)
	var start: int = chunk_index * per_chunk
	var end: int = mini(start + per_chunk, sample_count - 1)
	return Vector2i(start, end)


func _chunk_has_volume(
	floor_heights: PackedFloat32Array,
	vault_heights: PackedFloat32Array,
	dims: Vector2i,
	range_x: Vector2i,
	range_z: Vector2i
) -> bool:
	for iz in range(range_z.x, range_z.y + 1):
		for ix in range(range_x.x, range_x.y + 1):
			var i: int = iz * dims.x + ix
			if vault_heights[i] - floor_heights[i] > 0.05:
				return true
	return false


func _build_chunk(
	parent: Node3D,
	surface_name: String,
	cx: int,
	cz: int,
	heights: PackedFloat32Array,
	dims: Vector2i,
	range_x: Vector2i,
	range_z: Vector2i,
	material: Material,
	flip_faces: bool,
	collision_layer: int,
	punch_openings: bool
) -> void:
	var chunk := Node3D.new()
	chunk.name = "Chunk_%d_%d" % [cx, cz]
	parent.add_child(chunk)
	chunk.owner = owner

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = _build_chunk_mesh(heights, dims, range_x, range_z, flip_faces, punch_openings)
	if material != null:
		mesh_instance.material_override = material
	chunk.add_child(mesh_instance)
	mesh_instance.owner = owner

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = collision_layer
	chunk.add_child(body)
	body.owner = owner

	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = _build_chunk_shape(heights, dims, range_x, range_z)
	# HeightMapShape3D échantillonne à 1 unité et se centre sur son origine :
	# on le remet à l'échelle et on le recentre sur l'emprise de la tuile.
	collision.scale = Vector3(data.cell_size, 1.0, data.cell_size)
	var corner_min: Vector2 = sample_position(data, range_x.x, range_z.x)
	var corner_max: Vector2 = sample_position(data, range_x.y, range_z.y)
	var center: Vector2 = (corner_min + corner_max) * 0.5
	collision.position = Vector3(center.x, 0.0, center.y)
	body.add_child(collision)
	collision.owner = owner


func _build_chunk_mesh(
	heights: PackedFloat32Array,
	dims: Vector2i,
	range_x: Vector2i,
	range_z: Vector2i,
	flip_faces: bool,
	punch_openings: bool
) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var emitted: int = 0

	for iz in range(range_z.x, range_z.y):
		for ix in range(range_x.x, range_x.y):
			var p00: Vector2 = sample_position(data, ix, iz)
			var p10: Vector2 = sample_position(data, ix + 1, iz)
			var p01: Vector2 = sample_position(data, ix, iz + 1)
			var p11: Vector2 = sample_position(data, ix + 1, iz + 1)

			var h00: float = heights[iz * dims.x + ix]
			var h10: float = heights[iz * dims.x + ix + 1]
			var h01: float = heights[(iz + 1) * dims.x + ix]
			var h11: float = heights[(iz + 1) * dims.x + ix + 1]

			# Un quad n'est percé que si ses QUATRE coins sont dans l'ouverture :
			# le bord du trou reste ainsi net et fermé.
			if punch_openings and is_in_sky_opening(data, p00) and is_in_sky_opening(data, p10) \
					and is_in_sky_opening(data, p01) and is_in_sky_opening(data, p11):
				continue

			# Sur les quads du BORD du trou, les sommets intérieurs sont poussés
			# sur l'ellipse : le contour épouse la forme voulue au lieu de suivre
			# la grille. L'altitude est conservée, seul le plan (X, Z) bouge.
			if punch_openings:
				p00 = project_out_of_openings(data, p00)
				p10 = project_out_of_openings(data, p10)
				p01 = project_out_of_openings(data, p01)
				p11 = project_out_of_openings(data, p11)

			var v00 := Vector3(p00.x, h00, p00.y)
			var v10 := Vector3(p10.x, h10, p10.y)
			var v01 := Vector3(p01.x, h01, p01.y)
			var v11 := Vector3(p11.x, h11, p11.y)

			# ORDRE DES SOMMETS : Godot considère comme face AVANT celle dont
			# les sommets tournent dans le SENS HORAIRE vus de face. Inverser
			# ces branches rend la surface invisible sans qu'aucune erreur ne
			# soit signalée — on voit alors le fond à travers.
			if flip_faces:
				_add_triangle(st, v00, v11, v10)
				_add_triangle(st, v00, v01, v11)
			else:
				_add_triangle(st, v00, v10, v11)
				_add_triangle(st, v00, v11, v01)
			emitted += 1

	if emitted == 0:
		return ArrayMesh.new()
	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# UV planaires : le shader de roche est tri-planaire et n'en dépend pas,
	# mais les tangentes en ont besoin pour le micro-relief.
	st.set_uv(Vector2(a.x, a.z) * 0.1)
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z) * 0.1)
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z) * 0.1)
	st.add_vertex(c)


func _build_chunk_shape(
	heights: PackedFloat32Array,
	dims: Vector2i,
	range_x: Vector2i,
	range_z: Vector2i
) -> HeightMapShape3D:
	var width: int = range_x.y - range_x.x + 1
	var depth: int = range_z.y - range_z.x + 1
	var slice: PackedFloat32Array = PackedFloat32Array()
	slice.resize(width * depth)
	for iz in depth:
		for ix in width:
			slice[iz * width + ix] = heights[(range_z.x + iz) * dims.x + range_x.x + ix]

	var shape := HeightMapShape3D.new()
	shape.map_width = width
	shape.map_depth = depth
	shape.map_data = slice
	return shape


## Nappe du lac : une surface plane, dessinée là où le sol passe sous elle ET où
## la caverne existe. Sans collision — le fond du lac reste le sol praticable.
func _build_lake(floor_heights: PackedFloat32Array, dims: Vector2i) -> void:
	if data.lake == null:
		return

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var level: float = data.lake.surface_altitude
	var emitted: int = 0

	for iz in dims.y - 1:
		for ix in dims.x - 1:
			var corners := [
				Vector2i(ix, iz), Vector2i(ix + 1, iz), Vector2i(ix, iz + 1), Vector2i(ix + 1, iz + 1),
			]
			var submerged: bool = true
			for c in corners:
				var h: float = floor_heights[c.y * dims.x + c.x]
				if level - h < data.lake.minimum_depth:
					submerged = false
					break
			if not submerged:
				continue
			var p: Vector2 = sample_position(data, ix, iz)
			if chamber_mask(data, p) <= 0.0:
				continue
			if not is_in_lake_footprint(data, p):
				continue

			var v00 := Vector3(p.x, level, p.y)
			var p11: Vector2 = sample_position(data, ix + 1, iz + 1)
			var v10 := Vector3(p11.x, level, p.y)
			var v01 := Vector3(p.x, level, p11.y)
			var v11 := Vector3(p11.x, level, p11.y)
			_add_triangle(st, v00, v10, v11)
			_add_triangle(st, v00, v11, v01)
			emitted += 1

	if emitted == 0:
		return

	st.generate_normals()
	st.generate_tangents()
	var lake_instance := MeshInstance3D.new()
	lake_instance.name = "Lake"
	lake_instance.mesh = st.commit()
	if not data.lake.material_path.is_empty():
		lake_instance.material_override = load(data.lake.material_path) as Material
	add_child(lake_instance)
	lake_instance.owner = owner

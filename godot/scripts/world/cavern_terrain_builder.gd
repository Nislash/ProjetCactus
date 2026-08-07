## Générateur du terrain de la caverne (niveau 1).
##
## Consomme une [CavernTerrainData] et produit la géométrie du volume clos :
## sol vallonné, voûte percée de puits de ciel, et ceinture de parois qui
## referme le périmètre. Cf ADR `docs/tech/level01_terrain.md`.
##
## Structure produite sous ce nœud :
##   CavernTerrain (ce nœud)
##   ├── Floor   : MeshInstance3D + StaticBody3D/CollisionShape3D (HeightMapShape3D)
##   ├── Vault   : MeshInstance3D (TROUÉ) + StaticBody3D/CollisionShape3D (PLEIN)
##   └── Walls   : MeshInstance3D + StaticBody3D/CollisionShape3D (trimesh)
##
## Le maillage de la voûte est troué aux puits de ciel mais sa collision ne
## l'est pas : c'est ce qui garantit « on voit le ciel, on ne sort jamais » sans
## poser un seul bouchon invisible à la main.
##
## Les fonctions de calcul du champ de hauteurs sont **statiques et pures** pour
## que les tests puissent les appeler sans construire de scène
## (cf `godot/tests/test_cavern_terrain.gd`).

class_name CavernTerrainBuilder
extends Node3D

## Données de terrain à matérialiser.
@export var data: CavernTerrainData

## Matériau du sol (provisoire au blockout ; le PBR arrive en E3).
@export var floor_material: Material

## Matériau de la voûte et des parois.
@export var rock_material: Material

## Reconstruit le terrain au `_ready`. Laisser vrai : le terrain est dérivé de
## la donnée, il n'a pas à être sérialisé dans la scène.
@export var build_on_ready: bool = true


func _ready() -> void:
	if build_on_ready and data != null:
		build()


## Reconstruit intégralement le terrain. Idempotent : purge d'abord ce qui a été
## généré précédemment, pour qu'une réitération sur les données ne laisse aucun
## résidu.
func build() -> void:
	assert(data != null, "CavernTerrainBuilder : aucune CavernTerrainData assignée.")
	assert(data.floor_field != null, "CavernTerrainBuilder : floor_field manquant.")
	assert(data.vault_field != null, "CavernTerrainBuilder : vault_field manquant.")

	for child in get_children():
		child.queue_free()

	var dims: Vector2i = grid_dimensions(data)
	var floor_heights: PackedFloat32Array = sample_field(data, data.floor_field)
	var vault_heights: PackedFloat32Array = sample_field(data, data.vault_field)

	_build_surface("Floor", floor_heights, dims, floor_material, false, true)
	# La voûte est retournée (faces vers le bas) et trouée visuellement.
	_build_surface("Vault", vault_heights, dims, rock_material, true, false)
	_build_walls(floor_heights, vault_heights, dims)


# ---------------------------------------------------------------------------
# Échantillonnage du champ de hauteurs — statique et pur (testable)
# ---------------------------------------------------------------------------

## Adoucissement MINIMAL pour qu'une transition d'altitude reste praticable.
##
## Le fondu des primitives utilise un `smoothstep`, dont la pente maximale vaut
## **1,5 fois** la pente moyenne (dérivée de 3x²-2x³, maximale au milieu du
## fondu). Dimensionner à l'œil sur `delta / falloff` sous-estime donc la pente
## réelle de 50 % : c'est le piège que le test de pente a levé. Utiliser cette
## fonction pour dimensionner les `falloff`, `rim_width` et largeurs de rampe.
static func min_falloff_for(delta_altitude: float, max_slope_degrees: float) -> float:
	var slope: float = tan(deg_to_rad(clampf(max_slope_degrees, 1.0, 89.0)))
	return 1.5 * absf(delta_altitude) / maxf(slope, 0.001)


## Nombre d'échantillons en X et en Z, bornes comprises.
static func grid_dimensions(terrain: CavernTerrainData) -> Vector2i:
	var span: Vector2 = terrain.bounds_max - terrain.bounds_min
	return Vector2i(
		int(round(span.x / terrain.cell_size)) + 1,
		int(round(span.y / terrain.cell_size)) + 1
	)


## Position monde (X, Z) de l'échantillon (ix, iz).
static func sample_position(terrain: CavernTerrainData, ix: int, iz: int) -> Vector2:
	return terrain.bounds_min + Vector2(float(ix), float(iz)) * terrain.cell_size


## Évalue un champ complet. Retourne les altitudes en ligne, indexées
## `iz * width + ix`.
static func sample_field(terrain: CavernTerrainData, spec: CavernHeightfieldSpec) -> PackedFloat32Array:
	var dims: Vector2i = grid_dimensions(terrain)
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(dims.x * dims.y)

	var noise: FastNoiseLite = null
	if spec.noise_amplitude > 0.0:
		noise = FastNoiseLite.new()
		noise.seed = spec.noise_seed
		noise.frequency = 1.0 / maxf(spec.noise_scale, 0.001)

	for iz in dims.y:
		for ix in dims.x:
			var p: Vector2 = sample_position(terrain, ix, iz)
			heights[iz * dims.x + ix] = sample_point(spec, p, noise)
	return heights


## Évalue l'altitude en un point. Les primitives s'appliquent dans l'ordre
## plateaux → rampes → cuvettes ; chacune mélange sa contribution selon son
## adoucissement, de sorte qu'aucune ne produit de marche franche.
static func sample_point(spec: CavernHeightfieldSpec, p: Vector2, noise: FastNoiseLite) -> float:
	var height: float = spec.base_altitude

	for plateau in spec.plateaus:
		var w: float = _plateau_weight(plateau, p)
		if w > 0.0:
			height = lerpf(height, plateau.altitude, w)

	for ramp in spec.ramps:
		var result: Array = _ramp_weight_and_altitude(ramp, p)
		var w: float = result[0]
		if w > 0.0:
			height = lerpf(height, result[1], w)

	# Le bruit est appliqué AVANT les cuvettes : les margelles doivent rester
	# des bordures nettes et fiables, sinon la garantie anti-chute devient
	# statistique au lieu d'être structurelle.
	if noise != null:
		height += noise.get_noise_2d(p.x, p.y) * spec.noise_amplitude

	for basin in spec.basins:
		height += _basin_offset(basin, p)

	return height


## Poids d'appartenance à un plateau : 1 à l'intérieur, décroissant sur le
## `falloff`, 0 au-delà.
static func _plateau_weight(plateau: CavernPlateau, p: Vector2) -> float:
	var d: Vector2 = (p - plateau.center).abs()
	var outside: float
	if plateau.is_ellipse:
		var rx: float = maxf(plateau.half_extent.x, 0.001)
		var rz: float = maxf(plateau.half_extent.y, 0.001)
		# Distance normalisée puis remise à l'échelle du plus petit rayon, pour
		# que le falloff soit exprimé en mètres et pas en unités d'ellipse.
		var norm: float = Vector2(d.x / rx, d.y / rz).length()
		outside = (norm - 1.0) * minf(rx, rz)
	else:
		outside = Vector2(
			maxf(d.x - plateau.half_extent.x, 0.0),
			maxf(d.y - plateau.half_extent.y, 0.0)
		).length()

	if outside <= 0.0:
		return 1.0
	if plateau.falloff <= 0.0:
		return 0.0
	return smoothstep(1.0, 0.0, clampf(outside / plateau.falloff, 0.0, 1.0))


## Poids et altitude interpolée d'une rampe. Retourne `[poids, altitude]`.
static func _ramp_weight_and_altitude(ramp: CavernRamp, p: Vector2) -> Array:
	var axis: Vector2 = ramp.to_point - ramp.from_point
	var length_sq: float = axis.length_squared()
	if length_sq < 0.0001:
		return [0.0, ramp.from_altitude]

	var rel: Vector2 = p - ramp.from_point
	var t: float = clampf(rel.dot(axis) / length_sq, 0.0, 1.0)
	var altitude: float = lerpf(ramp.from_altitude, ramp.to_altitude, t)

	var closest: Vector2 = ramp.from_point + axis * t
	var lateral: float = p.distance_to(closest)
	var half_width: float = ramp.width * 0.5

	if lateral <= half_width:
		return [1.0, altitude]
	if ramp.falloff <= 0.0:
		return [0.0, altitude]
	var w: float = smoothstep(1.0, 0.0, clampf((lateral - half_width) / ramp.falloff, 0.0, 1.0))
	return [w, altitude]


## Décalage d'altitude dû à une cuvette : négatif au fond, POSITIF sur la
## margelle. C'est ce bourrelet qui interdit la chute.
static func _basin_offset(basin: CavernBasin, p: Vector2) -> float:
	var rx: float = maxf(basin.radii.x, 0.001)
	var rz: float = maxf(basin.radii.y, 0.001)
	var norm: float = Vector2((p.x - basin.center.x) / rx, (p.y - basin.center.y) / rz).length()

	if norm <= 1.0:
		# Intérieur : du fond (-depth) jusqu'à la CRÊTE de la margelle (+rim_height),
		# atteinte exactement au bord. La crête est le bord : sans ça, l'offset
		# saute de 0 à rim_height d'un échantillon à l'autre et crée une falaise
		# invisible dans la donnée (bug levé par le test de pente).
		return lerpf(-basin.depth, basin.rim_height, smoothstep(0.0, 1.0, norm))

	if basin.rim_width <= 0.0 or basin.rim_height <= 0.0:
		return 0.0

	# Extérieur : le bourrelet culmine juste au bord et retombe sur `rim_width`.
	var outside_m: float = (norm - 1.0) * minf(rx, rz)
	if outside_m >= basin.rim_width:
		return 0.0
	return basin.rim_height * smoothstep(1.0, 0.0, clampf(outside_m / basin.rim_width, 0.0, 1.0))


## Vrai si le point tombe dans un puits de ciel (utilisé pour trouer la voûte).
static func is_in_sky_well(terrain: CavernTerrainData, p: Vector2) -> bool:
	for well in terrain.sky_wells:
		if p.distance_to(well.center) <= well.diameter * 0.5:
			return true
	return false


# ---------------------------------------------------------------------------
# Construction de la géométrie
# ---------------------------------------------------------------------------

func _build_surface(
	surface_name: String,
	heights: PackedFloat32Array,
	dims: Vector2i,
	material: Material,
	flip_faces: bool,
	solid_mesh: bool
) -> void:
	var root: Node3D = Node3D.new()
	root.name = surface_name
	add_child(root)
	root.owner = owner

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	# `solid_mesh` distingue le sol (maillage plein) de la voûte (maillage troué
	# aux puits de ciel). La collision, elle, est toujours pleine.
	mesh_instance.mesh = _build_heightfield_mesh(heights, dims, flip_faces, not solid_mesh)
	if material != null:
		mesh_instance.material_override = material
	root.add_child(mesh_instance)
	mesh_instance.owner = owner

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	body.owner = owner

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = _build_heightmap_shape(heights, dims)
	# HeightMapShape3D échantillonne à 1 unité et se centre sur son origine :
	# on le remet à l'échelle et on le recentre sur l'emprise réelle.
	collision.scale = Vector3(data.cell_size, 1.0, data.cell_size)
	var center: Vector2 = (data.bounds_min + data.bounds_max) * 0.5
	collision.position = Vector3(center.x, 0.0, center.y)
	body.add_child(collision)
	collision.owner = owner


func _build_heightfield_mesh(
	heights: PackedFloat32Array,
	dims: Vector2i,
	flip_faces: bool,
	punch_sky_wells: bool
) -> ArrayMesh:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for iz in dims.y - 1:
		for ix in dims.x - 1:
			var p00: Vector2 = sample_position(data, ix, iz)
			var p10: Vector2 = sample_position(data, ix + 1, iz)
			var p01: Vector2 = sample_position(data, ix, iz + 1)
			var p11: Vector2 = sample_position(data, ix + 1, iz + 1)

			# Un quad n'est percé que si ses QUATRE coins sont dans le puits :
			# le bord du trou reste ainsi net et fermé.
			if punch_sky_wells and (
				is_in_sky_well(data, p00) and is_in_sky_well(data, p10)
				and is_in_sky_well(data, p01) and is_in_sky_well(data, p11)
			):
				continue

			var v00 := Vector3(p00.x, heights[iz * dims.x + ix], p00.y)
			var v10 := Vector3(p10.x, heights[iz * dims.x + ix + 1], p10.y)
			var v01 := Vector3(p01.x, heights[(iz + 1) * dims.x + ix], p01.y)
			var v11 := Vector3(p11.x, heights[(iz + 1) * dims.x + ix + 1], p11.y)

			if flip_faces:
				_add_triangle(st, v00, v10, v11)
				_add_triangle(st, v00, v11, v01)
			else:
				_add_triangle(st, v00, v11, v10)
				_add_triangle(st, v00, v01, v11)

	st.generate_normals()
	st.generate_tangents()
	return st.commit()


func _add_triangle(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	# UV planaires : suffisant au blockout ; E3 passera en tri-planaire, seul
	# procédé qui tienne sur du vallonné sans étirement visible sur les pentes.
	st.set_uv(Vector2(a.x, a.z) * 0.1)
	st.add_vertex(a)
	st.set_uv(Vector2(b.x, b.z) * 0.1)
	st.add_vertex(b)
	st.set_uv(Vector2(c.x, c.z) * 0.1)
	st.add_vertex(c)


func _build_heightmap_shape(heights: PackedFloat32Array, dims: Vector2i) -> HeightMapShape3D:
	var shape: HeightMapShape3D = HeightMapShape3D.new()
	shape.map_width = dims.x
	shape.map_depth = dims.y
	shape.map_data = heights
	return shape


## Ceinture de parois entre le contour du sol et celui de la voûte. Générée
## depuis les mêmes champs : le périmètre est scellé par construction, il n'y a
## pas de jonction à surveiller.
func _build_walls(
	floor_heights: PackedFloat32Array,
	vault_heights: PackedFloat32Array,
	dims: Vector2i
) -> void:
	var st: SurfaceTool = SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	for edge_index in 4:
		var count: int = dims.x if edge_index < 2 else dims.y
		for i in count - 1:
			var a: Vector2i = _edge_sample(edge_index, i, dims)
			var b: Vector2i = _edge_sample(edge_index, i + 1, dims)
			var pa: Vector2 = sample_position(data, a.x, a.y)
			var pb: Vector2 = sample_position(data, b.x, b.y)
			var fa: float = floor_heights[a.y * dims.x + a.x]
			var fb: float = floor_heights[b.y * dims.x + b.x]
			var va: float = vault_heights[a.y * dims.x + a.x]
			var vb: float = vault_heights[b.y * dims.x + b.x]

			var bottom_a := Vector3(pa.x, fa, pa.y)
			var bottom_b := Vector3(pb.x, fb, pb.y)
			var top_a := Vector3(pa.x, va, pa.y)
			var top_b := Vector3(pb.x, vb, pb.y)

			# Faces tournées vers l'intérieur du volume.
			if edge_index == 0 or edge_index == 3:
				_add_triangle(st, bottom_a, top_a, top_b)
				_add_triangle(st, bottom_a, top_b, bottom_b)
			else:
				_add_triangle(st, bottom_a, top_b, top_a)
				_add_triangle(st, bottom_a, bottom_b, top_b)

	st.generate_normals()
	st.generate_tangents()
	var mesh: ArrayMesh = st.commit()

	var root: Node3D = Node3D.new()
	root.name = "Walls"
	add_child(root)
	root.owner = owner

	var mesh_instance: MeshInstance3D = MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	if rock_material != null:
		mesh_instance.material_override = rock_material
	root.add_child(mesh_instance)
	mesh_instance.owner = owner

	var body: StaticBody3D = StaticBody3D.new()
	body.name = "Body"
	root.add_child(body)
	body.owner = owner

	var collision: CollisionShape3D = CollisionShape3D.new()
	collision.name = "Shape"
	collision.shape = mesh.create_trimesh_shape()
	body.add_child(collision)
	collision.owner = owner


## Coordonnées de grille du i-ème échantillon du bord `edge_index`
## (0 = nord, 1 = sud, 2 = ouest, 3 = est).
static func _edge_sample(edge_index: int, i: int, dims: Vector2i) -> Vector2i:
	match edge_index:
		0:
			return Vector2i(i, 0)
		1:
			return Vector2i(i, dims.y - 1)
		2:
			return Vector2i(0, i)
		_:
			return Vector2i(dims.x - 1, i)

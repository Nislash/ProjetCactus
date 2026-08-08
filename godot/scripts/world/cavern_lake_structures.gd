## Les structures du lac : la Chaussée, l'Îlot et les deux Piliers.
##
## POURQUOI DES PROPS ET PAS DU TERRAIN
## La spec créative demande une langue de pierre qui s'avance dans le lac et un
## îlot. C'est **infaisable en champ de hauteurs** : les cuvettes s'AJOUTENT aux
## plateaux, donc toute avancée posée dans l'emprise du lit du lac se retrouve
## creusée avec lui et coule sous la glace.
##
## Le contournement sert d'ailleurs mieux la fiction : la Chaussée est l'ÉBOULIS
## de la voûte effondrée. On ne marche pas sur une presqu'île, on marche sur les
## débris du plafond — ce sont les mêmes blocs qui ont ouvert la Brèche.
##
## Les Piliers sont les colonnes survivantes de cette voûte : ils touchent
## VRAIMENT le plafond, ce qui donne au lac son échelle verticale.
##
## Cf `docs/design/level01_topography.md` §5.

class_name CavernLakeStructures
extends Node3D

@export_file("*.tres") var terrain_path: String = "res://data/levels/level01_cavern_terrain.tres"
@export_file("*.tres") var rock_material_path: String = "res://data/levels/cavern_wall_material.tres"
@export_file("*.tres") var crystal_material_path: String = "res://assets/level01/materials/crystal_spire_b.tres"

## Rayon d'une plateforme de chaussée, en mètres.
@export var stepping_radius: float = 2.6

## Altitude du dessus des plateformes. Au-dessus de la nappe (−0,55) : on
## marche SUR la glace, pas dedans.
@export var stepping_top: float = 0.4

## Rayon du fût des Piliers.
@export var pillar_radius: float = 2.0

## Nombre de colonnes tentées autour du lac. Certaines sont écartées parce
## qu'elles tomberaient sur la Chaussée, l'Îlot ou dans la roche.
@export var colonnade_count: int = 10

## Position de la couronne, en fraction des rayons du lac. Au-delà de 1, les
## fûts sont sur la rive plutôt que dans la glace.
@export var colonnade_radius_factor: float = 1.06

var _rock: Material
var _crystal: Material


func _ready() -> void:
	var terrain: CavernTerrainData = load(terrain_path) as CavernTerrainData
	if terrain == null:
		push_error("CavernLakeStructures : terrain introuvable (%s)." % terrain_path)
		return
	_rock = load(rock_material_path) as Material
	_crystal = load(crystal_material_path) as Material

	# Le terrain se construit dans son propre `_ready`.
	await get_tree().process_frame

	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)
	var bed: float = CavernTerrainBuilder.sample_point(
		terrain.floor_field, Vector2(-4.0, 38.0), noise)

	# LA CHAUSSÉE — quatre blocs depuis la rive sud jusqu'au cœur du lac.
	# L'espacement (≈6 m entre centres, soit ~0,8 m de vide entre les bords)
	# se franchit en marchant : c'est un chemin, pas un parcours de saut.
	var causeway: Array[Vector2] = [
		Vector2(-9.0, 55.0), Vector2(-8.0, 49.0), Vector2(-6.0, 43.0), Vector2(-4.0, 37.0),
	]
	for i in causeway.size():
		_build_slab("Chaussee_%d" % i, causeway[i], bed, stepping_radius, stepping_top, 7)

	# L'ÎLOT — le socle du Pilier Nord, et le seul accès à K1.
	_build_slab("Ilot", Vector2(4.0, 28.0), bed, 3.4, 0.3, 9)

	# LE PILIER DE L'ÎLOT — celui qui garde K1.
	_build_pillar("PilierIlot", Vector2(4.0, 28.0), bed, terrain)

	# LA COLONNADE — une couronne de fûts autour du lac, qui SOUTIENNENT la
	# voûte. C'est ce qui explique visuellement pourquoi le plafond tient
	# encore ailleurs alors qu'il s'est effondré au centre : là où les colonnes
	# manquaient, il est tombé. La Brèche devient une conséquence, pas un décor.

	_build_colonnade(bed, terrain)


## Bloc d'éboulis à sommet plat : un cylindre à faible nombre de segments, donc
## facetté comme de la roche cassée, et praticable parce que son dessus est plan.
func _build_slab(node_name: String, at: Vector2, bed: float, radius: float,
		top: float, segments: int) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.position = Vector3(at.x, 0.0, at.y)
	add_child(body)
	body.owner = owner

	# Le bloc part du LIT du lac, pas de la surface : on doit le voir plonger
	# dans la glace, sinon il flotte.
	var height: float = maxf(top - bed, 0.5)
	var centre: float = bed + height * 0.5

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius * 1.25
	mesh.height = height
	mesh.radial_segments = segments
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, centre, 0.0)
	if _rock != null:
		mesh_instance.material_override = _rock
	body.add_child(mesh_instance)
	mesh_instance.owner = owner

	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	var shape := CylinderShape3D.new()
	shape.radius = radius
	shape.height = height
	collision.shape = shape
	collision.position = Vector3(0.0, centre, 0.0)
	body.add_child(collision)
	collision.owner = owner


## Dispose la colonnade autour du lac.
##
## Les fûts sont posés sur la RIVE (juste au-delà du bord de la nappe) et non
## dans l'eau : une colonne plantée au milieu de la glace bloquerait la
## traversée et masquerait la Brèche, qui est le repère principal du niveau.
##
## Deux emplacements sont écartés : la Chaussée (on doit pouvoir la parcourir)
## et l'Îlot (il a déjà son pilier).
func _build_colonnade(bed: float, terrain: CavernTerrainData) -> void:
	var lake: CavernLake = terrain.lake
	if lake == null:
		return

	# Les positions à laisser libres, avec leur rayon d'exclusion.
	var forbidden: Array = [
		[Vector2(-9.0, 55.0), 9.0], [Vector2(-8.0, 49.0), 9.0],
		[Vector2(-6.0, 43.0), 9.0], [Vector2(-4.0, 37.0), 9.0],
		[Vector2(4.0, 28.0), 10.0],
		[Vector2(-10.0, 58.0), 8.0],
	]

	var placed: int = 0
	for i in colonnade_count:
		# Décalage d'un demi-pas : sans lui, la première colonne tomberait pile
		# sur l'axe et la couronne se lirait comme une grille.
		var angle: float = TAU * (float(i) + 0.5) / float(colonnade_count)
		var at := Vector2(
			lake.center.x + cos(angle) * lake.radii.x * colonnade_radius_factor,
			lake.center.y + sin(angle) * lake.radii.y * colonnade_radius_factor)

		var blocked: bool = false
		for zone in forbidden:
			if at.distance_to(zone[0]) < zone[1]:
				blocked = true
				break
		if blocked:
			continue

		# Une colonne hors du volume creusé serait dans la roche pleine.
		if CavernTerrainBuilder.chamber_mask(terrain, at) < 0.4:
			continue

		_build_pillar("Colonne_%d" % i, at, bed, terrain)
		placed += 1

	if placed < 3:
		push_warning("CavernLakeStructures : seulement %d colonnes posées." % placed)


## Colonne survivante de la voûte : elle monte du lit jusqu'au plafond réel,
## calculé sur place. Un pilier qui s'arrête sous la voûte ne raconterait rien.
func _build_pillar(node_name: String, at: Vector2, bed: float, terrain: CavernTerrainData) -> void:
	var noise: FastNoiseLite = CavernTerrainBuilder.make_noise(terrain.floor_field)
	var ground: float = CavernTerrainBuilder.sample_point(terrain.floor_field, at, noise)
	var clearance: float = clampf(
		CavernTerrainBuilder.chamber_headroom(terrain, at),
		terrain.min_headroom, terrain.max_headroom)
	var ceiling: float = ground + clearance
	var height: float = maxf(ceiling - bed, 6.0)

	var body := StaticBody3D.new()
	body.name = node_name
	body.position = Vector3(at.x, 0.0, at.y)
	add_child(body)
	body.owner = owner

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	var mesh := CylinderMesh.new()
	# Fût légèrement conique, plus large en bas : une colonne parfaitement
	# cylindrique se lit comme un objet fabriqué, pas comme de la roche.
	mesh.top_radius = pillar_radius * 0.85
	mesh.bottom_radius = pillar_radius * 1.3
	mesh.height = height
	mesh.radial_segments = 9
	mesh_instance.mesh = mesh
	mesh_instance.position = Vector3(0.0, bed + height * 0.5, 0.0)
	if _rock != null:
		mesh_instance.material_override = _rock
	body.add_child(mesh_instance)
	mesh_instance.owner = owner

	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	var shape := CylinderShape3D.new()
	shape.radius = pillar_radius
	shape.height = height
	collision.shape = shape
	collision.position = Vector3(0.0, bed + height * 0.5, 0.0)
	body.add_child(collision)
	collision.owner = owner

	# Veines de cristal sur le TIERS SUPÉRIEUR : c'est ce qui rend les Piliers
	# lisibles de loin (repère T2 de la grammaire lumineuse), au-dessus du
	# relief qui masque tout le reste.
	var vein := MeshInstance3D.new()
	vein.name = "Veines"
	var vein_mesh := CylinderMesh.new()
	vein_mesh.top_radius = pillar_radius * 0.92
	vein_mesh.bottom_radius = pillar_radius * 0.98
	vein_mesh.height = height * 0.32
	vein_mesh.radial_segments = 9
	vein.mesh = vein_mesh
	vein.position = Vector3(0.0, ceiling - height * 0.20, 0.0)
	if _crystal != null:
		vein.material_override = _crystal
	body.add_child(vein)
	vein.owner = owner

	var glow := OmniLight3D.new()
	glow.name = "Glow"
	glow.position = Vector3(0.0, ceiling - height * 0.20, 0.0)
	glow.light_color = Color(0.42, 0.86, 1.0)
	glow.light_energy = 4.2
	glow.omni_range = 34.0
	glow.light_volumetric_fog_energy = 2.4
	glow.shadow_enabled = false
	body.add_child(glow)
	glow.owner = owner

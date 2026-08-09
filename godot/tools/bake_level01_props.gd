extends SceneTree

## Transforme les `.glb` bruts de Meshy en assets prêts pour le jeu (E4 #22, #36).
##
## LE PROBLÈME QU'IL RÉSOUT
## Un `.glb` Meshy texturé pèse 22 à 39 Mo : il embarque des textures en 4096²,
## y compris pour de la donnée basse fréquence (roughness, metallic, émission).
## Godot les ré-extrait ensuite en PNG à côté — la même matière est donc stockée
## DEUX FOIS. Résultat mesuré : 185 Mo pour trois cailloux décoratifs. À ce
## rythme, vingt props dépassent le gigaoctet de LFS.
##
## CE QU'IL PRODUIT
##   assets/level01/textures/<nom>_<slot>.png   textures redimensionnées
##   assets/level01/meshes/<nom>.res            maillage seul (géométrie)
##   assets/level01/materials/<nom>.tres        matériau pointant les textures
##   scenes/props/<nom>.tscn                    sous-scène réutilisable
##
## Les `.glb` restent dans `meshes/src/` mais ne sont PAS versionnés : ce sont
## des artefacts retéléchargeables, tracés par `meshy_task_id` dans
## `assets_manifest.yaml`. Le dépôt ne porte que le produit fini.
##
## DEUX PASSES, parce que Godot doit importer les PNG avant qu'on puisse les
## référencer depuis un matériau :
##   godot --headless --path godot --script tools/bake_level01_props.gd -- --pass=textures
##   godot --headless --path godot --import
##   godot --headless --path godot --script tools/bake_level01_props.gd -- --pass=assets

## Le niveau ciblé. `--level=02` bascule tous les dossiers d'un coup.
##
## Le nom du fichier dit encore « level01 » et c'est assumé : le renommer
## casserait les trois documents qui l'appellent par ce nom, pour un gain nul.
## C'est le CONTENU qui a cessé d'être spécifique à un niveau.
var _level: String = "level01"

var _tex_dir: String:
	get: return "res://assets/%s/textures/" % _level
var _mesh_dir: String:
	get: return "res://assets/%s/meshes/" % _level
var _mat_dir: String:
	get: return "res://assets/%s/materials/" % _level

const SCENE_DIR := "res://scenes/props/"

## Budget de résolution par rôle de texture.
##
## L'albédo et la normale portent le détail que l'œil lit ; la rugosité, le
## métallique et l'émission sont des données BASSE FRÉQUENCE — les stocker en
## 4096² ne rend rien de visible et coûte 64 fois la surface d'un 512².
const BUDGET_STANDARD := {
	"albedo": 1024, "normal": 1024, "roughness": 512, "metallic": 512, "emission": 512,
}

## Les hero assets sont vus de loin ET de près : ils gardent le double sur les
## canaux que l'œil lit.
const BUDGET_HERO := {
	"albedo": 2048, "normal": 2048, "roughness": 512, "metallic": 512, "emission": 1024,
}

## Table de production.
##
## `hero`     : budget de texture élevé (vu de loin ET de près).
## `emissive` : l'asset est une SOURCE de lumière. L'art bible est explicite —
##              le cristal éclaire, la roche non. Meshy renvoie une carte
##              d'émission pour tout ; l'activer sur un caillou coûterait une
##              lecture de texture pour du noir, et trahirait la grammaire
##              lumineuse du niveau (cf topographie §5).
## `collision`: forme de collision de la sous-scène.
const ASSETS := [
	{"name": "crystal_wall_a", "src": "crystal_wall_a.glb", "hero": false, "emissive": true, "collision": "convex"},
	{"name": "crystal_spire_b", "src": "crystal_spire_b.glb", "hero": false, "emissive": true, "collision": "convex"},
	{"name": "crystal_fan_c", "src": "crystal_fan_c.glb", "hero": false, "emissive": true, "collision": "convex"},
	{"name": "stalactite_cluster", "src": "src/stalactite_cluster.glb", "hero": false, "emissive": false, "collision": "convex"},
	{"name": "rock_rubble", "src": "src/rock_rubble.glb", "hero": false, "emissive": false, "collision": "convex"},
	{"name": "crystal_monolith_landmark", "src": "src/crystal_monolith_landmark.glb", "hero": true, "emissive": true, "collision": "trimesh"},
]

## Les assets du niveau 2. Le levier est vu de PRÈS — on s'en approche pour
## l'actionner — donc budget hero sur les canaux que l'œil lit.
const ASSETS_LEVEL02 := [
	{"name": "forge_lever", "src": "src/forge_lever.glb", "hero": true, "emissive": true, "collision": "convex"},
]

const SLOTS := {
	"albedo": BaseMaterial3D.TEXTURE_ALBEDO,
	"normal": BaseMaterial3D.TEXTURE_NORMAL,
	"roughness": BaseMaterial3D.TEXTURE_ROUGHNESS,
	"metallic": BaseMaterial3D.TEXTURE_METALLIC,
	"emission": BaseMaterial3D.TEXTURE_EMISSION,
}


func _init() -> void:
	var mode: String = "textures"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--pass="):
			mode = arg.trim_prefix("--pass=")
		elif arg.begins_with("--level="):
			_level = "level%s" % arg.trim_prefix("--level=")

	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_tex_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_mat_dir))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(SCENE_DIR))

	var table: Array = ASSETS_LEVEL02 if _level == "level02" else ASSETS
	var failures: int = 0
	for entry in table:
		failures += (0 if _bake_one(entry, mode) else 1)

	if failures > 0:
		push_error("[bake] %d asset(s) en échec" % failures)
		quit(1)
		return
	print("[bake] %s : passe « %s » terminée sur %d assets." % [_level, mode, table.size()])
	quit(0)


func _bake_one(entry: Dictionary, mode: String) -> bool:
	var source_path: String = _mesh_dir + entry.src
	var packed: PackedScene = load(source_path) as PackedScene
	if packed == null:
		push_error("[bake] source introuvable : %s" % source_path)
		return false

	var root: Node = packed.instantiate()
	var mesh_instance: MeshInstance3D = _find_mesh(root)
	if mesh_instance == null or mesh_instance.mesh == null:
		push_error("[bake] aucun MeshInstance3D dans %s" % source_path)
		return false

	if mode == "textures":
		return _bake_textures(entry, mesh_instance.mesh)
	return _bake_asset(entry, mesh_instance.mesh)


# ---------------------------------------------------------------------------
# Passe 1 — textures
# ---------------------------------------------------------------------------

func _bake_textures(entry: Dictionary, mesh: Mesh) -> bool:
	var budget: Dictionary = BUDGET_HERO if entry.hero else BUDGET_STANDARD
	var written: int = 0

	for surface in mesh.get_surface_count():
		var material: BaseMaterial3D = mesh.surface_get_material(surface) as BaseMaterial3D
		if material == null:
			continue
		for slot_name in SLOTS:
			if slot_name == "emission" and not entry.emissive:
				continue
			var texture: Texture2D = material.get_texture(SLOTS[slot_name])
			if texture == null:
				continue
			var image: Image = texture.get_image()
			if image == null:
				continue
			image = image.duplicate() as Image
			if image.is_compressed():
				image.decompress()

			var target: int = budget[slot_name]
			var before := image.get_size()
			# On ne remonte JAMAIS une texture : si la source est déjà sous le
			# budget, on la garde telle quelle plutôt que d'inventer des pixels.
			if image.get_width() > target or image.get_height() > target:
				var ratio: float = float(target) / float(maxi(image.get_width(), image.get_height()))
				image.resize(
					maxi(int(round(image.get_width() * ratio)), 1),
					maxi(int(round(image.get_height() * ratio)), 1),
					Image.INTERPOLATE_LANCZOS)

			var out_path: String = "%s%s_%s.png" % [_tex_dir, entry.name, slot_name]
			var error: int = image.save_png(ProjectSettings.globalize_path(out_path))
			if error != OK:
				push_error("[bake] échec d'écriture %s (code %d)" % [out_path, error])
				return false
			print("[bake] %-26s %-9s %dx%d -> %dx%d" % [
				entry.name, slot_name, before.x, before.y, image.get_width(), image.get_height()])
			written += 1
		# Un seul jeu de textures par asset : les meshes Meshy n'ont qu'une
		# surface, et dupliquer par surface écraserait les fichiers.
		break

	if written == 0:
		push_warning("[bake] %s : aucune texture trouvée" % entry.name)
	return true


# ---------------------------------------------------------------------------
# Passe 2 — maillage, matériau, sous-scène
# ---------------------------------------------------------------------------

func _bake_asset(entry: Dictionary, source_mesh: Mesh) -> bool:
	# Le maillage est réécrit sans ses matériaux : le matériau vit désormais
	# dans son propre `.tres`, réassignable sans retoucher la géométrie.
	var mesh := ArrayMesh.new()
	for surface in source_mesh.get_surface_count():
		mesh.add_surface_from_arrays(
			Mesh.PRIMITIVE_TRIANGLES, source_mesh.surface_get_arrays(surface))
	var mesh_path: String = "%s%s.res" % [_mesh_dir, entry.name]
	if ResourceSaver.save(mesh, mesh_path) != OK:
		push_error("[bake] échec d'écriture %s" % mesh_path)
		return false

	var material := StandardMaterial3D.new()
	for slot_name in SLOTS:
		# Pas de carte d'émission sur un asset non émissif : ni fichier chargé,
		# ni lecture de texture au rendu.
		if slot_name == "emission" and not entry.emissive:
			continue
		var texture_path: String = "%s%s_%s.png" % [_tex_dir, entry.name, slot_name]
		if not ResourceLoader.exists(texture_path):
			continue
		var texture: Texture2D = load(texture_path) as Texture2D
		if texture == null:
			continue
		material.set_texture(SLOTS[slot_name], texture)
		match slot_name:
			"normal":
				material.normal_enabled = true
			"roughness":
				material.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GREEN
			"metallic":
				material.metallic_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_BLUE
			"emission":
				material.emission_enabled = true
				# L'émission porte la grammaire lumineuse du niveau : ce sont les
				# cristaux qui guident dans le noir (cf topographie §5).
				material.emission_energy_multiplier = 1.6

	var material_path: String = "%s%s.tres" % [_mat_dir, entry.name]
	if ResourceSaver.save(material, material_path) != OK:
		push_error("[bake] échec d'écriture %s" % material_path)
		return false

	return _build_prop_scene(entry, mesh, material)


## Sous-scène réutilisable : un StaticBody3D porteur de la collision, son
## MeshInstance3D, et rien d'autre. C'est l'unité que le niveau instancie
## (composition plutôt qu'héritage, cf CLAUDE.md).
func _build_prop_scene(entry: Dictionary, mesh: ArrayMesh, material: Material) -> bool:
	var body := StaticBody3D.new()
	body.name = entry.name.to_pascal_case()

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "Mesh"
	mesh_instance.mesh = mesh
	mesh_instance.material_override = material
	body.add_child(mesh_instance)
	mesh_instance.owner = body

	var collision := CollisionShape3D.new()
	collision.name = "Shape"
	# Convexe pour les props (bon marché, suffisant sur des formes compactes) ;
	# trimesh pour les hero assets, dont la silhouette porte le gameplay
	# (on doit pouvoir se plaquer contre un monolithe sans flotter).
	collision.shape = mesh.create_trimesh_shape() if entry.collision == "trimesh" \
		else mesh.create_convex_shape()
	body.add_child(collision)
	collision.owner = body

	var packed := PackedScene.new()
	if packed.pack(body) != OK:
		push_error("[bake] échec du packing de %s" % entry.name)
		return false
	var scene_path: String = "%s%s.tscn" % [SCENE_DIR, entry.name]
	if ResourceSaver.save(packed, scene_path) != OK:
		push_error("[bake] échec d'écriture %s" % scene_path)
		return false

	print("[bake] %-26s mesh %d tris, scène %s" % [
		entry.name, _count_triangles(mesh), scene_path.get_file()])
	return true


# ---------------------------------------------------------------------------
# Outils
# ---------------------------------------------------------------------------

func _find_mesh(root: Node) -> MeshInstance3D:
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		for child in node.get_children():
			stack.append(child)
		if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
			return node as MeshInstance3D
	return null


func _count_triangles(mesh: Mesh) -> int:
	var total: int = 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		total += (indices.size() / 3) if indices.size() > 0 \
			else (arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array).size() / 3
	return total

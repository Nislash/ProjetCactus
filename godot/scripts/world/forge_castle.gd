class_name ForgeCastle
extends Node3D

## La forteresse au fond du cirque — le point de fuite du niveau 2.
##
## ## Ce qu'elle doit faire, dans l'ordre
##
## 1. **Se voir depuis la crête.** C'est la première chose qu'on aperçoit en
##    arrivant, et c'est elle qui dit où l'on va. Sa silhouette compte plus
##    que ses détails : on la verra surtout en contre-jour sur la lune.
## 2. **Fermer le fond du cirque.** Elle est bâtie sur le rebord du bassin de
##    lave, dos à la falaise — on ne peut pas la contourner.
## 3. **Porter une porte qui résiste.** Scellée par une coulée figée, elle ne
##    cède qu'au rayon de lune (cf [MoonMirror]).
##
## ## Pourquoi elle est construite en code
##
## Une forteresse modélisée serait plus belle, mais elle serait aussi figée :
## son échelle et sa position dépendent du terrain, qui a déjà changé trois
## fois. Bâtie en primitives, elle suit. Quand le niveau sera stable, la
## silhouette pourra être remplacée par un maillage sans rien changer au
## gameplay — la porte et le verrou vivent dans des nœuds séparés.
##
## ## La silhouette
##
## Massive et anguleuse, plus large en bas : un donjon central flanqué de
## quatre tours, crénelé, avec un pont étroit qui l'aborde de face. Elle
## n'imite pas le basalte du cirque — elle est TAILLÉE, régulière, et c'est ce
## contraste avec la roche cassée qui la fait lire comme un ouvrage.

signal gate_opened()

## Où la forteresse est posée, en (X, Z). Sur le rebord nord du bassin, dos à
## la falaise.
@export var footprint_center: Vector2 = Vector2(0.0, -34.0)

@export var keep_height: float = 26.0
@export var keep_width: float = 22.0
@export var tower_height: float = 34.0
@export var tower_radius: float = 4.2

@export_file("*.tres") var terrain_data_path: String = "res://data/levels/level02_forge_terrain.tres"

const STONE := Color(0.055, 0.045, 0.050)
const STONE_DARK := Color(0.030, 0.024, 0.028)
const SEAL := Color(1.000, 0.478, 0.184)

var _terrain: CavernTerrainData
var _noise: FastNoiseLite
var _gate: Node3D
var _gate_material: StandardMaterial3D
var _open: bool = false


func _ready() -> void:
	_terrain = load(terrain_data_path) as CavernTerrainData
	if _terrain == null:
		push_warning("ForgeCastle : terrain introuvable — pas de château.")
		return
	_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)
	await get_tree().process_frame
	_build()


func _ground(at: Vector2) -> float:
	return CavernTerrainBuilder.sample_point(_terrain.floor_field, at, _noise)


func _build() -> void:
	var base: float = _ground(footprint_center)
	global_position = Vector3(footprint_center.x, base, footprint_center.y)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.88
	stone.metallic = 0.0

	var stone_dark := StandardMaterial3D.new()
	stone_dark.albedo_color = STONE_DARK
	stone_dark.roughness = 0.92

	_build_terrace(stone_dark)
	_build_keep(stone)
	_build_towers(stone)
	_build_gate()


## LA TERRASSE. Une plateforme taillée qui rattrape le relief : sans elle, un
## donjon posé sur du terrain bruité flotterait d'un côté et s'enfoncerait de
## l'autre.
func _build_terrace(material: Material) -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Terrasse"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(keep_width * 2.1, 3.0, keep_width * 1.7)
	slab.mesh = mesh
	slab.material_override = material
	slab.position = Vector3(0.0, 1.0, 0.0)
	add_child(slab)
	_add_collider(slab, mesh.size, slab.position)


## LE DONJON. Un tronc de pyramide : plus large en bas, comme une forteresse
## qui pousse hors de la roche. Un parallélépipède droit se lirait comme une
## boîte.
func _build_keep(material: Material) -> void:
	var keep := MeshInstance3D.new()
	keep.name = "Donjon"
	var mesh := CylinderMesh.new()
	mesh.top_radius = keep_width * 0.38
	mesh.bottom_radius = keep_width * 0.52
	mesh.height = keep_height
	# Huit pans : assez pour ne pas être un cube, assez peu pour rester taillé.
	mesh.radial_segments = 8
	keep.mesh = mesh
	keep.material_override = material
	keep.position = Vector3(0.0, 2.5 + keep_height * 0.5, 0.0)
	add_child(keep)
	_add_collider(keep, Vector3(keep_width * 0.9, keep_height, keep_width * 0.9), keep.position)

	# Les créneaux. C'est ce qui fait lire « château » plutôt que « tour » :
	# une découpe en dents sur le ciel se reconnaît de très loin.
	_crown(Vector3(0.0, 2.5 + keep_height, 0.0), keep_width * 0.44, 10, material)


## LES TOURS. Quatre, plus hautes que le donjon : elles montent au-dessus de
## la crête du cirque, donc on les voit avant même d'être entré.
func _build_towers(material: Material) -> void:
	const OFFSETS: Array[Vector2] = [
		Vector2(-1.0, -0.72), Vector2(1.0, -0.72),
		Vector2(-1.0, 0.72), Vector2(1.0, 0.72),
	]
	for i in OFFSETS.size():
		var local: Vector2 = OFFSETS[i] * keep_width * 0.82
		# Les tours arrière sont plus hautes : la silhouette monte vers le
		# fond, ce qui creuse la perspective depuis l'entrée du cirque.
		var height: float = tower_height * (1.0 if local.y < 0.0 else 1.18)

		var tower := MeshInstance3D.new()
		tower.name = "Tour_%d" % i
		var mesh := CylinderMesh.new()
		mesh.top_radius = tower_radius * 0.82
		mesh.bottom_radius = tower_radius
		mesh.height = height
		mesh.radial_segments = 6
		tower.mesh = mesh
		tower.material_override = material
		tower.position = Vector3(local.x, 2.5 + height * 0.5, local.y)
		add_child(tower)
		_add_collider(tower, Vector3(tower_radius * 2.0, height, tower_radius * 2.0),
			tower.position)

		_crown(Vector3(local.x, 2.5 + height, local.y), tower_radius * 0.95, 6, material)


## Une couronne de créneaux. Les dents alternent en hauteur : régulières,
## elles feraient roue dentée.
func _crown(centre: Vector3, radius: float, count: int, material: Material) -> void:
	for i in count:
		var a: float = TAU * float(i) / float(count)
		var merlon := MeshInstance3D.new()
		merlon.name = "Creneau"
		var mesh := BoxMesh.new()
		var tall: bool = i % 2 == 0
		mesh.size = Vector3(radius * 0.42, 2.2 if tall else 1.4, radius * 0.42)
		merlon.mesh = mesh
		merlon.material_override = material
		merlon.position = centre + Vector3(cos(a) * radius, mesh.size.y * 0.5, sin(a) * radius)
		merlon.rotation.y = -a
		add_child(merlon)


## LA PORTE, scellée par une coulée figée.
##
## Elle est émissive : c'est le seul élément chaud d'une forteresse noire, donc
## le seul point d'accroche du regard. On sait où aller sans qu'on nous le
## dise.
func _build_gate() -> void:
	_gate = Node3D.new()
	_gate.name = "Porte"
	_gate.position = Vector3(0.0, 2.5, keep_width * 0.52)
	add_child(_gate)

	var panel := MeshInstance3D.new()
	panel.name = "Sceau"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(7.0, 10.0, 1.2)
	panel.mesh = mesh
	_gate_material = StandardMaterial3D.new()
	_gate_material.albedo_color = SEAL.darkened(0.55)
	_gate_material.emission_enabled = true
	_gate_material.emission = SEAL
	_gate_material.emission_energy_multiplier = 2.2
	_gate_material.roughness = 0.35
	panel.material_override = _gate_material
	panel.position = Vector3(0.0, 5.0, 0.0)
	_gate.add_child(panel)
	_add_collider(panel, mesh.size, _gate.position + panel.position)

	# LA CIBLE OPTIQUE. Un collider sur la couche des miroirs, plus large que
	# le battant : c'est lui que le rayon de lune doit toucher.
	#
	# Il est distinct du collider physique parce qu'ils ne servent pas à la
	# même chose — l'un arrête les joueurs, l'autre reçoit la lumière — et
	# parce que le premier disparaît quand la porte s'ouvre.
	#
	# Beaucoup plus HAUT que le battant : les miroirs portent leur plan optique
	# à quatorze mètres, et une cible à hauteur de porte serait survolée.
	var optic := StaticBody3D.new()
	optic.name = "CibleOptique"
	optic.collision_layer = MoonMirror.OPTICS_LAYER
	optic.collision_mask = 0
	var optic_shape := CollisionShape3D.new()
	var plate := BoxShape3D.new()
	plate.size = Vector3(11.0, 22.0, 0.6)
	optic_shape.shape = plate
	optic.add_child(optic_shape)
	optic.position = Vector3(0.0, 5.0, 0.4)
	_gate.add_child(optic)

	var glow := OmniLight3D.new()
	glow.name = "LueurDuSceau"
	glow.light_color = SEAL
	glow.light_energy = 2.4
	glow.omni_range = 22.0
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 5.0, 2.0)
	_gate.add_child(glow)


## Le sceau cède. Appelé par le puzzle des miroirs.
##
## La coulée refroidit d'abord — elle passe de l'orange au noir — PUIS la
## porte s'ouvre. L'ordre compte : c'est la lumière lunaire qui fige la lave,
## et non la porte qui décide de s'ouvrir.
func open_gate() -> void:
	if _open:
		return
	_open = true

	var tween: Tween = create_tween()
	if _gate_material != null:
		tween.tween_property(_gate_material, "emission_energy_multiplier", 0.05, 1.6)
		tween.parallel().tween_property(_gate_material, "albedo_color",
			Color(0.035, 0.030, 0.034), 1.6)
	var glow: OmniLight3D = _gate.get_node_or_null("LueurDuSceau") as OmniLight3D
	if glow != null:
		tween.parallel().tween_property(glow, "light_energy", 0.0, 1.6)

	# La collision part AVANT la fin de l'animation : un joueur collé au
	# battant ne doit pas rester coincé contre un mur devenu invisible.
	tween.chain().tween_callback(func() -> void:
		for child in get_children():
			var body: StaticBody3D = child as StaticBody3D
			if body != null and body.name.begins_with("Col_Sceau"):
				body.queue_free())
	tween.tween_property(_gate, "position",
		_gate.position - Vector3(0.0, 11.0, 0.0), 2.4) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	tween.tween_callback(func() -> void: gate_opened.emit())


func is_open() -> bool:
	return _open


## La position du sceau en repère monde — c'est la cible du rayon de lune.
func get_gate_target() -> Vector3:
	if _gate == null:
		return global_position
	return _gate.global_position + Vector3(0.0, 5.0, 0.0)


func _add_collider(source: MeshInstance3D, size: Vector3, at: Vector3) -> void:
	var body := StaticBody3D.new()
	body.name = "Col_%s" % source.name
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = at

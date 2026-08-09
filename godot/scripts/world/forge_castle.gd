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

## Le basalte taillé, généré par Meshy et projeté en triplanaire — cf
## `tools/build_forge_materials.gd` pour le pourquoi de cette voie plutôt que
## du « retexture-first » habituel.
const MASONRY_PATH := "res://assets/level02/materials/forge_masonry.tres"

## La terrasse : de combien elle est soulevée au-dessus de la base, et son
## épaisseur. Nommées parce que le pont doit arriver EXACTEMENT sur son dessus.
const TERRACE_LIFT: float = 1.0
const TERRACE_THICKNESS: float = 3.0

## Teinte de repli, si la matière manque. Un château invisible serait pire
## qu'un château gris : le repli garde la silhouette lisible.
const STONE := Color(0.055, 0.045, 0.050)
const STONE_DARK := Color(0.030, 0.024, 0.028)
const SEAL := Color(1.000, 0.478, 0.184)

var _terrain: CavernTerrainData
var _noise: FastNoiseLite
var _gate: Node3D
var _terrace_top: float = 0.0
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


## La maçonnerie, éventuellement assombrie. Retombe sur une couleur plate si
## la matière n'a pas été construite — le niveau reste jouable sans elle.
func _masonry(brightness: float) -> Material:
	var base: StandardMaterial3D = load(MASONRY_PATH) as StandardMaterial3D
	if base == null:
		push_warning("ForgeCastle : maçonnerie absente — repli sur une teinte plate.")
		var flat := StandardMaterial3D.new()
		flat.albedo_color = STONE if brightness >= 1.0 else STONE_DARK
		flat.roughness = 0.9
		return flat
	if is_equal_approx(brightness, 1.0):
		return base
	var shade: StandardMaterial3D = base.duplicate() as StandardMaterial3D
	shade.albedo_color = Color(brightness, brightness, brightness, 1.0)
	return shade


func _ground(at: Vector2) -> float:
	return CavernTerrainBuilder.sample_point(_terrain.floor_field, at, _noise)


func _build() -> void:
	var base: float = _ground(footprint_center)
	global_position = Vector3(footprint_center.x, base, footprint_center.y)

	var stone: Material = _masonry(1.0)
	# La terrasse est assombrie plutôt que changée de matière : c'est le MÊME
	# appareillage, posé à l'ombre du donjon. Deux matières différentes se
	# liraient comme deux bâtiments.
	var stone_dark: Material = _masonry(0.55)

	_terrace_top = base + TERRACE_LIFT + TERRACE_THICKNESS * 0.5
	_build_terrace(stone_dark)
	_build_keep(stone)
	_build_doorway(stone_dark)
	_build_towers(stone)
	_build_gate()


## LA TERRASSE. Une plateforme taillée qui rattrape le relief : sans elle, un
## donjon posé sur du terrain bruité flotterait d'un côté et s'enfoncerait de
## l'autre.
func _build_terrace(material: Material) -> void:
	var slab := MeshInstance3D.new()
	slab.name = "Terrasse"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(keep_width * 2.1, TERRACE_THICKNESS, keep_width * 1.7)
	slab.mesh = mesh
	slab.material_override = material
	slab.position = Vector3(0.0, TERRACE_LIFT, 0.0)
	add_child(slab)
	# SOURCE DE NAVMESH, contrairement au reste de la forteresse : c'est la
	# seule surface sur laquelle on MARCHE. Sans ce bit, les joueurs y montaient
	# — la couche physique suffit pour ça — mais aucun ennemi ne pouvait les y
	# suivre, et le chemin du navmesh s'arrêtait au pied de la terrasse.
	_add_collider(slab, mesh.size, slab.position,
		CavernTerrainBuilder.WORLD_COLLISION_LAYER | CavernTerrainBuilder.NAVMESH_SOURCE_LAYER)


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
	_hollow_keep(material)

	# Les créneaux. C'est ce qui fait lire « château » plutôt que « tour » :
	# une découpe en dents sur le ciel se reconnaît de très loin.
	_crown(Vector3(0.0, 2.5 + keep_height, 0.0), keep_width * 0.44, 10, material)


## LE DONJON EST CREUX, et sa collision le dit.
##
## Signalé en jeu : « quand on active le mécanisme ça descend un élément mais
## aucun passage ne s'ouvre ». Le sceau descendait devant un cylindre PLEIN —
## un seul collider en boîte pour toute la tour. Le mécanisme tenait sa
## promesse d'animation et pas celle du niveau.
##
## La collision est donc faite de huit murs, un par pan, avec un vide au sud
## là où se trouve l'embrasure. Ça coûte huit boîtes au lieu d'une, et ça rend
## la salle réelle : on entre, il y a un sol, et le reste tient debout.
##
## La salle est un CUL-DE-SAC, et c'est voulu. La route du boss passe par la
## rampe qui monte à l'extérieur (cf [KeepSpiralRamp]) — l'intérieur du donjon
## est la récompense du puzzle des miroirs, pas son passage obligé. Deux
## chemins pour la même porte les rendraient tous deux facultatifs.
func _hollow_keep(material: Material) -> void:
	var radius: float = keep_width * 0.46
	var wall: float = 1.8
	var faces: int = 8
	# Le pan 6 (compté depuis l'est, dans le sens du donjon) regarde le sud :
	# c'est là qu'est l'embrasure, donc c'est celui qu'on laisse ouvert.
	var doorway_face: int = 2
	# LE PAN OUEST EST RACCOURCI : c'est par là que la rampe extérieure entre
	# dans la tour, tout en haut. Sans cette brèche, l'ascension bute sur un mur
	# plein et la descente intérieure serait injoignable.
	var summit_face: int = 4

	for i in faces:
		if i == doorway_face:
			continue
		var a: float = TAU * float(i) / float(faces)
		var height: float = keep_height
		var lift: float = 2.5 + keep_height * 0.5
		if i == summit_face:
			# On s'arrête six mètres sous la couronne : de quoi passer debout.
			height = keep_height - 6.0
			lift = 2.5 + height * 0.5
		var body := StaticBody3D.new()
		body.name = "Col_Pan_%d" % i
		body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		# Un peu plus large que la corde d'un pan, pour que deux murs voisins
		# se recouvrent : sans recouvrement, on se coince dans l'angle.
		box.size = Vector3(radius * 0.92, height, wall)
		shape.shape = box
		body.add_child(shape)
		add_child(body)
		body.position = Vector3(cos(a) * radius, lift, sin(a) * radius)
		body.rotation.y = -a

	# LE SOL de la salle. Sans lui on tomberait à travers la terrasse.
	var floor_slab := MeshInstance3D.new()
	floor_slab.name = "SolDuDonjon"
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.6
	mesh.radial_segments = 8
	floor_slab.mesh = mesh
	floor_slab.material_override = material
	floor_slab.position = Vector3(0.0, 2.8, 0.0)
	add_child(floor_slab)
	_add_collider(floor_slab, Vector3(radius * 2.0, 0.6, radius * 2.0),
		floor_slab.position,
		CavernTerrainBuilder.WORLD_COLLISION_LAYER | CavernTerrainBuilder.NAVMESH_SOURCE_LAYER)

	# Un feu au centre : la salle serait autrement un trou noir, et personne
	# n'entre dans un trou noir.
	var brazier := OmniLight3D.new()
	brazier.name = "BrasierDuDonjon"
	brazier.light_color = SEAL
	brazier.light_energy = 2.6
	brazier.omni_range = 20.0
	brazier.shadow_enabled = false
	brazier.position = Vector3(0.0, 6.0, 0.0)
	add_child(brazier)


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


## L'EMBRASURE. Un vrai trou dans la base du donjon, derrière le sceau.
##
## Signalé en jeu : « dans le château il n'y a pas de porte pour rentrer ; quand
## on active le mécanisme ça descend un élément mais aucun passage ne s'ouvre ».
## C'était exact — le sceau descendait devant un mur plein. Le mécanisme tenait
## sa promesse d'animation et pas sa promesse de niveau.
##
## Le donjon étant un cylindre plein, on ne perce pas : on encadre. Deux
## jambages et un linteau posés en avant du fût dessinent une embrasure, et le
## vestibule derrière est un volume sombre qui donne au trou une PROFONDEUR.
## Sans lui, l'ouverture se lirait comme un décalque noir collé sur la tour.
func _build_doorway(material: Material) -> void:
	var opening := Node3D.new()
	opening.name = "Embrasure"
	opening.position = Vector3(0.0, TERRACE_LIFT + TERRACE_THICKNESS * 0.5,
		keep_width * 0.46)
	add_child(opening)

	var width: float = 7.6
	var height: float = 10.5
	var jamb: float = 2.2

	for side in [-1.0, 1.0]:
		var pillar := MeshInstance3D.new()
		pillar.name = "Jambage"
		var mesh := BoxMesh.new()
		mesh.size = Vector3(jamb, height, 2.4)
		pillar.mesh = mesh
		pillar.material_override = material
		pillar.position = Vector3((width * 0.5 + jamb * 0.5) * side, height * 0.5, 0.0)
		opening.add_child(pillar)
		_add_collider(pillar, mesh.size, opening.position + pillar.position)

	var lintel := MeshInstance3D.new()
	lintel.name = "Linteau"
	var lintel_mesh := BoxMesh.new()
	lintel_mesh.size = Vector3(width + jamb * 2.0, 2.4, 2.4)
	lintel.mesh = lintel_mesh
	lintel.material_override = material
	lintel.position = Vector3(0.0, height + 1.2, 0.0)
	opening.add_child(lintel)
	_add_collider(lintel, lintel_mesh.size, opening.position + lintel.position)

	# Pas de fond : l'embrasure DONNE sur la salle, qui est creuse. Une plaque
	# noire au fond ferait un trompe-l'œil, et c'est précisément ce qu'on
	# reprochait à la version précédente.


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
	# 0,9 et pas 2,2 : à 2,2, le sceau saturait en blanc et son halo effaçait la
	# moitié du cadre — y compris la maçonnerie qu'il est censé mettre en
	# valeur. Un point d'accroche qui aveugle n'accroche plus rien.
	_gate_material.emission_energy_multiplier = 0.9
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
	glow.light_energy = 1.5
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


## L'altitude du sol de la salle intérieure — là où la descente débouche.
func get_hall_altitude() -> float:
	return get_threshold_altitude() + 1.8


## L'altitude du dessus de la terrasse — le seuil que le pont doit rejoindre.
##
## Exposée plutôt que recalculée ailleurs : deux formules pour une même hauteur
## finissent toujours par diverger, et l'écart se voit comme une marche.
##
## Calculée À LA DEMANDE si la forteresse n'est pas encore bâtie. Elle se bâtit
## une frame après son `_ready`, et le pont a besoin de ce chiffre AVANT — le
## faire dépendre de l'ordre des frames serait précisément le genre de couplage
## qui casse en silence le jour où l'un des deux gagne une frame d'attente.
func get_threshold_altitude() -> float:
	if _terrace_top > 0.0:
		return _terrace_top
	if _terrain == null:
		return 0.0
	if _noise == null:
		_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)
	return _ground(footprint_center) + TERRACE_LIFT + TERRACE_THICKNESS * 0.5


## Le bord SUD de la terrasse, en Z. C'est là que le pont doit accoster.
func get_threshold_edge_z() -> float:
	return footprint_center.y + keep_width * 1.7 * 0.5


func is_open() -> bool:
	return _open


## La position du sceau en repère monde — c'est la cible du rayon de lune.
func get_gate_target() -> Vector3:
	if _gate == null:
		return global_position
	return _gate.global_position + Vector3(0.0, 5.0, 0.0)


func _add_collider(source: MeshInstance3D, size: Vector3, at: Vector3,
		layer: int = CavernTerrainBuilder.WORLD_COLLISION_LAYER) -> void:
	var body := StaticBody3D.new()
	body.name = "Col_%s" % source.name
	body.collision_layer = layer
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.position = at

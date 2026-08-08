class_name FrostLock
extends Interactable

## La Serrure de Givre — le mécanisme secret du niveau 1.
##
## Trois glyphes gravés dans la paroi du Seuil, **éteints**. Ils ne
## s'illuminent qu'à mesure que les cristaux du puzzle sont éveillés, et la
## serrure ne devient interactive qu'une fois les trois allumés.
##
## LE RYTHME VOULU (cf `docs/design/level01_topography.md` §6) : la Serrure est
## à quelques mètres du chemin obligatoire vers l'arène. On la frôle donc
## forcément, deux fois — à l'aller vers le boss, et au regard de la révélation.
## Personne ne la manque, personne ne la comprend avant d'avoir fini le puzzle.
## C'est cet écart entre « je l'ai vue » et « je sais ce que c'est » qui fait le
## secret.
##
## Elle se construit entièrement par code : c'est un ornement de paroi, pas un
## objet qui mérite sa propre scène à maintenir.

signal unlocked()

## Nombre de cristaux à éveiller. Fixé par [CavernGameplay] au moment du câblage,
## pour que la serrure ne présume pas du nombre de glyphes.
@export var required_count: int = 3

@export var rock_material: Material

## Couleur d'un glyphe éteint : visible, mais mort.
@export var dormant_color: Color = Color(0.20, 0.28, 0.38)

## Couleur d'un glyphe allumé.
@export var lit_color: Color = Color(0.36, 0.84, 1.0)

var _glyphs: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _glow: OmniLight3D
var _lit: int = 0
var _unlocked: bool = false


func _ready() -> void:
	super._ready()
	prompt_text = "Briser la serrure"
	hold_duration = 1.5
	interaction_range = 3.0
	selection_priority = 15
	_build_visual()
	_refresh()


func _build_visual() -> void:
	var area_shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.5
	area_shape.shape = sphere
	add_child(area_shape)

	# La dalle : une plaque de roche encastrée dans la paroi.
	var slab := MeshInstance3D.new()
	slab.name = "Dalle"
	var slab_mesh := BoxMesh.new()
	slab_mesh.size = Vector3(2.6, 2.2, 0.4)
	slab.mesh = slab_mesh
	slab.position = Vector3(0.0, 1.6, 0.0)
	if rock_material != null:
		slab.material_override = rock_material
	add_child(slab)

	# Les glyphes, alignés verticalement pour qu'on les compte d'un regard.
	for i in required_count:
		var glyph := MeshInstance3D.new()
		glyph.name = "Glyphe_%d" % i
		var glyph_mesh := TorusMesh.new()
		glyph_mesh.inner_radius = 0.16
		glyph_mesh.outer_radius = 0.30
		glyph_mesh.rings = 6
		glyph.mesh = glyph_mesh
		glyph.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		glyph.position = Vector3(0.0, 2.4 - float(i) * 0.7, 0.24)

		var material := StandardMaterial3D.new()
		material.albedo_color = dormant_color
		material.emission_enabled = true
		material.emission = dormant_color
		material.emission_energy_multiplier = 0.2
		glyph.material_override = material

		add_child(glyph)
		_glyphs.append(glyph)
		_materials.append(material)

	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.position = Vector3(0.0, 1.8, 0.6)
	_glow.light_color = lit_color
	_glow.light_energy = 0.0
	_glow.omni_range = 10.0
	_glow.shadow_enabled = false
	add_child(_glow)


## Appelé à chaque cristal éveillé. Les glyphes s'allument un par un : la
## serrure devient ainsi un COMPTEUR lisible, qui dit au joueur où il en est
## sans jamais l'expliquer.
func set_progress(lit: int, total: int) -> void:
	required_count = maxi(total, 1)
	_lit = clampi(lit, 0, _glyphs.size())
	_refresh()


func _refresh() -> void:
	for i in _materials.size():
		var on: bool = i < _lit
		var target: Color = lit_color if on else dormant_color
		var material: StandardMaterial3D = _materials[i]
		var tween: Tween = create_tween()
		tween.tween_property(material, "emission", target, 0.5)
		tween.parallel().tween_property(material, "albedo_color", target, 0.5)
		tween.parallel().tween_property(material, "emission_energy_multiplier",
			2.6 if on else 0.2, 0.5)

	if _glow != null:
		var tween: Tween = create_tween()
		tween.tween_property(_glow, "light_energy", 2.4 * float(_lit) / float(maxi(required_count, 1)), 0.5)


## Interactive seulement quand tous les glyphes sont allumés. Avant, on ne voit
## que des rainures : le joueur peut la toucher, il n'en tirera rien.
func can_interact(_by_player: Node) -> bool:
	return not _unlocked and _lit >= required_count


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	_unlocked = true

	# La serrure se consume : elle a servi, elle s'éteint.
	var tween: Tween = create_tween()
	if _glow != null:
		tween.tween_property(_glow, "light_energy", 8.0, 0.2)
		tween.tween_property(_glow, "light_energy", 0.0, 0.8)
	for material in _materials:
		tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, 0.8)

	unlocked.emit()
	interaction_completed.emit(by_player)
	remove_from_group(&"interactables")
	return true

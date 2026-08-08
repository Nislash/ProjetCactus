class_name CollapsedDoor
extends StaticBody3D

## La Porte Effondrée — l'éboulis qui bouche le Passage.
##
## Le goulet du Passage EXISTE dans le terrain dès le départ ; c'est cet
## amas de dalles qui l'obstrue. Ce choix n'est pas cosmétique : si le passage
## était absent de la géométrie, le navmesh ne saurait pas le cuire, et les
## ennemis comme les joueurs ignoreraient un raccourci qui devient pourtant
## central une fois ouvert.
##
## Quand la Serrure de Givre cède, la porte ne « s'ouvre » pas — elle
## **s'effondre**. C'est la même grammaire que le reste de la caverne : ici, la
## roche cède, elle ne pivote pas sur des gonds.

signal collapsed()

@export var rock_material: Material

## Nombre de dalles empilées.
@export var slab_count: int = 5

var _slabs: Array[MeshInstance3D] = []
var _collision: CollisionShape3D
var _has_collapsed: bool = false


func _ready() -> void:
	_build_visual()


func _build_visual() -> void:
	_collision = CollisionShape3D.new()
	_collision.name = "Shape"
	var box := BoxShape3D.new()
	box.size = Vector3(7.0, 5.0, 2.4)
	_collision.shape = box
	_collision.position = Vector3(0.0, 2.5, 0.0)
	add_child(_collision)

	# Des dalles empilées de guingois : un mur régulier se lirait comme une
	# construction, alors qu'on veut lire un effondrement.
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xC0110B5E
	for i in slab_count:
		var slab := MeshInstance3D.new()
		slab.name = "Dalle_%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(
			rng.randf_range(4.5, 7.0),
			rng.randf_range(1.0, 1.8),
			rng.randf_range(1.6, 2.6))
		slab.mesh = mesh
		slab.position = Vector3(
			rng.randf_range(-0.8, 0.8),
			0.5 + float(i) * 0.95,
			rng.randf_range(-0.4, 0.4))
		slab.rotation_degrees = Vector3(
			rng.randf_range(-7.0, 7.0),
			rng.randf_range(-14.0, 14.0),
			rng.randf_range(-9.0, 9.0))
		if rock_material != null:
			slab.material_override = rock_material
		add_child(slab)
		_slabs.append(slab)


## L'effondrement : les dalles s'affaissent et s'écartent, la collision tombe.
##
## La collision est retirée EN PREMIER, avant la fin de l'animation : le joueur
## qui vient de résoudre le puzzle doit pouvoir passer tout de suite. Attendre
## la fin de l'anim ferait croire à un bug.
func collapse() -> void:
	if _has_collapsed:
		return
	_has_collapsed = true

	if _collision != null:
		_collision.set_deferred("disabled", true)

	var rng := RandomNumberGenerator.new()
	rng.seed = 0x5A11EDEC
	for i in _slabs.size():
		var slab: MeshInstance3D = _slabs[i]
		var tween: Tween = create_tween()
		# Un léger décalage par dalle : elles ne tombent pas d'un bloc, la pile
		# se défait du haut vers le bas.
		tween.tween_interval(float(_slabs.size() - i) * 0.05)
		tween.tween_property(slab, "position",
			slab.position + Vector3(rng.randf_range(-2.5, 2.5), -slab.position.y - 0.6,
				rng.randf_range(-1.5, 1.5)), 0.7) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tween.parallel().tween_property(slab, "rotation_degrees",
			slab.rotation_degrees + Vector3(
				rng.randf_range(-40.0, 40.0),
				rng.randf_range(-60.0, 60.0),
				rng.randf_range(-40.0, 40.0)), 0.7)

	collapsed.emit()
	print("[CollapsedDoor] le Passage est ouvert.")

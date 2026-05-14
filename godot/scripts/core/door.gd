class_name Door
extends StaticBody3D

## Porte qui s'ouvre via Lever (ou autre source via Door.open()). Au _ready,
## la porte est CLOSED (collision active + visible). open() la passe OPEN
## (collision desactivee + invisible). Pas de re-fermeture pour le POC.
##
## Connecter via le pattern groupe : tous les Door avec le meme `lever_group`
## que le Lever s'ouvriront ensemble (cf lever.gd).

signal opened()

## Doit matcher le `lever_group` du Lever cible. Si vide, la porte ne sera
## jamais ouverte par un Lever (peut etre ouverte directement via open()).
@export var lever_group: StringName = &""

## Material custom applique au mesh au _ready. Permet de camoufler une
## porte "secrete" en lui donnant le meme material que le mur autour, sans
## dupliquer la scene door.tscn. Si null, garde le material par defaut.
@export var override_material: Material

@onready var _shape: CollisionShape3D = $CollisionShape3D if has_node("CollisionShape3D") else null
@onready var _mesh: MeshInstance3D = $Mesh if has_node("Mesh") else null

var is_open: bool = false


func _ready() -> void:
	add_to_group(&"doors")
	if override_material != null and _mesh != null:
		_mesh.material_override = override_material


func open() -> void:
	if is_open:
		return
	is_open = true
	if _shape != null:
		_shape.disabled = true
	if _mesh != null:
		_mesh.visible = false
	opened.emit()


## Hard-reset (utile pour des futurs sequences de puzzle qui rebooteraient
## la porte). Pas utilise dans le POC mais expose pour la lisibilite.
func close() -> void:
	if not is_open:
		return
	is_open = false
	if _shape != null:
		_shape.disabled = false
	if _mesh != null:
		_mesh.visible = true

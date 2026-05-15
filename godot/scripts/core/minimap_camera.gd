class_name MinimapCamera
extends Camera3D

## Camera orthographique top-down qui suit la position XZ d'un Node3D cible.
## Set par le HUD apres binding au player (set_follow_target).
##
## La camera ignore la rotation du joueur (nord toujours en haut). Si on
## voulait une rotation alignee sur le yaw du joueur, il faudrait
## modifier _process pour appliquer la rotation.

## Hauteur au-dessus du player (Y mondial = player.y + height).
@export var height: float = 35.0

## Taille orthographique. Plus petit = plus zoom-in.
@export var ortho_size: float = 32.0

var _follow_target: Node3D = null


func _ready() -> void:
	projection = Camera3D.PROJECTION_ORTHOGONAL
	size = ortho_size
	rotation_degrees = Vector3(-90, 0, 0)
	current = true


func set_follow_target(target: Node3D) -> void:
	_follow_target = target


func _process(_delta: float) -> void:
	if _follow_target == null or not is_instance_valid(_follow_target):
		return
	var pos: Vector3 = _follow_target.global_position
	pos.y += height
	global_position = pos

class_name Lever
extends Interactable

## Levier interactif. Au try_interact, emet activated. Reste actif (one-shot).
##
## Connecter le signal activated a Door.open() (ou autre target) via NodePath
## ou par code dans le level. Pour le pattern le plus simple, on utilise un
## groupe : tous les Door qui ont le meme `lever_group` que le Lever
## s'ouvriront a l'activation (cf door.gd).

signal activated(by_player: Node)

## Si non vide, le Lever appelle Door.open() sur tous les nodes du groupe
## "doors" qui ont le meme group_id. Permet de cabler N leviers vers M portes
## sans NodePath fragile.
@export var lever_group: StringName = &""

@onready var _handle: Node3D = $Handle if has_node("Handle") else null

var _activated: bool = false


func _ready() -> void:
	super._ready()
	prompt_text = "Activer le levier"
	hold_duration = 0.4
	interaction_range = 2.0
	selection_priority = 5  # Au-dessus des pickups (0), en-dessous des coffres (10)


func can_interact(_by_player: Node) -> bool:
	return not _activated


func try_interact(by_player: Node) -> bool:
	if _activated:
		return false
	_activated = true
	# Petit feedback visuel : bascule le handle de 45° si present.
	if _handle != null:
		_handle.rotation.x = deg_to_rad(45.0)
	activated.emit(by_player)
	interaction_completed.emit(by_player)
	_open_doors_in_group()
	return true


func _open_doors_in_group() -> void:
	if lever_group == &"":
		return
	for node in get_tree().get_nodes_in_group("doors"):
		if not (node is Door):
			continue
		var door: Door = node
		if door.lever_group == lever_group:
			door.open()

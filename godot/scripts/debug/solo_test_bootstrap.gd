extends Node

## Helper de test M1 : force l'inscription de la première manette détectée comme
## joueur 0 au démarrage, sans passer par le lobby. À supprimer / ignorer dès
## qu'on a le lobby → run flow câblé (M2).

@export var auto_register_first_device: bool = true


func _ready() -> void:
	if not auto_register_first_device:
		return
	# Laisser une frame à Godot pour énumérer les manettes branchées.
	await get_tree().process_frame
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		push_warning("[SoloTestBootstrap] Aucune manette connectée. Le joueur 0 restera inerte.")
		return
	var device_id: int = pads[0]
	var pid: int = PlayerManager.try_register_device(device_id)
	if pid == -1:
		push_warning("[SoloTestBootstrap] Échec d'inscription de la manette %d." % device_id)
	else:
		print("[SoloTestBootstrap] Joueur %d → manette %d (%s)" % [pid, device_id, Input.get_joy_name(device_id)])

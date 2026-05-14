extends Node

## Helper de test M1 : enregistre TOUTES les manettes connectées au démarrage.
## Permet de valider le split-screen sans passer par le lobby.
##
## À supprimer / ignorer quand le lobby → run flow sera câblé (M2).

@export var auto_register_all_devices: bool = true


func _ready() -> void:
	if not auto_register_all_devices:
		return
	await get_tree().process_frame
	var pads: Array = Input.get_connected_joypads()
	if pads.is_empty():
		push_warning("[MultiTestBootstrap] Aucune manette connectée — split-screen ne s'affichera pas.")
		return
	for device_id in pads:
		var pid: int = PlayerManager.try_register_device(device_id)
		if pid == -1:
			push_warning("[MultiTestBootstrap] Échec d'inscription manette %d." % device_id)
		else:
			print("[MultiTestBootstrap] Joueur %d → manette %d (%s)" % [pid, device_id, Input.get_joy_name(device_id)])

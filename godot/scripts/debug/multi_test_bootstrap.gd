extends Node

## Helper de test M1 : enregistre TOUTES les manettes connectées au démarrage.
## Permet de valider le split-screen sans passer par le lobby.
##
## À supprimer / ignorer quand le lobby → run flow sera câblé (M2).

@export var auto_register_all_devices: bool = true


func _ready() -> void:
	if not auto_register_all_devices:
		return
	# Plusieurs frames pour laisser Godot/macOS énumérer toutes les manettes
	# (le SDL backend peut prendre quelques ticks avant de signaler les devices).
	for _i in 5:
		await get_tree().process_frame

	var pads: Array = Input.get_connected_joypads()
	print("[MultiTestBootstrap] === Diagnostic joypads ===")
	print("[MultiTestBootstrap] Input.get_connected_joypads() = %s" % str(pads))
	for device_id in pads:
		print("[MultiTestBootstrap]   device %d : name=%s | guid=%s | known=%s" % [
			device_id,
			Input.get_joy_name(device_id),
			Input.get_joy_guid(device_id),
			Input.is_joy_known(device_id),
		])
	print("[MultiTestBootstrap] ==========================")

	# Écoute aussi les connexions futures (hot-plug pendant le run).
	Input.joy_connection_changed.connect(_on_joy_connection_changed)

	if pads.is_empty():
		push_warning("[MultiTestBootstrap] Aucune manette connectée — split-screen ne s'affichera pas.")
		return
	for device_id in pads:
		var pid: int = PlayerManager.try_register_device(device_id)
		if pid == -1:
			push_warning("[MultiTestBootstrap] Échec d'inscription manette %d." % device_id)
		else:
			print("[MultiTestBootstrap] Joueur %d → manette %d (%s)" % [pid, device_id, Input.get_joy_name(device_id)])


func _on_joy_connection_changed(device_id: int, connected: bool) -> void:
	print("[MultiTestBootstrap] joy_connection_changed device=%d connected=%s name=%s" % [
		device_id, connected, Input.get_joy_name(device_id) if connected else "?",
	])
	if connected:
		var pid: int = PlayerManager.try_register_device(device_id)
		if pid != -1:
			print("[MultiTestBootstrap] Hot-plug → Joueur %d → manette %d (%s)" % [pid, device_id, Input.get_joy_name(device_id)])

class_name MechanicLowGravity
extends Node

## Mécanique de niveau : gravité réduite. Réécrit la `gravity` de chaque
## PlayerController instancié dans le niveau (et à chaque player_joined
## tardif). Permet sauts longs (N3 Temple) ou zéro-G (N8 Vide cosmique).
##
## Usage : ajouter comme enfant du root Node3D du level avec gravity_value
## configuré dans l'inspector.

@export var gravity_value: float = 6.0
@export var jump_velocity_multiplier: float = 1.5


func _ready() -> void:
	# Laisse une frame au SplitScreenManager pour spawn les players.
	await get_tree().process_frame
	await get_tree().process_frame
	_apply_to_all_players()
	# Réapplique si des joueurs rejoignent tardivement.
	if PlayerManager.has_signal(&"player_joined"):
		PlayerManager.player_joined.connect(func(_pid, _did): _apply_to_all_players())


func _apply_to_all_players() -> void:
	var players: Array = get_tree().get_nodes_in_group(&"players")
	if players.is_empty():
		# Fallback : tous les PlayerController du tree.
		players = _find_all_players(get_tree().root)
	for p in players:
		if p is PlayerController:
			(p as PlayerController).gravity = gravity_value
			(p as PlayerController).jump_velocity = (p as PlayerController).jump_velocity * jump_velocity_multiplier
	print("[MechanicLowGravity] Appliqué à %d joueur(s) (gravity=%.1f)" % [players.size(), gravity_value])


func _find_all_players(node: Node) -> Array:
	var out: Array = []
	if node is PlayerController:
		out.append(node)
	for c in node.get_children():
		out.append_array(_find_all_players(c))
	return out

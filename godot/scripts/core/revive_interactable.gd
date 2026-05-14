class_name ReviveInteractable
extends Interactable

## Sur chaque PlayerController, expose le joueur comme Interactable QUAND il
## est DOWNED. Un allié maintient `interact` 3s a proximite -> revive.
##
## Architecture : enfant Area3D du player.tscn. _find_player remonte le tree
## pour trouver le PlayerController parent. can_interact filtre :
##   - pas de player parent -> false (sécurité)
##   - player parent pas DOWNED -> false
##   - by_player == _player (auto-revive) -> false
##
## prompt_text et hold_duration sont resolus au _ready / dynamiquement.

var _player: PlayerController = null


func _ready() -> void:
	super._ready()
	_player = _find_player_in_parents()
	hold_duration = 3.0
	interaction_range = 2.0
	# Priorite plus basse que les pickups (qui sont a 0). Si un allie downed
	# et une gemme sont a portee en meme temps, la gemme passe d'abord (logique
	# car beaucoup plus rapide a hold).
	selection_priority = -10
	if _player != null:
		prompt_text = "Relever J%d" % _player.player_id


func _find_player_in_parents() -> PlayerController:
	var current: Node = get_parent()
	while current != null:
		if current is PlayerController:
			return current as PlayerController
		current = current.get_parent()
	return null


func can_interact(by_player: Node) -> bool:
	if _player == null:
		return false
	if not _player.is_downed():
		return false
	if not (by_player is PlayerController):
		return false
	if by_player == _player:
		return false
	return true


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	_player.revive_by(by_player as PlayerController)
	interaction_completed.emit(by_player)
	return true

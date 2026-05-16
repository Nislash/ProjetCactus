class_name PuzzleGate
extends Node

## Multi-trigger door unlock. Écoute N Levers (ou autres sources qui émettent
## un signal `activated`). Quand TOUS sont activés, ouvre les Doors listées
## et émet puzzle_solved.
##
## Différent du pattern Lever standard (1 lever → 1 door via lever_group) :
## ici on attend N activations pour 1 (ou N) door(s). Sert au gating boss
## des niveaux 1-8 : "briser 3 cristaux", "abattre 3 totems", etc.

signal puzzle_solved()
signal progress_changed(activated: int, total: int)

@export var lever_paths: Array[NodePath] = []
@export var door_paths: Array[NodePath] = []
## Optionnel : material appliqué aux Levers non encore activés (feedback
## visuel "à activer"). Laissé null = pas de re-skin.
@export var pending_material: Material

var _activated_count: int = 0
var _required_count: int = 0
var _solved: bool = false


func _ready() -> void:
	_required_count = lever_paths.size()
	if _required_count == 0:
		push_warning("[PuzzleGate] Aucun lever assigné — la porte ne s'ouvrira jamais")
		return
	for path in lever_paths:
		var lever: Lever = get_node_or_null(path) as Lever
		if lever == null:
			push_warning("[PuzzleGate] lever path invalide : %s" % path)
			continue
		lever.activated.connect(_on_lever_activated)


func _on_lever_activated(_by_player: Node) -> void:
	if _solved:
		return
	_activated_count += 1
	progress_changed.emit(_activated_count, _required_count)
	print("[PuzzleGate] %d/%d activé(s)" % [_activated_count, _required_count])
	if _activated_count >= _required_count:
		_solved = true
		for path in door_paths:
			var door: Door = get_node_or_null(path) as Door
			if door != null:
				door.open()
		puzzle_solved.emit()
		print("[PuzzleGate] Puzzle résolu — portes ouvertes")


func is_solved() -> bool:
	return _solved


func get_progress() -> Vector2i:
	return Vector2i(_activated_count, _required_count)

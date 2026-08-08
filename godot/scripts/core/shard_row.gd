class_name ShardRow
extends Control

## Les éclats du verrou portés par CE joueur, sur le côté de son HUD.
##
## Quatre emplacements, toujours visibles : on voit du même coup ce qu'on
## tient **et** combien il en manque. N'afficher que les éclats possédés
## laisserait le joueur sans repère sur ce qu'il cherche.
##
## Il se construit par code. En quart d'écran, la place se négocie au pixel et
## la disposition change avec le nombre de joueurs : la calculer ici, à côté
## de la règle qui la justifie, vaut mieux que de la figer dans une scène.

const SLOT_SIZE := 26.0
const SLOT_GAP := 8.0

var _slots: Array[Panel] = []
var _held: int = 0


func _ready() -> void:
	# Ancré au bord droit, à mi-hauteur : hors du chemin de la barre de vie
	# (en bas à gauche) et de la minimap (en haut à droite).
	set_anchors_preset(Control.PRESET_CENTER_RIGHT)
	offset_left = -(SLOT_SIZE + 14.0)
	offset_right = -8.0
	var total: float = float(BossPuzzle.SHARD_COUNT) * SLOT_SIZE \
		+ float(BossPuzzle.SHARD_COUNT - 1) * SLOT_GAP
	offset_top = -total * 0.5
	offset_bottom = total * 0.5
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for i in BossPuzzle.SHARD_COUNT:
		var slot := Panel.new()
		slot.name = "Emplacement_%d" % i
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.position = Vector2(0.0, float(i) * (SLOT_SIZE + SLOT_GAP))
		slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(slot)
		_slots.append(slot)

	_refresh()


func bind(player: PlayerController) -> void:
	if player == null:
		return
	player.boss_shards_changed.connect(_on_shards_changed)
	_on_shards_changed(player.get_boss_shards())


func _on_shards_changed(count: int) -> void:
	_held = clampi(count, 0, _slots.size())
	_refresh()


## Un emplacement vide reste dessiné, en creux sombre. Rempli, il prend le
## vert glaciaire du verrou — la même couleur que les éclats au sol et que le
## cadran du pilier, pour qu'aucun apprentissage ne soit à refaire.
func _refresh() -> void:
	for i in _slots.size():
		var filled: bool = i < _held
		var style := StyleBoxFlat.new()
		style.bg_color = CrystalGrammar.COLOR_BOSS_LOCK if filled \
			else Color(0.06, 0.10, 0.14, 0.55)
		style.border_color = CrystalGrammar.COLOR_BOSS_LOCK.darkened(0.3 if filled else 0.7)
		style.set_border_width_all(2)
		style.set_corner_radius_all(4)
		# Un éclat porté « déborde » légèrement de son emplacement : le
		# remplissage seul se lit mal en quart d'écran.
		style.set_expand_margin_all(2.0 if filled else 0.0)
		_slots[i].add_theme_stylebox_override("panel", style)


func get_held() -> int:
	return _held

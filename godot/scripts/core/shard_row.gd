class_name ShardRow
extends Control

## Les éclats du verrou portés par CE joueur, sur le côté de son HUD.
##
## Quatre emplacements, toujours visibles : on voit du même coup ce qu'on
## tient **et** combien il en manque. N'afficher que les éclats possédés
## laisserait le joueur sans repère sur ce qu'il cherche.
##
## ## Où, et pourquoi là
##
## **En bas à gauche, juste au-dessus de la rangée de reliques.** C'est là que
## le joueur va chercher son inventaire, parce que c'est là qu'il en a déjà un.
## Un premier jet l'avait placé au bord droit, pour éviter la barre de vie et
## la minimap : personne ne l'y a trouvé. Le réflexe du joueur l'emporte sur
## la géométrie de l'écran.
##
## Il se construit par code. En quart d'écran, la place se négocie au pixel et
## la disposition change avec le nombre de joueurs : la calculer ici, à côté
## de la règle qui la justifie, vaut mieux que de la figer dans une scène.

const SLOT_SIZE := 30.0
const SLOT_GAP := 8.0
## La rangée de reliques occupe -180 à -120 depuis le bas. On se pose
## juste au-dessus.
const BOTTOM_OFFSET := -196.0

var _slots: Array[Panel] = []
var _held: int = 0


func _ready() -> void:
	var total: float = float(BossPuzzle.SHARD_COUNT) * SLOT_SIZE \
		+ float(BossPuzzle.SHARD_COUNT - 1) * SLOT_GAP

	# Ancré en bas à gauche, en RANGÉE HORIZONTALE — comme les reliques juste
	# en dessous. Deux inventaires côte à côte doivent se lire pareil.
	anchor_left = 0.0
	anchor_right = 0.0
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = 24.0
	offset_right = 24.0 + total
	offset_top = BOTTOM_OFFSET - SLOT_SIZE
	offset_bottom = BOTTOM_OFFSET
	mouse_filter = Control.MOUSE_FILTER_IGNORE

	for i in BossPuzzle.SHARD_COUNT:
		var slot := Panel.new()
		slot.name = "Emplacement_%d" % i
		slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
		slot.position = Vector2(float(i) * (SLOT_SIZE + SLOT_GAP), 0.0)
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

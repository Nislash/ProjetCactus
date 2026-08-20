extends Node

## Aperçu du menu de pause, hors partie.
##
## Le menu ne s'ouvre normalement qu'avec une manette, en pleine partie, sur un
## niveau chargé : conditions qu'on ne réunit pas pour juger d'un alignement ou
## d'un contraste. Ici il s'ouvre seul, sur un fond sombre du même ton que la
## caverne, et fait défiler ses trois pages toutes les cinq secondes.
##
## Lancer `tools/pause_menu_preview.tscn` depuis l'éditeur.

const PAUSE_MENU := "res://scenes/ui/hud/pause_menu.tscn"
const PAGE_SECONDS := 5.0

var _menu: CanvasLayer
var _page: int = 0


func _ready() -> void:
	_build_backdrop()
	_menu = (load(PAUSE_MENU) as PackedScene).instantiate() as CanvasLayer
	add_child(_menu)
	# Joueur 2 : la couleur du sous-titre suit celle du slot, autant vérifier
	# qu'elle n'est pas celle du joueur 1 par accident.
	_menu.call("open", 1)

	var timer := Timer.new()
	timer.wait_time = PAGE_SECONDS
	timer.autostart = true
	# L'aperçu tourne pendant que le menu gèle l'arbre — sans ça, le minuteur
	# ne battrait jamais et la page ne changerait pas.
	timer.process_mode = Node.PROCESS_MODE_ALWAYS
	process_mode = Node.PROCESS_MODE_ALWAYS
	timer.timeout.connect(_next_page)
	add_child(timer)


func _next_page() -> void:
	_page = (_page + 1) % 3
	if _page == 2:
		_menu.call("_ask_confirm", &"lobby")
	else:
		_menu.call("_show_page", _page)
	print("[PauseMenuPreview] page %d" % _page)


## Un aplat sombre plutôt qu'un vrai niveau : le voile du menu se juge sur un
## fond, pas sur du noir pur — sur du noir, n'importe quelle opacité passe.
func _build_backdrop() -> void:
	var layer := CanvasLayer.new()
	layer.layer = -1
	add_child(layer)
	var rect := ColorRect.new()
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	rect.color = Color(0.09, 0.16, 0.21)
	layer.add_child(rect)
	var glow := ColorRect.new()
	glow.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	glow.color = Color(0.40, 0.85, 1.00, 0.10)
	glow.offset_left = 200.0
	glow.offset_top = 120.0
	glow.offset_right = -200.0
	glow.offset_bottom = -120.0
	layer.add_child(glow)

class_name PauseMenu
extends CanvasLayer

## Le menu de pause. Start (+) pendant une partie gèle le monde et ouvre
## l'écran classique : Reprendre, Réglages, Retour au menu, Quitter.
##
## ## Pourquoi un CanvasLayer et pas un Control comme les autres écrans
##
## Le jeu est en split-screen : chaque joueur a son `SubViewport` et son HUD
## dedans. La pause, elle, concerne la table entière — un seul écran, par
## dessus les quatre vues. Un `CanvasLayer` haut placé passe devant tout, quel
## que soit l'ordre des nœuds dans le run.
##
## ## Qui met en pause, qui pilote
##
## N'importe quelle manette inscrite ouvre le menu, et le joueur qui a appuyé
## est nommé à l'écran — à quatre autour d'un écran, savoir à qui parler évite
## la moitié des « c'est qui qui a mis pause ? ».
##
## La navigation passe ensuite par les actions `ui_*` (D-pad + A/B, tous
## devices), exactement comme au lobby. Réserver le curseur à la seule manette
## qui a mis en pause serait plus « correct » et plus frustrant : c'est
## systématiquement quelqu'un d'autre qui veut baisser le son.
##
## ## Ce que la pause gèle
##
## `get_tree().paused = true` arrête le monde, les ennemis, les timers, les
## tweens et les `_physics_process` des joueurs — donc personne ne tire ni ne
## se fait toucher pendant que le menu est ouvert (le tir ami est actif, la
## question n'est pas théorique). Ce nœud est en `PROCESS_MODE_ALWAYS` : lui
## continue de tourner, c'est comme ça qu'il peut relire Start pour reprendre.

const LOBBY_SCENE := "res://scenes/ui/lobby/lobby.tscn"

enum Page { ROOT, SETTINGS, CONFIRM }

## Émis à l'ouverture, avec le joueur qui a appuyé sur Start.
signal opened(player_id: int)
signal closed()

var _is_open: bool = false
var _page: Page = Page.ROOT
var _pauser_id: int = -1
## Ce que le panneau de confirmation validera : &"lobby" ou &"quit".
var _confirm_kind: StringName = &""

var _screen: Control
var _menu_page: PanelContainer
var _settings_page: PanelContainer
var _confirm_page: PanelContainer
var _subtitle: Label
var _btn_resume: Button
var _confirm_label: Label
var _btn_confirm_no: Button
var _volume_slider: HSlider
var _volume_value: Label
var _sensitivity_slider: HSlider
var _sensitivity_value: Label
var _view_check: CheckButton


func _ready() -> void:
	# Au dessus du HUD, du boss HUD et de l'écran de fin de combat.
	layer = 128
	process_mode = Node.PROCESS_MODE_ALWAYS
	# Le volume enregistré n'existerait sinon que tant que le menu est ouvert.
	GameSettings.apply_master_volume()
	_build_ui()
	_screen.visible = false


func is_open() -> bool:
	return _is_open


## Ouvre le menu et gèle la partie. Retourne false si ce n'est pas le moment :
## un écran de fin (game over, stats de boss) attend déjà un appui, et deux
## écrans qui écoutent le même bouton, c'est un des deux qui gagne au hasard.
func open(player_id: int = -1) -> bool:
	if _is_open or not _can_open():
		return false
	_pauser_id = player_id
	_is_open = true
	_screen.visible = true
	_refresh_subtitle()
	_refresh_settings_widgets()
	_show_page(Page.ROOT)
	get_tree().paused = true
	opened.emit(player_id)
	return true


func close() -> void:
	if not _is_open:
		return
	_is_open = false
	_screen.visible = false
	_confirm_kind = &""
	get_tree().paused = false
	closed.emit()


func _process(_delta: float) -> void:
	var presser: int = _poll_pause_button()
	if presser == -1:
		return
	# Un seul point de bascule : lire Start ici et le relire ailleurs pour
	# fermer rouvrirait le menu dans la frame de sa propre ouverture.
	if _is_open:
		close()
	else:
		open(presser)


func _unhandled_input(event: InputEvent) -> void:
	if not _is_open:
		return
	if not event.is_action_pressed(&"ui_cancel"):
		return
	get_viewport().set_input_as_handled()
	if _page == Page.ROOT:
		close()
	else:
		_show_page(Page.ROOT)


## Le Start de n'importe quelle manette inscrite. On passe par InputRouter et
## non par `Input` : c'est la règle du projet, et c'est aussi ce qui permet de
## dire QUI a mis en pause.
func _poll_pause_button() -> int:
	for player_id in InputRouter.get_active_player_ids():
		if InputRouter.is_action_just_pressed(player_id, &"pause"):
			return player_id
	return -1


func _can_open() -> bool:
	if not is_inside_tree():
		return false
	# L'arbre déjà gelé par quelqu'un d'autre : on ne se superpose pas, et
	# surtout on ne dégèlerait pas à tort en fermant.
	if get_tree().paused:
		return false
	return not _blocking_overlay_visible()


func _blocking_overlay_visible() -> bool:
	var parent: Node = get_parent()
	if parent == null:
		return false
	for child in parent.get_children():
		if not (child is GameOverScreen or child is BossPostCombat):
			continue
		var overlay := child as CanvasItem
		if overlay != null and overlay.visible:
			return true
	return false


# --- Actions du menu --------------------------------------------------------

func _ask_confirm(kind: StringName) -> void:
	_confirm_kind = kind
	if kind == &"lobby":
		_confirm_label.text = "Abandonner le run et revenir au menu ?\nRien n'est conservé."
	else:
		_confirm_label.text = "Quitter le jeu ?\nRien n'est conservé."
	_show_page(Page.CONFIRM)


func _on_confirm_yes() -> void:
	match _confirm_kind:
		&"lobby":
			_quit_to_lobby()
		&"quit":
			get_tree().quit()


## Abandon volontaire du run. On clôt RunState comme le fait l'écran de game
## over : sans ça, classes, armes et XP de la partie quittée survivraient à
## l'écran d'accueil et repartiraient dans la suivante.
func _quit_to_lobby() -> void:
	# Dégeler AVANT de changer de scène : `paused` est porté par le SceneTree,
	# pas par la scène — le lobby s'ouvrirait figé, curseur bloqué.
	close()
	Engine.time_scale = 1.0
	RunState.end_run(RunState.REASON_QUIT)
	RunState.reset()
	get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_volume_changed(value: float) -> void:
	GameSettings.set_master_volume(value)
	_volume_value.text = "%d %%" % roundi(value * 100.0)


func _on_sensitivity_changed(value: float) -> void:
	GameSettings.set_look_sensitivity(value)
	GameSettings.apply_look_sensitivity(get_tree())
	_sensitivity_value.text = "%.2f" % value


## La vue est un réglage PAR MANETTE (cf [ViewPreference]) : on ne l'applique
## qu'au joueur qui a ouvert le menu, jamais aux trois autres.
func _on_view_toggled(pressed: bool) -> void:
	var player: PlayerController = _pauser_controller()
	if player != null:
		player.set_third_person(pressed)


func _pauser_controller() -> PlayerController:
	if _pauser_id < 0 or not is_inside_tree():
		return null
	for node in get_tree().get_nodes_in_group(&"players"):
		var player := node as PlayerController
		if player != null and player.player_id == _pauser_id:
			return player
	return null


# --- Construction de l'écran ------------------------------------------------
#
# Tout est bâti en code plutôt que rangé dans le .tscn, comme l'habillage du
# lobby : les couleurs viennent de LobbyTheme, donc du même endroit que celles
# du menu d'accueil. Un écran de pause qui ne ressemble pas au reste du jeu se
# remarque immédiatement.

func _build_ui() -> void:
	_screen = Control.new()
	_screen.name = "Screen"
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_screen)

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(0.012, 0.024, 0.039, 0.82)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_screen.add_child(center)

	_menu_page = _build_menu_page()
	_settings_page = _build_settings_page()
	_confirm_page = _build_confirm_page()
	center.add_child(_menu_page)
	center.add_child(_settings_page)
	center.add_child(_confirm_page)


func _build_menu_page() -> PanelContainer:
	var panel := _page_panel("MenuPage")
	var vbox: VBoxContainer = panel.get_node(^"Margin/VBox")

	var title := Label.new()
	LobbyTheme.style_title(title, "PAUSE")
	title.add_theme_font_size_override(&"font_size", 64)
	vbox.add_child(title)

	_subtitle = Label.new()
	LobbyTheme.style_subtitle(_subtitle)
	vbox.add_child(_subtitle)
	vbox.add_child(_spacer(12))

	_btn_resume = _menu_button("Reprendre", true)
	_btn_resume.pressed.connect(close)
	vbox.add_child(_btn_resume)

	var btn_settings := _menu_button("Réglages")
	btn_settings.pressed.connect(func() -> void: _show_page(Page.SETTINGS))
	vbox.add_child(btn_settings)

	var btn_lobby := _menu_button("Retour au menu")
	btn_lobby.pressed.connect(func() -> void: _ask_confirm(&"lobby"))
	vbox.add_child(btn_lobby)

	var btn_quit := _menu_button("Quitter le jeu")
	btn_quit.pressed.connect(func() -> void: _ask_confirm(&"quit"))
	vbox.add_child(btn_quit)

	vbox.add_child(_spacer(6))
	vbox.add_child(_hint("A valider · B ou Start reprendre"))
	return panel


func _build_settings_page() -> PanelContainer:
	var panel := _page_panel("SettingsPage")
	var vbox: VBoxContainer = panel.get_node(^"Margin/VBox")

	var title := Label.new()
	title.text = "Réglages"
	title.add_theme_font_size_override(&"font_size", 34)
	title.add_theme_color_override(&"font_color", LobbyTheme.COLD)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)
	vbox.add_child(_spacer(8))

	_volume_slider = HSlider.new()
	_volume_slider.min_value = 0.0
	_volume_slider.max_value = 1.0
	_volume_slider.step = 0.05
	_volume_value = _value_label()
	vbox.add_child(_setting_row("Volume général", _volume_slider, _volume_value))
	_volume_slider.value_changed.connect(_on_volume_changed)

	_sensitivity_slider = HSlider.new()
	_sensitivity_slider.min_value = GameSettings.SENSITIVITY_MIN
	_sensitivity_slider.max_value = GameSettings.SENSITIVITY_MAX
	_sensitivity_slider.step = 0.25
	_sensitivity_value = _value_label()
	vbox.add_child(_setting_row("Sensibilité de visée", _sensitivity_slider, _sensitivity_value))
	_sensitivity_slider.value_changed.connect(_on_sensitivity_changed)

	_view_check = CheckButton.new()
	_view_check.toggled.connect(_on_view_toggled)
	vbox.add_child(_setting_row("Vue à la troisième personne", _view_check, null))

	vbox.add_child(_spacer(6))
	vbox.add_child(_hint("La vue ne change que pour la manette qui a mis en pause · B pour revenir"))
	return panel


func _build_confirm_page() -> PanelContainer:
	var panel := _page_panel("ConfirmPage")
	var vbox: VBoxContainer = panel.get_node(^"Margin/VBox")

	_confirm_label = Label.new()
	_confirm_label.add_theme_font_size_override(&"font_size", 24)
	_confirm_label.add_theme_color_override(&"font_color", LobbyTheme.PALE)
	_confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(_confirm_label)
	vbox.add_child(_spacer(12))

	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override(&"separation", 18)
	vbox.add_child(row)

	var btn_yes := _menu_button("Oui")
	btn_yes.pressed.connect(_on_confirm_yes)
	row.add_child(btn_yes)

	# Le focus par défaut est sur « Non » : un abandon de run se demande, il ne
	# se déclenche pas en appuyant deux fois sur A par réflexe.
	_btn_confirm_no = _menu_button("Non")
	_btn_confirm_no.pressed.connect(func() -> void: _show_page(Page.ROOT))
	row.add_child(_btn_confirm_no)
	return panel


func _page_panel(node_name: String) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = node_name
	LobbyTheme.style_panel(panel)
	var margin := MarginContainer.new()
	margin.name = "Margin"
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_%s" % side, 30)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	vbox.add_theme_constant_override(&"separation", 12)
	margin.add_child(vbox)
	return panel


## Une ligne de réglage : un chevron, un intitulé, le widget, sa valeur.
##
## Le chevron et l'intitulé en cyan tiennent lieu de curseur. Un `HSlider` qui
## a le focus ne se distingue pas d'un autre dans le thème par défaut : à la
## manette, depuis un canapé, on ne saurait pas quelle ligne on est en train de
## régler — et on baisserait le volume en croyant changer la sensibilité.
func _setting_row(label_text: String, control: Control, value_label: Label) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override(&"separation", 12)

	var marker := Label.new()
	marker.text = "›"
	marker.custom_minimum_size = Vector2(18, 0)
	marker.add_theme_font_size_override(&"font_size", 22)
	marker.add_theme_color_override(&"font_color", LobbyTheme.COLD)
	# Masqué par l'alpha et non par `visible` : un enfant caché sort du
	# conteneur, et toute la ligne se décalerait au changement de focus.
	marker.modulate.a = 0.0
	row.add_child(marker)

	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size = Vector2(250, 0)
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", LobbyTheme.PALE)
	row.add_child(label)

	control.custom_minimum_size = Vector2(280, 32)
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	control.focus_entered.connect(_set_row_focus.bind(marker, label, true))
	control.focus_exited.connect(_set_row_focus.bind(marker, label, false))

	if value_label != null:
		row.add_child(value_label)
	else:
		# Une colonne vide de même largeur : sans elle, la ligne de la vue
		# serait plus courte que les deux autres et le bloc partirait de
		# travers.
		row.add_child(_spacer_width(70))
	return row


func _set_row_focus(marker: Label, label: Label, focused: bool) -> void:
	marker.modulate.a = 1.0 if focused else 0.0
	label.add_theme_color_override(
		&"font_color", LobbyTheme.COLD if focused else LobbyTheme.PALE)


func _value_label() -> Label:
	var label := Label.new()
	label.custom_minimum_size = Vector2(70, 0)
	label.add_theme_font_size_override(&"font_size", 18)
	label.add_theme_color_override(&"font_color", LobbyTheme.COLD)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return label


func _menu_button(text: String, primary: bool = false) -> Button:
	var button := Button.new()
	button.text = text
	LobbyTheme.style_button(button, primary)
	return button


func _hint(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override(&"font_size", 14)
	label.add_theme_color_override(&"font_color", LobbyTheme.DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer


func _spacer_width(width: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(width, 0)
	return spacer


func _show_page(page: Page) -> void:
	_page = page
	_menu_page.visible = page == Page.ROOT
	_settings_page.visible = page == Page.SETTINGS
	_confirm_page.visible = page == Page.CONFIRM
	# Le focus est le seul repère de navigation à la manette : une page qui
	# s'ouvre sans focus est une page où le D-pad ne fait rien.
	match page:
		Page.ROOT:
			_btn_resume.grab_focus()
		Page.SETTINGS:
			_volume_slider.grab_focus()
		Page.CONFIRM:
			_btn_confirm_no.grab_focus()


func _refresh_subtitle() -> void:
	if _pauser_id < 0:
		_subtitle.text = "Partie en pause"
		return
	_subtitle.text = "Joueur %d a mis la partie en pause" % (_pauser_id + 1)
	_subtitle.add_theme_color_override(&"font_color", LobbyTheme.slot_color(_pauser_id))


## Recharge les widgets depuis l'état réel (fichier de réglages, vue courante
## du joueur) sans redéclencher les callbacks : `set_value` émettrait
## `value_changed` et réécrirait le fichier à chaque ouverture.
func _refresh_settings_widgets() -> void:
	var volume: float = GameSettings.master_volume()
	_volume_slider.set_value_no_signal(volume)
	_volume_value.text = "%d %%" % roundi(volume * 100.0)

	var sensitivity: float = GameSettings.look_sensitivity()
	_sensitivity_slider.set_value_no_signal(sensitivity)
	_sensitivity_value.text = "%.2f" % sensitivity

	var player: PlayerController = _pauser_controller()
	_view_check.set_pressed_no_signal(player != null and player.is_third_person())
	_view_check.disabled = player == null

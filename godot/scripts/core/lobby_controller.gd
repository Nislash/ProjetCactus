extends Control

## Pilote la scene lobby (scenes/ui/lobby/lobby.tscn) — main menu du jeu.
##
## Phases :
## - JOIN : aucun joueur encore inscrit. Les manettes peuvent presser Start
##   pour rejoindre. Boutons menu invisibles tant que personne n'est joint.
## - MENU : 1+ joueur joint. Un bouton principal (Lancer), le choix du niveau,
##   et deux boutons secondaires (Leaderboard, Réglages).
## - PANEL : un sous-panel (leaderboard / settings) est ouvert. B pour
##   revenir au menu.
##
## Niveau 1 et Run set RunState.selected_level_path puis change_scene_to_file
## vers res://scenes/run/run_shell.tscn — le shell instancie le level.
##
## Pour ajouter un nouveau level jouable via "Lancer le Run", ajoutez une
## entree au tableau LEVELS ci-dessous. Le dropdown se peuple
## automatiquement au _ready et le bouton Run lance le level selectionne.
##
## Navigation menu : on utilise les actions Godot built-in `ui_up`, `ui_down`,
## `ui_accept`, `ui_cancel`. Project.godot ajoute D-pad + A/B sur ces actions
## (any device) pour qu'elles fonctionnent en couch coop sans avoir a router
## par player_id.

const RUN_SHELL_SCENE := "res://scenes/run/run_shell.tscn"
const MAX_PLAYERS: int = 4

## Les niveaux jouables. Un seul critère pour figurer ici : **être fini**.
##
## Il y en avait dix-sept — les huit sorties de la pipeline générative et les
## huit blockouts archivés, aucun à la qualité du niveau 1. Une liste où
## quinze entrées sur dix-sept déçoivent n'est pas un choix, c'est un piège.
## Elles restent sur disque, elles ne sont simplement plus proposées.
##
## Le bouton « Tutoriel » a disparu avec elles : l'ancienne arène de test qu'il
## lançait devient le **niveau 2**, refaite dans le biome de la Forge. On
## n'apprend plus à jouer dans un décor de test — on apprend dans l'Antichambre
## de Givre, qui ouvre le niveau 1.
const LEVELS: Array = [
	{"id": 1, "name": "Caverne Cristalline", "path": "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"},
	{"id": 2, "name": "La Forge", "path": "res://scenes/levels/level_02_forge/level_02_forge.tscn"},
]

enum Phase { JOIN, MENU, LEADERBOARD, SETTINGS }

@onready var _slots: Array[LobbySlotUI] = [
	%Slot0 as LobbySlotUI,
	%Slot1 as LobbySlotUI,
	%Slot2 as LobbySlotUI,
	%Slot3 as LobbySlotUI,
]
@onready var _status_label: Label = %StatusLabel
@onready var _menu_panel: Control = %MenuPanel
@onready var _leaderboard_panel: Control = %LeaderboardPanel
@onready var _settings_panel: Control = %SettingsPanel
@onready var _btn_run: Button = %BtnRun
@onready var _level_dropdown: OptionButton = %LevelDropdown
@onready var _btn_leaderboard: Button = %BtnLeaderboard
@onready var _btn_settings: Button = %BtnSettings

var _phase: Phase = Phase.JOIN


func _ready() -> void:
	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)
	PlayerManager.open_lobby()

	_btn_run.pressed.connect(_on_run_pressed)
	_btn_leaderboard.pressed.connect(_on_leaderboard_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)

	_apply_theme()
	_populate_level_dropdown()
	_adopt_existing_players()
	_refresh_status()


## RÉCUPÈRE LES JOUEURS DÉJÀ INSCRITS, au lieu de repartir de zéro.
##
## Signalé en jeu : après un game over, le lobby revenait « incomplet » et ne
## permettait plus de relancer.
##
## La cause : les manettes restent enregistrées d'une run à l'autre — c'est
## voulu, personne n'a envie de refaire l'appel après chaque mort. Mais le
## lobby forçait la phase JOIN à son `_ready` et n'attendait plus que le signal
## `player_joined` pour en sortir. Ce signal ne pouvait plus venir : les joueurs
## étaient déjà là, et `poll_lobby_joins` ignore les manettes connues. On
## restait donc bloqué sur un écran d'attente, slots vides, bouton « Lancer »
## invisible, sans aucun moyen d'en sortir.
##
## Le lobby lit maintenant l'état plutôt que de l'attendre.
func _adopt_existing_players() -> void:
	var joined: Array[int] = PlayerManager.get_active_player_ids()
	for player_id in joined:
		if player_id < _slots.size():
			_slots[player_id].set_joined(PlayerManager.get_device_id(player_id))
	_set_phase(Phase.MENU if not joined.is_empty() else Phase.JOIN)


## Habille l'écran. Il était en boutons Godot par défaut : gris, arrondis,
## police système. C'est la première chose qu'un joueur voit du jeu, et un
## menu par défaut annonce un jeu par défaut.
func _apply_theme() -> void:
	# L'ancien fond était un aplat opaque. Le masquer plutôt que le supprimer :
	# la scène reste ouvrable sans ce script, et un `ColorRect` absent ferait
	# un `@onready` cassé chez quiconque le référencerait.
	var flat: CanvasItem = get_node_or_null("Background") as CanvasItem
	if flat != null:
		flat.visible = false

	var backdrop := LobbyBackdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)
	# Derrière tout le reste : ajouté en dernier, il passerait devant.
	move_child(backdrop, 0)

	# Le contenu était collé en haut de l'écran, le reste vide. On l'étale et
	# on le centre : en 4-split comme en plein écran, le regard va au milieu.
	var layout: Control = get_node_or_null("Layout") as Control
	if layout is VBoxContainer:
		layout.set_anchors_preset(Control.PRESET_FULL_RECT)
		layout.offset_top = 60.0
		layout.offset_bottom = -60.0
		(layout as VBoxContainer).alignment = BoxContainer.ALIGNMENT_CENTER
		layout.add_theme_constant_override("separation", 28)

	var title: Label = get_node_or_null("Layout/Title") as Label
	if title != null:
		LobbyTheme.style_title(title, "PROJET CACTUS")
	if _status_label != null:
		LobbyTheme.style_subtitle(_status_label)

	for button in [_btn_run, _btn_leaderboard, _btn_settings]:
		if button != null:
			LobbyTheme.style_button(button, button == _btn_run)

	for panel in [_leaderboard_panel, _settings_panel]:
		if panel is PanelContainer:
			LobbyTheme.style_panel(panel as PanelContainer)

	for i in _slots.size():
		if _slots[i] != null:
			_slots[i].apply_theme(i)


func _populate_level_dropdown() -> void:
	_level_dropdown.clear()
	for i in LEVELS.size():
		var lvl: Dictionary = LEVELS[i]
		_level_dropdown.add_item("%d — %s" % [lvl.id, lvl.name], i)
	if LEVELS.size() > 0:
		_level_dropdown.select(0)


func _process(_delta: float) -> void:
	# Le PlayerManager scrute Start sur les manettes non-inscrites.
	PlayerManager.poll_lobby_joins()

	# Quitter son slot avec Back. On le route via PlayerManager pour les
	# joueurs deja inscrits — pas via ui_cancel (qui sert a back menu).
	for pid in PlayerManager.get_active_player_ids():
		if InputRouter.is_action_just_pressed(pid, &"lobby_leave"):
			PlayerManager.unregister_player(pid)
			return

	# Sortie de panel via ui_cancel (B button mappe globalement).
	if _phase == Phase.LEADERBOARD or _phase == Phase.SETTINGS:
		if Input.is_action_just_pressed(&"ui_cancel"):
			_set_phase(Phase.MENU)


func _set_phase(new_phase: Phase) -> void:
	_phase = new_phase
	_menu_panel.visible = (new_phase == Phase.MENU)
	_leaderboard_panel.visible = (new_phase == Phase.LEADERBOARD)
	_settings_panel.visible = (new_phase == Phase.SETTINGS)
	if new_phase == Phase.MENU:
		_btn_run.grab_focus()


func _on_player_joined(player_id: int, device_id: int) -> void:
	if player_id < _slots.size():
		_slots[player_id].set_joined(device_id)
	# Premier joueur joint -> on bascule en MENU.
	if _phase == Phase.JOIN:
		_set_phase(Phase.MENU)
	_refresh_status()


func _on_player_left(player_id: int) -> void:
	if player_id < _slots.size():
		_slots[player_id].set_empty()
	# Plus aucun joueur -> retour en JOIN.
	if PlayerManager.get_active_player_count() == 0:
		_set_phase(Phase.JOIN)
	_refresh_status()


func _refresh_status() -> void:
	var count: int = PlayerManager.get_active_player_count()
	if count == 0:
		_status_label.text = "Appuyez sur Start pour rejoindre."
	else:
		_status_label.text = "%d/%d joueur(s) — D-pad pour naviguer, A pour valider, Back pour quitter le slot." % [count, MAX_PLAYERS]


func _on_run_pressed() -> void:
	var idx: int = _level_dropdown.get_selected_id()
	if idx < 0 or idx >= LEVELS.size():
		idx = 0
	_launch_level(LEVELS[idx].path)


func _on_leaderboard_pressed() -> void:
	_set_phase(Phase.LEADERBOARD)


func _on_settings_pressed() -> void:
	_set_phase(Phase.SETTINGS)


func _launch_level(level_path: String) -> void:
	if PlayerManager.get_active_player_count() == 0:
		_status_label.text = "Au moins 1 joueur doit rejoindre avec Start."
		return
	RunState.selected_level_path = level_path
	# PlayerManager.start_run() bascule l'etat lobby -> jeu (pas de nouveaux
	# joins automatiques pendant le run).
	PlayerManager.start_run()
	get_tree().change_scene_to_file(RUN_SHELL_SCENE)

extends Control

## Pilote la scene lobby (scenes/ui/lobby/lobby.tscn) — main menu du jeu.
##
## Phases :
## - JOIN : aucun joueur encore inscrit. Les manettes peuvent presser Start
##   pour rejoindre. Boutons menu invisibles tant que personne n'est joint.
## - MENU : 1+ joueur joint. 2 gros boutons (Niveau 1, Lancer le Run) +
##   dropdown level select + boutons secondaires (Leaderboard, Settings).
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
## Niveau du bouton "Tutoriel" : l'ancien niveau 1 (test_open_arena) sert
## maintenant de tutoriel — petite arène ouverte avec boss Golem, parfait
## pour apprendre tir / sort / combo / revive avant les niveaux complets.
const TUTORIAL_PATH := "res://scenes/levels/test_open_arena.tscn"
const MAX_PLAYERS: int = 4

## Liste des niveaux jouables via le bouton "Lancer le Run". Le dropdown se
## remplit dans cet ordre. Premier element = selection par defaut.
##
## Ajoutez une entree quand un nouveau niveau est pret. Le numero affiche
## sert juste de tag (le path est la source de verite).
const LEVELS: Array = [
	# Niveau 1 « Caverne Cristalline » — grande caverne continue FAITE MAIN, en
	# sélection par défaut. C'est la vitrine du POC : il sort de la pipeline
	# (cf docs/design/levels.md, décision A), qui reste la source des N2-N8.
	{"id": 1, "name": "N1 — Caverne Cristalline", "path": "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"},
	# Niveaux générés par la pipeline (tools/dungeon_pipeline/). Format .tres
	# consommé par DungeonBuilder.
	{"id": 11, "name": "N1 [GEN] Caverne crystalline", "path": "res://data/levels/level_1.tres"},
	{"id": 2, "name": "N2 [GEN] Marais toxique", "path": "res://data/levels/level_2.tres"},
	{"id": 3, "name": "N3 [GEN] Temple gravité réduite", "path": "res://data/levels/level_3.tres"},
	{"id": 4, "name": "N4 [GEN] Forge en fusion", "path": "res://data/levels/level_4.tres"},
	{"id": 5, "name": "N5 [GEN] Bibliothèque hantée", "path": "res://data/levels/level_5.tres"},
	{"id": 6, "name": "N6 [GEN] Montagne frozen", "path": "res://data/levels/level_6.tres"},
	{"id": 7, "name": "N7 [GEN] Labyrinthe miroirs", "path": "res://data/levels/level_7.tres"},
	{"id": 8, "name": "N8 [GEN] Vide cosmique", "path": "res://data/levels/level_8.tres"},
	# Anciens blockouts archivés (référence visuelle, ne seront pas testés).
	{"id": 101, "name": "N1 — Caverne crystalline [archive]", "path": "res://archive/levels/level_01_caverne/level_01_caverne.tscn"},
	{"id": 102, "name": "N2 — Marais toxique [archive]", "path": "res://archive/levels/level_02_marais/level_02_marais.tscn"},
	{"id": 103, "name": "N3 — Temple gravité réduite [archive]", "path": "res://archive/levels/level_03_temple/level_03_temple.tscn"},
	{"id": 104, "name": "N4 — Forge en fusion [archive]", "path": "res://archive/levels/level_04_forge/level_04_forge.tscn"},
	{"id": 105, "name": "N5 — Bibliothèque hantée [archive]", "path": "res://archive/levels/level_05_biblio/level_05_biblio.tscn"},
	{"id": 106, "name": "N6 — Montagne frozen [archive]", "path": "res://archive/levels/level_06_montagne/level_06_montagne.tscn"},
	{"id": 107, "name": "N7 — Labyrinthe miroirs [archive]", "path": "res://archive/levels/level_07_miroirs/level_07_miroirs.tscn"},
	{"id": 108, "name": "N8 — Vide cosmique [archive]", "path": "res://archive/levels/level_08_vide/level_08_vide.tscn"},
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
@onready var _btn_tuto: Button = %BtnTuto
@onready var _btn_run: Button = %BtnRun
@onready var _level_dropdown: OptionButton = %LevelDropdown
@onready var _btn_leaderboard: Button = %BtnLeaderboard
@onready var _btn_settings: Button = %BtnSettings

var _phase: Phase = Phase.JOIN


func _ready() -> void:
	PlayerManager.player_joined.connect(_on_player_joined)
	PlayerManager.player_left.connect(_on_player_left)
	PlayerManager.open_lobby()

	_btn_tuto.pressed.connect(_on_tuto_pressed)
	_btn_run.pressed.connect(_on_run_pressed)
	_btn_leaderboard.pressed.connect(_on_leaderboard_pressed)
	_btn_settings.pressed.connect(_on_settings_pressed)

	_populate_level_dropdown()
	_set_phase(Phase.JOIN)
	_refresh_status()


func _populate_level_dropdown() -> void:
	_level_dropdown.clear()
	for i in LEVELS.size():
		var lvl: Dictionary = LEVELS[i]
		_level_dropdown.add_item("%02d — %s" % [lvl.id, lvl.name], i)
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
		_btn_tuto.grab_focus()


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


func _on_tuto_pressed() -> void:
	# Bouton "Tutoriel" : lance test_open_arena (mini-arène + boss Golem).
	# Sert d'introduction aux mécaniques avant les 8 niveaux complets.
	_launch_level(TUTORIAL_PATH)


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

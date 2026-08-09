class_name CharacterSelect
extends Control

## L'écran de choix du personnage, au démarrage.
##
## ## Ce qu'il montre
##
## Un personnage à la fois, en grand, qui joue son `idle` et tourne lentement
## sur lui-même. On défile de gauche à droite avec le stick, la croix ou les
## gâchettes ; A valide.
##
## Un seul personnage visible plutôt qu'une grille : c'est une silhouette qu'on
## choisit, et une silhouette ne se juge pas en vignette. Le tourniquet lent
## sert à ça — voir la découpe de dos, qui est ce qu'on regardera pendant toute
## la partie en vue à la troisième personne.
##
## ## Ce qu'il dit aussi
##
## Le nombre d'animations que le personnage possède. Aucune n'est obligatoire :
## on peut jouer une silhouette qui n'a qu'un `idle`, elle sera juste moins
## expressive. Afficher le compte évite la fausse promesse — on sait ce qu'on
## prend.

signal validated()

const LOBBY_SCENE := "res://scenes/ui/lobby/lobby.tscn"

const TURNTABLE_SPEED: float = 0.35
const REPEAT_DELAY: float = 0.28

@onready var _name_label: Label = %NameLabel
@onready var _tagline_label: Label = %TaglineLabel
@onready var _states_label: Label = %StatesLabel
@onready var _hint_label: Label = %HintLabel
## Chemins explicites plutôt que noms uniques : le pivot vit dans un
## `SubViewport`, et la chaîne de propriété qui alimente `%Nom` s'y interrompt.
@onready var _pivot: Node3D = $Stage/Viewport/World/Pivot

var _visual: CharacterVisual
var _repeat_left: float = 0.0


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	CharacterRoster.selection_changed.connect(_on_selection_changed)
	_apply_theme()
	_show(CharacterRoster.current_index())


func _apply_theme() -> void:
	LobbyTheme.style_title(_name_label, "")
	LobbyTheme.style_subtitle(_tagline_label)
	LobbyTheme.style_subtitle(_states_label)
	LobbyTheme.style_subtitle(_hint_label)
	_hint_label.text = "◀ ▶ pour changer de personnage   —   A pour valider"


func _process(delta: float) -> void:
	# Le tourniquet. Lent : on veut lire une silhouette, pas la faire tournoyer.
	if _pivot != null:
		_pivot.rotate_y(TURNTABLE_SPEED * delta)

	if _repeat_left > 0.0:
		_repeat_left -= delta
		return

	# N'IMPORTE QUELLE MANETTE peut défiler. Le choix se fait avant que les
	# joueurs aient un `player_id`, donc router par device n'aurait aucun sens
	# ici — c'est l'une des rares surfaces du jeu où c'est légitime.
	var step: int = 0
	if Input.is_action_pressed(&"ui_right"):
		step = 1
	elif Input.is_action_pressed(&"ui_left"):
		step = -1
	if step != 0:
		CharacterRoster.step(step)
		_repeat_left = REPEAT_DELAY
		return

	if Input.is_action_just_pressed(&"ui_accept"):
		validated.emit()
		get_tree().change_scene_to_file(LOBBY_SCENE)


func _on_selection_changed(index: int) -> void:
	_show(index)


func _show(index: int) -> void:
	var entry: Dictionary = CharacterRoster.entry(index)
	if entry.is_empty():
		return
	_name_label.text = entry["name"]
	_tagline_label.text = entry["tagline"]

	var set_data: CharacterAnimSet = load(entry["set"]) as CharacterAnimSet
	if set_data == null:
		_states_label.text = "pack introuvable"
		return

	var states: Array[StringName] = set_data.available_states()
	_states_label.text = "%d animations" % states.size()

	# Le visuel est RECONSTRUIT et non réutilisé : `set_anim_set` reconstruit
	# déjà tout, mais garder l'ancien nœud laisserait le squelette précédent
	# dans la scène quand les deux packs n'ont pas le même rig.
	if _visual != null and is_instance_valid(_visual):
		_visual.queue_free()
	_visual = CharacterVisual.new()
	_visual.name = "Apercu"
	_visual.anim_set = set_data
	_pivot.add_child(_visual)
	_pivot.rotation.y = 0.0

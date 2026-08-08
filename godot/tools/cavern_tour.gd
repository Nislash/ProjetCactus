extends Node3D

## Tour guidé de la caverne, pour capture d'écran (E3).
##
## Lancer la scène `tools/cavern_tour.tscn` depuis l'éditeur. La caméra
## s'arrête à chaque point de vue pendant [member seconds_per_stop], avec le
## nom du point et un compte à rebours affichés à l'écran — de quoi se
## synchroniser pour capturer sans deviner ce qu'on regarde.
##
## Les points de vue reprennent les sightlines de la spec créative
## (`docs/design/level01_topography.md` §5) : ce sont EXACTEMENT les cadrages
## que le niveau est censé produire. S'ils ne fonctionnent pas ici, c'est la
## topographie qu'il faut corriger, pas la caméra.
##
## Les altitudes de l'œil sont calées sur le sol réellement généré, +1,6 m
## (hauteur de regard du joueur).

const CAVERN_SCENE := "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"

## Durée d'arrêt sur chaque point de vue, en secondes.
@export var seconds_per_stop: float = 12.0

## Les arrêts, dans l'ordre. `from` = position de l'œil, `look` = cible visée.
const STOPS: Array = [
	{
		"title": "1/8 — VUE D'ENSEMBLE (aérienne)",
		"note": "La caverne entière : loot à gauche, lac au centre, salle du boss à droite",
		"from": Vector3(-40.0, 96.0, 130.0), "look": Vector3(0.0, 0.0, -10.0),
	},
	{
		"title": "2/8 — Spawn (ouest de la Grande Nef)",
		"note": "Ce que les joueurs voient à la 1re seconde",
		"from": Vector3(-104.0, 9.6, -38.0), "look": Vector3(-20.0, 4.0, -30.0),
	},
	{
		"title": "3/8 — La Grande Nef (vers l'est)",
		"note": "La longue traversée : 200 m d'ouest en est",
		"from": Vector3(-60.0, 7.5, -36.0), "look": Vector3(40.0, 4.0, -40.0),
	},
	{
		"title": "4/8 — Le Lac Gelé",
		"note": "La nappe de glace et le grand puits de plafond au-dessus",
		"from": Vector3(-6.0, 1.0, -6.0), "look": Vector3(-6.0, -1.0, 40.0),
	},
	{
		"title": "5/8 — Le Lac (regard vers la voûte)",
		"note": "Le puits de plafond à contour libre doit se lire",
		"from": Vector3(-6.0, 0.6, 44.0), "look": Vector3(-2.0, 14.0, 32.0),
	},
	{
		"title": "6/8 — La Poche du Loot (ouest)",
		"note": "L'alcôve perchée au bout du boyau étroit",
		"from": Vector3(-104.0, 8.0, 6.0), "look": Vector3(-130.0, 9.0, 6.0),
	},
	{
		"title": "7/8 — LA RÉVÉLATION (crête du seuil)",
		"note": "Compression du goulet, puis ouverture sur le bol de l'arène",
		"from": Vector3(46.0, 8.2, -47.0), "look": Vector3(100.0, -3.0, -52.0),
	},
	{
		"title": "8/8 — Fond de l'arène (regard vers la crête)",
		"note": "Le contrechamp, une fois descendu dans le bol",
		"from": Vector3(100.0, -1.5, -52.0), "look": Vector3(30.0, 10.0, -46.0),
	},
]

var _camera: Camera3D
var _title_label: Label
var _note_label: Label
var _countdown_label: Label
var _index: int = 0
var _remaining: float = 0.0


## Fige le tour sur un seul arrêt (index 0-8), pour comparer deux réglages sur
## un cadrage strictement identique. -1 = tour complet.
##
## Exporté plutôt que passé en ligne de commande : les captures MCP passent par
## l'ÉDITEUR, qui lance sa propre instance sans nos arguments. Comparer des
## captures d'un processus lancé à la main revient à comparer des images qui
## n'ont jamais reçu les changements — piège rencontré en diagnostiquant.
@export var frozen_stop: int = -1


func _ready() -> void:
	var _cli_stop: int = frozen_stop
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--stop="):
			_cli_stop = int(arg.trim_prefix("--stop="))
	frozen_stop = _cli_stop

	var cavern: Node = (load(CAVERN_SCENE) as PackedScene).instantiate()
	add_child(cavern)

	_camera = Camera3D.new()
	_camera.current = true
	# Champ large : on montre des volumes, pas des détails.
	_camera.fov = 75.0
	_camera.far = 300.0
	add_child(_camera)

	_build_overlay()
	if frozen_stop >= 0:
		_goto(clampi(frozen_stop, 0, STOPS.size() - 1))
		set_process(false)
		return
	_goto(0)


func _process(delta: float) -> void:
	_remaining -= delta
	_countdown_label.text = "capture — %0.1f s" % maxf(_remaining, 0.0)
	if _remaining <= 0.0:
		_index += 1
		if _index >= STOPS.size():
			_title_label.text = "TOUR TERMINÉ"
			_note_label.text = "Tu peux fermer la fenêtre."
			_countdown_label.text = ""
			set_process(false)
			return
		_goto(_index)


func _goto(index: int) -> void:
	var stop: Dictionary = STOPS[index]
	_camera.global_transform = Transform3D(Basis(), stop.from)
	_camera.look_at(stop.look, Vector3.UP)
	_title_label.text = stop.title
	_note_label.text = stop.note
	_remaining = seconds_per_stop
	# Doublé dans la console : utile si l'overlay gêne le cadrage.
	print("[tour] %s — %s" % [stop.title, stop.note])


## Bandeau minimal en haut de l'écran : titre, note, compte à rebours. Assez
## sobre pour ne pas manger le cadrage qu'on cherche justement à juger.
func _build_overlay() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var panel := PanelContainer.new()
	panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	panel.modulate = Color(1.0, 1.0, 1.0, 0.85)
	layer.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override(&"separation", 2)
	panel.add_child(box)

	_title_label = Label.new()
	_title_label.add_theme_font_size_override(&"font_size", 26)
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title_label)

	_note_label = Label.new()
	_note_label.add_theme_font_size_override(&"font_size", 15)
	_note_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_note_label)

	_countdown_label = Label.new()
	_countdown_label.add_theme_font_size_override(&"font_size", 15)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_countdown_label)

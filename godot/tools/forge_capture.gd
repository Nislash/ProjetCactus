extends Node3D

## Capture quelques cadrages de la Forge et quitte. Lancer via :
##   godot --path godot --resolution 1600x900 tools/forge_capture.tscn
##
## Ce banc existe parce que le tour guidé de la caverne demande un humain
## devant l'écran : il s'arrête douze secondes par point de vue et compte sur
## quelqu'un pour capturer au bon moment. Pour juger une MATIÈRE, il faut au
## contraire pouvoir refaire exactement les mêmes cadrages après chaque
## réglage — donc un banc qui enregistre tout seul.
##
## Il ne tourne PAS en `--headless` : le serveur d'affichage factice ne rend
## rien, et la capture serait noire. C'est le seul outil du projet dans ce cas.

const FORGE_SCENE := "res://scenes/levels/level_02_forge/level_02_forge.tscn"
const OUT_DIR := "user://forge_capture"

## Les cadrages. `from` = œil, `look` = cible.
const SHOTS: Array = [
	{
		"name": "01_vue_aerienne_du_sentier",
		"from": Vector3(30.0, 96.0, 70.0), "look": Vector3(-46.0, 16.0, 16.0),
	},
	{
		"name": "02_le_saut_et_le_levier",
		"from": Vector3(-30.0, 44.0, 6.0), "look": Vector3(-58.0, 26.0, -22.0),
	},
]

## Tirer le levier avant de capturer, pour voir la rampe déployée.
@export var pull_lever: bool = true

## Frames d'attente avant la première capture : le terrain, le château et le
## pont se bâtissent chacun sur plusieurs frames.
@export var warmup_frames: int = 90

## Frames entre deux cadrages, le temps que l'exposition et le brouillard
## volumétrique se stabilisent.
@export var settle_frames: int = 12

var _camera: Camera3D


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT_DIR))

	var packed: PackedScene = load(FORGE_SCENE) as PackedScene
	if packed == null:
		push_error("ForgeCapture : scène introuvable.")
		get_tree().quit(1)
		return
	add_child(packed.instantiate())

	_camera = Camera3D.new()
	_camera.fov = 70.0
	_camera.far = 900.0
	add_child(_camera)
	_camera.current = true

	_run.call_deferred()


func _run() -> void:
	for i in warmup_frames:
		await get_tree().process_frame

	if pull_lever:
		var lever: Node = find_child("LevierCache", true, false)
		if lever != null:
			lever.call("try_interact", null)
			# Le déploiement dure environ deux secondes, en temps réel.
			await get_tree().create_timer(3.2).timeout

	for shot in SHOTS:
		_camera.global_position = shot["from"]
		_camera.look_at(shot["look"], Vector3.UP)
		for i in settle_frames:
			await get_tree().process_frame
		# Deux frames de plus APRÈS le déplacement : la caméra bouge, mais le
		# rendu de la frame courante a déjà été soumis avec l'ancienne matrice.
		await RenderingServer.frame_post_draw
		var image: Image = get_viewport().get_texture().get_image()
		var path: String = ProjectSettings.globalize_path(
			"%s/%s.png" % [OUT_DIR, shot["name"]])
		image.save_png(path)
		print("[ForgeCapture] %s" % path)

	get_tree().quit(0)

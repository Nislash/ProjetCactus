extends Node3D

## Banc de visualisation du Boss Golem — pour juger l'habillage à l'œil.
##
## Lancer la scène `res://tools/golem_preview.tscn`. Le Golem tourne
## lentement sur lui-même, et `phase` permet de comparer les trois états :
## P1 veines cyan, P2 tiède, P3 veines orange + éclat de poitrine visible.
##
## Ce banc existe parce qu'un test automatique prouve que la valeur est
## arrivée dans le matériau, pas qu'elle rend bien.

const ENVIRONMENT_PATH := "res://data/levels/level01_cavern_environment.tres"

## 1 = P1, 3 = P2, 5 = P3 enrage (valeurs de BossBase.Phase).
@export_enum("P1:1", "P2:3", "P3 enrage:5") var phase: int = 1

## Vitesse de rotation du présentoir (deg/s). 0 = figé, pour une capture.
@export var turntable_speed: float = 18.0

@onready var _golem: Node3D = $Golem


## Cadrage et lumière posés ICI, pas dans la scène.
##
## Les tools d'édition MCP acceptent bien un Vector3 ou une Color et
## rapportent l'écriture comme réussie, mais ne la persistent pas dans le
## `.tscn` : la caméra restait à l'origine — donc à l'intérieur du Golem — et
## la lumière avait viré au noir. Le script est le seul endroit fiable.
func _frame_the_subject() -> void:
	var cam: Camera3D = $Camera3D as Camera3D
	if cam != null:
		cam.position = Vector3(0.0, 3.6, 13.0)
		cam.rotation_degrees = Vector3(-7.0, 0.0, 0.0)
		cam.fov = 50.0
		cam.current = true
	var key: DirectionalLight3D = $KeyLight as DirectionalLight3D
	if key != null:
		key.position = Vector3(0.0, 10.0, 6.0)
		key.rotation_degrees = Vector3(-38.0, 24.0, 0.0)
		key.light_color = Color(0.81, 0.89, 0.95)
		key.light_energy = 1.1


func _ready() -> void:
	_frame_the_subject()

	var env_res: Environment = load(ENVIRONMENT_PATH) as Environment
	var we: WorldEnvironment = $WorldEnvironment as WorldEnvironment
	if env_res != null and we != null:
		# Chargé par chemin depuis le script : l'assignation d'une propriété
		# typée Resource depuis l'extérieur ne prend pas.
		# Copie, et brume coupée : celle de la caverne est calibrée pour
		# masquer à 15-25 m, elle avalerait le sujet.
		var env: Environment = env_res.duplicate() as Environment
		env.fog_enabled = false
		env.volumetric_fog_enabled = false
		we.environment = env
	else:
		push_warning("GolemPreview : environnement introuvable — fond par défaut.")

	# Le Golem est un CharacterBody3D : sans sol sous lui, il tombe hors du
	# cadre en une seconde. Et son IA chercherait des joueurs qui n'existent
	# pas. On fige les deux — c'est un présentoir, pas un combat.
	if _golem != null:
		_golem.set_physics_process(false)
		var ai: Node = _golem.get_node_or_null(^"BossAI")
		if ai != null:
			ai.set_physics_process(false)

	# Une frame pour laisser le Golem s'habiller, puis on pose la phase.
	await get_tree().process_frame
	if _golem != null and _golem.has_method("_set_phase"):
		_golem.call("_set_phase", phase)


func _process(delta: float) -> void:
	if _golem != null and turntable_speed != 0.0:
		_golem.rotate_y(deg_to_rad(turntable_speed) * delta)

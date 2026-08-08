extends Node3D

## Banc de vérification d'une colonne lettrée : le fût, son cartouche et sa
## gravure, vus depuis la rive.
##
## Le tour guidé de la caverne regarde vers la voûte au niveau du lac, donc il
## ne montre jamais une colonne de face — et c'est précisément ce qu'il fallait
## juger : la lettre était posée sur l'AXE du poteau, donc enfermée dans la
## pierre, et rien dans les captures existantes ne pouvait le révéler.

## 0 par défaut : la capture arrive une à deux secondes après le lancement,
## donc un présentoir qui tourne présente presque toujours la lettre de profil
## — exactement ce qu'on ne cherche pas à vérifier.
@export var turntable_speed: float = 0.0
@export var letter: String = "B"

var _column: Node3D


func _ready() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.13, 0.22, 0.33)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.42, 0.55, 0.70)
	env.ambient_light_energy = 1.1
	env.ambient_light_sky_contribution = 0.0
	env.glow_enabled = true
	env.glow_intensity = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-30.0, 35.0, 0.0)
	key.light_energy = 1.2
	add_child(key)

	var cam := Camera3D.new()
	cam.position = Vector3(0.0, 3.2, 7.0)
	cam.rotation_degrees = Vector3(-4.0, 0.0, 0.0)
	cam.fov = 55.0
	cam.current = true
	add_child(cam)

	# Un fût aux cotes réelles de la colonnade.
	_column = Node3D.new()
	add_child(_column)
	var shaft := MeshInstance3D.new()
	shaft.name = "Mesh"
	var mesh := CylinderMesh.new()
	mesh.top_radius = 1.7
	mesh.bottom_radius = 2.6
	mesh.height = 16.0
	mesh.radial_segments = 9
	shaft.mesh = mesh
	var rock := StandardMaterial3D.new()
	rock.albedo_color = Color(0.10, 0.15, 0.22)
	rock.roughness = 0.9
	shaft.mesh = mesh
	shaft.material_override = rock
	shaft.position = Vector3(0.0, 8.0, 0.0)
	_column.add_child(shaft)

	var pylon := LetterPylon.new()
	pylon.letter = letter
	# Face à la caméra au départ : la rotation du présentoir fera le tour.
	pylon.glyph_angle_degrees = 0.0
	pylon.shaft_bottom_radius = mesh.bottom_radius
	pylon.shaft_top_radius = mesh.top_radius
	pylon.shaft_height = mesh.height
	_column.add_child(pylon)


func _process(delta: float) -> void:
	if _column != null:
		_column.rotate_y(deg_to_rad(turntable_speed) * delta)

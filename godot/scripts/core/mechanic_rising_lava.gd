class_name MechanicRisingLava
extends Node3D

## Mécanique de niveau : lave qui monte (N4 Forge). Un grand plan StaticBody3D
## remonte de start_y à end_y sur duration_sec. Tout joueur dont la position
## Y passe en-dessous de la surface de lave subit dégâts continus.
##
## Usage : instancier dans le level avec dimensions du plan adaptées au layout
## de la tour. La lave commence en bas et monte → force les joueurs à
## progresser verticalement.

@export var plane_size_xz: Vector2 = Vector2(80, 80)
@export var start_y: float = -10.0
@export var end_y: float = 30.0
@export var duration_sec: float = 360.0  # 6 minutes
@export var start_delay_sec: float = 90.0  # grace period avant montée
@export var damage_per_sec: int = 40
## Tick de dégâts (s). À 0.5s + 40 dmg/s = 20 dmg par tick.
@export var damage_tick_sec: float = 0.5

var _elapsed: float = 0.0
var _started: bool = false
var _last_damage_tick: float = 0.0
var _surface: MeshInstance3D
var _body: StaticBody3D


func _ready() -> void:
	# Crée le mesh + collision shape pour visualisation lave.
	_body = StaticBody3D.new()
	_body.name = "LavaBody"
	# Couche neutre : on n'arrête pas les joueurs/projectiles, c'est juste
	# une zone visuelle + damage. Les dégâts passent par la détection Y.
	_body.collision_layer = 0
	_body.collision_mask = 0
	add_child(_body)

	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(plane_size_xz.x, 0.3, plane_size_xz.y)
	shape.shape = box
	_body.add_child(shape)

	_surface = MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(plane_size_xz.x, 0.3, plane_size_xz.y)
	_surface.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.35, 0.05, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1, 1.0)
	mat.emission_energy_multiplier = 2.5
	_surface.material_override = mat
	_body.add_child(_surface)

	_body.position = Vector3(0, start_y, 0)


func _process(delta: float) -> void:
	if not _started:
		_elapsed += delta
		if _elapsed >= start_delay_sec:
			_started = true
			_elapsed = 0.0
		return

	_elapsed += delta
	var t: float = clamp(_elapsed / duration_sec, 0.0, 1.0)
	var y: float = lerp(start_y, end_y, t)
	_body.position.y = y

	# Damage tick : tout joueur sous la surface prend des dégâts.
	_last_damage_tick += delta
	if _last_damage_tick >= damage_tick_sec:
		_last_damage_tick = 0.0
		var dmg: int = int(damage_per_sec * damage_tick_sec)
		for p in get_tree().get_nodes_in_group(&"players"):
			if not (p is PlayerController):
				continue
			var player: PlayerController = p
			if player.global_position.y < y:
				var health = player.get_node_or_null("Health")
				if health != null and health.has_method("take_damage"):
					health.take_damage(dmg, self)

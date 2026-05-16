class_name BossRelicDrop
extends Area3D

## Drop de relique légendaire à la mort du boss. Lueur dorée pulsante,
## premier player qui entre dans l'Area3D ramasse la relique.

@export var pulse_speed: float = 2.5
@export var pulse_amplitude: float = 0.4

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $GoldLight

var _relic: RelicData
var _picked: bool = false
var _phase: float = 0.0


func _ready() -> void:
	body_entered.connect(_on_body_entered)


func set_relic(data: RelicData) -> void:
	_relic = data


func get_relic() -> RelicData:
	return _relic


func _process(delta: float) -> void:
	if _picked:
		return
	# Pulse lumineuse + scale légère.
	_phase += delta * pulse_speed
	var pulse: float = 1.0 + sin(_phase) * pulse_amplitude
	if _mesh != null:
		_mesh.scale = Vector3.ONE * pulse
		# Rotation lente pour l'effet "items dans le coffre du run".
		_mesh.rotate_y(delta * 1.5)
	if _light != null:
		_light.light_energy = 2.0 + sin(_phase) * 0.8


func _on_body_entered(body: Node) -> void:
	if _picked or not (body is PlayerController):
		return
	var p: PlayerController = body
	if p.relic_inventory == null:
		return
	if _relic == null:
		_picked = true
		queue_free()
		return
	# Ramassage = ajout direct à l'inventaire du player qui touche en 1er.
	if p.relic_inventory.is_full():
		# Inventaire plein : on laisse le drop posé, retry plus tard.
		return
	if p.relic_inventory.try_add(_relic):
		_picked = true
		queue_free()

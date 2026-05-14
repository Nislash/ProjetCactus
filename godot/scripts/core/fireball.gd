extends Area3D

## Projectile boule de feu du combo Pistolet × Feu (#17).
##
## Spawn par WeaponHitscan en mode combo. Vole en ligne droite, applique
## damage + burn au premier HealthComponent touché, puis se queue_free.
## Auto-destruction après `lifetime_max` même si rien n'est touché.

@export var speed: float = 30.0
@export var damage: int = 12
@export var burn_duration: float = 3.0
@export var burn_dps: float = 5.0
@export var lifetime_max: float = 2.0
## Couleur du projectile + trail (héritée de ComboData.override_element_color
## ou SpellData.element_color en M2).
@export var element_color: Color = Color(1.0, 0.4, 0.15, 1.0)
## Son joué au _ready (lancement). Si null, pas de son.
## Format recommandé : .wav (qualité brute, court) à mettre dans
## `godot/assets/audio/sfx/fireball_launch.wav` puis assigner ici via inspector.
@export var launch_sound: AudioStream

var owner_body: Node = null
var direction: Vector3 = Vector3.FORWARD

var _life_left: float = 0.0
var _has_hit: bool = false


func _ready() -> void:
	_life_left = lifetime_max
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	# Joue le son de lancement si défini.
	var sfx: AudioStreamPlayer3D = get_node_or_null(^"LaunchSfx") as AudioStreamPlayer3D
	if sfx != null and launch_sound != null:
		sfx.stream = launch_sound
		sfx.play()


## Setup à l'instanciation. Si `owner_to_exclude` est set, on ignore les
## collisions avec lui (le tireur).
func setup(start_pos: Vector3, dir: Vector3, owner_to_exclude: Node = null) -> void:
	global_position = start_pos
	direction = dir.normalized()
	owner_body = owner_to_exclude


func _physics_process(delta: float) -> void:
	if _has_hit:
		return
	_life_left -= delta
	if _life_left <= 0.0:
		queue_free()
		return
	global_position += direction * speed * delta


func _on_body_entered(body: Node) -> void:
	if body == owner_body or _has_hit:
		return
	_apply_hit(body)


func _on_area_entered(_area: Area3D) -> void:
	# Évite les double-hits si on touche un Area3D enfant d'un body.
	pass


func _apply_hit(body: Node) -> void:
	_has_hit = true
	var hc: HealthComponent = _find_health_component(body)
	if hc != null:
		hc.take_damage(damage, owner_body)
		hc.apply_burn(burn_duration, burn_dps, owner_body)
	queue_free()


func _find_health_component(node: Node) -> HealthComponent:
	var current: Node = node
	while current != null:
		for child in current.get_children():
			if child is HealthComponent:
				return child as HealthComponent
		current = current.get_parent()
	return null

class_name EnemyBase
extends CharacterBody3D

## Base class pour tous les ennemis. Gère HP via HealthComponent, gravité,
## et la détection du joueur le plus proche. Les sous-classes (melee, ranged)
## implémentent leur IA dans _enemy_tick() — appelé chaque physics frame.

signal damaged(amount: int, source: Node)
signal killed(source: Node)

@export var gravity: float = 20.0
@export var move_speed: float = 4.0
@export var acceleration: float = 30.0
@export var friction: float = 40.0
## Distance au-delà de laquelle on ignore le joueur (perf).
@export var aggro_range: float = 40.0

@onready var _health: HealthComponent = $Health


func _ready() -> void:
	_health.died.connect(_on_died)
	_health.damaged.connect(func(amount, source): damaged.emit(amount, source))


func get_health() -> HealthComponent:
	return _health


func _physics_process(delta: float) -> void:
	if _health.is_dead:
		return

	if not is_on_floor():
		velocity.y -= gravity * delta

	_enemy_tick(delta)
	move_and_slide()


## À surcharger dans les sous-classes pour l'IA.
func _enemy_tick(_delta: float) -> void:
	pass


## Cherche le PlayerController le plus proche dans aggro_range. Retourne null
## si aucun joueur valide en vue.
func _find_closest_player() -> PlayerController:
	var best: PlayerController = null
	var best_dist: float = aggro_range * aggro_range
	for node in get_tree().get_nodes_in_group("players"):
		if not (node is PlayerController):
			continue
		var p: PlayerController = node
		if p.get_health().is_dead:
			continue
		var d: float = (p.global_position - global_position).length_squared()
		if d < best_dist:
			best_dist = d
			best = p
	return best


func _on_died(source: Node) -> void:
	killed.emit(source)
	# Pour M1, on free l'ennemi simplement. M2+ : drops/XP/death anim.
	queue_free()


func _apply_horizontal_velocity(target_dir: Vector3, delta: float) -> void:
	# Helper pour les sous-classes : tend la vélocité horizontale vers
	# target_dir * move_speed (ou ralentit si target_dir est zéro).
	var horizontal: Vector2 = Vector2(velocity.x, velocity.z)
	if target_dir.length() > 0.01:
		var t: Vector2 = Vector2(target_dir.x, target_dir.z).normalized() * move_speed
		horizontal = horizontal.move_toward(t, acceleration * delta)
	else:
		horizontal = horizontal.move_toward(Vector2.ZERO, friction * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.y

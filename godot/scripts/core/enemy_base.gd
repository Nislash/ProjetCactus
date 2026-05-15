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
## Distance d'aggro : tant qu'aucun joueur n'est dans ce rayon, l'ennemi
## reste idle (immobile, n'attaque pas). Dès qu'un joueur entre, il devient
## actif. Combine perf + comportement classique "patrouille zone".
@export var aggro_range: float = 12.0

@onready var _health: HealthComponent = $Health
@onready var _mesh: MeshInstance3D = $Mesh

var _original_material: Material = null
## Cache des materials feedback par status_id, créés au _ready.
var _status_materials: Dictionary = {}
## Pile des status visuels actifs (par ordre d'application). Le HUD du
## mesh affiche le dernier appliqué. Quand il s'éteint, on retombe sur
## le précédent (ou _original_material si vide).
var _active_status_visuals: Array = []


func _ready() -> void:
	# Permet aux orbes (chain foudre, AoE futur) de retrouver les ennemis.
	add_to_group(&"enemies")

	_health.died.connect(_on_died)
	_health.damaged.connect(func(amount, source): damaged.emit(amount, source))
	# StatusComponent expose des signaux génériques (burn, slow, freeze,
	# poison, stun…). On les écoute pour le feedback visuel.
	var status: StatusComponent = _health.get_status()
	if status != null:
		status.status_started.connect(_on_status_started)
		status.status_ended.connect(_on_status_ended)
	if _mesh != null:
		_original_material = _mesh.material_override
		_status_materials[StatusComponent.BURN] = _make_status_mat(Color(1.0, 0.35, 0.1, 1.0))
		_status_materials[StatusComponent.SLOW] = _make_status_mat(Color(0.4, 0.75, 1.0, 1.0))
		_status_materials[StatusComponent.FREEZE] = _make_status_mat(Color(0.65, 0.9, 1.0, 1.0))
		_status_materials[StatusComponent.POISON] = _make_status_mat(Color(0.45, 0.95, 0.4, 1.0))
		_status_materials[StatusComponent.STUN] = _make_status_mat(Color(1.0, 0.95, 0.3, 1.0))

	# Jauge HP 3D billboard (optionnelle, attachée dans la scène fille).
	var hbar: HealthBar3D = get_node_or_null(^"HealthBar3D") as HealthBar3D
	if hbar != null:
		hbar.bind_to(_health)


func _make_status_mat(color: Color) -> StandardMaterial3D:
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 2.5
	return mat


func _on_status_started(id: StringName, _duration: float, _magnitude: float, _source: Node) -> void:
	if _mesh == null or not _status_materials.has(id):
		return
	# Si déjà dans la pile (re-application), on ne re-pousse pas.
	if not _active_status_visuals.has(id):
		_active_status_visuals.append(id)
	_mesh.material_override = _status_materials[id]


func _on_status_ended(id: StringName) -> void:
	_active_status_visuals.erase(id)
	if _mesh == null:
		return
	if _active_status_visuals.is_empty():
		_mesh.material_override = _original_material
	else:
		# Retombe sur le status visuel le plus récent encore actif.
		var top: StringName = _active_status_visuals[_active_status_visuals.size() - 1]
		_mesh.material_override = _status_materials[top]


## Multiplicateur de vitesse selon les status actifs. 0 si freeze ou stun
## (immobile), 0.4 si slow (ralenti), 1.0 sinon. Lu par les sous-classes
## (enemy_melee, enemy_ranged) pour piloter leur speed.
func get_speed_multiplier() -> float:
	var status: StatusComponent = _health.get_status()
	if status == null:
		return 1.0
	if status.has_status(StatusComponent.FREEZE) or status.has_status(StatusComponent.STUN):
		return 0.0
	if status.has_status(StatusComponent.SLOW):
		return 0.4
	return 1.0


## True si l'ennemi peut attaquer. Bloqué par freeze et stun.
func can_act() -> bool:
	var status: StatusComponent = _health.get_status()
	if status == null:
		return true
	return not (status.has_status(StatusComponent.FREEZE) or status.has_status(StatusComponent.STUN))


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

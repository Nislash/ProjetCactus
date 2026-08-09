class_name CharacterAnimator
extends Node

## Pilote un CharacterVisual à partir de l'état d'un CharacterBody3D parent
## (player, mob, boss). Logique simple : on lit `velocity` et quelques flags
## et on choisit l'état d'animation. Surchargeable via override_state.
##
## Branchement :
##   Parent (CharacterBody3D)
##     ├─ Visual (CharacterVisual node + script)
##     └─ Animator (ce script, pointant visual_path vers ../Visual)
##
## Pour des entités sans CharacterBody3D parent (futur), passe par
## set_velocity() / set_state_override() manuellement.

@export_node_path("Node3D") var visual_path: NodePath = ^"../Visual"
## Vitesse à partir de laquelle on bascule de idle à walk.
@export var walk_threshold: float = 0.4
## Vitesse à partir de laquelle on bascule de walk à run.
@export var run_threshold: float = 5.5
## Si true, on lit `velocity` du parent (CharacterBody3D). Sinon, on attend
## que quelqu'un appelle set_velocity().
@export var auto_read_parent_velocity: bool = true
## Si true et que le parent expose `is_shooting()` / `is_meleeing()`, on
## bascule sur shoot_walk_* / melee_combo.
@export var auto_read_combat_state: bool = true
## Si true et que le parent a une méthode `is_dead()` ou expose un Health
## en _health, joue death à la mort (one-shot puis fige).
@export var auto_play_death: bool = true
## Pivot caméra pour distinguer marche avant / arrière (pour shoot_walk_*).
## Si vide, on calcule avant/arrière via la basis du parent.
@export_node_path("Node3D") var aim_pivot_path: NodePath

var _visual: CharacterVisual = null
var _parent: Node3D = null
var _aim_pivot: Node3D = null
var _override_state: StringName = &""
var _override_oneshot: bool = false
var _last_external_velocity: Vector3 = Vector3.ZERO
var _is_dead: bool = false
var _is_shooting_flag: bool = false
var _is_meleeing_flag: bool = false


func _ready() -> void:
	_visual = get_node_or_null(visual_path) as CharacterVisual
	_parent = get_parent() as Node3D
	if aim_pivot_path != NodePath(""):
		_aim_pivot = get_node_or_null(aim_pivot_path) as Node3D
	if _visual != null:
		_visual.animation_finished.connect(_on_anim_finished)
	# Auto-connect death. Player → on s'abonne à `downed` (le player passe en
	# DOWNED quand HP=0, pas en vraie mort). Mob/boss → on écoute Health.died.
	if auto_play_death and _parent != null:
		if _parent.has_signal(&"downed"):
			_parent.connect(&"downed", notify_death)
			if _parent.has_signal(&"revived"):
				_parent.connect(&"revived", _on_revived)
		else:
			var health: Node = _parent.get_node_or_null(^"Health")
			if health != null and health.has_signal(&"died"):
				health.died.connect(_on_health_died)


func _on_health_died(_source: Node) -> void:
	notify_death()


func _on_revived() -> void:
	_is_dead = false
	_override_state = &""
	_override_oneshot = false


func _process(_delta: float) -> void:
	if _visual == null:
		return
	if _override_state != &"":
		return  # respecte l'override jusqu'à fin de l'oneshot
	_visual.play_state(_pick_state())


## Joue immédiatement un état one-shot (death, melee_combo, jump). Revient
## à l'auto-pick quand fini, sauf pour death.
func play_oneshot(state: StringName) -> void:
	if _visual == null:
		return
	_override_state = state
	_override_oneshot = true
	_visual.play_oneshot(state)


## Force un état permanent (override auto). Passe state=&"" pour rendre la
## main à l'auto-pick.
func set_state_override(state: StringName) -> void:
	_override_state = state
	_override_oneshot = false
	if _visual != null:
		if state == &"":
			_visual.play_state(_pick_state())
		else:
			_visual.play_state(state)


func set_velocity(v: Vector3) -> void:
	_last_external_velocity = v


func set_shooting(on: bool) -> void:
	_is_shooting_flag = on


func set_meleeing(on: bool) -> void:
	_is_meleeing_flag = on


func notify_death() -> void:
	if _is_dead:
		return
	_is_dead = true
	if auto_play_death and _visual != null and _visual.has_state(&"death"):
		_override_state = &"death"
		_override_oneshot = false  # on reste en pose death
		_visual.play_oneshot(&"death")


## LE CORPS SUIT LA VISÉE, PAS LE DÉPLACEMENT.
##
## Le joueur tourne avec la caméra (`rotation.y = _yaw`) et se déplace en
## repère local : il va donc en pas chassés et à reculons en permanence, pas
## seulement en combat. Sans états directionnels, marcher en arrière joue une
## course avant — le moonwalk, visible tout le temps en vue à la troisième
## personne.
##
## On classe la direction en quatre quadrants plutôt qu'en huit : à la manette
## on tient rarement une diagonale franche, et le clip latéral le plus proche
## se lit très bien. Ce que le personnage n'a pas, `resolve_state` le remplace.
func _pick_state() -> StringName:
	if _is_dead:
		return &"death"

	var v: Vector3 = _read_velocity()
	var horizontal: Vector2 = Vector2(v.x, v.z)
	var speed: float = horizontal.length()
	var moving: bool = speed >= walk_threshold

	if _read_shooting():
		if not moving:
			return _resolve(&"shoot_idle")
		if _is_moving_backward(horizontal):
			return _resolve(&"shoot_walk_back")
		if speed >= run_threshold:
			return _resolve(&"shoot_run")
		return _resolve(&"shoot_walk_forward")

	if not moving:
		return _resolve(&"idle")

	var wanted: StringName = _directional_state(horizontal, speed >= run_threshold)
	return _resolve(wanted)


## L'état de locomotion correspondant à la direction du déplacement, exprimée
## dans le repère du personnage.
func _directional_state(horizontal: Vector2, running: bool) -> StringName:
	if _parent == null:
		return &"run" if running else &"walk"
	# Composantes avant et latérale, dans le repère du corps.
	var forward := Vector2(-_parent.global_transform.basis.z.x,
		-_parent.global_transform.basis.z.z).normalized()
	var side := Vector2(_parent.global_transform.basis.x.x,
		_parent.global_transform.basis.x.z).normalized()
	var direction: Vector2 = horizontal.normalized()
	var ahead: float = direction.dot(forward)
	var lateral: float = direction.dot(side)

	if ahead < -0.4:
		return &"run_back"
	if absf(lateral) > absf(ahead):
		return &"run_right" if lateral > 0.0 else &"run_left"
	if ahead > 0.4 and absf(lateral) > 0.35:
		return &"run_forward_right" if lateral > 0.0 else &"run_forward_left"
	return &"run" if running else &"walk"


## Passe par la table de repli du visuel : un personnage à qui il manque un
## clip doit rester jouable, pas se figer.
func _resolve(wanted: StringName) -> StringName:
	if _visual == null:
		return wanted
	var resolved: StringName = _visual.resolve_state(wanted)
	return resolved if resolved != &"" else &"idle"


func _read_velocity() -> Vector3:
	if auto_read_parent_velocity and _parent != null and _parent is CharacterBody3D:
		return (_parent as CharacterBody3D).velocity
	return _last_external_velocity


func _read_shooting() -> bool:
	if not auto_read_combat_state:
		return _is_shooting_flag
	if _is_shooting_flag:
		return true
	if _parent != null and _parent.has_method(&"is_shooting"):
		return _parent.call(&"is_shooting")
	return false


## Détecte si la vélocité horizontale pointe à l'opposé du forward du parent
## (ou de l'aim_pivot s'il est fourni). Utile pour les players FPS dont la
## caméra dicte le "avant".
func _is_moving_backward(horizontal: Vector2) -> bool:
	if _parent == null:
		return false
	var fwd_node: Node3D = _aim_pivot if _aim_pivot != null else _parent
	var fwd: Vector3 = -fwd_node.global_transform.basis.z
	var fwd_h: Vector2 = Vector2(fwd.x, fwd.z).normalized()
	return horizontal.normalized().dot(fwd_h) < -0.2


func _on_anim_finished(anim_name: StringName) -> void:
	if _override_state == anim_name and _override_oneshot:
		_override_state = &""
		_override_oneshot = false

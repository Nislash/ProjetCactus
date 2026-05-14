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
## Son joué au _ready (lancement). À mettre dans
## `godot/assets/audio/sfx/fireball_throw.mp3` (ou .wav).
@export var launch_sound: AudioStream
## Son joué à l'impact (mur ou cible). À mettre dans
## `godot/assets/audio/sfx/fireball_impact.mp3` (ou .wav).
@export var impact_sound: AudioStream

@export_group("Burn mark (impact mur)")
## Taille de la marque noire spawnée sur un mur (rate de tir).
@export var burn_mark_size: float = 1.5
## Durée du fade-out de la marque (secondes).
@export var burn_mark_duration: float = 3.0

var owner_body: Node = null
var direction: Vector3 = Vector3.FORWARD

var _life_left: float = 0.0
var _has_hit: bool = false


func _ready() -> void:
	_life_left = lifetime_max
	body_entered.connect(_on_body_entered)
	area_entered.connect(_on_area_entered)
	# Joue le son de lancement si défini.
	var sfx: AudioStreamPlayer = get_node_or_null(^"LaunchSfx") as AudioStreamPlayer
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

	# Détection par raycast entre la position actuelle et la suivante.
	# Évite le tunneling à haute vitesse (Area3D.body_entered peut manquer
	# l'overlap si on passe outre un body fin en 1 frame).
	var next_pos: Vector3 = global_position + direction * speed * delta
	var space_state := get_world_3d().direct_space_state
	var query := PhysicsRayQueryParameters3D.create(global_position, next_pos, 0xFFFFFFFF)
	if owner_body is CollisionObject3D:
		query.exclude = [(owner_body as CollisionObject3D).get_rid()]
	var result: Dictionary = space_state.intersect_ray(query)
	if not result.is_empty():
		global_position = result.get(&"position", next_pos)
		_apply_hit(result.get(&"collider", null) as Node, result.get(&"normal", -direction))
		return
	global_position = next_pos


func _on_body_entered(body: Node) -> void:
	# Fallback : si la fireball spawne directement dans un body (collision
	# à t=0 sans avoir eu le temps de raycast), on déclenche l'impact ici.
	if body == owner_body or _has_hit:
		return
	_apply_hit(body, -direction)


func _on_area_entered(_area: Area3D) -> void:
	# Évite les double-hits si on touche un Area3D enfant d'un body.
	pass


func _apply_hit(body: Node, surface_normal: Vector3 = Vector3.ZERO) -> void:
	_has_hit = true
	if body == null:
		_play_impact_sound()
		queue_free()
		return
	var hc: HealthComponent = _find_health_component(body)
	if hc != null:
		hc.take_damage(damage, owner_body)
		hc.apply_burn(burn_duration, burn_dps, owner_body)
	else:
		# Pas de HealthComponent → c'est un mur / obstacle statique.
		# On laisse une marque visuelle qui s'estompe.
		_spawn_burn_mark(surface_normal)
	_play_impact_sound()
	queue_free()


func _play_impact_sound() -> void:
	if impact_sound == null:
		return
	# AudioStreamPlayer (2D global, volume constant). Le 3D avait une
	# atténuation trop forte rendant les sons quasi inaudibles depuis le
	# point de vue du player. À revoir avec un vrai mix sonore en M2.
	var sfx: AudioStreamPlayer = AudioStreamPlayer.new()
	sfx.stream = impact_sound
	sfx.volume_db = 0.0
	get_tree().current_scene.add_child(sfx)
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


## Spawne un QuadMesh noir émissif à l'endroit de l'impact, orienté avec
## la normale de la surface touchée. Fade alpha + emission sur burn_mark_duration.
func _spawn_burn_mark(surface_normal: Vector3) -> void:
	var mark: MeshInstance3D = MeshInstance3D.new()
	var quad: QuadMesh = QuadMesh.new()
	quad.size = Vector2(burn_mark_size, burn_mark_size)
	mark.mesh = quad

	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.08, 0.05, 0.03, 0.92)
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.18, 0.05, 1)
	mat.emission_energy_multiplier = 0.6
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mark.material_override = mat

	get_tree().current_scene.add_child(mark)

	# Si on a une vraie normale (du raycast), on l'utilise pour orienter le
	# quad parfaitement plaqué contre la surface. Sinon fallback -direction.
	var normal: Vector3 = surface_normal.normalized() if surface_normal.length() > 0.01 else -direction.normalized()
	# Recule un poil le quad par rapport à la surface pour éviter le z-fighting.
	mark.global_position = global_position + normal * 0.02
	# Le quad doit avoir sa face avant orientée selon la normale (donc on
	# regarde dans la direction opposée à la normale).
	mark.look_at(mark.global_position - normal, Vector3.UP if abs(normal.y) < 0.95 else Vector3.FORWARD)

	var tween: Tween = get_tree().create_tween()
	tween.set_parallel(true)
	tween.tween_property(mat, "albedo_color:a", 0.0, burn_mark_duration)
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, burn_mark_duration)
	tween.chain().tween_callback(mark.queue_free)


func _find_health_component(node: Node) -> HealthComponent:
	var current: Node = node
	while current != null:
		for child in current.get_children():
			if child is HealthComponent:
				return child as HealthComponent
		current = current.get_parent()
	return null

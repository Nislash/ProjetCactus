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
	else:
		# Pas de HealthComponent → c'est un mur / obstacle statique.
		# On laisse une marque visuelle qui s'estompe.
		_spawn_burn_mark()
	_play_impact_sound()
	queue_free()


func _play_impact_sound() -> void:
	if impact_sound == null:
		return
	var sfx: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	sfx.stream = impact_sound
	sfx.unit_size = 12.0
	sfx.attenuation_filter_db = -12.0
	get_tree().current_scene.add_child(sfx)
	sfx.global_position = global_position
	sfx.play()
	sfx.finished.connect(sfx.queue_free)


## Spawne un QuadMesh noir émissif à l'endroit de l'impact, orienté face
## à la direction d'où vient le projectile (= contre le mur touché).
## L'opacité fade vers 0 sur `burn_mark_duration` puis queue_free.
func _spawn_burn_mark() -> void:
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
	# Recule un poil le quad par rapport au mur pour éviter le z-fighting.
	mark.global_position = global_position - direction.normalized() * 0.05
	# Oriente le quad face avant vers le sens du tir = plaqué contre le mur.
	mark.look_at(global_position + direction, Vector3.UP)

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

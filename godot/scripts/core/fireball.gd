extends Area3D

## Orbe magique générique. Spawn par WeaponHitscan en mode combo. Vole en
## ligne droite, applique damage + status configurable au premier
## HealthComponent touché, puis se queue_free. Auto-destruction après
## `lifetime_max` même si rien n'est touché.
##
## Variantes par élément (cf scenes/combos/) :
##   - fireball.tscn  : status_id="burn"   → DoT brûlure
##   - ice_orb.tscn   : status_id="freeze" → immobilise N secondes
##   - thunder_orb.tscn: status_id="stun" + chain → propage aux ennemis proches
##   - poison_orb.tscn: status_id="poison" → DoT empilable
##
## Le nom "Fireball" du class est conservé pour compat avec les .tscn
## existants. Conceptuellement c'est maintenant un MagicOrb générique.

@export var speed: float = 30.0
@export var damage: int = 12
@export var lifetime_max: float = 2.0
## Couleur du projectile + trail (héritée de ComboData.override_element_color
## ou SpellData.element_color en M2).
@export var element_color: Color = Color(1.0, 0.4, 0.15, 1.0)

@export_group("Status à l'impact")
## ID du status appliqué via StatusComponent. Ex : "burn", "freeze",
## "slow", "stun", "poison". Si vide ou status_duration<=0, aucun status
## n'est appliqué (juste damage).
@export var status_id: StringName = &"burn"
@export var status_duration: float = 3.0
## Magnitude du status. DPS pour les DoT (burn, poison), 1.0 indicateur
## pour les non-DoT (freeze, stun, slow).
@export var status_magnitude: float = 5.0

@export_group("Chain (foudre)")
## Nombre d'ennemis supplémentaires touchés par chain après l'impact
## initial. 0 = pas de chain (orbes feu/glace/poison). 2 = thunder.
@export var chain_targets: int = 0
@export var chain_radius: float = 6.0
## Damage appliqué au chain = damage * chain_damage_falloff^N (N = ordre).
@export var chain_damage_falloff: float = 0.7
## Couleur du visual lightning bolt entre 2 cibles.
@export var chain_visual_color: Color = Color(1, 0.95, 0.3, 1)
@export var chain_visual_duration: float = 0.25

# Compat avec ancien API : burn_duration/burn_dps shadow status_duration/magnitude
# si laissés à 0 dans des .tscn legacy. À retirer plus tard.
@export var burn_duration: float = 0.0
@export var burn_dps: float = 0.0
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
		_apply_status_to(hc)
		# Chain (foudre) : propage aux N ennemis les plus proches.
		if chain_targets > 0:
			_do_chain(body, global_position)
	else:
		# Pas de HealthComponent → c'est un mur / obstacle statique.
		# On laisse une marque visuelle qui s'estompe.
		_spawn_burn_mark(surface_normal)
	_play_impact_sound()
	queue_free()


## Applique le status configuré (ou apply_burn legacy si burn_dps>0 set
## dans un ancien .tscn).
func _apply_status_to(hc: HealthComponent) -> void:
	# Compat legacy : si burn_duration/burn_dps sont set, on applique
	# burn directement (chemin historique fireball.tscn avant refacto).
	if burn_duration > 0.0 and burn_dps > 0.0:
		hc.apply_burn(burn_duration, burn_dps, owner_body)
		return
	if status_duration > 0.0 and status_magnitude > 0.0 and status_id != &"":
		var status: StatusComponent = hc.get_status()
		if status != null:
			status.apply_status(status_id, status_duration, status_magnitude, owner_body)


## Chain foudre : trouve jusqu'à `chain_targets` ennemis du groupe
## "enemies" dans `chain_radius` autour de la cible initiale, applique
## damage (avec falloff) + status à chacun, et dessine un visual
## lightning bolt entre la cible précédente et la nouvelle.
func _do_chain(initial_target: Node, from_pos: Vector3) -> void:
	var hit_set: Array = [initial_target]
	var current_pos: Vector3 = from_pos
	var current_damage: float = float(damage) * chain_damage_falloff
	for i in chain_targets:
		var next: Node = _find_nearest_unhit_enemy(current_pos, hit_set)
		if next == null:
			break
		var next_node3d: Node3D = next as Node3D
		if next_node3d == null:
			break
		var next_hc: HealthComponent = _find_health_component(next)
		if next_hc != null:
			next_hc.take_damage(int(current_damage), owner_body)
			_apply_status_to(next_hc)
		_spawn_chain_visual(current_pos, next_node3d.global_position)
		hit_set.append(next)
		current_pos = next_node3d.global_position
		current_damage *= chain_damage_falloff


func _find_nearest_unhit_enemy(from_pos: Vector3, hit_set: Array) -> Node:
	var best: Node = null
	var best_dist: float = chain_radius * chain_radius
	for n in get_tree().get_nodes_in_group(&"enemies"):
		if hit_set.has(n) or not (n is Node3D):
			continue
		var d: float = (from_pos - (n as Node3D).global_position).length_squared()
		if d < best_dist:
			best_dist = d
			best = n
	return best


## Spawne un BoxMesh fin entre les 2 positions, jaune émissif, qui
## disparait après chain_visual_duration. Inspiré de WeaponHitscan.
func _spawn_chain_visual(from_pos: Vector3, to_pos: Vector3) -> void:
	var segment: Vector3 = to_pos - from_pos
	var length: float = segment.length()
	if length < 0.01:
		return
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(0.08, 0.08, length)
	mesh_instance.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = chain_visual_color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = chain_visual_color
	mat.emission_energy_multiplier = 4.0
	mesh_instance.material_override = mat
	get_tree().current_scene.add_child(mesh_instance)
	mesh_instance.global_position = (from_pos + to_pos) * 0.5
	mesh_instance.look_at(to_pos, Vector3.UP)
	var timer := get_tree().create_timer(chain_visual_duration)
	timer.timeout.connect(func() -> void:
		if is_instance_valid(mesh_instance):
			mesh_instance.queue_free()
	)


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

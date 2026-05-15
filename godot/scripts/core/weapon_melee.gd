class_name WeaponMelee
extends Node3D

## Arme corps a corps. Swing horizontal devant le joueur, hit detection via
## sphere overlap dans la zone d'attaque pendant la duree active du swing.
##
## Actuellement bind sur l'action `cast_spell` (LT) cote PlayerController, ce
## qui permet de l'utiliser en parallele du pistolet (RT). Cohabitation des
## 2 armes simultanees, pas de switch.
##
## Pas de munitions, pas de reload (illimitee). Cooldown entre swings via
## `fire_rate` (swings par seconde) lu depuis WeaponData.
##
## Hit detection : on collecte tous les CollisionObject3D dans le rayon
## `attack_radius` devant le joueur (`attack_distance` en avant), on filtre
## par presence d'un HealthComponent dans la chaine parente, on applique
## `damage` une seule fois par swing.

signal swung()
signal hit_landed(target: Node)
signal weapon_name_changed(new_name: String)

## Source de verite des stats. Si defini, ecrase les @export ci-dessous au
## _ready. Idem que WeaponHitscan.
@export var data: WeaponData

@export var base_weapon_name: String = "Epee"
@export var damage: int = 25
@export var fire_rate: float = 1.5  ## Swings par seconde
@export var attack_distance: float = 1.6
@export var attack_radius: float = 1.4
## Duree d'animation visuelle du swing (rotation rapide du blade).
@export var swing_duration: float = 0.25
## Fenetre temporelle dans le swing pendant laquelle le hit est actif.
## Centree sur le milieu : si swing_duration=0.25 et active_window=0.15,
## le hit est actif de 0.05s a 0.20s.
@export var active_window: float = 0.15
@export var collision_mask: int = 0xFFFFFFFF

## Node proprietaire (typiquement le player). Sert a exclure son propre
## collider et a transmettre `source` au HealthComponent qui recoit damage.
@export var owner_body: NodePath

@onready var _blade: Node3D = $Blade if has_node("Blade") else null

# Nom de la gemme équipée (vide = lame nue, ex: "Feu", "Glace"). Détermine
# le nom HUD : "Épée × Feu" si gemme, sinon "Épée". Set par equip_spell().
var equipped_spell_name: String = ""

var _cooldown_left: float = 0.0
var _swing_time_left: float = 0.0
var _hit_targets_this_swing: Array = []


func _ready() -> void:
	_apply_data()
	weapon_name_changed.emit(base_weapon_name)


func _apply_data() -> void:
	if data == null:
		return
	damage = data.damage_base
	fire_rate = data.fire_rate
	attack_distance = data.max_range
	if not data.weapon_name_display.is_empty():
		base_weapon_name = data.weapon_name_display


## Nom à afficher dans le HUD : "Épée" en base, "Épée × Glace" si une
## gemme est équipée.
func get_display_name() -> String:
	if equipped_spell_name.is_empty():
		return base_weapon_name
	return "%s × %s" % [base_weapon_name, equipped_spell_name]


## Équipe une gemme sur la lame. La melee ignore `projectile_scene`
## (pas de projectile distant). Pour le POC, l'effet gameplay du combo
## est implémenté en suivi (cette PR fait juste le tracking nom + HUD).
## Signature alignée avec WeaponHitscan.equip_spell pour que SpellPickup
## puisse appeler n'importe quelle arme indifféremment.
func equip_spell(spell_name: String, _projectile_scene: PackedScene) -> void:
	equipped_spell_name = spell_name
	weapon_name_changed.emit(get_display_name())


## Retire la gemme équipée.
func unequip_spell() -> void:
	equipped_spell_name = ""
	weapon_name_changed.emit(get_display_name())


func can_fire() -> bool:
	return _cooldown_left <= 0.0 and _swing_time_left <= 0.0


## Declenche un swing. Le hit detection s'applique pendant active_window
## centree dans swing_duration.
func swing() -> void:
	if not can_fire():
		return
	_cooldown_left = 1.0 / fire_rate
	_swing_time_left = swing_duration
	_hit_targets_this_swing.clear()
	swung.emit()


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	if _swing_time_left > 0.0:
		_swing_time_left -= delta
		_animate_swing()
		_check_hits()
	elif _blade != null and _blade.rotation.y != 0.0:
		_blade.rotation.y = 0.0


func _animate_swing() -> void:
	if _blade == null:
		return
	# Progression du swing : 0 (debut) -> 1 (fin)
	var progress: float = 1.0 - (_swing_time_left / swing_duration)
	# Rotation horizontale -60 a +60 deg, easing simple
	var angle_deg: float = lerp(-60.0, 60.0, progress)
	_blade.rotation.y = deg_to_rad(angle_deg)


func _check_hits() -> void:
	# Le hit est actif uniquement dans active_window centree dans swing.
	var elapsed: float = swing_duration - _swing_time_left
	var window_start: float = (swing_duration - active_window) * 0.5
	var window_end: float = window_start + active_window
	if elapsed < window_start or elapsed > window_end:
		return

	var space_state := get_world_3d().direct_space_state
	# Sphere check devant le joueur, projetee a `attack_distance` en -Z basis
	var origin: Vector3 = global_transform.origin
	var forward: Vector3 = -global_transform.basis.z.normalized()
	var center: Vector3 = origin + forward * attack_distance

	var query := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = attack_radius
	query.shape = shape
	query.transform = Transform3D(Basis.IDENTITY, center)
	query.collision_mask = collision_mask
	var owner_node: Node = get_node_or_null(owner_body)
	if owner_node is CollisionObject3D:
		query.exclude = [owner_node.get_rid()]

	var hits: Array = space_state.intersect_shape(query, 16)
	for hit in hits:
		var collider: Node = hit.get(&"collider", null)
		if collider == null or _hit_targets_this_swing.has(collider):
			continue
		var hc: HealthComponent = _find_health_component(collider)
		if hc == null:
			continue
		_hit_targets_this_swing.append(collider)
		hc.take_damage(damage, owner_node)
		hit_landed.emit(collider)


func _find_health_component(node: Node) -> HealthComponent:
	var current: Node = node
	while current != null:
		for child in current.get_children():
			if child is HealthComponent:
				return child as HealthComponent
		current = current.get_parent()
	return null

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
##
## Animation : l'arc de swing s'adapte à la gemme équipée via SWING_PROFILES.
## Chaque combo arme×gemme a sa propre courbe (Y/X/Z), durée, easing et
## couleur de lame — la signature visuelle du jeu (cf CLAUDE.md combos).

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
@onready var _blade_mesh: MeshInstance3D = $Blade/Mesh if has_node("Blade/Mesh") else null

# Nom de la gemme équipée (vide = lame nue, ex: "Feu", "Glace"). Détermine
# le nom HUD : "Épée × Feu" si gemme, sinon "Épée". Set par equip_spell().
var equipped_spell_name: String = ""

var _cooldown_left: float = 0.0
var _swing_time_left: float = 0.0
var _hit_targets_this_swing: Array = []

## Profil actif pendant le swing courant. Saisi à chaque appel à swing() pour
## que les changements de gemme en plein swing ne perturbent pas l'anim.
var _active_profile: Dictionary = {}
## Material duppliqué pour pouvoir overrider la couleur sans toucher l'asset.
var _blade_material: StandardMaterial3D = null
## Combien de "ghosts" (copies de la lame qui fade out) on a déjà émis pour
## le swing courant. On les espace dans le temps pour faire un trail simple.
var _ghosts_emitted: int = 0
const GHOSTS_PER_SWING: int = 6
const GHOST_LIFETIME_SEC: float = 0.18

# -----------------------------------------------------------------------------
# Profils de swing par élément. Chaque profil paramètre la trajectoire 3D du
# blade + sa couleur + la durée. La table de mapping élément → profil utilise
# `equipped_spell_name` tel que stocké côté arme (cf SpellPickup).
#
# Conventions :
# - Y est l'axe vertical (yaw), c'est le balayage horizontal principal
# - X est l'axe latéral (pitch), provoque un "dip" ou un "uppercut" mid-swing
# - Z est l'axe roll (rotation autour de l'avant), pour les coups circulaires
# - duration_mult : multiplie swing_duration (lent = >1, rapide = <1)
# - easing : type d'interpolation appliquée à la progression t∈[0,1]
# - blade_color : couleur albedo + base de l'emission (HDR si >1)
# - emission_energy : intensité du glow (passé à material.emission_energy_multiplier)
# -----------------------------------------------------------------------------
const SWING_PROFILES: Dictionary = {
	"": {  # Lame nue : balayage horizontal propre, rapide
		"arc_y_start_deg": -75.0,
		"arc_y_end_deg": 75.0,
		"arc_x_dip_deg": 18.0,
		"roll_z_deg": 0.0,
		"duration_mult": 1.0,
		"easing": "out_cubic",
		"blade_color": Color(0.85, 0.88, 0.95, 1.0),
		"emission_color": Color(0.6, 0.7, 0.85, 1.0),
		"emission_energy": 0.6,
	},
	"Feu": {  # Feu : coup lourd, large, overshoot, glow chaud
		"arc_y_start_deg": -95.0,
		"arc_y_end_deg": 105.0,
		"arc_x_dip_deg": 28.0,
		"roll_z_deg": 18.0,
		"duration_mult": 1.15,
		"easing": "in_out_quad",
		"blade_color": Color(1.6, 0.55, 0.2, 1.0),
		"emission_color": Color(1.4, 0.4, 0.1, 1.0),
		"emission_energy": 3.0,
	},
	"Glace": {  # Glace : coup haché vers le bas, lent, glow froid
		"arc_y_start_deg": -55.0,
		"arc_y_end_deg": 65.0,
		"arc_x_dip_deg": 55.0,  # grosse plongée = effet hachoir
		"roll_z_deg": -8.0,
		"duration_mult": 1.3,
		"easing": "in_out_cubic",
		"blade_color": Color(0.55, 0.85, 1.4, 1.0),
		"emission_color": Color(0.4, 0.7, 1.2, 1.0),
		"emission_energy": 2.0,
	},
	"Foudre": {  # Foudre : snap ultra rapide, étroit, flash jaune
		"arc_y_start_deg": -100.0,
		"arc_y_end_deg": 100.0,
		"arc_x_dip_deg": 8.0,
		"roll_z_deg": 0.0,
		"duration_mult": 0.65,
		"easing": "out_expo",
		"blade_color": Color(1.4, 1.3, 0.4, 1.0),
		"emission_color": Color(1.2, 1.1, 0.3, 1.0),
		"emission_energy": 3.5,
	},
	"Poison": {  # Poison : sweep circulaire ample, roll prononcé
		"arc_y_start_deg": -120.0,
		"arc_y_end_deg": 120.0,
		"arc_x_dip_deg": 22.0,
		"roll_z_deg": 30.0,
		"duration_mult": 1.05,
		"easing": "in_out_sine",
		"blade_color": Color(0.4, 1.2, 0.4, 1.0),
		"emission_color": Color(0.3, 1.0, 0.3, 1.0),
		"emission_energy": 1.8,
	},
}


func _ready() -> void:
	_apply_data()
	weapon_name_changed.emit(base_weapon_name)
	# Duplique le material partagé pour qu'on puisse modifier emission/albedo
	# par instance sans contaminer les autres lames (ex: ennemi melee).
	if _blade_mesh != null and _blade_mesh.material_override is StandardMaterial3D:
		_blade_material = (_blade_mesh.material_override as StandardMaterial3D).duplicate()
		_blade_mesh.material_override = _blade_material
	_apply_blade_color(_get_profile(""))


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
	# Couleur de lame "au repos" = celle de la gemme équipée. Donne un feedback
	# visuel permanent : tu sais quelle gemme tu portes sans regarder le HUD.
	_apply_blade_color(_get_profile(equipped_spell_name))


## Retire la gemme équipée.
func unequip_spell() -> void:
	equipped_spell_name = ""
	weapon_name_changed.emit(get_display_name())
	_apply_blade_color(_get_profile(""))


func can_fire() -> bool:
	return _cooldown_left <= 0.0 and _swing_time_left <= 0.0


## Declenche un swing. Le hit detection s'applique pendant active_window
## centree dans swing_duration (lui-même modulé par le profil de la gemme).
func swing() -> void:
	if not can_fire():
		return
	_active_profile = _get_profile(equipped_spell_name)
	var dur_mult: float = float(_active_profile.get("duration_mult", 1.0))
	var current_duration: float = swing_duration * dur_mult
	_cooldown_left = max(1.0 / fire_rate, current_duration)
	_swing_time_left = current_duration
	_hit_targets_this_swing.clear()
	_ghosts_emitted = 0
	swung.emit()


func _process(delta: float) -> void:
	if _cooldown_left > 0.0:
		_cooldown_left -= delta
	if _swing_time_left > 0.0:
		_swing_time_left -= delta
		_animate_swing()
		_check_hits()
		_maybe_emit_ghost()
	elif _blade != null and _blade.rotation != Vector3.ZERO:
		_blade.rotation = Vector3.ZERO


## Lecture du profil. Tombe sur "" si l'élément n'est pas connu (ex: gemme
## ajoutée plus tard dans le yaml mais pas encore dans SWING_PROFILES).
func _get_profile(spell_name: String) -> Dictionary:
	if SWING_PROFILES.has(spell_name):
		return SWING_PROFILES[spell_name]
	return SWING_PROFILES[""]


## Trajectoire 3D du blade pendant le swing. Multi-axes :
## - Y : balayage horizontal principal (de arc_y_start à arc_y_end)
## - X : "dip" en cloche, peak au milieu du swing (sin(πt))
## - Z : roll qui suit la même cloche que X
func _animate_swing() -> void:
	if _blade == null or _active_profile.is_empty():
		return
	var duration: float = swing_duration * float(_active_profile.get("duration_mult", 1.0))
	var t: float = clamp(1.0 - (_swing_time_left / duration), 0.0, 1.0)
	var eased_t: float = _apply_easing(t, String(_active_profile.get("easing", "linear")))

	var y_start: float = float(_active_profile.get("arc_y_start_deg", -60.0))
	var y_end: float = float(_active_profile.get("arc_y_end_deg", 60.0))
	var x_dip: float = float(_active_profile.get("arc_x_dip_deg", 0.0))
	var z_roll: float = float(_active_profile.get("roll_z_deg", 0.0))

	# Cloche sin(πt) : 0 → 1 → 0, peak à t=0.5. Donne du caractère au milieu.
	var bell: float = sin(PI * eased_t)

	_blade.rotation = Vector3(
		deg_to_rad(x_dip * bell),
		deg_to_rad(lerp(y_start, y_end, eased_t)),
		deg_to_rad(z_roll * bell),
	)


func _apply_easing(t: float, kind: String) -> float:
	match kind:
		"linear":
			return t
		"out_cubic":
			return 1.0 - pow(1.0 - t, 3.0)
		"in_out_quad":
			return 2.0 * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 2.0) * 0.5
		"in_out_cubic":
			return 4.0 * t * t * t if t < 0.5 else 1.0 - pow(-2.0 * t + 2.0, 3.0) * 0.5
		"out_expo":
			return 1.0 if t >= 1.0 else 1.0 - pow(2.0, -10.0 * t)
		"in_out_sine":
			return -(cos(PI * t) - 1.0) * 0.5
		_:
			return t


## Applique la couleur + l'emission du profil au material du blade. Appelé
## à equip/unequip + au _ready, pour que la lame au repos reflète la gemme.
func _apply_blade_color(profile: Dictionary) -> void:
	if _blade_material == null:
		return
	_blade_material.albedo_color = profile.get("blade_color", Color.WHITE)
	_blade_material.emission = profile.get("emission_color", Color(0.6, 0.7, 0.85, 1.0))
	_blade_material.emission_energy_multiplier = float(profile.get("emission_energy", 0.6))


## Émet un "ghost" : copie du mesh blade avec material semi-transparent qui
## fade out. Espacé régulièrement dans le swing pour faire un trail bon marché.
## On freeze le ghost dans la basis monde courante, puis Tween son alpha→0.
func _maybe_emit_ghost() -> void:
	if _blade == null or _blade_mesh == null:
		return
	var duration: float = swing_duration * float(_active_profile.get("duration_mult", 1.0))
	var t: float = clamp(1.0 - (_swing_time_left / duration), 0.0, 1.0)
	var target_count: int = clampi(int(t * GHOSTS_PER_SWING) + 1, 0, GHOSTS_PER_SWING)
	if target_count <= _ghosts_emitted:
		return
	_ghosts_emitted = target_count

	var ghost := MeshInstance3D.new()
	ghost.mesh = _blade_mesh.mesh
	ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ghost_mat := StandardMaterial3D.new()
	var base_color: Color = _active_profile.get("emission_color", Color(1, 1, 1, 1))
	ghost_mat.albedo_color = Color(base_color.r, base_color.g, base_color.b, 0.55)
	ghost_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_mat.emission_enabled = true
	ghost_mat.emission = base_color
	ghost_mat.emission_energy_multiplier = float(_active_profile.get("emission_energy", 1.0)) * 0.7
	ghost.material_override = ghost_mat

	# On attache le ghost à la scène racine pour qu'il reste figé dans le monde
	# pendant que la lame continue. Reproduit la transform monde du mesh.
	var scene_root: Node = get_tree().current_scene
	if scene_root == null:
		ghost.queue_free()
		return
	scene_root.add_child(ghost)
	ghost.global_transform = _blade_mesh.global_transform

	var tween: Tween = create_tween()
	tween.tween_property(ghost_mat, "albedo_color:a", 0.0, GHOST_LIFETIME_SEC)
	tween.parallel().tween_property(ghost_mat, "emission_energy_multiplier", 0.0, GHOST_LIFETIME_SEC)
	tween.tween_callback(ghost.queue_free)


func _check_hits() -> void:
	# Le hit est actif uniquement dans active_window centree dans swing.
	var duration: float = swing_duration * float(_active_profile.get("duration_mult", 1.0))
	var elapsed: float = duration - _swing_time_left
	var window_start: float = (duration - active_window) * 0.5
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

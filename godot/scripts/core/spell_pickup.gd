class_name SpellPickup
extends Area3D

## Gemme flottante qui équipe un sort sur l'arme du joueur qui la ramasse.
## Le joueur entre dans le rayon → prompt HUD → hold interact → équipe le
## combo + queue_free.
##
## M2 minimal : 1 sort par gemme, configurable via @export.

signal picked_up(by_player: PlayerController)

@export var spell_name: String = "Feu"
## Scène de projectile que le sort fait spawn quand l'arme tire.
## Pour le Feu : scenes/combos/fireball.tscn.
@export var projectile_scene: PackedScene
## Couleur de la gemme + light + emission.
@export var element_color: Color = Color(1.0, 0.4, 0.15, 1.0)
## Vitesse de rotation (visuel).
@export var rotation_speed: float = 1.5
## Amplitude du flottement vertical.
@export var float_amplitude: float = 0.2
@export var float_speed: float = 2.0

@onready var _mesh: MeshInstance3D = $Mesh
@onready var _light: OmniLight3D = $Light

var _time: float = 0.0
var _base_y: float = 0.0
var _picked: bool = false


func _ready() -> void:
	add_to_group(&"spell_pickups")
	_base_y = position.y
	# Applique la couleur au mesh + à la lumière.
	if _mesh != null and _mesh.material_override is StandardMaterial3D:
		var mat: StandardMaterial3D = (_mesh.material_override as StandardMaterial3D).duplicate()
		mat.albedo_color = element_color
		mat.emission = element_color
		_mesh.material_override = mat
	if _light != null:
		_light.light_color = element_color


func _process(delta: float) -> void:
	_time += delta
	rotate_y(rotation_speed * delta)
	position.y = _base_y + sin(_time * float_speed) * float_amplitude


## Appelé par le PlayerController quand il a terminé le hold interact.
func try_pickup(by_player: PlayerController) -> bool:
	if _picked or by_player == null:
		return false
	var weapon: WeaponHitscan = by_player.get_weapon()
	if weapon == null:
		return false
	_picked = true
	weapon.equip_spell(spell_name, projectile_scene)
	picked_up.emit(by_player)
	queue_free()
	return true

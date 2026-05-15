class_name WeaponPickup
extends Interactable

## Pickup d'arme. Au try_interact, equipe l'arme correspondante sur le
## player qui ramasse. Le pickup ne disparait PAS (on peut revenir changer
## d'arme entre 2 vies).
##
## Convention : weapon_kind est utilise par le player pour decider quelle
## scene activer (pistol → WeaponHitscan node, melee → WeaponMelee node).
## On evite l'instanciation dynamique pour rester simple (les 2 nodes
## existent dans player.tscn et on toggle leur visibilite + activation).

signal weapon_picked(by_player: Node, weapon_kind: StringName)

const KIND_PISTOL := &"pistol"
const KIND_MELEE := &"melee"

@export var weapon_kind: StringName = &"pistol"
@export var display_name: String = "Pistolet"
## Couleur de l'indicateur visuel au-dessus du socle (set au _ready).
@export var indicator_color: Color = Color(0.9, 0.3, 0.25, 1)

@onready var _indicator: MeshInstance3D = $Indicator if has_node("Indicator") else null


func _ready() -> void:
	super._ready()
	prompt_text = "Prendre %s" % display_name
	hold_duration = 0.5
	interaction_range = 2.5
	selection_priority = 0
	_apply_indicator_color()


func _apply_indicator_color() -> void:
	if _indicator == null:
		return
	var mat := StandardMaterial3D.new()
	mat.albedo_color = indicator_color
	mat.emission_enabled = true
	mat.emission = indicator_color
	mat.emission_energy_multiplier = 2.5
	mat.metallic = 0.5
	_indicator.material_override = mat


func can_interact(by_player: Node) -> bool:
	return by_player is PlayerController


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	var player: PlayerController = by_player as PlayerController
	if not player.has_method(&"equip_weapon_kind"):
		push_warning("[WeaponPickup] PlayerController n'a pas equip_weapon_kind()")
		return false
	player.equip_weapon_kind(weapon_kind)
	weapon_picked.emit(player, weapon_kind)
	interaction_completed.emit(player)
	return true

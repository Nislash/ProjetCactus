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
## Couleur de la lame. Par défaut le blanc glacé de la famille « arme » — cf
## `CrystalGrammar`. Un socle qui aurait sa propre couleur casserait la
## grammaire au moment même où elle sert.
@export var indicator_color: Color = CrystalGrammar.COLOR_WEAPON

@onready var _indicator: MeshInstance3D = $Indicator if has_node("Indicator") else null


func _ready() -> void:
	super._ready()
	prompt_text = "Prendre %s" % display_name
	hold_duration = 0.5
	interaction_range = 2.5
	selection_priority = 0
	_apply_indicator_color()


## Impose la SILHOUETTE de la famille « arme » : une lame verticale, plantée,
## immobile. La forme est refaite ici plutôt que dans la scène pour que tous
## les socles la partagent — un socle qui garderait l'ancien cube flottant se
## lirait comme un pouvoir.
func _apply_indicator_color() -> void:
	if _indicator == null:
		return
	_indicator.mesh = CrystalGrammar.weapon_blade_mesh()
	_indicator.position = Vector3(0.0, 0.95, 0.0)
	_indicator.material_override = CrystalGrammar.make_material(indicator_color, 2.2)
	if not has_node("Glow"):
		add_child(CrystalGrammar.make_glow(indicator_color, 1.2, 4.5))
func can_interact(by_player: Node) -> bool:
	var player: PlayerController = by_player as PlayerController
	if player == null:
		return false
	return player.get_equipped_weapon_kind() != weapon_kind


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

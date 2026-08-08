class_name SpellPickup
extends Interactable

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
	super._ready()  # Ajoute au groupe "interactables".
	prompt_text = "Ramasser %s" % spell_name
	hold_duration = 0.6
	interaction_range = 2.5
	_base_y = position.y
	# SILHOUETTE de la famille « pouvoir » : un octaèdre, seul solide régulier
	# d'une caverne faite de cassures. Il garde la couleur de son élément —
	# savoir qu'une gemme est de feu compte plus que savoir que c'est une
	# gemme. Cf `CrystalGrammar`.
	if _mesh != null:
		_mesh.mesh = CrystalGrammar.power_gem_mesh()
		_mesh.material_override = CrystalGrammar.make_material(element_color, 3.0)
	if _light != null:
		_light.light_color = element_color


func _process(delta: float) -> void:
	_time += delta
	rotate_y(rotation_speed * delta)
	position.y = _base_y + sin(_time * float_speed) * float_amplitude


func can_interact(by_player: Node) -> bool:
	if _picked or not (by_player is PlayerController):
		return false
	# On exige une arme equipee — sans arme, la gemme n'a rien a equiper.
	# Si plus tard on veut un slot gemme persistent, retirer ce check et
	# stocker la gemme cote PlayerController.
	return (by_player as PlayerController).get_equipped_weapon_kind() != &""


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	var player: PlayerController = by_player as PlayerController
	_picked = true
	# On equipe la gemme sur l'arme actuellement en main, pas sur une arme
	# arbitraire. Pistol → WeaponHitscan.equip_spell. Melee → WeaponMelee.
	# Les 2 armes ont la meme signature equip_spell(name, projectile_scene)
	# meme si la melee ignore projectile_scene (pas de projectile distant).
	match player.get_equipped_weapon_kind():
		&"pistol":
			player.get_weapon().equip_spell(spell_name, projectile_scene)
		&"melee":
			if player.get_melee() != null:
				player.get_melee().equip_spell(spell_name, projectile_scene)
	picked_up.emit(player)
	interaction_completed.emit(player)
	queue_free()
	return true

class_name StartChest
extends Interactable

## Coffre de début de run. Pose au début du level (Marker3D "StartChestSpawn"
## dans la scene level), instancié par run_shell. Au try_interact, tire au
## sort 1 arme (parmi 2) et 1 sort (parmi 4) et les équipe sur TOUS les
## joueurs actifs.
##
## C'est la version minimale du systeme decrit dans CLAUDE.md : "chaque run
## démarre par l'ouverture d'un coffre qui tire au sort la classe + l'arme
## de départ". Pour l'instant on tire arme + sort, la classe reste implicite
## (Pistolero unique disponible).
##
## Le coffre disparait apres ouverture. Pas de re-roll.

signal opened(weapon_kind: StringName, spell_name: String)

## Resources tirees au sort. Edition possible dans l'inspector si on veut
## restreindre le pool sur un niveau (ex tutoriel = pistol+fire fixe).
@export var weapon_kinds: Array[StringName] = [&"pistol", &"melee"]
## Liste de paires (spell_name, projectile_scene_path). On stocke des paths
## plutot que PackedScene pour rester ext_resource-free (le path est resolu
## a l'ouverture du coffre).
@export var spell_pool: Array[Dictionary] = [
	{"name": "Feu",     "path": "res://scenes/combos/fireball.tscn",     "color": Color(1.0, 0.45, 0.15, 1)},
	{"name": "Glace",   "path": "res://scenes/combos/ice_orb.tscn",      "color": Color(0.45, 0.85, 1.0, 1)},
	{"name": "Poison",  "path": "res://scenes/combos/poison_orb.tscn",   "color": Color(0.5, 1.0, 0.4, 1)},
	{"name": "Foudre",  "path": "res://scenes/combos/thunder_orb.tscn",  "color": Color(1.0, 0.95, 0.4, 1)},
]

@onready var _indicator: MeshInstance3D = $Indicator if has_node("Indicator") else null
@onready var _light: OmniLight3D = $Light if has_node("Light") else null

var _opened: bool = false


func _ready() -> void:
	super._ready()
	# Le cristal d'armes : c'est lui qui tire la classe et l'arme de départ.
	prompt_text = "Éveiller le cristal d'armes"
	hold_duration = 0.6
	interaction_range = 3.0
	# Priorite haute : le coffre passe avant un weapon pickup colle (s'il y
	# en avait) ou un lever proche.
	selection_priority = 20


func can_interact(by_player: Node) -> bool:
	return not _opened and (by_player is PlayerController)


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	_opened = true

	# Tire arme + sort.
	var weapon_kind: StringName = weapon_kinds.pick_random() if not weapon_kinds.is_empty() else &"pistol"
	var spell_entry: Dictionary = spell_pool.pick_random() if not spell_pool.is_empty() else {}
	var spell_name: String = spell_entry.get("name", "")
	var spell_path: String = spell_entry.get("path", "")
	var spell_color: Color = spell_entry.get("color", Color.WHITE)

	# Charge le projectile une fois (peut etre null si le path est invalide
	# ou si le combo n'existe pas encore : on equipe juste le nom du sort).
	var projectile_scene: PackedScene = null
	if spell_path != "":
		projectile_scene = load(spell_path) as PackedScene

	# Applique sur TOUS les joueurs actifs (couch coop : meme loadout pour
	# tout le monde au demarrage, simple et previsible).
	var applied_to: int = 0
	for p in get_tree().get_nodes_in_group(&"players"):
		if not (p is PlayerController):
			continue
		var player: PlayerController = p
		player.equip_weapon_kind(weapon_kind)
		# Equipe le sort sur l'arme en main.
		match weapon_kind:
			&"pistol":
				var w = player.get_weapon()
				if w != null and spell_name != "":
					w.equip_spell(spell_name, projectile_scene)
			&"melee":
				var m = player.get_melee()
				if m != null and spell_name != "":
					m.equip_spell(spell_name, projectile_scene)
		applied_to += 1

	# Feedback visuel : coffre ouvert (indicateur dim + light off).
	if _indicator != null:
		_indicator.visible = false
	if _light != null:
		_light.visible = false

	print("[StartChest] Tirage : %s + %s — appliqué à %d joueur(s)" % [weapon_kind, spell_name, applied_to])
	opened.emit(weapon_kind, spell_name)
	interaction_completed.emit(by_player)
	return true

class_name RelicChest
extends Interactable

## Coffre du monde qui drop une relique aléatoire à l'ouverture (hold Interact).
## Place plusieurs Marker3D dans le groupe "relic_chest_spawns" dans la scène
## du niveau, run_shell instancie cette scène à 4 markers tirés au hasard.
##
## Tirage : par défaut TIER_PROBS_TUTO inclut les légendaires à 1 %. Si vous
## voulez le comportement standard (legendary 0 %), set tier_probs_override
## avant le _ready ou laissez RelicLootTable.TIER_PROBS_STANDARD via Inspector.

signal chest_opened(by_player: Node, data: RelicData)

## Override tuto : 70/24/5/1. Les légendaires drop rarement même au tuto
## puisque l'user a choisi "Tous tiers (légendaire inclus)".
const TIER_PROBS_TUTO: Dictionary = {
	RelicData.Tier.COMMON: 0.70,
	RelicData.Tier.RARE: 0.24,
	RelicData.Tier.EPIC: 0.05,
	RelicData.Tier.LEGENDARY: 0.01,
}

## Si set par l'instance (Inspector ou code), écrase les probas du draw.
## Vide = utilise TIER_PROBS_TUTO.
@export var tier_probs_override: Dictionary = {}

## Si true, évite de drop une relique déjà possédée par le joueur qui ouvre.
@export var avoid_duplicates: bool = true

var _opened: bool = false

@onready var _base_mesh: MeshInstance3D = $Base/BaseMesh if has_node("Base/BaseMesh") else null
@onready var _lid: Node3D = $Lid if has_node("Lid") else null

## Forme diégétique cristalline (niveau 1) : un sanctuaire de cristal plutôt
## qu'un coffre de bois — dans une caverne cristalline, un coffre n'a rien à y
## faire. Ces nœuds sont OPTIONNELS : une scène qui ne les déclare pas garde
## l'animation de couvercle historique.
@onready var _crystal: Node3D = $Crystal if has_node("Crystal") else null
@onready var _crystal_glow: OmniLight3D = $Crystal/Glow if has_node("Crystal/Glow") else null


func _ready() -> void:
	super._ready()
	# Forme diégétique du niveau 1 : un sanctuaire de cristal, pas un coffre.
	prompt_text = "Briser le cristal"
	hold_duration = 1.0
	interaction_range = 2.5
	selection_priority = 10  ## convention CLAUDE.md : coffre = +10


func can_interact(by_player: Node) -> bool:
	if _opened:
		return false
	var player: PlayerController = by_player as PlayerController
	if player == null:
		return false
	# Inventaire plein : le coffre ne se propose pas. `try_interact` refusait
	# déjà, mais sans marquer le coffre comme utilisé — la jauge se remplissait
	# donc en boucle sur un refus muet.
	if player.relic_inventory != null and player.relic_inventory.is_full():
		return false
	return true


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	var player: PlayerController = by_player as PlayerController
	if player.relic_inventory == null:
		push_warning("[RelicChest] PlayerController sans RelicInventory")
		return false

	# Inventaire plein → le coffre reste fermable.
	if player.relic_inventory.is_full():
		player.relic_inventory.inventory_full_attempt.emit(null)
		interaction_cancelled.emit()
		return false

	var probs: Dictionary = tier_probs_override if not tier_probs_override.is_empty() else TIER_PROBS_TUTO
	var data: RelicData
	if avoid_duplicates:
		data = RelicLootTable.draw_excluding(player.relic_inventory.get_relics(), probs)
	else:
		data = RelicLootTable.draw_with(probs)
	if data == null:
		push_warning("[RelicChest] LootTable a retourné null")
		return false

	if not player.relic_inventory.try_add(data):
		return false

	_opened = true
	_play_open_anim()
	chest_opened.emit(player, data)
	interaction_completed.emit(player)
	# Sortir du groupe interactables pour ne plus être scanné.
	remove_from_group(&"interactables")
	return true


func _play_open_anim() -> void:
	# Forme cristalline : le cristal S'ÉTEINT. C'est le retour visuel qui a du
	# sens ici — un cristal n'a pas de couvercle, et la lueur qui meurt dit
	# « consommé » sans un mot. Elle raconte aussi quelque chose à distance : la
	# caverne compte ses sanctuaires encore vivants.
	if _crystal != null:
		_play_crystal_extinction()
		return

	# Anim minimaliste : le lid pivote vers l'arrière en 0.4 s.
	if _lid != null:
		var tween: Tween = create_tween()
		tween.tween_property(_lid, "rotation:x", deg_to_rad(-100.0), 0.4) \
			.set_trans(Tween.TRANS_BACK) \
			.set_ease(Tween.EASE_OUT)
	# Assombrit la base pour signaler l'état "vide".
	if _base_mesh != null:
		var mat: StandardMaterial3D = _base_mesh.material_override as StandardMaterial3D
		if mat != null:
			mat = mat.duplicate() as StandardMaterial3D
			mat.albedo_color = mat.albedo_color.darkened(0.4)
			mat.emission_energy_multiplier = 0.0
			_base_mesh.material_override = mat


## Extinction du sanctuaire : un éclat bref, puis la lueur meurt.
##
## Le sursaut avant l'extinction n'est pas décoratif — il confirme au joueur
## que SON action a été prise en compte, à l'instant précis où elle l'est. Une
## lumière qui décroît seulement pourrait passer pour un effet d'ambiance.
func _play_crystal_extinction() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(false)

	if _crystal_glow != null:
		var base_energy: float = _crystal_glow.light_energy
		tween.tween_property(_crystal_glow, "light_energy", base_energy * 2.2, 0.12) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_crystal_glow, "light_energy", 0.0, 0.9) \
			.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)

	# L'émission du matériau suit la lumière, sinon le cristal resterait
	# lumineux alors qu'il n'éclaire plus rien.
	var mesh_instance: MeshInstance3D = _crystal.get_node_or_null("Mesh") as MeshInstance3D
	if mesh_instance == null:
		return
	var material: BaseMaterial3D = mesh_instance.material_override as BaseMaterial3D
	if material == null:
		return
	# Duplique : le matériau est partagé entre toutes les instances du prop,
	# éteindre l'original éteindrait TOUS les sanctuaires du niveau d'un coup.
	material = material.duplicate() as BaseMaterial3D
	mesh_instance.material_override = material
	tween.parallel().tween_property(material, "emission_energy_multiplier", 0.0, 0.9) \
		.set_trans(Tween.TRANS_QUINT).set_ease(Tween.EASE_IN)
	tween.parallel().tween_property(material, "albedo_color", Color(0.28, 0.33, 0.40), 0.9)

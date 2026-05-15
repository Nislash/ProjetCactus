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


func _ready() -> void:
	super._ready()
	prompt_text = "Ouvrir le coffre"
	hold_duration = 1.0
	interaction_range = 2.5
	selection_priority = 10  ## convention CLAUDE.md : coffre = +10


func can_interact(by_player: Node) -> bool:
	if _opened:
		return false
	return by_player is PlayerController


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

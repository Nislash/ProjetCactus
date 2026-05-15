class_name RelicData
extends Resource

## Définit un artefact (relique) du run. Source de vérité : docs/design/relics.yaml,
## converti en .tres via tools/relics_yaml_to_tres.py.
##
## Une RelicData est portée par un joueur via RelicInventory (cf
## scripts/core/relic_inventory.gd). Les effets sont appliqués par le
## RelicEffectResolver enfant du PlayerController.

enum Tier { COMMON, RARE, EPIC, LEGENDARY }

enum EffectType {
	STAT,        ## bonus passif lu via RelicInventory.compute_stat()
	ON_HIT,      ## proc sur weapon.fired (chance / status)
	ON_KILL,     ## proc sur kill ennemi (heal / buff / drop)
	ON_DASH,     ## proc au début du dash
	ON_DAMAGED,  ## proc quand le joueur est touché
	ON_LOW_HP,   ## proc quand HP traverse threshold_pct
	ON_REVIVE,   ## proc quand le joueur relève un allié
	ON_RELOAD,   ## proc à la fin du reload
	COMBO_MOD,   ## modifie un combo arme×école (stub jusqu'à combo_engine Rust)
	COOP,        ## conditionnel à l'état/position d'un allié
}

enum Trigger { PASSIVE, ON_HIT, ON_KILL, ON_DASH, ON_DAMAGED, ON_LOW_HP, ON_REVIVE, ON_RELOAD }

enum DropPool { STANDARD, SHOP_ONLY, BOSS_ONLY }

@export var id: StringName = &""
@export var display_name: String = "Relique sans nom"
@export_multiline var description: String = ""
@export_multiline var flavor: String = ""

@export_group("Classification")
@export var tier: Tier = Tier.COMMON
@export var effect_type: EffectType = EffectType.STAT
@export var trigger: Trigger = Trigger.PASSIVE
@export var drop_pool: DropPool = DropPool.STANDARD

@export_group("Filtres conditionnels")
## Vide = pas de filtre. Sinon : "pistol" / "shotgun" / "rifle" / "melee".
@export var weapon_filter: StringName = &""
## Vide = pas de filtre. Sinon : "fire" / "ice" / "thunder" / "poison" / "earth".
@export var school_filter: StringName = &""

@export_group("Effet")
## Dictionnaire libre de paramètres (clés StringName). Schéma dépend de
## l'effect_type. Cf docs/design/relics.yaml pour la convention de clés.
@export var magnitude: Dictionary = {}

@export_group("Visuel")
@export var icon: Texture2D


## Lecture sûre d'une clé magnitude avec valeur par défaut.
func get_magnitude(key: StringName, default_value: Variant = 0.0) -> Variant:
	if magnitude.has(key):
		return magnitude[key]
	return default_value


func tier_name() -> String:
	match tier:
		Tier.COMMON: return "Commun"
		Tier.RARE: return "Rare"
		Tier.EPIC: return "Épique"
		Tier.LEGENDARY: return "Légendaire"
	return "?"


func tier_color() -> Color:
	match tier:
		Tier.COMMON: return Color(0.78, 0.78, 0.78)
		Tier.RARE: return Color(0.35, 0.55, 0.95)
		Tier.EPIC: return Color(0.75, 0.35, 0.95)
		Tier.LEGENDARY: return Color(1.0, 0.65, 0.15)
	return Color.WHITE

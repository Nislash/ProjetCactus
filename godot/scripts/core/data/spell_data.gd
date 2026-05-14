class_name SpellData
extends Resource

## Définit un parchemin de sort tiré au coffre. Un sort modifie une arme
## pour produire un combo (cf ComboData).

## Ordre des écoles aligné avec ClassData/WeaponData.compatible_spell_schools.
enum School {
	PYROMANCY,   ## 0 — Feu (burn DoT)
	CRYOMANCY,   ## 1 — Glace (slow + freeze)
	LIGHTNING,   ## 2 — Foudre (chain)
	POISON,      ## 3 — Poison (DoT AoE)
	ARCANE,      ## 4 — Arcane (utility)
}

@export var spell_name_display: String = "Sort sans nom"
@export_multiline var description: String = ""

@export_group("Identification")
@export var school: School = School.PYROMANCY

@export_group("Modifs au tir de l'arme")
## Multiplicateur appliqué au damage_base de l'arme (1.0 = pas de change).
@export var damage_modifier: float = 1.0
## ID de status effect appliqué à l'impact (M2 = vrai status system).
## M1 = string descriptif, peut être lu par le gameplay code en attendant.
@export var status_effect_id: StringName = &""
## Durée du status effect en secondes.
@export var status_duration: float = 0.0
## DPS du status effect si applicable (burn, poison).
@export var status_dps: float = 0.0

@export_group("Visuel")
## Couleur dominante du combo associé (modulate du projectile / VFX).
@export var element_color: Color = Color.WHITE

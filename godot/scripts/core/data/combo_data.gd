class_name ComboData
extends Resource

## Définit un combo arme×sort. Cf docs/design/combos_matrix.md pour la
## matrice 4×5 = 20 combos à terme. M1 = 1 combo : Pistolet × Feu.
##
## Le ComboData référence une WeaponData + une SpellData et peut SURCHARGER
## le rendu / les stats. C'est la "signature gameplay" du jeu (cf CLAUDE.md
## "Signature du jeu") : le gameplay et l'animation doivent se ressentir,
## pas juste une recoloration.

@export var combo_name_display: String = "Combo sans nom"
@export_multiline var description: String = ""

@export_group("Sources")
@export var weapon: WeaponData
@export var spell: SpellData

@export_group("Surcharges projectile")
## Si set, remplace projectile_scene de la WeaponData. Permet d'avoir un
## "vrai" projectile boule de feu visuel pour le combo Pistolet × Feu, par
## exemple, même si la WeaponData de base est hitscan.
@export var override_projectile_scene: PackedScene
## Force le combo à utiliser un projectile physique au lieu du hitscan
## (utile pour les sorts qui ont besoin d'un trajet visible).
@export var force_projectile_mode: bool = false

@export_group("Surcharges damage")
## Multiplicateur appliqué au damage_base après damage_modifier du sort.
@export var damage_multiplier: float = 1.0
@export var aoe_radius: float = 0.0  ## 0 = pas d'AoE (impact direct)

@export_group("Surcharges status")
## Override du status_effect_id du sort si non-vide. Permet d'avoir un
## status custom pour le combo (ex: "burn_amplified" au lieu de "burn").
@export var override_status_id: StringName = &""
@export var override_status_duration: float = 0.0
@export var override_status_dps: float = 0.0

@export_group("Surcharges visuelles")
## VFX scene à spawn sur le projectile / impact (M2+).
@export var vfx_overlay_scene: PackedScene
## Override de la couleur élémentaire (sinon hérite de spell.element_color).
@export var override_element_color: Color = Color.TRANSPARENT

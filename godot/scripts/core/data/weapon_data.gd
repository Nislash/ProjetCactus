class_name WeaponData
extends Resource

## Définit une arme tirée au coffre d'ouverture. Une arme + un sort = un combo
## visuel + mécanique signature (cf docs/design/combos_matrix.md).
##
## M1 : seul le Pistolet existe. M2 ajoutera les 3 autres (Shotgun, SMG, Sniper).

@export var weapon_name_display: String = "Arme sans nom"
@export_multiline var description: String = ""

@export_group("Combat")
@export var damage_base: int = 10
@export var fire_rate: float = 4.0  ## Tirs par seconde
@export var max_range: float = 50.0
@export_enum("Hitscan", "Projectile") var fire_mode: int = 0

@export_group("Munitions")
@export var max_ammo: int = 12
@export var reload_time: float = 1.5

@export_group("Slots de compatibilité")
## 5 booleans (1 par école de magie). Si une école est désactivée, on ne
## peut pas appliquer ce sort à cette arme (= pas de combo possible).
@export var compatible_spell_schools: Array[bool] = [true, true, true, true, true]

@export_group("Visuel")
## Scène 3D du projectile (M1 = hitscan donc null). M2+ pour le visuel
## projectile physique (cf #15 ComboData.override_projectile).
@export var projectile_scene: PackedScene

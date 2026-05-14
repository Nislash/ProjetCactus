class_name ClassData
extends Resource

## Définit une classe de personnage tirée au coffre d'ouverture.
## Cf docs/design/classes.md pour les 4 classes du POC.

@export var class_name_display: String = "Classe sans nom"
@export_multiline var description: String = ""

@export_group("Stats de base")
@export var base_hp: int = 100
@export var base_speed: float = 7.0
@export var base_jump_velocity: float = 7.0

@export_group("Loadout de départ")
## Arme tirée par défaut quand cette classe est ouverte au coffre.
@export var starting_weapon: WeaponData
## Sort tiré par défaut. M1 = un seul sort fixe ; M2 ajoutera le pool d'écoles.
@export var starting_spell: SpellData

@export_group("Slots de compatibilité")
## 5 booleans (1 par école de magie : Pyromancie / Cryomancie / Foudre /
## Poison / Arcane). Une classe peut bloquer certaines écoles.
## Cf docs/design/magic_schools.md pour l'ordre des écoles.
@export var compatible_spell_schools: Array[bool] = [true, true, true, true, true]

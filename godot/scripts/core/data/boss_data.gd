class_name BossData
extends Resource

## Définit un boss (un par niveau à terme). Stats, phases, recette de combo
## weak point, métadonnées musique/intro. Voir docs/design/bosses.md.

@export var boss_name_display: String = "Boss sans nom"
@export_multiline var description: String = ""

@export_group("Combat")
@export var max_health: int = 500
@export var move_speed_base: float = 2.0
@export var move_speed_enrage: float = 3.5

@export_group("Phases (HP %)")
## Trigger transition phase 1 -> phase 2 (ex: 0.66 = à 66% HP restants).
@export_range(0.0, 1.0) var phase_2_trigger: float = 0.66
## Trigger transition phase 2 -> phase 3 enrage (ex: 0.33 = à 33% HP).
@export_range(0.0, 1.0) var phase_3_trigger: float = 0.33

@export_group("Résistance status")
## Nombre d'applications du même status dans la fenêtre pour qu'il déclenche
## (1 = mob standard, 2 = boss POC).
@export_range(1, 5) var status_hit_threshold: int = 2
## Fenêtre temporelle pour accumuler les applications (en s).
@export var status_threshold_window: float = 5.0
## Multiplicateur de durée des status appliqués (0.5 = boss subit 50% du
## temps qu'un mob).
@export_range(0.1, 2.0) var status_duration_multiplier: float = 0.5
## Liste des status auxquels le boss devient immunisé pendant l'enrage.
@export var enrage_immune_status: Array[StringName] = [&"stun", &"freeze"]

@export_group("Weak point combo")
## Recette : séquence d'IDs status à appliquer dans l'ordre dans la fenêtre.
## Ex: [&"freeze", &"thunder"] = freeze puis thunder dans les X secondes.
@export var weak_point_recipe: Array[StringName] = []
## Fenêtre temporelle entre 1er et dernier ingrédient de la recette (en s).
@export var weak_point_window: float = 3.0
## Durée du stun déclenché par un combo réussi (en s).
@export var combo_stun_duration: float = 5.0
## Pourcentage de HP perdus instantanément par le combo (0.15 = 15%).
@export_range(0.0, 1.0) var combo_hp_loss_percent: float = 0.15
## Cooldown avant un nouveau combo possible (en s).
@export var combo_cooldown: float = 15.0

@export_group("Intro / Audio")
@export var intro_camera_duration: float = 3.0
## Chemin de la musique boss (ogg/mp3). Vide = pas de switch.
@export_file("*.ogg", "*.mp3") var boss_music_path: String = ""

@export_group("Drop")
## Référence vers la table de drop legendary (peuplée au runtime).
## TODO : couplage avec RelicLootTable une fois M3 lancé.
@export var drops_legendary_relic: bool = true

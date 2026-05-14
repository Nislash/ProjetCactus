class_name Interactable
extends Area3D

## Composant generique pour objets du monde avec lesquels le joueur interagit
## via le bouton interact maintenu (pickup, levier, coffre, shop, revive).
##
## Le PlayerController scanne les objets du groupe "interactables" a chaque
## frame, choisit le meilleur candidat (priorite haute puis distance), accumule
## le temps de hold et appelle try_interact() quand hold_duration est atteint.
##
## Sous-classes doivent override try_interact (logique metier au moment du
## declenchement). Peuvent override can_interact (filtrage : ex. gemme deja
## ramassee, allie non-downed pour un ReviveInteractable, etc.).

@warning_ignore_start("unused_signal")
signal interaction_started(by_player: Node)
signal interaction_completed(by_player: Node)
signal interaction_cancelled()
@warning_ignore_restore("unused_signal")

## Texte affiche au HUD pendant le hold (ex. "Ramasser Feu", "Activer le levier").
@export var prompt_text: String = "Interagir"

## Duree du hold en secondes pour declencher try_interact().
@export var hold_duration: float = 0.6

## Distance maxi (m) a laquelle le joueur peut interagir.
@export var interaction_range: float = 2.5

## Priorite de selection si plusieurs interactables sont a portee. Plus haut =
## prioritaire. Convention : pickup=0, revive=-10, coffre/levier=+10.
## (Renomme depuis 'priority' qui collide avec Area3D.priority audio.)
@export var selection_priority: int = 0


func _ready() -> void:
	add_to_group(&"interactables")


## Filtrage. Retournez false pour ignorer cet interactable dans la selection
## (ex. allie non-downed, gemme deja ramassee). Defaut : true.
func can_interact(_by_player: Node) -> bool:
	return true


## Appele par PlayerController quand le hold est complete. A override par les
## sous-classes pour faire le vrai travail (equip_spell, open_door, etc.).
## Retourne true si l'interaction a eu lieu.
func try_interact(_by_player: Node) -> bool:
	return false

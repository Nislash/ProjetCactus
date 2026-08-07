## Charge l'environnement de la caverne depuis un `.tres`.
##
## POURQUOI CE SCRIPT EXISTE
## Le MCP Godot **ne sait pas assigner une propriété typée `Resource`** dans un
## `.tscn` : `modify_node_property` rapporte un succès mais n'écrit rien, et la
## propriété reste nulle. Comme `CLAUDE.md` interdit d'éditer les `.tscn` à la
## main, on charge la ressource par chemin — exactement le même contournement
## que [CavernTerrainBuilder.data_path].
##
## Effet de bord bienvenu : l'environnement redevient un artefact réassignable
## sans toucher à la scène, ce qui sert la passe d'éclairage E3.

class_name CavernEnvironment
extends WorldEnvironment

const DEFAULT_ENVIRONMENT_PATH := "res://data/levels/level01_cavern_environment.tres"

## Chemin de l'environnement à charger si aucun n'est déjà assigné.
@export_file("*.tres") var environment_path: String = DEFAULT_ENVIRONMENT_PATH


func _ready() -> void:
	if environment != null or environment_path.is_empty():
		return
	var loaded: Environment = load(environment_path) as Environment
	if loaded == null:
		push_error("CavernEnvironment : impossible de charger « %s »." % environment_path)
		return
	environment = loaded

class_name BossGolem
extends BossBase

## Golem de cristal. Boss POC du niveau 1. Hérite de BossBase qui gère la
## machine à états 3 phases, la résistance status, le combo recipe.
##
## Pour le POC : boss_data est préchargé ici. À terme, un BossSpawner ou
## le RunState injectera le BossData selon le niveau.

const _GOLEM_DATA: Resource = preload("res://resources/bosses/boss_data_golem.tres")


func _ready() -> void:
	if boss_data == null:
		boss_data = _GOLEM_DATA
	super._ready()

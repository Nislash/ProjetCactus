extends Node

## Le catalogue des personnages jouables, et celui qui est choisi.
##
## ## Pourquoi un autoload
##
## Le choix est fait au menu et consommé à la naissance du joueur, deux scènes
## plus loin. Le faire transiter par `RunState` serait plus propre en théorie,
## mais `RunState` est remis à zéro à chaque game over — et le personnage
## choisi, lui, doit survivre à une mort. Ce n'est pas de l'état de run, c'est
## une préférence.
##
## ## Ajouter un personnage
##
## Une ligne dans [constant ROSTER]. Rien d'autre. Le `.tres` décide seul de ce
## qu'il sait faire : un personnage livré avec trois animations est jouable, il
## est simplement moins expressif (cf `CharacterVisual.resolve_state`).

signal selection_changed(index: int)

const ROSTER: Array = [
	{
		"id": &"conqueror",
		"name": "Le Conquérant",
		"tagline": "Silhouette lourde, démarche assurée.",
		"set": "res://resources/characters/conqueror.tres",
	},
	{
		"id": &"sentinel",
		"name": "La Sentinelle",
		"tagline": "Le prototype. Peu d'animations, mais il tient debout.",
		"set": "res://resources/characters/sentinel.tres",
	},
]

var _index: int = 0


func count() -> int:
	return ROSTER.size()


## Volontairement PAS `get_index` : `Node` possède déjà cette méthode, avec un
## sens tout autre — l'indice du nœud chez son parent. La surcharger empêche
## Godot de résoudre la classe.
func current_index() -> int:
	return _index


func entry(index: int) -> Dictionary:
	if ROSTER.is_empty():
		return {}
	return ROSTER[posmod(index, ROSTER.size())]


func selected() -> Dictionary:
	return entry(_index)


## Défile d'un cran. Le catalogue BOUCLE : au bout on revient au début.
##
## Une liste qui bute à ses extrémités oblige à se rappeler où l'on est ; une
## liste circulaire se parcourt sans y penser, ce qui est le seul comportement
## acceptable pour un choix qu'on fait à la manette avant chaque partie.
func step(delta: int) -> void:
	if ROSTER.size() <= 1:
		return
	_index = posmod(_index + delta, ROSTER.size())
	selection_changed.emit(_index)


func select(index: int) -> void:
	_index = posmod(index, maxi(ROSTER.size(), 1))
	selection_changed.emit(_index)


## Le pack d'animations du personnage choisi, ou `null` s'il est introuvable.
##
## On ne fait PAS de repli sur un autre personnage : afficher quelqu'un d'autre
## que celui qu'on a choisi est plus déroutant qu'un personnage absent, et le
## message d'erreur dit alors ce qui manque.
func selected_anim_set() -> CharacterAnimSet:
	var chosen: Dictionary = selected()
	if chosen.is_empty():
		return null
	var loaded: CharacterAnimSet = load(chosen["set"]) as CharacterAnimSet
	if loaded == null:
		push_error("CharacterRoster : pack introuvable — %s" % chosen["set"])
	return loaded


## Les états que le personnage choisi sait jouer. Sert à l'écran de sélection,
## qui affiche ce que chacun a et ce qui lui manque.
func selected_states() -> Array[StringName]:
	var set_data: CharacterAnimSet = selected_anim_set()
	if set_data == null:
		return []
	return set_data.available_states()

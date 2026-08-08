class_name ViewPreference
extends RefCounted

## Mémorise la vue choisie — première ou troisième personne — **par manette**.
##
## ## Pourquoi par manette et non globalement
##
## Le jeu est un couch coop. Deux personnes assises côte à côte n'ont pas la
## même préférence, et l'une ne doit pas imposer la sienne à l'autre. Chaque
## joueur ayant déjà son propre viewport, rien ne s'oppose techniquement à ce
## que l'un joue en vue subjective pendant que l'autre voit son personnage.
##
## ## Pourquoi ça ne viole pas la règle roguelike
##
## `CLAUDE.md` interdit toute persistance entre runs. Comme le saut
## d'onboarding, ceci est une exception étroite et de même nature : un
## **réglage de confort**, qui ne stocke qu'un booléen, ne donne aucun
## avantage, et se réinitialise. Redemander sa vue à quelqu'un à chaque
## partie serait une friction, pas un design.
##
## Le fichier est partagé avec [OnboardingSkip] — même dossier utilisateur,
## sections distinctes. Deux fichiers pour deux booléens n'auraient rien
## simplifié.

const CONFIG_PATH := "user://onboarding.cfg"
const SECTION := "view"


## L'identité d'une manette est son NOM et non son index : rebrancher les
## manettes dans un autre ordre réattribue les index, et tout le monde
## perdrait son réglage.
##
## Recopié depuis [OnboardingSkip] plutôt qu'appelé : ce dernier tire toute la
## chaîne des autoloads derrière lui, et ce module doit rester utilisable — et
## testable — sans qu'un `PlayerManager` existe.
static func device_key(device_id: int) -> String:
	if device_id < 0:
		return "keyboard"
	var joy_name: String = Input.get_joy_name(device_id).strip_edges()
	if joy_name.is_empty():
		return "device_%d" % device_id
	return joy_name.to_lower().replace(" ", "_")


## Vrai si ce joueur veut voir son personnage. Défaut : **non**.
##
## La vue subjective reste le défaut parce que c'est celle sur laquelle le jeu
## est calibré — visée au réticule, tir ami, telegraphs au sol. La troisième
## personne est un confort qu'on choisit, pas un mode qu'on subit.
static func wants_third_person(device_id: int) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return false
	return bool(cfg.get_value(SECTION, device_key(device_id), false))


static func set_third_person(device_id: int, value: bool) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # absent = on part d'un fichier vide, pas une erreur
	cfg.set_value(SECTION, device_key(device_id), value)
	if cfg.save(CONFIG_PATH) != OK:
		push_warning("ViewPreference : impossible d'écrire %s" % CONFIG_PATH)


## Bascule et retourne la nouvelle valeur.
static func toggle(device_id: int) -> bool:
	var next: bool = not wants_third_person(device_id)
	set_third_person(device_id, next)
	return next

class_name GameSettings
extends RefCounted

## Les réglages de confort, écrits sur disque et relus au lancement.
##
## Deux valeurs pour l'instant — le volume général et la sensibilité de visée —
## et ce sont exactement celles qu'on veut changer *pendant* une partie, quand
## on entend que c'est trop fort ou qu'on rate ses visées. D'où leur place :
## dans le menu de pause, pas seulement au lobby.
##
## ## Pourquoi écrire sur disque ne viole pas la règle roguelike
##
## Même exception, de même nature, que [ViewPreference] et [OnboardingSkip] :
## un réglage de confort ne fait pas partie du run, ne donne aucun avantage, et
## redemander son volume à quelqu'un à chaque lancement serait une friction,
## pas un design.
##
## Fichier séparé de `user://onboarding.cfg` : celui-là est indexé par manette
## (chaque joueur sa vue), celui-ci est global à la machine (une seule paire
## d'enceintes dans le salon).

const CONFIG_PATH := "user://settings.cfg"
const SECTION_AUDIO := "audio"
const SECTION_GAMEPLAY := "gameplay"

const DEFAULT_MASTER_VOLUME := 0.8
const DEFAULT_LOOK_SENSITIVITY := 3.0
const SENSITIVITY_MIN := 1.0
const SENSITIVITY_MAX := 8.0


## Volume général, en linéaire 0..1 (0 = muet). Le stockage est linéaire et non
## en décibels : c'est ce que le curseur manipule, et convertir à l'écriture
## comme à la lecture ferait deux arrondis pour rien.
static func master_volume() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return DEFAULT_MASTER_VOLUME
	return clampf(float(cfg.get_value(SECTION_AUDIO, "master_volume", DEFAULT_MASTER_VOLUME)), 0.0, 1.0)


static func set_master_volume(value: float) -> void:
	_store(SECTION_AUDIO, "master_volume", clampf(value, 0.0, 1.0))
	apply_master_volume()


## Pousse le volume enregistré dans le bus Master. À appeler une fois au
## démarrage : sans ça, le réglage n'existerait que tant que le menu est ouvert.
static func apply_master_volume() -> void:
	var bus: int = AudioServer.get_bus_index(&"Master")
	if bus < 0:
		return
	var linear: float = master_volume()
	# En dessous de ce seuil, `linear_to_db` part vers -inf. On coupe le bus
	# franchement plutôt que de laisser un résidu inaudible mais actif.
	if linear <= 0.001:
		AudioServer.set_bus_mute(bus, true)
		return
	AudioServer.set_bus_mute(bus, false)
	AudioServer.set_bus_volume_db(bus, linear_to_db(linear))


static func look_sensitivity() -> float:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return DEFAULT_LOOK_SENSITIVITY
	var raw: float = float(cfg.get_value(SECTION_GAMEPLAY, "look_sensitivity", DEFAULT_LOOK_SENSITIVITY))
	return clampf(raw, SENSITIVITY_MIN, SENSITIVITY_MAX)


static func set_look_sensitivity(value: float) -> void:
	_store(SECTION_GAMEPLAY, "look_sensitivity", clampf(value, SENSITIVITY_MIN, SENSITIVITY_MAX))


## Applique la sensibilité aux joueurs déjà en jeu. Le réglage se change au
## milieu d'une partie : attendre le prochain run pour qu'il prenne effet
## reviendrait à ne pas pouvoir le régler du tout — on ne juge une sensibilité
## qu'en bougeant la caméra.
##
## Globale et non par manette, contrairement à la vue : c'est la seule des deux
## qui touche l'équilibre du jeu (viser vite), et une table qui veut la même
## difficulté pour tous doit pouvoir la fixer une fois.
static func apply_look_sensitivity(tree: SceneTree) -> void:
	if tree == null:
		return
	var value: float = look_sensitivity()
	for node in tree.get_nodes_in_group(&"players"):
		# `set()` et non un cast en [PlayerController] : celui-ci lit ses
		# réglages ici au `_ready`, et les deux scripts se référençant l'un
		# l'autre par leur `class_name` forment un cycle que GDScript refuse
		# de compiler.
		node.set(&"look_sensitivity", value)


static func _store(section: String, key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # absent = on part d'un fichier vide, pas une erreur
	cfg.set_value(section, key, value)
	cfg.save(CONFIG_PATH)

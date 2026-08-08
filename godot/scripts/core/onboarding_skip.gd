class_name OnboardingSkip
extends RefCounted

## Mémorise, PAR MANETTE, si l'onboarding a déjà été vu (beat B8).
##
## ## Pourquoi ceci ne viole pas la règle roguelike
##
## `CLAUDE.md` interdit toute persistance entre runs : ni monnaie méta, ni
## déblocage permanent. Ce fichier est la seule exception, et elle est étroite
## par construction :
##
## - il ne stocke **qu'un booléen par manette**, jamais un état de jeu ;
## - il ne donne **aucun avantage** — le skip ne fait gagner ni objet, ni
##   statistique, ni accès ; il fait gagner du *temps de tutoriel* ;
## - il est **réversible** (`forget_everything()`), ce qu'aucun déblocage
##   méta ne serait.
##
## C'est du confort d'accessibilité : redemander à quelqu'un d'apprendre à
## marcher à chaque run serait une punition, pas un design.
##
## ## Pourquoi par manette et pas global
##
## Le jeu est un couch coop. Un vétéran qui invite un ami veut que SON
## antichambre soit déjà éveillée et que celle de l'ami ne le soit pas. La clé
## est donc l'identité de la manette, pas la machine.

const CONFIG_PATH := "user://onboarding.cfg"
const SECTION := "seen"


## Le nom de la manette sert d'identité. Ce n'est pas parfait — deux manettes
## identiques partagent la clé — mais c'est stable entre deux lancements, ce
## que l'index de device n'est pas : brancher les manettes dans un autre ordre
## réattribue les index et ferait « oublier » tout le monde.
static func device_key(device_id: int) -> String:
	if device_id < 0:
		return "keyboard"
	var joy_name: String = Input.get_joy_name(device_id).strip_edges()
	if joy_name.is_empty():
		return "device_%d" % device_id
	return joy_name.to_lower().replace(" ", "_")


static func has_seen(device_id: int) -> bool:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return false
	return bool(cfg.get_value(SECTION, device_key(device_id), false))


static func mark_seen(device_id: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(CONFIG_PATH)  # Absent = on part d'un fichier vide, pas une erreur.
	cfg.set_value(SECTION, device_key(device_id), true)
	if cfg.save(CONFIG_PATH) != OK:
		push_warning("OnboardingSkip : impossible d'écrire %s" % CONFIG_PATH)


## Vrai seulement si TOUTES les manettes inscrites ont déjà vu l'onboarding.
##
## Le « ou » serait cruel : il suffirait d'un vétéran dans le salon pour
## priver un débutant de son apprentissage. Un seul nouveau venu et tout le
## monde rejoue l'antichambre — c'est trois minutes, et c'est ensemble.
static func everyone_has_seen(player_ids: Array[int]) -> bool:
	if player_ids.is_empty():
		return false
	for pid in player_ids:
		if not has_seen(PlayerManager.get_device_id(pid)):
			return false
	return true


static func mark_all_seen(player_ids: Array[int]) -> void:
	for pid in player_ids:
		mark_seen(PlayerManager.get_device_id(pid))


## Remet tout le monde à zéro. Existe pour les tests et pour une option de
## menu « revoir l'introduction » — sans elle, le skip serait irréversible,
## et un skip irréversible EST une progression méta.
static func forget_everything() -> void:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CONFIG_PATH))

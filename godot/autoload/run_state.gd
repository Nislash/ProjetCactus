extends Node

## Source de vérité du run roguelike en cours. Per-player : class/weapon/spell
## actuels + XP + level. Lifecycle : start_run → enemies kills + level-ups →
## end_run → reset.
##
## RIEN ne persiste entre runs (cf CLAUDE.md "pur roguelike"). reset() est
## appelé au game over → retour menu, _players vidé.
##
## Listé dans CLAUDE.md comme autoload autorisé. Référencé par futurs :
## #38 coffre début de run, #39 XP + level-up, HUD level/xp, drops d'ennemis.

signal run_started()
signal run_ended(reason: StringName)
signal player_leveled_up(player_id: int, new_level: int)
signal player_xp_changed(player_id: int, xp: int, threshold: int)
signal loadout_changed(player_id: int)

const REASON_GAME_OVER := &"game_over"
const REASON_VICTORY := &"victory"
const REASON_QUIT := &"quit"

## player_id (int) -> Dictionary {
##   "class_data": ClassData,
##   "weapon_data": WeaponData,
##   "spell_data": SpellData,
##   "xp": int,
##   "level": int,
## }
var _players: Dictionary = {}
var is_running: bool = false
## Chemin de la scene de niveau a charger par run_shell.tscn au prochain run.
## Set par le lobby (Tuto / Lancer le run) avant change_scene_to_file.
var selected_level_path: String = ""


func _ready() -> void:
	# Seed le RNG global avec le temps système, sinon Godot part avec seed 0
	# à chaque process → mêmes tirages à chaque run (coffres, drops, IA…).
	# RunState est l'autoload #3, exécuté avant RelicLootTable et les systèmes
	# de gameplay : tous les randf()/randi() qui suivent sont donc aléatoires.
	randomize()


## Démarre un nouveau run avec les loadouts initiaux. Appelé par le coffre
## de début de run (#38) après que chaque joueur ait validé.
##
## `loadouts` : player_id -> {class: ClassData, weapon: WeaponData, spell: SpellData}.
## Champs manquants tolérés (null).
func start_run(loadouts: Dictionary) -> void:
	_players.clear()
	for pid in loadouts.keys():
		var data: Dictionary = loadouts[pid]
		_players[pid] = {
			"class_data": data.get("class", null),
			"weapon_data": data.get("weapon", null),
			"spell_data": data.get("spell", null),
			"xp": 0,
			"level": 1,
		}
	is_running = true
	run_started.emit()


func end_run(reason: StringName = REASON_GAME_OVER) -> void:
	is_running = false
	run_ended.emit(reason)


## Reset complet. Pas de persistance entre runs.
func reset() -> void:
	_players.clear()
	is_running = false


func has_player(player_id: int) -> bool:
	return _players.has(player_id)


func get_player_ids() -> Array:
	return _players.keys()


func get_player_state(player_id: int) -> Dictionary:
	return _players.get(player_id, {})


## Note : pas `get_class` car conflit avec Object.get_class().
func get_class_data(player_id: int) -> ClassData:
	var p: Dictionary = _players.get(player_id, {})
	return p.get("class_data", null)


func get_weapon_data(player_id: int) -> WeaponData:
	var p: Dictionary = _players.get(player_id, {})
	return p.get("weapon_data", null)


func get_spell_data(player_id: int) -> SpellData:
	var p: Dictionary = _players.get(player_id, {})
	return p.get("spell_data", null)


func get_xp(player_id: int) -> int:
	var p: Dictionary = _players.get(player_id, {})
	return p.get("xp", 0)


func get_level(player_id: int) -> int:
	var p: Dictionary = _players.get(player_id, {})
	return p.get("level", 1)


## Ajoute de l'XP à un joueur. Peut déclencher plusieurs level-ups en chaine
## si `amount` est gros. Émet player_leveled_up à chaque palier puis
## player_xp_changed avec le reste.
func add_xp(player_id: int, amount: int) -> void:
	if amount <= 0 or not _players.has(player_id):
		return
	var p: Dictionary = _players[player_id]
	p["xp"] = p.get("xp", 0) + amount
	var threshold: int = xp_threshold_for_level(p.get("level", 1))
	while p["xp"] >= threshold:
		p["xp"] -= threshold
		p["level"] = p.get("level", 1) + 1
		player_leveled_up.emit(player_id, p["level"])
		threshold = xp_threshold_for_level(p["level"])
	player_xp_changed.emit(player_id, p["xp"], threshold)


## Seuil d'XP pour passer du niveau N au N+1. Linéaire pour le POC, à
## remplacer par une courbe (#39 final).
func xp_threshold_for_level(level: int) -> int:
	return 100 * level


func set_player_class(player_id: int, class_data: ClassData) -> void:
	if not _players.has(player_id):
		return
	_players[player_id]["class_data"] = class_data
	loadout_changed.emit(player_id)


func set_player_weapon(player_id: int, weapon: WeaponData) -> void:
	if not _players.has(player_id):
		return
	_players[player_id]["weapon_data"] = weapon
	loadout_changed.emit(player_id)


func set_player_spell(player_id: int, spell: SpellData) -> void:
	if not _players.has(player_id):
		return
	_players[player_id]["spell_data"] = spell
	loadout_changed.emit(player_id)

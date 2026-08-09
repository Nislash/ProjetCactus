class_name CharacterVisual
extends Node3D

## Wrapper modulaire de visuel personnage. Au _ready(), instancie le
## CharacterAnimSet.model_scene comme enfant, puis pour chaque clip d'anim
## du set : instancie temporairement le .glb d'anim, extrait son Animation
## du AnimationPlayer interne, et l'ajoute à un AnimationPlayer unique
## monté sur ce node. Les .glb d'anim temporaires sont free()d.
##
## Hypothèse : tous les .glb du pack (model + anims) partagent la même
## structure de skeleton (cas typique d'un pack Meshy). Si une anim n'a
## qu'un seul clip, on l'ajoute sous le nom logique (idle/walk/...). Si elle
## en a plusieurs, on les ajoute tous préfixés par le nom logique.
##
## Pour le player en FPS : laisse `hide_for_local_player = true` et appelle
## set_local_player(true) — le visuel devient invisible pour la caméra du
## propriétaire mais reste visible dans les caméras des autres joueurs.

signal animation_finished(anim_name: StringName)

@export var anim_set: CharacterAnimSet
## Si true, on affiche le shadow et les autres viewports voient le model
## mais la caméra locale du player ne le voit pas (utile en FPS). Cf
## set_local_player().
@export var hide_for_local_player: bool = false

## Matériau appliqué à TOUS les mesh du modèle instancié, en override.
##
## C'est le seul moyen d'habiller un personnage dont le `.glb` est chargé à
## l'exécution : on ne peut pas poser un `material_override` dans la scène sur
## un nœud qui n'existe pas encore. Laisser vide = le modèle garde ses propres
## matériaux.
@export var model_material_override: Material = null

const LIB_NAME: StringName = &"char"

var _model: Node3D = null
var _anim_player: AnimationPlayer = null
var _current_state: StringName = &""


func _ready() -> void:
	if anim_set == null:
		push_warning("CharacterVisual sans anim_set — node vide")
		return
	_build()


## Permet de swap le pack à chaud (test / debug). Reconstruit tout.
func set_anim_set(new_set: CharacterAnimSet) -> void:
	anim_set = new_set
	if is_inside_tree():
		_build()


func _build() -> void:
	# Cleanup précédent
	if _model != null and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	_anim_player = null

	if anim_set == null or anim_set.model_scene == null:
		return

	_model = anim_set.model_scene.instantiate() as Node3D
	if _model == null:
		push_warning("CharacterAnimSet.model_scene n'est pas une Node3D")
		return
	add_child(_model)
	if anim_set.scale != 1.0:
		_model.scale = Vector3.ONE * anim_set.scale
	if anim_set.y_offset != 0.0:
		_model.position.y = anim_set.y_offset
	if anim_set.y_rotation_deg != 0.0:
		_model.rotation.y = deg_to_rad(anim_set.y_rotation_deg)

	if model_material_override != null:
		_apply_material_override(_model)

	# Trouver / créer l'AnimationPlayer cible.
	_anim_player = _find_animation_player(_model)
	if _anim_player == null:
		_anim_player = AnimationPlayer.new()
		_anim_player.name = "AnimationPlayer"
		_model.add_child(_anim_player)

	# Vider la lib par défaut (la T-pose interne du .glb model)
	_install_animation_library()
	_anim_player.animation_finished.connect(_on_anim_finished)

	# Lance idle par défaut si dispo
	if _anim_player.has_animation(_full_name(&"idle")):
		play_state(&"idle")


## Change l'habillage à chaud, sans reconstruire les animations.
func set_model_material_override(mat: Material) -> void:
	model_material_override = mat
	if _model != null and is_instance_valid(_model):
		_apply_material_override(_model)


func _apply_material_override(node: Node) -> void:
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null:
		mesh.material_override = model_material_override
	for child in node.get_children():
		_apply_material_override(child)


## LA TABLE DE REPLI. Ce qu'on joue quand l'état demandé n'existe pas.
##
## Elle est la raison pour laquelle aucune animation n'est obligatoire : un
## personnage livré avec trois clips reste jouable, il se contente d'être moins
## expressif. Sans elle, il faudrait produire les trente animations avant de
## pouvoir seulement voir un nouveau personnage bouger.
##
## Chaque chaîne va du plus précis au plus générique, et se termine sur un état
## que tout le monde a. On ne descend jamais vers un état d'une autre famille :
## un tir qui retomberait sur une course afficherait un personnage qui court
## sans tirer, ce qui ment sur ce qu'il fait.
const FALLBACKS := {
	&"shoot_idle": [&"shoot_walk_forward", &"shoot_run", &"idle"],
	&"shoot_walk_forward": [&"shoot_run", &"shoot_idle", &"walk"],
	&"shoot_walk_back": [&"shoot_walk_forward", &"shoot_idle", &"walk"],
	&"shoot_run": [&"shoot_walk_forward", &"shoot_idle", &"run"],
	&"run_back": [&"run", &"walk", &"idle"],
	&"run_left": [&"run_forward_left", &"run", &"walk", &"idle"],
	&"run_right": [&"run_forward_right", &"run", &"walk", &"idle"],
	&"run_forward_left": [&"run", &"walk", &"idle"],
	&"run_forward_right": [&"run", &"walk", &"idle"],
	&"run": [&"walk", &"idle"],
	&"walk": [&"run", &"idle"],
	&"dash_left": [&"dash", &"dash_right"],
	&"dash_right": [&"dash", &"dash_left"],
	&"dash_back": [&"dash"],
	&"downed_crawl": [&"downed_idle", &"death"],
	&"downed_idle": [&"death", &"idle"],
	&"get_up": [&"idle"],
	&"death": [&"downed_idle", &"idle"],
	&"land": [&"idle"],
	&"fall_loop": [&"jump", &"idle"],
	&"jump_start": [&"jump", &"idle"],
}


## L'état réellement jouable pour l'état demandé.
##
## Retourne une chaîne vide si rien de la chaîne n'existe — l'appelant doit
## alors ne rien faire, plutôt que de jouer n'importe quoi.
func resolve_state(wanted: StringName) -> StringName:
	if has_state(wanted):
		return wanted
	if not FALLBACKS.has(wanted):
		return &""
	for candidate in FALLBACKS[wanted]:
		if has_state(candidate):
			return candidate
	return &""


func _install_animation_library() -> void:
	# La bibliothèque préparée court-circuite tout : elle porte déjà les
	# animations sous leur nom d'état.
	if anim_set.library != null:
		for existing in _anim_player.get_animation_library_list():
			_anim_player.remove_animation_library(existing)
		var baked: AnimationLibrary = anim_set.library.duplicate(true) as AnimationLibrary
		for state in baked.get_animation_list():
			var clip: Animation = baked.get_animation(state)
			clip.loop_mode = Animation.LOOP_LINEAR if _loops(state) \
				else Animation.LOOP_NONE
		_anim_player.add_animation_library(LIB_NAME, baked)
		return

	var lib: AnimationLibrary = AnimationLibrary.new()
	for entry in anim_set.iter_clips():
		var state_name: StringName = entry[0]
		var packed: PackedScene = entry[1]
		var anim: Animation = _extract_animation(packed)
		if anim == null:
			push_warning("CharacterVisual: anim %s introuvable dans le .glb" % state_name)
			continue
		anim.loop_mode = Animation.LOOP_LINEAR if _loops(state_name) \
			else Animation.LOOP_NONE
		lib.add_animation(StringName(state_name), anim)
	# Vire toute lib existante puis ajoute la nôtre.
	for ln in _anim_player.get_animation_library_list():
		_anim_player.remove_animation_library(ln)
	_anim_player.add_animation_library(LIB_NAME, lib)


## Cet état boucle-t-il ?
##
## La locomotion et les postures d'attente bouclent ; tout le reste est joué
## une fois. Une esquive ou un relèvement qui boucle donne un personnage pris
## de convulsions — c'est le genre d'erreur qu'on ne voit qu'en jeu.
func _loops(state: StringName) -> bool:
	if not anim_set.loop_locomotion:
		return false
	return state in [
		&"idle", &"walk", &"run",
		&"run_back", &"run_left", &"run_right",
		&"run_forward_left", &"run_forward_right",
		&"shoot_idle", &"shoot_walk_forward", &"shoot_walk_back", &"shoot_run",
		&"downed_idle", &"downed_crawl", &"crouch_idle", &"fall_loop",
	]


## Charge le .glb d'anim, en extrait la première Animation du premier
## AnimationPlayer trouvé, retourne une copie indépendante (duplicate).
func _extract_animation(packed: PackedScene) -> Animation:
	var temp: Node = packed.instantiate()
	if temp == null:
		return null
	var ap: AnimationPlayer = _find_animation_player(temp)
	if ap == null:
		temp.queue_free()
		return null
	var names: PackedStringArray = ap.get_animation_list()
	if names.is_empty():
		temp.queue_free()
		return null
	var anim: Animation = ap.get_animation(names[0])
	var copy: Animation = anim.duplicate(true)
	temp.queue_free()
	return copy


func _find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root
	for c in root.get_children():
		var found: AnimationPlayer = _find_animation_player(c)
		if found != null:
			return found
	return null


func _full_name(state: StringName) -> StringName:
	return StringName("%s/%s" % [LIB_NAME, state])


## Joue un état (idle/walk/run/...). No-op si l'état n'existe pas dans la lib.
func play_state(state: StringName, custom_blend: float = 0.15, speed: float = 1.0) -> void:
	if _anim_player == null:
		return
	var full: StringName = _full_name(state)
	if not _anim_player.has_animation(full):
		return
	if _current_state == state and _anim_player.is_playing():
		return
	_current_state = state
	_anim_player.play(full, custom_blend, speed)


## Joue un état one-shot (death, melee_combo, jump). Émet animation_finished
## avec le nom logique quand terminé.
func play_oneshot(state: StringName, custom_blend: float = 0.05, speed: float = 1.0) -> void:
	if _anim_player == null:
		return
	var full: StringName = _full_name(state)
	if not _anim_player.has_animation(full):
		return
	_current_state = state
	_anim_player.play(full, custom_blend, speed)


func get_current_state() -> StringName:
	return _current_state


func has_state(state: StringName) -> bool:
	if _anim_player == null:
		return false
	return _anim_player.has_animation(_full_name(state))


func get_anim_player() -> AnimationPlayer:
	return _anim_player


## Bascule la visibilité locale en FPS. En split-screen, chaque caméra a
## son propre `cull_mask` ; ici on choisit l'approche simple : cache le
## node entier pour le viewport local (le SplitScreenManager gère le cull
## via layers, à venir). Pour le moment, on toggle visible.
func set_local_player(is_local: bool) -> void:
	if _model == null:
		return
	if hide_for_local_player and is_local:
		_model.visible = false
	else:
		_model.visible = true


func _on_anim_finished(anim_name: StringName) -> void:
	# anim_name est full ("char/idle") → on émet juste le state logique.
	var s: String = String(anim_name)
	var sep: int = s.find("/")
	var logical: StringName = StringName(s.substr(sep + 1)) if sep >= 0 else StringName(s)
	animation_finished.emit(logical)

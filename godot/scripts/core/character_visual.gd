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


func _install_animation_library() -> void:
	var lib: AnimationLibrary = AnimationLibrary.new()
	for entry in anim_set.iter_clips():
		var state_name: StringName = entry[0]
		var packed: PackedScene = entry[1]
		var anim: Animation = _extract_animation(packed)
		if anim == null:
			push_warning("CharacterVisual: anim %s introuvable dans le .glb" % state_name)
			continue
		# Loop policy : locomotion bouclée par défaut.
		if anim_set.loop_locomotion and state_name in [&"idle", &"walk", &"run", &"shoot_walk_forward", &"shoot_walk_back", &"shoot_run"]:
			anim.loop_mode = Animation.LOOP_LINEAR
		else:
			anim.loop_mode = Animation.LOOP_NONE
		lib.add_animation(StringName(state_name), anim)
	# Vire toute lib existante puis ajoute la nôtre.
	for ln in _anim_player.get_animation_library_list():
		_anim_player.remove_animation_library(ln)
	_anim_player.add_animation_library(LIB_NAME, lib)


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

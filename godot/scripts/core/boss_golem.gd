class_name BossGolem
extends BossBase

## Golem de cristal. Boss POC du niveau 1. Hérite de BossBase qui gère la
## machine à états 3 phases, la résistance status, le combo recipe.
##
## Pour le POC : boss_data est préchargé ici. À terme, un BossSpawner ou
## le RunState injectera le BossData selon le niveau.
##
## HABILLAGE (tâche #23). Le Golem emprunte le squelette et les dix
## animations du mannequin « Sentinel ». Lui générer un corps neuf
## imposerait de le rigger et de recibler les animations : beaucoup de
## travail, et un risque réel sur la hitbox. On l'habille donc par
## matériau — roche sombre et veines de cristal — ce qui laisse le rig,
## la collision et l'IA strictement intacts.
##
## Les veines portent aussi l'information de combat. Elles sont cyan au
## repos, virent vers l'orange de danger quand le boss s'enrage, et
## battent pendant le telegraph d'une attaque. C'est le même vocabulaire
## que les decals au sol (art bible §3 : le chaud est réservé au danger),
## donc lisible en quart d'écran sans rien lire.

const _GOLEM_DATA: Resource = preload("res://resources/bosses/boss_data_golem.tres")
const _SKIN_MATERIAL: ShaderMaterial = preload("res://data/bosses/golem_crystal_material.tres")
const _SHARD_MATERIAL: ShaderMaterial = preload("res://data/bosses/golem_shard_material.tres")

## Chaleur des veines par phase. P1 froid, P2 tiède, P3 le cœur est ouvert.
const _HEAT_BY_PHASE: Dictionary = {
	Phase.PHASE_1: 0.0,
	Phase.TRANSITION_1_TO_2: 0.35,
	Phase.PHASE_2: 0.35,
	Phase.TRANSITION_2_TO_3: 1.0,
	Phase.PHASE_3_ENRAGE: 1.0,
}

## Le corps ET les éclats. Tous chauffent et battent ensemble : un éclat
## resté cyan pendant que le corps s'embrase relirait comme un bug.
var _skins: Array[ShaderMaterial] = []
var _chest_crystal: MeshInstance3D
var _heat: float = 0.0
var _heat_tween: Tween
var _pulse_tween: Tween


func _ready() -> void:
	if boss_data == null:
		boss_data = _GOLEM_DATA
	super._ready()
	_dress()


## Applique le matériau au modèle instancié par le CharacterVisual.
##
## Le matériau est DUPLIQUÉ : un `.tres` est partagé par toutes les
## instances qui le chargent, et l'animer en place teinterait n'importe
## quel autre objet qui viendrait à s'en servir.
func _dress() -> void:
	_skins.clear()

	var visual: CharacterVisual = get_node_or_null(^"Visual") as CharacterVisual
	if visual == null:
		push_warning("BossGolem : pas de nœud Visual — le boss reste en peau de test.")
	else:
		var skin: ShaderMaterial = _SKIN_MATERIAL.duplicate() as ShaderMaterial
		# Le CharacterVisual est un enfant : il s'est construit avant ce
		# _ready, donc on passe par le setter à chaud plutôt que par l'export.
		visual.set_model_material_override(skin)
		_skins.append(skin)

	# Les éclats affleurants — dos et poitrine. Chacun sa copie, pour la même
	# raison que la peau.
	for node_name in [^"CrystalBack", ^"CrystalChest"]:
		var shard: MeshInstance3D = get_node_or_null(node_name) as MeshInstance3D
		if shard == null:
			continue
		var mat: ShaderMaterial = _SHARD_MATERIAL.duplicate() as ShaderMaterial
		shard.material_override = mat
		_skins.append(mat)

	_chest_crystal = get_node_or_null(^"CrystalChest") as MeshInstance3D
	_set_param("heat", 0.0)
	_set_param("pulse", 0.0)


func _set_param(name: String, value: float) -> void:
	for mat in _skins:
		mat.set_shader_parameter(name, value)


func _set_heat(value: float, duration: float) -> void:
	if _skins.is_empty():
		return
	if _heat_tween != null and _heat_tween.is_valid():
		_heat_tween.kill()
	if duration <= 0.0:
		_heat = value
		_set_param("heat", value)
		return
	_heat_tween = create_tween()
	_heat_tween.tween_method(
		func(v: float) -> void:
			_heat = v
			_set_param("heat", v),
		_heat,
		value,
		duration,
	)


## Le battement du telegraph. Monte vite (l'alerte doit précéder le coup),
## redescend sur toute la durée du windup : quand la lueur s'éteint, l'attaque
## part. Le joueur peut lire le timing sans compter.
func _on_attack_windup(_attack_name: String, _target_pos: Vector3, duration: float, _radius: float) -> void:
	if _skins.is_empty():
		return
	if _pulse_tween != null and _pulse_tween.is_valid():
		_pulse_tween.kill()
	var set_pulse: Callable = func(v: float) -> void: _set_param("pulse", v)
	_pulse_tween = create_tween()
	_pulse_tween.tween_method(set_pulse, 0.0, 1.6, minf(0.12, duration * 0.25))
	_pulse_tween.tween_method(set_pulse, 1.6, 0.0, maxf(0.05, duration * 0.75))


## Remplace le comportement de BossBase, qui repeignait le nœud `Mesh` — une
## capsule laissée invisible depuis que le boss a un vrai modèle. L'enrage ne
## se voyait donc nulle part.
func _apply_enrage_visual() -> void:
	_set_heat(1.0, 0.6)


func _set_phase(new_phase: int) -> void:
	super._set_phase(new_phase)
	if _HEAT_BY_PHASE.has(new_phase):
		_set_heat(float(_HEAT_BY_PHASE[new_phase]), 0.6)
	# « Le Cœur ouvert » (encounters §5) : l'éclat de poitrine n'apparaît
	# qu'en P3. C'est ce qui rend le point faible visible — et le dilemme du
	# tir ami lisible, puisqu'il faut se placer face au boss pour l'atteindre.
	if _chest_crystal != null:
		_chest_crystal.visible = (new_phase == Phase.PHASE_3_ENRAGE)


## Lecture de l'habillage pour les tests — les matériaux sont dupliqués, donc
## introuvables depuis les `.tres` d'origine.
func get_skin_materials() -> Array[ShaderMaterial]:
	return _skins


func get_heat() -> float:
	return _heat

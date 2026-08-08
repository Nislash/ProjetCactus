class_name LakeBeam
extends Node3D

## Le trait de lumière du verrou : le Pilier de l'Îlot se charge, tire vers la
## Brèche, et la salle du boss s'éclaire.
##
## ## Pourquoi cette mise en scène existe
##
## Résoudre B‑O‑S‑S ouvrait deux passages situés à **deux cents mètres** du lac
## où l'on vient de poser le dernier éclat. Le joueur entendait la pierre
## tomber, ne voyait rien, et devait croire sur parole que quelque chose avait
## changé. C'est le seul moment du niveau où il fallait relier les deux
## extrémités de la caverne **à l'écran**.
##
## Trois temps, et chacun répond à une question du joueur :
##
## 1. **La charge** (1,4 s) — « ça a marché ? ». Le pilier aspire la lumière,
##    l'anneau au sol se resserre.
## 2. **Le tir** (0,5 s) — « et alors ? ». Le trait monte d'un coup vers la
##    Brèche : le regard suit, et découvre la voûte.
## 3. **La retombée** (2,2 s) — « où dois-je aller ? ». La lumière redescend
##    sur la salle du boss et l'y laisse allumée. La réponse est un lieu.

## Où la lumière retombe. C'est le bol de l'arène (cf `build_cavern_terrain`).
const ARENA_CENTER := Vector2(100.0, -52.0)

## Sommet du trait, au-dessus du lac.
const BEAM_TOP := 46.0

const CHARGE_TIME := 1.4
const SHOT_TIME := 0.5
const FALL_TIME := 2.2

var _core: MeshInstance3D
var _core_material: StandardMaterial3D
var _charge_light: OmniLight3D
var _arena_light: OmniLight3D


## Déclenche la séquence. `world` sert à retrouver le pilier et le terrain ;
## `gate` est le Seuil qui vient de tomber, dont on prend la position pour
## viser juste — si la topographie bouge, la lumière suit.
func fire(world: Node3D, gate: Node) -> void:
	var pillar: Node3D = world.find_child("PilierIlot", true, false) as Node3D
	var base: Vector3 = pillar.global_position if pillar != null else Vector3.ZERO

	_build_core(base)
	_build_lights(base, gate)

	var tween: Tween = create_tween()
	# 1. La charge : le cœur s'allume, l'air se tend.
	tween.tween_method(_set_charge, 0.0, 1.0, CHARGE_TIME) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN)
	# 2. Le tir : le trait jaillit vers la voûte.
	tween.tween_method(_set_beam, 0.0, 1.0, SHOT_TIME) \
		.set_trans(Tween.TRANS_EXPO).set_ease(Tween.EASE_OUT)
	# 3. La retombée : la salle du boss s'éclaire et le reste.
	tween.tween_method(_set_arena_glow, 0.0, 1.0, FALL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	# Le trait s'efface ; la salle, elle, reste allumée.
	tween.parallel().tween_method(_set_beam, 1.0, 0.0, FALL_TIME) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)


func _build_core(base: Vector3) -> void:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.55
	mesh.bottom_radius = 0.9
	mesh.height = BEAM_TOP
	mesh.radial_segments = 8

	_core_material = StandardMaterial3D.new()
	_core_material.albedo_color = Color(
		CrystalGrammar.COLOR_BOSS_LOCK.r, CrystalGrammar.COLOR_BOSS_LOCK.g,
		CrystalGrammar.COLOR_BOSS_LOCK.b, 0.55)
	_core_material.emission_enabled = true
	_core_material.emission = CrystalGrammar.COLOR_BOSS_LOCK
	_core_material.emission_energy_multiplier = 0.0
	_core_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	# Sans culling : on doit pouvoir être DANS le faisceau et le voir encore.
	_core_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Pas d'ombre portée : un trait de lumière qui projette une ombre est un
	# objet, pas de la lumière.
	_core_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	_core = MeshInstance3D.new()
	_core.name = "Trait"
	_core.mesh = mesh
	_core.material_override = _core_material
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_core)
	_core.global_position = base + Vector3(0.0, BEAM_TOP * 0.5, 0.0)
	_core.scale = Vector3(1.0, 0.001, 1.0)


func _build_lights(base: Vector3, gate: Node) -> void:
	_charge_light = CrystalGrammar.make_glow(CrystalGrammar.COLOR_BOSS_LOCK, 0.0, 34.0)
	_charge_light.name = "Charge"
	add_child(_charge_light)
	_charge_light.global_position = base + Vector3(0.0, 6.0, 0.0)

	# La lumière qui reste sur la salle du boss. Posée haut : elle doit
	# descendre du trou de voûte, pas monter du sol.
	_arena_light = OmniLight3D.new()
	_arena_light.name = "LueurArene"
	_arena_light.light_color = CrystalGrammar.COLOR_BOSS_LOCK
	_arena_light.light_energy = 0.0
	_arena_light.omni_range = 90.0
	_arena_light.shadow_enabled = false
	add_child(_arena_light)
	var target := Vector3(ARENA_CENTER.x, 24.0, ARENA_CENTER.y)
	if gate is Node3D:
		# Le Seuil est sur le chemin de l'arène : on prend son altitude comme
		# référence plutôt qu'un chiffre écrit à la main.
		target.y = (gate as Node3D).global_position.y + 26.0
	_arena_light.global_position = target


func _set_charge(t: float) -> void:
	if _charge_light != null:
		_charge_light.light_energy = t * 7.0
	if _core_material != null:
		_core_material.emission_energy_multiplier = t * 1.2


func _set_beam(t: float) -> void:
	if _core != null:
		_core.scale = Vector3(1.0, maxf(t, 0.001), 1.0)
	if _core_material != null:
		_core_material.emission_energy_multiplier = 1.2 + t * 5.0


func _set_arena_glow(t: float) -> void:
	if _arena_light != null:
		_arena_light.light_energy = t * 5.5
	if _charge_light != null:
		_charge_light.light_energy = (1.0 - t) * 7.0


## Lecture pour les tests.
func get_arena_light() -> OmniLight3D:
	return _arena_light

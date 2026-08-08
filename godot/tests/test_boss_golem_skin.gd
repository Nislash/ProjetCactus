extends SceneTree

## Habillage du Boss Golem (E4 #23). Lancer via :
##   godot --headless --path godot --script tests/test_boss_golem_skin.gd
##
## Ce que ce test défend, dans l'ordre d'importance :
##
## 1. **Le shader expose bien ses uniformes.** Un shader qui ne compile plus
##    n'annonce rien : les matériaux tournent sur les valeurs par défaut, le
##    boss reste gris, et RIEN dans la console ne le dit. C'est déjà arrivé
##    sur la roche de la caverne (un `return` dans `fragment()`), et ça a
##    coûté cher à diagnostiquer.
## 2. **L'habillage atteint le modèle.** Le `.glb` est instancié à
##    l'exécution : un `material_override` posé dans la scène ne l'atteindrait
##    pas, il faut passer par `CharacterVisual`.
## 3. **La hitbox et l'IA sont intactes.** C'est la condition de la tâche :
##    on habille sans rien casser.
## 4. **La chaleur suit les phases** et le point faible n'apparaît qu'en P3.

const GOLEM_SCENE := "res://scenes/boss/boss_golem.tscn"
const SHADER_PATH := "res://shaders/golem_crystal.gdshader"

## Valeurs de `BossBase.Phase`, recopiées à la main. Nommer le type ici
## forcerait `boss_base.gd` à compiler pendant la compilation de CE script,
## c'est-à-dire AVANT que les autoloads existent — et toute la chaîne
## (PlayerController → InputRouter, BossBase → RelicLootTable) échouerait.
const PHASE_1: int = 1
const PHASE_2: int = 3
const PHASE_3_ENRAGE: int = 5

var _golem: Node3D


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var failed: int = 0
	failed += _test_shader_exposes_its_uniforms()

	var packed: PackedScene = load(GOLEM_SCENE) as PackedScene
	if packed == null:
		print("[FAIL] scène introuvable : %s" % GOLEM_SCENE)
		quit(1)
		return
	_golem = packed.instantiate() as Node3D
	if _golem == null or not _golem.has_method("get_skin_materials"):
		print("[FAIL] la scène n'instancie pas un BossGolem habillable")
		quit(1)
		return
	root.add_child(_golem)
	await process_frame

	failed += _test_the_model_is_dressed()
	failed += _test_hitbox_and_ai_untouched()
	failed += await _test_heat_follows_the_phases()
	failed += _test_the_weak_point_shows_only_in_phase_3()

	if failed > 0:
		print("\n[TESTS] %d test(s) échoué(s)" % failed)
		quit(1)
	else:
		print("\n[TESTS] OK — le Golem est habillé, sa hitbox et son IA intactes")
		quit(0)


## Le test le plus important : un shader cassé est SILENCIEUX.
func _test_shader_exposes_its_uniforms() -> int:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		print("[FAIL] shader introuvable : %s" % SHADER_PATH)
		return 1
	var uniforms: Array = shader.get_shader_uniform_list()
	if uniforms.is_empty():
		print("[FAIL] shader : 0 uniforme exposé — il ne compile pas")
		return 1
	var names: Array[String] = []
	for u in uniforms:
		names.append(String(u["name"]))
	for required in ["heat", "pulse", "vein_color", "danger_color"]:
		if not names.has(required):
			print("[FAIL] shader : uniforme « %s » absent" % required)
			return 1
	print("[OK] shader_exposes_its_uniforms (%d uniformes)" % uniforms.size())
	return 0


func _test_the_model_is_dressed() -> int:
	var skins: Array = _golem.get_skin_materials()
	if skins.size() < 3:
		print("[FAIL] habillage : %d matériaux appliqués, attendu 3 (corps + 2 éclats)"
			% skins.size())
		return 1

	# Le modèle est instancié à l'exécution : on vérifie que l'override est
	# bien descendu jusqu'aux mesh, et pas seulement rangé dans une variable.
	var visual: Node = _golem.get_node_or_null(^"Visual")
	if visual == null:
		print("[FAIL] habillage : pas de nœud Visual")
		return 1
	var dressed: int = _count_dressed_meshes(visual)
	if dressed == 0:
		print("[FAIL] habillage : aucun mesh du modèle n'a reçu l'override")
		return 1

	# Chaque matériau est une COPIE : muter le .tres partagé teindrait tout
	# objet qui viendrait à s'en servir.
	var source: Resource = load("res://data/bosses/golem_crystal_material.tres")
	for mat in skins:
		if mat == source:
			print("[FAIL] habillage : le .tres source est utilisé tel quel, pas dupliqué")
			return 1

	print("[OK] the_model_is_dressed (%d mesh du modèle + 2 éclats)" % dressed)
	return 0


func _count_dressed_meshes(node: Node) -> int:
	var n: int = 0
	var mesh: MeshInstance3D = node as MeshInstance3D
	if mesh != null and mesh.material_override != null:
		n += 1
	for child in node.get_children():
		n += _count_dressed_meshes(child)
	return n


## La condition de la tâche : habiller sans casser.
func _test_hitbox_and_ai_untouched() -> int:
	var shape: CollisionShape3D = _golem.get_node_or_null(^"CollisionShape3D") as CollisionShape3D
	if shape == null or shape.shape == null:
		print("[FAIL] hitbox : CollisionShape3D absent ou vide")
		return 1
	var capsule: CapsuleShape3D = shape.shape as CapsuleShape3D
	if capsule == null:
		print("[FAIL] hitbox : la forme n'est plus une capsule")
		return 1
	var ai: Node = _golem.get_node_or_null(^"BossAI")
	if ai == null:
		print("[FAIL] IA : nœud BossAI absent — la lib Rust est-elle compilée ?")
		return 1
	print("[OK] hitbox_and_ai_untouched (capsule r=%.2f h=%.2f, BossAI présent)"
		% [capsule.radius, capsule.height])
	return 0


func _test_heat_follows_the_phases() -> int:
	_golem._set_phase(PHASE_1)
	await _settle(0.0)
	if _golem.get_heat() > 0.01:
		print("[FAIL] chaleur : %.2f en P1, le boss devrait être froid" % _golem.get_heat())
		return 1

	_golem._set_phase(PHASE_3_ENRAGE)
	await _settle(1.0)
	var hot: float = _golem.get_heat()
	if hot < 0.99:
		print("[FAIL] chaleur : %.2f en P3, l'enrage ne se voit pas" % hot)
		return 1

	# Et la valeur doit avoir atteint les matériaux, pas seulement la variable.
	for mat in _golem.get_skin_materials():
		var v: float = float(mat.get_shader_parameter("heat"))
		if v < 0.99:
			print("[FAIL] chaleur : un matériau est resté à %.2f" % v)
			return 1

	print("[OK] heat_follows_the_phases (P1 froid → P3 à %.2f)" % hot)
	return 0


func _test_the_weak_point_shows_only_in_phase_3() -> int:
	var chest: MeshInstance3D = _golem.get_node_or_null(^"CrystalChest") as MeshInstance3D
	if chest == null:
		print("[FAIL] point faible : CrystalChest absent")
		return 1
	# On sort de P3 (le test précédent y a laissé le boss).
	_golem._set_phase(PHASE_2)
	if chest.visible:
		print("[FAIL] point faible : visible dès la P2")
		return 1
	_golem._set_phase(PHASE_3_ENRAGE)
	if not chest.visible:
		print("[FAIL] point faible : invisible en P3 — « le Cœur ouvert » ne se voit pas")
		return 1
	print("[OK] the_weak_point_shows_only_in_phase_3")
	return 0


## Laisse le tween de chaleur arriver au bout. En headless la boucle tourne
## à vide, donc le delta n'a rien à voir avec 1/60 s : on attend la VALEUR,
## pas un nombre de frames.
func _settle(target: float) -> void:
	for i in 4000:
		if absf(_golem.get_heat() - target) < 0.001:
			return
		await process_frame

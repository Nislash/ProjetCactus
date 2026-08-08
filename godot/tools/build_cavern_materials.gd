extends SceneTree

## Écrit les matériaux du terrain de la caverne (E3 #17). Lancer via :
##   godot --headless --path godot --script tools/build_cavern_materials.gd
##
## Trois matériaux dérivés du MÊME shader tri-planaire procédural
## (`shaders/cavern_rock.gdshader`), différenciés par leurs paramètres :
##   - sol   : givre marqué (le givre tient sur le plat), grain moyen
##   - parois: pas de givre (surfaces verticales), grain plus grossier
##   - voûte : plus sombre encore, grain large — elle est vue de loin et de
##             dessous, tout détail fin y serait invisible
##
## Un seul shader pour trois matériaux : une seule compilation, trois jeux de
## paramètres. C'est ce qui garde le coût de rendu bas en 4-split.

const SHADER_PATH := "res://shaders/cavern_rock.gdshader"
const OUT_DIR := "res://data/levels/"


func _init() -> void:
	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		push_error("Shader introuvable : %s" % SHADER_PATH)
		quit(1)
		return

	var floor_material := _make(shader, {
		"macro_scale": 0.10, "detail_scale": 0.95, "detail_strength": 0.45,
		"frost_slope_threshold": 0.70, "frost_amount": 0.60,
		"rock_roughness": 0.90,
	})
	var wall_material := _make(shader, {
		"macro_scale": 0.07, "detail_scale": 0.70, "detail_strength": 0.55,
		# Aucun givre sur les parois : un seuil de pente à 1.0 le désactive de
		# fait, puisqu'aucune normale verticale n'existe sur un mur.
		"frost_slope_threshold": 0.95, "frost_amount": 0.10,
		"rock_roughness": 0.94,
	})
	var vault_material := _make(shader, {
		"macro_scale": 0.05, "detail_scale": 0.45, "detail_strength": 0.35,
		"frost_slope_threshold": 0.95, "frost_amount": 0.0,
		"rock_roughness": 0.96,
		# La voûte est le fond de tous les plans : plus sombre, elle laisse les
		# cristaux se détacher.
		"rock_color": Color(0.075, 0.106, 0.157),
		"rock_highlight": Color(0.141, 0.184, 0.243),
	})

	var saved: int = 0
	for pair in [["cavern_floor", floor_material], ["cavern_wall", wall_material], ["cavern_vault", vault_material]]:
		var path: String = "%s%s_material.tres" % [OUT_DIR, pair[0]]
		if ResourceSaver.save(pair[1], path) != OK:
			push_error("Échec d'écriture : %s" % path)
			quit(1)
			return
		print("[materials] écrit : %s" % path)
		saved += 1
	print("[materials] %d matériaux produits depuis un seul shader." % saved)
	quit(0)


func _make(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in params:
		material.set_shader_parameter(key, params[key])
	return material

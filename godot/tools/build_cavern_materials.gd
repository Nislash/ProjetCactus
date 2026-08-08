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

	# Les valeurs ci-dessous ont ete CORRIGEES apres capture (2026-08-08) : la
	# premiere passe rendait une roche parfaitement plate. Trois causes, toutes
	# reelles :
	#   - echelles de bruit trop grandes (un motif de ~11 m se lit comme un
	#     degrade lisse, pas comme de la roche) ;
	#   - couleurs trop sombres sous une ambiante faible : la roche tombait
	#     dans le noir et l'ecran n'affichait plus que du brouillard ;
	#   - amplitude de relief insuffisante pour que les normales accrochent.
	var floor_material := _make(shader, {
		"macro_scale": 0.28, "detail_scale": 2.4, "detail_strength": 0.80,
		# GIVRE FORTEMENT REDUIT (0,55 -> 0,12) et seuil de pente releve.
		# A 0,55 sur un sol majoritairement horizontal, le givre couvrait la
		# quasi-totalite de la surface et la roche disparaissait sous un aplat
		# blanc : le sol se lisait comme un champ de neige, pas comme de la
		# pierre. Le givre doit etre un ACCENT par plaques, pas une couche.
		"frost_slope_threshold": 0.74, "frost_amount": 0.34,
		"rock_roughness": 0.88,
		"deep_color": Color(0.038, 0.055, 0.080),
		"rock_color": Color(0.105, 0.140, 0.195),
		"rock_highlight": Color(0.235, 0.295, 0.375),
		"blend_sharpness": 4.0,
	})
	var wall_material := _make(shader, {
		# Grain plus grossier sur les parois : elles sont vues de loin et en
		# silhouette, un grain fin y disparaitrait.
		"macro_scale": 0.18, "detail_scale": 1.6, "detail_strength": 0.85,
		# Aucun givre sur les parois : un seuil de pente eleve le desactive de
		# fait, puisqu'aucune normale verticale n'existe sur un mur.
		"frost_slope_threshold": 0.95, "frost_amount": 0.10,
		"rock_roughness": 0.94,
		"deep_color": Color(0.030, 0.044, 0.066),
		"rock_color": Color(0.095, 0.128, 0.180),
		"rock_highlight": Color(0.205, 0.260, 0.335),
		"blend_sharpness": 3.0,
	})
	var vault_material := _make(shader, {
		"macro_scale": 0.22, "detail_scale": 1.9, "detail_strength": 0.90,
		"frost_slope_threshold": 0.95, "frost_amount": 0.0,
		"rock_roughness": 0.96,
		# La voute est le fond de tous les plans : plus sombre que le reste,
		# elle laisse les cristaux se detacher.
		"deep_color": Color(0.022, 0.032, 0.050),
		"rock_color": Color(0.072, 0.098, 0.140),
		"rock_highlight": Color(0.165, 0.210, 0.275),
		"blend_sharpness": 3.0,
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


## Valeurs communes aux trois materiaux. Elles doivent etre ECRITES et non
## laissees au defaut du shader : un parametre absent est serialise `null` par
## ResourceSaver, ce qui rend le materiau dependant du defaut du shader et
## masque toute divergence entre les deux.
const SHARED := {
	"frost_color": Color(0.560, 0.640, 0.720),
	"frost_roughness": 0.62,
	"debug_mode": 0,
}


func _make(shader: Shader, params: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = shader
	for key in SHARED:
		material.set_shader_parameter(key, SHARED[key])
	for key in params:
		material.set_shader_parameter(key, params[key])
	return material

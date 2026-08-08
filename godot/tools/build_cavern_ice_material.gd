extends SceneTree

## Écrit le matériau de la nappe de glace du lac.
##   godot --headless --path godot --script tools/build_cavern_ice_material.gd
##
## De la glace, pas de l'eau : la référence visuelle du projet montre un lac
## GELÉ, et c'est ce qui permet de marcher dessus. Donc pas de transparence
## totale ni de vagues — une surface claire, lisse, légèrement translucide, qui
## renvoie la lumière du puits de plafond au-dessus d'elle.

const OUTPUT_PATH := "res://data/levels/cavern_ice_material.tres"


func _init() -> void:
	var material := StandardMaterial3D.new()
	# Claire : c'est le contraste avec la roche sombre qui fait l'image (art
	# bible §3, inflexion glaciaire).
	material.albedo_color = Color(0.62, 0.74, 0.84)
	# Lisse et réfléchissante, sans être un miroir.
	material.roughness = 0.12
	material.metallic = 0.0
	material.metallic_specular = 0.85
	# Un rien de translucidité : on devine le fond sans le voir nettement.
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.albedo_color.a = 0.88
	# La glace capte la lueur ambiante froide plutôt que d'être un aplat mort.
	material.rim_enabled = true
	material.rim = 0.5
	material.rim_tint = 0.2
	# Pas d'ombre portée : une nappe plane n'en projette pas de crédible, et
	# elle coûterait une passe d'ombre sur une grande surface.
	material.cull_mode = BaseMaterial3D.CULL_DISABLED

	if ResourceSaver.save(material, OUTPUT_PATH) != OK:
		push_error("Échec d'écriture de %s" % OUTPUT_PATH)
		quit(1)
		return
	print("[glace] écrit : %s" % OUTPUT_PATH)
	quit(0)

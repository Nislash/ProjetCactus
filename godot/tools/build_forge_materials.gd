@tool
extends SceneTree

## Dérive les cartes normal + rugosité des matières de la Forge, et écrit les
## `StandardMaterial3D` triplanaires du château et du pont. Lancer via :
##   godot --headless --path godot --script tools/build_forge_materials.gd
##
## ## Pourquoi les albédos viennent de Meshy et le reste d'ici
##
## Meshy sait produire une matière : on lui a demandé un basalte taillé et un
## dallage volcanique, il les a rendus en 1024² raccordables. Il ne rend PAS de
## jeu de cartes PBR — seulement l'image de couleur. Les deux autres cartes se
## dérivent de celle-là, et c'est reproductible : c'est le rôle de ce script.
##
## ## Pourquoi PAS le pipeline « retexture-first » du projet
##
## La règle de `meshy_setup.md` est de retexturer une géométrie qu'on maîtrise
## plutôt que d'en générer. Elle ne s'applique pas ici : `meshy_retexture`
## réclame un `input_task_id` Meshy ou une URL publique de modèle, et le château
## comme le pont sont bâtis en primitives À L'EXÉCUTION — il n'existe aucun
## maillage à envoyer, et des UV de boîtes et de cylindres ne survivraient de
## toute façon pas à un unwrap.
##
## D'où le triplanaire : la matière est projetée selon les trois axes du monde,
## sans UV du tout. C'est déjà ce que fait le shader du terrain, et ça règle
## d'un coup le placage sur des primitives et les coutures aux arêtes.
##
## ## Ce que les cartes dérivées valent, et ne valent pas
##
## Un relief déduit de la luminance n'est pas un relief mesuré : une pierre
## sombre parce qu'elle est sombre creuse autant qu'une pierre sombre parce
## qu'elle est en retrait. Sur du basalte à joints creusés, les deux coïncident
## largement — c'est ce qui rend l'approximation acceptable ICI, et ce qui
## l'interdirait sur une matière peinte ou colorée.

const SOURCES: Array[Dictionary] = [
	{
		"name": "forge_masonry",
		# Le basalte des murs : très rugueux partout, les joints encore plus.
		"rough_min": 0.78,
		"rough_max": 0.97,
		"relief": 2.6,
	},
	{
		"name": "forge_deck",
		# Le dallage du tablier : usé au centre, donc un peu moins rugueux là où
		# la lumière l'accroche.
		"rough_min": 0.70,
		"rough_max": 0.95,
		"relief": 2.0,
	},
]

const TEXTURE_DIR := "res://assets/level02/textures"


func _init() -> void:
	for source in SOURCES:
		_derive(source)
	print("[Forge] cartes dérivées — relancer un import Godot avant de mesurer.")
	quit(0)


func _derive(source: Dictionary) -> void:
	var name: String = source["name"]
	var albedo_path: String = "%s/%s_albedo.png" % [TEXTURE_DIR, name]
	var on_disk: String = ProjectSettings.globalize_path(albedo_path)
	if not FileAccess.file_exists(albedo_path):
		push_error("[Forge] albédo introuvable : %s" % albedo_path)
		return
	var albedo: Image = Image.load_from_file(on_disk)
	if albedo == null:
		# Distinguer les deux pannes vaut le détour : Meshy sert parfois du JPEG
		# sous une extension `.png`, et le fichier est alors bien là mais
		# illisible. « Introuvable » nous a fait chercher au mauvais endroit.
		push_error("[Forge] albédo illisible (format réel ≠ extension ?) : %s" % albedo_path)
		return
	albedo.convert(Image.FORMAT_RGB8)

	var width: int = albedo.get_width()
	var height: int = albedo.get_height()

	# La hauteur, une fois pour toutes. La relire depuis l'image à chaque voisin
	# ferait quatre décodages par pixel.
	var heights: PackedFloat32Array = PackedFloat32Array()
	heights.resize(width * height)
	for y in height:
		for x in width:
			var c: Color = albedo.get_pixel(x, y)
			# Luminance perceptuelle : sur une matière neutre, c'est ce qui
			# approche le mieux « en relief » contre « en retrait ».
			heights[y * width + x] = 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

	var normal := Image.create(width, height, false, Image.FORMAT_RGB8)
	var rough := Image.create(width, height, false, Image.FORMAT_RGB8)
	var relief: float = source["relief"]
	var rough_min: float = source["rough_min"]
	var rough_max: float = source["rough_max"]

	for y in height:
		for x in width:
			# Sobel, en BOUCLANT sur les bords. Pincer aux bords creuserait une
			# rainure de un pixel tout autour, qui se verrait à chaque raccord —
			# c'est-à-dire partout, puisque la texture est faite pour se répéter.
			var dx: float = (
				_at(heights, width, height, x + 1, y - 1)
				+ 2.0 * _at(heights, width, height, x + 1, y)
				+ _at(heights, width, height, x + 1, y + 1)
				- _at(heights, width, height, x - 1, y - 1)
				- 2.0 * _at(heights, width, height, x - 1, y)
				- _at(heights, width, height, x - 1, y + 1))
			var dy: float = (
				_at(heights, width, height, x - 1, y + 1)
				+ 2.0 * _at(heights, width, height, x, y + 1)
				+ _at(heights, width, height, x + 1, y + 1)
				- _at(heights, width, height, x - 1, y - 1)
				- 2.0 * _at(heights, width, height, x, y - 1)
				- _at(heights, width, height, x + 1, y - 1))

			var n: Vector3 = Vector3(-dx * relief, -dy * relief, 1.0).normalized()
			normal.set_pixel(x, y, Color(
				n.x * 0.5 + 0.5, n.y * 0.5 + 0.5, n.z * 0.5 + 0.5))

			# Rugosité : le clair est ce qui a été poli ou usé, le sombre ce qui
			# est resté brut ou s'est empli de cendre.
			var lum: float = heights[y * width + x]
			var r: float = lerpf(rough_max, rough_min, clampf(lum * 1.8, 0.0, 1.0))
			rough.set_pixel(x, y, Color(r, r, r))

	var normal_path: String = ProjectSettings.globalize_path(
		"%s/%s_normal.png" % [TEXTURE_DIR, name])
	var rough_path: String = ProjectSettings.globalize_path(
		"%s/%s_rough.png" % [TEXTURE_DIR, name])
	normal.save_png(normal_path)
	rough.save_png(rough_path)
	print("[Forge] %s : normal + rugosité en %d×%d" % [name, width, height])


## Lecture de la hauteur avec enroulement — voir le commentaire du Sobel.
func _at(heights: PackedFloat32Array, width: int, height: int, x: int, y: int) -> float:
	return heights[posmod(y, height) * width + posmod(x, width)]

class_name LavaFall
extends Node3D

## Une chute de lave : la cascade qui alimente les douves à l'ouest, et celle
## par laquelle elles se vident à l'est.
##
## ## Pourquoi une chute est un objet à part
##
## La nappe du niveau est un CHAMP DE HAUTEURS : une altitude par (X, Z). Elle
## sait donc représenter une rivière, jamais une chute — une chute a deux
## altitudes à la même verticale. Ce n'est pas une limite du générateur qu'on
## contourne ici, c'est sa définition.
##
## D'où un objet distinct, posé sur la nappe : un rideau vertical qui rejoint
## deux altitudes, sa vasque en bas, et la lumière qui va avec.
##
## ## Ce qu'elle apporte au niveau
##
## Une rivière sans amont ni aval se lit comme une flaque allongée : elle est
## là, elle ne vient de nulle part. Les deux chutes donnent à la coulée un sens
## de lecture — elle ARRIVE de la montagne et elle S'EN VA par la faille — et
## ce sens est le même que celui du courant dans le shader. C'est cette
## cohérence-là qu'on remarque sans savoir la nommer.

## Où la chute tombe, en (X, Z).
@export var at: Vector2 = Vector2.ZERO

## Altitude du déversoir et du bassin de réception.
@export var top_altitude: float = 20.0
@export var bottom_altitude: float = 1.9

## Largeur du rideau. Un peu moins que le lit, pour qu'on voie la roche de
## chaque côté — un rideau bord à bord se lit comme un mur.
@export var width: float = 15.0

## Direction dans laquelle la chute REGARDE (le rideau lui est perpendiculaire).
@export var facing: Vector2 = Vector2(1.0, 0.0)

## Épaisseur du rideau. Deux plans très légèrement écartés : un plan unique
## disparaît quand on l'atteint par la tranche.
@export var thickness: float = 1.1

## Bâtir un CONTREFORT de roche derrière le rideau.
##
## Vrai à l'amont, faux à l'aval. Le champ de hauteurs ne sait pas produire la
## paroi dont la cascade a besoin : le déversoir est un couloir de cent
## cinquante mètres, et son rempart ne se referme jamais avant le bord du
## domaine. Tenter de l'y forcer déréglait les pentes du cirque à chaque essai.
##
## On bâtit donc la paroi ICI, où elle est un objet qu'on maîtrise, plutôt que
## de tordre un générateur pour lui faire dire une chose qu'il ne dit pas. Le
## contrefort ferme du même coup la tranchée qui filait vers l'ouest.
@export var buttress: bool = false

const MATERIAL_PATH := "res://data/levels/forge_lava_material.tres"
## LA ROCHE DU TERRAIN, et non la maçonnerie du château.
##
## Première version faite en maçonnerie : le contrefort se lisait comme un
## barrage bâti de main d'homme, à l'autre bout d'un cirque où rien n'est bâti
## sauf la forteresse. Or c'est une MONTAGNE d'où la lave sort. Le shader du
## terrain le raccorde aux falaises sans couture, puisque c'est littéralement
## la même matière.
const ROCK_PATH := "res://data/levels/forge_rock_material.tres"

const GLOW := Color(1.000, 0.478, 0.184)
const ROCK := Color(0.048, 0.040, 0.044)


func _ready() -> void:
	_build()


func _build() -> void:
	var material: ShaderMaterial = _fall_material()
	var drop: float = maxf(top_altitude - bottom_altitude, 0.5)
	var heading: float = atan2(facing.x, facing.y)

	if buttress:
		_build_buttress(drop, heading)

	# LE RIDEAU. Deux plans écartés de `thickness` : vu de la tranche, une
	# chute d'un seul plan s'évanouit, ce qui arrive dès qu'on longe la berge.
	for i in 2:
		var sheet := MeshInstance3D.new()
		sheet.name = "Rideau_%d" % i
		var mesh := BoxMesh.new()
		mesh.size = Vector3(width, drop, 0.12)
		sheet.mesh = mesh
		sheet.material_override = material
		add_child(sheet)
		sheet.global_position = Vector3(at.x, bottom_altitude + drop * 0.5, at.y) \
			+ Vector3(facing.x, 0.0, facing.y).normalized() \
			* (thickness * (float(i) - 0.5))
		sheet.rotation.y = heading

	# LA VASQUE. Un disque à peine au-dessus de la nappe, qui marque l'endroit
	# où la chute frappe. Sans elle, le rideau semble traverser la coulée sans
	# la toucher.
	var basin := MeshInstance3D.new()
	basin.name = "Vasque"
	var basin_mesh := CylinderMesh.new()
	basin_mesh.top_radius = width * 0.62
	basin_mesh.bottom_radius = width * 0.62
	basin_mesh.height = 0.12
	basin_mesh.radial_segments = 18
	basin.mesh = basin_mesh
	basin.material_override = material
	add_child(basin)
	basin.global_position = Vector3(at.x, bottom_altitude + 0.10, at.y)

	# LA LUMIÈRE. Une chute est la source la plus brillante du niveau : c'est
	# de la lave en mouvement sur toute une hauteur. Deux lampes, une au
	# déversoir et une à la vasque, pour que la paroi derrière se détache.
	_add_light("LueurDeversoir", Vector3(at.x, top_altitude - drop * 0.15, at.y), 26.0, 4.2)
	_add_light("LueurVasque", Vector3(at.x, bottom_altitude + 2.0, at.y), 30.0, 5.0)


## LE CONTREFORT : deux épaules de roche et un linteau, laissant entre eux
## l'échancrure par où la lave sort.
##
## Trois blocs plutôt qu'un bloc percé : Godot ne sait pas soustraire un volume
## d'un autre, et une boîte creuse serait de toute façon plus chère qu'un
## encadrement. L'échancrure est donc le VIDE entre les pièces.
func _build_buttress(drop: float, heading: float) -> void:
	var rock: Material = load(ROCK_PATH) as Material
	if rock == null:
		var flat := StandardMaterial3D.new()
		flat.albedo_color = ROCK
		flat.roughness = 0.93
		rock = flat

	var height: float = drop + 14.0
	var mouth: float = width * 0.92
	var shoulder: float = 17.0
	var base: float = bottom_altitude - 3.0

	# Les deux épaules.
	for side in [-1.0, 1.0]:
		_slab("Epaule", rock,
			Vector3(mouth * 0.5 + shoulder * 0.5, 0.0, 0.0) * side,
			Vector3(shoulder, height, 7.0), base + height * 0.5, heading)

	# Le linteau, au-dessus de l'échancrure.
	var lintel_height: float = maxf(height - (top_altitude - base) - 1.0, 3.0)
	_slab("Linteau", rock, Vector3.ZERO, Vector3(mouth, lintel_height, 7.0),
		base + height - lintel_height * 0.5, heading)

	# Et le seuil : la lèvre par-dessus laquelle la lave bascule. Sans elle, le
	# rideau part d'une arête invisible.
	_slab("Seuil", rock, Vector3.ZERO, Vector3(mouth, 1.4, 5.0),
		top_altitude - 0.7, heading)


func _slab(slab_name: String, material: Material, offset: Vector3, size: Vector3,
		altitude: float, heading: float) -> void:
	var block := MeshInstance3D.new()
	block.name = "%s_%d" % [slab_name, get_child_count()]
	var mesh := BoxMesh.new()
	mesh.size = size
	block.mesh = mesh
	block.material_override = material
	add_child(block)
	var side_axis := Vector3(cos(heading), 0.0, -sin(heading))
	block.global_position = Vector3(at.x, altitude, at.y) + side_axis * offset.x
	block.rotation.y = heading

	var body := StaticBody3D.new()
	body.name = "Col_%s" % block.name
	body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = block.global_position
	body.rotation.y = heading


## La matière de la coulée, réglée en mode CHUTE.
##
## Dupliquée et non partagée : la nappe et la chute ont besoin du même shader
## mais pas du même `flow_plane`, et modifier la ressource commune retournerait
## la rivière entière à la verticale.
func _fall_material() -> ShaderMaterial:
	var base: ShaderMaterial = load(MATERIAL_PATH) as ShaderMaterial
	if base == null:
		push_warning("LavaFall : matière de lave introuvable.")
		return null
	var material: ShaderMaterial = base.duplicate() as ShaderMaterial
	material.set_shader_parameter("flow_plane", 1)
	# Une chute descend plus vite qu'une rivière ne coule. Le rapport compte
	# plus que les valeurs : c'est lui qui dit « ça tombe » plutôt que « ça
	# glisse ».
	material.set_shader_parameter("current_speed", 5.5)
	material.set_shader_parameter("flow_stretch", 4.2)
	material.set_shader_parameter("crust_scale", 0.075)
	return material


func _add_light(light_name: String, at_position: Vector3, range_m: float,
		energy: float) -> void:
	var light := OmniLight3D.new()
	light.name = light_name
	light.light_color = GLOW
	light.light_energy = energy
	light.omni_range = range_m
	# Pas d'ombres : la chute est une source ÉTENDUE, et une ombre portée
	# ponctuelle depuis son centre trahirait immédiatement qu'il n'y a qu'une
	# lampe. Le niveau tient déjà son contraste des ombres de la lune.
	light.shadow_enabled = false
	add_child(light)
	light.global_position = at_position

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

## Rayon du BASSIN de réception. 0 = pas de bassin.
##
## Signalé en jeu : « l'écoulement de lave est mal fini à droite ». La chute
## aval s'arrêtait sur la roche nue, et le champ de hauteurs y descend par
## marches — des marches que rien ne cachait. Un plan de lave au pied les
## couvre, et il est de toute façon ce qu'on attend au bas d'une chute : la
## lave ne s'évapore pas en touchant le sol.
@export var pool_radius: float = 0.0

## De combien le bassin déborde vers l'AVAL. Une flaque ronde au pied d'une
## chute ne raconte rien ; une nappe allongée dans le sens de l'écoulement dit
## que ça continue au-delà de ce qu'on voit.
@export var pool_stretch: float = 2.4

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
	_add_pool("Vasque", width * 0.62, 1.0, bottom_altitude + 0.10)

	# LE BASSIN. Beaucoup plus large, et allongé vers l'aval : c'est lui qui
	# couvre le relief en marches au pied de la chute.
	if pool_radius > 0.0:
		_add_pool("Bassin", pool_radius, pool_stretch, bottom_altitude + 0.04)

	# LA LUMIÈRE. Une chute est la source la plus brillante du niveau : c'est
	# de la lave en mouvement sur toute une hauteur. Deux lampes, une au
	# déversoir et une à la vasque, pour que la paroi derrière se détache.
	_add_light("LueurDeversoir", Vector3(at.x, top_altitude - drop * 0.15, at.y), 26.0, 4.2)
	_add_light("LueurVasque", Vector3(at.x, bottom_altitude + 2.0, at.y), 30.0, 5.0)


## Une nappe plate de lave, éventuellement étirée dans le sens du courant.
func _add_pool(pool_name: String, radius: float, stretch: float,
		altitude: float) -> void:
	var pool := MeshInstance3D.new()
	pool.name = pool_name
	var mesh := CylinderMesh.new()
	mesh.top_radius = radius
	mesh.bottom_radius = radius
	mesh.height = 0.12
	mesh.radial_segments = 22
	pool.mesh = mesh
	# La nappe reste HORIZONTALE : c'est du liquide au repos, pas une chute.
	# Elle garde donc le `flow_plane` de la coulée.
	pool.material_override = load(MATERIAL_PATH) as Material
	add_child(pool)
	pool.global_position = Vector3(at.x, altitude, at.y)
	var along := Vector3(facing.x, 0.0, facing.y).normalized()
	pool.scale = Vector3(1.0 + (stretch - 1.0) * absf(along.x), 1.0,
		1.0 + (stretch - 1.0) * absf(along.z))
	# Décalée vers l'aval : une chute ne remplit pas autant en amont qu'en aval.
	pool.global_position += along * radius * (stretch - 1.0) * 0.45


## LE CONTREFORT : la montagne d'où la lave sort.
##
## ELLE DÉBORDE PAR LE HAUT, comme un cratère qui déverse.
##
## Première version : une échancrure à mi-hauteur, avec un linteau au-dessus.
## Ça se lisait comme une vanne dans un barrage — un ouvrage, pas un volcan.
## Le linteau a disparu et les épaules montent maintenant au-dessus du
## déversoir : la lave passe par-dessus la lèvre, et ce sont les épaules qui
## font les bords du cratère.
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

	var mouth: float = width * 0.92
	var base: float = bottom_altitude - 3.0
	var lip: float = top_altitude

	# LES DEUX ÉPAULES, plus hautes que le déversoir : ce sont les bords du
	# cratère. Elles montent en s'écartant, pour que la montagne s'évase vers
	# le haut au lieu de faire deux piliers.
	var shoulders: Array[float] = [9.0, 15.0, 21.0]
	for step in shoulders.size():
		var lift: float = 5.0 * float(step + 1)
		var span: float = shoulders[step]
		for side in [-1.0, 1.0]:
			_slab("Epaule", rock,
				Vector3((mouth * 0.5 + span * 0.5 - float(step) * 1.5) * side, 0.0,
					1.5 + float(step) * 2.0),
				Vector3(span, lip - base + lift, 8.0 + float(step) * 2.0),
				base + (lip - base + lift) * 0.5, heading)

	# LA LÈVRE, par-dessus laquelle la lave bascule. Elle est BASSE et large :
	# c'est une échancrure dans le rebord du cratère, pas une porte.
	_slab("Levre", rock, Vector3(0.0, 0.0, 3.4), Vector3(mouth, 1.2, 6.0),
		lip - 0.6, heading)

	# Le massif sous la lèvre : la montagne est pleine, on ne doit pas voir le
	# ciel sous la coulée.
	_slab("Massif", rock, Vector3(0.0, 0.0, 5.2), Vector3(mouth, lip - base, 7.0),
		base + (lip - base) * 0.5 - 0.6, heading)


## `offset.x` écarte latéralement, `offset.z` recule DERRIÈRE le rideau.
##
## Le recul n'est pas cosmétique : la première version posait le massif dans le
## plan même de la coulée, et la montagne bouchait donc entièrement la cascade.
## On ne voyait plus que la flaque au pied. La roche doit être derrière l'eau,
## pas devant — c'est vrai de toutes les cascades.
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
	var back_axis := Vector3(facing.x, 0.0, facing.y).normalized()
	block.global_position = Vector3(at.x, altitude, at.y) \
		+ side_axis * offset.x - back_axis * offset.z
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

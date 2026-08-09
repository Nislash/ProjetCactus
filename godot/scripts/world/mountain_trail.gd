class_name MountainTrail
extends Node3D

## Le sentier qui monte dans la montagne ouest, en lacets, jusqu'au haut de la
## cascade.
##
## ## Pourquoi un objet et pas du terrain
##
## Un sentier en lacets se recoupe : au-dessus du deuxième virage, il repasse
## par-dessus le premier. Le champ de hauteurs du niveau ne connaît qu'une
## altitude par (X, Z) — il ne peut donc pas représenter ça, par construction.
## Ce n'est pas une limite qu'on contourne, c'est ce que le terrain est.
##
## ## Pourquoi des LACETS et pas une rampe droite
##
## Vingt et un mètres à gravir. En ligne droite depuis le point d'apparition, il
## faudrait soit une pente que le joueur ne peut pas monter, soit cent
## cinquante mètres de couloir rectiligne — un tapis roulant. Les lacets
## donnent la même altitude sur une emprise trois fois plus courte, et chaque
## virage change ce qu'on voit : on découvre le cirque par morceaux en montant,
## ce qu'une ligne droite ne fait jamais.
##
## ## Il part DERRIÈRE le point d'apparition
##
## Volontairement à contre-sens : la première chose qu'on voit du niveau est le
## château, droit devant. Le sentier est dans le dos, à gauche. Un joueur qui
## se contente d'avancer ne le trouvera pas — et c'est ce qui en fait une
## découverte plutôt qu'un couloir.

## Les points de passage, en (X, Z, altitude).
@export var waypoints: Array[Vector3] = []

## Largeur du sentier. Étroit : c'est un chemin de montagne, et une voie large
## enlèverait toute prudence à la montée.
@export var width: float = 5.0

## Longueur maximale d'un tronçon. Les points de passage sont subdivisés :
## sinon les virages seraient des angles vifs et le navmesh accrocherait.
@export var segment_length: float = 4.0

@export_file("*.tres") var terrain_data_path: String = "res://data/levels/level02_forge_terrain.tres"

const STONE_PATH := "res://data/levels/forge_rock_material.tres"

## Pente maximale tolérée, en degrés. Alignée sur le `floor_max_angle` du
## joueur ET sur l'agent du navmesh : au-delà, ni les joueurs ni les ennemis ne
## montent, et le sentier ne mène nulle part.
const MAX_SLOPE_DEGREES: float = 30.0

## De combien chaque bloc s'enfonce sous le terrain, au minimum.
const BURIED_DEPTH: float = 3.0

## De combien le dessus du sentier reste au-dessus du sol réel, au minimum.
const CLEARANCE: float = 0.6

## Recalculer les altitudes le long du tracé, au lieu de prendre celles des
## points de passage.
##
## Le lissage de la courbe adoucit le TRACÉ, pas la PENTE : entre deux points
## d'altitudes mal choisies, elle saute encore de zéro à vingt degrés, et c'est
## sur ces ruptures que la navigation se coupait. Le profil calculé ici part et
## finit à plat, et sa pente varie continûment — un `smoothstep` sur la distance
## parcourue. Les altitudes des points de passage ne servent alors plus qu'aux
## deux extrémités, ce qui supprime six chiffres à régler à la main.
@export var smooth_altitudes: bool = true

var _terrain: CavernTerrainData
var _noise: FastNoiseLite


func _ready() -> void:
	if waypoints.size() < 2:
		push_warning("MountainTrail : moins de deux points — pas de sentier.")
		return
	_terrain = load(terrain_data_path) as CavernTerrainData
	if _terrain != null:
		_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)
	_build()


func _ground(at: Vector2) -> float:
	if _terrain == null:
		return 0.0
	return CavernTerrainBuilder.ground_at(_terrain, at, _noise)


func _build() -> void:
	var rock: Material = load(STONE_PATH) as Material
	var line: PackedVector3Array = _smoothed()
	for i in line.size() - 1:
		_block(rock, line[i], line[i + 1], i)


## LES POINTS DE PASSAGE, LISSÉS EN COURBE.
##
## ## Pourquoi pas des segments droits avec un palier dans chaque virage
##
## C'est ce que faisait la version précédente, et c'est là qu'elle se coupait :
## mesuré, la rupture tombait exactement sur les paliers. Une dalle plate
## coincée entre deux rampes inclinées, c'est trois pentes différentes qui se
## rejoignent sur deux arêtes — Recast y voit des corniches, les filtre, et le
## sentier se retrouve en tronçons isolés. Chaque jambe était praticable, aucune
## ne communiquait avec la suivante.
##
## Une courbe de Catmull-Rom supprime la question : la pente et le cap varient
## continûment, deux blocs voisins ont presque la même inclinaison, et il n'y a
## plus d'arête où filtrer quoi que ce soit. C'est aussi ce qu'est un vrai
## chemin de montagne — on ne tourne pas à angle droit sur un flanc.
func _smoothed() -> PackedVector3Array:
	var out := PackedVector3Array()
	for leg in waypoints.size() - 1:
		# Les points de contrôle débordent aux extrémités : sans eux la courbe
		# partirait et finirait sans tangente, donc avec un coude.
		var p0: Vector3 = waypoints[maxi(leg - 1, 0)]
		var p1: Vector3 = waypoints[leg]
		var p2: Vector3 = waypoints[leg + 1]
		var p3: Vector3 = waypoints[mini(leg + 2, waypoints.size() - 1)]
		var steps: int = maxi(int(p1.distance_to(p2) / segment_length), 2)
		for i in steps:
			out.append(_catmull(p0, p1, p2, p3, float(i) / float(steps)))
	out.append(waypoints[waypoints.size() - 1])
	if smooth_altitudes:
		_reprofile(out)
	return out


## Redistribue les altitudes le long du tracé, à plat aux deux bouts.
func _reprofile(line: PackedVector3Array) -> void:
	var lengths := PackedFloat32Array()
	lengths.resize(line.size())
	lengths[0] = 0.0
	for i in range(1, line.size()):
		var a := Vector2(line[i - 1].x, line[i - 1].z)
		var b := Vector2(line[i].x, line[i].z)
		lengths[i] = lengths[i - 1] + a.distance_to(b)
	var total: float = lengths[lengths.size() - 1]
	if total < 0.01:
		return
	var bottom: float = line[0].y
	var top: float = line[line.size() - 1].y
	for i in line.size():
		line[i] = Vector3(line[i].x,
			lerpf(bottom, top, smoothstep(0.0, 1.0, lengths[i] / total)),
			line[i].z)

	# PUIS ON REMONTE CE QUI PASSE SOUS LA ROCHE.
	#
	# Le profil lissé ne connaît que la distance parcourue ; il ignore ce qu'il
	# traverse. Au départ, le sentier sortait d'une fosse de six mètres et son
	# profil, encore plat, restait dans la paroi.
	#
	# On relève donc chaque point au-dessus du sol RÉEL, puis on relisse — et on
	# recommence, parce que relisser fait replonger ce qu'on vient de relever.
	# Huit passes suffisent : au-delà le tracé ne bouge plus d'un centimètre.
	for pass_index in 8:
		for i in line.size():
			var floor_here: float = _ground(Vector2(line[i].x, line[i].z)) + CLEARANCE
			if line[i].y < floor_here:
				line[i] = Vector3(line[i].x, floor_here, line[i].z)
		# Moyenne glissante, extrémités figées : elles sont posées, l'une au
		# fond de la fosse et l'autre sur le belvédère.
		for i in range(1, line.size() - 1):
			line[i] = Vector3(line[i].x,
				(line[i - 1].y + line[i].y * 2.0 + line[i + 1].y) * 0.25,
				line[i].z)
	# Dernière remontée : le lissage a le dernier mot sinon, et il replonge.
	for i in line.size():
		var rock: float = _ground(Vector2(line[i].x, line[i].z)) + CLEARANCE
		if line[i].y < rock:
			line[i] = Vector3(line[i].x, rock, line[i].z)


func _catmull(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: float) -> Vector3:
	var t2: float = t * t
	var t3: float = t2 * t
	return 0.5 * ((2.0 * p1)
		+ (-p0 + p2) * t
		+ (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2
		+ (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3)


## UN SEUL VOLUME PAR TRONÇON, et non une dalle posée sur un mur.
##
## Une dalle mince qui décolle du terrain crée DEUX surfaces superposées. Là où
## elles sont à moins de deux mètres l'une de l'autre, Recast écarte celle du
## bas faute de hauteur libre pour l'agent ; au-delà, il garde les deux. Élargir
## un mur de soutènement n'y change rien — essayé à cinq puis quatorze mètres de
## débord, le résultat empirait. C'est la superposition qu'il faut supprimer.
##
## Un bloc profond dont seul le DESSUS émerge : le terrain est à l'intérieur du
## volume, plus à côté. Une seule surface, aucune corniche à filtrer, aucune
## question de hauteur libre. C'est aussi ce qu'on veut voir — un chemin taillé
## dans un éperon de roche, pas un ruban sur pilotis.
func _block(material: Material, from_point: Vector3, to_point: Vector3,
		index: int) -> void:
	var span: Vector3 = to_point - from_point
	var flat: float = Vector2(span.x, span.z).length()
	if span.length() < 0.01:
		return
	var centre: Vector3 = (from_point + to_point) * 0.5
	var depth: float = maxf(centre.y - _ground(Vector2(centre.x, centre.z)), 0.0) \
		+ BURIED_DEPTH

	var piece := MeshInstance3D.new()
	piece.name = "Tronçon_%d" % index
	var mesh := BoxMesh.new()
	# Chevauchement volontaire : sans lui on voit le vide entre deux tronçons
	# dès que le cap change.
	mesh.size = Vector3(width, depth, span.length() + 1.2)
	piece.mesh = mesh
	piece.material_override = material
	add_child(piece)
	piece.global_position = centre
	piece.rotation.y = atan2(span.x, span.z)
	piece.rotate_object_local(Vector3.RIGHT, -atan2(span.y, flat))
	# Descendu de la moitié de sa hauteur DANS SON PROPRE REPÈRE : son dessus
	# reste donc exactement sur la ligne du sentier, quelle que soit la pente.
	piece.translate_object_local(Vector3(0.0, -depth * 0.5, 0.0))
	_collider(mesh.size, piece.global_position, piece.rotation, index)


func _collider(size: Vector3, at: Vector3, rotation: Vector3, index: int) -> void:
	var body := StaticBody3D.new()
	body.name = "Col_%d" % index
	body.collision_layer = CavernTerrainBuilder.WORLD_COLLISION_LAYER \
		| CavernTerrainBuilder.NAVMESH_SOURCE_LAYER
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	add_child(body)
	body.global_position = at
	body.rotation = rotation


## La pente la plus raide du sentier, en degrés.
##
## Mesurée sur le tracé RÉELLEMENT construit, pas sur les points de passage :
## depuis que les altitudes sont recalculées, ceux-ci ne décrivent plus la pente
## qu'on obtient. Un `smoothstep` pique à une fois et demie sa pente moyenne, et
## c'est ce pic qu'il faut surveiller.
func steepest_slope() -> float:
	var line: PackedVector3Array = _smoothed()
	var worst: float = 0.0
	for i in line.size() - 1:
		var span: Vector3 = line[i + 1] - line[i]
		var flat: float = Vector2(span.x, span.z).length()
		if flat < 0.01:
			continue
		worst = maxf(worst, rad_to_deg(atan(absf(span.y) / flat)))
	return worst

## Brume par zone — la mécanique signature du niveau 1 (« visibilité limitée »).
##
## LE PRINCIPE : la portée de vue n'est pas un réglage d'ambiance, c'est un
## PARAMÈTRE DE GAMEPLAY. Elle dit au joueur, à chaque instant, s'il est dans un
## endroit où l'on s'oriente ou dans un endroit où l'on se perd.
##
## La grammaire du niveau tient à ceci : la brume éteint la géométrie MATE bien
## avant les émissifs. Là où la roche disparaît à 14 m, un cristal se voit encore
## à 50. Réduire la portée ne rend donc pas le joueur aveugle — ça le force à
## naviguer aux LUMIÈRES. Les cristaux deviennent la boussole, et c'est
## exactement ce que le plan appelle « visibilité limitée ».
##
## Le contraste fait tout le travail : après 14 m de boyau oppressant, les 65 m
## de la Salle du Lac produisent un soulagement physique. Une brume uniforme,
## même bien réglée, n'obtiendrait jamais cet effet.
##
## Les zones sont des sphères d'influence lues sur les chambres du terrain : une
## correction de topographie les déplace donc avec elle, sans réglage manuel.

class_name CavernFogZones
extends Node

## Une zone d'ambiance : un centre, un rayon d'influence, une portée de vue.
class FogZone:
	var label: String
	var center: Vector2
	var radius: float
	var view_distance: float

	func _init(p_label: String, p_center: Vector2, p_radius: float, p_view: float) -> void:
		label = p_label
		center = p_center
		radius = p_radius
		view_distance = p_view


@export_file("*.tres") var environment_path: String = "res://data/levels/level01_cavern_environment.tres"

## Vitesse de transition entre deux zones, en fraction par seconde. Assez lent
## pour que l'œil ne voie pas de saut, assez rapide pour que franchir un goulet
## se ressente.
@export var blend_speed: float = 0.9

## Portée par défaut, hors de toute zone déclarée.
@export var default_view_distance: float = 24.0

var _environment: Environment
var _zones: Array[FogZone] = []
var _current: float = 0.0


func _ready() -> void:
	_environment = load(environment_path) as Environment
	if _environment == null:
		push_error("CavernFogZones : environnement introuvable (%s)." % environment_path)
		set_process(false)
		return

	_build_zones()
	_current = default_view_distance
	_apply(_current)


## Les portées viennent de la spec créative (`level01_topography.md` §7).
func _build_zones() -> void:
	_zones = [
		FogZone.new("Galerie ouest", Vector2(-102.0, -38.0), 46.0, 28.0),
		FogZone.new("Galerie centrale", Vector2(-54.0, -44.0), 42.0, 28.0),
		FogZone.new("Galerie est", Vector2(-12.0, -36.0), 40.0, 28.0),
		# Le boyau et la poche : c'est ici qu'on est le plus aveugle, et c'est
		# ce qui fait de la cachette une vraie cachette.
		FogZone.new("Boyau du Loot", Vector2(-112.0, -10.0), 26.0, 14.0),
		FogZone.new("Poche du Loot", Vector2(-128.0, 8.0), 26.0, 14.0),
		FogZone.new("Jardin de Givre", Vector2(-86.0, 34.0), 38.0, 18.0),
		# LA clairière. Sous la Brèche, on voit tout : c'est le seul endroit du
		# niveau où l'on peut s'orienter à l'échelle de la caverne entière.
		FogZone.new("Salle du Lac", Vector2(-4.0, 36.0), 56.0, 65.0),
		FogZone.new("Seuil du Boss", Vector2(42.0, -46.0), 20.0, 16.0),
		FogZone.new("Bol de l'Arène", Vector2(100.0, -52.0), 46.0, 32.0),
	]


func _process(delta: float) -> void:
	var target: float = _view_distance_at(_average_player_position())
	# Interpolation exponentielle : indépendante du framerate, contrairement à
	# un lerp à pas fixe qui accélérerait sur une machine rapide.
	_current = lerpf(_current, target, 1.0 - exp(-blend_speed * delta))
	_apply(_current)


## Portée en un point : celle de la zone la plus influente, pondérée par la
## distance. Aux frontières, les zones se mélangent au lieu de commuter — un
## saut de portée se verrait comme un défaut de rendu.
func _view_distance_at(at: Vector2) -> float:
	var total_weight: float = 0.0
	var total_view: float = 0.0
	for zone in _zones:
		var distance: float = at.distance_to(zone.center)
		if distance >= zone.radius:
			continue
		# Poids en cloche : plein au cœur, nul au bord.
		var weight: float = 1.0 - smoothstep(0.0, 1.0, distance / zone.radius)
		total_weight += weight
		total_view += zone.view_distance * weight

	if total_weight <= 0.001:
		return default_view_distance
	return total_view / total_weight


## Position moyenne des joueurs. En split-screen il n'y a qu'UN environnement
## partagé : on ne peut pas donner à chacun sa propre brume, donc on suit le
## barycentre de l'équipe. C'est aussi ce qui a du sens en coop — l'équipe vit
## la même ambiance, et se séparer n'en donne pas deux.
func _average_player_position() -> Vector2:
	var sum := Vector2.ZERO
	var count: int = 0
	for node in get_tree().get_nodes_in_group(&"players"):
		var player: Node3D = node as Node3D
		if player == null:
			continue
		sum += Vector2(player.global_position.x, player.global_position.z)
		count += 1

	if count == 0:
		# Aucun joueur (aperçu, tests) : on prend la caméra active, qui est le
		# seul point de vue existant.
		var camera: Camera3D = get_viewport().get_camera_3d()
		if camera != null:
			return Vector2(camera.global_position.x, camera.global_position.z)
		return Vector2.ZERO
	return sum / float(count)


## Traduit une portée de vue en densité de brume.
##
## La densité de Godot est un coefficient d'extinction : la visibilité utile
## vaut environ 3/densité (au-delà, il reste moins de 5 % de la couleur
## d'origine). On inverse donc la relation plutôt que de régler une densité au
## jugé — ainsi les valeurs de la spec créative sont directement des MÈTRES.
func _apply(view_distance: float) -> void:
	var safe: float = maxf(view_distance, 1.0)
	_environment.fog_density = 3.0 / safe
	# Le volumétrique suit, en plus dilué : c'est lui qui porte les colonnes de
	# lumière, et une densité égale à celle du brouillard les noierait.
	_environment.volumetric_fog_density = clampf(1.6 / safe, 0.004, 0.05)


## Portée courante, pour les tests et le débogage.
func get_view_distance() -> float:
	return _current

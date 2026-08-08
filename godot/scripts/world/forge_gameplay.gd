class_name ForgeGameplay
extends Node

## Câble la boucle de jeu de la Forge (niveau 2).
##
## Même principe qu'au niveau 1 : la scène ne contient que des **marqueurs**,
## tout ce qui vit est instancié ici, après que le terrain a été généré et que
## les marqueurs ont été recalés au sol. C'est ce qui permet de retoucher la
## topographie sans repositionner quoi que ce soit à la main.
##
## ## Ce qui diffère du niveau 1
##
## Pas de puzzle. La Caverne se mérite — quatre éclats, quatre serrures, un
## mot à reconstituer. La Forge est une **arène** : on voit le boss depuis la
## crête, on descend, on se bat. Deux niveaux qui demanderaient la même chose
## au joueur ne seraient qu'un seul niveau joué deux fois.
##
## Le danger n'est plus signalé par la couleur — toute la salle est ambre — mais
## par le **mouvement** : la lave qui monte pendant le combat, et qui reprend
## un anneau à chaque phase du boss.

const BOSS_SCENE := "res://scenes/boss/boss_golem.tscn"

## Si faux, le boss n'est pas instancié (utile pour visiter).
@export var spawn_boss: bool = true

## Rayon de la laisse d'arène. Plus large qu'au niveau 1 : le bol de la Forge
## fait 21 m de rayon au palier bas, et le boss doit pouvoir remonter d'un
## anneau à la poursuite d'un joueur.
@export var boss_leash_radius: float = 30.0

signal boss_awakened()

var _world: Node3D
var _boss: Node3D


func _ready() -> void:
	_world = get_parent() as Node3D
	if _world == null:
		push_error("ForgeGameplay : doit être enfant du nœud World.")
		return

	# Deux frames : le terrain se construit, puis le snapper recale les
	# marqueurs. Instancier avant reviendrait à poser les objets dans le vide.
	await get_tree().process_frame
	await get_tree().process_frame

	if spawn_boss:
		_spawn_boss()


func _spawn_boss() -> void:
	var marker: Node3D = _world.get_node_or_null("BossArena/BossSpawn") as Node3D
	if marker == null:
		push_warning("ForgeGameplay : BossSpawn introuvable — pas de boss.")
		return
	var packed: PackedScene = load(BOSS_SCENE) as PackedScene
	if packed == null:
		push_error("ForgeGameplay : %s introuvable." % BOSS_SCENE)
		return

	_boss = packed.instantiate() as Node3D
	_boss.name = "BossGolem"
	_world.add_child(_boss)
	_boss.global_position = marker.global_transform.origin

	var ai: Node = _boss.get_node_or_null("BossAI")
	if ai != null and ai.has_method("set_arena"):
		ai.call("set_arena", _boss.global_position, boss_leash_radius)

	_build_arena_lock()
	print("[ForgeGameplay] boss posé en %v." % _boss.global_position)


## La zone d'éveil. Le niveau 1 n'en avait pas et son boss dormait
## indéfiniment sans que rien ne le signale — on ne refait pas l'erreur.
func _build_arena_lock() -> void:
	var zone := Area3D.new()
	zone.name = "ReveilDuGolem"
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = boss_leash_radius
	shape.shape = sphere
	zone.add_child(shape)
	_world.add_child(zone)
	zone.global_position = _boss.global_position

	zone.body_entered.connect(func(body: Node) -> void:
		if not (body is PlayerController):
			return
		if _boss.has_method("is_engaged") and bool(_boss.call("is_engaged")):
			return
		if _boss.has_method("engage"):
			_boss.call("engage")
			boss_awakened.emit()
			print("[ForgeGameplay] le Golem s'éveille dans la Forge."))


func get_boss() -> Node3D:
	return _boss

class_name BossShard
extends Interactable

## Un éclat du verrou — l'objet qu'on ramasse pour le puzzle B‑O‑S‑S.
##
## Les quatre éclats sont **interchangeables**. Ce n'est pas une simplification :
## c'est le puzzle. Si chaque éclat portait sa lettre, le joueur n'aurait qu'à
## faire correspondre ; comme ils sont identiques, la seule question qui reste
## est **dans quel ordre alimenter les poteaux**, et il faut avoir lu les
## lettres autour du lac pour y répondre.
##
## Vert glaciaire, silhouette hexagonale trapue : une couleur et une forme qui
## n'existent nulle part ailleurs dans le niveau (cf [CrystalGrammar]). Un
## objet qui verrouille l'arène du boss doit se reconnaître de loin.

signal collected(by_player: Node)

## Hauteur de flottement et vitesse de pulsation. L'éclat **bat** au lieu de
## briller fixe : c'est ce qui le distingue des cristaux muraux, immobiles.
const FLOAT_AMPLITUDE := 0.18
const PULSE_PERIOD := 2.2

var _mesh: MeshInstance3D
var _material: StandardMaterial3D
var _glow: OmniLight3D
var _time: float = 0.0
var _base_y: float = 0.0
var _taken: bool = false


func _ready() -> void:
	super._ready()
	add_to_group(&"boss_shards")
	prompt_text = "Prendre l'éclat"
	hold_duration = 0.5
	interaction_range = 2.6
	selection_priority = 8
	_base_y = position.y
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.0
	shape.shape = sphere
	add_child(shape)

	_material = CrystalGrammar.make_material(CrystalGrammar.COLOR_BOSS_LOCK, 3.2)
	_mesh = MeshInstance3D.new()
	_mesh.name = "Mesh"
	_mesh.mesh = CrystalGrammar.boss_shard_mesh()
	_mesh.material_override = _material
	_mesh.position = Vector3(0.0, 0.9, 0.0)
	add_child(_mesh)

	_glow = CrystalGrammar.make_glow(CrystalGrammar.COLOR_BOSS_LOCK, 2.2, 7.0)
	_glow.position = Vector3(0.0, 0.9, 0.0)
	add_child(_glow)


func _process(delta: float) -> void:
	if _taken:
		return
	_time += delta
	if _mesh != null:
		_mesh.rotate_y(delta * 0.9)
		_mesh.position.y = 0.9 + sin(_time * 1.6) * FLOAT_AMPLITUDE
	# Le battement. Lent, ample : il attire l'œil de loin sans clignoter.
	var pulse: float = 0.5 + 0.5 * sin(_time * TAU / PULSE_PERIOD)
	if _material != null:
		_material.emission_energy_multiplier = 2.4 + pulse * 1.6
	if _glow != null:
		_glow.light_energy = 1.6 + pulse * 1.2


## Même contrat que [LetterPylon] : ce qui compte est de savoir porter un
## éclat, pas d'être un PlayerController.
func can_interact(by_player: Node) -> bool:
	if _taken:
		return false
	if not LetterPylon._carries_shards(by_player):
		return false
	# Un joueur qui porte déjà les quatre n'a rien à ramasser de plus. Sans ce
	# garde, l'éclat resterait proposable et compterait au-delà du puzzle.
	return int(by_player.call(&"get_boss_shards")) < BossPuzzle.SHARD_COUNT


func try_interact(by_player: Node) -> bool:
	if not can_interact(by_player):
		return false
	var player: Node = by_player
	_taken = true
	player.add_boss_shard()
	collected.emit(player)
	interaction_completed.emit(player)
	remove_from_group(&"interactables")
	_vanish()
	return true


## L'éclat monte vers le joueur et se resserre. On voit **où il va** — sans
## ça, un objet qui disparaît d'un coup se lit comme un bug.
func _vanish() -> void:
	var tween: Tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(self, "position", position + Vector3(0.0, 1.4, 0.0), 0.35)
	tween.tween_property(_mesh, "scale", Vector3.ZERO, 0.35)
	if _glow != null:
		tween.tween_property(_glow, "light_energy", 0.0, 0.35)
	tween.chain().tween_callback(queue_free)

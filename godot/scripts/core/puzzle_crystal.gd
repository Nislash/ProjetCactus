class_name PuzzleCrystal
extends Lever

## Cristal du puzzle méta (niveau 1 : K1, K2, K3).
##
## Un [Lever] déguisé : il en garde tout le contrat — le signal `activated`, le
## one-shot, le branchement au [PuzzleGate] — mais change ce que « activer »
## veut dire. Un levier bascule un manche ; un cristal S'ALLUME.
##
## Le feedback n'est pas cosmétique. La grammaire lumineuse du niveau veut que
## les émissifs portent bien plus loin que la géométrie mate : un cristal
## allumé se voit **de l'autre bout de la caverne**. C'est ainsi que l'équipe
## sait, sans un mot ni une interface, combien il en reste — et où.
##
## Cf `docs/design/level01_topography.md` §6 et `puzzle_meta.md`.

## Couleur du cristal éteint : froid, sourd, mais assez visible pour qu'on
## comprenne qu'il y a quelque chose là.
@export var dormant_color: Color = Color(0.16, 0.26, 0.36)

## Couleur du cristal actif — le cyan signature de la caverne.
@export var awakened_color: Color = Color(0.32, 0.80, 1.0)

## Puissance de la lumière une fois éveillé.
@export var awakened_energy: float = 5.0

## Portée de la lumière une fois éveillé. Large : c'est un repère de niveau,
## pas un éclairage d'appoint.
@export var awakened_range: float = 40.0

@onready var _mesh: MeshInstance3D = $Crystal/Mesh if has_node("Crystal/Mesh") else null
@onready var _glow: OmniLight3D = $Crystal/Glow if has_node("Crystal/Glow") else null

var _material: BaseMaterial3D


func _ready() -> void:
	# L'ambiance sonore accroche son scintillement sur ce groupe : un son de
	# cristal doit venir d'un cristal qu'on peut aller voir.
	add_to_group(&"crystal_sources")
	super._ready()
	prompt_text = "Éveiller le cristal"
	hold_duration = 1.2
	interaction_range = 3.0
	# Au-dessus des coffres (10) : dans une salle qui contient les deux, c'est
	# le cristal qu'on veut viser — il commande la progression.
	selection_priority = 15

	if _mesh != null and _mesh.material_override is BaseMaterial3D:
		# Duplique : le matériau est partagé entre toutes les instances du prop.
		# Sans copie, éveiller UN cristal les éveillerait TOUS.
		_material = (_mesh.material_override as BaseMaterial3D).duplicate()
		_mesh.material_override = _material
	_apply_dormant()


## État de repos : la pierre est là, elle attend, elle n'éclaire rien.
func _apply_dormant() -> void:
	if _glow != null:
		_glow.light_energy = 0.35
		_glow.light_color = dormant_color
		_glow.omni_range = 8.0
	if _material != null:
		_material.emission = dormant_color
		_material.emission_energy_multiplier = 0.25
		_material.albedo_color = dormant_color.lightened(0.1)


func try_interact(by_player: Node) -> bool:
	if not super.try_interact(by_player):
		return false
	_play_awakening()
	return true


## L'éveil : la lumière monte en deux temps. Un jaillissement bref, puis une
## installation lente jusqu'à la pleine puissance.
##
## Le jaillissement confirme au joueur que SON action a été prise en compte, à
## l'instant où elle l'est ; l'installation lente, elle, dit que quelque chose
## de durable vient de changer dans la caverne. Une simple montée linéaire ne
## dirait ni l'un ni l'autre.
func _play_awakening() -> void:
	var tween: Tween = create_tween()

	if _glow != null:
		_glow.light_color = awakened_color
		tween.tween_property(_glow, "light_energy", awakened_energy * 1.8, 0.15) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tween.tween_property(_glow, "light_energy", awakened_energy, 1.1) \
			.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tween.parallel().tween_property(_glow, "omni_range", awakened_range, 1.1)

	if _material != null:
		tween.parallel().tween_property(_material, "emission", awakened_color, 0.6)
		tween.parallel().tween_property(_material, "emission_energy_multiplier", 2.4, 0.6)
		tween.parallel().tween_property(_material, "albedo_color", awakened_color, 0.6)

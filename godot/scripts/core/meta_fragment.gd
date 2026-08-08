class_name MetaFragment
extends Node3D

## Le Fragment du puzzle méta — la récompense de la Serrure de Givre.
##
## Chaque niveau du jeu en porte un ; les huit réunis débloquent la fin
## spéciale (cf `docs/design/puzzle_meta.md`). Celui du niveau 1 attend dans
## l'alcôve du Passage Effondré, invisible tant que la Porte tient : le voir à
## travers l'obstacle gâcherait la découverte.
##
## Il ne se ramasse pas encore — le système de collecte inter-niveaux
## n'existe pas. Il est ici comme PRÉSENCE : le joueur qui a résolu le puzzle
## doit trouver quelque chose au bout, sinon l'effort n'a rien payé. Sa
## collecte sera branchée quand le puzzle méta sera implémenté.

## Vitesse de rotation, en degrés par seconde. Lente : un objet sacré ne
## tournoie pas, il dérive.
@export var spin_speed: float = 22.0

## Amplitude du flottement vertical, en mètres.
@export var bob_amplitude: float = 0.18

## Période du flottement, en secondes.
@export var bob_period: float = 3.4

var _shard: MeshInstance3D
var _glow: OmniLight3D
var _base_height: float = 0.0
var _elapsed: float = 0.0


func _ready() -> void:
	_base_height = position.y
	_build_visual()
	set_process(false)


func _build_visual() -> void:
	_shard = MeshInstance3D.new()
	_shard.name = "Eclat"
	var mesh := PrismMesh.new()
	mesh.size = Vector3(0.5, 0.9, 0.5)
	_shard.mesh = mesh

	var material := StandardMaterial3D.new()
	# Violet : la palette réserve cette teinte aux cristaux rares (art bible
	# §3). Le fragment ne doit ressembler à AUCUN autre cristal du niveau,
	# sinon il se confond avec le puzzle qu'il récompense.
	material.albedo_color = Color(0.66, 0.55, 1.0)
	material.emission_enabled = true
	material.emission = Color(0.66, 0.55, 1.0)
	material.emission_energy_multiplier = 3.2
	material.metallic = 0.3
	material.roughness = 0.15
	_shard.material_override = material
	add_child(_shard)

	_glow = OmniLight3D.new()
	_glow.name = "Glow"
	_glow.light_color = Color(0.66, 0.55, 1.0)
	_glow.light_energy = 0.0
	_glow.omni_range = 12.0
	_glow.shadow_enabled = false
	_glow.light_volumetric_fog_energy = 2.0
	add_child(_glow)


## Apparition, déclenchée par l'effondrement de la Porte.
func reveal() -> void:
	visible = true
	set_process(true)
	var tween: Tween = create_tween()
	tween.tween_property(_glow, "light_energy", 4.5, 1.2) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	print("[MetaFragment] le fragment du niveau 1 est révélé.")


func _process(delta: float) -> void:
	_elapsed += delta
	rotate_y(deg_to_rad(spin_speed) * delta)
	position.y = _base_height + sin(_elapsed * TAU / bob_period) * bob_amplitude

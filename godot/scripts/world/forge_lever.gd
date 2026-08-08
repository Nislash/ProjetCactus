class_name ForgeLever
extends Interactable

## Le levier caché derrière la cascade. Il fait sortir l'escalier du donjon.
##
## ## Pourquoi il est LOIN de ce qu'il actionne
##
## Le levier est à soixante-dix mètres à l'ouest de la tour qu'il ouvre, et
## derrière un rideau de lave. C'est délibéré : un interrupteur posé au pied de
## ce qu'il commande n'est pas une énigme, c'est une porte avec deux étapes.
##
## La distance impose au contraire de retenir ce qu'on a vu — la tour sans
## accès — puis d'y revenir. Et le trajet de retour n'existe pas encore quand on
## tire le levier : c'est le pylône (cf [FragilePylon]) qui le fabrique. Les
## trois objets ne valent que les uns par les autres.
##
## ## Ce qu'il n'est pas
##
## Il ne se réarme pas. Un levier qu'on peut remettre dans l'autre sens invite à
## chercher ce que fait « l'autre position », et ici il n'y a rien à y trouver —
## ce serait une promesse vide.

signal pulled()

const HANDLE_IDLE := Color(0.62, 0.16, 0.11)
const HANDLE_LIVE := Color(1.000, 0.478, 0.184)
const STONE := Color(0.058, 0.049, 0.053)

var _pulled: bool = false
var _handle: Node3D
var _glow: OmniLight3D


func _ready() -> void:
	super._ready()
	prompt_text = "Actionner le levier"
	# Plus long qu'un ramassage : un levier qu'on effleure par accident en
	# passant ferait rater le moment. On veut que le geste soit décidé.
	hold_duration = 0.9
	interaction_range = 3.2
	selection_priority = 10
	_build()


func _build() -> void:
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 3.4
	shape.shape = sphere
	shape.position = Vector3(0.0, 1.6, 0.0)
	add_child(shape)

	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.9

	# LE SOCLE. Il porte le levier et, surtout, il le SIGNALE : une manette
	# plantée dans le sol nu se confondrait avec un caillou.
	var base := MeshInstance3D.new()
	base.name = "Socle"
	var base_mesh := CylinderMesh.new()
	base_mesh.top_radius = 1.05
	base_mesh.bottom_radius = 1.45
	base_mesh.height = 1.6
	base_mesh.radial_segments = 6
	base.mesh = base_mesh
	base.material_override = stone
	base.position = Vector3(0.0, 0.8, 0.0)
	add_child(base)

	_handle = Node3D.new()
	_handle.name = "Manette"
	_handle.position = Vector3(0.0, 1.6, 0.0)
	add_child(_handle)

	var lever := MeshInstance3D.new()
	lever.name = "Bras"
	var lever_mesh := BoxMesh.new()
	lever_mesh.size = Vector3(0.22, 2.2, 0.22)
	lever.mesh = lever_mesh
	var metal := StandardMaterial3D.new()
	metal.albedo_color = HANDLE_IDLE
	metal.emission_enabled = true
	metal.emission = HANDLE_IDLE
	metal.emission_energy_multiplier = 1.1
	metal.metallic = 0.5
	metal.roughness = 0.4
	lever.material_override = metal
	lever.position = Vector3(0.0, 1.1, 0.0)
	_handle.add_child(lever)
	# Incliné vers l'arrière au repos : une manette verticale ne dit pas dans
	# quel sens elle va basculer.
	_handle.rotation.x = deg_to_rad(-24.0)

	_glow = OmniLight3D.new()
	_glow.name = "Lueur"
	_glow.light_color = HANDLE_LIVE
	_glow.light_energy = 1.4
	_glow.omni_range = 9.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0.0, 2.4, 0.0)
	add_child(_glow)


func can_interact(_by_player: Node) -> bool:
	return not _pulled


func try_interact(_by_player: Node) -> bool:
	if _pulled:
		return false
	_pulled = true

	var tween: Tween = create_tween()
	tween.tween_property(_handle, "rotation:x", deg_to_rad(52.0), 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glow != null:
		tween.parallel().tween_property(_glow, "light_energy", 4.5, 0.35)
		tween.tween_property(_glow, "light_energy", 1.0, 1.2)
	tween.tween_callback(func() -> void: pulled.emit())
	print("[ForgeLever] levier tiré — l'escalier sort de la tour.")
	return true


func is_pulled() -> bool:
	return _pulled

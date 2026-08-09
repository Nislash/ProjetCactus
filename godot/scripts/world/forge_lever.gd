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

## Le maillage sculpté (Meshy, cf `assets/level02/assets_manifest.yaml`).
const MESH_PATH := "res://assets/level02/meshes/forge_lever.res"
const MATERIAL_PATH := "res://assets/level02/materials/forge_lever.tres"

## Hauteur voulue en jeu, en mètres. Le maillage arrive à une échelle que Meshy
## estime lui-même ; on le remet à la taille du niveau plutôt que de faire
## confiance à cette estimation.
const HEIGHT: float = 2.6

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

	# LE LEVIER SCULPTÉ.
	#
	# Il bascule TOUT ENTIER, socle compris, et c'est un compromis assumé : le
	# maillage vient d'une génération, ses pièces ne sont pas séparées, et rien
	# ne dit où finit la pierre et où commence le fer. Faire pivoter l'ensemble
	# de quelques degrés se lit comme un mécanisme qui joue dans son logement ;
	# tenter d'isoler la manette donnerait une découpe fausse.
	_handle = Node3D.new()
	_handle.name = "Levier"
	add_child(_handle)

	var mesh: Mesh = load(MESH_PATH) as Mesh
	if mesh == null:
		push_warning("ForgeLever : maillage absent — repli sur des primitives.")
		_build_fallback()
		return

	var body := MeshInstance3D.new()
	body.name = "Mesh"
	body.mesh = mesh
	var material: Material = load(MATERIAL_PATH) as Material
	if material != null:
		body.material_override = material
	_handle.add_child(body)

	# Remis à l'échelle du niveau depuis sa taille réelle : un asset généré
	# arrive à la taille que le générateur a cru bon de lui donner.
	var extent: Vector3 = mesh.get_aabb().size
	if extent.y > 0.01:
		_handle.scale = Vector3.ONE * (HEIGHT / extent.y)

	_add_glow()


## Repli si l'asset manque : le levier doit rester actionnable, sinon le niveau
## devient infinissable pour une texture absente.
func _build_fallback() -> void:
	var stone := StandardMaterial3D.new()
	stone.albedo_color = STONE
	stone.roughness = 0.9

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
	_handle.add_child(base)

	var arm := MeshInstance3D.new()
	arm.name = "Bras"
	var arm_mesh := BoxMesh.new()
	arm_mesh.size = Vector3(0.22, 2.2, 0.22)
	arm.mesh = arm_mesh
	arm.material_override = stone
	arm.position = Vector3(0.0, 2.2, 0.0)
	_handle.add_child(arm)

	_add_glow()


## LA LUEUR. Elle n'est pas décorative : le levier est au fond d'un palier
## sombre, et sans elle on ne le distingue pas de la roche. Un objet qu'on doit
## chercher au pixel près n'est pas caché, il est manquant.
func _add_glow() -> void:
	_glow = OmniLight3D.new()
	_glow.name = "Lueur"
	_glow.light_color = HANDLE_LIVE
	_glow.light_energy = 2.2
	_glow.omni_range = 12.0
	_glow.shadow_enabled = false
	_glow.position = Vector3(0.0, 1.8, 0.0)
	add_child(_glow)


func can_interact(_by_player: Node) -> bool:
	return not _pulled


func try_interact(_by_player: Node) -> bool:
	if _pulled:
		return false
	_pulled = true

	var tween: Tween = create_tween()
	# Quinze degrés, pas cinquante : c'est l'ensemble du bloc qui pivote, et
	# une bascule ample donnerait un socle de pierre qui se couche.
	tween.tween_property(_handle, "rotation:x", deg_to_rad(15.0), 0.55) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	if _glow != null:
		tween.parallel().tween_property(_glow, "light_energy", 6.0, 0.35)
		tween.tween_property(_glow, "light_energy", 1.4, 1.2)
	tween.tween_callback(func() -> void: pulled.emit())
	print("[ForgeLever] levier tiré — l'escalier sort de la tour.")
	return true


func is_pulled() -> bool:
	return _pulled

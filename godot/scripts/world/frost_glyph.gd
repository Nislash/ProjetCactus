class_name FrostGlyph
extends Node3D

## Le glyphe manette gravé dans le givre.
##
## Règle absolue de l'onboarding : **zéro mur de texte**. Le glyphe n'est donc
## pas un popup de HUD mais une gravure au sol ou au mur, près de l'objet
## concerné, qui s'illumine quand elle devient pertinente et s'éteint quand la
## leçon est apprise.
##
## Il affiche le bouton **dans la nomenclature du device détecté** : `A` sur
## une Xbox, `✕` sur une PlayStation. Un joueur PS à qui on montre « A »
## cherche un bouton qui n'existe pas sur sa manette.

## Les verbes que l'antichambre enseigne, et leur nom par famille de manette.
## Les sticks et gâchettes n'ont pas de nom court universel : on les nomme par
## leur position, qui est vraie partout.
const _LABELS: Dictionary = {
	&"join": {"xbox": "START", "playstation": "OPTIONS", "generic": "START"},
	&"move": {"xbox": "L", "playstation": "L", "generic": "L"},
	&"look": {"xbox": "R", "playstation": "R", "generic": "R"},
	&"shoot": {"xbox": "RT", "playstation": "R2", "generic": "RT"},
	&"interact": {"xbox": "A", "playstation": "✕", "generic": "A"},
}

const COLD := Color(0.40, 0.85, 1.00)

@export var verb: StringName = &"interact"
## Taille de la gravure. Une gravure au sol se lit de loin : 0,9 m par défaut.
@export var glyph_size: float = 0.9
## `true` = posée à plat dans le sol (gravure), `false` = sur une paroi.
@export var lies_on_floor: bool = true

var _label: Label3D
var _lit: bool = false


func _ready() -> void:
	_label = Label3D.new()
	_label.name = "Gravure"
	_label.text = label_for_device(verb, active_device_family())
	_label.font_size = 128
	_label.pixel_size = glyph_size / 128.0
	_label.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	_label.double_sided = true
	_label.no_depth_test = false
	_label.shaded = false
	_label.modulate = Color(COLD.r, COLD.g, COLD.b, 0.0)
	_label.outline_size = 0
	if lies_on_floor:
		# À plat, lisible depuis la direction de marche.
		_label.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
		_label.position = Vector3(0.0, 0.06, 0.0)
	add_child(_label)


## S'illumine. Un glyphe éteint n'est pas caché : il est gravé, simplement
## sans lueur — la présence de la gravure prépare le regard.
func light(duration: float = 0.8) -> void:
	if _lit or _label == null:
		return
	_lit = true
	_fade_to(1.0, duration)


## S'éteint : la leçon est apprise. Le monde ne répète pas.
func dim(duration: float = 0.6) -> void:
	if not _lit or _label == null:
		return
	_lit = false
	_fade_to(0.12, duration)


func is_lit() -> bool:
	return _lit


func _fade_to(alpha: float, duration: float) -> void:
	var tw: Tween = create_tween()
	tw.tween_method(
		func(a: float) -> void: _label.modulate = Color(COLD.r, COLD.g, COLD.b, a),
		_label.modulate.a, alpha, duration)


## La famille de manette du premier joueur inscrit. À quatre avec des
## manettes différentes il faudrait un glyphe par joueur ; ce n'est pas la
## peine tant que les gravures sont partagées — le cas est noté dans le doc.
static func active_device_family() -> String:
	var ids: Array[int] = PlayerManager.get_active_player_ids()
	if ids.is_empty():
		return "generic"
	return device_family(PlayerManager.get_device_id(ids[0]))


static func device_family(device_id: int) -> String:
	if device_id < 0:
		return "generic"
	var name: String = Input.get_joy_name(device_id).to_lower()
	if name.contains("ps") or name.contains("playstation") or name.contains("dualshock") \
			or name.contains("dualsense") or name.contains("sony"):
		return "playstation"
	if name.contains("xbox") or name.contains("xinput") or name.contains("microsoft"):
		return "xbox"
	return "generic"


static func label_for_device(for_verb: StringName, family: String) -> String:
	if not _LABELS.has(for_verb):
		return "?"
	var by_family: Dictionary = _LABELS[for_verb]
	return String(by_family.get(family, by_family["generic"]))

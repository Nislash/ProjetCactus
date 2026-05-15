class_name HealthBar3D
extends Node3D

## Jauge HP 3D billboard à attacher au-dessus d'une entité avec un
## HealthComponent. Cachée tant que current == max. Fill rouge → vert selon
## le ratio HP.
##
## Usage : ajouter en enfant de l'entité + appeler `bind_to(health_component)`.

@onready var _fill: MeshInstance3D = $Fill

const FULL_WIDTH: float = 1.0

var _fill_material: StandardMaterial3D


func _ready() -> void:
	# On clone le material pour pouvoir changer la couleur par instance.
	if _fill != null and _fill.material_override is StandardMaterial3D:
		_fill_material = (_fill.material_override as StandardMaterial3D).duplicate()
		_fill.material_override = _fill_material
	visible = false


func bind_to(health: HealthComponent) -> void:
	health.health_changed.connect(_on_health_changed)
	_on_health_changed(health.current_health, health.max_health)


func _on_health_changed(current: int, max_hp: int) -> void:
	if current >= max_hp or current <= 0:
		visible = false
		return
	visible = true
	var ratio: float = clamp(float(current) / float(max_hp), 0.0, 1.0)
	# Le fill se rétrécit depuis la droite : on scale.x et on offset à gauche
	# pour que le fill reste calé à gauche du background.
	_fill.scale.x = ratio
	_fill.position.x = -FULL_WIDTH * (1.0 - ratio) * 0.5
	# Couleur : rouge si bas, vert si plein, jaune au milieu.
	if _fill_material != null:
		var color: Color = Color(1.0 - ratio, ratio, 0.1, 1.0)
		_fill_material.albedo_color = color
		_fill_material.emission = color

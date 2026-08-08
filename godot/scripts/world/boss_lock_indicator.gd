class_name BossLockIndicator
extends Node3D

## Les quatre octogones du verrou, gravés en grand sur le Pilier de l'Îlot.
##
## ## Pourquoi sur le pilier du lac
##
## Ils étaient sur une dalle de deux mètres, plaquée contre la paroi du Seuil,
## à l'autre bout du niveau. On les frôlait sans les voir, et rien ne les
## reliait au lac où se joue l'énigme.
##
## Le Pilier de l'Îlot est **le seul objet visible de partout autour du lac**.
## Y graver le compteur en fait un cadran : où qu'on soit sur la rive, on sait
## combien de lettres sont posées, et on lève les yeux vers le même point que
## tout le monde. En coop, c'est ce qui remplace un appel vocal.
##
## ## Pourquoi quatre et pourquoi verticaux
##
## Quatre comme les lettres de « BOSS » — le compteur EST le mot. Empilés du
## bas vers le haut, ils se remplissent comme une jauge, ce qu'aucune
## disposition en cercle ne dirait aussi vite.

## Rayon des octogones, en mètres. Grand : ils se lisent depuis l'autre rive.
@export var glyph_radius: float = 1.15
## Espacement vertical. Resserré pour que les quatre tiennent dans le tiers
## bas du fût : étalés sur toute sa hauteur, le dernier frôlait la voûte et on
## ne pouvait plus les compter d'un regard.
@export var spacing: float = 2.7
@export var base_height: float = 3.6

## Le fût sur lequel on grave. Renseignés par [BossPuzzle] depuis la colonne
## réelle : sans eux, les octogones flottaient **à côté** du pilier au lieu
## d'y être incrustés — ils se lisaient comme une guirlande accrochée là,
## pas comme une gravure.
@export var shaft_bottom_radius: float = 2.6
@export var shaft_top_radius: float = 1.7
@export var shaft_height: float = 16.0

## Fraction du rayon à laquelle le CENTRE de l'anneau est posé.
##
## À 1, le centre tombe pile sur la surface du fût : l'anneau est donc à
## moitié dans la pierre et à moitié dehors — c'est ce qui se lit comme une
## gravure. En dessous, il s'enfonce et disparaît (essayé à 0,72 : on ne
## voyait plus que quelques éclats affleurants) ; au-dessus, il décolle et
## redevient une guirlande accrochée à côté du pilier.
@export_range(0.3, 1.4, 0.01) var sink: float = 1.0

var _rings: Array[MeshInstance3D] = []
var _materials: Array[StandardMaterial3D] = []
var _glow: OmniLight3D
var _lit: int = 0
var _total: int = 4


func _ready() -> void:
	_build()
	refresh(0, _total)


func _build() -> void:
	for i in _total:
		var ring := MeshInstance3D.new()
		ring.name = "Octogone_%d" % i
		var mesh := TorusMesh.new()
		mesh.inner_radius = glyph_radius * 0.62
		mesh.outer_radius = glyph_radius
		# Huit segments : un octogone, pas un cercle. Une forme taillée se lit
		# comme un ouvrage, un cercle parfait comme un effet.
		mesh.rings = 8
		mesh.ring_segments = 6
		ring.mesh = mesh
		# Debout, face à l'extérieur : un tore couché ne se verrait que d'en haut.
		ring.rotation_degrees = Vector3(90.0, 0.0, 0.0)
		var height: float = base_height + float(i) * spacing
		# Incrusté DANS le fût : on suit le rayon local, qui rétrécit avec la
		# hauteur puisque la colonne est conique. Un décalage constant aurait
		# laissé les anneaux du haut flotter dans le vide.
		ring.position = Vector3(0.0, height, _shaft_radius_at(height) * sink)

		# Éteint mais PAS invisible : un cadran qu'on ne voit qu'une fois
		# résolu n'aurait jamais dit au joueur qu'il y avait quelque chose à
		# résoudre. À travers la brume du lac, 0,15 ne se distinguait pas de
		# la roche.
		var material := CrystalGrammar.make_material(CrystalGrammar.COLOR_BOSS_LOCK, 0.9)
		ring.material_override = material
		add_child(ring)
		_rings.append(ring)
		_materials.append(material)

	var mid: float = base_height + spacing * 1.5
	_glow = CrystalGrammar.make_glow(CrystalGrammar.COLOR_BOSS_LOCK, 0.0, 26.0)
	_glow.position = Vector3(0.0, mid, _shaft_radius_at(mid) * sink)
	add_child(_glow)


## Rayon du fût à cette hauteur. La colonne est conique — plus large en bas.
func _shaft_radius_at(height: float) -> float:
	var t: float = clampf(height / maxf(shaft_height, 0.001), 0.0, 1.0)
	return lerpf(shaft_bottom_radius, shaft_top_radius, t)


## Met le cadran à jour. `lit` = nombre de lettres correctement posées.
func refresh(lit: int, total: int) -> void:
	_total = maxi(total, 1)
	_lit = clampi(lit, 0, _rings.size())
	for i in _materials.size():
		var on: bool = i < _lit
		var tween: Tween = create_tween()
		tween.tween_property(_materials[i], "emission_energy_multiplier",
			5.5 if on else 0.9, 0.45)
	if _glow != null:
		var tween: Tween = create_tween()
		tween.tween_property(_glow, "light_energy", float(_lit) * 1.1, 0.45)


## Le verrou cède : les quatre octogones s'embrasent d'un coup, puis
## redescendent. Le pilier tout entier sert de signal — à cette distance, une
## simple couleur ne se verrait pas.
func play_unlock() -> void:
	var tween: Tween = create_tween()
	for material in _materials:
		tween.parallel().tween_property(material, "emission_energy_multiplier", 12.0, 0.25)
	if _glow != null:
		tween.parallel().tween_property(_glow, "light_energy", 14.0, 0.25)
	tween.chain()
	for material in _materials:
		tween.parallel().tween_property(material, "emission_energy_multiplier", 5.0, 1.2)
	if _glow != null:
		tween.parallel().tween_property(_glow, "light_energy", 5.5, 1.2)

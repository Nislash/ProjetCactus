class_name CrystalGrammar
extends RefCounted

## La grammaire des cristaux : **une silhouette et une couleur par famille**.
##
## ## Le problème qu'elle règle
##
## La caverne est faite de cristaux. Certains donnent une arme, d'autres un
## pouvoir, d'autres ouvrent l'arène du boss, et l'immense majorité ne sont que
## du décor. Tant qu'ils se ressemblaient tous, le joueur ne pouvait pas savoir
## lequel valait le détour — et un signal qu'on ne peut pas lire n'est pas un
## signal.
##
## ## Les quatre familles
##
## | Famille | Silhouette | Couleur | Comportement |
## |---|---|---|---|
## | **Décor** | grappes, éclats muraux | cyan `#66d9ff` | immobile, inerte |
## | **Arme** | **lame** verticale plantée dans un socle | blanc glacé `#cfe4f2` | immobile — une arme attend, elle ne flotte pas |
## | **Pouvoir** | **octaèdre** qui flotte et tourne | couleur de l'élément | flotte : c'est de la magie, elle ne touche pas le sol |
## | **Verrou du boss** | **éclat hexagonal** | vert glaciaire `#5ef0c0` | pulse lentement, comme un battement |
##
## ## Pourquoi ces couleurs-là
##
## Le cyan est la couleur signature du niveau : elle appartient au décor, et
## la donner à un objet ramassable la banaliserait. Le blanc glacé est celui
## du jour qui entre par les puits — un objet taillé par quelqu'un, pas poussé
## par la caverne. Les pouvoirs gardent leur couleur d'élément, parce que
## savoir qu'une gemme est de feu compte plus que savoir que c'est une gemme.
##
## Le vert glaciaire n'existe **nulle part ailleurs** dans le niveau. C'est
## délibéré : la seule chose qui verrouille l'arène du boss doit être
## reconnaissable au premier coup d'œil et impossible à confondre. On a écarté
## l'ambre `#f2b45c`, qui dit déjà « esquive maintenant » dans les telegraphs
## du boss, et le violet `#a98bff`, qui appartient au fragment du puzzle méta.

enum Family { DECOR, WEAPON, POWER, BOSS_LOCK }

const COLOR_DECOR := Color(0.400, 0.851, 1.000)      # #66d9ff — cyan signature
const COLOR_WEAPON := Color(0.812, 0.894, 0.949)     # #cfe4f2 — blanc du jour
const COLOR_BOSS_LOCK := Color(0.369, 0.941, 0.753)  # #5ef0c0 — vert glaciaire
const COLOR_META := Color(0.663, 0.545, 1.000)       # #a98bff — fragment méta
const COLOR_DANGER := Color(0.949, 0.706, 0.361)     # #f2b45c — telegraphs boss


static func color_of(family: Family) -> Color:
	match family:
		Family.WEAPON: return COLOR_WEAPON
		Family.BOSS_LOCK: return COLOR_BOSS_LOCK
		Family.POWER: return COLOR_DECOR  # remplacé par la couleur d'élément
		_: return COLOR_DECOR


## La lame d'un socle d'arme. Haute, étroite, à quatre pans — elle se lit de
## loin comme une **lame plantée**, pas comme une pierre.
static func weapon_blade_mesh() -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.02
	mesh.bottom_radius = 0.19
	mesh.height = 1.5
	mesh.radial_segments = 4
	mesh.rings = 1
	return mesh


## La gemme d'un pouvoir : un octaèdre. Un solide régulier au milieu d'une
## caverne de formes cassées ne peut pas être confondu avec elle.
static func power_gem_mesh() -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = 0.26
	mesh.height = 0.72
	mesh.radial_segments = 4
	mesh.rings = 2
	return mesh


## L'éclat du verrou : hexagonal, trapu, taillé. Il tient dans la main — c'est
## ce qui dit qu'on peut l'emporter.
static func boss_shard_mesh() -> Mesh:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.10
	mesh.bottom_radius = 0.28
	mesh.height = 0.85
	mesh.radial_segments = 6
	mesh.rings = 1
	return mesh


## Matériau commun aux trois familles ramassables : un corps sombre traversé
## d'une émission forte. C'est l'émission qui porte la famille — le corps reste
## de la roche, partout pareil, ce qui fait ressortir la couleur.
static func make_material(color: Color, energy: float = 2.6) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color.darkened(0.55)
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.22
	material.metallic = 0.0
	return material


## Le halo d'un ramassable. Court : il doit se remarquer en approchant, pas
## éclairer la salle — sinon les glows muraux, qui sont la boussole du niveau,
## perdent leur rôle.
static func make_glow(color: Color, energy: float = 1.6, radius: float = 5.0) -> OmniLight3D:
	var light := OmniLight3D.new()
	light.name = "Glow"
	light.light_color = color
	light.light_energy = energy
	light.omni_range = radius
	light.shadow_enabled = false
	return light

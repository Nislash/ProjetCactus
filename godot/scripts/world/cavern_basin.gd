## Creux BORDÉ — DATA UNIQUEMENT.
##
## Correspond aux cuvettes de la spec créative (C1 dans la forêt, le lac gelé,
## le bol de l'arène). La margelle [member rim_height] n'est pas décorative :
## c'est **le mécanisme qui rend la chute impossible**, exigé par la contrainte
## dure du plan. Elle vit dans la donnée pour être vérifiable automatiquement
## (cf tests d'étanchéité), et non dans la vigilance du level designer.
## Cf `docs/design/level01_topography.md` §7.

class_name CavernBasin
extends Resource

## Nom lisible, uniquement pour s'y retrouver dans l'inspecteur et les erreurs.
@export var label: String = ""

## Centre du creux en mètres (X, Z).
@export var center: Vector2 = Vector2.ZERO

## Rayons du creux en mètres. Toujours elliptique.
@export var radii: Vector2 = Vector2(6.0, 6.0)

## Profondeur du fond sous l'altitude du terrain environnant, en mètres.
@export_range(0.0, 12.0, 0.1) var depth: float = 1.0

## Hauteur de la margelle au-dessus du terrain environnant, en mètres.
## Zéro = cuvette non bordée = chute possible : les tests le refusent.
@export_range(0.0, 6.0, 0.1) var rim_height: float = 0.5

## Largeur de la margelle, en mètres : la distance sur laquelle le bourrelet
## retombe vers le terrain environnant.
@export_range(0.5, 15.0, 0.5) var rim_width: float = 3.0

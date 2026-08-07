## Zone d'altitude constante — DATA UNIQUEMENT.
##
## Correspond à une « zone » de la spec créative (corniche Z1, lac Z3, terrasses
## du nid Z4…). Rectangle par défaut, ellipse si [member is_ellipse].
## Cf `docs/design/level01_topography.md` §3.

class_name CavernPlateau
extends Resource

## Nom lisible, uniquement pour s'y retrouver dans l'inspecteur et les erreurs.
@export var label: String = ""

## Centre en mètres, dans le plan (X, Z).
@export var center: Vector2 = Vector2.ZERO

## Demi-étendue en mètres : demi-largeur/demi-profondeur du rectangle, ou rayons
## de l'ellipse.
@export var half_extent: Vector2 = Vector2(10.0, 10.0)

## Si vrai, la zone est une ellipse plutôt qu'un rectangle.
@export var is_ellipse: bool = false

## Altitude imposée à l'intérieur de la zone.
@export var altitude: float = 0.0

## Distance en mètres sur laquelle l'altitude se fond dans le terrain existant,
## au-delà de la bordure. Zéro donnerait une marche franche : à éviter sur du
## sol praticable.
@export_range(0.0, 30.0, 0.5) var falloff: float = 6.0

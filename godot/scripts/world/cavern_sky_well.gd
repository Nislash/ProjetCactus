## Puits de ciel — DATA UNIQUEMENT.
##
## Une ouverture percée dans le **maillage visuel** de la voûte. La collision de
## la voûte, elle, reste pleine : on voit le ciel, on ne sort jamais. C'est ce
## qui satisfait la contrainte dure « volume fermé » par construction, sans avoir
## à poser des collisions invisibles à la main au-dessus de chaque trou.
## Cf `docs/design/level01_topography.md` §6 et l'ADR `docs/tech/level01_terrain.md`.

class_name CavernSkyWell
extends Resource

## Nom lisible (P1, P2…), pour s'y retrouver dans l'inspecteur et les erreurs.
@export var label: String = ""

## Centre de l'ouverture en mètres (X, Z).
@export var center: Vector2 = Vector2.ZERO

## Diamètre de l'ouverture en mètres.
@export_range(1.0, 30.0, 0.5) var diameter: float = 8.0

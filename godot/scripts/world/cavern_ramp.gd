## Liaison pentue entre deux altitudes — DATA UNIQUEMENT.
##
## Correspond aux rampes de la spec créative (descentes de la forêt Z2, montée
## du seuil, rampes d'arène RN/RS). L'altitude est interpolée le long du segment
## [member from_point] → [member to_point], sur une bande de largeur
## [member width]. Cf `docs/design/level01_topography.md` §7 et §8.

class_name CavernRamp
extends Resource

## Nom lisible, uniquement pour s'y retrouver dans l'inspecteur et les erreurs.
@export var label: String = ""

## Départ de la rampe en mètres (X, Z).
@export var from_point: Vector2 = Vector2.ZERO

## Arrivée de la rampe en mètres (X, Z).
@export var to_point: Vector2 = Vector2(10.0, 0.0)

## Altitude au départ.
@export var from_altitude: float = 0.0

## Altitude à l'arrivée.
@export var to_altitude: float = 0.0

## Largeur totale de la bande, en mètres.
@export_range(1.0, 40.0, 0.5) var width: float = 6.0

## Distance de fondu de part et d'autre de la bande.
@export_range(0.0, 20.0, 0.5) var falloff: float = 4.0

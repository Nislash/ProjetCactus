## Ouverture dans la voûte — DATA UNIQUEMENT.
##
## Remplace l'ancien `CavernSkyWell`, qui ne savait faire que des disques. Les
## croquis demandent des trous de forme libre : ellipse orientée, et plusieurs
## ouvertures qui se recouvrent pour composer un contour irrégulier — le même
## procédé que les chambres pour la silhouette du volume.
##
## Le maillage de la voûte est percé ici ; sa COLLISION reste pleine. On voit le
## ciel, on ne sort jamais.

class_name CavernSkyOpening
extends Resource

@export var label: String = ""

## Centre de l'ouverture, en mètres (X, Z).
@export var center: Vector2 = Vector2.ZERO

## Demi-axes de l'ellipse, en mètres.
@export var radii: Vector2 = Vector2(4.0, 4.0)

## Rotation de l'ellipse, en degrés.
@export_range(-180.0, 180.0, 1.0) var rotation_degrees: float = 0.0

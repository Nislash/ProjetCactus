## Données du terrain de la caverne (niveau 1) — DATA UNIQUEMENT, aucune logique.
##
## Décrit un volume clos par deux champs de hauteurs : le sol et la voûte. Chacun
## est composé de primitives qui parlent la même langue que la spec créative
## (`docs/design/level01_topography.md`) : des **plateaux**, des **rampes** et des
## **cuvettes bordées**. Itérer sur la topographie = éditer ce `.tres`, pas
## resculpter un mesh (cf ADR `docs/tech/level01_terrain.md`).
##
## Le générateur qui consomme ces données est `cavern_terrain_builder.gd`.

class_name CavernTerrainData
extends Resource

## Coin minimum de l'emprise, en mètres (X, Z). Topo §2 : (-45, -28).
@export var bounds_min: Vector2 = Vector2(-45.0, -28.0)

## Coin maximum de l'emprise, en mètres (X, Z). Topo §2 : (+48, +26).
@export var bounds_max: Vector2 = Vector2(48.0, 26.0)

## Pas d'échantillonnage en mètres. 1 m donne ~5 000 points sur l'emprise du
## niveau 1 : assez fin pour des pentes propres, assez grossier pour rester
## gratuit. Le mesh ET la collision utilisent cette valeur (le builder les garde
## synchronisés — ne pas la changer d'un côté seulement).
@export_range(0.25, 4.0, 0.25) var cell_size: float = 1.0

## Champ de hauteurs du sol praticable.
@export var floor_field: CavernHeightfieldSpec

## Champ de hauteurs de la voûte. Son maillage visuel est troué aux `sky_wells`,
## mais sa collision reste pleine : on voit le ciel, on ne sort jamais.
@export var vault_field: CavernHeightfieldSpec

## Puits de ciel : ouvertures percées dans le MAILLAGE de la voûte uniquement.
@export var sky_wells: Array[CavernSkyWell] = []

## Hauteur libre minimale exigée entre sol et voûte (contrainte dure du plan).
@export var min_headroom: float = 10.0

## Hauteur libre maximale exigée entre sol et voûte (contrainte dure du plan).
@export var max_headroom: float = 15.0

## Pente maximale tolérée sur le sol, en degrés. Au-delà, le terrain est
## considéré comme non praticable et les tests échouent.
@export var max_slope_degrees: float = 25.0

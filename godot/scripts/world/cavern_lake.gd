## Lac de la caverne — DATA UNIQUEMENT.
##
## Une nappe plane posée à une altitude fixe, rendue partout où le sol passe en
## dessous ET où la caverne existe. Elle ne peut pas venir du champ de hauteurs
## du sol : un heightfield n'a qu'une surface par point, or un lac EST une
## seconde surface au-dessus du fond.
##
## Le fond du lac reste donc du terrain normal — praticable, mesuré par les
## tests d'étanchéité. Le lac n'ajoute qu'une surface visuelle et, à terme, un
## volume de gameplay (ralentissement, glace qui se brise).

class_name CavernLake
extends Resource

## Nom lisible.
@export var label: String = "Lac"

## Altitude de la surface, en mètres. Le lac apparaît là où le sol est en
## dessous.
@export var surface_altitude: float = 0.0

## Marge sous la surface en deçà de laquelle on ne dessine pas de nappe, en
## mètres. Évite un liseré d'eau d'un centimètre sur toute la rive, qui
## scintillerait au moindre mouvement de caméra (z-fighting).
@export_range(0.0, 2.0, 0.05) var minimum_depth: float = 0.15

## Centre de l'emprise du lac, en mètres (X, Z).
##
## SANS EMPRISE, la nappe se dessine partout où le sol passe sous son altitude —
## y compris au fond du bol de l'arène, qui se retrouvait inondé. Un lac occupe
## une cuvette précise, pas tous les points bas de la caverne.
@export var center: Vector2 = Vector2.ZERO

## Demi-axes de l'emprise, en mètres.
@export var radii: Vector2 = Vector2(40.0, 40.0)

## Chemin du matériau de la nappe (glace ou eau). Chargé par chemin plutôt
## qu'assigné : le MCP Godot n'écrit pas les propriétés typées `Resource`
## (cf docs/tech/godot_mcp_setup.md).
@export_file("*.tres") var material_path: String = ""

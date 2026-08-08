## Données du terrain de la caverne (niveau 1) — DATA UNIQUEMENT, aucune logique.
##
## Le volume est décrit par trois choses :
##
## 1. UNE SILHOUETTE — l'union de [member chambers]. La caverne existe là où une
##    poche la déclare, et nulle part ailleurs. C'est ce qui remplace l'emprise
##    rectangulaire de la première version, incapable de produire une forme
##    organique.
##
## 2. UN SOL — champ de hauteurs composé de plateaux, rampes et cuvettes bordées.
##
## 3. UNE HAUTEUR LIBRE — et non une voûte en altitude absolue. La voûte vaut
##    `sol + hauteur libre`, ce qui rend la contrainte « 10-15 m au-dessus du sol »
##    structurelle plutôt que réglée à la main.
##
## Aux abords de la silhouette, la hauteur libre tend vers ZÉRO : le sol rejoint
## la voûte et le volume SE REFERME TOUT SEUL. Il n'y a donc ni jupe de parois à
## générer, ni jonction à surveiller — l'étanchéité est une propriété de la
## construction, pas un résultat à vérifier.
##
## Itérer sur la topographie = éditer ce `.tres` (cf ADR `docs/tech/level01_terrain.md`).

class_name CavernTerrainData
extends Resource

## Coin minimum de la zone échantillonnée, en mètres (X, Z). C'est une simple
## fenêtre de calcul : la forme réelle vient des chambres.
@export var bounds_min: Vector2 = Vector2(-150.0, -100.0)

## Coin maximum de la zone échantillonnée, en mètres (X, Z).
@export var bounds_max: Vector2 = Vector2(150.0, 100.0)

## Pas d'échantillonnage en mètres.
##
## Sur une emprise de 300 × 200 m, 1,0 m donnerait 60 000 points par champ et
## 120 000 triangles par surface. 1,5 m divise cela par plus de deux tout en
## gardant un relief lisible : le grain fin vient du matériau, pas de la
## géométrie.
@export_range(0.5, 4.0, 0.25) var cell_size: float = 1.5

## Poches qui composent la silhouette du volume. Vide = aucune caverne.
@export var chambers: Array[CavernChamber] = []

## Champ de hauteurs du sol praticable.
@export var floor_field: CavernHeightfieldSpec

## Modulation de la hauteur libre, ajoutée à celle déclarée par les chambres.
## Facultatif : sert à creuser une nef ou à écraser un passage sans redéfinir
## les poches.
@export var headroom_field: CavernHeightfieldSpec

## Ouvertures percées dans le MAILLAGE de la voûte (sa collision reste pleine).
@export var sky_openings: Array[CavernSkyOpening] = []

## Nappe d'eau ou de glace. Nulle = pas de lac.
@export var lake: CavernLake

## Hauteur libre minimale dans les zones jouables (contrainte dure du plan).
## À CIEL OUVERT. Aucune voûte n'est construite : le volume est borné par des
## falaises, pas par un plafond.
##
## La hauteur libre continue d'être CALCULÉE — elle définit la zone jouable et
## sert aux tests — mais plus aucune géométrie ne la matérialise. Le joueur
## voit le ciel ; le moteur, lui, raisonne comme avant.
@export var open_sky: bool = false

## Hauteur des falaises qui bordent un niveau à ciel ouvert, en mètres.
##
## Elles remplacent la voûte dans son rôle d'enceinte : là où le masque des
## chambres retombe à zéro, le SOL monte de cette hauteur au lieu que le
## plafond descende. C'est ce qui garantit « aucune sortie » sans plafond.
@export var open_sky_rim_height: float = 34.0

@export var min_headroom: float = 10.0

## Hauteur libre maximale (contrainte dure du plan).
@export var max_headroom: float = 15.0

## En deçà de cette hauteur libre, on considère qu'on n'est plus dans le volume
## jouable mais dans la paroi qui le referme. Sert aux tests et à la cuisson du
## navmesh, pour qu'ils ne jugent pas la roche comme du sol.
@export var playable_headroom_threshold: float = 2.5

## Pente maximale tolérée sur le sol JOUABLE, en degrés.
@export var max_slope_degrees: float = 36.0

## Côté d'une tuile de maillage, en mètres.
##
## À cette échelle, un maillage unique serait toujours dessiné en entier : on
## perdrait tout le culling et les quelques draw calls par viewport deviendraient
## un mur. Le découpage en tuiles rend le frustum culling efficace.
@export_range(16.0, 128.0, 8.0) var chunk_size: float = 48.0

## Poche de caverne — DATA UNIQUEMENT.
##
## C'est la primitive qui définit **où la caverne existe**. L'union des chambres
## dessine la silhouette du volume ; partout ailleurs, c'est de la roche pleine.
##
## Elle remplace l'emprise rectangulaire de la première version. Un rectangle ne
## sait produire qu'une boîte : impossible d'en tirer la forme organique des
## croquis. Une union de poches, si — et c'est exactement ainsi qu'on lit un
## plan de caverne dessiné à la main : des salles reliées par des goulets.
##
## UNE SEULE PRIMITIVE POUR LES DEUX. Sans [member to_center], la chambre est
## une ellipse (une salle). Avec, c'est une capsule entre deux points (un
## couloir). Les couloirs étant des salles étirées, les distinguer n'apporterait
## qu'un second vocabulaire à apprendre.

class_name CavernChamber
extends Resource

## Nom lisible (« Salle du boss », « Goulet nord »…), pour l'inspecteur et les
## messages d'erreur.
@export var label: String = ""

## Centre de la poche, en mètres (X, Z). Départ de la capsule si
## [member to_center] est renseigné.
@export var center: Vector2 = Vector2.ZERO

## Second foyer. Laissé à zéro (et [member is_corridor] à faux), la chambre est
## une simple ellipse.
@export var to_center: Vector2 = Vector2.ZERO

## Vrai pour traiter la chambre comme une capsule `center` → `to_center`.
@export var is_corridor: bool = false

## Rayons de la poche en mètres. Pour un couloir, seul `x` est utilisé comme
## demi-largeur.
@export var radii: Vector2 = Vector2(20.0, 20.0)

## Rotation de l'ellipse en degrés. Sans elle, toutes les salles seraient
## alignées sur les axes et la caverne aurait l'air d'un plan de métro.
@export_range(-180.0, 180.0, 1.0) var rotation_degrees: float = 0.0

## Distance sur laquelle la poche se referme vers la roche pleine, en mètres.
##
## C'est le paramètre qui règle la RAIDEUR DES PAROIS : la hauteur libre passe
## de sa valeur intérieure à zéro sur cette distance. Court = falaise, long =
## évasement. Cf `CavernTerrainBuilder.min_falloff_for` pour le dimensionner
## plutôt que de l'écrire au jugé.
@export_range(1.0, 40.0, 0.5) var edge_softness: float = 8.0

## Hauteur libre visée à l'intérieur de cette poche, en mètres. Bornée ensuite
## par les limites globales du terrain. Permet des salles basses et oppressantes
## à côté de nefs hautes, sans toucher au champ de voûte.
@export_range(0.0, 40.0, 0.5) var headroom: float = 12.0

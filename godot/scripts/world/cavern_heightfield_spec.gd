## Spécification d'un champ de hauteurs — DATA UNIQUEMENT, aucune logique.
##
## Les primitives s'appliquent dans l'ordre : plateaux, puis rampes, puis
## cuvettes. Chacune mélange sa contribution selon son adoucissement, de sorte
## qu'aucune ne crée de marche franche. Le bruit final ajoute les ondulations
## demandées par la spec créative sans jamais dominer le relief voulu.

class_name CavernHeightfieldSpec
extends Resource

## Altitude par défaut, là où aucune primitive ne s'applique.
@export var base_altitude: float = 0.0

## Zones d'altitude (corniche, lac, terrasses…).
@export var plateaus: Array[CavernPlateau] = []

## Liaisons pentues entre zones (rampes, montée du seuil…).
@export var ramps: Array[CavernRamp] = []

## Creux bordés. La margelle est ce qui rend la chute impossible.
@export var basins: Array[CavernBasin] = []

## Amplitude des ondulations de surface, en mètres (±). 0 = surface lisse.
@export_range(0.0, 2.0, 0.05) var noise_amplitude: float = 0.0

## Échelle spatiale du bruit, en mètres. Plus grand = ondulations plus larges.
@export_range(2.0, 40.0, 1.0) var noise_scale: float = 12.0

## Graine du bruit. Fixe : deux générations doivent donner le même terrain,
## sinon on ne peut plus comparer un avant/après ni reproduire un bug.
@export var noise_seed: int = 20260808

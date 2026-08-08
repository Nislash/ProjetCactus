## Cuit le NavigationMesh de la caverne à l'exécution (E2 #12).
##
## POURQUOI À L'EXÉCUTION
## Le terrain est généré au `_ready` depuis une [CavernTerrainData] : il n'existe
## pas au moment où l'éditeur pourrait cuire un navmesh. Le cuire ici garantit
## que la navigation correspond TOUJOURS au relief réellement construit — pas à
## un état antérieur oublié dans la scène, ce qui est le mode de panne classique
## d'un navmesh cuit à la main.
##
## LES PARAMÈTRES D'AGENT NE SONT PAS ARBITRAIRES
## Ils sont dérivés de la capsule du joueur (rayon 0,4 m, hauteur 1,8 m) et de
## son `floor_max_angle`. Si le navmesh acceptait des pentes que le joueur ne
## peut pas gravir, les ennemis atteindraient des zones inaccessibles aux
## joueurs ; s'il en refusait, ils resteraient bloqués devant des pentes que les
## joueurs montent. Les deux cassent le combat.

class_name CavernNavigation
extends NavigationRegion3D

## Rayon d'agent. Capsule joueur 0,4 m + marge pour ne pas raser les parois.
##
## MULTIPLE EXACT de [member cell_size] : le baker arrondit ce rayon au voxel
## SUPÉRIEUR. En 0,55 avec des voxels de 0,25, l'agent cuit valait en réalité
## 0,75 m — les passages étroits de la spec (2,5 m) auraient été jugés sur une
## largeur d'agent que personne n'avait choisie.
@export var agent_radius: float = 0.5

## Hauteur d'agent. MULTIPLE EXACT de [member cell_height] (8 voxels), que le
## baker arrondit au SUPÉRIEUR.
##
## 2,0 plutôt que les 1,8 de la capsule joueur : arrondir vers le HAUT est le
## sens sûr — le navmesh ne promet jamais un passage où le joueur ne tiendrait
## pas. La voûte étant partout à 10-15 m, aucun passage bas n'est perdu.
@export var agent_height: float = 2.0

## Pente maximale franchissable. DOIT rester alignée sur le `floor_max_angle`
## du CharacterBody3D du joueur (45° par défaut dans Godot) — voir l'entête.
@export var agent_max_slope_degrees: float = 45.0

## Hauteur de marche franchissable. MULTIPLE EXACT de [member cell_height], que
## le baker arrondit au voxel INFÉRIEUR.
@export var agent_max_climb: float = 0.5

## Finesse de la grille de voxelisation. 0,25 m tient le compromis entre
## précision sur le relief et temps de cuisson sur une emprise de ~100 × 55 m.
@export var cell_size: float = 0.25

## DOIT correspondre au `cell_height` de la carte de navigation (0,25 par
## défaut moteur). Un écart provoque des erreurs de rastérisation sur les bords
## du navmesh — Godot le signale, et ça se traduit en pathing qui accroche.
## Changer la carte plutôt que le navmesh toucherait `project.godot`, zone
## partagée : on s'aligne sur le moteur.
@export var cell_height: float = 0.25

## Nœud dont la géométrie est parsée. Laissé vide : le parent.
@export var geometry_root_path: NodePath

## Émis quand la cuisson est terminée et la région active.
signal navigation_baked(polygon_count: int)


func _ready() -> void:
	# Un frame d'attente : le terrain se construit dans son propre `_ready`, et
	# l'ordre d'appel entre nœuds frères n'est pas un contrat sur lequel
	# s'appuyer.
	await get_tree().process_frame
	bake_now()


## Cuit le navmesh depuis la géométrie présente dans la scène. Retourne le
## nombre de polygones produits (0 = échec, la géométrie n'a pas été trouvée).
func bake_now() -> int:
	var root: Node = get_node_or_null(geometry_root_path) if not geometry_root_path.is_empty() else get_parent()
	if root == null:
		push_error("CavernNavigation : racine de géométrie introuvable.")
		return 0

	var mesh := NavigationMesh.new()
	mesh.cell_size = cell_size
	mesh.cell_height = cell_height
	mesh.agent_radius = agent_radius
	mesh.agent_height = agent_height
	mesh.agent_max_slope = agent_max_slope_degrees
	mesh.agent_max_climb = agent_max_climb
	# On parse les maillages visibles plutôt que les collisions : le sol et la
	# voûte partagent leur géométrie, mais la voûte a une collision PLEINE aux
	# puits de ciel alors que son maillage est troué. Parser les collisions
	# ferait donc croire à un plafond navigable au-dessus des puits.
	# On parse les COLLISIONS, pas les maillages visuels : Godot avertit que
	# parser du visuel exige un readback GPU (coûteux en runtime, et inopérant en
	# headless — donc intestable en CI).
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	# Et on ne parse QUE le sol praticable, grâce à son bit dédié. Un baker ne
	# raisonne qu'en pentes : une voûte horizontale à 12 m lui paraît parfaitement
	# marchable. Sans ce filtre, la navigation se cuit aussi au plafond et les
	# points de départ se retrouvent projetés 12 m au-dessus du sol.
	mesh.geometry_collision_mask = CavernTerrainBuilder.NAVMESH_SOURCE_LAYER
	mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN

	var source := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, source, root)
	if source.get_vertices().is_empty():
		push_error("CavernNavigation : aucune géométrie source trouvée sous « %s »." % root.name)
		return 0

	NavigationServer3D.bake_from_source_geometry_data(mesh, source)
	navigation_mesh = mesh

	var count: int = mesh.get_polygon_count()
	navigation_baked.emit(count)
	return count

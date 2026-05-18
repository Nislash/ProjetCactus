## LevelLayout — Resource sérialisable produite par tools/dungeon_pipeline.
##
## Contient toute la géométrie 2D-par-strate d'un niveau plus ses métadonnées
## (rooms, doors, stairs, contents). Le runtime [DungeonBuilder] instancie
## une GridMap 3D à partir de ces données.
##
## Note pour le pipeline : cette classe est l'unique contrat entre la pipeline
## Python (`tools/dungeon_pipeline/`) et Godot. Si l'un de ses champs change,
## le sérialiseur `tools/dungeon_pipeline/export/godot_resource.py` doit
## suivre — sinon les `.tres` générés deviennent invalides.
class_name LevelLayout
extends Resource

## Identifiant stable du niveau, ex. "level_1".
@export var level_id: String = ""

## Nom lisible, ex. "N1 — Caverne crystalline".
@export var level_name: String = ""

## Seed RNG utilisé pour la génération (déterminisme).
@export var seed: int = 0

## Taille de la grille 3D en cellules : (width_x, strata_count_y, depth_z).
@export var grid_size: Vector3i = Vector3i.ZERO

## Taille world-space d'une cellule (mètres). Par défaut 4×3×4.
@export var cell_size: Vector3 = Vector3(4.0, 3.0, 4.0)

## Liste ordonnée des strates présentes, de la plus basse à la plus haute.
## ex: ["-2", "-1", "0"] → Y=0 est la strate -2.
@export var strata: PackedStringArray = PackedStringArray()

## ID de la room où spawner les joueurs.
@export var spawn_room: String = ""

## room_id -> {x:int, y:int, z:int, w:int, h:int, d:int, stratum:String, type:String}
## - (x, y, z) = coin origin de la room dans la grille
## - (w, h, d) = taille de la room (h toujours 1, une strate)
## - type ∈ {spawn, combat_small, combat_large, boss_arena, loot, secret, corridor, door}
@export var rooms: Dictionary = {}

## Tile data plat : longueur = grid_size.x * grid_size.y * grid_size.z.
## Indexation : cells[y * (depth * width) + z * width + x]
## Valeurs : voir TILE_ID_BY_TAG dans tools/dungeon_pipeline/export/godot_resource.py
##   0=void 1=floor 2=wall 3=corridor 4=secret 5=door 6=boss_door 7=secret_door
##   8=stair_up 9=stair_down 10=drop 11=drop_landing 12=jump_pad 13=drift
@export var cells: PackedByteArray = PackedByteArray()

## Array de Dictionary {id, x, y, z, locked, unlock_keys: Array[String]}
@export var doors: Array = []

## Array de Dictionary décrivant les transitions verticales
## {kind, from_room, to_room, from_x, from_y, from_z, to_x, to_y, to_z}
## kind ∈ {stairs, ladder, elevator, jump_required, one_way_drop}
@export var stairs: Array = []

## room_id -> Dictionary des contenus
## {spawn:bool, mini_boss:bool, loot_major:int, meta_fragment:bool,
##  checkpoint:bool, puzzle_triggers:Array[String]}
@export var contents: Dictionary = {}

## {from_room, trigger, target_level} ou {} si dernier niveau.
@export var inter_level: Dictionary = {}


## Renvoie le tile_id d'une cellule, 0 (void) si hors bounds.
func get_tile(x: int, y: int, z: int) -> int:
	if x < 0 or y < 0 or z < 0:
		return 0
	if x >= grid_size.x or y >= grid_size.y or z >= grid_size.z:
		return 0
	var idx: int = y * (grid_size.z * grid_size.x) + z * grid_size.x + x
	if idx < 0 or idx >= cells.size():
		return 0
	return cells[idx]


## Itère sur toutes les cellules non-void en yieldant (x, y, z, tile_id).
## (Pas un vrai iterator GDScript — utilise un for sur un Array.)
func iter_non_void_cells() -> Array:
	var out: Array = []
	for y in range(grid_size.y):
		for z in range(grid_size.z):
			for x in range(grid_size.x):
				var idx: int = y * (grid_size.z * grid_size.x) + z * grid_size.x + x
				var v: int = cells[idx]
				if v != 0:
					out.append([x, y, z, v])
	return out

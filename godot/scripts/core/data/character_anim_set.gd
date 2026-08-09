class_name CharacterAnimSet
extends Resource

## Pack d'animations modulaire pour un personnage (player / ennemi / boss).
## Pointe vers un .glb de modèle (skeleton + mesh, anim T-pose ignorée) et un
## set de .glb d'animations. CharacterVisual les charge à _ready() et construit
## une AnimationLibrary unique. Pour changer le visuel d'une entité : swap
## ce .tres dans l'inspecteur — aucun autre code à toucher.
##
## Convention de noms d'états (StringName) consommés par CharacterAnimator :
## - &"idle"
## - &"walk"
## - &"run"
## - &"jump"
## - &"shoot_walk_forward"
## - &"shoot_walk_back"
## - &"shoot_run"
## - &"death"
## - &"melee_combo"

@export var display_name: String = "Sentinel"

@export_group("Bibliothèque")
## Bibliothèque d'animations préparée par `tools/bake_character.gd`.
##
## C'est la voie recommandée, et de loin : un pack Meshy livre chaque clip dans
## un `.glb` qui embarque AUSSI le maillage et ses textures — dix-huit
## animations pèsent cent vingt-deux mégaoctets, dont cent quinze de doublons.
## La bibliothèque équivalente en fait sept cent soixante-dix-huit KILOoctets.
##
## Quand elle est renseignée, les emplacements individuels ci-dessous sont
## ignorés. Ils restent là pour le personnage « Sentinel », importé avant que ce
## chemin n'existe.
@export var library: AnimationLibrary

@export_group("Modèle")
## .glb du personnage (skeleton + mesh). Anim interne ignorée.
@export var model_scene: PackedScene

@export_group("Animations")
@export var idle: PackedScene
@export var walk: PackedScene
@export var run: PackedScene
@export var jump: PackedScene
@export var shoot_walk_forward: PackedScene
@export var shoot_walk_back: PackedScene
@export var shoot_run: PackedScene
@export var death: PackedScene
@export var melee_combo: PackedScene

@export_group("Réglages")
## Échelle uniforme appliquée au modèle (1.0 = taille Meshy d'origine).
@export var scale: float = 1.0
## Offset Y appliqué au modèle (utile si le pivot du .glb n'est pas aux pieds).
@export var y_offset: float = 0.0
## Rotation Y (deg) appliquée au modèle. 180 pour les .glb Meshy qui
## regardent +Z (forward Godot = -Z, il faut donc retourner).
@export var y_rotation_deg: float = 0.0
## Loop par défaut sur idle/walk/run.
@export var loop_locomotion: bool = true


## Les états réellement disponibles pour ce personnage.
##
## AUCUNE ANIMATION N'EST OBLIGATOIRE. Un personnage qui n'a qu'un `idle` doit
## rester jouable — c'est ce qui permet d'en essayer un nouveau sans avoir
## produit ses trente clips. Ce que le personnage n'a pas, le moteur le
## remplace par le plus proche parent (cf `CharacterVisual.resolve_state`).
func available_states() -> Array[StringName]:
	var out: Array[StringName] = []
	if library != null:
		for name in library.get_animation_list():
			out.append(name)
		return out
	for entry in iter_clips():
		out.append(entry[0])
	return out


## Retourne la liste (state_name, packed_scene) des animations renseignées.
## Utilisé par CharacterVisual pour itérer sans hardcoder la liste.
func iter_clips() -> Array:
	var out: Array = []
	if idle != null: out.append([&"idle", idle])
	if walk != null: out.append([&"walk", walk])
	if run != null: out.append([&"run", run])
	if jump != null: out.append([&"jump", jump])
	if shoot_walk_forward != null: out.append([&"shoot_walk_forward", shoot_walk_forward])
	if shoot_walk_back != null: out.append([&"shoot_walk_back", shoot_walk_back])
	if shoot_run != null: out.append([&"shoot_run", shoot_run])
	if death != null: out.append([&"death", death])
	if melee_combo != null: out.append([&"melee_combo", melee_combo])
	return out

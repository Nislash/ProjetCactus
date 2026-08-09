extends SceneTree

## Réduit un pack d'animations Meshy en une seule bibliothèque d'animations.
##
##   godot --headless --path godot --script tools/bake_character.gd -- --character=conqueror
##
## ## Le problème
##
## Meshy exporte chaque animation en `.glb` « withSkin » : le clip, MAIS AUSSI
## le maillage complet et ses textures. Dix-huit animations pèsent donc cent
## vingt-deux mégaoctets, dont cent quinze de maillage recopié dix-huit fois.
##
## Le personnage « Sentinel » a été importé comme ça et pèse 161 Mo à lui seul,
## avec une texture de huit mégaoctets extraite PAR animation. À deux
## personnages on dépasse le tiers de gigaoctet de LFS pour du contenu qui tient
## en quelques centaines de kilooctets.
##
## ## Ce que fait ce script
##
## Il ouvre chaque `.glb`, en extrait la seule piste d'animation, la renomme
## sous son nom d'état logique, et écrit une `AnimationLibrary` unique. Les
## `.glb` sources restent sur disque mais ne sont PAS versionnés (cf
## `.gitignore`) : ce sont des artefacts retéléchargeables.
##
## Seul le maillage garde son `.glb`, puisqu'il faut bien un squelette et une
## peau.

const SRC_TEMPLATE := "res://assets/characters/%s/src/"
const OUT_TEMPLATE := "res://assets/characters/%s/%s_anims.res"

## Table de correspondance : nom de fichier Meshy → état logique du jeu.
##
## Elle est explicite et pas déduite : les noms Meshy sont descriptifs
## (« SideLying_Reach_Help ») et n'ont aucune raison de coïncider avec le
## vocabulaire du jeu (« downed_idle »). Écrire la traduction rend aussi
## visible ce qui n'a PAS d'équivalent — c'est là qu'on voit ce qui manque.
const MAPPING := {
	"Idle_02": "idle",
	"Walking": "walk",
	"Running": "run",
	"BackLeft_run": "run_back",
	"ForwardLeft_Run_Fight": "run_forward_left",
	"ForwardRight_Run_Fight": "run_forward_right",
	"Walk_Forward_While_Shooting": "shoot_walk_forward",
	"Run_and_Shoot": "shoot_run",
	"Shot_and_Blown_Back": "death",
	"SideLying_Reach_Help": "downed_idle",
	"Stand_Up6": "get_up",
	"Roll_Dodge": "dash",
	"Roll_Dodge_1": "dash_right",
	"Roll_Dodge_3": "dash_left",
	"climbing_up_wall": "climb",
	"CrouchLookAroundBow": "crouch_idle",
	# Deux clips de trois secondes livrés sans nom exploitable — leur piste
	# s'appelle « rigify_clip » chez Meshy. Ils sont embarqués sous un nom
	# neutre pour ne pas les perdre ; à renommer quand on saura ce qu'ils sont.
	"019fe788-56ed-7f9c-9484-99f68dac74a1": "custom_1",
	"019fe789-a8fd-7b03-a4cc-66f3b76add33": "custom_2",
}


func _init() -> void:
	var character: String = "conqueror"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--character="):
			character = arg.trim_prefix("--character=")

	var src_dir: String = SRC_TEMPLATE % character
	var dir: DirAccess = DirAccess.open(src_dir)
	if dir == null:
		push_error("[perso] dossier source introuvable : %s" % src_dir)
		quit(1)
		return

	var library := AnimationLibrary.new()
	var baked: int = 0
	var skipped: Array[String] = []

	for file_name in dir.get_files():
		if not file_name.ends_with(".glb"):
			continue
		var stem: String = file_name.trim_suffix(".glb")
		if not MAPPING.has(stem):
			skipped.append(stem)
			continue
		var animation: Animation = _extract(src_dir + file_name)
		if animation == null:
			push_warning("[perso] aucune piste dans %s" % file_name)
			continue
		var state: String = MAPPING[stem]
		library.add_animation(StringName(state), animation)
		baked += 1
		print("[perso] %-34s -> %-20s %.2f s" % [stem, state, animation.length])

	if not skipped.is_empty():
		print("[perso] ignorés (absents de la table) : %s" % ", ".join(skipped))

	var out_path: String = OUT_TEMPLATE % [character, character]
	var status: int = ResourceSaver.save(library, out_path)
	if status != OK:
		push_error("[perso] échec d'écriture : %s" % out_path)
		quit(1)
		return
	print("[perso] %d animations dans %s" % [baked, out_path])
	quit(0)


## Sort la piste d'animation d'un `.glb`, sans garder le reste.
##
## Meshy nomme ses pistes « Armature|<nom>|baselayer » et livre parfois une
## seconde piste technique (« rigify_clip ») ; on prend la PLUS LONGUE, qui est
## systématiquement la vraie.
func _extract(path: String) -> Animation:
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		return null
	var root: Node = packed.instantiate()
	var player: AnimationPlayer = _find_player(root)
	var best: Animation = null
	if player != null:
		for name in player.get_animation_list():
			var candidate: Animation = player.get_animation(name)
			if candidate == null:
				continue
			if best == null or candidate.length > best.length:
				best = candidate
	# Dupliquée AVANT de libérer la scène : sinon on garderait une référence
	# vers une ressource dont le propriétaire vient de disparaître.
	var out: Animation = best.duplicate() as Animation if best != null else null
	root.queue_free()
	return out


func _find_player(node: Node) -> AnimationPlayer:
	var player: AnimationPlayer = node as AnimationPlayer
	if player != null:
		return player
	for child in node.get_children():
		var found: AnimationPlayer = _find_player(child)
		if found != null:
			return found
	return null

class_name LobbyBackdrop
extends ColorRect

## Le fond de l'écran d'accueil : une caverne qu'on devine, pas une image.
##
## ## Pourquoi un shader et pas un rendu 3D
##
## Un décor 3D en fond de menu coûte une scène à charger, à éclairer et à
## maintenir — pour une image qu'on regarde trente secondes. Ici, deux nappes
## de bruit et une poignée d'éclats donnent la même impression de profondeur
## pour un plein écran de fragment shader.
##
## ## Ce qu'il raconte
##
## Le regard descend vers un fond sombre où pulsent des veines de cristal.
## C'est la promesse du jeu — on va sous terre, il y fait froid, quelque chose
## y brille — et c'est la seule chose qu'un écran d'accueil doive dire.
##
## La palette est celle de l'art bible (§3) : roche `#0a0e15`, cristal cyan
## `#66d9ff`. Un menu qui n'aurait pas les couleurs du jeu ferait promesse
## d'un autre jeu.

const SHADER_PATH := "res://shaders/lobby_backdrop.gdshader"


func _ready() -> void:
	# `set_anchors_preset` seul laisse les marges intactes : un nœud créé par
	# code naît avec une taille nulle et reste invisible. Il faut la variante
	# qui remet aussi les marges.
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0.039, 0.055, 0.082)

	var shader: Shader = load(SHADER_PATH) as Shader
	if shader == null:
		# Sans shader, le fond reste la couleur de roche : dégradé mais lisible.
		push_warning("LobbyBackdrop : %s introuvable — fond uni." % SHADER_PATH)
		return
	var mat := ShaderMaterial.new()
	mat.shader = shader
	material = mat

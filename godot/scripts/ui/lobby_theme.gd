class_name LobbyTheme
extends RefCounted

## L'habillage de l'écran d'accueil.
##
## Les boutons étaient ceux de Godot : gris, arrondis, avec la police système.
## Un joueur qui lance le jeu voit d'abord ça — et un menu par défaut annonce
## un jeu par défaut.
##
## Tout est construit en code plutôt que rangé dans un `.theme` : les couleurs
## viennent de `CrystalGrammar`, donc du même endroit que celles du niveau. Un
## fichier de thème séparé aurait dérivé au premier changement de palette.

const TITLE_FONT := "res://assets/fonts/october_crow.ttf"

const COLD := Color(0.400, 0.851, 1.000)      # cristal cyan, l'accent du jeu
const ROCK := Color(0.055, 0.078, 0.114)      # roche, le fond des panneaux
const PALE := Color(0.812, 0.894, 0.949)      # texte courant
const DIM := Color(0.478, 0.573, 0.667)       # texte secondaire


## Le titre : la police tracée à la main du jeu, en grand, en cyan.
static func style_title(label: Label, text: String) -> void:
	label.text = text
	var face: Font = load(TITLE_FONT) as Font
	if face != null:
		label.add_theme_font_override("font", face)
	label.add_theme_font_size_override("font_size", 96)
	label.add_theme_color_override("font_color", COLD)
	label.add_theme_color_override("font_outline_color", Color(0.012, 0.024, 0.039))
	label.add_theme_constant_override("outline_size", 10)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


static func style_subtitle(label: Label) -> void:
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", DIM)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER


## Les boutons. Bord cyan sur fond de roche, et le focus se voit de loin :
## en couch coop, on navigue à la manette depuis un canapé, pas à la souris à
## cinquante centimètres.
static func style_button(button: Button, primary: bool = false) -> void:
	button.add_theme_font_size_override("font_size", 20 if primary else 16)
	button.custom_minimum_size = Vector2(260 if primary else 190, 62 if primary else 46)

	button.add_theme_stylebox_override("normal", _box(
		ROCK, COLD.darkened(0.55), 2))
	button.add_theme_stylebox_override("hover", _box(
		ROCK.lightened(0.10), COLD.darkened(0.25), 2))
	# Le focus est volontairement franc — c'est le seul repère de navigation
	# à la manette.
	button.add_theme_stylebox_override("focus", _box(
		Color(COLD.r, COLD.g, COLD.b, 0.14), COLD, 3))
	button.add_theme_stylebox_override("pressed", _box(
		Color(COLD.r, COLD.g, COLD.b, 0.28), COLD, 3))
	button.add_theme_stylebox_override("disabled", _box(
		ROCK.darkened(0.3), DIM.darkened(0.6), 1))

	button.add_theme_color_override("font_color", PALE)
	button.add_theme_color_override("font_focus_color", Color.WHITE)
	button.add_theme_color_override("font_hover_color", Color.WHITE)
	button.add_theme_color_override("font_pressed_color", Color.WHITE)
	button.add_theme_color_override("font_disabled_color", DIM.darkened(0.4))


static func style_panel(panel: PanelContainer) -> void:
	panel.add_theme_stylebox_override("panel", _box(
		Color(ROCK.r, ROCK.g, ROCK.b, 0.94), COLD.darkened(0.6), 2, 16))


## Un emplacement de joueur. Vide, il n'est qu'un contour ; occupé, il prend
## la couleur du joueur — le même code couleur que le HUD en jeu.
static func style_slot(panel: PanelContainer, joined: bool, slot_color: Color) -> void:
	var accent: Color = slot_color if joined else DIM.darkened(0.5)
	var fill: Color = Color(slot_color.r, slot_color.g, slot_color.b, 0.16) if joined \
		else Color(ROCK.r, ROCK.g, ROCK.b, 0.55)
	panel.add_theme_stylebox_override("panel", _box(fill, accent, 3 if joined else 2, 10))


static func slot_color(player_id: int) -> Color:
	const SLOTS: Array[Color] = [
		Color(0.40, 0.85, 1.00), Color(1.00, 0.68, 0.35),
		Color(0.60, 1.00, 0.55), Color(0.85, 0.60, 1.00),
	]
	return SLOTS[player_id % SLOTS.size()]


static func _box(bg: Color, border: Color, width: int, radius: int = 8) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = bg
	box.border_color = border
	box.set_border_width_all(width)
	box.set_corner_radius_all(radius)
	box.set_content_margin_all(12)
	return box

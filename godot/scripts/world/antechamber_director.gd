class_name AntechamberDirector
extends Node

## Met en scène les 8 beats de « L'Antichambre de Givre »
## (`docs/design/level01_onboarding.md`).
##
## ## Trois règles, tenues par la structure et pas par la discipline
##
## **Zéro mur de texte.** Rien ici n'affiche de phrase. Ce que le joueur lit,
## ce sont des gravures de bouton (`FrostGlyph`) et des réactions du monde :
## une veine qui pulse dans le sens du chemin, un cristal qui s'illumine plus
## loin, une lumière qui s'éteint derrière soi.
##
## **La progression se valide par l'ACTION, jamais par un timer.** Chaque beat
## expose une condition (`_beat_is_done`) qui interroge l'état réel du monde.
## Un beat ne peut donc pas être « passé » en attendant. Les seules durées de
## ce fichier sont des fondus et des relances d'attention.
##
## **Tout est posé à l'exécution.** Aucune position de beat n'existe dans une
## scène : elles sont dans `_BEATS` ci-dessous, et les objets sont recalés sur
## le sol réellement généré. Déplacer un beat, c'est changer deux nombres — pas
## rouvrir l'éditeur, et pas se battre avec des transforms que les outils
## d'édition ne persistent pas.
##
## ## Ce qui n'est pas encore là
##
## L'audio (les notes de join qui composent un accord à quatre, le grondement
## du Golem) attend la tâche #31. Les emplacements d'appel sont marqués
## `TODO(audio)` — il y en a quatre, et ils sont tous dans `_enter_beat`.

signal beat_started(beat: int)
signal beat_completed(beat: int)
signal onboarding_finished()

enum Beat {
	AWAKENING,      ## B1 — les cristaux de join s'allument
	MOVE_AND_LOOK,  ## B2 — la veine, les sticks
	FIRST_SHOT,     ## B3 — le cristal fragile qui barre
	THE_COMBO,      ## B4 — le parchemin de feu, LE pic
	COOP_DRILL,     ## B5 — la gangue de glace, le revive
	THE_DARK,       ## B6 — tout s'éteint, le chapelet guide
	THE_CHEST,      ## B7 — le coffre, la porte, la vista
	DONE,
}

# ---------------------------------------------------------------------------
# La géographie des beats
# ---------------------------------------------------------------------------
#
# En (X, Z). L'altitude n'est jamais écrite : elle est prise sur le sol
# généré, comme pour la caverne. Les cotes suivent le tracé en Z de
# `tools/build_antechamber.gd` — si l'un bouge, l'autre doit suivre, et le
# test `test_antechamber` vérifie que chaque beat tombe bien dans le volume.

const _JOIN_CRYSTALS: Array[Vector2] = [
	Vector2(-5.0, 4.5), Vector2(-2.0, 6.0), Vector2(2.0, 6.0), Vector2(5.0, 4.5),
]
const _SPAWNS: Array[Vector2] = [
	Vector2(-3.0, -1.0), Vector2(-1.0, 0.5), Vector2(1.0, 0.5), Vector2(3.0, -1.0),
]
const _GLYPH_MOVE := Vector2(0.0, -5.0)
const _GLYPH_LOOK := Vector2(0.0, -15.0)
const _BARRIER := Vector2(9.0, -18.0)
const _PEDESTAL := Vector2(24.0, -21.0)
const _COMBO_TARGETS: Array[Vector2] = [Vector2(21.0, -15.0), Vector2(27.0, -15.0)]
const _TRAP := Vector2(24.0, 4.0)
const _ROSARY: Array[Vector2] = [
	Vector2(24.0, 9.0), Vector2(24.0, 15.0), Vector2(24.0, 21.0), Vector2(24.0, 26.0),
]
const _CHEST := Vector2(24.0, 31.0)
const _DOOR := Vector2(24.0, 37.5)

## Distance à parcourir et angle de caméra à balayer avant que B2 soit acquis.
const _MOVE_REQUIRED_M := 10.0
const _LOOK_REQUIRED_DEG := 90.0

## Au-delà, la veine pulse plus fort et un cristal « toussote ». Jamais de
## texte, jamais de voix off — juste le monde qui rappelle qu'il attend.
const _IDLE_NUDGE_SEC := 45.0

## B1 se clôt quand plus personne ne rejoint. Ce délai n'est pas une
## validation par timer : il n'y a rien à réussir, on attend juste le dernier
## arrivant.
const _JOIN_SETTLE_SEC := 3.0

const COLD := Color(0.40, 0.85, 1.00)
const WARM := Color(0.95, 0.71, 0.36)

@export_file("*.tres") var terrain_data_path: String = "res://data/levels/antechamber_terrain.tres"
## Si faux, le director ne fait rien — utile pour visiter le décor.
@export var run_beats: bool = true

var _world: Node3D
var _terrain: CavernTerrainData
var _terrain_noise: FastNoiseLite
var _beat: int = Beat.AWAKENING
var _beat_time: float = 0.0
var _idle_time: float = 0.0

var _join_crystals: Array[MeshInstance3D] = []
var _lit_slots: Dictionary = {}          # player_id -> true
var _since_last_join: float = 0.0
var _glyphs: Dictionary = {}             # StringName -> FrostGlyph
var _rosary: Array[OmniLight3D] = []
var _rosary_reached: int = 0
var _vein: Node3D
var _barrier: FragileCrystal
var _barrier_broken: bool = false
var _combo_targets: Array[FragileCrystal] = []
var _combo_shots: Dictionary = {}        # player_id -> true
var _trapped_player: PlayerController
var _revive_done: bool = false
var _chest: Node3D
var _door: StaticBody3D
var _door_open: bool = false

## Suivi par joueur pour B2 : distance parcourue et rotation caméra cumulée.
var _travelled: Dictionary = {}          # player_id -> float
var _turned: Dictionary = {}             # player_id -> float
var _last_pos: Dictionary = {}           # player_id -> Vector3
var _last_yaw: Dictionary = {}           # player_id -> float


func _ready() -> void:
	_world = get_parent() as Node3D
	if _world == null:
		push_error("AntechamberDirector : doit être enfant du nœud World.")
		return
	_terrain = load(terrain_data_path) as CavernTerrainData
	if _terrain == null:
		push_error("AntechamberDirector : terrain introuvable (%s)." % terrain_data_path)
		return
	_terrain_noise = CavernTerrainBuilder.make_noise(_terrain.floor_field)

	# Deux frames : le terrain se construit, puis on peut lui demander une
	# altitude. Poser les objets avant reviendrait à les semer dans le vide.
	await get_tree().process_frame
	await get_tree().process_frame

	_build_spawn_points()
	_build_props()

	if not run_beats:
		return

	# Le skip (B8) : si toutes les manettes présentes connaissent déjà les
	# lieux, l'antichambre apparaît éveillée et le coffre attend au pied de la
	# porte. Le skip est un chemin, pas un menu.
	if OnboardingSkip.everyone_has_seen(PlayerManager.get_active_player_ids()):
		_open_everything()
		return

	_enter_beat(Beat.AWAKENING)


func _process(delta: float) -> void:
	if not run_beats or _beat == Beat.DONE:
		return
	_beat_time += delta
	_track_players(delta)
	if _beat_is_done():
		_complete_beat()
	elif _idle_time > _IDLE_NUDGE_SEC:
		_nudge()
		_idle_time = 0.0


# ---------------------------------------------------------------------------
# Construction
# ---------------------------------------------------------------------------

## Le sol réellement généré, à l'aplomb de (x, z). Rien n'est posé à une
## altitude écrite à la main : le terrain est la seule autorité.
func _ground(at: Vector2) -> Vector3:
	if _terrain == null:
		return Vector3(at.x, 0.0, at.y)
	return Vector3(at.x, CavernTerrainBuilder.sample_point(_terrain.floor_field, at, _terrain_noise), at.y)


func _build_spawn_points() -> void:
	# RunShell cherche `PlayerSpawnPoints/SpawnN`. On les crée ici plutôt que
	# dans la scène : les positions vivent avec les beats.
	var root := Node3D.new()
	root.name = "PlayerSpawnPoints"
	_world.add_child(root)
	for i in _SPAWNS.size():
		var m := Marker3D.new()
		m.name = "Spawn%d" % i
		root.add_child(m)
		# Lâchés d'un mètre : posés pile au sol, les joueurs s'y enfoncent.
		m.global_position = _ground(_SPAWNS[i]) + Vector3(0.0, 1.0, 0.0)


func _build_props() -> void:
	for i in _JOIN_CRYSTALS.size():
		_join_crystals.append(_make_crystal(_JOIN_CRYSTALS[i], 2.4, false))

	_glyphs[&"move"] = _make_glyph(&"move", _GLYPH_MOVE)
	_glyphs[&"look"] = _make_glyph(&"look", _GLYPH_LOOK)
	_glyphs[&"shoot"] = _make_glyph(&"shoot", _BARRIER + Vector2(-2.5, 0.0))
	_glyphs[&"interact_pedestal"] = _make_glyph(&"interact", _PEDESTAL + Vector2(0.0, 2.0))
	_glyphs[&"interact_revive"] = _make_glyph(&"interact", _TRAP + Vector2(2.0, 0.0))
	_glyphs[&"interact_chest"] = _make_glyph(&"interact", _CHEST + Vector2(0.0, -2.0))

	_vein = _make_vein()
	_barrier = _make_fragile(_BARRIER)
	_barrier.shattered.connect(func(_by: Node) -> void: _barrier_broken = true)
	for p in _COMBO_TARGETS:
		var c: FragileCrystal = _make_fragile(p)
		_combo_targets.append(c)

	for p in _ROSARY:
		_rosary.append(_make_rosary_light(p))

	_door = _make_door()
	_build_chest()


func _make_crystal(at: Vector2, height: float, lit: bool) -> MeshInstance3D:
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.0
	mesh.bottom_radius = 0.42
	mesh.height = height
	mesh.radial_segments = 6
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.10, 0.16, 0.24)
	mat.emission_enabled = true
	mat.emission = COLD
	mat.emission_energy_multiplier = 2.2 if lit else 0.0
	mi.material_override = mat
	_world.add_child(mi)
	mi.global_position = _ground(at) + Vector3(0.0, height * 0.5, 0.0)
	return mi


func _make_glyph(verb: StringName, at: Vector2) -> FrostGlyph:
	var g := FrostGlyph.new()
	g.verb = verb
	_world.add_child(g)
	g.global_position = _ground(at)
	return g


## La veine de givre : une bande émissive dans le sol qui pulse DANS LE SENS
## du chemin. Le pouls porte la direction — c'est pour ça qu'il n'y a pas de
## flèche.
func _make_vein() -> Node3D:
	var root := Node3D.new()
	root.name = "VeineDeGivre"
	_world.add_child(root)
	var path: Array[Vector2] = [
		Vector2(0.0, -2.0), Vector2(0.0, -18.0), Vector2(20.0, -18.0),
		Vector2(24.0, -14.0), Vector2(24.0, 27.0), _CHEST,
	]
	for i in range(path.size() - 1):
		_add_vein_segment(root, path[i], path[i + 1])
	return root


func _add_vein_segment(root: Node3D, from_point: Vector2, to_point: Vector2) -> void:
	var span: Vector2 = to_point - from_point
	var length: float = span.length()
	var steps: int = maxi(1, int(length / 1.5))
	for s in steps:
		var t: float = (float(s) + 0.5) / float(steps)
		var at: Vector2 = from_point + span * t
		var quad := MeshInstance3D.new()
		var m := QuadMesh.new()
		m.size = Vector2(0.55, 1.35)
		quad.mesh = m
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.05, 0.10, 0.16)
		mat.emission_enabled = true
		mat.emission = COLD
		mat.emission_energy_multiplier = 1.4
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		quad.material_override = mat
		root.add_child(quad)
		quad.global_position = _ground(at) + Vector3(0.0, 0.05, 0.0)
		quad.rotation_degrees = Vector3(-90.0, rad_to_deg(atan2(span.x, span.y)), 0.0)


func _make_fragile(at: Vector2) -> FragileCrystal:
	var c := FragileCrystal.new()
	_world.add_child(c)
	c.global_position = _ground(at)
	return c


func _make_rosary_light(at: Vector2) -> OmniLight3D:
	var l := OmniLight3D.new()
	l.light_color = COLD
	l.light_energy = 0.0
	l.omni_range = 12.0
	_world.add_child(l)
	l.global_position = _ground(at) + Vector3(0.0, 2.2, 0.0)
	_make_crystal(at + Vector2(2.6, 0.0), 1.8, false)
	return l


## La porte de glace. Elle est un mur tant qu'elle est fermée : sans
## collision, le beat final n'aurait rien à ouvrir.
func _make_door() -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = "PorteDeGlace"
	var mesh := BoxMesh.new()
	mesh.size = Vector3(7.0, 6.0, 0.6)
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.62, 0.76, 0.86, 0.9)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.roughness = 0.25
	mi.material_override = mat
	body.add_child(mi)
	var shape := BoxShape3D.new()
	shape.size = mesh.size
	var col := CollisionShape3D.new()
	col.shape = shape
	body.add_child(col)
	_world.add_child(body)
	body.global_position = _ground(_DOOR) + Vector3(0.0, 3.0, 0.0)
	return body


func _build_chest() -> void:
	# Le coffre de départ existe déjà : c'est lui qui tire classe et arme.
	# On ne le réimplémente pas, on le pose — et RunShell le trouvera par son
	# marqueur, comme dans la caverne.
	var marker := Marker3D.new()
	marker.name = "StartChestSpawn"
	_world.add_child(marker)
	marker.global_position = _ground(_CHEST)
	_chest = marker


# ---------------------------------------------------------------------------
# La machine à beats
# ---------------------------------------------------------------------------

func _enter_beat(beat: int) -> void:
	_beat = beat
	_beat_time = 0.0
	_idle_time = 0.0
	beat_started.emit(beat)

	match beat:
		Beat.AWAKENING:
			# TODO(audio, #31) : une note tenue par slot — à quatre, le join
			# compose un accord.
			pass
		Beat.MOVE_AND_LOOK:
			_dim_join_crystals()
			_pulse_vein(1.0)
			_glyph(&"move").light()
			_glyph(&"look").light()
		Beat.FIRST_SHOT:
			_glyph(&"move").dim()
			_glyph(&"look").dim()
			_glyph(&"shoot").light()
		Beat.THE_COMBO:
			_glyph(&"shoot").dim()
			_glyph(&"interact_pedestal").light()
			_light_pedestal()
		Beat.COOP_DRILL:
			_glyph(&"interact_pedestal").dim()
			_spring_the_trap()
			_glyph(&"interact_revive").light()
		Beat.THE_DARK:
			# TODO(audio, #31) : premier grondement lointain du Golem.
			_glyph(&"interact_revive").dim()
			_fall_dark()
		Beat.THE_CHEST:
			_glyph(&"interact_chest").light()
			_open_the_door()
		Beat.DONE:
			OnboardingSkip.mark_all_seen(PlayerManager.get_active_player_ids())
			onboarding_finished.emit()


## La condition de sortie de chaque beat. Toutes interrogent l'état réel du
## monde ; aucune ne consulte l'horloge pour décider qu'un beat est réussi.
func _beat_is_done() -> bool:
	match _beat:
		Beat.AWAKENING:
			if _lit_slots.is_empty():
				return false
			return _lit_slots.size() >= 4 or _since_last_join >= _JOIN_SETTLE_SEC
		Beat.MOVE_AND_LOOK:
			for pid in PlayerManager.get_active_player_ids():
				if float(_travelled.get(pid, 0.0)) < _MOVE_REQUIRED_M:
					return false
				if float(_turned.get(pid, 0.0)) < _LOOK_REQUIRED_DEG:
					return false
			return true
		Beat.FIRST_SHOT:
			return _barrier_broken
		Beat.THE_COMBO:
			# Chacun doit avoir tiré une fois avec l'arme transformée :
			# personne ne repart sans son moment.
			for pid in PlayerManager.get_active_player_ids():
				if not _combo_shots.has(pid):
					return false
			return not PlayerManager.get_active_player_ids().is_empty()
		Beat.COOP_DRILL:
			return _revive_done
		Beat.THE_DARK:
			return _rosary_reached >= _rosary.size()
		Beat.THE_CHEST:
			return _door_open and _everyone_past_the_door()
	return false


func _complete_beat() -> void:
	beat_completed.emit(_beat)
	_enter_beat(mini(_beat + 1, Beat.DONE))


# ---------------------------------------------------------------------------
# Les gestes de chaque beat
# ---------------------------------------------------------------------------

func _glyph(key: StringName) -> FrostGlyph:
	return _glyphs.get(key) as FrostGlyph


## B1 — un cristal par joueur inscrit. Le cristal EST le slot de lobby :
## allumé = inscrit. On voit qui est là en regardant le mur, sans écran.
func light_slot(player_id: int) -> void:
	if player_id < 0 or player_id >= _join_crystals.size():
		return
	if _lit_slots.has(player_id):
		return
	_lit_slots[player_id] = true
	_since_last_join = 0.0
	var mi: MeshInstance3D = _join_crystals[player_id]
	var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission = _slot_color(player_id)
	var tw: Tween = create_tween()
	tw.tween_property(mat, "emission_energy_multiplier", 2.6, 1.5)


func _slot_color(player_id: int) -> Color:
	# Les couleurs de slot du split-screen, pour que le mur dise la même chose
	# que le HUD.
	const SLOTS: Array[Color] = [
		Color(0.40, 0.85, 1.00), Color(1.00, 0.68, 0.35),
		Color(0.60, 1.00, 0.55), Color(0.85, 0.60, 1.00),
	]
	return SLOTS[player_id % SLOTS.size()]


func _dim_join_crystals() -> void:
	for mi in _join_crystals:
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat == null:
			continue
		var tw: Tween = create_tween()
		tw.tween_property(mat, "emission_energy_multiplier", 0.35, 2.0)


func _pulse_vein(energy: float) -> void:
	if _vein == null:
		return
	for child in _vein.get_children():
		var mi: MeshInstance3D = child as MeshInstance3D
		if mi == null:
			continue
		var mat: StandardMaterial3D = mi.material_override as StandardMaterial3D
		if mat != null:
			mat.emission_energy_multiplier = 1.4 * energy


## B4 — le parchemin de feu. Première et unique lumière chaude de
## l'antichambre : dans un couloir intégralement bleu, on ne peut pas ne pas
## le voir.
func _light_pedestal() -> void:
	var l := OmniLight3D.new()
	l.light_color = WARM
	l.light_energy = 3.0
	l.omni_range = 9.0
	_world.add_child(l)
	l.global_position = _ground(_PEDESTAL) + Vector3(0.0, 1.4, 0.0)
	_make_crystal(_PEDESTAL, 1.2, true)


## Enregistre qu'un joueur a tiré avec l'arme transformée. Appelé par le
## parchemin quand le tir part ; exposé pour que le test puisse le simuler.
func register_combo_shot(player_id: int) -> void:
	_combo_shots[player_id] = true


## B5 — le plafond cède sur le joueur de tête. **C'est la caverne qui l'a eu,
## pas une faute de jeu** : d'où l'effondrement scripté plutôt que des dégâts.
func _spring_the_trap() -> void:
	var players: Array = _players()
	if players.is_empty():
		return
	var lead: PlayerController = players[0] as PlayerController
	for p in players:
		var pc: PlayerController = p as PlayerController
		if pc != null and pc.global_position.z > lead.global_position.z:
			lead = pc
	_trapped_player = lead
	if lead != null and not lead.is_downed():
		if not lead.revived.is_connected(_on_revived):
			lead.revived.connect(_on_revived)
		# On passe par les PV plutôt que de forcer l'état : c'est le chemin
		# réel du jeu, donc le revive qui suivra sera le vrai revive, pas une
		# imitation qui marcherait ici et nulle part ailleurs.
		var hc: HealthComponent = lead.get_health()
		if hc != null:
			hc.take_damage(hc.max_health * 10, self)
	# Filet du document : l'antichambre ne peut pas game-over. Si tout le monde
	# finit à terre (tir ami trop enthousiaste), la glace fond d'elle-même.
	get_tree().create_timer(6.0).timeout.connect(_thaw_if_everyone_is_down)


func _on_revived() -> void:
	_revive_done = true


func _thaw_if_everyone_is_down() -> void:
	if _revive_done:
		return
	var players: Array = _players()
	if players.is_empty():
		return
	for p in players:
		var pc: PlayerController = p as PlayerController
		if pc != null and not pc.is_downed():
			return  # Quelqu'un tient debout : on laisse le drill se jouer.
	for p in players:
		var pc: PlayerController = p as PlayerController
		if pc != null and pc.is_downed():
			pc.revive_by(pc)
	_revive_done = true


## B6 — le noir avale le chemin parcouru et pousse dans le dos. Puis les
## cristaux se rallument devant, un par un : *quand tout s'éteint, les
## cristaux sont la boussole*. C'est le régime lumineux de la caverne, appris
## avant d'y entrer.
func _fall_dark() -> void:
	_dim_join_crystals()
	_pulse_vein(0.35)
	_light_next_rosary()


func _light_next_rosary() -> void:
	if _rosary_reached >= _rosary.size():
		return
	var l: OmniLight3D = _rosary[_rosary_reached]
	var tw: Tween = create_tween()
	tw.tween_property(l, "light_energy", 2.4, 0.8)


func _open_the_door() -> void:
	if _door == null or _door_open:
		return
	_door_open = true
	# La porte se fend : on la fait coulisser hors du passage, et sa collision
	# part AVANT la fin de l'animation — un joueur qui s'y colle ne doit pas
	# rester bloqué contre un mur devenu invisible.
	for child in _door.get_children():
		var col: CollisionShape3D = child as CollisionShape3D
		if col != null:
			col.set_deferred("disabled", true)
	var tw: Tween = create_tween()
	tw.tween_property(_door, "position", _door.position + Vector3(0.0, -5.6, 0.0), 2.4)


func _everyone_past_the_door() -> bool:
	var players: Array = _players()
	if players.is_empty():
		return false
	for p in players:
		var pc: PlayerController = p as PlayerController
		if pc != null and pc.global_position.z < _DOOR.y:
			return false
	return true


## Le skip (B8) : l'antichambre déjà éveillée. Lumières hautes, porte fendue,
## coffre au pied de la porte. Marcher tout droit suffit.
func _open_everything() -> void:
	for i in _join_crystals.size():
		light_slot(i)
	_pulse_vein(1.0)
	for l in _rosary:
		l.light_energy = 2.4
	if _barrier != null:
		_barrier.queue_free()
	_rosary_reached = _rosary.size()
	_open_the_door()
	_beat = Beat.DONE
	onboarding_finished.emit()


## Relance d'attention après une longue immobilité : la veine pulse plus fort.
## Jamais de texte, jamais de voix off.
func _nudge() -> void:
	_pulse_vein(1.6)
	var tw: Tween = create_tween()
	tw.tween_interval(1.2)
	tw.tween_callback(func() -> void: _pulse_vein(1.0))


# ---------------------------------------------------------------------------
# Observation des joueurs
# ---------------------------------------------------------------------------

func _players() -> Array:
	return get_tree().get_nodes_in_group(&"players")


func _track_players(delta: float) -> void:
	_since_last_join += delta

	# B1 : on écoute les manettes qui rejoignent.
	if _beat == Beat.AWAKENING:
		for pid in PlayerManager.get_active_player_ids():
			light_slot(pid)

	var anyone_moved: bool = false
	for p in _players():
		var pc: PlayerController = p as PlayerController
		if pc == null:
			continue
		var pid: int = pc.player_id
		var pos: Vector3 = pc.global_position
		if _last_pos.has(pid):
			var step: float = (pos - (_last_pos[pid] as Vector3)).length()
			if step > 0.01:
				anyone_moved = true
			_travelled[pid] = float(_travelled.get(pid, 0.0)) + step
		_last_pos[pid] = pos

		var yaw: float = pc.global_rotation.y
		if _last_yaw.has(pid):
			var d: float = absf(rad_to_deg(angle_difference(float(_last_yaw[pid]), yaw)))
			if d > 0.05:
				anyone_moved = true
			_turned[pid] = float(_turned.get(pid, 0.0)) + d
		_last_yaw[pid] = yaw

		# B6 : chaque cristal du chapelet ne s'allume qu'une fois le précédent
		# atteint. On avance dans le noir, pas dans un couloir déjà éclairé.
		if _beat == Beat.THE_DARK and _rosary_reached < _rosary.size():
			var target: Vector2 = _ROSARY[_rosary_reached]
			if Vector2(pos.x, pos.z).distance_to(target) < 3.5:
				_rosary_reached += 1
				_light_next_rosary()

	_idle_time = 0.0 if anyone_moved else _idle_time + delta


# ---------------------------------------------------------------------------
# Lecture (tests, debug)
# ---------------------------------------------------------------------------

func get_beat() -> int:
	return _beat


func get_beat_positions() -> Array[Vector2]:
	var out: Array[Vector2] = []
	out.append_array(_JOIN_CRYSTALS)
	out.append_array(_SPAWNS)
	out.append_array(_COMBO_TARGETS)
	out.append_array(_ROSARY)
	out.append_array([_GLYPH_MOVE, _GLYPH_LOOK, _BARRIER, _PEDESTAL, _TRAP, _CHEST, _DOOR])
	return out

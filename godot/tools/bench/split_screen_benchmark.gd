class_name SplitScreenBenchmark
extends Node

## Mesure du budget technique en split-screen (E0 du plan niveau 1).
##
## POURQUOI CET OUTIL EXISTE
## L'art bible annonçait des cibles de budget (≤1200 draw calls/viewport,
## ≤1,5 M triangles) qui n'avaient jamais été mesurées. Impossible de juger le
## coût du texturing (E3) ou de tenir 60 fps au packaging (E7) sans baseline
## reproductible. Cet outil produit cette baseline et sera relancé À
## L'IDENTIQUE après chaque passe lourde, pour comparer des chiffres
## comparables.
##
## IL NE PASSE PAS PAR PlayerManager / SplitScreenManager
## Le join exige des manettes physiquement branchées (`_is_device_connected`),
## ce qui rend une mesure automatisée à 4 joueurs impossible. On reproduit donc
## la seule chose qui compte pour la perf — N SubViewports partageant le même
## `world_3d`, chacun avec sa caméra — sans le gameplay.
##
## TROIS MODES
##   baseline  : coût réel de la scène de niveau, à 1 / 2 / 4 viewports.
##   geometry  : rampe de charge géométrique jusqu'à décrochage sous 60 fps.
##               Répond à « combien de draw calls et de triangles tient-on ? »
##   lights    : rampe de lumières à ombres portées jusqu'à décrochage.
##               Répond à « combien de sources ombrées peut-on se payer ? »
## Les deux rampes tournent à 4 viewports : c'est le cas nominal du jeu, et le
## seul qui décide du budget.
##
## USAGE (hors éditeur, pour ne pas mesurer le coût de l'éditeur)
##   godot --path godot res://tools/bench/bench_split_screen.tscn -- --mode=baseline
##   godot --path godot res://tools/bench/bench_split_screen.tscn -- --mode=geometry
##   godot --path godot res://tools/bench/bench_split_screen.tscn -- --mode=lights
##   ... --rendering-method mobile   (pour tester le fallback renderer)
##
## Sortie : tableau Markdown sur stdout entre BENCH_REPORT_BEGIN / _END.

enum Mode { BASELINE, GEOMETRY, LIGHTS }

## Objectif de tenue de frame. C'est la barre du plan : 60 fps en 4-split.
const TARGET_FPS: float = 60.0

## Marge sous la cible avant de déclarer un décrochage. Sans elle, le bruit de
## mesure autour de 60 (59,7 par exemple) couperait la rampe dès le premier
## palier et on n'apprendrait rien.
const FPS_TOLERANCE: float = 3.0

## Budget de frame correspondant à la cible. C'est CE chiffre qui sert de
## verdict, pas les fps : sur macOS la présentation est cadencée sur l'écran
## même vsync désactivé, donc les fps saturent à 60 et cachent la marge.
const FRAME_BUDGET_MS: float = 1000.0 / TARGET_FPS

## Nombre de viewports du cas nominal, celui qui décide du budget.
const NOMINAL_VIEWPORTS: int = 4

const SPAWN_POINTS_NODE_NAME := "PlayerSpawnPoints"
const CAMERA_EYE_HEIGHT: float = 1.6

@export_file("*.tscn") var level_scene_path: String = "res://scenes/levels/level_01_cavern/level_01_cavern.tscn"

## Configurations mesurées en mode baseline.
@export var viewport_counts: Array[int] = [1, 2, 4]

## Paliers de la rampe géométrique (nombre de mailles instanciées).
@export var geometry_steps: Array[int] = [200, 500, 1000, 2000, 4000, 8000]

## Paliers de la rampe de lumières ombrées.
@export var light_steps: Array[int] = [1, 2, 4, 8, 16, 32]

@export var window_size: Vector2i = Vector2i(1920, 1080)

## Échauffement : compilation des shaders et montée en charge du GPU. Mesurer
## pendant cette phase tirerait tous les chiffres vers le bas.
@export var warmup_seconds: float = 1.5

## Échauffement supplémentaire au tout premier palier, où les shaders du
## pipeline sont compilés pour la première fois.
## 10 s : le niveau se construit en asynchrone (dungeon_builder.build_async,
## spawn des ennemis, navmesh). Mesurer pendant cette construction fait
## ressortir le premier palier artificiellement mauvais et fausse la lecture.
@export var first_warmup_seconds: float = 10.0

@export var sample_seconds: float = 3.0

var _mode: Mode = Mode.BASELINE
var _level_root: Node3D
var _grid: GridContainer
var _load_root: Node3D
var _results: Array[Dictionary] = []
var _level_stats: Dictionary = {}
var _first_measure_done: bool = false

## RID des SubViewports actifs, pour lire leur temps de rendu mesuré.
var _viewport_rids: Array[RID] = []


func _ready() -> void:
	_mode = _parse_mode()

	# On mesure le coût de rendu, pas la capacité de l'écran à l'afficher :
	# vsync et cap de fps masqueraient toute la marge disponible.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = 0
	DisplayServer.window_set_size(window_size)

	var ui_root: Control = Control.new()
	ui_root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(ui_root)

	_grid = GridContainer.new()
	_grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_grid.add_theme_constant_override(&"h_separation", 0)
	_grid.add_theme_constant_override(&"v_separation", 0)
	ui_root.add_child(_grid)

	if not _load_level():
		get_tree().quit(1)
		return

	_level_stats = _collect_level_stats()

	_load_root = Node3D.new()
	_level_root.add_child(_load_root)

	match _mode:
		Mode.BASELINE:
			await _run_baseline()
		Mode.GEOMETRY:
			await _run_geometry_ramp()
		Mode.LIGHTS:
			await _run_lights_ramp()

	_print_report()
	get_tree().quit(0)


func _parse_mode() -> Mode:
	for arg in OS.get_cmdline_user_args():
		if not arg.begins_with("--mode="):
			continue
		match arg.trim_prefix("--mode="):
			"geometry":
				return Mode.GEOMETRY
			"lights":
				return Mode.LIGHTS
			_:
				return Mode.BASELINE
	return Mode.BASELINE


# ---------------------------------------------------------------------------
# Modes
# ---------------------------------------------------------------------------

func _run_baseline() -> void:
	for count in viewport_counts:
		_build_viewports(count)
		var measurement: Dictionary = await _measure()
		measurement["label"] = "%d viewport(s)" % count
		measurement["viewports"] = count
		_results.append(measurement)
		_clear_viewports()


## Rampe géométrique : on ajoute des mailles jusqu'à passer sous 60 fps. La
## dernière configuration au-dessus de la cible EST le budget de la machine.
func _run_geometry_ramp() -> void:
	_build_viewports(NOMINAL_VIEWPORTS)
	var placed: int = 0
	for target_count in geometry_steps:
		_add_load_meshes(target_count - placed)
		placed = target_count
		var measurement: Dictionary = await _measure()
		measurement["label"] = "%d mailles" % target_count
		measurement["viewports"] = NOMINAL_VIEWPORTS
		_results.append(measurement)
		if measurement.fps_avg < TARGET_FPS - FPS_TOLERANCE:
			# Inutile de continuer : on a franchi la limite, on sait où elle est.
			break
	_clear_load()
	_clear_viewports()


## Rampe de lumières : le point que l'art bible désignait comme
## « perf-critique » sans l'avoir jamais chiffré.
func _run_lights_ramp() -> void:
	_build_viewports(NOMINAL_VIEWPORTS)
	# Un fond géométrique modeste : sans surface à recevoir les ombres, une
	# lumière ombrée ne coûte presque rien et la mesure serait mensongère.
	_add_load_meshes(300)
	var placed: int = 0
	for target_count in light_steps:
		_add_load_lights(target_count - placed)
		placed = target_count
		var measurement: Dictionary = await _measure()
		measurement["label"] = "%d lumières ombrées" % target_count
		measurement["viewports"] = NOMINAL_VIEWPORTS
		_results.append(measurement)
		if measurement.fps_avg < TARGET_FPS - FPS_TOLERANCE:
			break
	_clear_load()
	_clear_viewports()


# ---------------------------------------------------------------------------
# Charge synthétique
# ---------------------------------------------------------------------------

## Mailles réparties en volume autour du barycentre du niveau, pour qu'elles
## tombent dans le champ des 4 caméras. Chacune est un MeshInstance3D distinct
## (donc un draw call potentiel) : c'est justement ce qu'on veut mesurer, le
## coût du non-instancié — celui que MultiMesh viendra corriger si besoin.
func _add_load_meshes(count: int) -> void:
	if count <= 0:
		return
	var mesh: SphereMesh = SphereMesh.new()
	mesh.radial_segments = 24
	mesh.rings = 12
	mesh.radius = 0.4
	mesh.height = 0.8

	var center: Vector3 = _level_stats.get("center", Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	# Graine fixe : deux runs doivent produire exactement la même charge,
	# sinon la comparaison avant/après ne vaut rien.
	rng.seed = 0x0CAC7 + _load_root.get_child_count()

	for i in count:
		var instance: MeshInstance3D = MeshInstance3D.new()
		instance.mesh = mesh
		# Volume resserré autour du barycentre : les mailles doivent tomber dans
		# le champ des caméras ET sous la portée des lumières, sinon on mesure du
		# culling au lieu de mesurer une charge.
		instance.position = center + Vector3(
			rng.randf_range(-12.0, 12.0),
			rng.randf_range(0.5, 6.0),
			rng.randf_range(-12.0, 12.0)
		)
		_load_root.add_child(instance)


func _add_load_lights(count: int) -> void:
	if count <= 0:
		return
	var center: Vector3 = _level_stats.get("center", Vector3.ZERO)
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x11317 + _load_root.get_child_count()

	for i in count:
		var light: OmniLight3D = OmniLight3D.new()
		light.shadow_enabled = true
		light.omni_range = 18.0
		light.light_energy = 1.2
		light.position = center + Vector3(
			rng.randf_range(-12.0, 12.0),
			rng.randf_range(2.0, 6.0),
			rng.randf_range(-12.0, 12.0)
		)
		_load_root.add_child(light)


func _clear_load() -> void:
	for child in _load_root.get_children():
		_load_root.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# Niveau
# ---------------------------------------------------------------------------

func _load_level() -> bool:
	var packed: PackedScene = load(level_scene_path) as PackedScene
	if packed == null:
		push_error("SplitScreenBenchmark: scène introuvable : %s" % level_scene_path)
		return false
	var instance: Node = packed.instantiate()
	_level_root = instance as Node3D
	if _level_root == null:
		push_error("SplitScreenBenchmark: la racine de %s n'est pas un Node3D." % level_scene_path)
		instance.queue_free()
		return false
	add_child(_level_root)
	return true


## Statistiques statiques : ce qui est là AVANT tout rendu. Le total de
## triangles borne ce que le culling peut au mieux économiser.
func _collect_level_stats() -> Dictionary:
	var mesh_count: int = 0
	var triangle_total: int = 0
	var light_count: int = 0
	var center: Vector3 = Vector3.ZERO
	var positioned: int = 0

	for node in _all_descendants(_level_root):
		if node is Light3D:
			light_count += 1
		var mesh_instance: MeshInstance3D = node as MeshInstance3D
		if mesh_instance == null or mesh_instance.mesh == null:
			continue
		mesh_count += 1
		center += mesh_instance.global_transform.origin
		positioned += 1
		triangle_total += _count_triangles(mesh_instance.mesh)

	if positioned > 0:
		center /= float(positioned)

	return {
		"mesh_instances": mesh_count,
		"triangles_total": triangle_total,
		"lights": light_count,
		"center": center,
	}


func _count_triangles(mesh: Mesh) -> int:
	var triangles: int = 0
	for surface in mesh.get_surface_count():
		var arrays: Array = mesh.surface_get_arrays(surface)
		if arrays.is_empty():
			continue
		# Une surface NON INDEXÉE renvoie `null` à l'emplacement des indices —
		# et c'est le cas de toute la caverne, dont les chunks sont générés en
		# triangles bruts. L'affecter à un `PackedInt32Array` typé lève une
		# erreur par maille : le compte tombait à zéro et le rapport annonçait
		# « 0 triangles » sur une scène qui en a un demi-million.
		var index_data: Variant = arrays[Mesh.ARRAY_INDEX]
		if index_data is PackedInt32Array and (index_data as PackedInt32Array).size() > 0:
			triangles += (index_data as PackedInt32Array).size() / 3
			continue
		var vertex_data: Variant = arrays[Mesh.ARRAY_VERTEX]
		if vertex_data is PackedVector3Array:
			triangles += (vertex_data as PackedVector3Array).size() / 3
	return triangles


func _all_descendants(root: Node) -> Array[Node]:
	var out: Array[Node] = []
	var stack: Array[Node] = [root]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		out.append(current)
		for child in current.get_children():
			stack.append(child)
	return out


# ---------------------------------------------------------------------------
# Viewports
# ---------------------------------------------------------------------------

func _build_viewports(count: int) -> void:
	_grid.columns = 1 if count <= 2 else 2
	var slot_size: Vector2 = _slot_size_for(count)

	for i in count:
		var container: SubViewportContainer = SubViewportContainer.new()
		container.stretch = true
		container.custom_minimum_size = slot_size
		container.size = slot_size
		_grid.add_child(container)

		var viewport: SubViewport = SubViewport.new()
		viewport.handle_input_locally = false
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		# PIÈGE SPLIT-SCREEN : un SubViewport a `positional_shadow_atlas_size` à 0
		# par défaut. Sans atlas, les OmniLight3D/SpotLight3D ne projettent AUCUNE
		# ombre dans ce viewport, silencieusement -- alors qu'elles fonctionnent
		# dans le viewport racine. Les cristaux émissifs d'E3 sont concernés.
		viewport.positional_shadow_atlas_size = 2048
		container.add_child(viewport)
		# Partage du monde 3D : c'est ce qui fait qu'un même niveau est rendu
		# N fois, donc toute la charge du split-screen.
		viewport.world_3d = get_tree().root.world_3d

		var camera: Camera3D = Camera3D.new()
		camera.current = true
		viewport.add_child(camera)
		_place_camera(camera, i)

		# Instrumentation GPU par viewport. Indispensable ici : sur macOS/Metal la
		# présentation reste cadencée sur l'écran même vsync désactivé, donc les fps
		# saturent à 60 et masquent toute la marge. Le temps de rendu mesuré, lui,
		# reflète le coût réel et reste comparable d'un run à l'autre.
		RenderingServer.viewport_set_measure_render_time(viewport.get_viewport_rid(), true)
		_viewport_rids.append(viewport.get_viewport_rid())


func _slot_size_for(count: int) -> Vector2:
	var full: Vector2 = Vector2(window_size)
	match count:
		1:
			return full
		2:
			return Vector2(full.x, full.y * 0.5)
		_:
			return full * 0.5


## Caméras posées sur les vrais spawns joueurs, orientées vers le barycentre du
## niveau : déterministe (donc comparable d'un run à l'autre) et cadrant une vue
## réellement chargée, pas un mur.
func _place_camera(camera: Camera3D, index: int) -> void:
	var origin: Vector3 = _spawn_position(index) + Vector3.UP * CAMERA_EYE_HEIGHT
	camera.global_transform = Transform3D(Basis(), origin)
	var target: Vector3 = _level_stats.get("center", Vector3.ZERO)
	if not origin.is_equal_approx(target):
		camera.look_at(target, Vector3.UP)


func _spawn_position(index: int) -> Vector3:
	var spawn_root: Node = _level_root.find_child(SPAWN_POINTS_NODE_NAME, true, false)
	if spawn_root != null:
		var marker: Node3D = spawn_root.get_node_or_null("Spawn%d" % index) as Node3D
		if marker != null:
			return marker.global_transform.origin
	var fallbacks: Array[Vector3] = [
		Vector3(-2, 1, 0), Vector3(2, 1, 0), Vector3(0, 1, -2), Vector3(0, 1, 2),
	]
	return fallbacks[index % fallbacks.size()]


func _clear_viewports() -> void:
	_viewport_rids.clear()
	for child in _grid.get_children():
		_grid.remove_child(child)
		child.queue_free()


# ---------------------------------------------------------------------------
# Mesure
# ---------------------------------------------------------------------------

func _measure() -> Dictionary:
	# Le tout premier palier paie la compilation des shaders : sans ce surcroît
	# d'échauffement, il ressort artificiellement mauvais et fausse la lecture.
	var warmup: float = first_warmup_seconds if not _first_measure_done else warmup_seconds
	_first_measure_done = true
	await _wait_seconds(warmup)

	var frames: int = 0
	var fps_min: float = INF
	var fps_sum: float = 0.0
	var draw_calls_sum: float = 0.0
	var primitives_sum: float = 0.0
	var frame_ms_max: float = 0.0
	var gpu_ms_sum: float = 0.0
	var gpu_ms_max: float = 0.0
	var cpu_ms_sum: float = 0.0
	var elapsed: float = 0.0

	while elapsed < sample_seconds:
		await get_tree().process_frame
		var frame_seconds: float = _last_frame_seconds()
		elapsed += frame_seconds
		frames += 1

		var fps: float = Performance.get_monitor(Performance.TIME_FPS)
		fps_sum += fps
		fps_min = minf(fps_min, fps)
		draw_calls_sum += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
		primitives_sum += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
		frame_ms_max = maxf(frame_ms_max, frame_seconds * 1000.0)

		# Somme sur les N viewports : c'est le coût de rendu total d'une frame
		# de split-screen, la vraie grandeur à tenir sous 16,7 ms.
		var gpu_ms: float = 0.0
		var cpu_ms: float = 0.0
		for rid in _viewport_rids:
			gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(rid)
			cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(rid)
		gpu_ms_sum += gpu_ms
		gpu_ms_max = maxf(gpu_ms_max, gpu_ms)
		cpu_ms_sum += cpu_ms

	var divisor: float = maxf(float(frames), 1.0)
	return {
		"load_nodes": _load_root.get_child_count(),
		"frames": frames,
		"fps_avg": fps_sum / divisor,
		"fps_min": fps_min,
		"frame_ms_max": frame_ms_max,
		"gpu_ms_avg": gpu_ms_sum / divisor,
		"gpu_ms_max": gpu_ms_max,
		"cpu_ms_avg": cpu_ms_sum / divisor,
		"draw_calls": draw_calls_sum / divisor,
		"primitives": primitives_sum / divisor,
		"video_mem_mb": Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0,
		"objects_drawn": Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME),
	}


func _last_frame_seconds() -> float:
	return maxf(get_process_delta_time(), 0.0001)


func _wait_seconds(seconds: float) -> void:
	var elapsed: float = 0.0
	while elapsed < seconds:
		await get_tree().process_frame
		elapsed += _last_frame_seconds()


# ---------------------------------------------------------------------------
# Rapport
# ---------------------------------------------------------------------------

func _print_report() -> void:
	var window: Vector2i = DisplayServer.window_get_size()
	var screen: int = DisplayServer.window_get_current_screen()

	print("BENCH_REPORT_BEGIN")
	print("mode: %s" % Mode.keys()[_mode].to_lower())
	print("scene: %s" % level_scene_path)
	print("renderer: %s" % ProjectSettings.get_setting("rendering/renderer/rendering_method", "unknown"))
	print("adapter: %s" % RenderingServer.get_video_adapter_name())
	print("window: %dx%d (écran %.0f Hz)" % [window.x, window.y, DisplayServer.screen_get_refresh_rate(screen)])
	print("vsync demandé: disabled, vsync effectif: %d, max_fps: %d, cible: %.0f fps" % [
		DisplayServer.window_get_vsync_mode(), Engine.max_fps, TARGET_FPS,
	])
	print("niveau: %d MeshInstance3D, %d triangles, %d Light3D" % [
		_level_stats.get("mesh_instances", 0),
		_level_stats.get("triangles_total", 0),
		_level_stats.get("lights", 0),
	])
	print("")
	print("Verdict = temps de rendu GPU total (somme des viewports) vs budget %.1f ms." % FRAME_BUDGET_MS)
	print("")
	print("| Config | vp | charge | **GPU ms** | GPU max | CPU ms | fps moy | draw calls | dc / vp | primitives | VRAM (Mo) | verdict |")
	print("|---|---|---|---|---|---|---|---|---|---|---|---|")
	var gpu_measured: bool = _gpu_timing_available()
	for r in _results:
		print("| %s | %d | %d | %.2f | %.2f | %.2f | %.1f | %.0f | %.0f | %.0f | %.0f | %s |" % [
			r.label, r.viewports, r.load_nodes,
			r.gpu_ms_avg, r.gpu_ms_max, r.cpu_ms_avg, r.fps_avg,  # fps affiché en %.1f
			r.draw_calls, r.draw_calls / float(r.viewports),
			r.primitives, r.video_mem_mb,
			_verdict(r, gpu_measured),
		])
	if not gpu_measured:
		print("")
		print("⚠️  **Le temps GPU n'est pas mesurable sur ce backend** (colonnes GPU à 0,00).")
		print("Les fps ne peuvent pas le remplacer : la présentation reste cadencée sur l'écran")
		print("même vsync désactivé, donc ils saturent à %.0f et un « OK » calculé dessus ne" % TARGET_FPS)
		print("prouve rien. Le verdict retombe sur le pire temps de frame observé, qui inclut")
		print("l'attente de présentation et surestime donc le coût réel — il alerte, il ne")
		print("rassure pas. Pour un chiffre GPU ferme : relancer les rampes `geometry` et")
		print("`lights`, dont le décrochage est un fait observable indépendant de l'horloge.")
	print("BENCH_REPORT_END")


## Le temps GPU par viewport n'est pas remonté par tous les backends (le
## backend Metal de Godot 4.6 renvoie 0). Zéro partout = non mesuré, pas
## « gratuit ».
func _gpu_timing_available() -> bool:
	for r in _results:
		if r.gpu_ms_max > 0.0001:
			return true
	return false


func _verdict(r: Variant, gpu_measured: bool) -> String:
	if gpu_measured:
		return "OK" if r.gpu_ms_avg <= FRAME_BUDGET_MS else "HORS BUDGET"
	# Sans mesure GPU, on ne peut que constater un dépassement franc du budget
	# de frame. On ne prononce jamais « OK » sur une mesure absente.
	if r.frame_ms_max > FRAME_BUDGET_MS * 2.0:
		return "HORS BUDGET"
	return "GPU non mesuré"

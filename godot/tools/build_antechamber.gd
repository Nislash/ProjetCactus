extends SceneTree

## Construit `res://data/levels/antechamber_terrain.tres` — l'Antichambre de
## Givre, le lieu des 8 beats d'onboarding (`docs/design/level01_onboarding.md`).
##
## Lancer :
##   godot --headless --path godot --script tools/build_antechamber.gd
##
## Même générateur que la caverne : des CHAMBRES et des GOULETS, le volume se
## referme tout seul là où il n'y en a pas. Réutiliser le générateur plutôt
## que de poser des boîtes à la main donne gratuitement l'étanchéité, la
## voûte, le navmesh et le recalage des marqueurs.
##
## ÉCART ASSUMÉ SUR LA SPEC. Le document annonce « ~25 × 15 m », mais il
## demande aussi sept beats en enfilade et, pour le seul B6, un chapelet de
## cristaux « à ~8 m les uns des autres ». Les deux ne tiennent pas ensemble :
## le chemin fait au bas mot 70 m. L'emprise retenue est donc 52 × 72 m —
## ce qui reste **1/25e** de la caverne en surface et une voûte deux fois plus
## basse. L'intention (« l'antichambre est un étui, la caverne sera la
## révélation d'échelle ») est tenue ; la cote littérale ne l'est pas.

const OUTPUT_PATH := "res://data/levels/antechamber_terrain.tres"

## Le couloir est plat. L'antichambre enseigne des verbes, pas du relief : un
## dénivelé n'apporterait ici qu'une occasion de se coincer.
const FLOOR_ALTITUDE := 0.0


func _init() -> void:
	var terrain := CavernTerrainData.new()
	terrain.bounds_min = Vector2(-16.0, -30.0)
	terrain.bounds_max = Vector2(36.0, 42.0)
	terrain.cell_size = 1.0
	terrain.chunk_size = 24.0
	# Voûte basse — 8 m dans les salles, 6 dans les goulets. La caverne
	# monte à 15 : l'écart se ressent au moment où la porte s'ouvre.
	terrain.min_headroom = 5.0
	terrain.max_headroom = 8.0
	terrain.playable_headroom_threshold = 2.5
	terrain.max_slope_degrees = 36.0

	terrain.chambers = _build_chambers()
	terrain.floor_field = _flat_floor()
	terrain.headroom_field = CavernHeightfieldSpec.new()

	if ResourceSaver.save(terrain, OUTPUT_PATH) != OK:
		push_error("Échec de l'écriture de %s" % OUTPUT_PATH)
		quit(1)
		return
	print("[antichambre] écrit : %s" % OUTPUT_PATH)
	_report(terrain)
	quit(0)


# ---------------------------------------------------------------------------
# La silhouette : un couloir en deux coudes, une alcôve par beat
# ---------------------------------------------------------------------------
#
# Le tracé est un Z : on ne voit jamais le beat suivant avant d'avoir joué le
# sien, ce qui est la contrainte structurante du document. Chaque coude coupe
# la ligne de vue, et c'est le coude — pas un glyphe — qui enseigne le stick
# droit au joueur.

func _build_chambers() -> Array[CavernChamber]:
	var chambers: Array[CavernChamber] = []

	# B1 — la chambre du Réveil. Les quatre cristaux de join sont en arc au
	# fond ; on entre dos à la sortie, on ne voit que le mur qui s'allume.
	chambers.append(_room("A1 Chambre du Réveil", Vector2(0.0, 0.0), Vector2(9.0, 7.0), 0.0, 8.0, 5.0))

	# B2 — la descente vers le premier coude.
	chambers.append(_corridor("G1 Veine de Givre", Vector2(0.0, -4.0), Vector2(0.0, -18.0), 3.5, 6.0, 3.5))
	chambers.append(_room("A2 Premier Coude", Vector2(0.0, -18.0), Vector2(6.0, 6.0), 0.0, 7.0, 4.0))

	# B3 — le goulet barré par le cristal fragile.
	chambers.append(_corridor("G2 Passage Barré", Vector2(0.0, -18.0), Vector2(20.0, -18.0), 3.5, 6.0, 3.5))

	# B4 — l'alcôve du parchemin. LE pic : elle est plus large que le goulet
	# qui y mène, la compression relâche pile au moment de la découverte.
	chambers.append(_room("A3 Alcôve du Parchemin", Vector2(24.0, -18.0), Vector2(7.5, 6.5), 0.0, 7.0, 4.5))

	# B5 — la remontée jusqu'au second coude, où le plafond cède.
	chambers.append(_corridor("G3 Remontée", Vector2(24.0, -14.0), Vector2(24.0, 4.0), 3.5, 6.0, 3.5))
	chambers.append(_room("A4 Coude du Piège", Vector2(24.0, 4.0), Vector2(6.0, 6.0), 0.0, 6.0, 4.0))

	# B6 — le long couloir du chapelet. Volontairement le plus long segment :
	# c'est celui qu'on parcourt dans le noir, et la longueur EST la tension.
	chambers.append(_corridor("G4 Chapelet", Vector2(24.0, 4.0), Vector2(24.0, 27.0), 3.5, 6.0, 3.5))

	# B7 — le dais du coffre, et la porte de glace au fond.
	chambers.append(_room("A5 Dais du Coffre", Vector2(24.0, 32.0), Vector2(8.0, 7.0), 0.0, 8.0, 5.0))

	return chambers


func _flat_floor() -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	spec.base_altitude = FLOOR_ALTITUDE
	# Un grain très faible : assez pour que le sol ne soit pas une table de
	# billard, trop faible pour créer un accroc sous les pieds.
	spec.noise_amplitude = 0.12
	spec.noise_scale = 6.0
	return spec


# ---------------------------------------------------------------------------
# Fabriques (mêmes signatures que build_cavern_terrain.gd)
# ---------------------------------------------------------------------------

func _room(label: String, center: Vector2, radii: Vector2, rotation: float,
		headroom: float, softness: float) -> CavernChamber:
	var c := CavernChamber.new()
	c.label = label
	c.center = center
	c.radii = radii
	c.rotation_degrees = rotation
	c.headroom = headroom
	c.edge_softness = softness
	return c


func _corridor(label: String, from_point: Vector2, to_point: Vector2, half_width: float,
		headroom: float, softness: float) -> CavernChamber:
	var c := CavernChamber.new()
	c.label = label
	c.is_corridor = true
	c.center = from_point
	c.to_center = to_point
	c.radii = Vector2(half_width, half_width)
	c.headroom = headroom
	c.edge_softness = softness
	return c


func _report(terrain: CavernTerrainData) -> void:
	var size: Vector2 = terrain.bounds_max - terrain.bounds_min
	print("[antichambre] emprise %.0f × %.0f m, voûte %.0f→%.0f m, %d poches."
		% [size.x, size.y, terrain.min_headroom, terrain.max_headroom, terrain.chambers.size()])

extends SceneTree

## Construit `res://data/levels/level02_forge_terrain.tres` — « La Forge »,
## niveau 2.
##
## Lancer :
##   godot --headless --path godot --script tools/build_forge_terrain.gd
##
## ## Le lieu
##
## Un cirque volcanique À CIEL OUVERT, en entonnoir : trois anneaux concentriques qui
## descendent vers un lac de lave central. On tourne autour du gouffre plutôt
## que de le traverser — l'inverse exact du niveau 1, où le lac gelé est une
## chaussée qu'on emprunte.
##
## ## Ce qui l'oppose à la Caverne Cristalline
##
## | | Niveau 1 | Niveau 2 |
## |---|---|---|
## | Lecture | horizontale, on traverse | **verticale**, on descend |
## | Nappe | lac gelé, praticable | **lac de lave**, mortel |
## | Lumière | par le haut (puits de jour) | **par le bas** (la lave) |
## | Danger | signalé par le chaud | tout est chaud : le danger se signale par le **mouvement** |
##
## Ce dernier point est le vrai problème de design du biome. Au niveau 1,
## l'ambre `#f2b45c` veut dire « esquive ». Ici la salle entière est ambre, et
## une couleur ne peut plus rien dire. C'est donc **ce qui bouge** qui alerte :
## la lave qui monte, les coulées qui s'ouvrent. Cf `level02_forge.md`.
##
## Le cirque fait 156 m ; derrière le château, un tunnel mène à l'**arène du
## Golem**, une salle à part. On ne rencontre donc le boss qu'après avoir
## résolu le puzzle — c'est ce qui donne un enjeu à la porte.

const OUTPUT_PATH := "res://data/levels/level02_forge_terrain.tres"

## Pente visée sur les descentes. Comme au niveau 1, sous le plafond de
## praticabilité : le bruit de surface ajoute son propre gradient.
const PATH_TARGET_DEG := 18.0


func _init() -> void:
	var terrain := CavernTerrainData.new()
	terrain.bounds_min = Vector2(-92.0, -142.0)
	terrain.bounds_max = Vector2(92.0, 78.0)
	terrain.cell_size = 1.25
	terrain.chunk_size = 40.0
	# Voûte plus basse et plus régulière qu'au niveau 1 : une forge est une
	# salle, pas un réseau. On doit sentir le couvercle au-dessus de la tête.
	# À CIEL OUVERT. La Forge n'est pas une cavité : c'est un cirque, bordé de
	# falaises, sous une lune rouge. Aucune voûte n'est construite — ce sont
	# les parois qui montent qui bornent le volume.
	#
	# La hauteur libre reste déclarée parce qu'elle définit la zone jouable et
	# sert aux contrôles d'étanchéité. Elle ne matérialise plus rien.
	terrain.open_sky = true
	terrain.open_sky_rim_height = 38.0
	terrain.min_headroom = 9.0
	terrain.max_headroom = 16.0
	terrain.playable_headroom_threshold = 2.5
	terrain.max_slope_degrees = 36.0

	terrain.chambers = _build_chambers()
	terrain.floor_field = _build_floor()
	terrain.headroom_field = CavernHeightfieldSpec.new()
	terrain.sky_openings = _build_openings()
	terrain.lake = _build_lava()

	if ResourceSaver.save(terrain, OUTPUT_PATH) != OK:
		push_error("Échec de l'écriture de %s" % OUTPUT_PATH)
		quit(1)
		return
	print("[forge] écrit : %s" % OUTPUT_PATH)
	_report(terrain)
	quit(0)


# ---------------------------------------------------------------------------
# La silhouette : un entonnoir, pas un réseau
# ---------------------------------------------------------------------------

func _build_chambers() -> Array[CavernChamber]:
	var chambers: Array[CavernChamber] = []

	# LE PUITS — la grande salle ronde qui contient tout. Une seule poche, là
	# où le niveau 1 en assemblait treize : la Forge se lit d'un coup d'œil.
	#
	# Rayon 46 et non 58 : avec son adoucissement, la poche s'étendait jusqu'à
	# 74 m sur un domaine qui n'en fait que 78. Il ne restait que quatre
	# mètres pour les falaises, et le cirque n'était donc pas borné.
	chambers.append(_room("F1 Le Puits", Vector2(0.0, -6.0), Vector2(56.0, 46.0), 0.0, 16.0, 11.0))

	# LES GALERIES D'ACCÈS. Trois entailles dans la paroi, décalées, qui
	# donnent au pourtour une silhouette mordue plutôt qu'un cercle parfait.
	chambers.append(_room("F2 Galerie Nord", Vector2(-6.0, 62.0), Vector2(22.0, 20.0), 15.0, 11.0, 9.0))
	chambers.append(_room("F3 Galerie Est", Vector2(62.0, -12.0), Vector2(20.0, 18.0), -20.0, 10.0, 9.0))
	chambers.append(_room("F4 Souffleries", Vector2(-58.0, -40.0), Vector2(24.0, 19.0), 35.0, 12.0, 10.0))

	# Les goulets qui les relient au Puits.
	chambers.append(_corridor("G1 Descente Nord", Vector2(-4.0, 56.0), Vector2(-2.0, 34.0), 7.0, 10.0, 6.0))
	chambers.append(_corridor("G2 Descente Est", Vector2(56.0, -10.0), Vector2(34.0, -6.0), 6.5, 10.0, 6.0))
	chambers.append(_corridor("G3 Descente Ouest", Vector2(-52.0, -36.0), Vector2(-32.0, -22.0), 6.5, 10.0, 6.0))

	# L'ARÈNE DU BOSS — une salle à part, DERRIÈRE le château.
	#
	# Le Golem se tenait auparavant au bord du bassin, à vingt-deux mètres du
	# centre du cirque : il s'éveillait avant même qu'on ait fini de descendre,
	# et le puzzle n'avait plus aucun sens puisqu'on se battait avant de
	# l'avoir résolu. Il faut franchir la porte pour le rencontrer.
	#
	# Elle est vaste — 38 m de rayon — parce qu'un boss de placement a besoin
	# d'espace : le tir ami est actif, et à quatre dans une salle étroite le
	# combat se joue entre joueurs plutôt que contre le boss.
	chambers.append(_room("A1 Arène du Golem", Vector2(0.0, -96.0), Vector2(38.0, 34.0), 0.0, 15.0, 12.0))
	# Le tunnel qui la relie au cirque, sous le château. Étroit et long : le
	# passage de l'un à l'autre doit se sentir.
	chambers.append(_corridor("G4 Sous le Château", Vector2(0.0, -50.0), Vector2(0.0, -70.0), 5.0, 9.0, 5.0))

	return chambers


func _build_floor() -> CavernHeightfieldSpec:
	var spec := CavernHeightfieldSpec.new()
	# Le pourtour est haut : on ARRIVE par le haut et on voit le gouffre.
	spec.base_altitude = 9.0
	# Une roche cassée, plus rugueuse que la glace du niveau 1.
	# Réduit de 0,9 à 0,5 : le bruit s'AJOUTE aux transitions de plateaux, et
	# là où deux fondus se recouvrent il suffisait à faire passer la pente
	# au-dessus du plafond de praticabilité.
	spec.noise_amplitude = 0.30
	spec.noise_scale = 11.0
	spec.noise_seed = 20260809

	var plateaus: Array[CavernPlateau] = []
	# LES TROIS ANNEAUX. Chacun est un palier plat : on descend par marches, et
	# chaque marche est un lieu où l'on peut se battre. Une pente continue
	# aurait fait glisser le combat vers le bas sans jamais l'y arrêter.
	# Les fondus sont dimensionnés sur le DÉNIVELÉ par rapport au palier
	# précédent, jamais sur l'altitude absolue : un `smoothstep` pique à 1,5
	# fois sa pente moyenne, et 4,5 m étalés sur 9 m donnent déjà 38°.
	# LES BERGES. Deux paliers ALIGNÉS SUR LES DOUVES, et non plus des anneaux
	# concentriques.
	#
	# Les anneaux dataient du lac rond du premier jet. Une rivière rectiligne
	# qui traverse des anneaux concentriques croise leurs bords partout, et
	# chaque croisement additionne deux fondus : on mesurait 40° à 45° un peu
	# n'importe où. Alignés sur la coulée, les paliers l'accompagnent au lieu
	# de la couper.
	plateaus.append(_plateau("Berge haute", Vector2(0.0, -14.0), Vector2(78.0, 44.0), 8.0, 16.0, true, 1.0))
	plateaus.append(_plateau("Berge basse", Vector2(0.0, -14.0), Vector2(64.0, 26.0), 3.5, 30.0, true, 4.5))

	# Les galeries d'accès sont à l'altitude du POURTOUR, pas au-dessus.
	#
	# Elles culminaient à 10,5-11 m alors que l'anneau haut est à 8 : leur
	# fondu recouvrait celui de l'anneau médian, et deux transitions qui se
	# superposent additionnent leurs pentes — 50° mesurés au premier essai.
	# Supprimer le dénivelé est plus sûr que l'étaler indéfiniment ; la galerie
	# se distingue déjà par sa voûte basse et son étroitesse.
	plateaus.append(_plateau("Seuil Nord", Vector2(-6.0, 66.0), Vector2(20.0, 16.0), 8.6, 14.0, true, 0.6))
	plateaus.append(_plateau("Seuil Est", Vector2(64.0, -12.0), Vector2(18.0, 16.0), 8.6, 14.0, true, 0.6))
	plateaus.append(_plateau("Souffleries", Vector2(-60.0, -42.0), Vector2(22.0, 17.0), 8.8, 14.0, true, 0.8))

	# L'arène est PLATE et plus basse que le cirque : on y descend, et une
	# fois dedans plus rien ne distrait du combat.
	plateaus.append(_plateau("Sol de l'Arène", Vector2(0.0, -96.0), Vector2(34.0, 30.0), 4.0, 22.0, true, 4.5))
	plateaus.append(_plateau("Tunnel", Vector2(0.0, -66.0), Vector2(8.0, 14.0), 5.5, 22.0, true, 1.5))

	# LA SOURCE, à l'ouest : un épaulement haut d'où la coulée descend. Et à
	# l'est, la lèvre par-dessus laquelle elle tombe. C'est ce qui donne à la
	# rivière un amont et un aval, donc un sens.
	plateaus.append(_plateau("Épaulement Source", Vector2(-72.0, -14.0), Vector2(15.0, 12.0), 6.0, 28.0, true, 5.0))
	plateaus.append(_plateau("Lèvre de la Chute", Vector2(76.0, -14.0), Vector2(12.0, 11.0), -4.0, 24.0, true, 3.0))
	spec.plateaus = plateaus

	var basins: Array[CavernBasin] = []
	# LES DOUVES. Plus une mare ronde au centre, mais une COULÉE qui traverse
	# le cirque d'ouest en est et passe sous le pont du château.
	#
	# Une nappe circulaire au milieu d'une cuvette ne raconte rien : elle est
	# là, elle ne va nulle part. Une rivière a une source et une chute, donc un
	# sens de lecture — et elle sépare le cirque du château, ce qui donne au
	# pont sa raison d'être.
	basins.append(_basin("Lit des Douves", Vector2(0.0, -14.0), Vector2(66.0, 17.0), 2.2, 0.6, 26.0, 0.40))
	spec.basins = basins
	return spec


## Plus aucune ouverture de voûte : il n'y a plus de voûte. Le ciel est
## partout, la lune éclaire tout ce que la lave n'atteint pas.
func _build_openings() -> Array[CavernSkyOpening]:
	return []


## Le lac de lave. Même système que le lac gelé du niveau 1 — c'est ce qui
## rend le biome bon marché à construire : une nappe, une altitude, une
## emprise. Seuls le matériau et ce qu'elle fait au joueur changent.
func _build_lava() -> CavernLake:
	var lava := CavernLake.new()
	lava.label = "Douves de lave"
	# +1,9 ET PAS -2,2.
	#
	# À -2,2, la nappe était SOUS la roche partout : le lit des douves ne
	# descend jamais plus bas que +1,18, donc la lave était enterrée de trois
	# mètres et rien n'en apparaissait. Le cirque montrait un fossé sec, et ce
	# que je prenais pour de la coulée dans les captures n'était que la lueur
	# des lampes posées sur les berges.
	#
	# La leçon est qu'une altitude de nappe ne se choisit pas dans l'absolu :
	# elle se choisit CONTRE le lit qu'on a creusé. À +1,9 la coulée remplit le
	# lit sur 0,5 à 0,7 m et lèche des berges qui montent à 2,4 — assez pour se
	# lire de loin, trop peu pour qu'on la prenne pour un lac.
	lava.surface_altitude = 1.9
	lava.minimum_depth = 0.2
	lava.center = Vector2(0.0, -14.0)
	lava.radii = Vector2(62.0, 8.0)
	lava.material_path = "res://data/levels/forge_lava_material.tres"
	return lava


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


## `drop` est le dénivelé RÉEL par rapport au terrain voisin — pas l'altitude
## absolue. Contrôler sur l'altitude donnait des alertes absurdes : un palier
## à 10 m au-dessus du zéro mais à 1,5 m de son voisin réclamait 48 m de
## fondu.
func _plateau(label: String, center: Vector2, half_extent: Vector2, altitude: float,
		falloff: float, is_ellipse: bool, drop: float = 0.0) -> CavernPlateau:
	var required: float = CavernTerrainBuilder.min_falloff_for(drop, PATH_TARGET_DEG)
	if falloff < required - 0.01:
		push_warning("[forge] « %s » : fondu %.1f m < %.1f m requis à %.0f°."
			% [label, falloff, required, PATH_TARGET_DEG])
	var p := CavernPlateau.new()
	p.label = label
	p.center = center
	p.half_extent = half_extent
	p.altitude = altitude
	p.falloff = falloff
	p.is_ellipse = is_ellipse
	return p


func _basin(label: String, center: Vector2, radii: Vector2, depth: float,
		rim_height: float, target_deg: float, flat_bottom: float = 0.0) -> CavernBasin:
	var required: float = CavernTerrainBuilder.min_falloff_for(depth + rim_height, target_deg)
	if minf(radii.x, radii.y) * (1.0 - flat_bottom) < required - 0.01:
		push_warning("[forge] « %s » : rayon utile %.1f m < %.1f m requis."
			% [label, minf(radii.x, radii.y) * (1.0 - flat_bottom), required])
	var b := CavernBasin.new()
	b.label = label
	b.center = center
	b.radii = radii
	b.depth = depth
	b.rim_height = rim_height
	b.flat_bottom = flat_bottom
	b.rim_width = CavernTerrainBuilder.min_falloff_for(rim_height, target_deg)
	return b


func _opening(label: String, center: Vector2, radii: Vector2, rotation: float) -> CavernSkyOpening:
	var o := CavernSkyOpening.new()
	o.label = label
	o.center = center
	o.radii = radii
	o.rotation_degrees = rotation
	return o


func _report(terrain: CavernTerrainData) -> void:
	var size: Vector2 = terrain.bounds_max - terrain.bounds_min
	print("[forge] emprise %.0f × %.0f m, voûte %.0f→%.0f m, %d poches, %d cheminées."
		% [size.x, size.y, terrain.min_headroom, terrain.max_headroom,
		terrain.chambers.size(), terrain.sky_openings.size()])

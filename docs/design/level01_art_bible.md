# Niveau 1 « Caverne Cristalline » — Art Bible

> **Statut : E0 en cours (#94).** Ce document est rempli par **● Opus** (palette, matériaux, budget, liste d'assets, contraintes) ; la **conception géographique/topographique** (silhouette, relief, sightlines, puits de ciel) est produite par **◆ Fable** en Session 1 à partir du *brief créatif* en §6.
>
> Réf. plan : `docs/design/level01_openworld_plan.md`. Décision actée : **option A** (grande caverne continue faite main).

---

## 1. Pitch visuel en une ligne

Une **grande caverne cristalline fermée et vallonée**, plongée dans la pénombre, éclairée par des **cristaux qui glow sur les parois** et des **puits de jour** perçant la voûte — le contraste entre les zones sombres (où les cristaux sont la boussole) et les flaques de lumière naturelle porte toute l'ambiance.

## 2. Contraintes spatiales (dures — cf plan §2)

| Contrainte | Spec |
|---|---|
| Hauteur de voûte | **10–15 m** au-dessus du sol praticable |
| Sol | **vallonné** (pentes douces, bosses, creux), praticable **partout** |
| Bornes | volume **fermé** : impossible de sortir |
| Anti-chute | **aucune chute possible** — creux = cuvettes bordées, zéro vide, pas de kill-floor |
| Zones ouvertes | **trous dans la voûte/parois** → on voit le ciel, ≥ 1 landmark visible de loin |
| POI | 4–6 points d'intérêt (loot, combat, puzzle, respiration) |

## 3. Palette (source de vérité — reprise de l'artifact du plan)

Neutres à **biais bleu** (jamais un gris pur), accent cristal cyan émissif, contre-accent chaud réservé au danger/boss.

| Rôle | Hex | Usage |
|---|---|---|
| Roche profonde | `#0a0e15` | ombres de caverne, fond |
| Roche | `#1e2b3e` → `#3a4a60` | parois, sol (variations) |
| Cristal cyan (émissif) | `#66d9ff` | **source lumineuse** murale, veines — couleur signature |
| Cristal profond | `#2f7fd4` | facettes, dégradés de cristaux |
| Facette violette | `#a98bff` | variété de cristaux (rare) |
| Jour (puits de ciel) | `#cfe4f2` chaud légèrement | shafts volumétriques, flaques au sol |
| Danger / boss / lave | `#f2b45c` | **réservé** aux telegraphs boss et hazards |

> Cohérence avec l'existant : les colonnes de cristal du blockout actuel utilisent déjà `albedo Color(0.45,0.85,1)` + `emission Color(0.2,0.6,0.9)` — on s'aligne dessus.

## 4. Matériaux (PBR, cibles pour Meshy retexture — E3)

| Matériau | Notes |
|---|---|
| **Roche de caverne** | PBR mate, roughness haute, micro-relief ; trim sheet + tri-planar pour le vallonné |
| **Cristal émissif** | translucide/metallic léger, `emission` ON, sert de **vraie source** (OmniLight au cœur) |
| **Veines / lichen luminescent** | glow diffus secondaire sur la roche, guide discret dans le noir |
| **Sol détaillé** | éboulis, poussière cristalline, flaques sous les puits de jour |
| **Puits de jour** | pas un matériau : `FogVolume` + `DirectionalLight`/`SpotLight` shafts par trou de voûte |

## 5. Budget technique — **mesuré** (2026-08-07)

> Les valeurs de cette section ne sont plus des estimations. Elles sortent de
> `godot/tools/bench/bench_split_screen.tscn`, qui doit être **relancé à l'identique** après E3
> (texturing) et E7 (packaging) pour comparer des chiffres comparables. Protocole et limites :
> [`docs/tech/perf_budget.md`](../tech/perf_budget.md).

**Machine de test** : Apple M4, Godot 4.6 Forward+/Metal, fenêtre 1920×942, 4 SubViewports de 960×471.

### 5.1. Coût du blockout actuel — la référence

| Viewports | draw calls | dc / viewport | primitives | CPU render | fps |
|---|---|---|---|---|---|
| 1 | 76 | 76 | 1 046 | 0,33 ms | 60 |
| 2 | 207 | 104 | 2 740 | 0,49 ms | 60 |
| 4 | 293 | 73 | 3 992 | 0,61 ms | 60 |

Le blockout pèse **35 MeshInstance3D et 420 triangles**. Autrement dit : **il ne coûte rien, et la
totalité du budget reste disponible** pour la caverne texturée. Ce n'est pas une bonne nouvelle en soi,
c'est juste le point de départ — la question utile n'était pas « combien coûte la scène actuelle » mais
« où est le plafond de la machine ». D'où les rampes ci-dessous.

### 5.2. Plafond mesuré — rampe géométrique à 4 viewports

Charge synthétique : N `MeshInstance3D` distincts (576 tris chacun), graine fixe, dans le champ des
4 caméras.

| Mailles | draw calls | dc / vp | primitives / frame | CPU render | fps | |
|---|---|---|---|---|---|---|
| 1 000 | 481 | 120 | 10,8 M | 2,58 ms | 60,0 | OK |
| **2 000** | **545** | **136** | **21,6 M** | **3,22 ms** | **60,0** | **dernier palier tenu** |
| 4 000 | 611 | 153 | 43,1 M | 4,01 ms | 50,7 | ❌ décrochage |

**Le genou est entre 2 000 et 4 000 objets distincts**, soit entre ~21 M et ~43 M de primitives par
frame cumulées sur les 4 viewports.

### 5.3. Budget de travail retenu

Cibles **par viewport**, avec une marge de sécurité de ~40 % sous le genou mesuré (une caverne réelle a
des shaders, du fog et du gameplay que la charge synthétique n'a pas) :

| Métrique | Cible retenue | Origine |
|---|---|---|
| Objets distincts visibles / viewport | **≤ 350** (≈1 400 au total) | genou à 500/vp, marge 30 % |
| Draw calls / viewport | **≤ 140** | mesuré à 136 au dernier palier tenu |
| Primitives / frame (4 vp cumulés) | **≤ 20 M** | mesuré à 21,6 M au dernier palier tenu |
| CPU render time (4 vp) | **≤ 4 ms** | 3,22 ms au dernier palier tenu |
| VRAM totale | **≤ 700 Mo** | 174 Mo à vide, ~300 Mo mesurés sous charge |
| Textures | atlas / trim sheets, 2K max par matériau | inchangé — `.glb` embed (LFS) |

> ⚠️ **L'ancienne cible « ≤ 1200 draw calls / viewport » était fausse d'un facteur ~9.** Le décrochage
> arrive à ~153 draw calls par viewport, pas 1200. Elle aurait laissé croire à une marge inexistante.
> À l'inverse, « ≤ 1,5 M triangles / viewport » était **trop conservateur** : on tient 5 M/vp.

### 5.4. Lumières à ombres portées — coût VRAM linéaire, coût frame non mesurable

Rampe de 1 à 32 `OmniLight3D` avec `shadow_enabled`, à 4 viewports :

| Lumières ombrées | VRAM | CPU render | fps |
|---|---|---|---|
| 1 | 213 Mo | 1,38 ms | 60,0 |
| 8 | 231 Mo | 1,42 ms | 60,0 |
| 32 | 299 Mo | 1,58 ms | 59,9 |

**Coût VRAM : ~2,7 Mo par lumière ombrée**, parfaitement linéaire — c'est l'allocation de sa shadow map.
Le coût en temps de frame, lui, **n'est pas mesurable sur cette machine** (cf §5.5) : les compteurs de
draw calls et de primitives ne bougent pas d'un iota entre 1 et 32 lumières. Ne pas conclure « les
ombres sont gratuites » : conclure « on sait ce qu'elles coûtent en VRAM, pas en temps ».
La consigne de l'art bible (**ombres portées réservées à 2-3 sources majeures**, le reste en émissif)
reste donc en vigueur, et sera revalidée sur la vraie caverne en E3.

### 5.5. Deux limites de mesure à connaître (elles changent la façon de lire ces chiffres)

1. **Les fps ne mesurent pas la marge sur cette machine.** Sous macOS/Metal la présentation reste
   cadencée sur l'écran 60 Hz *même avec `VSYNC_DISABLED` accepté par Godot*. Tout ce qui tient le
   budget affiche exactement 60,0 — impossible de distinguer « il reste 80 % de marge » de « il reste
   2 % ». Seul le **décrochage** est une information fiable ; d'où la méthode par rampe.
2. **Le chronométrage GPU est indisponible.** `RenderingServer.viewport_get_measured_render_time_gpu()`
   renvoie systématiquement 0 sur le backend Metal. On lit donc le **CPU render time**, qui ne capture
   que la soumission côté processeur.

Conséquence pratique : **sur une machine Windows/Vulkan, ces deux limites tombent** et les mêmes runs
donneront des chiffres plus fins. Le budget ci-dessus est volontairement prudent pour cette raison.

### 5.6. Fallback renderer

Le **renderer Mobile** reste prévu si le Forward+ ne tient pas une fois la caverne texturée (cf
`CLAUDE.md`). Le bench accepte `--rendering-method mobile` : la comparaison se fera avec des chiffres,
pas au jugé, au moment de la mesure post-texturing (E3).

## 6. Liste d'assets à produire (priorisée)

1. **Terrain caverne** (roche sol + parois + voûte) — texturé E3
2. **Cristaux muraux émissifs** — ≥ 3 variantes de silhouette (E4), instanciés MultiMesh
3. **Formations/piliers de cristal** landmarks — 2-3 grosses pièces héro (E4)
4. **Props caverne** : stalactites/stalagmites, éboulis (E4)
5. **Coffres** : départ + reliques, retexturés (E4)
6. **Boss Golem de cristal** retexturé (E4, sans casser IA/hitbox — cf #62 fait, #63/#64 en cours)

---

## 6bis. Brief créatif pour la Session 1 (◆ Fable) — conception géo/topographique

> À donner tel quel en entrée de la session Fable. Fable **conçoit**, ne code pas ici ; sa sortie alimente l'exécution Opus en Session 2 (#96).

**Rôle** : tu es level designer/directeur artistique. Conçois la **structure géographique et topographique** d'une grande caverne cristalline jouable en FPS coop split-screen 1-4 joueurs.

**Livrable attendu** (un document + un schéma topographique) :
1. **Silhouette & parti-pris** : la forme d'ensemble du volume, son « geste » (ex. un grand bol descendant vers l'arène boss ? une faille traversante ? un dôme central ?).
2. **Carte topographique** : le sol vallonné décrit par zones (altitudes relatives, pentes, bosses, cuvettes), sur une emprise cohérente pour 1-4 joueurs (ordre de grandeur à proposer, ~60-90 m de large).
3. **Sightlines & landmarks** : 2-3 repères visibles de loin (grosse formation de cristal, puits de lumière géant, pic rocheux), et ce qu'on voit d'où — comment la caverne « se lit » à l'œil.
4. **Puits de ciel** : où percer la voûte/les parois (nombre, taille, ce qu'ils éclairent au sol), pour créer le contraste jour/profondeur.
5. **Placement des 4-6 POI** dans le relief : spawn, zones de combat, nid de puzzle (3 cristaux), respiration/loot, antichambre + arène boss — avec la logique « où va le joueur et pourquoi ».
6. **Circulation** : comment on traverse le vallonné sans se coincer, où sont les montées/descentes, où l'arène boss se révèle.

**Contraintes dures** (non négociables) : voûte **10–15 m** ; **fermé** (aucune sortie) ; **aucune chute possible** (creux = cuvettes bordées, zéro vide) ; sol **praticable partout** ; ≥ 1 zone ouverte à ciel ouvert servant de landmark.

**Hors périmètre** : pas de texturing (E3), pas de placement moteur (Opus/Session 2), pas de code. Uniquement la **conception spatiale** + justification.

**Format de sortie** : Markdown structuré + un schéma (ASCII/coordonnées ou description assez précise pour qu'Opus le rebuild au MCP Godot en E2).

---

## 7. Definition of Done (E0 — #94)

- [x] Décision A notée dans `docs/design/levels.md` (section « Décision actée — Niveau 1 »)
- [x] Palette, matériaux, contraintes, budget de départ, liste d'assets (ce document)
- [ ] Budget technique **confirmé** sur la machine cible (remplacer les valeurs de départ)
- [ ] Brief créatif §6bis exécuté par Fable → carte topographique validée (alimente #96 E2)

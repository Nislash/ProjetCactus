# Budget perf 4-split — protocole de mesure

> Outil : `godot/tools/bench/bench_split_screen.tscn` + `tools/bench/split_screen_benchmark.gd`.
> Résultats et budget retenu : [`docs/design/level01_art_bible.md`](../design/level01_art_bible.md) §5.

Le jeu vise **60 fps en split-screen 4 joueurs**. Ce document décrit comment on le mesure, pourquoi
l'outil est construit ainsi, et surtout **ce que la mesure ne dit pas** — parce qu'un budget mal lu est
pire qu'une absence de budget.

## 1. Lancer une mesure

```bash
# Hors éditeur : l'éditeur Godot consomme lui-même du GPU et fausserait tout.
godot --path godot res://tools/bench/bench_split_screen.tscn -- --mode=baseline
godot --path godot res://tools/bench/bench_split_screen.tscn -- --mode=geometry
godot --path godot res://tools/bench/bench_split_screen.tscn -- --mode=lights

# Fallback renderer (cf CLAUDE.md)
godot --path godot res://tools/bench/bench_split_screen.tscn --rendering-method mobile -- --mode=geometry
```

La sortie est un tableau Markdown entre `BENCH_REPORT_BEGIN` et `BENCH_REPORT_END`, collable tel quel
dans l'art bible.

| Mode | Question à laquelle il répond |
|---|---|
| `baseline` | Combien coûte la scène actuelle, à 1 / 2 / 4 viewports ? |
| `geometry` | Combien d'objets distincts tient-on avant de décrocher ? |
| `lights` | Combien de lumières à ombres portées peut-on se payer ? |

**Quand le relancer** : après E3 (texturing) et avant le packaging E7. À l'identique — même machine,
même scène, mêmes paliers. Un bench dont on change les paramètres entre deux runs ne compare rien.

## 2. Pourquoi il ne passe pas par le jeu réel

`PlayerManager.try_register_device()` refuse tout device qui n'est pas une manette **physiquement
branchée**. Impossible donc de forcer 4 joueurs en automatisé. L'outil reproduit à la place la seule
chose qui compte pour la perf — **N SubViewports partageant le même `world_3d`, chacun avec sa
caméra** — sans le gameplay. Les caméras sont posées sur les **vrais marqueurs de spawn** et orientées
vers le barycentre du niveau : déterministe, donc comparable d'un run à l'autre, et cadrant une vue
réellement chargée plutôt qu'un mur.

## 3. Trois pièges rencontrés, et ce qu'ils impliquent pour le jeu

### 3.1. `positional_shadow_atlas_size` vaut 0 sur un SubViewport ⚠️

**C'est un piège pour le jeu, pas seulement pour le bench.** Un `SubViewport` a
`positional_shadow_atlas_size` à **0 par défaut** : sans atlas, les `OmniLight3D` et `SpotLight3D` n'y
projettent **aucune ombre**, silencieusement — alors qu'elles fonctionnent normalement dans le viewport
racine. En split-screen, tout le rendu passe par des SubViewports.

→ **Les cristaux muraux émissifs d'E3 sont directement concernés.** Si on veut qu'ils projettent des
ombres, il faudra le régler sur chaque SubViewport créé par `SplitScreenManager`, pas seulement dans le
bench. À vérifier au moment de l'éclairage.

### 3.2. Les fps ne mesurent pas la marge (macOS/Metal)

Sous macOS, la présentation reste cadencée sur l'écran 60 Hz **même quand Godot rapporte
`VSYNC_DISABLED` accepté** (`window_get_vsync_mode()` renvoie bien 0). Résultat : toute configuration
qui tient le budget affiche exactement `60.0`, qu'il reste 80 % ou 2 % de marge.

→ D'où la **méthode par rampe** : on ne cherche pas à lire une marge, on cherche le **point de
décrochage**. C'est la seule information fiable que la machine veut bien donner.

### 3.3. Le chronométrage GPU est indisponible

`RenderingServer.viewport_get_measured_render_time_gpu()` renvoie systématiquement `0` sur le backend
Metal. Les colonnes `GPU ms` du rapport sont donc vides **par limitation du backend, pas par bug de
l'outil** — elles sont conservées parce qu'elles se rempliront sur une machine Vulkan. On lit en
attendant le **CPU render time**, qui ne capture que la soumission côté processeur.

## 4. Comment lire le rapport

- **`verdict`** : `OK` tant que fps ≥ 57 (cible 60, tolérance 3 pour le bruit de mesure), `HORS BUDGET`
  en dessous. Le premier palier `HORS BUDGET` **est** la limite de la machine.
- **`dc / vp`** : draw calls divisés par le nombre de viewports. C'est cette grandeur-là qui se compare
  aux budgets par viewport, pas le total.
- **`primitives`** : cumul sur les 4 viewports, shadow passes comprises. Ne pas le diviser par 4 pour
  en déduire un « triangles par viewport » — le culling n'est pas uniforme entre les caméras.
- **`charge`** : nombre de nœuds de charge synthétique effectivement instanciés. Colonne de contrôle :
  si elle ne progresse pas d'un palier à l'autre, la mesure est invalide (c'est ce qui a permis de
  détecter un bug de rampe pendant la mise au point).

## 5. Ce que le bench ne couvre pas

- Le **coût gameplay** (IA, physique, projectiles, status effects) : la charge est purement graphique.
- Les **shaders réels** de la caverne texturée : la charge synthétique utilise le matériau par défaut.
  Le run post-E3 sur la vraie scène est donc le seul qui fasse foi pour le budget final.
- La **tenue thermique** : les mesures durent quelques secondes, pas une session de jeu. Un playtest
  long reste nécessaire pour détecter un throttling.


---

## 6. Mesure post-texturing (● Opus, tâche #20, 2026-08-08)

Relancé à l'identique après E3 (matériaux PBR, éclairage, brume par zone) et E4/E6 (props bakés,
gameplay câblé, boss habillé). Machine : Apple M4, Forward+, fenêtre 1920 × 942, écran 60 Hz.

### 6.1. Ce que coûte le niveau

| | 1 viewport | 2 viewports | **4 viewports** |
|---|---|---|---|
| Draw calls (total) | 107 | 224 | **428** |
| Draw calls **par viewport** | 107 | 112 | **107** |
| Primitives | 119 k | 256 k | **478 k** |
| VRAM | 249 Mo | 280 Mo | **341 Mo** |
| CPU rendu | 0,44 ms | 0,66 ms | **0,74 ms** |

Géométrie du niveau : 63 `MeshInstance3D`, **102 892 triangles**.

Le coût par viewport est **plat** (107 → 112 → 107) : le split-screen multiplie le travail sans
surcoût par écran. C'est ce qu'on veut, et ce n'était pas acquis — les quatre vues partagent le même
`world_3d`, donc tout gain de culling profite quatre fois.

### 6.2. L'écart avec le checkpoint E2

Le blockout non texturé tournait à **70 draw calls/viewport et 310 Mo**. On est à **107 et 341 Mo**.
Le texturing, les props, la brume, le boss et la chaîne de puzzle coûtent donc **+37 draw calls par
viewport (+53 %) et +31 Mo**. C'est cher en proportion et négligeable en absolu : le décrochage
géométrique est deux ordres de grandeur plus loin.

### 6.3. Où sont les murs

| Rampe | Dernier palier tenu | Premier palier décroché | Marge du niveau |
|---|---|---|---|
| Géométrie | **4 000 mailles — 10,5 M primitives, 60 fps** | 8 000 mailles — 20,4 M primitives, **54 fps** | le niveau en consomme 478 k, soit **×22** |
| Lumières ombrées | **32 — 60 fps, aucun décrochage** | *jamais atteint dans la rampe* | le niveau en a une poignée |

La rampe de lumières ne décroche pas : ce n'est pas le temps de rendu qui limite les sources ombrées
ici, c'est la **VRAM des atlas d'ombres** (347 → 433 Mo entre 1 et 32 lumières, +2,7 Mo par source).

**Conclusion : aucune optimisation n'est justifiée à ce stade.** Le niveau tient 60 fps en 4-split
avec vingt fois la marge géométrique, et le poste qui bouge vraiment est la mémoire vidéo — c'est là
qu'il faudra regarder au packaging (#32), pas dans le nombre de draw calls.

### 6.4. Deux défauts de l'outil, corrigés au passage

**Le compteur de triangles renvoyait 0.** Une surface non indexée renvoie `null` à l'emplacement des
indices ; l'affecter à un `PackedInt32Array` typé levait une erreur par maille. Toute la caverne est
générée en triangles bruts non indexés, donc le rapport annonçait « 0 triangles » sur une scène qui
en a cent mille.

**Le verdict s'appuyait sur les fps.** Le fichier documentait pourtant l'inverse (§3.2 : les fps
saturent à 60 sur macOS). Chaque ligne affichait donc « OK » quelle que soit la charge — un verdict
faussement rassurant, le pire genre. Le bench dit maintenant **« GPU non mesuré »** quand le backend
ne remonte pas de temps GPU, et ne prononce « HORS BUDGET » que sur un dépassement franc du temps de
frame. Il n'écrit plus jamais « OK » sur une mesure absente.


---

## 7. Post-process activé (● Opus, tâche #31)

Trois passes ajoutées à `level01_cavern_environment.tres` : **glow**, **SSAO**, **ajustements**.

Le glow est la plus importante et de loin : toute l'identité du niveau repose sur des cristaux
**émissifs**, et sans halo un émissif n'est qu'un aplat clair — il brille sur le papier, pas à
l'écran. Le halo est volontairement **large** (niveaux 3-5, pas 1-2) : serré il ferait « néon »,
large il fait « lumière dans la brume ».

**Mesuré, pas supposé.** Une capture A/B au même point de vue, glow activé puis désactivé, donne deux
images quasi identiques hors du halo des puits : le post-process **ne délave pas** l'image. Ce qui la
délave à ce point de vue précis (arrêt 5 du tour, regard vers la voûte), c'est la brume volumétrique
traversée sur toute sa longueur — un comportement antérieur à cette passe. À trancher par la review
artistique (#33), pas par une retouche silencieuse d'un éclairage déjà validé.


### 7.1. Ce que le post-process coûte, mesuré

Même protocole, après activation du glow, du SSAO et des ajustements :

| | avant | après | écart |
|---|---|---|---|
| Draw calls / viewport (4-split) | 107 | 107 | **inchangé** |
| Primitives | 478 k | 478 k | inchangé |
| CPU rendu | 0,74 ms | 0,88 ms | +0,14 ms |
| **VRAM** | 341 Mo | **392 Mo** | **+51 Mo** |

Le post-process ne coûte **rien** en géométrie — c'est du plein écran. Il coûte de la **mémoire
vidéo** : les pyramides de glow et le tampon SSAO, alloués une fois par viewport. C'est la
confirmation du §6.3 : à ce stade du projet, le poste qui bouge est la VRAM, pas les draw calls.

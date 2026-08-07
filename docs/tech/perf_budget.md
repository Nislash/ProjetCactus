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

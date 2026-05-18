# Pipeline de génération des niveaux — Plan

> Source de vérité topologique : `docs/design/levels/topology.drawio` (9 pages = légende + 8 niveaux).
> Cible : remplacer les `.tscn` générés "à la main par LLM" (défauts géométriques) par une pipeline déterministe en 5 étapes.

---

## 1. Résumé du drawio (ce que je vois)

### Conventions globales

**Strates verticales** (axe Y in-game, codage couleur dans le diagramme) :

| Code | Couleur | Sens |
|---|---|---|
| `+3` / sommet | rouge | altitude max |
| `+2` | orange foncé | |
| `+1` | jaune | |
| `0` / RDC | vert | référence entrée |
| `−1` | bleu indigo | sous-sol |
| `−2` | bleu marine | profondeur max |
| `void` | pointillé gris | extérieur / zéro-G |

**Glyphes** (= types de nœuds) :

| Glyphe | Type |
|---|---|
| Rectangle arrondi | `room` (taille du rect ≈ importance gameplay) |
| Rectangle fin | `corridor` (couloir explicite, rare — la plupart sont implicites entre salles) |
| Rhombus blanc | `door` (porte normale) |
| Rhombus rouge épais | `boss_door` (verrouillée par puzzle, label = clés requises ex. "P1+P2+P3") |
| Ellipse verte "P×4" | `spawn` (1-4 joueurs) |
| Ellipse violette "Pn" | `puzzle_trigger` (totem/levier/cristal/brasero/grimoire/forge…) |
| Triangle orange | `mini_boss` |
| Hexagone rouge épais | `boss_arena` |
| Parallélogramme or | `loot` (coffre majeur) |
| Étoile cyan | `meta_fragment` (1 par niveau → fin spéciale si 8/8) |
| Plus blanc | `checkpoint` |

**Connexions** (= edge `kind`) :

| Style trait | Kind |
|---|---|
| Plein, sans flèche | `corridor` (couloir normal, latéral) |
| Pointillé fin `2 2` | `secret_passage` |
| Plein rouge, label `Pn` | `locked_passage` (déverrouillé par trigger) |
| Flèche double `↕ escalier` | `stairs` |
| Flèche double marron `↕ échelle` | `ladder` |
| Flèche bleue épaisse `lift` | `elevator` |
| Pointillé `8 4` `jump` | `jump_required` (gravité réduite) |
| Flèche orange épaisse `drop ↓` | `one_way_drop` (irréversible) |
| Pointillé gris `void` / `dérive` | `zero_g_drift` (N8 uniquement) |

### Inventaire des 8 niveaux

| # | Nom | Strates | Salles | Triggers puzzle | Boss | Mécanique signature |
|---|---|---|---|---|---|---|
| N1 | Caverne crystalline | 0 / −1 / −2 | 8 (entrée, hall, g1-3, cachée, profonde, boss) | P1, P2, P3 (briser 3 cristaux) | Golem de cristal | visibilité limitée |
| N2 | Marais toxique | 0 / −1 | 7 (ilot_dep + a/b/c/d, bassin, boss) + 1 couloir noyé | P1, P2, P3 (totems-sangsue) | Sangsue géante | brouillard + slow eau + DoT |
| N3 | Temple gravité réduite | 0 / +1 / +2 / +3 | 7 (parvis, piédestal, 3× plat+1, 2× plat+2, boss) | P1, P2, P3 (idoles à aligner) | Idole flottante | gravité réduite, sauts 8m |
| N4 | Forge en fusion | −1 / 0 / +1 / +2 / +3 | 5 (fonderie + 3 ateliers + boss) | P1, P2, P3, P4 (forger 4 clés) | Forgeron infernal | lave montante (timer 6 min) |
| N5 | Bibliothèque hantée | 0 / +1 / +2 / +3 / +4 | 9 (hall + 4× ailes w/e) + ascenseur central + dôme boss | P1, P2, P3, P4 (4 grimoires) | Liche bibliothécaire | sorts ennemis amplifiés |
| N6 | Montagne frozen | 0 / +1 / +2 / +3 | 8 (camp, chemin, versants w/e, refuge, col w/e + pont, boss) | P1, P2, P3 (éteindre 3 braseros) | Roi de glace | gel immobile >3s |
| N7 | Labyrinthe miroirs | −1 / 0 / +1 | 11 (place + 4 maisons + 3 combles + 3 sous-sols + boss) | P1, P2, P3 (tuer 3 leurres) | Doppelganger | reflets ennemis + faux passages |
| N8 | Vide cosmique | périphérie / médian / cœur | 9 (aster_dep + 7 plateformes + boss) | P1..P7 (clins d'œil aux 7 niveaux précédents) | Boss final | zéro-G + timer respiration |

**Total** : ~64 salles, ~30 triggers puzzle, 8 boss, 8 mini-boss, 8 fragments méta, 8+ loots, 2 checkpoints (N6 uniquement).

### Détail des graphes (un par niveau)

#### N1 — Caverne crystalline
- **Rooms** : `entree` (spawn, loot, strate 0) — `hall` (carrefour, −1) — `g1` (mêlée, −1, P1) — `g2` (ranged, −1, mini-boss) — `g3` (charger, −1, P2) — `cachee` (P3, −2) — `profond` (arrivée −2) — `cour` (couloir d'arène) — `boss` (Golem, −2).
- **Edges** : `entree ↔ hall` stairs · `hall ↔ g1` corridor · `hall ↔ g2` corridor · `g2 ↔ g3` corridor · `g1 ↔ cachee` ladder · `hall ↔ profond` stairs · `g3 ↔ boss` stairs · `profond → dlock(P1+P2+P3) → cour → boss` corridor · `cachee ↔ frag` secret.

#### N2 — Marais toxique
- **Rooms** : `ilot_dep` (spawn, 0) — `ilot_a` (P1, 0) — `ilot_b` (P2 + mini-boss, 0) — `ilot_c` (P3, 0) — `ilot_d` (loot + pont, 0) — `bassin` (−1) — `cour_b` (couloir noyé) — `boss` (Sangsue, −1).
- **Edges** : `ilot_dep ↔ a/c` corridor (ponts) · `a ↔ b`, `c ↔ b`, `b ↔ d` corridor · `d → dlock(P1+P2+P3) → bassin` **one_way_drop** · `bassin ↔ cour_b ↔ boss` · `boss ↔ frag` secret.

#### N3 — Temple gravité réduite
- **Rooms** : `parvis` (spawn, 0) — `piedestal0` (P1, 0) — `plat1a` / `plat1b` (P2) / `plat1c` (mini-boss, +1) — `plat2a` (P3, +2) / `plat2b` (loot, +2) — `boss` (Idole, +3).
- **Edges** : tous **jump_required** entre strates, plus `plat2b → dlock(P1+P2+P3) → boss` ("pont de lumière" post-puzzle) · `plat2a ↔ frag` secret jump.
- ⚠ pas d'edges latéraux dans la même strate explicites (plat1a ↔ plat1b ?). À vérifier visuellement.

#### N4 — Forge en fusion
- **Rooms** : `fonderie` (spawn + P1, −1) — `atelier0` (P2, 0) — `atelier1` (P3 + mini-boss, +1) — `atelier2` (P4 + loot, +2) — `boss` (Forgeron, +3).
- **Edges** : `fonderie ↔ atelier0` stairs · `atelier0 ↔ atelier1` stairs · `atelier1 ↔ atelier2` elevator · `atelier2 → dlock(4 clés) → boss` elevator final · `atelier1 ↔ frag` secret.
- **Constraint hors graphe** : lave qui inonde par strate à T+90s puis monte (timer 6 min) — pas une connexion mais une règle de gameplay.

#### N5 — Bibliothèque hantée
- **Rooms** : `hall0` (spawn, 0) — `aile0w` (P1, 0) / `aile0e` (0) — `aile1w` (P2, +1) / `aile1e` (loot, +1) — `aile1w → aile2w` (P3, +2) / `aile2e` (secrète + frag, +2) — `aile3w` (P4, +3) / `aile3e` (mini-boss, +3) — `lift_lbl` (ascenseur central, traverse toutes strates) — `boss` (Liche, dôme +4).
- **Edges** : `hall0 ↔ lift_lbl` elevator · `hall0 ↔ aile0w` corridor · `aile0w ↔ aile0e` · escaliers verticaux entre `aileNw ↔ aile(N+1)w` · `aileNw ↔ aileNe` corridor par étage · `aile2w ↔ aile2e` secret · `lift_lbl → dlock(4 grimoires) → boss`.
- ⚠ `lift_lbl` est dessiné comme un grand bloc vertical (60×600 px) — c'est un **shaft**, pas une salle habitable. Faut-il en faire une room ou juste une liaison verticale ? **À trancher**.

#### N6 — Montagne frozen
- **Rooms** : `camp` (spawn + chk0, 0) — `chemin0` (sinueux, 0) — `versant_w` (P1, +1) — `refuge1` (chk1, +1) — `versant_e` (mini-boss, +1) — `col_w` (P2, +2) — `cor_col` (pont gelé, couloir, +2) — `col_e` (P3, +2) — `boss` (Roi de glace, +3).
- **Edges** : `camp ↔ chemin0` · `chemin0 ↔ versant_w` · `chemin0 ↔ refuge1` · `refuge1 ↔ versant_e` · `versant_e → camp` **one_way_drop** (avalanche) · `versant_w ↔ col_w` · `versant_e ↔ col_e` · `col_w ↔ cor_col ↔ col_e` · `col_e → dlock(braseros) → boss` ("pont gelé") · `versant_e ↔ frag` secret.

#### N7 — Labyrinthe miroirs
- **Rooms** : `entree` (place + spawn, 0) — `m_a` (P1, 0) — `m_b` (P2, 0) — `m_c` (P3, 0) — `m_d` (RDC, 0) — `comble_a/c/d` (+1, `comble_c` loot, ni `comble_b`) — `ss_x/y/z` (−1, `ss_z` reflet boss, `ss_y` faux passages) — `boss` (Doppelganger, central élargi).
- **Edges** : rues `entree ↔ m_a/m_b`, `m_a ↔ m_c`, `m_b ↔ m_d`, `m_c ↔ m_d` · `m_d → dlock(3 leurres tués) → boss` · échelles `m_a ↔ comble_a`, `m_c ↔ comble_c`, `m_d ↔ comble_d` · passerelles `comble_a ↔ comble_c ↔ comble_d` · escaliers `m_a ↔ ss_x`, `m_b ↔ ss_y`, `m_c ↔ ss_y`, `m_d ↔ ss_z` · `ss_x ↔ ss_y ↔ ss_z` · `ss_z ↔ frag` secret · `ss_y ↔ ss_x` **faux passage** (kind spécial — illusoire, à matérialiser en cul-de-sac visuel ?).

#### N8 — Vide cosmique
- **Rooms** : `aster_dep` (spawn) — `ap1..ap7` (7 plateformes, chacune un trigger P1..P7) — `ap5` a aussi un mini-boss — `boss` (cœur cosmique + fragment au cœur).
- **Edges** (toutes en `zero_g_drift`) : `aster_dep ↔ ap1`, `aster_dep ↔ ap2`, `ap1 ↔ ap6`, `ap6 ↔ ap3`, `ap3 ↔ ap5`, `ap5 ↔ ap4`, `ap4 ↔ ap7`, `ap7 ↔ ap2`, puis `dlock(P1..P7) → boss` (entrée cœur).
- ⚠ **manque** : aucune edge explicite ne relie une plateforme `apN` au `dlock` ni au `boss`. Le drawio suppose probablement que le passage central est implicite ou que la dlock s'active quand les 7 sont fait. **À clarifier**.

### Ambiguïtés détectées

**Décision tranchée** (cf §5) : **le parser lève une erreur explicite** sur chacune de ces ambiguïtés. L'utilisateur patche le drawio à la source puis re-run. Aucune inférence silencieuse.

1. **N3** : pas d'edge latéral entre `plat1a/1b/1c` ni entre `plat2a/2b` dans la même strate — chaque plateforme est-elle passable que via jumps verticaux ? Ou couloirs implicites manquants ? → **erreur si pas d'edge latéral et plus d'une room dans la strate**.
2. **N5** : `lift_lbl` est un shaft de 600 px de haut — type room ou type pure connection ? Aucun trigger ni contenu dedans → **erreur** : faut explicitement le tagger `kind=shaft` (pure connection) ou ajouter du contenu pour en faire une room.
3. **N7** : kind `false_passage` (faux passage gris) → **erreur** : kind d'edge non reconnu, faut décider entre `secret_passage` (qui mène quelque part) ou nouveau kind `dead_end` (cul-de-sac court).
4. **N8** : edges manquantes entre plateformes et entrée cœur (dlock/boss) → **erreur** : aucune edge ne relie `apN` au `dlock1` ; le parser ne peut pas inférer ce que veut dire "P1..P7 alignés".
5. **Inter-niveaux (N→N+1)** : convention validée : tuer le boss du niveau N déclenche le passage N→N+1. **Pas besoin de l'expliciter dans le drawio**. Le JSON canonique génère automatiquement `stairs_to_next_level: {from_room: <boss>, trigger: on_boss_defeat, target: level_(N+1)}` pour les niveaux 1-7.

---

## 2. Pipeline (5 étapes)

### Layout général

```
levels.drawio
   │
   ▼  parser/drawio_to_json.py
levels.json  ──── 1 fichier canonique par niveau, validé
   │
   ▼  layout/force_directed.py + config.json
layouts/level_N.json  ──── {room_id: {x,y,w,h,doors[]}}
   │
   ▼  corridors/{astar,drunkard}.py
geometry/level_N.json  ──── grille avec sols/murs/portes
   │
   ▼  validation/checks.py
   │   ↓ retry max 10× avec seed différent
   ▼
exports/level_N.tres  ──── ressource Godot custom
   │
   ▼  (côté Godot) dungeon_builder.gd  ── async TileMap + nœuds enfants
runtime
```

### Localisation dans le repo

| Composant | Chemin |
|---|---|
| Pipeline Python (étapes 1-4) | `tools/dungeon_pipeline/` |
| Tests pytest | `tools/dungeon_pipeline/tests/` |
| Configs | `tools/dungeon_pipeline/config.json` |
| Sorties intermédiaires (gitignore) | `tools/dungeon_pipeline/build/` |
| Ressource Godot custom | `godot/scripts/world/level_layout.gd` (`class_name LevelLayout`) |
| `.tres` exportés | `godot/data/levels/level_N.tres` |
| Builder runtime (GridMap 3D) | `godot/scripts/world/dungeon_builder.gd` |
| MeshLibrary tiles (sol/mur/escalier 3D) | `godot/scenes/world/dungeon_mesh_library.tres` |
| Tests GDScript GUT | `godot/tests/world/` |

**Owner** : Machine B (content/world).
**Branche** : `feature/B-level-pipeline` (créée depuis `main` propre après merge PR #92).
**Anciens blockouts** : déplacés dans `godot/archive/levels/` (encore référencés par le lobby avec tag `[archive]` jusqu'à ce que la pipeline génère leurs remplaçants).

### Étape 1 — Parser `drawio → JSON`

**Module** : `tools/dungeon_pipeline/parser/drawio_to_json.py`

**Entrée** : `docs/design/levels/topology.drawio`
**Sortie** : `tools/dungeon_pipeline/build/levels.json`

**Algo** :
1. Parse XML avec `xml.etree.ElementTree` (lib std).
2. Itère sur `<diagram>` (1 = légende skip, 8 = niveaux).
3. Pour chaque `<mxCell>` :
   - Si `vertex="1"` : extrait `id`, `value`, `style`, `mxGeometry (x,y,w,h)`.
   - Le `style` classifie en `room` / `corridor` / `door` / `boss_door` / `spawn` / `puzzle_trigger` / `mini_boss` / `boss_arena` / `loot` / `meta_fragment` / `checkpoint` / `stratum_band` (les bandes de strate sont des rectangles englobants — ignorées pour le graphe, gardées comme `stratum` tag sur les rooms qu'elles contiennent).
   - Attribution strate par **AABB containment** : la room dont la bbox est dans la bbox d'un `stratum_band` hérite de son code couleur → tag `stratum: 0|+1|−1|...`.
   - Objets glyphes (spawn, p_n, loot, etc.) attachés à leur room conteneuse par AABB.
4. Pour chaque `<mxCell edge="1">` : extrait `source`, `target`, `style`, `value`. Classifie en `corridor` / `secret_passage` / `locked_passage` (rouge + label) / `stairs` / `ladder` / `elevator` / `jump_required` / `one_way_drop` / `zero_g_drift` / `false_passage`.
5. Construit le JSON canonique :

```json
{
  "schema_version": 1,
  "levels": [
    {
      "id": "level_1",
      "name": "Caverne crystalline",
      "boss": "Golem de cristal",
      "signature_mechanic": "visibilité limitée",
      "rooms": [
        {"id": "entree", "type": "spawn", "stratum": "0", "tags": ["loot"]},
        {"id": "hall",   "type": "combat", "stratum": "-1", "tags": []},
        {"id": "g1",     "type": "combat", "stratum": "-1", "tags": ["trigger:P1"]},
        ...
      ],
      "edges": [
        {"from": "entree", "to": "hall", "kind": "stairs"},
        {"from": "g1", "to": "cachee", "kind": "ladder"},
        ...
      ],
      "doors": [
        {"id": "dlock1", "between": ["profond", "cour"], "unlock_keys": ["P1","P2","P3"]}
      ],
      "contents": {
        "entree": {"spawn": true, "loot_major": 1},
        "g1":     {"puzzle_trigger": "P1", "enemies_hint": "melee"},
        ...
      },
      "stairs_to_next_level": {"from_room": "boss", "trigger": "on_boss_defeat", "target": "level_2"}
    }
  ]
}
```

**Validation au parse** :
- exactement 1 spawn par niveau ;
- ≥ 1 boss_arena par niveau ;
- pas de room orpheline (graphe connexe) ;
- chaque `door` rouge a un label `unlock_keys` non vide ;
- ambiguïtés N3/N5/N7/N8 listées plus haut → **erreurs explicites** ou décisions encodées dans le code, jamais d'inférence silencieuse.

**Tests** :
- `test_parse_legend_skipped()` : la page légende n'apparaît pas dans levels[].
- `test_parse_n1_topology()` : N1 a 8 rooms, edges attendus.
- `test_parse_orphan_room_raises()` : fixture XML cassée → erreur.
- `test_parse_missing_spawn_raises()`.
- Idem pour chaque niveau N1..N8 (snapshot comparaison rooms/edges).

### Étape 2 — Layout (graphe → coordonnées grille)

**Module** : `tools/dungeon_pipeline/layout/force_directed.py`

**Algo** :
1. Init : positions aléatoires (seed du niveau).
2. Force-directed (Fruchterman-Reingold) :
   - chaque edge = ressort (attraction `k_spring * distance`) ;
   - chaque paire de rooms = répulsion (`k_repulse / distance²`) ;
   - **stratum constraint** : composante `y` contrainte autour du Y central de la strate (force vers `y_target = stratum_index * stratum_height`).
3. Itère N=500 max ou Δposition < ε.
4. Snap sur grille : `floor(x/cell_size)`, `floor(y/cell_size)`.
5. Vérifie absence de chevauchement de rooms (AABB inflate par `room_spacing`) ; si chevauchement, re-tire seed.
6. Calcule **door anchors** (= positions des portes sur les murs des rooms) selon le voisin connecté : porte sur le côté du voisin le plus proche.

**Tailles par défaut (`config.json`)** :

```json
{
  "room_sizes": {
    "spawn": [7, 7],
    "combat_small": [9, 9],
    "combat_large": [12, 12],
    "boss_arena": [15, 15],
    "loot": [5, 5],
    "secret": [4, 4],
    "corridor_node": [3, 3]
  },
  "stratum_height_cells": 24,
  "room_spacing_cells": 3,
  "force_directed": {
    "iterations_max": 500,
    "epsilon": 0.5,
    "k_spring": 0.05,
    "k_repulse": 2000,
    "stratum_pull": 0.1
  }
}
```

**Sortie** : `tools/dungeon_pipeline/build/layouts/level_N.json` :

```json
{
  "level_id": "level_1",
  "seed": 12345,
  "grid_size": [80, 60],
  "rooms": {
    "entree":   {"x": 4,  "y": 4,  "w": 7,  "h": 7,  "stratum": "0",  "doors": [{"x": 11, "y": 7, "to": "hall"}]},
    "hall":     {"x": 20, "y": 28, "w": 12, "h": 12, "stratum": "-1", "doors": [...]},
    ...
  }
}
```

**Tests** : convergence, pas de chevauchement, rooms même strate alignées en Y, doors sur des murs.

### Étape 3 — Couloirs (A* + drunkard)

**Modules** :
- `tools/dungeon_pipeline/corridors/astar.py`
- `tools/dungeon_pipeline/corridors/drunkard.py`

**Couloirs normaux (A*)** :
- Source = door A, target = door B.
- Coûts : `+1` par tuile vide, `+5` par tuile adjacente à un mur de salle (évite de longer une salle), `+∞` à l'intérieur d'une salle (interdit).
- **Stairs / ladder / elevator** : modélisés comme un nœud virtuel à `stratum diff` — l'A* prend un escalier au passage et ressort dans la strate cible. Sortie : tag tuile `stair_up` / `stair_down`.

**Passages secrets (drunkard's walk)** :
- Marche aléatoire seedée entre door A et door B, longueur = `1.5×–2× distance directe`, biais 30 % vers la cible pour garantir la fin.
- Stops si on entre dans une room non-prévue → annule et retire.

**Edges spéciaux** :
- `jump_required` : pas de couloir physique, juste tag de plateforme avec `jump_target: B_room_id` (le gameplay portera le saut).
- `one_way_drop` : tuile drop unique sur le mur source.
- `zero_g_drift` (N8) : ne pas creuser de couloir, marquer juste l'edge comme `traversable_in_zero_g`.
- `false_passage` (N7) : creuse un couloir court qui se termine en cul-de-sac (max 5 tuiles), pas relié au target.

**Sortie** : `tools/dungeon_pipeline/build/geometry/level_N.json` — grille 2D par strate avec tuiles `floor` / `wall` / `door` / `secret_door` / `stair_up` / `stair_down` / `drop` / `void`.

**Tests** : pas de couloir traversant une salle, A* trouve toujours un chemin sur fixtures valides, drunkard se termine bien sur target.

### Étape 4 — Validation (filet de sécurité — **étape critique manquante last time**)

**Module** : `tools/dungeon_pipeline/validation/checks.py`

**Checks** (par niveau, par strate, et global multi-strates) :
1. **Connexité globale** : flood-fill depuis tuile `spawn`. Doit atteindre tous les `room.floor`, tous les `boss_arena`, tous les `loot`, tous les `meta_fragment`, tous les `stair_*` qui mènent à la strate ou niveau suivant.
2. **Cohérence portes** : chaque `door` doit être sur un mur de salle, avec un couloir aligné côté extérieur, pas de mur au milieu de l'ouverture.
3. **Spawn safe** : spawn dans une salle, sur `floor`, pas adjacent à `wall`.
4. **Boss reachable & locked** : `boss_arena` atteignable **après** activation des keys dans son `door.unlock_keys`. Simulé en flood-fill 2 fois : sans keys (doit échouer à atteindre boss), avec keys (doit y arriver).
5. **Fragment méta atteignable** : doit être atteignable, mais possiblement via `secret_passage` (autorisé).
6. **Pas de tuile orpheline** : aucun `floor` ou `corridor` non connecté à un spawn.
7. **Strata coherence** : tuiles `stair_up` ↔ `stair_down` alignées entre strates.

**Sur échec** : log précis (`level_id`, `room_id`, `(x, y)`, check raté) ; sortie code ≠ 0 ; retry layout+corridors avec nouveau seed (max 10) ; sinon erreur fatale.

**Tests** : fixtures de niveaux **cassés exprès** (boss non atteignable, porte au milieu d'un mur, tuile orpheline, etc.) — la validation doit les **attraper**.

### Étape 5 — Export Godot (GridMap 3D natif)

**Cible 3D** : décision tranchée → **GridMap 3D**, pas TileMap 2D. La pipeline produit (x, stratum, z) ; le builder remplit une `GridMap` Godot avec des meshes sol/mur/escalier issus d'une `MeshLibrary`.

**Modules** :
- `tools/dungeon_pipeline/export/godot_resource.py` (sérialisation `.tres`).
- `godot/scripts/world/level_layout.gd` (la classe Resource).
- `godot/scripts/world/dungeon_builder.gd` (le runtime, GridMap-based).
- `godot/scenes/world/dungeon_mesh_library.tres` (MeshLibrary des tuiles 3D).

**Mapping strate → Y in-game** :
- Cell size GridMap : `Vector3(4, 3, 4)` (1 cellule = 4m × 3m haut × 4m).
- Strate `N` → Y world = `N * 3.0` (1 strate = 1 niveau vertical de GridMap).
- Strates supportées : `−2`, `−1`, `0`, `+1`, `+2`, `+3`, `+4` (cf drawio).

**Resource Godot** :

```gdscript
class_name LevelLayout extends Resource
@export var level_id: String
@export var seed: int
@export var grid_size: Vector3i             # (width, strata_count, depth)
@export var rooms: Dictionary               # room_id -> {origin: Vector3i, size: Vector3i, stratum: int, type: String, tags: PackedStringArray}
@export var cells: PackedByteArray          # flat array, tile_id par cellule (encodage MeshLibrary)
@export var doors: Array                    # array of {pos: Vector3i, room_a: String, room_b: String, locked: bool, keys: PackedStringArray}
@export var stairs: Array                   # array of {pos: Vector3i, dir: String, target_room: String, kind: String}  # kind = stairs|ladder|elevator|jump|drop|drift
@export var contents: Dictionary            # room_id -> {spawn: bool, enemies: Array, loot: Array, puzzle_trigger: String, mini_boss: bool, meta_fragment: bool}
@export var inter_level: Dictionary         # {from_room: String, trigger: String, target_level: String}
```

**Builder runtime (`dungeon_builder.gd`)** :
- `await load_layout(path: String) -> LevelLayout`.
- Itère sur `cells` ; remplit la `GridMap` via `set_cell_item(Vector3i, mesh_id)`. `await get_tree().process_frame` toutes les 200 cellules pour éviter de bloquer le thread.
- Pas d'autotiling à coder soi-même : la `MeshLibrary` contient des variantes (mur droit, mur coin, mur intersection en T, etc.) et le pipeline tagge la bonne variante par cellule.
- Place spawn, ennemis, loots, triggers, boss comme **PackedScene instanciées** (`packed_scene.instantiate()`), ajoutées sous un nœud `Entities` enfant de la scène niveau.
- Pas de logique dans `_ready()` — méthode `build_async(layout: LevelLayout) -> Signal` appelée explicitement par le `lobby_controller` après le chargement.

**Determinisme** : même `seed` → même niveau (force-directed et drunkard's walk utilisent un RNG seedé).

**Tests** : ouverture du `.tres` en éditeur, runtime build sur N1, screenshot, comparaison à expected (smoke tests GUT côté Godot).

---

## 3. Livrables

| # | Fichier | Étape |
|---|---|---|
| 1 | `tools/dungeon_pipeline/parser/drawio_to_json.py` + tests | 1 |
| 2 | `tools/dungeon_pipeline/layout/force_directed.py` + tests | 2 |
| 3 | `tools/dungeon_pipeline/corridors/{astar,drunkard}.py` + tests | 3 |
| 4 | `tools/dungeon_pipeline/validation/checks.py` + tests (fixtures cassées) | 4 |
| 5 | `tools/dungeon_pipeline/export/godot_resource.py` | 5 |
| 6 | `godot/scripts/world/{level_layout,dungeon_builder}.gd` | 5 |
| 7 | `tools/dungeon_pipeline/regenerate_all.py` (orchestrateur CLI) | meta |
| 8 | `tools/dungeon_pipeline/config.json` | meta |
| 9 | `tools/dungeon_pipeline/README.md` | meta |

---

## 4. Méthode de travail

1. **Aucun code avant validation user de ce résumé**.
2. Implémenter **étape par étape**, chaque étape verte (tests + revue) avant la suivante.
3. Pas de placement de tuiles par LLM — pipeline déterministe algo + seed.
4. Commit Git séparé par étape (`feat(pipeline): step N — parser drawio`, etc.) pour faciliter le revert.
5. À la fin, le N1 actuel (blockout direct) sera **remplacé** par le N1 généré ; les autres `.tscn` blockout (`level_02_marais..level_08_vide`) seront archivés ou supprimés.

---

## 5. Décisions actées (validées par l'utilisateur)

| # | Question | Décision |
|---|---|---|
| 1 | Langage pipeline (étapes 1-4) | **Python 3.11+** avec pytest. Tests indépendants de Godot, CLI scriptable. |
| 2 | Ambiguïtés drawio (N3/N5/N7/N8) | **Erreurs explicites**. Le parser refuse de produire un JSON canonique si une ambiguïté est rencontrée. L'utilisateur patche le drawio, re-run. |
| 3 | Transitions N→N+1 | **Convention "tuer boss N → ouvre passage"**. Pas d'edit drawio nécessaire. Le builder spawn un portail/escalier dans l'arène boss à sa mort. |
| 4 | Branche Git | **`feature/B-level-pipeline`** créée depuis `main` propre après merge PR #92 (qui consolide foundation + blockouts). |
| 5 | Anciens `.tscn` blockout | **Déplacés dans `godot/archive/levels/`**. Le lobby pointe encore vers eux (tag `[archive]` dans le label) jusqu'à ce que la pipeline régénère leurs remplaçants. |
| 6 | 2D vs 3D côté runtime | **GridMap 3D natif Godot**. Pipeline produit (x, stratum, z) → builder remplit GridMap via MeshLibrary. Cellule 4m × 3m haut × 4m. |
| 7 | Review PR | **Self-merge** (un seul humain, 2 sessions Claude). |

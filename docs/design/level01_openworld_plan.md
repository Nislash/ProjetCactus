# Niveau 1 « Caverne Cristalline » — Plan grande caverne semi-ouverte + texturing

> **Statut : PLAN (aucun code).** Owner : à définir (chevauche Machine A systèmes + Machine B contenu).
> Objectif : emmener le niveau 1 — le plus abouti — d'un blockout jouable à une **grande caverne fermée, vallonée et semi-ouverte**, texturée PBR, avec pipeline de textures autonome (Meshy) et **onboarding diégétique** repensé. Vertical slice « cadeau ».
>
> **« Open world » était un abus de langage** : on ne veut pas un monde ouvert, mais **une seule grande caverne continue** — fermée (on ne peut pas en sortir ni tomber), au sol vallonné praticable partout, avec des **zones ouvertes à ciel ouvert** là où la voûte est percée.
>
> Version présentable (artifact) : voir le lien partagé dans la session Claude Code.

---

## 1. Où en est le niveau 1 aujourd'hui

Deux versions coexistent + une base de systèmes déjà solide. Le manque n'est pas le gameplay, c'est **la matière et l'espace**.

**Acquis — blockout fait main** (`godot/scenes/levels/level_01_poc/level_01_poc.tscn`)
- 5 salles + couloirs + arène boss, colonnes de cristal émissives cyan
- Golem de cristal + 3 ennemis (mêlée, ranged, charger), ciel procédural, navmesh

**Acquis — pipeline de génération** (`tools/dungeon_pipeline/` → `godot/data/levels/level_1.tres`)
- drawio → JSON → layout → A* → validation → **GridMap 3D** (déterministe, seedé, testé)
- 8 salles, puzzle 3 cristaux, mécanique signature nommée : **visibilité limitée**

**Acquis — systèmes de jeu**
- Combos arme×parchemin (Rust), IA boss (Rust), 50 reliques, status effects, XP, down/revive, FF
- HUD par viewport, minimap, coffres, game-over ; mécaniques prêtes : freeze / low-gravity / rising-lava

**À combler pour le cadeau**
- **Zéro texture PBR** (tout est du BoxMesh gris) · topologie **cloisonnée** en salles ·
  onboarding = menu + coffre (rien de diégétique) · aucun landmark ni profondeur de champ ni ambiance

---

## 2. Direction actée — la grande caverne semi-ouverte

Décision prise : **une seule grande caverne continue faite main** (option A), en vitrine. On **sort le niveau 1 de la pipeline** (qui reste la source des niveaux 2–8, documentée comme cas à part). Ce n'est pas un monde ouvert : c'est un **volume fermé, cohérent et entièrement praticable**.

### 2.1. Cadrage spatial (contraintes dures)

| Contrainte | Spec |
|---|---|
| **Hauteur de voûte** | **10–15 m** au-dessus du sol praticable (échelle qui rend le lieu imposant sans écraser le combat) |
| **Sol** | **Vallonné** — pentes douces, bosses, creux ; **praticable partout**, pas de zone décorative inaccessible |
| **Bornes** | Caverne **fermée** : parois + voûte referment le volume, **impossible de sortir** de la zone jouable |
| **Anti-chute** | **Aucune chute possible** — pas de vide ni de gouffre sans fond ; les creux sont des cuvettes bordées, jamais des trous mortels. Pas de kill-floor à gérer parce qu'il n'y a nulle part où tomber |
| **Zones ouvertes** | **Trous dans la voûte/les parois** → on **voit le ciel** par endroits ; respirations visuelles + gameplay |

### 2.2. Éclairage (deux sources diégétiques)

1. **Glows sur les murs** — des éléments qui **émettent de la lumière** sur la roche (cristaux, veines, champignons/lichens luminescents) : ce sont les **vraies sources** qui guident le joueur dans les zones sombres → colonne vertébrale de la mécanique **visibilité limitée**.
2. **Lumière extérieure** — **puits de jour** entrant par les trous de la voûte : shafts volumétriques, flaques de lumière naturelle au sol, contraste fort avec les zones profondes.

Le texturing Meshy et l'onboarding sont valables tels quels sous cette direction.

---

## 3. Textures — intégration Meshy (réponse à la question outillage)

Il existe un **MCP officiel** Meshy, branchable comme le `godot-mcp` déjà présent. Un agent peut générer / retexturer / poller / télécharger **en autonomie**.

- Serveur : **`@meshy-ai/meshy-mcp-server`** (officiel, `npx`, 24 tools) · alt communautaire : `pasie15/meshy-ai-mcp-server`
- Clé : **`MESHY_API_KEY`** (variable d'environnement, **jamais commit**)
- Tools clés : `meshy_text_to_3d`, `meshy_image_to_3d`, **`meshy_retexture`**, `meshy_remesh`, `meshy_uv_unwrap`,
  `meshy_get_task_status`, `meshy_download_model`, `meshy_check_balance` — export `glb / fbx / obj / usdz`
- **Pas de skill Meshy tout prêt** trouvé ; le MCP suffit. On pourra encapsuler la boucle dans un skill maison `meshy-texture-agent` plus tard.

**Boucle de l'agent texture autonome :**
`brief (art bible)` → `text_to_3d / retexture` → `get_task_status (poll async)` → `download_model → glb dans godot/assets/` → `import Godot + LFS + entrée manifest`

**Config `.mcp.json` (ZONE PARTAGÉE → PR isolée, cf CLAUDE.md) :**
```json
"meshy": {
  "command": "npx",
  "args": ["-y", "@meshy-ai/meshy-mcp-server"],
  "env": { "MESHY_API_KEY": "msy_..." }
}
```

**Garde-fous avant de lancer l'agent :**
- LFS déjà actif sur `.glb/.png` (vérifier `.gitattributes`)
- Convention de nommage (`crystal_wall_a.glb`) + `assets_manifest.yaml` (prompt + task-id → reproductible)
- **Valider la licence commerciale** du plan Meshy avant d'embarquer les assets, tracée par asset
- Clé API en env, budget crédits suivi (`meshy_check_balance`)

---

## 4. Onboarding repensé — diégétique, pas un menu

Aujourd'hui : lobby (Start pour rejoindre) → boutons Tuto/Run → coffre (tire classe+arme) → run.
Problème : ça n'apprend ni les combos, ni le FF, ni le revive, ni la mécanique signature.

**Nouvelle entrée = première scène du jeu (antichambre cristalline) :**
1. **Le réveil** — chaque manette qui fait Start **allume un cristal** (join = rituel visible)
2. **Bouger & regarder** — suivre une veine lumineuse (glyphes manette, zéro mur de texte)
3. **Le premier tir** — briser un cristal fragile (viser+tirer ; les cristaux réagissent)
4. **Le combo qui se ressent** — ramasser le feu **transforme l'arme sous tes yeux** (signature, dès la 1re minute)
5. **Le drill de coop** — un allié « tombe » scripté, les autres apprennent le revive (Interact 3 s) + FF
6. **L'obscurité qui tombe** — premier goût de la **visibilité limitée**, les cristaux deviennent la boussole
7. **Le coffre en climax** — plus un écran : récompense diégétique qui lance la run
8. **Solo-friendly & skippable** — jouable à 1, validé par l'action (pas le temps), skip mémorisé par device

---

## 5. Stratégie modèles IA (Opus 4.8 / Fable 5)

Deux modèles, deux rôles. **Opus 4.8 est le défaut** (inclus dans la souscription → gratuit au point d'usage). **Fable 5 est mesuré** (budget ~100 $) et réservé aux tâches à fort levier — dont, explicitement, **le travail créatif de structure géographique et topographique** du niveau, où sa puissance créative fait la différence.

| | Opus 4.8 (défaut) | Fable 5 (réservé, mesuré) |
|---|---|---|
| Prix (in/out par 1M) | 5 $ / 25 $ · **inclus** | 10 $ / 50 $ · **budget 100 $** |
| Rôle | Cheval de trait : exécution, wiring, `.tres`, scripts, docs, MCP Godot, review courante | Spécialiste : **création géo/topographique**, Rust dur (`boss_ai`, `combo_engine`), algo (navmesh sur relief), archi, passes de review |
| Bonus | Fast mode (sortie ~2,5× plus rapide) | Pas de fast mode |

**Règles :**
- **On démarre toujours sur Opus.** On passe à Fable seulement si la tâche est marquée `Fable` ci-dessous, ou si Opus cale visiblement (escalade).
- **Créatif géo/topo = Fable.** La silhouette de la caverne, le relief vallonné, la composition des sightlines, l'emplacement des puits de ciel et des landmarks, la logique de « où va le joueur et pourquoi » — c'est là qu'on exploite la créativité de Fable (E0 concept + E2 design).
- **Borne chaque run Fable** (`effort: high`, cahier des charges complet d'entrée, prompt caching) — l'output à 50 $/1M est ce qui vide le budget.
- **Sessions dédiées** : ne pas alterner Opus↔Fable dans une même session (ça invalide le cache).
- **Calibration d'abord** : ~15 $ en A/B Fable vs Opus sur 2-3 tâches dures avant d'engager le reste.

### 5.1. Regroupement en sessions cohérentes par modèle

Les étapes E0–E7 sont **mixtes** par nature, mais on ne veut pas basculer Opus↔Fable en cours de route (cache invalidé, budget gaspillé, contexte créatif perdu). On **réordonne le travail en 5 sessions mono-modèle**, en respectant les dépendances (le créatif Fable précède l'exécution Opus qu'il alimente).

| # | Session | Modèle | Regroupe | Produit |
|---|---|---|---|---|
| 0 | **Calibration** | ◆ Fable (~15 $) | 2-3 tâches A/B, dont **un test de concept topographique** | mesure du burn + validation créative |
| 1 | **Direction créative** | ◆ Fable | E0 concept géo/topo · **E2 design topo + logique navmesh** · direction créative d'E3 (mood), E4 (silhouettes), E5 (rythme) | spec topographique + bible de direction artistique |
| 2 | **Construction** | ● Opus | E0 rédaction bible/budget · E1 Meshy · **E2 exécution MCP Godot** · E3 texturing · E4 assets · E5 onboarding | caverne texturée jouable |
| 3 | **Boss & tension** | ◆ Fable | E6 **`boss_ai`** (Rust) · design rencontres/tension · mise en scène révélation | IA boss + design combat |
| 4 | **Gameplay & finition** | ● Opus | E6 wiring encounters/placement/récompenses · E7 audio/perf/bugs/build | run complète + build jouable |
| 5 | **Review finale** | ◆ Fable | E7 passe de review caverne + boss | validation avant remise |

**Logique du séquencement** :
- **Toute la direction créative est front-loadée dans la Session 1** (Fable) : topo, relief, mood, silhouettes, rythme — produits en un seul passage pendant que le contexte créatif est chaud. Opus n'a plus besoin de Fable pour construire E1→E5.
- **Session 2 (Opus)** est la longue phase d'exécution : elle lit la spec/bible produite en Session 1 et construit tout.
- **Sessions 3-4** répètent le motif sur le gameplay : Fable conçoit l'IA + le combat, Opus câble.
- **Session 5 (Fable)** clôt par la review.
- Budget Fable **concentré sur 3 sessions bornées** (1, 3, 5) + calibration → facile à suivre et à plafonner.

---

## 6. Feuille de route — 8 paliers avec Definition of Done

Chaque étape est shippable/testable seule. « Done » = **vérifié**, pas « codé ». Playtest humain 2–4 joueurs là où marqué. Chaque étape indique le **modèle** à utiliser.

### E0 — Cadrage & art bible
**Modèle : Mixte.** Opus pour rédiger la bible et chiffrer le budget technique. **Fable pour le concept créatif géo/topographique** : silhouette de la caverne, langage de relief, parti-pris des puits de ciel et des landmarks.
Trancher A, poser la DA et le budget technique avant de produire.
- [ ] **Décision A vs B actée** et notée dans `docs/design/levels.md`
- [ ] Art bible `docs/design/level01_art_bible.md` : palette, matériaux, refs, échelle
- [ ] Budget technique chiffré : poly / draw-calls / texture pour **4 viewports à 60 fps**
- [ ] Liste priorisée des assets (terrain, cristaux, props, boss, coffres)

### E1 — Meshy branché · agent texture autonome
**Modèle : Opus (défaut).** Plomberie MCP, manifest, LFS, licence — pas besoin de Fable.
Intégrer le MCP et prouver la boucle sur **un** asset avant d'industrialiser.
- [ ] MCP Meshy configuré, clé en **env**, **PR `.mcp.json` isolée** mergée
- [ ] Un asset test **généré → téléchargé → importé → visible en jeu**, texturé
- [ ] `assets_manifest.yaml` en place (prompt + task-id + licence par asset)
- [ ] LFS vérifié ; **licence commerciale Meshy confirmée**

### E2 — Blockout de la grande caverne fermée & vallonée
**Modèle : Fable (étape phare) → Opus pour l'exécution.** **Fable conçoit la structure géographique et topographique** : plan de la caverne, sculpture du relief vallonné, sightlines, composition des landmarks et des puits de ciel, placement intentionnel des 4–6 POI, et la logique algorithmique du **navmesh sur relief**. **Opus exécute** ensuite le placement via MCP Godot. *(C'est l'étape où le budget Fable travaille le plus.)*
Géométrie grise à la **bonne échelle** : un volume unique, voûte 10–15 m, **sol vallonné praticable partout**, **fermé** (aucune sortie, aucune chute), avec les **trous de voûte** vers le ciel déjà troués. Landmarks + 4–6 POI. Édition via **MCP Godot** (pas de `.tscn` à la main).
- [ ] Caverne **traversable de bout en bout** (spawn → boss), sans cul-de-sac cassé
- [ ] **Voûte à 10–15 m**, sol **vallonné** (pentes/bosses/creux) où le joueur va **partout**
- [ ] Volume **fermé** : impossible de sortir, **impossible de tomber** (creux = cuvettes bordées, zéro vide)
- [ ] ≥ 1 **zone ouverte à ciel ouvert** trouée dans la voûte, visible de loin comme landmark
- [ ] Navmesh + collisions OK sur terrain vallonné ; **playtest 2–4 joueurs** : pas de blocage, pas de coincement dans les pentes, split-screen lisible
- [ ] 4–6 POI placés avec intention (loot, combat, puzzle, respiration)

### E3 — Texturing passe 1 · roche, glows muraux, puits de jour
**Modèle : Opus (défaut).** Boucle Meshy retexture, matériaux, éclairage, brume. *Option Fable* : une courte passe créative de direction d'éclairage/ambiance si on veut pousser le mood.
Matériaux PBR sol/murs/roche (Meshy retexture + trim sheets), **éclairage à deux sources** (glows sur les murs + shafts de lumière extérieure par les trous), brume au service de la mécanique.
- [ ] Sol/murs/roche **texturés PBR** — plus de BoxMesh gris sur le chemin critique
- [ ] **Glows muraux** (cristaux/veines) posés comme **vraies sources** qui guident dans les zones sombres
- [ ] **Puits de jour** par les trous de voûte : shafts volumétriques + flaques de lumière au sol, fort contraste jour/profondeur
- [ ] Brume/portée de vue branchées sur la **mécanique signature** (visibilité limitée), réglées jouables
- [ ] Perf tenue en **4-split** (mesure avant/après, budget E0)

### E4 — Hero assets & props
**Modèle : Opus (défaut).** Génération Meshy, retexture, composition de sous-scènes. *Option Fable* : concepting créatif des variantes de formations cristallines si on veut des silhouettes plus originales.
Objets signature via Meshy (text-to-3d + retexture), instanciés en sous-scènes (composition).
- [ ] ≥ 3 variantes de formations cristallines + props, en `.tscn` réutilisables
- [ ] Coffres départ/reliques **retexturés**, cohérents art bible
- [ ] Boss Golem **habillé** sans casser IA (Rust) ni hitbox
- [ ] Assets tracés au manifest ; LFS OK ; scène sans erreur (MCP `get_errors`)

### E5 — Onboarding diégétique
**Modèle : Opus (défaut).** Construction de l'antichambre, scripting des beats, wiring, skip. *Option Fable* : design créatif du rythme/mise en scène des 8 beats si on veut peaufiner l'émotion.
Antichambre + 8 beats ; glyphes manette ; skippable mémorisé par device.
- [ ] Un **nouveau joueur seul** comprend bouger / tirer / combo / revive **sans aide externe**
- [ ] Le combo est **montré et ressenti** dans la 1re minute
- [ ] Join allume un cristal par manette ; le coffre lance la run proprement
- [ ] Skip fonctionnel/mémorisé ; **playtest 2–4 joueurs** confirme la clarté

### E6 — Gameplay open-world
**Modèle : Mixte.** **Fable** pour le Rust dur (**`boss_ai`**), le design créatif des rencontres/tension et la mise en scène de la révélation du boss (adossée aux sightlines conçues en E2). **Opus** pour le wiring des encounters, le placement et les récompenses.
Rencontres réparties, récompenses d'exploration, puzzle 3 cristaux à l'échelle du monde, révélation du boss mise en scène.
- [ ] Boucle complète : **explorer → combattre → puzzle → boss → victoire**
- [ ] L'exploration **récompense** (loot caché hors chemin critique)
- [ ] Révélation du boss **cadrée** par un landmark ; arène se verrouille/déverrouille
- [ ] Difficulté validée en **playtest 2–4 joueurs** (ni triviale, ni injuste avec FF)

### E7 — Polish, perf & packaging cadeau
**Modèle : Opus (défaut) + une passe de review Fable.** Opus pour audio/post-process/perf/bugs/build. **Fable** pour une **passe de review finale** du plus gros livrable (caverne + boss) avant la remise.
Audio d'ambiance, post-process, réglage 4-split, chasse aux bugs, build + parcours de démo.
- [ ] Ambiance audio + post-process ; **60 fps tenus en 4-split** sur la machine cible
- [ ] Zéro erreur console, zéro asset manquant ; run complète sans crash
- [ ] **Build jouable** livré (exécutable + notes de lancement)
- [ ] Script de démo 3 min prêt ; niveau 1 **présentable tel quel**

---

## 7. Risques & garde-fous

| Risque | Garde-fou |
|---|---|
| **Perf** — le 4-split fait mal (textures + brume × 4) | Budget dès E0, mesures E3/E7, fallback renderer Mobile prévu |
| **Assets** — style Meshy incohérent | Vocabulaire de prompt figé (art bible), retexture > regénérer, manifest reproductible |
| **Licence** — droits commerciaux IA | Valider les conditions Meshy avant E1, tracer la licence par asset |
| **Scope** — la caverne grossit sans fin | 4–6 POI max au POC, volume fermé borné, DoD stricte, reste en phase 2 |
| **Terrain** — sol vallonné = joueur qui se coince / nav cassée | Pentes douces plafonnées, navmesh régénéré + testé sur le relief, playtest E2 dédié |
| **Repo** — conflits Godot | Édition via MCP Godot, PR isolée `.mcp.json`/`project.godot`, respect machine-split |
| **Pipeline** — casser N2–8 | La pipeline reste la source des autres niveaux ; N1 = cas showcase documenté |

---

## 8. Le cadeau — script de démo 3 min

1. **Le réveil** — Start → un cristal s'allume. C'est vivant.
2. **La 1re minute qui apprend** — bouger, tirer un cristal, ramasser le feu → l'arme se transforme (signature offerte d'entrée).
3. **L'obscurité** — la lumière baisse, les cristaux deviennent des repères ; la caverne texturée respire.
4. **L'exploration** — grimper vers un landmark, trouver une relique planquée, résoudre le puzzle.
5. **Le boss** — le Golem se révèle, cadré par la caverne ; coop + FF + revive servent.
6. **La remise** — « C'est le niveau 1. Joyeux cadeau. »

# Niveau 1 « Caverne Cristalline » — Plan open-world + texturing

> **Statut : PLAN (aucun code).** Owner : à définir (chevauche Machine A systèmes + Machine B contenu).
> Objectif : emmener le niveau 1 — le plus abouti — d'un blockout jouable à une **zone open-world texturée PBR**, avec pipeline de textures autonome (Meshy) et **onboarding diégétique** repensé. Vertical slice « cadeau ».
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

## 2. Décision structurante — quel « open world » ?

| Option | Description | Verdict |
|---|---|---|
| **A. La grande caverne continue** *(recommandé)* | Une caverne vaste, verticale, non-linéaire, faite main comme **vitrine**. Sightlines, landmarks cristallins, POI, exploration libre, visibilité limitée = vraie tension. | Le « waouh » maximal, parfait à offrir. |
| **B. Le donjon gonflé** | Garder la pipeline, l'ouvrir : salles larges, murs percés, seamless, plus de verticalité. | Plus safe, réutilisable, mais reste « donjon aéré ». Fallback. |

**Reco : A pour le niveau 1**, tout en **gardant la pipeline vivante pour les niveaux 2–8**.
Le texturing Meshy et l'onboarding sont valables quelle que soit l'option — trancher A ne fait rien perdre.

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

## 5. Feuille de route — 8 paliers avec Definition of Done

Chaque étape est shippable/testable seule. « Done » = **vérifié**, pas « codé ». Playtest humain 2–4 joueurs là où marqué.

### E0 — Cadrage & art bible
Trancher A, poser la DA et le budget technique avant de produire.
- [ ] **Décision A vs B actée** et notée dans `docs/design/levels.md`
- [ ] Art bible `docs/design/level01_art_bible.md` : palette, matériaux, refs, échelle
- [ ] Budget technique chiffré : poly / draw-calls / texture pour **4 viewports à 60 fps**
- [ ] Liste priorisée des assets (terrain, cristaux, props, boss, coffres)

### E1 — Meshy branché · agent texture autonome
Intégrer le MCP et prouver la boucle sur **un** asset avant d'industrialiser.
- [ ] MCP Meshy configuré, clé en **env**, **PR `.mcp.json` isolée** mergée
- [ ] Un asset test **généré → téléchargé → importé → visible en jeu**, texturé
- [ ] `assets_manifest.yaml` en place (prompt + task-id + licence par asset)
- [ ] LFS vérifié ; **licence commerciale Meshy confirmée**

### E2 — Blockout open-world de la grande caverne
Géométrie grise à la **bonne échelle** : continue, verticale, landmarks + 4–6 POI. Édition via **MCP Godot** (pas de `.tscn` à la main).
- [ ] Caverne **traversable de bout en bout** (spawn → boss), sans cul-de-sac cassé
- [ ] Verticalité réelle : ≥ 2 altitudes, un landmark visible de loin
- [ ] Navmesh + collisions OK ; **playtest 2–4 joueurs** : pas de blocage, split-screen lisible
- [ ] 4–6 POI placés avec intention (loot, combat, puzzle, respiration)

### E3 — Texturing passe 1 · terrain, lumière, brume
Matériaux PBR sol/murs/roche (Meshy retexture + trim sheets), refonte éclairage, brouillard au service de la mécanique.
- [ ] Sol/murs/roche **texturés PBR** — plus de BoxMesh gris sur le chemin critique
- [ ] Éclairage retravaillé : les cristaux **éclairent réellement** la scène
- [ ] Brouillard/portée de vue branchés sur la **mécanique signature**, réglés jouables
- [ ] Perf tenue en **4-split** (mesure avant/après, budget E0)

### E4 — Hero assets & props
Objets signature via Meshy (text-to-3d + retexture), instanciés en sous-scènes (composition).
- [ ] ≥ 3 variantes de formations cristallines + props, en `.tscn` réutilisables
- [ ] Coffres départ/reliques **retexturés**, cohérents art bible
- [ ] Boss Golem **habillé** sans casser IA (Rust) ni hitbox
- [ ] Assets tracés au manifest ; LFS OK ; scène sans erreur (MCP `get_errors`)

### E5 — Onboarding diégétique
Antichambre + 8 beats ; glyphes manette ; skippable mémorisé par device.
- [ ] Un **nouveau joueur seul** comprend bouger / tirer / combo / revive **sans aide externe**
- [ ] Le combo est **montré et ressenti** dans la 1re minute
- [ ] Join allume un cristal par manette ; le coffre lance la run proprement
- [ ] Skip fonctionnel/mémorisé ; **playtest 2–4 joueurs** confirme la clarté

### E6 — Gameplay open-world
Rencontres réparties, récompenses d'exploration, puzzle 3 cristaux à l'échelle du monde, révélation du boss mise en scène.
- [ ] Boucle complète : **explorer → combattre → puzzle → boss → victoire**
- [ ] L'exploration **récompense** (loot caché hors chemin critique)
- [ ] Révélation du boss **cadrée** par un landmark ; arène se verrouille/déverrouille
- [ ] Difficulté validée en **playtest 2–4 joueurs** (ni triviale, ni injuste avec FF)

### E7 — Polish, perf & packaging cadeau
Audio d'ambiance, post-process, réglage 4-split, chasse aux bugs, build + parcours de démo.
- [ ] Ambiance audio + post-process ; **60 fps tenus en 4-split** sur la machine cible
- [ ] Zéro erreur console, zéro asset manquant ; run complète sans crash
- [ ] **Build jouable** livré (exécutable + notes de lancement)
- [ ] Script de démo 3 min prêt ; niveau 1 **présentable tel quel**

---

## 6. Risques & garde-fous

| Risque | Garde-fou |
|---|---|
| **Perf** — le 4-split fait mal (textures + brume × 4) | Budget dès E0, mesures E3/E7, fallback renderer Mobile prévu |
| **Assets** — style Meshy incohérent | Vocabulaire de prompt figé (art bible), retexture > regénérer, manifest reproductible |
| **Licence** — droits commerciaux IA | Valider les conditions Meshy avant E1, tracer la licence par asset |
| **Scope** — open-world sans fin | 4–6 POI max au POC, DoD stricte, reste en phase 2 |
| **Repo** — conflits Godot | Édition via MCP Godot, PR isolée `.mcp.json`/`project.godot`, respect machine-split |
| **Pipeline** — casser N2–8 | La pipeline reste la source des autres niveaux ; N1 = cas showcase documenté |

---

## 7. Le cadeau — script de démo 3 min

1. **Le réveil** — Start → un cristal s'allume. C'est vivant.
2. **La 1re minute qui apprend** — bouger, tirer un cristal, ramasser le feu → l'arme se transforme (signature offerte d'entrée).
3. **L'obscurité** — la lumière baisse, les cristaux deviennent des repères ; la caverne texturée respire.
4. **L'exploration** — grimper vers un landmark, trouver une relique planquée, résoudre le puzzle.
5. **Le boss** — le Golem se révèle, cadré par la caverne ; coop + FF + revive servent.
6. **La remise** — « C'est le niveau 1. Joyeux cadeau. »

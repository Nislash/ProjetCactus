# CLAUDE.md — ProjetCactus

Ce fichier est lu automatiquement par Claude Code à chaque session dans ce repo. Il contient le contrat de dev, les conventions et le contexte projet. Maintiens-le à jour : c'est la source de vérité quand on bosse à plusieurs machines en parallèle.

## Vision produit

FPS roguelike/puzzle coop local 1-4 joueurs en split-screen, manettes USB uniquement. 8 niveaux à terme, chacun avec un thème + une mécanique signature + un boss. Un puzzle méta réparti sur les 8 niveaux débloque une fin spéciale.

Pure roguelike : rien ne persiste entre runs. Chaque run démarre par l'ouverture d'un coffre qui tire au sort la classe + l'arme de départ. 4 classes × 5 écoles de magie = 20 combinaisons arme×parchemin. **Les combos sont la signature du jeu** : un pistolet + un parchemin de feu doit *devenir visuellement et mécaniquement* un pistolet boule de feu (animation modifiée, projectile différent, brûlure infligée).

## Stack

- **Godot 4.6 stable**, renderer `Forward+` (fallback `Mobile` si perf 4-split insuffisante)
- **GDScript** par défaut
- **Rust via [gdext](https://github.com/godot-rust/gdext)** pour les hotspots : moteur de combos, IA boss, proc-gen (phase 2)
- **Godot MCP : [`tomyud1/godot-mcp`](https://github.com/tomyud1/godot-mcp)** v0.5.0+ — 42 tools (édition scènes/scripts, debug, visualization). Plugin embarqué dans `godot/addons/`, serveur Node.js via `.mcp.json` du repo
- **Git LFS** sur tous les binaires (modèles, textures, audio, fonts)
- Multijoueur **local uniquement**, mais architecture compatible online (state sérialisable, pas de globals sales)

## Comment lancer le projet

```bash
# 1. Cloner et installer LFS
git clone <repo>
cd ProjetCactus
git lfs install
git lfs pull

# 2. Compiler la lib Rust
cd rust && cargo build --release && cd ..

# 3. Ouvrir Godot
godot --editor godot/project.godot

# 4. F5 pour lancer
```

## Conventions de code

### GDScript
- `snake_case` pour variables/fonctions, `PascalCase` pour classes et noms de scènes
- `class_name` systématique sur les scripts attachés à des scènes
- Typage statique partout : `var foo: int = 0`, `func bar(x: float) -> Vector3:`
- Signaux : `signal player_died(player_id: int)` — toujours typés
- Pas de `get_node()` magique : utiliser `@onready var x: NodeType = $Path` ou `@export`
- Pas d'`Autoload` pour stocker de l'état muable global hors `GameState`, `RunState`, `InputRouter`, `PlayerManager`

### Rust (gdext)
- Suivre les conventions [gdext](https://godot-rust.github.io/book/)
- `#[derive(GodotClass)]` + `#[class(init, base=Node)]`
- Pas de `unsafe` sauf besoin justifié documenté
- Tests Rust dans `rust/tests/` pour la logique pure ; smoke tests Godot côté GDScript

### Scènes Godot
- Une scène = un fichier, un propriétaire de feature
- Préférer **composition** (sub-scènes instanciées) à l'héritage de scènes
- Resources `.tres` : data uniquement, jamais de logique
- Données de gameplay (armes, sorts, classes, combos, ennemis) : **toujours via `.tres`**, jamais hardcodées

### Resources data
- `ClassData.tres` : nom, stats base, slots autorisés, abilités passives, sorts de classe
- `WeaponData.tres` : damage_base, fire_rate, projectile_scene, animation_set, slots_compatibles
- `SpellData.tres` : element, damage_modifier, status_effects, vfx_overlay, animation_override
- `ComboData.tres` : référence (WeaponData, SpellData), surcharges (projectile, vfx, anim, status)
- `EnemyData.tres` : HP, damage, vitesse, IA tree, drops

## Système d'input (critique)

Manettes USB uniquement (Xbox / PS / générique XInput). 1 à 4 joueurs. Le lobby d'attribution :
1. À l'écran lobby, chaque manette appuie sur `Start` pour rejoindre
2. Le `PlayerManager` (autoload) assigne un `player_id` (0-3) et un `device_id` (Godot `device` int)
3. Toutes les actions du joueur N passent par `InputRouter.get_action(N, "shoot")` qui filtre par device

**Ne jamais** utiliser `Input.is_action_pressed("shoot")` directement dans un script de joueur — toujours passer par `InputRouter`. Sinon le joueur 1 tirerait pour tout le monde.

## Split-screen

Implémentation via `SubViewportContainer` × N + `SubViewport` × N. Le `SplitScreenManager` adapte la grille selon le nombre de joueurs actifs :
- 1 joueur : 1 viewport plein écran
- 2 joueurs : split horizontal (haut/bas) ou vertical selon ratio écran
- 3-4 joueurs : 4 quadrants (viewport vide ou cachant le HUD si 3 joueurs)

Le HUD de chaque joueur vit **dans son `SubViewport`** pour suivre son champ de vue. Aucun HUD global hors écran lobby/coffre/fin.

## Friendly fire & revive

- **FF actif** : balles et sorts blessent les alliés. Pas d'option pour désactiver.
- **Down + revive** : à 0 HP, le joueur tombe au sol (état `DOWNED`), peut ramper lentement, ne peut plus tirer. Un allié maintient `Interact` pendant 3 secondes pour le relever (50% HP restauré). Si tous les joueurs sont down simultanément → **game over** du run.

## Roguelike rules

- Aucune persistance entre runs (aucune monnaie méta, aucun unlock permanent)
- Mort du dernier joueur up = run terminé, retour menu principal
- Démarrage de run : écran coffre, animation d'ouverture, draws aléatoires (classe + arme), affichage du loadout, validation
- XP gagnée en tuant des ennemis → niveau du perso monte → choix de boon (à designer)
- Loot : armes/parchemins/objets droppés par ennemis et coffres au sol
- 8 niveaux à terme, **POC = niveau 1 uniquement fait main** (proc-gen en phase 2)

## Système de combos arme×parchemin (signature du jeu)

C'est la mécanique de différenciation. Implémentation :

1. **Data** :
   - `WeaponData.tres` (B) déclare `compatible_spell_slots: Array[bool]` (5 slots = 5 écoles)
   - `SpellData.tres` (B) déclare `element`, `damage_modifier`, `status_effects`, `vfx_overlay`, `animation_override`
2. **Resolver Rust** (`rust/src/combo_engine.rs`, A) :
   - Input : `(WeaponData, SpellData)`
   - Output : `ComboInstance` runtime contenant projectile modifié, override anim, override SFX, modificateurs gameplay (range, AoE, ricochet, brûlure, gel…)
3. **Règle critique** : le **gameplay et l'animation doivent se ressentir**, pas juste une recoloration. Cf `docs/design/combos_matrix.md`.

Matrice POC (4 combos) : ex. `Pistolet × Feu = Pistolet Boule de Feu` (brûlure DoT), `Pistolet × Glace = Pistolet Givre` (slow), `Shotgun × Foudre = Décharge en chaîne`, `Shotgun × Poison = Spray toxique AoE`.

## Git workflow

- Branche par défaut : `main` (protégée — pas de push direct)
- Toute feature : `feature/<machine-letter>-<short-name>` (ex : `feature/A-input-router`, `feature/B-level01-blockout`)
- PR review mutuelle obligatoire (l'autre machine review)
- **Pas de force push** sur `main`, jamais. Sur sa propre branche, OK avec `--force-with-lease`
- Commits petits et thématiques, messages impératifs en français OK
- `git pull --rebase` toujours avant de coder
- Conflits .tscn : on **ne merge jamais à l'aveugle**, on ouvre Godot et on vérifie la scène fonctionne

## Git LFS

Activé sur : `*.png *.jpg *.tga *.exr *.hdr *.blend *.fbx *.gltf *.glb *.wav *.ogg *.mp3 *.ttf *.otf`. Voir `.gitattributes`. Installer via `git lfs install` une fois par machine après clone.

## Répartition des machines

- **Machine A — Engine/Systems** : input, split-screen, contrôleur joueur, combat, status effects, XP/drops, coffre, HUD, autoloads, Rust `combo_engine` et `boss_ai`
- **Machine B — Content/World** : niveau POC, ennemis, scènes weapons/spells/combos visuelles, boss scène/anim, VFX, audio, assets, `.tres` data, docs design

Détail des dossiers possédés par chaque machine : voir `docs/workflow/machine_split.md`.

### Zones partagées (PR isolées obligatoires)
- `project.godot`, `default_env.tres`
- `CLAUDE.md`, `README.md`
- `.gitattributes`, `.gitignore`
- `docs/tech/`

### Règles anti-conflit Godot critiques
- Une scène = un owner. Si Machine B touche `level_01_poc.tscn`, Machine A ne le touche pas pendant cette feature.
- `project.godot` modifié → **PR isolée**, fast review.
- Input map édité **uniquement via** `docs/tech/input_system.md` + commit dédié.
- Resources `.tres` : un `.tres` = un propriétaire principal par feature. Préférer plusieurs fichiers (`weapon_pistol.tres`, `weapon_shotgun.tres`) à un monolithique `weapons.tres`.
- Toujours `git pull --rebase` avant de coder, jamais de merge commits sur feature branches.

## Anti-patterns interdits

- État muable global hors `autoload/` autorisés
- `Input.is_action_pressed` direct (passer par `InputRouter`)
- `get_node("../../foo")` avec chemins fragiles
- Logique de gameplay dans des `.tres`
- Hardcoder des stats d'armes/sorts/classes dans des scripts
- Modifier `project.godot` dans une PR qui touche autre chose
- Toucher un fichier appartenant à l'autre machine sans coordination
- Commiter des binaires hors LFS

## Tests

- Logique pure Rust : tests Rust standard (`cargo test`)
- Logique GDScript : [GUT](https://github.com/bitwes/Gut) dans `godot/tests/`
- Playtests 2-4 joueurs réels obligatoires à chaque fin de milestone

## Outils de suivi

- GitHub Issues + GitHub Projects (board Kanban : Backlog / In Progress / Review / Done)
- Labels : `engine`, `content`, `bug`, `polish`, `tech-debt`, `blocked`, `M0`/`M1`/`M2`/`M3`/`M4`
- Une issue = une feature shippable. Sous-tâches = checklist markdown dans le corps de l'issue.

## Docs vivantes (à lire avant de coder selon le sujet)

- `docs/design/classes.md` — 4 classes, stats, abilités
- `docs/design/magic_schools.md` — 5 écoles, effets élémentaires
- `docs/design/combos_matrix.md` — les 20 combos arme×parchemin
- `docs/design/relics.yaml` — pool de 50 artefacts/reliques (source de vérité à convertir en `.tres`)
- `docs/design/puzzle_meta.md` — énigme cross-8-niveaux
- `docs/design/levels.md` — 8 niveaux : thèmes, mécaniques signature, boss
- `docs/tech/input_system.md` — mapping manettes, lobby attribution
- `docs/tech/split_screen.md` — SubViewport layout adaptatif
- `docs/tech/rust_gdext_setup.md` — toolchain Rust, build, debug
- `docs/tech/lfs_setup.md` — initialisation et maintenance LFS
- `docs/workflow/git_workflow.md` — branches, PR, conflits .tscn
- `docs/workflow/machine_split.md` — répartition fichiers Machine A / B

## Plan en milestones (POC, 8-10 semaines)

- **M0 (S1)** — Bootstrap : repo, MCP Godot, crate Rust, CI, board GitHub
- **M1 (S2-3)** — Foundation : A=split-screen+input+player ; B=level01+1 classe+1 arme+1 sort+1 combo+2 ennemis
- **M2 (S4-5)** — Combat slice : A=damage+status+revive+XP+coffre ; B=+1 classe+1 arme+1 sort+3 combos+1 ennemi
- **M3 (S6-8)** — Boss : A=IA boss Rust ; B=asset boss+anim+audio+balance+playtest
- **M4 (S9-10)** — Vertical slice review : builds, playtests, GO/NO-GO phase 2

Post-POC : proc-gen niveau 1, puis niveaux 2-8 (thème + mécanique signature + fragment puzzle méta + boss), puzzle méta + fin spéciale, polish, online optionnel.

## Pour Claude (instructions agent)

- **Avant toute modif**, lire `CLAUDE.md` + le ou les docs `docs/` concernés
- **Pour toute édition `.tscn` ou script attaché à une scène : passer par les tools du MCP `tomyud1/godot-mcp`** (file/scene/script/project tools). Édition texte brute de `.tscn` interdite sauf cas exceptionnel justifié.
- **Avant un refactor** (renommage script, déplacement nœud), utiliser le tool `find usages` pour vérifier l'impact sur les fichiers de l'autre machine
- **Vérifier le propriétaire** du dossier ciblé (Machine A vs B) avant d'éditer (cf `docs/workflow/machine_split.md`)
- Si la modif déborde sur la **zone partagée** (`project.godot`, autoloads root, `.gitattributes`), faire une **PR isolée**
- Toujours **typer le GDScript** et utiliser `.tres` pour la data
- Préférer **composer** des scènes plutôt qu'hériter
- **Tester manuellement** avant de marquer une feature complète (couch coop = test humain obligatoire)

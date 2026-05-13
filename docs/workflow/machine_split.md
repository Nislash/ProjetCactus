# Répartition Machine A / Machine B

**Principe** : par couche (Engine/Systems vs Content/World) avec suivi par feature dans GitHub Projects. Chaque feature = 1 issue, 1 feature branch, 1 PR.

## Machine A — Engine / Systems

**Dossiers possédés (exclusifs)** :
- `godot/scripts/core/` — input router, split-screen manager, player manager
- `godot/scripts/combat/` — damage system, status effects, hitscan vs projectile
- `godot/scripts/progression/` — XP, drops, level-up
- `godot/scripts/debug/`
- `godot/scenes/characters/player/` — Player.tscn, contrôleur
- `godot/scenes/ui/hud/`
- `godot/scenes/ui/lobby/`
- `godot/scenes/ui/chest/`
- `godot/scenes/boot/` — splash, menu principal
- `godot/scenes/run/` — orchestrateur de run
- `godot/autoload/` — GameState, RunState, InputRouter, PlayerManager
- `rust/src/combo_engine.rs`
- `rust/src/boss_ai/` (post M2)
- `rust/src/procgen/` (post POC)

## Machine B — Content / World

**Dossiers possédés (exclusifs)** :
- `godot/scenes/levels/` — niveaux POC et futurs
- `godot/scenes/characters/enemies/` — scènes ennemis + IA standard en GDScript (boss IA en Rust = Machine A)
- `godot/scenes/weapons/` — scènes visuelles armes + animations + projectile bases
- `godot/scenes/spells/` — scènes VFX parchemins
- `godot/scenes/combos/` — scènes overrides visuels combos (peuvent ré-utiliser scenes weapons/spells)
- `godot/scenes/boss/` — scènes, anims, hitboxes boss (l'IA Rust est plug-in depuis A)
- `godot/scenes/vfx/`
- `godot/assets/` — tous les binaires (modèles, textures, audio)
- `godot/resources/` — tous les `.tres` (ClassData, WeaponData, SpellData, ComboData, EnemyData, BossData)
- `docs/design/`

## Zones partagées (PR isolées obligatoires)

Quand on touche un fichier ici, on fait une **PR dédiée** qui ne touche rien d'autre, fast review :

- `godot/project.godot`
- `godot/default_env.tres`
- `CLAUDE.md`, `README.md`
- `.gitattributes`, `.gitignore`
- `.mcp.json`
- `docs/tech/` (l'autre machine peut review et compléter)
- `docs/workflow/`

## Règles anti-conflit

1. **Une scène = un owner pendant une feature**. Pas de modif croisée d'une `.tscn` en parallèle.
2. **Resources `.tres`** : un fichier par entité (`weapon_pistol.tres`, `weapon_shotgun.tres`...). Jamais de fichier monolithique `weapons.tres`.
3. **Input map** dans `project.godot` : modifié exclusivement via `docs/tech/input_system.md` + commit dédié.
4. **Autoloads** : déclarés dans `project.godot`, owned par Machine A.
5. Toujours `git pull --rebase` avant de coder ; jamais de merge commits sur feature branches.

## Communication entre machines

- Issue GitHub par feature, assigner explicitement Machine A ou B
- PR review obligatoire **avant merge** (l'autre machine review)
- Discord / chat pour signaler "je touche XXX, je libère dans 30 min" si besoin urgent

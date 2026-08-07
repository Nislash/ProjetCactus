# ProjetCactus

FPS roguelike / puzzle coop local 1-4 joueurs en split-screen, manettes USB uniquement. Godot 4.6 + Rust (gdext).

> **Logiciel propriétaire — tous droits réservés.** © 2026 oshovibe & StanislasSC.
> Ce dépôt n'est ni libre ni open source. Aucune licence n'est accordée du fait de sa visibilité :
> ni copie, ni distribution, ni modification, ni usage commercial sans autorisation écrite des deux
> titulaires. Voir [`LICENSE`](./LICENSE) et [`NOTICE`](./NOTICE) (composants tiers).

## Pitch

- 4 classes × 5 écoles de magie = 20 combinaisons arme×parchemin uniques (signature du jeu)
- Run pur roguelike démarré par un coffre qui tire au sort classe + arme
- 8 niveaux à terme, chacun thème + mécanique signature + boss
- Puzzle méta réparti sur les 8 niveaux → fin spéciale
- Couch coop : friendly fire actif, down/revive, HUD complet par viewport

## Stack

- **Godot 4.6** (renderer Forward+) — GDScript par défaut
- **Rust via [gdext](https://github.com/godot-rust/gdext)** sur les hotspots : moteur de combos, IA boss, proc-gen
- **MCP [`tomyud1/godot-mcp`](https://github.com/tomyud1/godot-mcp)** pour piloter l'éditeur Godot via Claude
- **Git LFS** pour binaires (modèles, textures, audio)

## Setup local

```bash
git clone <repo>
cd ProjetCactus
git lfs install && git lfs pull

cd rust && cargo build --release && cd ..

godot --editor godot/project.godot
```

Puis F5 dans Godot.

## Documentation

- [`CLAUDE.md`](./CLAUDE.md) — contrat de dev (conventions, anti-patterns, workflow)
- [`docs/design/`](./docs/design/) — classes, écoles de magie, combos, niveaux, puzzle méta
- [`docs/tech/`](./docs/tech/) — input system, split-screen, Rust gdext, LFS
- [`docs/workflow/`](./docs/workflow/) — git workflow, répartition des machines
- [`LICENSE`](./LICENSE) — licence propriétaire, titularité, régime des contributions
- [`NOTICE`](./NOTICE) — composants tiers et leurs licences (Godot MIT, gdext MPL-2.0, assets Meshy)

## Roadmap POC (~8-10 semaines)

| Milestone | Contenu |
|---|---|
| M0 (S1) | Bootstrap repo + MCP + Rust + CI |
| M1 (S2-3) | Foundation : split-screen + 1 classe + 1 arme + 1 sort + 1 combo |
| M2 (S4-5) | Combat slice : dégâts + statut + revive + 2 classes + 4 combos |
| M3 (S6-8) | Boss en Rust + assets + équilibrage |
| M4 (S9-10) | Builds, playtests, décision phase 2 (proc-gen + 8 niveaux) |

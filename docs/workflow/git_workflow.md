# Git workflow

## Branche principale

- `main` — protégée. Aucun push direct.
- Toute modification passe par une **feature branch** + PR.

## Nommage des feature branches

`feature/<machine-letter>-<short-name>`

Exemples :
- `feature/A-input-router`
- `feature/A-split-screen-manager`
- `feature/B-level01-blockout`
- `feature/B-pistol-fire-combo`

Pour les hotfixes : `fix/<short-name>`. Pour les chores : `chore/<short-name>`.

## Cycle de feature

1. `git pull --rebase origin main`
2. `git checkout -b feature/A-<name>`
3. Coder, commit fréquent, messages impératifs
4. `git push -u origin feature/A-<name>`
5. Ouvrir PR vers `main`, l'autre machine review
6. CI verte → squash & merge

## Commits

- Messages en français OK, impératif présent
- Petits commits thématiques
- Pas de "wip" final dans `main` (squash si nécessaire)
- Pas de force push sur `main`. Sur feature branch : `--force-with-lease` autorisé

## Conflits .tscn

Les fichiers `.tscn` sont texte mais leur structure (NodePaths, IDs, refs) rend le merge à 3 voies fragile.

Règle :
- **Une scène = un owner pendant une feature**. Si Machine B travaille sur `level_01_poc.tscn`, Machine A ne le touche pas tant que la PR n'est pas mergée.
- En cas de conflit : ouvrir Godot, recharger la scène, vérifier visuellement qu'elle fonctionne. Ne jamais merger à l'aveugle.
- Si vraiment merge complexe : préférer rebaser et refaire les modifs proprement plutôt qu'un merge sale.

## Conflits zones partagées

Les fichiers suivants demandent des **PR isolées** (rien d'autre dans la même PR) :
- `project.godot`
- `CLAUDE.md`, `README.md`
- `.gitattributes`, `.gitignore`
- `.mcp.json`
- Autoloads root

## Protection branch (à configurer sur GitHub)

- `main` : require PR, require 1 review, require CI green, no force push, no deletion
- Squash merge par défaut

## Tags / releases

- Tag `vX.Y.Z` aux fins de milestones (M1, M2, M3, POC final)
- Release notes générées depuis les PR mergées

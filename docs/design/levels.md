# Niveaux (8 à terme)

**Statut : STUB — 1 niveau fait main au POC (`level_01_poc`), proc-gen + 7 niveaux restants en phase 2.** Owner : Machine B.

> Voir aussi : [`levels/topology.drawio`](levels/topology.drawio) — schémas topologiques des 8 niveaux avec verticalité, puzzle, fragment méta. Ouvrir dans [app.diagrams.net](https://app.diagrams.net) ou l'extension VS Code "Draw.io Integration".

## Règle

Chaque niveau a :
- **Un thème visuel** unique (biome, palette, ambiance audio)
- **Une mécanique signature** unique qui modifie le gameplay
- **Un boss** unique avec ses propres patterns
- **Un fragment** du puzzle méta (cf `puzzle_meta.md`)
- **Des ennemis** propres (peut partager ennemis communs entre 2 niveaux)

## Pistes (à valider design session)

| # | Thème | Mécanique signature | Boss (pitch) | Fragment puzzle |
|---|---|---|---|---|
| 1 | Caverne crystalline | Lumière limitée, cristaux qui explosent | Golem de cristal | ? |
| 2 | Marais toxique | Brouillard réduit visibilité, slow dans l'eau | Sangsue géante | ? |
| 3 | Temple en gravité réduite | Sauts longs, balles courbées | Idole flottante | ? |
| 4 | Forge en fusion | Lave montante (timer), forge des armes temporaires | Forgeron infernal | ? |
| 5 | Bibliothèque hantée | Sorts ennemis amplifiés, parchemins en chute | Liche bibliothécaire | ? |
| 6 | Champ de bataille frozen | Gel progressif des joueurs immobiles | Roi de glace | ? |
| 7 | Labyrinthe miroirs | Reflet ennemi, faux passages | Doppelganger | ? |
| 8 | Vide cosmique | Pas de gravité, atmosphère limitée (timer) | ??? (boss final) | Fragment final |

## POC — Niveau 1 (`level_01_poc`)

- Thème : caverne crystalline simplifiée (block-out en M1)
- Mécanique : aucune signature au POC, juste un niveau jouable et clair
- Boss : version POC du Golem de cristal (M3)
- ~5 salles + couloir + arène boss
- 3 ennemis distincts (mêlée, ranged, charger)

Voir `scenes/levels/level_01_poc/`.

## Décision actée — Niveau 1 « Caverne Cristalline » = **option A**, fait main (cas à part)

**Décision (E0, issue #94) : option A — une grande caverne continue faite main**, en vitrine, plutôt que
l'option B (niveau généré par la pipeline). Conséquences, à connaître avant de toucher au niveau 1 :

- **Le niveau 1 sort de `tools/dungeon_pipeline/`.** La pipeline drawio → JSON → A* → GridMap **reste la
  source de vérité des niveaux 2 à 8** et ne doit pas être modifiée pour les besoins du niveau 1.
- `godot/data/levels/level_1.tres` (sortie pipeline) n'est donc **plus le niveau 1 livré** : il reste comme
  référence/test de la pipeline. Le niveau 1 livré est une scène faite main.
- « Open world » était un abus de langage : ce n'est **pas** un monde ouvert, mais **un volume unique fermé**
  — voûte 10-15 m, sol vallonné praticable partout, aucune sortie, **aucune chute possible**, avec des trous
  de voûte ouvrant sur le ciel.
- Le blockout cloisonné existant (`scenes/levels/level_01_poc/`) reste la référence jouable **jusqu'à la
  bascule** sur la nouvelle scène caverne ; on ne le casse pas en cours de route.

Détail complet : [`level01_openworld_plan.md`](level01_openworld_plan.md) (roadmap E0→E7) et
[`level01_art_bible.md`](level01_art_bible.md) (palette, matériaux, budget, brief topographique).

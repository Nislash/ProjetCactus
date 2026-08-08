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


---

## Décision de portée (2026-08-09)

**Deux niveaux, pas huit.** Le lobby proposait dix-sept entrées : les huit sorties de la pipeline
générative et les huit blockouts archivés. Aucune n'était à la qualité du niveau 1, et une liste où
quinze choix sur dix-sept déçoivent n'est pas un choix — c'est un piège. Elles restent sur disque,
elles ne sont plus proposées.

Le bouton « Tutoriel » disparaît avec elles. L'arène de test qu'il lançait devient le **niveau 2**,
refaite dans son propre biome. On n'apprend plus à jouer dans un décor de test : on apprend dans
l'Antichambre de Givre, qui ouvre le niveau 1.

## Niveau 2 — « La Forge »

Un puits volcanique : trois anneaux concentriques qui descendent vers un lac de lave. **156 × 156 m**,
contre 310 × 210 pour la Caverne — le niveau 1 est une exploration, celui-ci est une arène. On voit le
gouffre depuis la crête et on sait tout de suite où l'on va.

### Ce qui l'oppose au niveau 1, point par point

| | Caverne Cristalline | La Forge |
|---|---|---|
| Lecture | horizontale, on traverse | **verticale**, on descend |
| Nappe | lac gelé, praticable | **lac de lave**, mortel |
| Lumière | par le haut, deux puits de jour | **par le bas**, la lave est la seule source |
| Palette | bleu délavé, saturation 0,88 | ambre saturé, saturation 1,18 |
| Progression | un puzzle à résoudre | une descente à survivre |

### Le vrai problème de design du biome

Au niveau 1, l'ambre `#f2b45c` est **réservé** : il veut dire « esquive maintenant », et rien d'autre
ne l'utilise. Dans la Forge, la salle entière est ambre — **la couleur ne peut plus rien signaler**.

C'est donc le **mouvement** qui alerte : la lave qui monte, les braises qui s'emballent, les coulées
qui s'ouvrent. Les telegraphs du boss devront battre plutôt que rougir. C'est la contrainte
structurante du niveau, et elle vaut d'être retenue pour les biomes suivants : *une grammaire
chromatique ne survit pas à un changement de biome, une grammaire de mouvement oui*.

### Ce qui est fait, ce qui reste

**Fait** : terrain (`tools/build_forge_terrain.gd`), matériaux basalte et lave, environnement à
lumière basse, éclairage par le bassin (`forge_lighting.gd`), spawns, ennemis par palier, boss et sa
zone d'éveil (`forge_gameplay.gd`). Six tests, dont deux qui vérifient les promesses géométriques du
biome — que ça descende, et que la lumière vienne d'en bas.

**Reste** : la lave montante branchée sur les phases du boss (`mechanic_rising_lava.gd` existe et
n'est pas encore câblé), les props de basalte, l'audio, et un boss propre au niveau — pour l'instant
c'est le Golem de la Caverne.

### À ciel ouvert (2026-08-09)

La Forge n'est plus une cavité : c'est un **cirque**, bordé de falaises, sous une **lune rouge**.

Le générateur referme toujours son volume par une voûte. Il sait maintenant faire l'inverse
(`open_sky`) : aucune voûte n'est construite, et hors des chambres c'est le **sol qui monte** de
`open_sky_rim_height`. Même masque, donc même silhouette jouable — seul change ce qui la borne. La
hauteur libre continue d'être calculée, parce qu'elle définit la zone jouable et sert aux contrôles
d'étanchéité ; elle ne matérialise simplement plus rien.

**Deux lumières qui s'opposent.** La lave, par en dessous, chaude et mouvante. La lune, rasante et
froide dans son rouge, qui ne fait presque pas de lumière mais fait les **ombres** — c'est elle qui
découpe le château sur le ciel. Elles ne se mélangent jamais : une surface est soit orange et vivante,
soit rouge sombre et figée. C'est ce qui rend le puzzle lisible.

### Le puzzle : les miroirs de lune

**Le verbe change.** Le niveau 1 demande de *rassembler* — quatre éclats, un mot. Celui-ci demande
d'*orienter* : trois miroirs de basalte à faire pivoter pour conduire la lumière de la lune jusqu'au
sceau du château, qui fige et cède.

Dans un monde de chaleur, c'est **le froid qui ouvre**. La lune devient un acteur, pas un décor.

**Ça se comprend sans un mot** : le rayon est visible sur toute sa longueur et s'arrête là où il bute.
On voit donc aussi *pourquoi* il n'arrive pas. Rien à deviner, seulement une trajectoire à lire — et
personne n'a besoin qu'on lui explique comment se comporte un miroir.

**L'échec ne coûte rien.** Un rayon qui rate ne casse rien. Dans un roguelike où rien ne persiste, une
énigme punitive serait une double peine.

#### Deux corrections imposées par la mesure

Le test résout le puzzle **par force brute** — toutes les combinaisons de crans — parce qu'un puzzle
de réflexion mal placé n'échoue pas bruyamment : il reste insoluble, et le joueur tourne des miroirs
vingt minutes en croyant qu'il n'a pas compris. Il a trouvé deux fautes.

1. **Douze crans ne suffisaient pas.** Un rayon réfléchi tourne *deux fois plus vite* que la normale
   du miroir : 30° de cran font 60° de balayage, et la cible passait systématiquement entre deux
   positions. Vingt-quatre crans.
2. **La lune rasante rendait le puzzle impossible.** Un miroir vertical conserve l'inclinaison du
   rayon incident : venant de 20° au-dessus de l'horizon, il repartait vers le bas et plongeait dans
   le sol vingt mètres plus loin. Les miroirs sont donc **taillés pour redresser** — ils renvoient à
   l'horizontale. Le joueur ne raisonne qu'en azimut, ce qui est exactement ce qu'on veut à la
   manette, où viser en site est pénible.

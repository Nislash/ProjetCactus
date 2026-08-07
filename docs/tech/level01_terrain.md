# ADR — Technique du terrain vallonné (niveau 1)

> **Statut : décidé, 2026-08-08.** Tâche E2 #9. Concerne uniquement le niveau 1 « Caverne Cristalline »,
> qui est un cas fait main (cf `docs/design/levels.md`) ; les niveaux 2-8 restent sur
> `tools/dungeon_pipeline/`.
> Spec spatiale à matérialiser : [`docs/design/level01_topography.md`](../design/level01_topography.md).

## Contexte

Il faut matérialiser dans Godot 4.6 un **volume clos** : sol vallonné praticable partout (pentes douces,
bosses, cuvettes bordées), voûte à 10-15 m percée de deux puits de ciel, parois qui referment le tout.
Contraintes qui pèsent sur le choix :

1. **Itérabilité.** Une review créative post-blockout est planifiée (tâche #15) : la topographie *va*
   changer après playtest. Ce qui coûte cher à modifier sera modifié à contrecœur, donc mal.
2. **Édition via MCP Godot.** `CLAUDE.md` interdit l'édition `.tscn` à la main.
3. **Navmesh sur relief.** Le navmesh doit se régénérer sur la géométrie sans intervention manuelle.
4. **Budget repo.** Un mesh sculpté de 93 × 54 m en LFS, réimporté à chaque itération, gonfle
   l'historique — on vient déjà de se prendre 185 Mo sur trois props.
5. **Anti-chute prouvable.** La contrainte « aucune chute possible » doit être *vérifiable
   automatiquement*, pas constatée à l'œil.

## Options

| Option | Verdict |
|---|---|
| **(a) Mesh sculpté externe** (Blender) + collision trimesh | ❌ Itération hors moteur, binaire lourd en LFS à chaque passe, incompatible avec « édition via MCP ». Le meilleur contrôle artistique, au pire coût d'itération. |
| **(b) GridMap** | ❌ Rejeté d'emblée : pas de pentes douces. C'est la raison même pour laquelle le niveau 1 sort de la pipeline. |
| **(c) CSG puis bake** | ❌ Coûteux en runtime, difficile à contrôler finement, et le bake casse l'itérabilité qu'on cherche. |
| **(d) Double champ de hauteurs généré par script** | ✅ **Retenu.** |

## Décision

**Deux champs de hauteurs (sol + voûte) générés par script depuis une `Resource` de données, plus une
ceinture de parois qui referme le périmètre.**

```
       ╭──────────── voûte (heightfield #2, trouée visuellement) ────────────╮
       │   ○ P1                                    ○ P2                      │
  parois                                                                 parois
       │                                                                     │
       ╰────────── sol (heightfield #1) : plateaux · rampes · cuvettes ───────╯
```

- **Le sol** : `CavernHeightfieldSpec` → grille de hauteurs → `ArrayMesh` (visuel) +
  `HeightMapShape3D` (collision). Le heightfield est *exactement* le bon outil : le sol de la topo est
  une fonction de (X, Z), sans surplomb.
- **La voûte** : un second heightfield, inversé. Son **maillage visuel est troué** aux puits P1/P2,
  mais sa **collision reste pleine** — on voit le ciel, on ne sort jamais. La contrainte dure la plus
  délicate du plan tombe ainsi par construction, sans collision invisible à poser à la main.
- **Les parois** : une jupe extrudée entre le contour du sol et celui de la voûte, générée en même
  temps. Le périmètre est donc scellé par construction, pas par vigilance.

### Le format de données

La spec de Fable parle en **plateaux, rampes et cuvettes** — le générateur parle la même langue :

| Primitive | Champs | Correspond à |
|---|---|---|
| `CavernPlateau` | centre, demi-étendue (rect ou ellipse), altitude, adoucissement | une zone d'altitude (Z1 corniche, Z3 lac, terrasses du nid) |
| `CavernRamp` | départ→arrivée, altitudes, largeur, adoucissement | les liaisons pentues (rampes de Z2, montée du seuil, rampes d'arène) |
| `CavernBasin` | centre, rayons, profondeur, **hauteur de margelle** | les cuvettes bordées (C1, le lac, le bol d'arène) |

Les primitives s'appliquent dans l'ordre, chacune mélangée par son adoucissement. La margelle des
cuvettes n'est pas décorative : c'est **le mécanisme qui rend la chute impossible**, et il est dans la
donnée, pas dans la main du level designer.

Un bruit de faible amplitude (graine fixe) ajoute les ondulations demandées sans jamais créer de pente
supérieure au plafond configuré.

### Ce que ça donne concrètement

- **Itérer** = éditer un `.tres` (quelques dizaines de lignes de données) et relancer le générateur.
  La review créative #15 se traduit en patch de données, pas en resculptage.
- **Le repo** ne stocke que la donnée : ni mesh ni heightmap binaire. Zéro LFS pour le terrain.
- **Vérifier** devient possible : le champ de hauteurs est un tableau de flottants, donc « aucune pente
  > 25° » et « aucun creux non bordé » sont des assertions sur des nombres (tâche #11).
- **Le navmesh** se régénère sur un `ArrayMesh` standard, sans cas particulier (tâche #12).

## Règles d'authoring (découvertes en validant le prototype)

Trois pièges se sont révélés en écrivant les tests. Ils ne sont pas théoriques : le premier était un
**bug**, les deux autres produisent des falaises que rien ne signale à l'œil sur un blockout gris.

### 1. Dimensionner un fondu « à l'œil » sous-estime la pente de 50 %

Le fondu des primitives est un `smoothstep`, dont la pente maximale vaut **1,5 fois** la pente moyenne
(dérivée de 3x²−2x³, maximale au milieu du fondu). Une transition de 6 m sur 8 m de fondu ne fait pas
37°, elle fait **50°**.

→ Toujours dimensionner via `CavernTerrainBuilder.min_falloff_for(delta_altitude, pente_visée)`.
Jamais un nombre écrit à la main.

### 2. La crête de la margelle EST le bord de la cuvette

Première version de `_basin_offset` : l'intérieur remontait vers 0 au bord, l'extérieur démarrait à
`rim_height`. Résultat, un **saut de `rim_height` d'un échantillon à l'autre** — une falaise invisible
dans la donnée, que seul le test de pente a attrapée. Le profil correct d'un bol bordé va de `−depth`
au centre à **`+rim_height` au bord exactement**, puis redescend à l'extérieur.

→ Le rayon d'une cuvette doit couvrir `depth + rim_height`, pas seulement `depth`.

### 3. Les cuvettes s'ajoutent, les plateaux et les rampes se fondent

Plateaux et rampes appliquent un `lerp` **vers une altitude cible** : les superposer ne cumule pas
leurs pentes. Les cuvettes, elles, ajoutent un **décalage** au relief existant. Poser une cuvette sur
une rampe additionne donc les deux pentes.

→ Éloigner les cuvettes des rampes, ou budgéter la somme des deux.

### 4. Réserver de la marge de pente pour les ondulations

Le bruit de surface ajoute son propre gradient par-dessus tout le reste. Dimensionner les transitions
pile au plafond de praticabilité garantit de le dépasser une fois le bruit posé.

→ Viser **~16°** sur les transitions quand le plafond est 25°. Le prototype validé sort à 22,5° de
pente maximale avec ce réglage.

## Conséquences et limites acceptées

- **Pas de surplombs, pas d'arches, pas de tunnels superposés.** Un heightfield est une fonction de
  (X, Z). La topo de Fable n'en demande aucun — c'est une combe, pas un réseau. Si un surplomb devient
  nécessaire plus tard, il sera **ajouté comme mesh séparé** posé sur le terrain, sans remettre en
  cause le socle.
- **`HeightMapShape3D` échantillonne à 1 unité.** Le nœud de collision est mis à l'échelle de
  `cell_size` ; toute modification de `cell_size` doit rester synchronisée entre le mesh et la forme —
  c'est fait dans le builder, un seul endroit.
- **Le coût mémoire du champ** croît en 1/cell_size². À `cell_size = 1 m` sur 93 × 54 m : ~5 000
  échantillons par champ, négligeable.
- **Le grain fin du relief** (micro-relief de roche) ne vient pas de là : c'est le travail des
  matériaux et des normal maps en E3, pas de la géométrie.

## Fichiers

| Rôle | Chemin |
|---|---|
| Données (primitives, un `.tres` par niveau) | `godot/scripts/world/cavern_terrain_data.gd` |
| Générateur (mesh + collision + parois) | `godot/scripts/world/cavern_terrain_builder.gd` |
| Tests (pentes, bordures, étanchéité) | `godot/tests/test_cavern_terrain.gd` |

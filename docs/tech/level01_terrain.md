# ADR — Technique du terrain de la caverne (niveau 1)

> **Statut : décidé (2026-08-08), révisé le même jour pour la caverne ×7.**
> Tâches E2 #9 puis E2bis #38. Concerne uniquement le niveau 1, qui est un cas
> fait main (cf `docs/design/levels.md`) ; les niveaux 2-8 restent sur
> `tools/dungeon_pipeline/`.

## Contexte

Il faut matérialiser dans Godot 4.6 un **volume clos de forme organique** :
~35 000 m² jouables sur une emprise d'environ 300 × 200 m, au sol vallonné
praticable partout, voûte à 10-15 m percée d'ouvertures sur le ciel, et un lac
en son centre. Contraintes qui pèsent sur le choix :

1. **Itérabilité.** Des allers-retours créatifs sont prévus : la topographie
   *va* changer. Ce qui coûte cher à modifier sera modifié à contrecœur, donc mal.
2. **Édition via MCP Godot** — `CLAUDE.md` interdit l'édition `.tscn` à la main.
3. **Navmesh sur relief**, régénéré sans intervention manuelle.
4. **Budget dépôt** — un mesh sculpté de cette taille, réimporté à chaque passe,
   gonfle l'historique LFS.
5. **Anti-chute et étanchéité prouvables** automatiquement, pas constatées à l'œil.
6. **Forme non rectangulaire** — la contrainte qui a fait tomber la v1.

## Options

| Option | Verdict |
|---|---|
| **Mesh sculpté externe** (Blender) + collision trimesh | ❌ Itération hors moteur, binaire lourd à chaque passe, incompatible avec l'édition MCP. Meilleur contrôle artistique, pire coût d'itération. |
| **GridMap** | ❌ Pas de pentes douces. C'est la raison même pour laquelle le N1 sort de la pipeline. |
| **CSG puis bake** | ❌ Coûteux en runtime, difficile à contrôler finement, et le bake casse l'itérabilité recherchée. |
| **Champs de hauteurs générés depuis de la donnée** | ✅ **Retenu.** |

## Décision

**Deux champs de hauteurs — sol et hauteur libre — générés depuis une
`Resource`, et une silhouette définie par l'union de chambres.**

```
        roche pleine                                    roche pleine
   ═════════════════╗                                 ╔═══════════════
                    ╚═══╗   ← la voûte descend    ╔═══╝
                        ╚═══╗                 ╔═══╝
                            ╰───  caverne  ───╯
   ─────────────────────────────────────────────────────────────────
                      sol (champ de hauteurs)
```

### 1. La silhouette vient des chambres

Une `CavernChamber` est une **poche** (ellipse orientée) ou un **goulet**
(capsule entre deux points). Leur **union** dessine le volume ; partout ailleurs,
c'est de la roche pleine.

C'est ainsi que se lit un plan de caverne dessiné à la main — des salles reliées
par des couloirs — donc c'est le vocabulaire dans lequel la conception créative
peut écrire directement, sans traduction.

> **Ce qui a été abandonné :** la v1 échantillonnait une **emprise rectangulaire**
> et posait une jupe de parois sur ses 4 bords. Elle ne savait produire qu'une
> boîte. Aucun réglage n'en aurait tiré la forme des croquis.

### 2. Le volume se referme tout seul

La voûte n'est pas cotée en altitude absolue : elle vaut **`sol + hauteur libre`**,
et la hauteur libre est **multipliée par le masque des chambres**. Hors de la
silhouette, elle vaut zéro : la voûte descend au contact du sol, et il n'y a
plus d'espace où passer.

Conséquences, et c'est tout l'intérêt :

- **Plus de ceinture de parois à générer**, donc plus de jonction à surveiller.
- **L'étanchéité devient une propriété de la construction**, pas un résultat à
  vérifier après coup.
- La **contrainte « voûte à 10-15 m »** est structurelle : elle ne peut pas
  dériver quand on retouche le relief.
- La **largeur de la fermeture** (`edge_softness`) devient un paramètre de design :
  court = falaise, long = évasement.

### 3. Découpage en tuiles

Le maillage est découpé en tuiles de `chunk_size` mètres. À cette échelle, un
maillage unique serait **toujours dessiné en entier** et le frustum culling ne
servirait plus à rien. Les tuiles entièrement dans la roche pleine ne sont pas
générées du tout.

### 4. Le lac est une surface distincte

Un champ de hauteurs n'a qu'une surface par point ; un lac **est** une seconde
surface au-dessus du fond. La nappe est donc un maillage plan à part, dessiné là
où le sol passe sous son altitude **et** dans l'emprise déclarée du lac.

> L'emprise n'est pas un luxe : sans elle, la nappe se dessinait aussi au fond
> du bol de l'arène, qui se retrouvait **inondé**. Un lac occupe une cuvette
> précise, pas tous les points bas de la caverne.

### Le format de données

| Primitive | Rôle |
|---|---|
| `CavernChamber` | **où la caverne existe** — poche ou goulet, avec sa hauteur libre |
| `CavernPlateau` | une zone d'altitude |
| `CavernRamp` | une liaison pentue |
| `CavernBasin` | un creux **bordé**, avec fond plat optionnel |
| `CavernSkyOpening` | une ouverture elliptique orientée dans le maillage de voûte |
| `CavernLake` | la nappe, son altitude et son emprise |

## Règles d'authoring (apprises en construisant, pas déduites)

Chacune vient d'un défaut réel, dont plusieurs invisibles à l'œil sur un
blockout gris.

### 1. Dimensionner un fondu « à l'œil » sous-estime la pente de 50 %

Le fondu des primitives est un `smoothstep`, dont la pente **maximale** vaut
**1,5 fois** la pente moyenne. Une transition de 6 m sur 8 m de fondu ne fait pas
37°, elle fait **50°**.

→ Toujours passer par `CavernTerrainBuilder.min_falloff_for(delta, pente_visée)`.
Jamais un nombre écrit à la main.

### 2. La crête de la margelle EST le bord de la cuvette

Première version : l'intérieur remontait vers 0 au bord, l'extérieur démarrait à
`rim_height` — soit un **saut** d'un échantillon à l'autre, une falaise
invisible dans la donnée. Le profil correct va de `−depth` au centre à
**`+rim_height` au bord exactement**.

→ Le rayon d'une cuvette doit couvrir `depth + rim_height`, pas seulement `depth`.

### 3. Les cuvettes s'ajoutent, les plateaux et rampes se fondent

Plateaux et rampes appliquent un `lerp` **vers une altitude cible** : les
superposer ne cumule pas leurs pentes. Les cuvettes ajoutent un **décalage**.

→ Ne pas faire chevaucher le bourrelet d'une cuvette et le fondu d'un plateau :
constaté à 49° au bord du bol d'arène, au-delà de l'angle où le joueur glisse.
Et une rampe creusée **dans** une cuvette se cote en altitude *avant* creusement,
sinon on soustrait deux fois.

### 4. Réserver de la marge de pente pour les ondulations

Le bruit de surface ajoute son propre gradient par-dessus tout le reste.

→ Viser **~16°** sur les transitions quand le plafond est 36°.

### 5. L'influence d'une rampe est une capsule

Elle déborde au-delà de ses extrémités. Une rampe large posée pour « la descente
d'ensemble » lavait les terrasses situées 60 m plus loin.

→ Préférer le fondu d'un plateau pour un mouvement d'ensemble ; garder les
rampes pour des liaisons courtes et locales.

### 6. Un lac exige un fond PLAT

Sans `flat_bottom`, la cuvette descend en pointe : le fond n'est qu'un point et
la nappe se réduit à une flaque. Un lit plat donne aussi une glace praticable au
lieu d'un entonnoir où l'on glisse.

## Conséquences et limites acceptées

- **Pas de surplombs, pas d'arches, pas de tunnels superposés.** Un champ de
  hauteurs est une fonction de (X, Z). Si un surplomb devient nécessaire, il sera
  **ajouté comme mesh séparé** posé sur le terrain, sans remettre en cause le socle.
- **`HeightMapShape3D` échantillonne à 1 unité** : le nœud de collision est mis à
  l'échelle de `cell_size`. Toute modification doit rester synchronisée entre le
  mesh et la forme — c'est fait dans le builder, un seul endroit.
- **Le grain fin du relief** ne vient pas de la géométrie mais du matériau
  tri-planaire (cf `shaders/cavern_rock.gdshader`).
- **Les faces ont un sens.** Godot considère comme face avant l'ordre **horaire**
  vu de face. Les inverser rend la surface invisible **sans aucune erreur** : le
  sol l'a été, et on voyait le ciel à travers. Vérifié par
  `test_cavern_terrain.gd::surfaces_face_the_right_way`.

## Fichiers

| Rôle | Chemin |
|---|---|
| Silhouette | `godot/scripts/world/cavern_chamber.gd` |
| Relief | `cavern_plateau.gd`, `cavern_ramp.gd`, `cavern_basin.gd` |
| Voûte et lac | `cavern_sky_opening.gd`, `cavern_lake.gd` |
| Données | `cavern_terrain_data.gd`, `cavern_heightfield_spec.gd` |
| Générateur | `cavern_terrain_builder.gd` |
| Recalage des marqueurs | `cavern_marker_snapper.gd` |
| Layout du niveau | `godot/tools/build_cavern_terrain.gd` |
| Carte vue de dessus | `godot/tools/render_cavern_map.gd` |
| Tests | `godot/tests/test_cavern_terrain.gd`, `test_cavern_sealing.gd`, `test_cavern_navigation.gd` |

# Fiche de contraintes constructibles — grande caverne ×7

> **Pour la session ◆ Fable (tâche #39).** À lire avant de concevoir.
>
> Cette fiche existe parce que la première session créative a produit trois specs
> **géométriquement infaisables** — dont un bol d'arène de 6 m de dénivelé sur
> 10 m de rayon avec des parois « à 25° », qui en donnait 45. Les écarts sont
> retombés sur l'exécution, et il a fallu un aller-retour pour les arbitrer.
>
> Tout ce qui est listé ici est **mesuré sur le générateur réel**, pas estimé.

---

## 1. Le vocabulaire que le générateur consomme

Décris la caverne avec **ces mots-là** : il n'y a pas de traduction entre ce que
tu écris et ce qui est construit.

| Mot | Ce que ça produit | Paramètres |
|---|---|---|
| **Chambre** | une poche du volume (une salle) | centre, rayons, rotation, hauteur libre, adoucissement du bord |
| **Goulet** | un couloir entre deux points | départ, arrivée, demi-largeur, hauteur libre |
| **Plateau** | une zone d'altitude | centre, demi-étendue, altitude, fondu |
| **Rampe** | une liaison pentue | départ→arrivée, altitudes, largeur |
| **Cuvette** | un creux **bordé** | centre, rayons, profondeur, margelle, **fond plat** |
| **Ouverture** | un trou dans la voûte | centre, rayons, rotation |
| **Lac** | une nappe | altitude, **emprise**, profondeur minimale |

**La silhouette de la caverne = l'union des chambres et des goulets.** Partout
ailleurs, c'est de la roche pleine. Il n'y a rien à « fermer » : le volume se
referme tout seul aux abords des chambres.

Pour obtenir un contour irrégulier, **superpose plusieurs poches** plutôt que
d'en chercher une seule de la bonne forme. Même procédé pour les ouvertures de
voûte : deux ellipses qui se recouvrent donnent un trou non circulaire.

---

## 2. Ce qui est faisable, chiffré

### Pentes

| | Valeur | Pourquoi |
|---|---|---|
| Confort de marche | **≤ 36°** | plafond du projet ; au-delà, l'ascension devient pénible |
| Glissement | **45°** | `floor_max_angle` du personnage. **Au-delà, le joueur glisse au lieu de marcher** — c'est un mur, pas une pente |
| Transitions d'ensemble | **viser 16°** | le bruit de surface ajoute son propre gradient par-dessus |

⚠️ **Une pente ne se déduit pas de `dénivelé / distance`.** Le fondu est un
`smoothstep`, dont la pente maximale vaut **1,5 fois** la pente moyenne. Une
transition de 6 m sur 8 m fait **50°**, pas 37°.

**Distance minimale pour un dénivelé donné** (à 36°, avec la marge du bruit) :

| Dénivelé | Distance mini |
|---|---|
| 1 m | 2 m |
| 3 m | 6 m |
| 5 m | 10 m |
| 8 m | 17 m |
| 12 m | 25 m |

### Cuvettes (arènes, lits de lac, cratères)

Le dénivelé s'étale sur la portion **non plate** du rayon :

```
rayon × (1 − fond_plat)  ≥  distance mini pour (profondeur + margelle)
```

*Exemple réel :* le bol de l'arène fait 5 m de profondeur, 0,6 m de margelle,
42 % de fond plat. Il lui faut donc `10,5 / 0,58 ≈ 19 m` de rayon minimum. Il en
a 38 — confortable.

⚠️ La **margelle n'est pas décorative** : c'est elle qui rend la chute
impossible. Une cuvette à margelle nulle est refusée par les tests.

⚠️ Un **lac exige un fond plat** (≥ 0,4). Sans lui, la cuvette descend en pointe
et la nappe se réduit à une flaque.

### Hauteur libre

| | Valeur |
|---|---|
| Fourchette dure | **10 à 15 m** dans les zones jouables |
| Seuil de jouabilité | **2,5 m** — en dessous, c'est la paroi qui referme le volume |

Une chambre déclare sa hauteur libre ; elle est ensuite bornée à la fourchette.
Une salle basse voisine d'une nef haute donne une transition continue.

**Pour une compression dramatique** (le seuil avant une révélation), demande
10 m : c'est le minimum autorisé, et l'écart avec les 15 m de la salle suivante
se ressent.

### Largeurs

| | Valeur | Pourquoi |
|---|---|---|
| Chemin principal | **≥ 6 m** | 4 joueurs avec friendly fire actif ; plus étroit = bouchon mortel |
| Goulet secondaire | **≥ 3 m** | passable en file |
| Goulet dramatique | **8 m** | assez pour comprimer sans bloquer |

⚠️ **La demi-largeur d'un goulet est son rayon de capsule.** Un goulet de
demi-largeur 11 fait 22 m de large — c'est déjà une salle, plus un couloir.

### Ce qui est IMPOSSIBLE

- **Surplombs, arches, tunnels superposés.** Le sol est une fonction de (X, Z) :
  un seul niveau par point. Un pont ou une arche devra être un objet posé, pas
  du terrain.
- **Parois verticales franches.** Le volume se referme sur la largeur de
  l'adoucissement. Le plus raide reste une pente très forte, jamais un à-pic.
- **Salles superposées en hauteur.** Même raison.

---

## 3. L'état actuel, comme base de travail

Un **premier jet** est déjà construit depuis les croquis
(`godot/tools/build_cavern_terrain.gd`). Il prouve que la forme est constructible ;
il ne prétend pas être beau.

| | Mesure |
|---|---|
| Emprise | 310 × 210 m |
| Surface jouable | **41 884 m²** (×8,3 l'ancienne caverne) |
| Traversée spawn → boss | **375 m** |
| Pente max sur sol jouable | 42,6° (0,02 % au-dessus de 36°) |
| Hauteur libre jouable | 2,5 → 15,0 m |
| Nappe du lac | 1 870 m² |
| Ouvertures de voûte | 4 |
| Perf 4-split | 56 draw calls/viewport, 310 Mo VRAM |

Chambres actuelles : Salle du Boss, Grande Nef, Seuil du Boss, Salle du Lac,
Descente du Lac, Poche du Loot, Boyau du Loot, Anse Sud-Ouest, Passe Sud-Ouest.

**Carte vue de dessus** : `godot --headless --path godot --script tools/render_cavern_map.gd`
→ `godot/addons/godot_mcp/cache/screenshots/cavern_map.png`

### Ce qui manque, et qui est le vrai travail de conception

1. **La silhouette est trop « bulles ».** On lit des ellipses assemblées, pas une
   caverne creusée par l'eau. Les croquis ont des angles, des rétrécissements
   brusques, de l'asymétrie.
2. **Le vide.** À 375 m de traversée, le risque n'est plus le manque d'espace
   mais la **marche inutile**. La densité d'intérêt au mètre carré est le sujet
   principal, devant la forme.
3. **Les 5 zones légendées** des croquis (Salle Boss, Loot, Lac, Mécanisme secret,
   Poteau roche) ne sont qu'approximativement placées.
4. **Les sightlines à cette échelle.** La grammaire lumineuse actuelle (le mat
   s'éteint à 15-25 m, les émissifs portent à 50 m) a été calibrée sur une
   caverne 8 fois plus petite. Elle est à repenser.
5. **La circulation.** Comment traverse-t-on 375 m sans que ce soit long ?
   Raccourcis, téléporteurs, boucles ?

---

## 4. Comment vérifier une proposition

Toute spec peut être testée avant d'être construite :

```
godot --headless --path godot --script tools/build_cavern_terrain.gd   # génère + rapport
godot --headless --path godot --script tests/test_cavern_sealing.gd    # étanchéité, pentes, lac
godot --headless --path godot --script tests/test_cavern_navigation.gd # traversabilité
godot --headless --path godot --script tools/render_cavern_map.gd      # carte
```

Le rapport de génération affiche la surface jouable, la hauteur libre, la pente
maximale et l'altitude aux points clés. **Si une proposition sort de ces bornes,
les tests le disent avant qu'on ait construit quoi que ce soit.**

# Niveau 1 « Caverne Cristalline » — Spécification topographique ×7

> **Produit par ◆ Fable (session créative E2bis, tâche #39, 2026-08-08).**
> Remplace intégralement la spec « Combe Gelée » : le niveau passe à **×7+ en
> surface** sur la forme organique des **croquis de l'utilisateur** (plan +
> plafond), sous les contraintes mesurées de
> [`level01_buildable_constraints.md`](level01_buildable_constraints.md).
>
> **Ce document est la source de vérité spatiale.** Les tables de coordonnées
> sont autoritaires ; Opus transcrit sans réinterpréter. Toute correction passe
> par un patch d'ici, jamais par une divergence silencieuse dans la scène.

---

## 1. Parti-pris — « La Faille du Pilier »

**L'histoire géologique en une phrase : le plafond s'est effondré au centre, le
lac s'est formé sous la brèche, et deux piliers de roche — vestiges de la voûte
— tiennent encore debout dans l'eau gelée.**

Tout le niveau découle de cet événement :

- **Le Trou du Plafond** (2e croquis) n'est pas une fenêtre : c'est **la
  cicatrice de l'effondrement**. Sa colonne de lumière est le repère de niveau
  T1, visible de presque partout. On ne « suit pas une flèche », on marche vers
  la lumière.
- **Les deux Poteaux de roche** (1er croquis) sont les colonnes survivantes.
  Ils encadrent la lumière, portent des veines de cristal, et donnent au lac
  son échelle verticale — 15 m de fût, du lit gelé à la voûte.
- **La caverne est une faille en S** : on entre à l'ouest par la galerie haute,
  on descend vers la brèche lumineuse, on contourne le lac, et on remonte au
  nord-est vers la salle du boss — le seul lobe que la lumière du jour ne
  touche jamais.
- **La lumière raconte la sûreté.** Zones touchées par le jour = respiration,
  hub, puzzle. Zones que le jour ne touche pas = loot caché, boss. Le joueur
  l'apprend sans un mot.

### Réponse au vrai problème : la marche inutile

À cette échelle (~330 m de parcours nominal), le danger n'est plus le manque
d'espace, c'est le vide. Trois réponses structurelles :

1. **Un battement tous les 30-40 m** (table §8) : combat, découverte, bifurcation,
   vue — jamais deux tronçons muets d'affilée.
2. **Le retour n'existe pas** : le **Passage Effondré** — ouvert par le
   *Mécanisme secret* du croquis — relie la salle du boss au lac en 40 m et
   transforme le S en **boucle**. On ne re-marche jamais ce qu'on a déjà vu.
3. **Les détours paient** : Loot et Jardin sont hors du chemin critique, courts
   (60-80 m aller-retour), et signalés par leur propre lumière.

---

## 2. Système de coordonnées et emprise

- Unités : **mètres**. Repère Godot : +X = est, −X = ouest, −Z = nord, +Z = sud.
- **Origine (0, 0)** ≈ centre de la brèche. **Y = 0** ≈ rives du lac − 2 m.
- Fenêtre d'échantillonnage : **X ∈ [−155, +155], Z ∈ [−105, +105]** (inchangée).
- Surface jouable visée : **≥ 36 000 m²** (brief ×7 ; le premier jet en donne 41 884).

---

## 3. La silhouette — chambres et goulets (TABLE AUTORITAIRE)

Le reproche au premier jet : « trop bulles ». La correction tient en trois
procédés, à appliquer tels quels :

- **Chaque salle = 2-3 poches décalées et tournées**, jamais une seule ellipse.
- **Adoucissement de bord VARIÉ** (4 à 18 m) : bords serrés = falaises franches,
  bords larges = évasements. L'alternance casse la rondeur.
- **Bruit de modulation de hauteur libre plus agressif** : amplitude **1,2**,
  échelle **14 m** (au lieu de 0,8/22) — les parois deviennent crénelées.

### Salles (poches elliptiques)

| ID | Nom | Centre | Rayons | Rot° | H. libre | Bord | Rôle |
|---|---|---|---|---|---|---|---|
| B1 | Salle du Boss (cœur) | (96, −54) | 46×34 | −14 | 15 | 14 | l'arène |
| B2 | Salle du Boss (lobe NO) | (66, −70) | 24×18 | +22 | 14 | 10 | le « marteau » du croquis |
| B3 | Encoche Est | (122, −30) | 14×10 | −30 | 12 | 6 | alcôve d'arène, dos au mur |
| G1 | Galerie Ouest | (−102, −38) | 34×24 | +18 | 13 | 12 | zone de spawn, haute |
| G2 | Galerie Centrale | (−54, −44) | 30×20 | −10 | 12 | 8 | premier combat |
| G3 | Galerie Est | (−12, −36) | 30×22 | +8 | 13 | 16 | débouché vers la lumière |
| N1 | Baie Nord | (−44, −64) | 11×8 | +25 | 11 | 5 | nid du cristal K3, à l'écart |
| L1 | Salle du Lac (cœur) | (−4, 36) | 46×40 | −8 | 15 | 18 | le hub sous la brèche |
| L2 | Lobe Nord-Est | (28, 16) | 22×16 | +30 | 14 | 8 | vers le seuil et le passage secret |
| L3 | Queue Sud | (−14, 74) | 14×10 | −20 | 11 | 6 | l'appendice bas du croquis |
| P1 | Poche du Loot | (−128, 8) | 20×15 | +20 | 10 | 5 | la cachette, bords durs |
| J1 | Jardin de Givre | (−86, 34) | 30×22 | −28 | 12 | 14 | respiration, forêt de stalagmites |
| J2 | Jardin (lobe est) | (−60, 52) | 16×12 | +15 | 11 | 8 | fond du jardin, cristal K2 |

### Goulets (capsules)

| ID | Nom | De → À | ½-larg. | H. libre | Rôle |
|---|---|---|---|---|---|
| C1 | Le Détroit | (−32, −42) → (−24, −38) | 5 | 10 | pince la galerie en deux actes |
| C2 | Boyau du Loot | (−104, −22) → (−120, 2) | 4,5 | 10 | étroit, en file — une cachette se mérite |
| C3 | Passe du Jardin | (−74, −8) → (−80, 16) | 6 | 11 | bifurcation sud |
| C4 | La Descente | (−20, −14) → (−10, 6) | 7 | 12 | LE débouché sur le lac (vista V2) |
| C5 | Seuil du Boss | (30, −40) → (52, −48) | 8 | **10** | compression avant la révélation |
| C6 | **Passage Effondré** | (50, −32) → (30, 2) | 4 | 10 | **la boucle** — fermé au départ, cf §6 |

> C1/C2/C6 sont volontairement sous les 6 m du chemin principal : ce sont des
> passages secondaires, la fiche l'autorise (≥ 3 m).

---

## 4. Le relief — altitudes (TABLE AUTORITAIRE)

L'histoire verticale : **haut à l'ouest (+9), bas au centre (−3,75 sous la
glace), l'arène en contrebas au nord-est (−3)**. On descend vers la lumière,
puis on plonge vers le noir.

### Plateaux

| Nom | Centre | ½-étendue | Alt. | Fondu* | Note |
|---|---|---|---|---|---|
| Perchoir Ouest | (−112, −38) | 26×20 | +9 | Δ4 @16° | spawn — on domine la galerie |
| Galerie mi-pente | (−54, −42) | 26×18 | +6 | Δ3 @16° | |
| Galerie basse | (−12, −36) | 26×18 | +4 | Δ2 @16° | |
| Perchoir du Loot | (−128, 8) | 16×12 | +9,5 | Δ3 @16° | perché : y monter se mérite |
| Jardin | (−82, 36) | 26×20 | +3 | Δ3 @16° | |
| Crête du Seuil | (42, −46) | 9×7 | +6,5 | Δ2 @16° | on MONTE avant de voir l'arène |
| Berge du Passage | (40, −14) | 8×12 | +4 | Δ2 @16° | sol du Passage Effondré |

*\* Fondu : utiliser `min_falloff_for(Δ, 16°)` — jamais un nombre à la main.*

### Cuvettes

| Nom | Centre | Rayons | Prof. | Margelle | Fond plat | Note |
|---|---|---|---|---|---|---|
| Lit du Lac | (−4, 38) | 30×26 | 3,2 | 0,7 | **0,55** | nappe à −0,55 |
| Bol de l'Arène | (100, −52) | 38×30 | 5,0 | 0,6 | **0,42** | comme le premier jet |

Rampes de l'arène : **inchangées** (nord (66,−66)→(84,−58) et sud (66,−38)→(84,−46),
largeur 9, altitudes 3 → −2,5 *avant creusement*).

### Modulation de hauteur libre

| Nom | Centre | ½-étendue | Δ | Effet |
|---|---|---|---|---|
| Compression du Seuil | (42, −46) | 11×10 | **−6** | voûte à ~10 m : on baisse la tête avant l'arène |
| Ouverture de l'Arène | (100, −52) | 34×26 | +5 | le plafond s'enfuit d'un coup |
| Nef de la Brèche | (−4, 36) | 36×44 | +4 | le lac respire à 15 m |
| Étranglement du Détroit | (−28, −40) | 8×6 | −4 | pincement de C1 |

Bruit de modulation : **amplitude 1,2, échelle 14, graine 4412** (parois crénelées).

---

## 5. Le lac, la Langue et les Piliers

**Lac** : emprise (−4, 38), rayons 30×26, surface **−0,55**, prof. min 0,2.

### ⚠️ La presqu'île et l'îlot sont des PROPS, pas du terrain

Le croquis montre une langue de pierre qui s'avance dans le lac, et un îlot.
**C'est infaisable en terrain** : les cuvettes s'*ajoutent* aux plateaux, donc
toute « langue » posée dans l'emprise du lit coulerait sous l'eau (piège n° 3 de
l'ADR — je le contourne au lieu de le subir).

Décision : **la Langue est une chaussée de blocs effondrés** — l'éboulis de la
voûte, ce qui sert l'histoire mieux qu'une presqu'île de terrain :

| Élément | Position (X, Z) | Spec |
|---|---|---|
| Chaussée (4 plateformes) | (−9, 55) → (−8, 49) → (−6, 43) → (−4, 37) | `rock_rubble` agrandi ×3-4, sommets plats **à +0,4** (≈1 m au-dessus de la glace), espacés d'un pas de joueur (≤ 1,6 m), **collision praticable** |
| **Pilier Sud** | (−6, 40) | fût de roche **15 m**, du lit (−3,75) à la voûte — il la TOUCHE. Veines de cristal émissives sur le tiers supérieur |
| **Îlot** | (4, 28) | socle d'éboulis ∅5 m, plat à +0,3 |
| **Pilier Nord** | (4, 28) | idem Pilier Sud, sur l'îlot |
| Cristal **K1** | (4, 29) | au pied du Pilier Nord — il faut traverser la glace ou la chaussée |
| Coffre puzzle **CH1** | (−10, 58) | à TERRE, rive sud, au départ de la chaussée — visible dès V2, inerte avant les 3 cristaux |

Hero asset à produire (E4) : **le Pilier** — un seul modèle, 2 instances
tournées différemment. Brief Meshy : colonne de roche stratifiée bleu-gris,
fût brisé-refait, veines de cristal cyan sur le haut, ~4 m de diamètre.
`keep_altitude` sur K1 et tout marqueur posé sur la chaussée (le snapper les
coulerait au lit du lac).

### Les ouvertures de voûte

| ID | Centre | Rayons | Rot° | Rôle |
|---|---|---|---|---|
| O1 | (−8, 32) | 16×12 | −20 | la Brèche, lobe principal |
| O2 | (6, 40) | 12×14 | +35 | la Brèche, lobe est — l'union O1+O2+O3 fait le contour libre du croquis |
| O3 | (−18, 44) | 9×7 | 0 | la Brèche, échancrure ouest |
| O4 | (−128, 6) | 6×5 | 0 | au-dessus du Loot — l'appât |
| O5 | (−58, −36) | 4×12 | +30 | fente au-dessus de la galerie — une lame de lumière en travers du chemin, à mi-parcours |
| O6 | (104, −44) | 2,5×9 | −40 | fissure d'arène : **une seule lame froide tombe sur le Golem endormi**. Le seul jour que le boss reçoit |

---

## 6. Le Mécanisme secret (croquis : « Mécanisme secret jeu »)

C'est le **fragment du puzzle méta** du niveau 1 (cf `puzzle_meta.md` — chaque
niveau en porte un). Trois étages de secret :

1. **La Serrure de Givre** — paroi nord du Seuil (C5), à (46, −38) : trois
   glyphes gravés, **éteints**. Ils ne s'illuminent que quand les trois cristaux
   K1-K3 sont activés. Le joueur qui passe avant ne voit que des rainures.
2. **Le Passage Effondré (C6)** — le goulet existe dans le terrain mais son
   entrée côté lac (32, 2) est **obstruée par la Porte Effondrée** (prop :
   dalles de roche, même famille que la chaussée). Interagir avec la Serrure
   illuminée fait s'effondrer la porte (même grammaire que G : la roche cède).
3. **L'Alcôve du Fragment** — à mi-passage (40, −14), une niche : le
   **fragment méta** y flotte, gravé des mêmes glyphes. Le passage sert ensuite
   de **raccourci boss ↔ lac** : le secret ne se visite pas, il s'utilise.

Lisibilité : la Serrure est à 4 m du chemin obligatoire du Seuil — on la frôle
forcément deux fois (aller simple + regard V3). Personne ne la manque, personne
ne la comprend avant d'avoir fini le puzzle. C'est le rythme voulu.

---

## 7. Sightlines & grammaire lumineuse ×7

Recalibrage complet — l'ancienne grammaire était réglée pour 90 m d'emprise.

### Trois étages de repères

| Étage | Portée | Repères |
|---|---|---|
| **T1** | tout le niveau (~120 m+) | **la colonne de lumière de la Brèche** (brouillard volumétrique). Pas une géométrie : de la lumière dans l'air — elle traverse la brume là où le mat s'éteint |
| **T2** | ~60-110 m | les **deux Piliers** (veines émissives hautes, à 12-15 m du sol donc visibles par-dessus le relief) ; la **lame O5** de la galerie |
| **T3** | ~25-40 m | sanctuaires de cristal, K1-K3, la Lanterne (unique point chaud, Jardin) |

### Brouillard par zone (extinction du mat / les émissifs portent au-delà)

| Zone | Mat | Intention |
|---|---|---|
| Galerie (G1-G3) | 28 m | on avance de halo en halo, la lame O5 rythme |
| Boyau + Loot | 14 m | oppressant — la cachette se gagne à l'aveugle |
| Jardin (J1-J2) | 18 m | intime, la Lanterne guide |
| **Salle du Lac** | **65 m** | LA clairière : sous la Brèche, on voit tout — c'est ici qu'on s'oriente |
| Seuil (C5) | 16 → **12 scripté** | inspiration avant le plongeon |
| Bol de l'Arène | 32 | le combat reste lisible à 4 joueurs |

### Les trois vues qui font le niveau

| # | Où | Ce qu'on voit | Ce que ça dit |
|---|---|---|---|
| **V1** | spawn (−124, −44), regard est | la galerie descend, la lame O5 en travers à 65 m, et **au fond, une lueur** qui déborde du coude de G3 | « la lumière est par là » — teasing, pas révélation |
| **V2** | sortie de la Descente (−10, 6) | **la carte postale** : la Brèche, sa colonne de lumière, les deux Piliers dans la glace, la chaussée, CH1 | le hub. On voit K1 (îlot), l'entrée du Jardin, la montée du Seuil — on choisit sa route d'un regard |
| **V3** | Crête du Seuil (42, −46) | le bol en contrebas, le Golem sous l'unique lame froide d'O6 | la révélation. Le seul endroit du niveau où la lumière désigne un danger |

---

## 8. Le rythme — un battement tous les 30-40 m

Distances cumulées sur le chemin nominal spawn → boss (~330 m) :

| m | Lieu | Battement |
|---|---|---|
| 0 | Perchoir Ouest | réveil, cristal d'armes (25 m devant, impossible à rater) |
| 35 | G1 → G2 | **combat 1** : 3 rôdeurs entre les stalagmites |
| 70 | Le Détroit (C1) | pincement, voûte à 10 m — puis la Baie Nord s'ouvre à gauche : **K3** |
| 100 | G3 | bifurcation : Passe du Jardin visible à droite (lumière chaude au loin) |
| 130 | La Descente (C4) | **V2** — la carte postale. Pause voulue |
| 160 | rive sud du lac | CH1 + départ de la chaussée. **Combat 2** : béliers sur la glace (dérapage) |
| 190 | Îlot | **K1** au pied du Pilier Nord — traversée à risque |
| 230 | Lobe NE (L2) | montée vers le Seuil ; la Porte Effondrée intrigue à gauche |
| 260 | Seuil (C5) | la Serrure de Givre frôlée ; compression |
| 275 | Crête | **V3** — révélation |
| 300+ | Bol | boss |

Détours : Loot (C2+P1, ~70 m A/R depuis G1, gardé par l'élite ? non — l'élite
reste au Jardin près de K2) ; Jardin (C3+J1-J2, ~80 m A/R, **K2 + Lanterne +
élite**). Chaque détour contient une pièce du puzzle OU du loot — jamais du vide.

Rencontres : les intentions de `level01_encounters.md` restent valides, les
positions sont à re-poser par zone (tâche #29) : rôdeurs G2/G3, cracheurs sur
les hauteurs de G3 et du Seuil, élite au Jardin, béliers sur la glace du lac
(leur piste de lancement rêvée), boss au bol.

---

## 9. Marqueurs de gameplay (X, Z — le snapper déduit Y sauf mention)

| Marqueur | (X, Z) | Note |
|---|---|---|
| Spawn0-3 | (−124,−48) (−120,−42) (−124,−36) (−128,−42) | face à l'est |
| Cristal d'armes (StartChest) | (−114, −40) | |
| K1 | (4, 29) | **`keep_altitude`, Y = +0,35** (sur l'îlot-prop) |
| K2 | (−60, 50) | Jardin, lobe est |
| K3 | (−44, −62) | Baie Nord |
| CH1 (puzzle) | (−10, 58) | rive sud, à terre |
| CH2 (relique) | (−132, 10) | Loot |
| Lanterne | (−84, 32) | unique point chaud |
| Monolithe (prop existant) | (−16, 4) | sentinelle de la Descente — il marque V2 |
| Pilier Sud / Nord | (−6, 40) / (4, 28) | hero props, `keep_altitude` |
| Serrure de Givre | (46, −38) | paroi nord du Seuil |
| Porte Effondrée | (32, 2) | bouche du Passage, côté lac |
| Fragment méta | (40, −14) | alcôve du Passage |
| PuzzleGate | (42, −46) | crête du Seuil |
| Boss | (100, −52) | centre du bol |
| Coffres candidats (×7) | (−96,−48) (−58,−28) (−34,20) (18,52) (−94,42) (26,−28) (118,−34) | RunShell en tire 4 |

---

## 10. Écarts assumés vs le premier jet d'Opus

1. **Galerie scindée en deux actes** par le Détroit (C1) — le premier jet avait
   une nef continue de 170 m, illisible et monotone.
2. **La Baie Nord (N1) est nouvelle** : K3 y vit, à l'écart mais frôlé au
   passage du Détroit.
3. **Le Passage Effondré (C6) est nouveau** : c'est lui qui transforme le S en
   boucle et donne un corps au « Mécanisme secret » du croquis.
4. **Presqu'île + îlot = props d'éboulis**, pas du terrain (infaisable — cf §5).
5. **L'Anse Sud-Ouest devient le Jardin de Givre** : même emprise, mais un rôle
   (K2, Lanterne, élite) au lieu d'un simple appendice.
6. Le bruit de modulation passe à **1,2 / 14 m** pour créneler les parois.

## 11. Conformité (à vérifier après transcription)

- [ ] Surface jouable ≥ 36 000 m² (brief ×7)
- [ ] Hauteur libre jouable dans [10, 15] m — compression du Seuil à 10, jamais moins
- [ ] Pente : ≤ 2 % du sol jouable au-dessus de 36°, aucun point ≥ 45°
- [ ] Traversabilité : chaque POI atteignable depuis chaque spawn ; boucle
      spawn → Loot → Jardin → lac → îlot → Seuil → bol sans discontinuité
- [ ] Le Passage Effondré est traversable une fois la Porte retirée
- [ ] Aucun marqueur enterré (snapper) ; K1 et piliers en `keep_altitude`
- [ ] Les 3 lobes de la Brèche (O1-O3) forment UN SEUL trou au rendu

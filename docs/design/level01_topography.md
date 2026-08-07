# Niveau 1 « Caverne Cristalline » — Spécification topographique

> **Produit par ◆ Fable (session créative E2, 2026-08-08)** à partir du brief §6bis de
> [`level01_art_bible.md`](level01_art_bible.md), sous la DA glaciaire actée (art bible §3).
> **Ce document est la source de vérité spatiale du niveau.** Opus l'exécute au MCP Godot sans
> réinterpréter : en cas d'ambiguïté entre la carte ASCII (indicative) et les **tables de coordonnées
> (autoritaires)**, les tables gagnent. Toute correction issue du playtest passe par un patch de ce
> fichier, pas par une divergence silencieuse dans la scène.

---

## 1. Parti-pris — « La Combe Gelée »

**Le geste : une combe glaciaire qui descend, respire, puis mord.** On entre par une corniche haute à
l'ouest, on descend à travers une forêt de stalactites qui hache la vue, et le volume s'ouvre d'un coup
sur un **lac gelé** — le cœur du niveau, une nappe de glace pâle frappée par un puits de jour, le seul
endroit où la caverne se laisse voir en entier. Trois lobes rayonnent autour du lac (le nid, la
lanterne, la forêt qu'on retraverse) ; tout à l'est, une crête-seuil compresse le passage avant de
révéler l'arène du Golem, en contrebas dans son bol de glace.

Pourquoi ce geste :

- **La pente raconte la progression.** +6 m au spawn, 0 m au lac, −3 m dans l'arène : on s'enfonce
  vers le boss, littéralement. Le regard du joueur suit la gravité.
- **Le lac est le hub d'orientation.** La mécanique signature est la *visibilité limitée* : elle
  n'existe que par contraste. Zones hachées (forêt, nid) ↔ clairière totale (lac). Depuis la glace, on
  lit les quatre directions ; dès qu'on en sort, le brouillard reprend ses droits.
- **Le milieu est non-linéaire, les extrémités sont linéaires.** Entrée et boss sont des couloirs
  dramatiques ; entre les deux, les 3 cristaux du puzzle sont répartis dans 3 lobes que l'équipe visite
  dans l'ordre qu'elle veut. C'est la structure qui fait travailler la coop (se séparer ou pas) sans
  jamais perdre personne : tout ramène au lac.
- **La lumière est le langage.** Froid émissif cyan = chemin et objectifs. **Un unique point chaud**
  dans tout le niveau (la lanterne, Z5) = curiosité, récompense cachée. Le chaud ne réapparaît ensuite
  que dans les telegraphs du boss — la grammaire de la référence visuelle, systématisée.

## 2. Système de coordonnées et emprise

- Unités : **mètres**. Repère Godot : **+X = est, −X = ouest, −Z = nord, +Z = sud**, Y = altitude.
- **Origine (0, 0)** : centre du lac gelé. **Y = 0** : surface de la glace du lac.
- Emprise jouable : **X ∈ [−45, +48], Z ∈ [−28, +26]** → ~93 m × 54 m (le brief demandait un ordre de
  grandeur 60–90 m ; je propose 93 m parce que l'arène est un appendice fermé, pas de l'espace de
  traversée — le cœur jouable tient dans 80 m).
- Le volume est clos par parois rocheuses sur tout le périmètre et par la voûte partout. **Aucune
  arête de l'emprise n'est franchissable.**

## 3. Les six zones

| Zone | Nom | Emprise X | Emprise Z | Sol (alt) | Voûte (alt) | Rôle |
|---|---|---|---|---|---|---|
| **Z1** | Corniche du Réveil | −45 → −32 | −8 → +8 | **+6 → +5** (pente 2°) | +18 | spawn, vista d'ouverture |
| **Z2** | Forêt de Stalactites | −32 → −12 | −15 → +12 | **+5 → +2** (2 rampes ≤ 9°, ondulations ±0,6) | +16 → +14 | combat 1, visibilité hachée, K3 |
| **Z3** | Le Lac Gelé | ellipse c.(0,0), 16×12 | — | **0** (plat, bosselé ±0,3 aux rives) | +14 | hub, landmark, respiration |
| **Z4** | Le Nid | +8 → +28 | +8 → +26 | **+2 → +4** (3 terrasses) | +14 | combat 2, K1 |
| **Z5** | La Lanterne | +6 → +22 | −28 → −14 | **+3** (plat ±0,3) | +13 | loot caché, accent chaud, K2 |
| **Z6** | Seuil & Arène | +28 → +48 | −10 → +10 | crête **+3**, bol **−3** | +13 / +12 | révélation + boss |

Hauteur libre voûte−sol : minimum **10,0 m** (Z5 et crête du seuil), maximum **15,0 m** (arène). Toutes
les zones respectent la fourchette dure 10–15 m. La voûte s'interpole continûment entre les valeurs du
tableau (pas de marches).

### Z1 — Corniche du Réveil

Balcon rocheux adossé à la paroi ouest. Les 4 spawns y sont décalés en ligne. Le sol penche doucement
vers l'est : dès la première seconde, le corps est orienté dans le bon sens. C'est d'ici que se lit la
**vista V1** (cf §5) — le halo du monolithe à travers la brume, au bout de l'allée. L'antichambre
d'onboarding (E5, scène séparée) débouche ici par une porte de glace dans la paroi ouest.

### Z2 — Forêt de Stalactites

Le motif vertical de la référence : ~25 groupes de stalagmites/stalactites (`stalactite_cluster`,
instancié MultiMesh) qui hachent les sightlines à 8–15 m. Deux rampes douces descendent +5 → +2 avec
un plateau intermédiaire — jamais plus de 9° sur le chemin principal. Une **allée** de 8 m de large
(A1, cf table des features) reste vierge de colonnes : c'est le canal de la vista V1. La cuvette C1
(∅6 m, prof. 1 m, rebord +0,5 m) abrite le cristal de puzzle **K3**, éteint au premier passage — on le
voit, on ne peut rien en faire, on s'en souvient.

### Z3 — Le Lac Gelé

L'image du niveau. Glace pâle, plate, qui **renvoie la lumière du puits P1 vers la voûte** — le seul
endroit où l'on voit le plafond de la caverne entier. Rives en anneau montant +1,5 → +2 sur 3–5 m de
large (le lac est une cuvette **bordée**, conforme anti-chute). Sur la rive nord, **le Monolithe** (M) :
la pièce héro `crystal_monolith_landmark`, 9 m, faiblement émissive — visible en halo depuis presque
partout. À son pied, le **coffre de puzzle** (CH1), visible dès l'arrivée au lac, inerte tant que les
3 cristaux ne sont pas allumés : la récompense se montre avant de se donner.

**Règle de sanctuaire** : aucun combat ne se déclenche sur la glace tant que le premier cristal de
puzzle n'est pas activé (cf `level01_encounters.md`). Le hub reste lisible le temps d'apprendre à s'en
servir.

### Z4 — Le Nid

Lobe sud-est en trois terrasses (+2 / +3 / +4, rampes de 3 m à ≤ 12°, jamais de ressaut supérieur à
0,3 m). Le cristal **K1** trône sur la terrasse haute, gardé (ranged sur les terrasses, cf encounters).
Depuis le rocher-table central (+16, +15), les trois terrasses se lisent d'un regard — le joueur peut
planifier avant d'engager.

### Z5 — La Lanterne

Chambre nord derrière un rideau de stalactites percé de **deux** passages (pas de cul-de-sac). Sous le
petit puits de jour P2 : une **lanterne abandonnée (L)** — l'unique lumière chaude du niveau, posée là
comme une anomalie. Depuis le lac, son reflet chaud clignote entre les colonnes : c'est l'appât
d'exploration. Dans la chambre : le cristal **K2**, un élite en garde, et le **coffre de relique**
(CH2) hors chemin critique. Qui a suivi la curiosité repart payé.

### Z6 — Le Seuil & l'Arène

La crête +3 se gagne depuis la rive est (+2) par une pente à 6°. Au sommet, **compression** : la voûte
descend à +13 (10 m au-dessus de la crête — le minimum autorisé, exploité comme effet), le passage se
resserre à 8 m entre deux piliers (G). Puis la **révélation V3** : le bol de l'arène s'ouvre en
contrebas, −3, ∅20 m, et ce qu'on prenait pour une formation de glace au centre est le Golem agenouillé.
Deux rampes (RN, RS) descendent dans le bol ; ses parois intérieures sont à 25° — remontables partout,
mais l'évidence du chemin reste les rampes. La porte de glace G (le PuzzleGate) barre le passage tant
que le puzzle n'est pas résolu, et **repousse** derrière l'équipe quand le combat s'engage.

## 4. Carte (indicative — les tables font foi)

```
       X: -45      -35      -25      -15      -5   0   +5      +15      +25      +35      +48
          ┌─────────────────────────────────────────────────────────────────────────────────┐
  Z -28   │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░░░░░ Z5 ░░░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
  Z -20   │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓░░ K2   ☀P2 🔥L  ░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
  Z -14   │▓▓▓▓▓▓▓▓▓▓▓▓▓ f f f f f ▓▓▓▓▓▓▓▓▓▓▓░(rive)░░ ‖ ░░░░ ‖ ░░░░▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
  Z  -8   │▓▓▓ S S S ▓▓ f f f f f f f ░░≈≈≈≈≈ M ≈≈≈≈≈░░░░░░░░░░░▓▓▓▓▓▓▓▓▓╔══════════╗▓▓▓▓│
  Z   0   │▓▓▓ S S S ══A1══ f f  ░░≈≈≈≈≈≈ ☀P1 ≈≈≈≈≈≈░░(rive)░░░═╡G╞═══  ║  ARÈNE  B ║▓▓▓▓│
  Z  +8   │▓▓▓ S S S ▓▓ f f (C1·K3) f ░░≈≈≈≈≈≈≈≈≈░░░░░░░░░░░░▓▓▓▓▓▓▓▓▓╚══════════╝▓▓▓▓│
  Z +14   │▓▓▓▓▓▓▓▓▓▓▓▓▓▓ f f f ▓▓▓▓▓▓▓░░(rive)░░░ n n (table) n n ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
  Z +22   │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓ n n K1 n n n ▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
  Z +26   │▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓▓│
          └─────────────────────────────────────────────────────────────────────────────────┘
   ▓ roche (hors jeu)   S spawns   f forêt de stalactites   ≈ glace du lac   ░ rives/sol
   ☀ puits de jour   M monolithe   🔥 lanterne (seul point chaud)   ‖ passages du rideau
   A1 allée de vista   C1 cuvette   K1-K3 cristaux puzzle   G porte de glace   B Golem
```

## 5. Sightlines & landmarks — comment la caverne se lit

**Grammaire lumineuse (la clé de tout)** : le brouillard est réglé pour que la **géométrie mate**
s'éteigne à 15–25 m selon la zone, mais que les **sources émissives** restent lisibles en halo diffus
jusqu'à ~50 m. On ne voit pas les murs de loin — on voit les balises. C'est la mécanique de visibilité
limitée transformée en système de navigation : les cristaux SONT la boussole, exactement comme au beat
6 de l'onboarding.

| # | Depuis | Vers | Distance | Ce que ça dit au joueur |
|---|---|---|---|---|
| **V1** | Z1 corniche (+6, yeux +7,6) | halo du Monolithe + colonne du puits P1, par l'allée A1 | ~44 m | « C'est par là. » L'objectif du niveau, montré à la première seconde, jamais expliqué |
| **V2** | centre du lac (0,0) | 360° : M et CH1 au nord, reflet chaud de L entre les colonnes nord, halos de K1 au SE / K3 à l'ouest, masse sombre de la crête à l'est | 15–25 m | Le hub. Chaque POI a une signature lumineuse distincte visible d'ici — l'équipe se répartit les cibles sans un mot |
| **V3** | crête du seuil (+3) | le bol de l'arène en contrebas, le Golem-qu'on-prend-pour-un-rocher au centre | ~15 m plongeants | La révélation. Cadrée par la compression (voûte +13, passage 8 m) puis l'ouverture — cf `level01_encounters.md` §4 |

Landmarks, par portée : **le puits P1** (colonne de lumière, visible de partout où la voûte du lac est
dans le champ), **le Monolithe** (halo froid, ~50 m), **la Lanterne** (halo chaud, ~25 m, unique). Trois
signatures, trois températures, aucune confusion possible.

## 6. Puits de ciel

| ID | Position (X,Z) | ∅ ouverture | Voûte locale | Éclaire | Rôle |
|---|---|---|---|---|---|
| **P1** | (+2, −2) | 8 m | +14 | le centre du lac : flaque de lumière ∅~10 m sur la glace | landmark principal, respiration, « on voit le ciel » |
| **P2** | (+14, −20) | 3 m | +13 | la lanterne et son îlot | consacre le sanctuaire de la récompense cachée |

Deux puits seulement — la rareté fait le prix. Chaque ouverture est **fermée par une collision
invisible** au niveau de la voûte (on voit le ciel, on ne sort jamais — contrainte dure). Shafts
volumétriques et flaques au sol : exécution en E3.

## 7. Circulation — et ce que le navmesh doit garantir

Boucle nominale : **Z1 → Z2 (combat, K3 repéré) → Z3 (hub) → K1/K2/K3 dans l'ordre choisi → G s'ouvre
→ V3 → arène**. Trois allers-retours courts qui rayonnent du lac ; aucun point du cœur jouable n'est à
plus de ~30 s de la glace.

Contraintes d'exécution (Opus, tâches #10–#12) :

- **Pentes** : chemin principal ≤ 9°, rampes secondaires ≤ 14°, parois du bol d'arène 25° (praticables).
  Aucun ressaut > 0,3 m sur une surface praticable. `max_slope` du navmesh aligné sur le
  `floor_max_angle` du joueur.
- **Largeurs minimales** : chemin principal 6 m, rampes 3 m, passages du rideau Z5 2,5 m chacun —
  jamais de goulot où 4 joueurs + FF = bouchon mortel, sauf le seuil G (8 m), qui est un choix.
- **Pas d'îlot** : chaque zone a ≥ 2 connexions praticables (Z5 a ses deux passages ; C1 a un rebord
  franchissable sur tout son périmètre ; le bol d'arène a ses 2 rampes + parois 25°).
- **Toutes les cuvettes sont bordées** : C1 (prof. 1 m), le lac (rives +1,5), le bol (−3, rebord +3).
  Aucun vide, nulle part. Le volume est un bol de bols.

## 8. Table des features (autoritaire pour le placement)

| ID | Objet | Position (X, Y, Z) | Dim/notes |
|---|---|---|---|
| SP0–SP3 | spawns joueurs | (−41, +6, −4,5) / (−41, +6, −1,5) / (−41, +6, +1,5) / (−41, +6, +4,5) | face à l'est |
| A1 | allée de vista | axe (−32, 0) → (+5, −12), largeur 8 m | zone interdite aux colonnes |
| C1 | cuvette | centre (−20, +6), ∅6 m, fond +1,0 (sol local +2), rebord +0,5 | contient K3 |
| K3 | cristal puzzle 3 | (−20, sol, +6) au fond de C1 | éteint au 1er passage |
| M | Monolithe (héro) | (+5, +1,5, −12), pedestal rive | h. 9 m, émissif faible |
| CH1 | coffre puzzle | (+3, +1,5, −10), pied du monolithe | inerte avant puzzle |
| P1 | puits principal | voûte, centre (+2, −2), ∅8 m | collision invisible |
| K1 | cristal puzzle 1 | (+22, +4, +20), terrasse T2 du Nid | gardé (ranged) |
| — | rocher-table | (+16, +3, +15), terrasse T1 | poste d'observation Z4 |
| ‖×2 | passages rideau Z5 | (+8, −14) et (+18, −14), larg. 2,5 m | jamais un seul accès |
| P2 | puits secondaire | voûte, centre (+14, −20), ∅3 m | collision invisible |
| L | lanterne | (+14, +3, −21) | **unique lumière chaude du niveau** |
| K2 | cristal puzzle 2 | (+10, +3, −22) | gardé (élite, évitable) |
| CH2 | coffre relique | (+20, +3, −24) | hors chemin critique |
| G | porte de glace / PuzzleGate | crête, notch entre piliers (+30, −4) et (+30, +4) | s'ouvre au puzzle, se referme au combat |
| RN / RS | rampes d'arène | (+33, −7)→(+36, −3) et (+33, +7)→(+36, +3), larg. 3,5 m, 14° | seuls chemins « évidents » |
| B | Golem (boss) | (+38, −3, 0), centre du bol | agenouillé, gainé de glace au repos |

## 9. Brouillard par zone (réglages de départ, à affiner en E3)

| Zone | Portée géométrie mate | Ambiance |
|---|---|---|
| Z1 | 25 m | on découvre V1 : assez de vue pour comprendre, pas assez pour tout voir |
| Z2 | 10–14 m | le cœur de la visibilité limitée — les colonnes surgissent |
| Z3 | 35 m | la respiration : seul endroit où la caverne s'expose |
| Z4 | 15 m | tactique : on lit la terrasse suivante, pas tout le nid |
| Z5 | 18 m | intime, sanctuaire |
| Z6 | 25 m → resserrement scripté pendant le combat (cf encounters) | la tension se voit |

## 10. Conformité aux contraintes dures (DoD E2)

| Contrainte | Où c'est garanti |
|---|---|
| Voûte 10–15 m au-dessus du sol praticable | tableau §3 : min 10,0 (Z5, seuil), max 15,0 (arène) |
| Volume fermé, aucune sortie | parois sur tout le périmètre + collisions invisibles sur P1/P2 |
| Aucune chute possible | §7 : « bol de bols » — toutes les dépressions bordées, prof. max 3 m (arène), remontable partout |
| Sol vallonné praticable partout | pentes ≤ 14° sur chemins, 25° max (bol), aucun ressaut > 0,3 m |
| ≥ 1 zone à ciel ouvert landmark | P1 (∅8 m) au-dessus du lac, visible en colonne de lumière depuis V1 |
| 4–6 POI intentionnels | 6 : corniche, forêt/C1, lac/monolithe, nid, lanterne, seuil/arène |
| Traversable spawn → boss sans cul-de-sac | boucle §7, chaque zone ≥ 2 connexions |

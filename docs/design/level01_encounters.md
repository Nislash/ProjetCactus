# Niveau 1 — Rencontres, tension & révélation du boss

> **Produit par ◆ Fable (session créative, 2026-08-08).** Design de combat exécutable par Opus en E6
> (câblage des encounters, `boss_ai` Rust). Toutes les positions renvoient aux zones et features de
> [`level01_topography.md`](level01_topography.md). Archétypes existants : **rôdeur** (mêlée),
> **cracheur** (ranged), **bélier** (charger) ; toutes les stats vivent en `EnemyData.tres`, ce
> document ne fixe que des intentions et des ratios.

## 1. La courbe de tension

```
intensité
   ▲                                                            ┌── BOSS P3
   │                                              V3 ┌─ P1 ─ P2 ┘
   │            ┌ E1 ┐            ┌ E-K (×3, l'ordre au choix) ┐│
   │   calme    │    │   LAC      │  pics courts, retours hub  ││
   │  (vista)   │    │(sanctuaire)│                            ││
   └──────────────────────────────────────────────────────────────▶ temps
      Z1          Z2       Z3         K1 / K2 / K3        seuil  arène
```

Principe : **le lac est un sanctuaire** — zéro spawn sur la glace tant que le premier cristal du
puzzle n'est pas activé. La tension monte par vagues courtes dans les lobes et retombe à chaque retour
au hub. La seule montée continue du niveau est le boss. Dans un jeu au FF actif, les respirations ne
sont pas du temps mort : c'est là que l'équipe se repardonne.

## 2. Les rencontres

### E1 — La Forêt (Z2, déclencheur : franchir X = −30)

**3 rôdeurs** (+1 par joueur au-delà du premier) qui **tissent entre les colonnes** : consigne d'IA —
préférer les trajectoires qui coupent derrière un stalagmite plutôt que la ligne droite. Dans une
visibilité à 10–14 m, un mêlée qui disparaît et réapparaît ailleurs est effrayant sans être injuste :
on entend ses griffes sur la glace (audio directionnel obligatoire, cf E7).
**Leçon implicite** : tirer dans le désordre entre les colonnes = toucher un allié. La forêt enseigne
la discipline de tir que le boss exigera.
*Pas de bélier ici : un charger dans un slalom de colonnes et de la brume serait illisible en
split-screen quart d'écran.*

### E-K1 — Le Nid (Z4, déclencheur : entrer dans le lobe)

**2 cracheurs** postés sur les terrasses T1/T2 (positions dominantes, halos de leurs projectiles
visibles de loin — on sait où ils sont, y monter est le défi), **+2 rôdeurs** en renfort quand K1 est
activé. Le rocher-table (+16,+15) est le poste de lecture : depuis là, on voit les deux terrasses et on
planifie. En coop, la solution naturelle est pince (un fixe le cracheur, l'autre monte) — le relief
crée la tactique, pas un script.

### E-K2 — La Lanterne (Z5, pas de déclencheur : il garde, il ne patrouille pas)

**1 élite** : un rôdeur cuirassé de givre (×3 HP, −30 % vitesse, même moveset — un mur, pas un puzzle).
Il est **évitable** : il campe près de K2, et les deux passages du rideau permettent de le contourner
pour activer le cristal ou piller CH2 en discrétion pendant qu'un allié l'occupe. Se battre est un
choix, pas un péage. S'il est tué : il lâche le contenu le plus généreux du niveau hors boss.

### E-K3 — La Cuvette (Z2 revisitée, déclencheur : activer K3)

Le retour dans la forêt, mais **la caverne a changé** : activer K3 depuis le fond de la cuvette C1
déclenche **2 béliers** qui déboulent de la brume dans l'axe de l'allée A1 — le seul endroit du niveau
où un charger a une piste de lancement digne de ce nom. Les joueurs dans la cuvette ont le rebord
comme couvert naturel : le bélier qui rate saute par-dessus et doit faire demi-tour. Terreur brève,
solution lisible.

### Sur la glace (Z3, uniquement après le premier cristal activé)

Le sanctuaire se fissure : à chaque cristal activé, **1–2 béliers** émergent de plaques de glace
mince en bordure du lac (craquelures audio 2 s avant — telegraph). Sur la glace plate, le bélier est
dans son élément… mais **il glisse** : sa charge ratée le fait déraper 4–5 m au-delà de sa cible.
Comique, lisible, et tactiquement riche (l'esquive latérale devient la réponse naturelle). Le hub
reste traversable, plus jamais gratuit.

### Échelle par nombre de joueurs

Règle unique, à valider en playtest (#30) : **effectifs +1 par joueur au-delà du premier** sur E1 et
E-K1 ; l'élite et les béliers ne scalent pas en nombre mais en HP (×1 + 0,4·(n−1)). Boss : cf §5. Pas
de spawn additionnel pendant un revive — le FF punit déjà assez la panique.

## 3. Récompenses d'exploration (l'exploration doit payer, DoD #100)

| Où | Quoi | Pourquoi ça marche |
|---|---|---|
| C1 (cuvette, Z2) | micro-loot (consommable/XP) au premier passage | apprend « les creux contiennent des choses » à 30 s de jeu |
| CH2 (Z5, hors chemin critique) | **relique** + l'élite lâche son gros loot | la seule lueur chaude du niveau paie sa promesse |
| CH1 (pied du monolithe) | coffre de puzzle, **visible dès l'arrivée au lac**, inerte avant les 3 cristaux | récompense vue avant d'être gagnée — c'est elle qui vend le puzzle |
| Boss | relique légendaire (pool dédié, #64) | l'issue attendue |

## 4. La révélation du boss — mise en scène de V3

La règle : **pas de cinématique**. Tout se joue caméra en main, par la topographie.

1. **L'approche** — G fond quand le 3ᵉ cristal s'allume : les trois halos du puzzle s'éteignent
   ensemble et **une veine de givre lumineuse court du lac jusqu'au seuil** (même grammaire que
   l'antichambre : la lumière montre le chemin). Le grondement entendu au beat 6 de l'onboarding
   revient, plus proche, en rythme de pas.
2. **La compression** — montée à 6° vers la crête, voûte à 10 m du sol, passage à 8 m entre les
   piliers de G. Le split-screen le plus chargé (4 joueurs serrés) traverse un cadre qui force la file.
   Le brouillard local se resserre à 15 m pendant la traversée du seuil : deux secondes d'aveuglement
   relatif juste avant l'ouverture — l'inspiration avant le plongeon.
3. **La révélation** — la crête franchie, le bol s'ouvre : 20 m de vue plongeante (le brouillard
   se rouvre à 25 m d'un coup), et au centre, ce que la silhouette laissait prendre pour une formation
   de glace **bouge**. Le Golem se déplie de sa gangue — mise en échelle : il se déplie DE BAS EN HAUT,
   et la caméra des joueurs sur la crête est à +4,6 : ils le voient se dresser *jusqu'à leur hauteur
   des yeux puis au-delà*.
4. **Le verrou** — dès le premier joueur au fond du bol (Y < 0) : G **regèle** en 1,5 s derrière
   l'équipe (bruit de banquise qui prend). Personne dehors : un retardataire encore sur la crête est
   téléporté-poussé par la regelée vers l'intérieur (jamais coupé de l'équipe — règle dure : le verrou
   ne sépare JAMAIS le groupe, cf cas limite tâche #29).
5. **La victoire** — G et la gangue du Golem se brisent sur le même son. La sortie se rouvre sur la
   vue inverse : tout le niveau traversé, les trois cristaux rallumés au loin. La boucle se referme
   visuellement.

## 5. Le combat — intentions pour `boss_ai` (Opus implémente, tâche #28)

Le Golem est un **boss de placement** : dans une arène ronde avec FF actif, l'ennemi réel des joueurs,
c'est leur propre feu croisé. Chaque phase augmente la pression sur le positionnement, pas seulement
les dégâts.

**Grammaire des telegraphs** : toute attaque est annoncée par la couleur chaude `#f2b45c` (art bible :
le chaud est réservé au danger) — fissures au sol, cœur incandescent, veines des bras. Dans un niveau
intégralement froid, une demi-seconde d'orange est illisible à personne, même en quart d'écran.

| Phase | Seuil HP | Comportement | Pression FF |
|---|---|---|---|
| **P1 — Le Réveil** | 100→70 % | lent, slams frontaux télégraphiés (cône au sol orange 0,8 s), charge d'épaule sur la cible la plus lointaine | l'équipe apprend à se répartir en éventail — deux joueurs alignés = l'un tire dans l'autre |
| **P2 — La Fracture** | 70→35 % | +barrage de shards (mortier : zones d'impact ∅2 m marquées au sol), invoque **2 rôdeurs** à 50 % (une seule fois) | les zones marquées cassent l'éventail : se replacer sans traverser la ligne de tir d'un allié |
| **P3 — Le Cœur ouvert** | 35→0 % | vitesse +30 %, le cœur exposé (point faible ×1,5 dégâts, en face avant : tirer dans le cœur = tirer vers l'allié qui le kite), la glace du bol se fissure radialement (visuel, aucun trou réel — anti-chute respecté), brouillard d'arène 25→15 m | l'arène rétrécit *optiquement* ; le point faible met le meilleur DPS dans l'axe du tank : le dilemme FF au sommet |

**HP boss** : ×(1 + 0,6·(n−1)) par joueur supplémentaire. **Downed pendant le combat** : le Golem
cible en priorité les joueurs debout (jamais d'acharnement sur un corps — le revive doit rester une
fenêtre jouable, pas un suicide). Tous down = game over standard.

**Ce que le boss ne fait jamais** : d'attaque non télégraphiée, d'attaque qui suit sa cible pendant le
telegraph (le placement doit payer), de dégâts par la caméra (pas d'AoE plein écran en split 4).

## 5bis. État d'exécution des spawns (● Opus, 2026-08-08)

Les points de spawn sont posés dans `level_01_cavern.tscn` sous `World/EnemySpawnPoints`, à
l'altitude du sol **réellement généré** (et non aux altitudes nominales de la topographie).
L'archétype est déclaré par **groupe de nœud** (`enemy_melee` / `enemy_ranged`), plus explicite et
plus robuste que la convention de nommage héritée du POC — laquelle basculait en ranged dès qu'un
« C » apparaissait dans le nom.

| Rencontre | Design | Posé | Écart |
|---|---|---|---|
| **E1 La Forêt** | 3 rôdeurs | `EnemyForest0-2` (mêlée) | conforme |
| **E-K1 Le Nid** | 2 cracheurs + 2 rôdeurs | `EnemyNestRanged0-1` + `EnemyNest0-1` | conforme, mais les 2 rôdeurs sont posés d'emblée au lieu d'arriver en renfort à l'activation de K1 (déclencheur = #29) |
| **E-K2 La Lanterne** | 1 élite (rôdeur cuirassé) | `EnemyLanternElite0` (mêlée) | **le statut d'élite n'existe pas encore** — c'est un rôdeur standard tant que la variante (×3 HP, −30 % vitesse) n'est pas créée |
| **E-K3 La Cuvette** | 2 béliers | **absent** | ⚠️ **l'archétype charger n'existe pas** : seules `enemy_melee` et `enemy_ranged` sont implémentées. Cf issue #46 (« Ennemi #3 »). À poser dès qu'il existe |
| **Béliers sur la glace** | 1-2 par cristal activé | **absent** | même cause |
| **Boss** | Golem | `World/BossArena/BossSpawn` | marqueur posé, instanciation = #29 |

Ce qui dépend encore du câblage (#29) et non du placement : les **déclencheurs** (franchir X = −30,
entrer dans un lobe, activer un cristal), le **sanctuaire du lac** (zéro spawn avant le premier
cristal), l'**échelle par nombre de joueurs**, et le **verrouillage d'arène**.

## 5ter. L'IA sur relief — ce que la cuvette a changé (● Opus, tâche #28)

L'arène n'est plus un sol plat de 35 × 35 m : c'est un **bol de 5 m de creux**, aux rayons 38 × 30 m,
dont les parois montent à 37° — soit **sous le seuil de glissement** du personnage (45°). Elles sont
donc marchables, et deux hypothèses de l'IA du POC sont tombées avec.

**1. La portée est désormais horizontale.** Le déplacement du boss l'a toujours été (la composante
verticale de son steering est annulée), mais l'agro se mesurait en 3D. Sur un sol plat les deux
coïncident ; dans un bol, un joueur à 4 m de distance mais 10 m plus haut passait pour plus lointain
qu'un joueur à 12 m sur le même plan. La sélection de cible **et** le choix d'attaque au corps à corps
mesurent maintenant la seule distance que le Golem puisse franchir.

**2. Un joueur perché n'est pas une cible.** Au-delà de `max_vertical_reach` (8 m par défaut : le bol
et sa margelle), le boss cesse de le considérer et prend quelqu'un d'autre. Sans cette règle il
resterait planté sous lui à tourner en rond, ce qui se lit comme une IA cassée plutôt que comme une
IA qui renonce.

**3. La laisse.** Rien n'empêchait un joueur de sortir le Golem de son arène en remontant la pente —
et un boss qui suit jusque dans la Grande Nef, c'est le lock d'arène qui ne veut plus rien dire. Le
boss circule **librement dans ses 24 m** (il doit pouvoir acculer un joueur contre la paroi) ; au-delà
du rayon, seule la composante qui l'éloigne est retirée, si bien qu'il **longe** la limite au lieu de
s'y figer ; passé 2 m de plus, il rentre. La charge est tenue par la même laisse : sans ça elle
restait le moyen le plus simple de le faire sortir.

Le rayon est transmis par `CavernGameplay` au moment du spawn (`boss_leash_radius`) : l'IA Rust ne
connaît pas la topographie, et le centre du territoire est le point de spawn du boss.

## 6. Ce qui reste au playtest (#30) — les curseurs, pas la structure

Effectifs exacts, HP de l'élite, durée des telegraphs P1 (0,8 s de départ), portée du resserrement de
brume P3, et le point le plus sensible : **la lisibilité du combat à 4 en quart d'écran**. Si un seul
réglage doit bouger après playtest, ce sera la brume d'arène — elle est belle avant d'être juste.

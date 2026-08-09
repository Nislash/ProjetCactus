# Animations du personnage joueur

> Liste de production pour l'export Meshy. Elle est **dérivée du code**, pas d'un
> catalogue générique : chaque entrée dit qui la consomme et ce qui casse sans
> elle.
>
> Contrat côté moteur : `scripts/core/data/character_anim_set.gd` (la ressource),
> `scripts/core/character_animator.gd` (qui choisit l'état),
> `scripts/core/character_visual.gd` (qui joue le clip).

---

## 1. Ce que le moteur consomme aujourd'hui

`CharacterAnimSet` expose neuf emplacements. **Six sont réellement branchés**,
trois sont déclarés mais rien ne les déclenche encore — c'est utile à savoir
avant de payer des crédits.

| État | Boucle | Branché ? | Qui le choisit |
|---|---|---|---|
| `idle` | oui | ✅ | état par défaut, `_pick_state()` |
| `walk` | oui | ✅ | vitesse ≥ 0,4 m/s |
| `run` | oui | ✅ | vitesse ≥ 5,5 m/s |
| `shoot_walk_forward` | oui | ✅ | tir en marchant vers l'avant |
| `shoot_walk_back` | oui | ✅ | tir en reculant |
| `shoot_run` | oui | ✅ | tir en courant |
| `death` | non | ✅ | signal `downed` du joueur |
| `jump` | non | ⚠️ **mort** | slot présent, **aucun appel** dans le code |
| `melee_combo` | non | ⚠️ **mort** | idem, et l'épée a été annulée |

**Piège de vitesse.** Le joueur court à 7 m/s et le seuil de course est à 5,5 :
en pratique on est en `run` dès qu'on avance à fond, et `walk` ne sert que sur
stick partiel. Si tu veux que la marche se voie, il faudra soit remonter le
seuil, soit accepter que `walk` soit une animation rare.

---

## 2. Le minimum jouable — à exporter en premier

Sept clips. Avec ça le personnage est correct dans les deux vues.

1. **`idle`** — debout, arme basse, respiration. C'est l'animation qu'on voit le
   plus longtemps ; c'est elle qui décide si le personnage a l'air vivant.
2. **`walk`** — marche avant, boucle.
3. **`run`** — course avant, boucle.
4. **`shoot_idle`** ⭐ **nouveau, manquant aujourd'hui** — tirer sans bouger.
   Actuellement le code retombe sur `shoot_walk_forward` quand on tire à
   l'arrêt : le personnage marche sur place. C'est le défaut visuel le plus
   visible du lot.
5. **`shoot_walk_forward`** — tirer en avançant, buste tourné vers l'avant.
6. **`shoot_walk_back`** — tirer en reculant. Distinct du précédent : reculer en
   tirant est la posture de survie du jeu, elle doit se lire de loin.
7. **`death`** — chute au sol, **une seule fois puis figé**. Ne la fais pas
   boucler : le moteur reste sur la dernière pose.

---

## 3. Ce que le jeu promet et qui n'a pas d'animation

Ces mécaniques **existent déjà dans le code** et tournent aujourd'hui sans
animation dédiée. C'est le lot qui rend le personnage cohérent avec ses règles.

| Clip | Boucle | Pourquoi c'est nécessaire |
|---|---|---|
| `downed_idle` | oui | À 0 HP le joueur passe en `DOWNED` — il n'est pas mort, il attend qu'on le relève. Aujourd'hui il joue `death` et reste figé au sol : rien ne distingue « à terre » de « mort ». |
| `downed_crawl` | oui | Le règlement du jeu (`CLAUDE.md`) dit qu'un joueur à terre **rampe lentement**. Il rampe déjà, sans animation. |
| `revive` | non | Maintenir `Interact` 3 s au-dessus d'un allié. Un geste de 3 s sans animation, c'est un joueur planté qui a l'air bloqué. |
| `get_up` | non | La sortie de `DOWNED`. Sans elle, on repasse debout par un saut d'image. |
| `hit_react` | non | Le tir ami est actif : savoir **qu'on vient d'être touché, et d'où**, est une information de survie. Idéalement quatre variantes (avant / arrière / gauche / droite). |
| `jump_start`, `fall_loop`, `land` | non/oui/non | Le saut existe (`jump_velocity = 7.0`) et le niveau 2 demande un saut de 6 m au-dessus de la lave **plus** une chute de 22 m depuis la catapulte. Le slot `jump` existe déjà mais **rien ne l'appelle** — je devrai le câbler. |
| `dash` | non | Le dash existe (`dashed`, cooldown, direction). Sans clip, c'est une glissade. |

---

## 4. Utile plus tard

### 4a. Les combos arme × parchemin — la signature du jeu

`CLAUDE.md` est explicite : *« un pistolet + un parchemin de feu doit devenir
visuellement et mécaniquement un pistolet boule de feu (animation modifiée) »*.
`ComboData` prévoit déjà un champ `animation_override`.

Concrètement, ça veut dire une **variante de la pose de tir par école** plutôt
que 20 animations complètes :

- `shoot_idle_fire` / `_ice` / `_lightning` / `_poison` / `_arcane` — la même
  base, main libre différente, recul différent.

Cinq écoles × trois postures de tir = 15 clips si tu vas au bout. Commence par
**une seule école** pour éprouver que la substitution fonctionne avant
d'industrialiser — c'est la règle qui a déjà servi sur les assets Meshy.

### 4b. Armes

La matrice POC prévoit pistolet **et shotgun**. Le shotgun demande une posture à
deux mains :

- `idle_shotgun`, `shoot_idle_shotgun`, `shoot_walk_forward_shotgun`
- `reload` — **il n'y a pas de rechargement dans le code aujourd'hui**. À ne
  produire que si tu décides d'en ajouter un.

### 4c. Interactions du monde

- `interact_hold` — ramasser un cristal, actionner un levier, pousser le pylône.
  Tout passe par un maintien de bouton, et rien ne s'anime.
- `open_chest` — le coffre d'ouverture de run est le **premier plan du jeu** :
  chaque run commence par là.

### 4d. Mise en scène

- `victory` — fin de run, one-shot.
- `level_up` — la montée de niveau donne un choix de boon, elle mérite un beat.
- `emote_*` (salut, provocation) — pur couch-coop. Ça ne sert à rien
  mécaniquement et beaucoup socialement.

### 4e. Vue subjective

Le jeu a une **vue à la première personne** avec un viewmodel séparé (le corps
est masqué). Les animations ci-dessus sont donc pour la **troisième personne**
et pour ce que *les autres joueurs* voient de toi. Le viewmodel (bras + arme)
est un chantier distinct — ne le confonds pas avec cette liste.

---

## 5. Contraintes techniques Meshy → Godot

À respecter à l'export, sinon ça se rattrape à la main par asset.

1. **Un clip par fichier `.glb`.** `CharacterAnimSet` attend un `.glb` de modèle
   (squelette + mesh) **plus** un `.glb` par animation. Ne livre pas un fichier
   unique contenant toutes les pistes.
2. **Le modèle en T-pose**, son animation interne est ignorée. Meshy propose
   `pose_mode: "t-pose"` — utilise-le, c'est ce qui donne les meilleurs rigs.
3. **Même squelette pour tous les clips.** Un rig regénéré entre deux
   animations ne se recolle pas.
4. **Pas de root motion.** Le déplacement vient du `CharacterBody3D` ; une
   animation qui déplace la racine fait glisser ou patiner le personnage.
5. **Rotation à corriger.** Les `.glb` Meshy regardent souvent +Z alors que
   l'avant de Godot est −Z. Le champ `y_rotation_deg = 180` existe pour ça.
6. **Boucles propres** sur `idle` / `walk` / `run` / `shoot_*` / `downed_*` /
   `fall_loop` : première et dernière image identiques. Le reste est en
   one-shot.
7. **Budget.** Le jeu rend **quatre vues simultanées** à 60 fps. Le squelette
   doit rester raisonnable, et le maillage passer par `meshy_remesh` comme tout
   le reste — une sortie brute pèse plusieurs centaines de milliers de
   triangles (mesuré : 838 872 sur le probe E1).

---

## 6. Ordre de production conseillé

| Lot | Clips | Effet |
|---|---|---|
| **1** | idle, walk, run, shoot_idle, shoot_walk_forward, shoot_walk_back, death | Le personnage est jouable et lisible |
| **2** | downed_idle, downed_crawl, revive, get_up, hit_react | La coop tient ses promesses |
| **3** | jump_start, fall_loop, land, dash | Le niveau 2 se lit correctement |
| **4** | interact_hold, open_chest | Les objets du monde répondent |
| **5** | variantes d'école, shotgun, victory, level_up, emotes | La signature et le polish |

Le lot 1 seul change déjà tout : c'est celui qu'on voit 90 % du temps.

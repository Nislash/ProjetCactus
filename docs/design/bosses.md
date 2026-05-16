# Boss design

**Statut** : design validé pour le POC (Golem de cristal niveau 1). Les autres boss héritent des règles communes ci-dessous et apportent leur weak point + recette combo propres. Owner : Machine A (engine/IA) + Machine B (scènes/anim/audio).

## Différences avec un mob

Un mob standard (`enemy_base.gd`) : 1 attaque, mono-phase, queue_free à la mort, status appliqué au 1er hit, healthbar 3D billboard au-dessus de la tête.

Un boss :

| Aspect | Mob | Boss |
|---|---|---|
| Phases HP | 1 | **3** (100→66%, 66→33%, 33→0% enrage) |
| Attaques | 1 | **6 au total**, 2 par phase (1 CaC + 1 distance) ; phase 3 = 2 attaques exclusives |
| Telegraphing | aucun | **chaque attaque a un *tell*** (decal au sol ou anim d'amorce 1-2s) |
| Status (freeze/stun/burn/poison/slow) | appliqué au 1er hit | nécessite **2 applications dans 5 s** pour déclencher |
| Weak point | aucun | **progressif** (cf. ci-dessous) |
| Arène | libre | **lock** quand tous les joueurs sont entrés, unlock à la mort |
| HUD | healthbar 3D billboard | **barre HP unique en haut d'écran**, au-dessus du split-screen, avec nom + portrait (1 seule barre même en 4 joueurs) |
| Musique | musique de niveau | **musique boss** + cinématique cam de présentation au trigger |
| Mort | `queue_free` immédiat | slow-mo 0.3s + anim explosion + drop relique légendaire (lueur) + unlock porte + **écran stats post-combat** |
| Drop | rien (POC) | **1 relique légendaire** garantie depuis le pool `boss_only` (cf `relics.yaml` lignes 711+) |

## Règles communes à tous les boss

### 1. Trois phases (100 % → 0 % HP)

| Phase | Trigger HP | Attaques | Weak point exposé |
|---|---|---|---|
| 1 | 100 % → 66 % | 1 CaC + 1 distance (set A) | 1 zone vulnérable |
| 2 | 66 % → 33 % | 1 nouvelle CaC + 1 nouvelle distance (set B) | 2 zones vulnérables |
| 3 (enrage) | 33 % → 0 % | 2 attaques exclusives plus dévastatrices (set C) | corps entier vulnérable au combo |

Transition de phase = courte animation `phase_transition` (2-3 s), invulnérable pendant la transition, repositionnement camera optionnel.

### 2. Telegraphing systématique

Aucune attaque n'arrive sans avertissement. Selon le type :

- **AoE au sol** : decal clignotant (couleur élément) 1-2 s avant impact
- **Charge / dash** : animation d'amorce visible (body pull-back, son grave) avant déclenchement
- **Projectile lent / shards** : VFX d'invocation au-dessus du boss, lock-on visible
- **Slam (CaC)** : levée du bras 0.8 s, ombre au sol qui s'étend

Règle : **tout joueur attentif peut esquiver une attaque** dès la 1re rencontre. La difficulté vient du *chaining* d'attaques et de la gestion d'agro multi-joueur.

### 3. Résistance aux status

Sur un mob, 1 hit `freeze` → freeze. Sur un boss :

- Il faut **2 applications du même status dans une fenêtre de 5 s** pour qu'il prenne effet
- Durée appliquée = 50 % de la durée mob (un freeze qui dure 4 s sur mob dure 2 s sur boss)
- Pendant l'enrage (phase 3), le boss est **immune** à `stun` et `freeze` (pas à `burn`, `slow`, `poison`)

### 4. Weak point progressif + combo recipe

Chaque boss a une **recette de combo** (2 status élémentaires appliqués dans le bon ordre / la bonne fenêtre) qui le rend vulnérable.

- **Phase 1** : 1 zone du corps exposée (hitbox dédiée, gros bonus de dégât si touchée)
- **Phase 2** : 2 zones exposées
- **Phase 3 enrage** : corps entier vulnérable au combo

Effet du combo réussi (n'importe quelle phase) : **stun 5 s + 15 % HP perdus**. Pendant le stun, weak point grand ouvert → fenêtre offensive collective pour les joueurs.

Cooldown du combo : une fois déclenché, il faut attendre 15 s avant de re-trigger (sinon trivialise le combat).

| Boss | Recette combo | Notes |
|---|---|---|
| Golem de cristal (niveau 1) | `freeze` → `thunder` (dans 3 s) | Les cristaux conduisent → choc structurel |
| Sangsue géante (niveau 2) | TBD | |
| Idole flottante (niveau 3) | TBD | |
| Forgeron infernal (niveau 4) | TBD | |
| Liche bibliothécaire (niveau 5) | TBD | |
| Roi de glace (niveau 6) | TBD | |
| Doppelganger (niveau 7) | TBD | |
| Boss final (niveau 8) | TBD | |

### 5. Lock d'arène

- `Area3D` à l'entrée de la salle boss
- Au moins 1 joueur dans la zone → trigger d'init (caméra de présentation + musique fade-in possible)
- **Tous les joueurs vivants dans la zone** → ferme portes + démarre l'IA boss
- Mort du boss → unlock portes

Si un joueur tombe `DOWNED` avant le lock, il compte comme "présent" (sinon les coop downed bloquent à l'infini).

### 6. HUD boss global

- Layer dédié **au-dessus** des `SubViewportContainer` (couche globale, pas par viewport)
- Composé de : nom du boss (haut centre), portrait à gauche, barre HP large, indicateurs de phase (pips ou changement de couleur)
- Apparaît à l'init (fade-in 0.5 s), disparaît à la mort (fade-out 0.5 s)
- En 4 joueurs split-screen, occupe ~80 % de la largeur de l'écran physique, hauteur ~10 %

### 7. Mort et récompenses

Séquence :

1. HP atteint 0 → **slow-mo 0.3 s** (Engine.time_scale = 0.3)
2. Anim de mort spectaculaire (explosion de cristaux pour le Golem)
3. Drop de la **relique légendaire** (random du pool `boss_only`) avec lueur dorée + son distinctif
4. Unlock portes de l'arène
5. **Écran stats post-combat** (overlay global) :
   - Temps de combat (mm:ss)
   - % de dégâts infligés par chaque joueur (camembert ou bars)
   - Relique droppée (nom + icône + rareté)
   - Bouton "Continuer" (input commun à tous les joueurs : tout joueur peut valider)

## Spec POC — Golem de cristal (niveau 1)

### Stats

- **HP total** : 500 (placeholder, à équilibrer en M3)
- **Taille** : ~6 m de haut (4× la taille d'un joueur), ~2-2.5 m de rayon
- **Vitesse de déplacement** : lent (2 m/s base, 3.5 m/s en enrage)
- **Pattern d'agro** : cible le joueur avec le plus de dégâts cumulés sur lui (focus tank), switch toutes les 8 s

### Arène

- Salle : `level_01_poc/RoomBoss`, agrandie à **~35×35 m**, hauteur plafond ~12 m
- **Colonnes de cristal** sur les côtés (4-6 colonnes) : cover visuel + obstacles tactiques
- Entrée au sud (porte vers RoomLoot), pas d'autre sortie avant la mort

### Attaques par phase

**Phase 1 (100 → 66 % HP)**

- *Slam (CaC)* : le Golem lève les 2 poings et frappe le sol → AoE circulaire 4 m de rayon, 30 dégâts. Tell : levée des bras 0.8 s + ombre au sol.
- *Lancer de cailloux (distance)* : invoque 3 rochers au-dessus de lui et les lance en cône vers le joueur ciblé. 20 dégâts/rocher. Tell : VFX cristaux qui s'agglomèrent 1.2 s.

**Phase 2 (66 → 33 % HP)**

- *Charge cristalline (CaC)* : pull-back 1 s, charge en ligne droite sur 15 m. 50 dégâts au contact, knockback. Tell : body pull-back + son grave.
- *Pluie de shards (distance)* : 6 decals au sol clignotent 1.5 s puis impactent. 25 dégâts par shard. Couvre l'arène pour forcer le mouvement.

**Phase 3 enrage (33 → 0 % HP)**

- *Onde de choc (CaC AoE)* : frappe le sol → onde concentrique qui s'étend sur tout l'arène en 2 s. 40 dégâts. Sautable en se mettant sur une colonne cassée. Tell : flash blanc + son strident.
- *Faisceau cristallin (distance)* : laser élémentaire qui balaye l'arène en 3 s. 60 dégâts/s en contact. Tell : laser de visée rouge 1.5 s avant.

### Weak point + combo

- **Phase 1** : 1 cristal sur le dos exposé
- **Phase 2** : 2 cristaux (dos + torse)
- **Phase 3** : tout le corps vulnérable au combo

Combo : `freeze` (avec 2 hits glace dans 5 s) → `thunder` (1 hit foudre dans les 3 s qui suivent le freeze) → **stun 5 s + 15 % HP perdus + cristaux explosent en VFX**.

### Drop

- 1 relique légendaire random du pool `boss_only` (5 dispos dans `relics.yaml`)

### Musique / cam

- Cam de présentation : 3 s, plan rapproché sur le Golem qui se réveille (anim `wake_up`)
- Musique : `audio/music/boss_golem.ogg` (TBD), démarre en fade-in pendant la cam de présentation

## Implémentation — répartition machines

- **Machine A** (engine) :
  - `BossData.tres` resource (HP, phases, attaques, weak point recipe)
  - `boss_base.gd` (extends `EnemyBase`) : state machine 3 phases, résistance status, weak point, lock arène
  - HUD boss global (overlay top-screen)
  - Écran post-combat stats
  - `rust/src/boss_ai.rs` : IA Rust gdext (issue #62)
  - Drop relique légendaire (issue #64)
- **Machine B** (content) :
  - Agrandissement `RoomBoss` + colonnes
  - Scène `boss_golem.tscn` + mesh placeholder + anims + audio (issue #63)
  - VFX cristaux / explosion mort

## Refs

- `docs/design/levels.md` — boss par niveau, thèmes
- `docs/design/relics.yaml` — pool legendary boss_only (lignes 711+)
- `docs/design/magic_schools.md` — éléments pour les combo recipes
- Issues : #62 (IA Rust), #63 (scène boss), #64 (drop relique)

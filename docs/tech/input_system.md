# Input system

**Statut : STUB — à concrétiser au M1.** Owner : Machine A.

## Principes

- **Manettes USB uniquement** (Xbox, PS, génériques XInput). Pas de clavier/souris en jeu.
- 1 à 4 joueurs, attribution dynamique au lobby
- Un seul script central pour router les inputs : **`InputRouter` (autoload)**
- Jamais d'appel direct à `Input.is_action_pressed(...)` dans les scripts joueur — toujours `InputRouter.get_action(player_id, "action_name")`

## Lobby d'attribution

1. Scène lobby affichée au démarrage de partie (et en hot-plug pendant un run en cours, bonus)
2. Chaque manette détectée affiche un slot "Press Start to join"
3. Un appui sur `Start` enregistre la manette → `PlayerManager.register_player(device_id)` → renvoie `player_id` (0-3)
4. Quand 1-4 joueurs ready, on lance le run

## Mapping (à finaliser)

| Action | Bouton (Xbox-like) |
|---|---|
| `move` | Stick gauche |
| `look` | Stick droit |
| `shoot` | RT |
| `cast_spell` | LT |
| `combo_swap` | LB / RB |
| `jump` | A |
| `dash` | B |
| `interact` (revive, coffre) | X (hold) |
| `pause` | Start |

## Hot-plug (phase 2 ou bonus M1)

- Manette branchée en cours de partie → toast "Press Start to join" si moins de 4 joueurs
- Manette débranchée → pause automatique si c'est un joueur actif, sinon ignore

## Tests

- Test physique avec 2/3/4 manettes différentes (Xbox, PS, générique)
- Vérifier que joueur 1 ne déclenche pas d'action sur joueur 2 quand il appuie sur RT


---

## Bascule de vue (● Opus, 2026-08-09)

`toggle_view` — **croix bas** de la manette, à côté de `toggle_map` (croix haut) : ce sont les deux
réglages de confort qu'on change en jouant.

**Par manette, pas globalement.** Chaque joueur ayant déjà son propre viewport, rien n'empêche l'un de
jouer en vue subjective pendant que l'autre voit son personnage. Deux personnes sur le même canapé
n'ont pas la même préférence, et l'une ne doit pas imposer la sienne à l'autre.

**Persistance.** Comme le saut d'onboarding, c'est une exception étroite à la règle roguelike : un
booléen de confort, aucun avantage, réversible. Même fichier (`user://onboarding.cfg`), section
distincte. La clé est le **nom** de la manette et non son index — rebrancher les manettes dans un
autre ordre ferait sinon tout oublier.

**La vue subjective reste le défaut** : c'est celle sur laquelle le jeu est calibré (visée au
réticule, tir ami, telegraphs au sol). La troisième personne est un confort qu'on choisit, pas un
mode qu'on subit.

### Comment c'est fait

La caméra réelle vit dans le SubViewport du joueur et suit un `RemoteTransform3D` resté dans le
personnage. Changer de vue revient donc à **déplacer ce relais** : sous le pivot en vue subjective, au
bout d'un `SpringArm3D` en troisième personne. Le reste du jeu ne voit aucune différence — on tire
toujours depuis le pivot, la visée n'est pas touchée.

Le bras est un `SpringArm3D` et non un simple décalage : sans lui, la caméra traverserait la roche dès
qu'on se colle à une paroi, ce qui arrive en permanence dans une caverne. Son masque de collision est
restreint au **décor** : sur la couche des joueurs, un allié qui passe derrière ferait sauter la vue
d'un mètre toutes les dix secondes.


---

## Menu de pause (● Opus, 2026-08-20)

`pause` — **Start**, la même touche qu'au lobby, et le même réflexe que sur n'importe quelle console.

**N'importe quelle manette inscrite ouvre le menu**, et le joueur qui a appuyé est nommé à l'écran,
dans sa couleur de slot : à quatre autour d'un écran, savoir à qui parler évite la moitié des « c'est
qui qui a mis pause ? ». La navigation passe ensuite par les actions `ui_*` (croix + A/B, tous
devices), comme au lobby — réserver le curseur à la seule manette qui a mis en pause serait plus
rigoureux et plus frustrant : c'est systématiquement quelqu'un d'autre qui veut baisser le son.

**Un seul point de bascule.** `PauseMenu._process` lit Start via `InputRouter` et bascule
ouvert/fermé au même endroit. Le lire à deux endroits rouvrirait le menu dans la frame de sa propre
fermeture.

**Le menu refuse de s'ouvrir** quand un écran de fin attend déjà un appui (game over, stats de boss),
ou quand l'arbre est déjà gelé par quelqu'un d'autre : deux écrans sur le même bouton, c'est un des
deux qui gagne au hasard — et fermer le menu dégèlerait ce que l'autre gelait.

### Ce que la pause gèle

`get_tree().paused = true` arrête le monde, les ennemis, les timers, les tweens, l'audio et les
`_physics_process` des joueurs. Personne ne tire ni ne se fait toucher pendant que le menu est ouvert
— le tir ami est actif, la question n'est pas théorique.

Le nœud `PauseMenu` est en `PROCESS_MODE_ALWAYS` : c'est ce qui lui permet de relire Start pour
reprendre. Le pont d'outillage (`MCPBridge`) est passé au même mode, sinon captures d'écran et
inspection de l'arbre tombent en panne exactement quand on veut regarder l'écran de pause.

**Retour au menu** clôt le run (`RunState.end_run(REASON_QUIT)` puis `reset()`) comme le fait l'écran
de game over, et dégèle l'arbre **avant** de changer de scène : `paused` est porté par le SceneTree,
pas par la scène — le lobby s'ouvrirait figé.

### Réglages accessibles depuis la pause

| Réglage | Portée | Stockage |
|---|---|---|
| Volume général | machine | `user://settings.cfg`, `[audio]` |
| Sensibilité de visée | toutes les manettes | `user://settings.cfg`, `[gameplay]` |
| Vue subjective / 3e personne | la manette qui a mis en pause | `user://onboarding.cfg`, `[view]` |

Le volume et la sensibilité sont **globaux** : il n'y a qu'une paire d'enceintes dans le salon, et une
table qui veut la même difficulté pour tous doit pouvoir fixer la sensibilité une fois. La vue reste
**par manette** (cf section précédente).

La sensibilité s'applique aux joueurs déjà en jeu (`GameSettings.apply_look_sensitivity`) : on ne juge
une sensibilité qu'en bougeant la caméra, attendre le prochain run reviendrait à ne pas pouvoir la
régler. `PlayerController` la relit à son `_ready`, donc elle vaut aussi pour les runs suivants.

Aperçu hors partie : `tools/pause_menu_preview.tscn` ouvre le menu sur un fond sombre et fait défiler
ses trois pages.

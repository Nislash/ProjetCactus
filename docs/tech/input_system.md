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

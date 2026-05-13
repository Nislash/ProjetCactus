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

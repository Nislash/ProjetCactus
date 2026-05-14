# Input drift investigation — Switch Pro Controller (macOS)

**Statut : OUVERT.** Owner : Machine A. Dernière mise à jour : 2026-05-14.

## Contexte

Au M1, l'`InputRouter` (`godot/autoload/input_router.gd`) achemine les axes
de stick vers les actions Godot via le système d'actions standard
(`Input.get_vector(neg_x, pos_x, neg_y, pos_y, DEADZONE)`).

Avec une **manette Xbox One** : RAS, le mouvement répond parfaitement, pas
de drift, pas de latence.

Avec une **Nintendo Switch Pro Controller** sur macOS (connectée en
Bluetooth ou USB, GUID `0300bb977e0500000920000010026803`), un comportement
non-trivial apparait — décrit ci-dessous. Ce doc archive ce qu'on a tenté
et ce qu'on **n'a pas** compris, pour repartir clean en session suivante.

## Symptômes observés

1. **Drift d'arrière au repos** : sans toucher la manette posée à plat, le
   personnage recule lentement après quelques secondes. Magnitude variable
   selon les essais — on a vu de 0.3 à 0.99 sur l'axe `JOY_AXIS_LEFT_Y`.
2. **Délai d'arrêt proportionnel à la durée du mouvement arrière** : quand
   on relâche le stick après avoir reculé, le personnage **continue de
   reculer plus longtemps si on a reculé plus longtemps**. Ce point n'a
   PAS d'explication avec un drift hardware classique (qui serait constant
   indépendamment de l'historique).
3. **Pas observé** sur les axes `move_forward` / `move_left` / `move_right` /
   les sticks de look (right stick). Spécifique au mouvement arrière
   (axe `JOY_AXIS_LEFT_Y` positif).
4. Les autres jeux sur macOS avec la même manette **n'ont pas** ce problème.
   Donc c'est lié à Godot 4.6 / SDL / notre code, pas à la manette.

## Hypothèses examinées

### A. Drift hardware classique (drift constant)
- **Falsifiée** par le point 2 : un drift hardware constant ne dépend pas
  de l'historique récent. Le délai d'arrêt prolongé après un long recul
  suggère un état interne dynamique.

### B. Calibration interne du stick qui dérive
- **Cohérent partiellement** avec le point 2 : certaines manettes Pro ont
  une auto-calibration qui ajuste le "centre" selon la position tenue
  longtemps. Mais ça expliquerait un drift CHANGEANT au cours du temps,
  pas le délai d'arrêt proportionnel.

### C. Friction / inertie du player controller
- **Falsifiée** : la friction est de 60 m/s² sur une vélocité max de 7 m/s
  → 0.12s pour s'arrêter. Constant, indépendant de la durée passée à
  reculer. Le délai observé est plus long que ça.

### D. Smoothing/latence dans Godot SDL backend Mac
- **Plausible et non testée** : SDL2/SDL3 sur macOS peut introduire un
  filtre passe-bas sur les axes, et le filtre peut avoir une fenêtre
  longue qui produit une dépendance à l'historique récent.
- Test à faire : sampling brut via `Input.get_joy_axis(device_id, axis)`
  ET log de la valeur dans le temps. Voir si la valeur d'axis "retarde"
  derrière le retour mécanique du stick.

### E. Bug du système d'actions par joueur (`p{N}_move_back`)
- **Plausible et non testée** : on crée des actions Godot dynamiques avec
  `event.axis_value = 1.0`. Godot peut interpréter ça avec un seuil
  spécifique, et la magnitude de `Input.get_action_strength` peut être
  filtrée différemment qu'un axe brut.
- Test à faire : remplacer `Input.get_vector` par lecture directe
  `Input.get_joy_axis` (sans passer par les actions), et comparer.

### F. Ordre du tree / signal qui produit un effet de mémoire
- **Non vérifié** : peu probable, mais à exclure. Le `_physics_process`
  du player_controller appelle `InputRouter.get_move_vector(player_id)`
  qui lui-même appelle `Input.get_vector(...)`. Pas d'état entre les
  frames de notre côté.

## Ce qu'on a essayé (et qui n'a pas marché)

### 1. Augmenter la deadzone Godot
- 0.2 → 0.25 → 0.3 : drift toujours présent sur la Switch.

### 2. Hard deadzone post-vector (snap à zéro)
- Magnitude < 0.35 → return Vector2.ZERO.
- A absorbé le drift initial (constante) mais **n'a PAS résolu le délai
  d'arrêt proportionnel**. Confirme que le problème n'est pas qu'une
  deadzone trop petite.

### 3. Per-device deadzone (Switch Pro = 0.45)
- Détection par préfixe GUID `0300bb977e05`.
- A absorbé encore plus de drift dans certains cas, mais Robin a continué
  de recule au repos malgré ça → drift > 0.45 dans certaines sessions.
- Pénalisait la sensibilité Switch sans résoudre le délai proportionnel.

### 4. Calibration auto au boot (sample 60 frames + soustraction d'offset)
- À l'inscription d'un device, on lisait `Input.get_joy_axis` pendant 1s
  pour calculer la moyenne = offset à soustraire.
- **CASSÉ** : pendant les premières frames après connect, SDL retourne
  des valeurs bidons (souvent 1.0 par défaut, ou avant le 1er event).
  Résultat : offset calibré à ~0.99 → impossible de reculer du tout
  (axe saturé), le joueur peut juste avancer.
- Conclusion : la calibration au boot n'est pas viable telle quelle.

## Pistes à explorer (session suivante)

### Priorité 1 — Diagnostic brut
Ajouter un mode debug qui LOG les valeurs d'axis brutes en continu :
```gdscript
print(Input.get_joy_axis(device_id, JOY_AXIS_LEFT_Y))
```
- Voir si la valeur "retarde" après un relâchement (test D).
- Voir si la valeur dérive vraiment ou si elle est stable.
- Compare avec un autre input method (mouse, keyboard) en parallèle pour
  isoler.

### Priorité 2 — Bypass système d'actions
Remplacer `get_move_vector` par lecture directe (test E) :
```gdscript
func get_move_vector(pid: int) -> Vector2:
    var device := _player_to_device[pid]
    var raw := Vector2(
        Input.get_joy_axis(device, JOY_AXIS_LEFT_X),
        Input.get_joy_axis(device, JOY_AXIS_LEFT_Y),
    )
    if raw.length() < DEADZONE:
        return Vector2.ZERO
    return raw
```
Comparer le comportement contre la version actuelle.

### Priorité 3 — Calibration dynamique au runtime
Plutôt qu'au boot : surveiller la lecture des axes en continu. Si la
magnitude reste stable (< 0.1 de variance) pendant N secondes
(joueur a relâché), capter ce point comme nouveau "centre" et
soustraire pour les lectures futures. Évite les valeurs bidons du
boot SDL.

### Priorité 4 — Tester sur d'autres modèles
Si possible : DualShock 4, 8BitDo, manette générique XInput. Si seule
la Switch Pro a ce comportement, le bug est dans SDL pour ce GUID
spécifique → workaround documenté.

### Priorité 5 — Forcer un mapping SDL custom
Godot accepte des fichiers SDL2 GameController DB en plus de sa DB
interne. On peut écrire un mapping custom pour la Switch Pro qui
shunte le filtre SDL problématique.

## État actuel du code

À cette date, l'`InputRouter` est volontairement remis dans son état le
plus **minimal** :
- Une seule `DEADZONE = 0.2` uniforme appliquée à tous les devices via
  `Input.get_vector(..., DEADZONE)`.
- Aucun traitement per-device, aucune hard deadzone supplémentaire,
  aucune calibration.

Le problème **n'est pas résolu** — il est juste **isolé pour qu'on puisse
le reproduire et l'investiguer proprement** plutôt que d'empiler des
contournements.

## Pour Stan / co-dev qui reprend

1. Re-lire ce doc.
2. Reproduire le bug sur ton hardware (Switch Pro + macOS).
3. Suivre les "pistes à explorer" dans l'ordre de priorité.
4. Updater ce doc avec ce que tu observes.

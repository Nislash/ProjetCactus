# Assets armes — HUD

Sprites affichés dans le HUD pour représenter l'arme équipée (avec ou sans gemme).

## Convention de nommage

```
{kind}_{element}.png
```

- **`{kind}`** : type d'arme — `gun` (pistolet) ou `sword` (épée)
- **`{element}`** : gemme équipée — `default` (aucune), `fire`, `ice`, `thunder`, `poison`

## Liste des fichiers attendus (10 au total)

### Pistolet
- `gun_default.png` — pistolet de base, sans gemme
- `gun_fire.png` — pistolet boule de feu
- `gun_ice.png` — pistolet givre
- `gun_thunder.png` — pistolet électrique (chain)
- `gun_poison.png` — pistolet toxique (DoT empilable)

### Épée
- `sword_default.png` — épée de base, sans gemme
- `sword_fire.png` — lame enflammée
- `sword_ice.png` — lame gelée
- `sword_thunder.png` — lame foudroyante
- `sword_poison.png` — lame empoisonnée

## Format technique

- **Format** : PNG avec transparence (alpha)
- **Résolution** : 256×256 px ou 512×512 px (sera resized à 96×96 dans le HUD)
- **Style** : icône stylisée, vue de profil ou 3/4. Le fond doit être transparent.
- **Couleurs dominantes** par élément :
  - Feu → orange/rouge
  - Glace → cyan/blanc
  - Foudre → jaune/violet
  - Poison → vert
- **Default** : neutre, pas de teinte élémentaire

## Comportement du HUD

Le HUD `player_hud.gd` charge dynamiquement le sprite via :
```gdscript
var path := "res://assets/textures/weapons/%s_%s.png" % [kind, element]
```

Si le PNG n'existe pas (asset pas encore généré), le HUD ne plante pas — il
affiche juste l'icône vide + le label texte ("Pistolet × Feu").

## Quand ajouter un fichier

Drop le PNG dans ce dossier. Godot le détecte au prochain refresh du
filesystem (Project → Reload Current Project, ou simplement F5).
Le HUD le picke automatiquement à la prochaine sélection d'arme/gemme.

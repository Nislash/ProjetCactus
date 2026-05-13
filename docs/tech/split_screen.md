# Split-screen

**Statut : STUB — à concrétiser au M1.** Owner : Machine A.

## Architecture

```
MainScene
├── SplitScreenManager (Node)
│   ├── ViewportContainer1 (SubViewportContainer)
│   │   └── SubViewport1
│   │       ├── Camera3D (perspective joueur 1)
│   │       ├── HUD1 (CanvasLayer)
│   │       └── (rien d'autre — le monde est partagé)
│   ├── ViewportContainer2
│   ├── ViewportContainer3
│   └── ViewportContainer4
└── World (Node3D)  ← monde 3D unique partagé par toutes les caméras
    ├── Level
    ├── Players (4 max)
    ├── Enemies
    └── ...
```

## Layout adaptatif selon nombre de joueurs

| Joueurs | Layout |
|---|---|
| 1 | 1 viewport plein écran |
| 2 | Split horizontal (haut/bas) sur écran 16:9 ; vertical si écran portrait ou ultrawide |
| 3 | 4 quadrants, le 4e affiche HUD partagé ou est masqué |
| 4 | 4 quadrants |

## Considérations perf

- 4 viewports = 4× le coût de rendu. Le renderer `Forward+` peut souffrir.
- **Fallback `Mobile`** activable si 4-split rame sous 60 fps
- Désactiver les effets coûteux (SSR, GI) à partir de 3 joueurs si nécessaire
- Mesurer dès M1 avec scène vide + 4 caméras

## HUD par viewport

Le HUD de chaque joueur (HP, ammo, sort, mini-map, état combo) vit **dans son SubViewport** pour suivre son champ de vue. Pas de HUD global hors écran lobby / coffre / fin de niveau / pause.

## Tests

- 1 joueur : transition fluide vers split 2 quand un 2e joueur join
- 4 joueurs : 60 fps stable sur GPU de référence

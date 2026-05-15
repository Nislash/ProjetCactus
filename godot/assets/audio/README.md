# Assets audio

## Structure

```
audio/
├── sfx/        # Sons courts (tirs, impacts, pas) — préférer .wav
├── music/      # Musique d'ambiance, boss themes — préférer .ogg
└── ui/         # Sons d'interface (menus, hover, click) — préférer .wav
```

## Formats recommandés (Godot 4)

| Type de son | Format | Pourquoi |
|---|---|---|
| **SFX courts** (<2s) | `.wav` (PCM 16-bit, 44.1 ou 48 kHz, mono) | Qualité brute, décodage instantané, pas de latence |
| **Musique / ambiance** | `.ogg` Vorbis (qualité 5-8) | Compressé (~10% taille WAV), streaming OK |
| **Voix / dialogues** | `.ogg` Vorbis | Compromis qualité/taille |

Godot supporte aussi `.mp3` mais déconseillé en gameplay (latence de décodage).

## Comment ajouter un son

### Exemple : son de lancement de boule de feu

1. Récupérer ou créer un `.wav` court (~0.3–0.8s) — sons synthétiques OK pour M1
2. Le mettre dans : `godot/assets/audio/sfx/fireball_launch.wav`
3. Dans Godot, ouvrir `scenes/combos/fireball.tscn`
4. Sélectionner le node racine `Fireball`
5. Dans l'inspecteur, panneau "Launch Sound" → glisser le `.wav` ici
6. Sauvegarder. Tester en jeu : le son joue à chaque tir.

### Variation par projectile

Pour avoir un son différent par combo (ex: feu vs glace vs foudre), set le
`@export launch_sound` directement sur l'instance du projectile (chaque combo
a sa propre scène, qui peut référencer un son différent).

## LFS

Les fichiers audio binaires sont sous Git LFS via `.gitattributes`
(`*.wav *.ogg *.mp3`). Vérifier avec `git lfs ls-files` après commit.

## Sources de SFX libres

- [freesound.org](https://freesound.org) — CC0/CC-BY, immense bibliothèque
- [zapsplat.com](https://zapsplat.com) — gratuit avec compte
- [opengameart.org](https://opengameart.org) — assets jeu vidéo libres
- Synthétiser avec [BFXR](https://www.bfxr.net/) ou [sfxr](https://www.drpetter.se/project_sfxr.html) — parfait pour SFX rétro/jeu

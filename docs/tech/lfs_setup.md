# Git LFS setup

## Installation (une fois par machine)

```bash
# macOS
brew install git-lfs

# Linux
sudo apt install git-lfs   # ou équivalent

# Windows
# Installeur officiel : https://git-lfs.com/

# Puis sur chaque machine, après clone du repo :
git lfs install
git lfs pull
```

## Quels fichiers sont en LFS

Voir `.gitattributes` à la racine. Aujourd'hui :

- Textures : `.png .jpg .jpeg .tga .exr .hdr .webp .psd`
- Modèles 3D : `.blend .blend1 .fbx .gltf .glb .obj`
- Audio : `.wav .ogg .mp3 .flac`
- Fonts : `.ttf .otf`
- Libs natives Rust compilées : `.dylib .so .dll`

## Workflow normal

- `git add foo.png` → automatiquement géré par LFS si l'extension matche `.gitattributes`
- `git push` → upload sur LFS du remote
- `git pull` → download des LFS objects nécessaires

## Anti-patterns

- ❌ Commiter une grosse texture sans LFS (file > 50 MB sera refusé par GitHub)
- ❌ Modifier `.gitattributes` sans coordonner avec l'autre machine (PR isolée)
- ❌ Faire un `git lfs migrate` sans backup et accord d'équipe

## Vérifier qu'un fichier est bien tracké par LFS

```bash
git lfs ls-files | grep mon_fichier
git lfs status
```

## Quotas

GitHub free LFS = 1 GB storage, 1 GB bandwidth/mois. Si on dépasse, soit on paie LFS data pack, soit on bascule sur un host moins cher (Backblaze B2 via lfs.url custom).

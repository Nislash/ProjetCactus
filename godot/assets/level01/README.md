# `assets/level01/` — assets du niveau 1 « Caverne Cristalline »

Assets générés (Meshy) et matériaux du niveau 1. Tout ce qui atterrit ici doit avoir une entrée dans
[`assets_manifest.yaml`](assets_manifest.yaml) — **pas d'entrée, pas de merge**.

```
level01/
├── assets_manifest.yaml   source de vérité : prompt, task_id, licence, coût, triangles
├── meshes/                .glb importés (LFS)
│   └── src/               géométries de base qu'on retexture (nos meshes, pas ceux de Meshy)
├── textures/              textures autonomes (LFS)
└── materials/             .tres StandardMaterial3D — DATA uniquement, aucune logique
```

## Règles

- **LFS obligatoire** sur les binaires. `.gitattributes` couvre déjà `.glb .obj .fbx .png .jpg`.
  Vérifier avec `git lfs status` avant de commiter qu'un binaire n'est pas passé en clair.
- **Retexture-first** : on part d'une géométrie qu'on maîtrise (`meshes/src/`) ; on ne génère de la
  géométrie que pour les hero assets (landmarks, boss). La topologie générative est imprévisible en
  nombre de triangles, et le jeu tourne en **4 viewports à 60 fps**.
- **Les `.tres` de `materials/` sont de la data**, jamais de la logique (règle `CLAUDE.md`).
- **Licence** : le jeu est propriétaire. Seuls des assets produits sous plan Meshy **payant** (propriété
  pleine) sont admissibles — un asset en CC BY 4.0 imposerait une attribution incompatible.
  Détail : [`docs/tech/meshy_setup.md`](../../../docs/tech/meshy_setup.md) §2.

## Nommage

`<sujet>_<variante>.<ext>` en kebab/snake case : `crystal_wall_a.glb`, `stalactite_small_b.glb`,
`rock_cavern_floor.tres`. Le `name` du manifest = le nom du fichier sans extension.

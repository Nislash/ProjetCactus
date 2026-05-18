# Dungeon Pipeline — ProjetCactus

Pipeline déterministe de génération de niveaux à partir du `topology.drawio`.

## Pourquoi

Première tentative : LLM placé directement des tuiles dans des `.tscn` Godot → défauts géométriques systématiques (escaliers sous des salles fermées, murs au milieu d'ouvertures). Cette pipeline remplace cette approche par une chaîne algo + tests + validation stricte.

Cf `docs/design/levels/PIPELINE_PLAN.md` pour le plan détaillé.

## Pipeline (5 étapes)

```
topology.drawio
   │ parser/drawio_to_json.py  ── classification glyphes + edges, validation strict
   ▼
build/levels.json
   │ layout/force_directed.py  ── force-directed placement + snap grid
   ▼
build/layouts/level_N.json
   │ corridors/{astar,drunkard}.py  ── couloirs normaux + passages secrets
   ▼
build/geometry/level_N.json
   │ validation/checks.py  ── connexité, portes, spawn safe, boss reachable, ...
   ▼  (retry max 10× avec nouveau seed sur échec)
build/geometry/level_N.json (validé)
   │ export/godot_resource.py
   ▼
godot/data/levels/level_N.tres  ── consommé par dungeon_builder.gd (runtime GridMap 3D)
```

## Setup

```bash
cd tools/dungeon_pipeline
python -m venv .venv
source .venv/bin/activate          # macOS/Linux
pip install -e ".[dev]"
```

## Usage

### Étape 1 seule (parser drawio)

```bash
python -m parser.drawio_to_json ../../docs/design/levels/topology.drawio --out build/levels.json
```

### Pipeline complète

```bash
python regenerate_all.py
```

## Tests

```bash
pytest                                # tous les tests
pytest tests/test_parser.py -v        # uniquement le parser
pytest -k "n1" -v                     # uniquement les tests sur N1
```

## Conventions

- **Python 3.11+**, typage statique systématique.
- **Aucune dépendance Godot** côté pipeline (étapes 1-4). Seul `export/godot_resource.py` connaît le format `.tres`.
- **Erreurs explicites** sur toute ambiguïté du drawio plutôt qu'inférence. L'utilisateur patche le drawio puis re-run.
- **Determinisme** : chaque niveau a un seed visible dans le `.tres` ; même seed → même niveau.
- **Pas de magic numbers** : tailles, coûts, paramètres dans `config.json`.

## État

| Étape | Status |
|---|---|
| 1. Parser drawio → JSON | 🔨 en cours |
| 2. Layout force-directed | ⏳ pending |
| 3. Couloirs A* + drunkard | ⏳ pending |
| 4. Validation | ⏳ pending |
| 5. Export Godot | ⏳ pending |

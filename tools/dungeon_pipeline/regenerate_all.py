"""regenerate_all.py — Orchestrateur CLI de la pipeline.

Enchaîne les 5 étapes :
  1. parser   : drawio -> build/levels.json
  2. layout   : (à venir)
  3. corridors: (à venir)
  4. validation: (à venir)
  5. export   : (à venir)

Usage:
    python regenerate_all.py                       # tout enchaîner
    python regenerate_all.py --step parser         # étape 1 seule
    python regenerate_all.py --drawio path/to.drawio
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_DRAWIO = REPO_ROOT / "docs" / "design" / "levels" / "topology.drawio"
BUILD_DIR = Path(__file__).resolve().parent / "build"

STEPS_AVAILABLE = ["parser", "layout", "corridors", "validate"]


def step_parser(drawio: Path, out: Path, strict: bool) -> int:
    from parser.drawio_to_json import main as parser_main
    argv = [str(drawio), "--out", str(out)]
    if strict:
        argv.append("--strict")
    return parser_main(argv)


def step_layout(levels_json: Path, out_dir: Path, seed: int) -> int:
    from layout.force_directed import main as layout_main
    return layout_main([str(levels_json), "--out-dir", str(out_dir), "--seed", str(seed)])


def step_corridors(levels_json: Path, layouts_dir: Path, out_dir: Path, seed: int) -> int:
    from corridors.build_geometry import main as corr_main
    return corr_main([str(levels_json), "--layouts", str(layouts_dir), "--out-dir", str(out_dir), "--seed", str(seed)])


def step_validate(levels_json: Path, layouts_dir: Path, geometry_dir: Path, config_path: Path, max_retries: int, seed_base: int) -> int:
    """Valide tous les niveaux. Sur fail, re-tire layout+corridors avec un seed différent.
    Retourne 0 si tous les niveaux finissent par valider, 1 sinon.
    """
    import json as _json
    from corridors.build_geometry import carve_level_geometry
    from layout.force_directed import layout_level
    from validation.checks import validate_level

    config = _json.loads(config_path.read_text(encoding="utf-8"))
    levels_data = _json.loads(levels_json.read_text(encoding="utf-8"))

    all_ok = True
    for i, lv in enumerate(levels_data["levels"]):
        layout_path = layouts_dir / f"{lv['id']}.json"
        geom_path = geometry_dir / f"{lv['id']}.json"

        layout = _json.loads(layout_path.read_text(encoding="utf-8"))
        geom = _json.loads(geom_path.read_text(encoding="utf-8"))
        res = validate_level(lv, layout, geom)

        attempts = 1
        while not res.ok and attempts <= max_retries:
            new_seed_layout = seed_base + i + attempts * 1000
            new_seed_geom = seed_base + 100 + i + attempts * 1000
            sys.stderr.write(
                f"  ⟲ {lv['name']} retry {attempts}/{max_retries} "
                f"(seed_layout={new_seed_layout}, seed_geom={new_seed_geom})\n"
            )
            layout = layout_level(lv, config, seed=new_seed_layout)
            geom = carve_level_geometry(lv, layout, config, seed=new_seed_geom)
            res = validate_level(lv, layout, geom)
            attempts += 1

        if res.ok:
            # Persiste si différent (retry a réussi à un seed différent).
            layout_path.write_text(_json.dumps(layout, indent=2, ensure_ascii=False), encoding="utf-8")
            geom_path.write_text(_json.dumps(geom, ensure_ascii=False), encoding="utf-8")
            warn_msg = f", {len(res.warnings)} warnings" if res.warnings else ""
            sys.stderr.write(f"  ✓ {lv['name']}: OK{warn_msg}\n")
            for w in res.warnings:
                sys.stderr.write(f"      ⚠ {w}\n")
        else:
            all_ok = False
            sys.stderr.write(f"  ✗ {lv['name']}: échec après {max_retries} retries\n")
            for e in res.errors:
                sys.stderr.write(f"      • {e}\n")
    return 0 if all_ok else 1


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--drawio", type=Path, default=DEFAULT_DRAWIO, help="Source drawio file")
    ap.add_argument("--step", choices=STEPS_AVAILABLE + ["all"], default="all")
    ap.add_argument("--strict", action="store_true", help="Exit 1 if any step errors")
    ap.add_argument("--seed", type=int, default=42, help="Seed pour l'étape layout (chaque niveau N a seed=base+N-1)")
    args = ap.parse_args(argv)

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    levels_json = BUILD_DIR / "levels.json"
    layouts_dir = BUILD_DIR / "layouts"

    if args.step in ("parser", "all"):
        sys.stderr.write("=== Étape 1 : parser drawio -> JSON ===\n")
        rc = step_parser(args.drawio, levels_json, args.strict)
        if rc != 0 and args.strict:
            return rc

    if args.step in ("layout", "all"):
        sys.stderr.write("\n=== Étape 2 : layout force-directed ===\n")
        if not levels_json.exists():
            sys.stderr.write(f"ERREUR: {levels_json} absent. Lance d'abord --step parser.\n")
            return 1
        rc = step_layout(levels_json, layouts_dir, args.seed)
        if rc != 0 and args.strict:
            return rc

    geometry_dir = BUILD_DIR / "geometry"

    if args.step in ("corridors", "all"):
        sys.stderr.write("\n=== Étape 3 : corridors (A* + drunkard) ===\n")
        if not levels_json.exists() or not layouts_dir.exists():
            sys.stderr.write("ERREUR: prérequis manquant (levels.json ou layouts/).\n")
            return 1
        rc = step_corridors(levels_json, layouts_dir, geometry_dir, args.seed + 100)
        if rc != 0 and args.strict:
            return rc

    if args.step in ("validate", "all"):
        sys.stderr.write("\n=== Étape 4 : validation (retry max 10) ===\n")
        if not geometry_dir.exists():
            sys.stderr.write("ERREUR: build/geometry/ absent. Lance d'abord --step corridors.\n")
            return 1
        config = (PIPELINE_DIR := Path(__file__).resolve().parent) / "config.json"
        import json as _json
        max_retries = _json.loads(config.read_text(encoding="utf-8")).get("validation", {}).get("retry_max", 10)
        rc = step_validate(levels_json, layouts_dir, geometry_dir, config, max_retries, args.seed)
        if rc != 0 and args.strict:
            return rc

    return 0


if __name__ == "__main__":
    sys.exit(main())

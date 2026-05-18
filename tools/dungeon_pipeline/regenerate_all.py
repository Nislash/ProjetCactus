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

STEPS_AVAILABLE = ["parser", "layout", "corridors"]


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

    if args.step in ("corridors", "all"):
        sys.stderr.write("\n=== Étape 3 : corridors (A* + drunkard) ===\n")
        if not levels_json.exists() or not layouts_dir.exists():
            sys.stderr.write("ERREUR: prérequis manquant (levels.json ou layouts/).\n")
            return 1
        geometry_dir = BUILD_DIR / "geometry"
        rc = step_corridors(levels_json, layouts_dir, geometry_dir, args.seed + 100)
        if rc != 0 and args.strict:
            return rc

    return 0


if __name__ == "__main__":
    sys.exit(main())

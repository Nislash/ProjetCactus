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

STEPS_AVAILABLE = ["parser"]


def step_parser(drawio: Path, out: Path, strict: bool) -> int:
    from parser.drawio_to_json import main as parser_main
    argv = [str(drawio), "--out", str(out)]
    if strict:
        argv.append("--strict")
    return parser_main(argv)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--drawio", type=Path, default=DEFAULT_DRAWIO, help="Source drawio file")
    ap.add_argument("--step", choices=STEPS_AVAILABLE + ["all"], default="all")
    ap.add_argument("--strict", action="store_true", help="Exit 1 if any step errors")
    args = ap.parse_args(argv)

    BUILD_DIR.mkdir(parents=True, exist_ok=True)
    if args.step in ("parser", "all"):
        rc = step_parser(args.drawio, BUILD_DIR / "levels.json", args.strict)
        if rc != 0 and args.strict:
            return rc
    return 0


if __name__ == "__main__":
    sys.exit(main())

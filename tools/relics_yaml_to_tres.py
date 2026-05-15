#!/usr/bin/env python3
"""Convert docs/design/relics.yaml into 50 Godot .tres resources.

Usage:
    python3 tools/relics_yaml_to_tres.py            # writes godot/resources/relics/*.tres
    python3 tools/relics_yaml_to_tres.py --check    # parse only, no writes

Schema (see CLAUDE.md docs/design/relics.yaml):
    tier        ∈ common/rare/epic/legendary
    effect_type ∈ stat/on_hit/on_kill/on_dash/on_damaged/on_low_hp/on_revive/on_reload/combo_mod/coop
    trigger     ∈ passive/on_hit/on_kill/on_dash/on_damaged/on_low_hp/on_revive/on_reload
    drop_pool   ∈ standard/shop_only/boss_only
"""

from __future__ import annotations

import argparse
import sys
from pathlib import Path

try:
    import yaml
except ImportError:
    sys.stderr.write("Missing PyYAML. Run: pip install pyyaml\n")
    sys.exit(1)


REPO_ROOT = Path(__file__).resolve().parents[1]
YAML_PATH = REPO_ROOT / "docs" / "design" / "relics.yaml"
OUT_DIR = REPO_ROOT / "godot" / "resources" / "relics"

SCRIPT_RES_PATH = "res://scripts/core/data/relic_data.gd"

TIER_ENUM = {"common": 0, "rare": 1, "epic": 2, "legendary": 3}
EFFECT_ENUM = {
    "stat": 0, "on_hit": 1, "on_kill": 2, "on_dash": 3, "on_damaged": 4,
    "on_low_hp": 5, "on_revive": 6, "on_reload": 7, "combo_mod": 8, "coop": 9,
}
TRIGGER_ENUM = {
    "passive": 0, "on_hit": 1, "on_kill": 2, "on_dash": 3, "on_damaged": 4,
    "on_low_hp": 5, "on_revive": 6, "on_reload": 7,
}
DROP_POOL_ENUM = {"standard": 0, "shop_only": 1, "boss_only": 2}


def gdescape(s: str) -> str:
    """Escape a Python string for embedding into a .tres double-quoted literal."""
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def format_dict_literal(d: dict) -> str:
    """Emit a Godot Dictionary literal from a Python dict.

    Keys are emitted as StringName (&"key"). Values: bool/int/float/str/None
    (None → null). No nested structures expected in the relics schema.
    """
    if not d:
        return "{}"
    parts: list[str] = []
    for k, v in d.items():
        key_lit = f'&"{gdescape(str(k))}"'
        parts.append(f"{key_lit}: {format_value(v)}")
    return "{\n" + ",\n".join(f"    {p}" for p in parts) + "\n}"


def format_value(v) -> str:
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return f'"{gdescape(v)}"'
    raise ValueError(f"Unsupported magnitude value type: {type(v).__name__} ({v!r})")


def filter_to_stringname(value) -> str:
    """null/empty → empty StringName; otherwise the string verbatim."""
    if value is None:
        return ""
    s = str(value).strip()
    return s


def emit_tres(relic: dict) -> str:
    rid = relic["id"]
    tier = TIER_ENUM[relic["tier"]]
    effect = EFFECT_ENUM[relic["effect_type"]]
    trigger = TRIGGER_ENUM[relic["trigger"]]
    pool = DROP_POOL_ENUM[relic["drop_pool"]]
    weapon_filter = filter_to_stringname(relic.get("weapon_filter"))
    school_filter = filter_to_stringname(relic.get("school_filter"))
    magnitude = relic.get("magnitude") or {}
    name = relic["name"]
    description = relic.get("description", "")
    flavor = relic.get("flavor", "") or ""

    lines: list[str] = []
    lines.append(
        f'[gd_resource type="Resource" script_class="RelicData" '
        f'load_steps=2 format=3 uid="uid://{rid}"]'
    )
    lines.append("")
    lines.append(f'[ext_resource type="Script" path="{SCRIPT_RES_PATH}" id="1_relic"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_relic")')
    lines.append(f'id = &"{gdescape(rid)}"')
    lines.append(f'display_name = "{gdescape(name)}"')
    lines.append(f'description = "{gdescape(description)}"')
    lines.append(f'flavor = "{gdescape(flavor)}"')
    lines.append(f"tier = {tier}")
    lines.append(f"effect_type = {effect}")
    lines.append(f"trigger = {trigger}")
    lines.append(f"drop_pool = {pool}")
    lines.append(f'weapon_filter = &"{gdescape(weapon_filter)}"')
    lines.append(f'school_filter = &"{gdescape(school_filter)}"')
    lines.append(f"magnitude = {format_dict_literal(magnitude)}")
    lines.append("")
    return "\n".join(lines)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true",
                        help="Validate only, don't write .tres files")
    parser.add_argument("--yaml", type=Path, default=YAML_PATH)
    parser.add_argument("--out", type=Path, default=OUT_DIR)
    args = parser.parse_args()

    with args.yaml.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)

    relics = data.get("relics", [])
    if len(relics) == 0:
        print("[!] No relics found in YAML")
        return 1

    ids = [r["id"] for r in relics]
    dupes = {x for x in ids if ids.count(x) > 1}
    if dupes:
        print(f"[!] Duplicate ids: {dupes}")
        return 2

    counts = {"common": 0, "rare": 0, "epic": 0, "legendary": 0}
    for r in relics:
        counts[r["tier"]] += 1

    print(f"Loaded {len(relics)} relics: "
          f"{counts['common']} common / {counts['rare']} rare / "
          f"{counts['epic']} epic / {counts['legendary']} legendary")

    if args.check:
        # Dry parse: emit each to memory to catch schema issues.
        for r in relics:
            emit_tres(r)
        print("[check] All entries parse cleanly.")
        return 0

    args.out.mkdir(parents=True, exist_ok=True)
    written = 0
    for r in relics:
        out_path = args.out / f"{r['id']}.tres"
        out_path.write_text(emit_tres(r), encoding="utf-8")
        written += 1
    print(f"Wrote {written} .tres files to {args.out.relative_to(REPO_ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())

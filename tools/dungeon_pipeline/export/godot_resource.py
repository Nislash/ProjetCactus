"""godot_resource.py — Étape 5 de la pipeline. Sérialise un niveau en `.tres`.

Format ciblé : Godot 4 Resource format (`[gd_resource ...]` headers).

La ressource a la forme :
    [gd_resource type="Resource" script_class="LevelLayout" load_steps=2 format=3]
    [ext_resource type="Script" path="res://scripts/world/level_layout.gd" id="1_layout"]
    [resource]
    script = ExtResource("1_layout")
    level_id = "level_1"
    seed = 100
    grid_size = Vector3i(52, 3, 60)
    cell_size = Vector3(4, 3, 4)
    strata = ["-2", "-1", "0"]
    rooms = { ... }
    cells = PackedByteArray(...)
    doors = [...]
    stairs = [...]
    contents = { ... }
    inter_level = { ... }

`cells` est un PackedByteArray plat de taille (strata_count × width × depth)
où chaque octet encode un tile_id selon TILE_ID_BY_TAG.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

# ============================================================================
# Encodage tile → tile_id (1 octet)
# ============================================================================

TILE_ID_BY_TAG: dict[str, int] = {
    "void":          0,
    "floor":         1,
    "wall":          2,
    "corridor":      3,
    "secret":        4,
    "door":          5,
    "boss_door":     6,
    "secret_door":   7,
    "stair_up":      8,
    "stair_down":    9,
    "drop":          10,
    "drop_landing":  11,
    "jump_pad":      12,
    "drift":         13,
}

# Ordre canonique des strates (de la plus basse à la plus haute) pour l'axe Y.
STRATA_ORDER = ["-2", "-1", "0", "+1", "+2", "+3", "+4"]


def _stratum_to_y_index(stratum: str) -> int:
    """Convertit une strate en index Y (0 = la plus basse présente)."""
    return STRATA_ORDER.index(stratum)


# ============================================================================
# Sérialisation atomique vers syntaxe .tres
# ============================================================================

def _esc_str(s: str) -> str:
    return s.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n")


def _serialize_value(v) -> str:
    """Sérialise une valeur Python en syntaxe .tres."""
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "true" if v else "false"
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return f'"{_esc_str(v)}"'
    if isinstance(v, list):
        return "[" + ", ".join(_serialize_value(x) for x in v) + "]"
    if isinstance(v, dict):
        items = ", ".join(f'"{_esc_str(k)}": {_serialize_value(val)}' for k, val in v.items())
        return "{" + items + "}"
    raise TypeError(f"Type non sérialisable : {type(v).__name__}")


def _serialize_packed_byte_array(values: list[int]) -> str:
    return "PackedByteArray(" + ", ".join(str(v) for v in values) + ")"


def _serialize_vec3i(x: int, y: int, z: int) -> str:
    return f"Vector3i({x}, {y}, {z})"


def _serialize_vec3(x: float, y: float, z: float) -> str:
    return f"Vector3({x}, {y}, {z})"


# ============================================================================
# Conversion d'un niveau (level + layout + geometry) en .tres
# ============================================================================

def build_resource_data(level: dict, layout: dict, geometry: dict, config: dict) -> dict:
    """Construit le dict de champs à sérialiser dans le .tres."""
    g_size = geometry["grid_size"]
    width = g_size["x"] + 1
    depth = g_size["z"] + 1

    present_strata = sorted(
        (s for s in geometry["strata"]),
        key=lambda s: _stratum_to_y_index(s) if s in STRATA_ORDER else 99,
    )
    height = len(present_strata)
    stratum_to_y = {s: i for i, s in enumerate(present_strata)}

    # Aplatir les cells en PackedByteArray : index = y * (depth*width) + z * width + x.
    cells_flat: list[int] = [0] * (height * width * depth)
    for s, gd in geometry["strata"].items():
        y = stratum_to_y[s]
        for z in range(gd["depth"]):
            for x in range(gd["width"]):
                if x >= width or z >= depth:
                    continue
                tag = gd["cells"][z * gd["width"] + x]
                tid = TILE_ID_BY_TAG.get(tag, 0)
                idx = y * (depth * width) + z * width + x
                cells_flat[idx] = tid

    # Rooms : dict id → {x, y, z, w, h, d, stratum, type}
    rooms_out: dict[str, dict] = {}
    for rid, r in layout["rooms"].items():
        rooms_out[rid] = {
            "x": r["x"],
            "y": stratum_to_y[r["stratum"]] if r["stratum"] in stratum_to_y else 0,
            "z": r["z"],
            "w": r["w"],
            "h": 1,  # 1 cellule de haut par strate
            "d": r["d"],
            "stratum": r["stratum"],
            "type": r["type"],
        }

    # Doors : Array de dict
    doors_out: list[dict] = []
    for door in level["doors"]:
        d_layout = layout["rooms"].get(door["id"])
        if d_layout is None:
            continue
        doors_out.append({
            "id": door["id"],
            "x": d_layout["x"],
            "y": stratum_to_y[d_layout["stratum"]],
            "z": d_layout["z"],
            "locked": door["locked"],
            "unlock_keys": door["unlock_keys"],
        })

    # Stairs : edges_resolved verticaux (stairs/ladder/elevator/jump/drop)
    stairs_out: list[dict] = []
    for e in geometry["edges_resolved"]:
        if "stratum_from" not in e:
            continue
        stairs_out.append({
            "kind": e["kind"],
            "from_room": e["from"],
            "to_room": e["to"],
            "from_x": e["pos_from"][0],
            "from_y": stratum_to_y[e["stratum_from"]],
            "from_z": e["pos_from"][1],
            "to_x": e["pos_to"][0],
            "to_y": stratum_to_y[e["stratum_to"]],
            "to_z": e["pos_to"][1],
        })

    # Contents par room
    contents_out: dict[str, dict] = {}
    for rid, c in level["contents"].items():
        out = {}
        if c.get("spawn"):
            out["spawn"] = True
        if c.get("mini_boss"):
            out["mini_boss"] = True
        if c.get("loot_major"):
            out["loot_major"] = c["loot_major"]
        if c.get("meta_fragment"):
            out["meta_fragment"] = True
        if c.get("checkpoint"):
            out["checkpoint"] = True
        if c.get("puzzle_triggers"):
            out["puzzle_triggers"] = list(c["puzzle_triggers"])
        if out:
            contents_out[rid] = out

    cell_size_world = config["grid"]["cell_size_world"]

    return {
        "level_id": level["id"],
        "level_name": level["name"],
        "seed": geometry["seed"],
        "grid_size": (width, height, depth),
        "cell_size": tuple(cell_size_world),
        "strata": present_strata,
        "spawn_room": level["spawn_room"],
        "rooms": rooms_out,
        "cells": cells_flat,
        "doors": doors_out,
        "stairs": stairs_out,
        "contents": contents_out,
        "inter_level": level.get("inter_level") or {},
    }


def render_tres(data: dict, script_path: str = "res://scripts/world/level_layout.gd") -> str:
    """Sérialise un dict (issu de build_resource_data) en texte .tres."""
    lines: list[str] = []
    lines.append('[gd_resource type="Resource" script_class="LevelLayout" load_steps=2 format=3]')
    lines.append("")
    lines.append(f'[ext_resource type="Script" path="{script_path}" id="1_layout"]')
    lines.append("")
    lines.append("[resource]")
    lines.append('script = ExtResource("1_layout")')
    lines.append(f'level_id = "{_esc_str(data["level_id"])}"')
    lines.append(f'level_name = "{_esc_str(data["level_name"])}"')
    lines.append(f'seed = {data["seed"]}')
    gw, gh, gd = data["grid_size"]
    lines.append(f"grid_size = {_serialize_vec3i(gw, gh, gd)}")
    cs = data["cell_size"]
    lines.append(f"cell_size = {_serialize_vec3(cs[0], cs[1], cs[2])}")
    lines.append(f'strata = {_serialize_value(data["strata"])}')
    lines.append(f'spawn_room = "{_esc_str(data["spawn_room"])}"')
    lines.append(f'rooms = {_serialize_value(data["rooms"])}')
    lines.append(f'cells = {_serialize_packed_byte_array(data["cells"])}')
    lines.append(f'doors = {_serialize_value(data["doors"])}')
    lines.append(f'stairs = {_serialize_value(data["stairs"])}')
    lines.append(f'contents = {_serialize_value(data["contents"])}')
    lines.append(f'inter_level = {_serialize_value(data["inter_level"])}')
    return "\n".join(lines) + "\n"


# ============================================================================
# CLI
# ============================================================================

def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("input", type=Path, help="Chemin vers build/levels.json")
    ap.add_argument("--layouts", type=Path, default=None)
    ap.add_argument("--geometry", type=Path, default=None)
    ap.add_argument("--config", type=Path, default=None)
    ap.add_argument("--out-dir", type=Path, default=None, help="Dossier de sortie pour .tres")
    ap.add_argument("--script-path", default="res://scripts/world/level_layout.gd")
    args = ap.parse_args(argv)

    if args.config is None:
        args.config = args.input.parent.parent / "config.json"
    if args.layouts is None:
        args.layouts = args.input.parent / "layouts"
    if args.geometry is None:
        args.geometry = args.input.parent / "geometry"
    if args.out_dir is None:
        args.out_dir = args.input.parent / "godot_resources"
    args.out_dir.mkdir(parents=True, exist_ok=True)

    config = json.loads(args.config.read_text(encoding="utf-8"))
    levels_data = json.loads(args.input.read_text(encoding="utf-8"))

    for lv in levels_data["levels"]:
        layout = json.loads((args.layouts / f"{lv['id']}.json").read_text(encoding="utf-8"))
        geometry = json.loads((args.geometry / f"{lv['id']}.json").read_text(encoding="utf-8"))
        data = build_resource_data(lv, layout, geometry, config)
        text = render_tres(data, script_path=args.script_path)
        out_path = args.out_dir / f"{lv['id']}.tres"
        out_path.write_text(text, encoding="utf-8")
        cells_count = sum(1 for c in data["cells"] if c != 0)
        sys.stderr.write(
            f"  ✓ {lv['name']}: {out_path.name} grid {data['grid_size']} "
            f"{cells_count} cellules non-vides, {len(data['rooms'])} rooms, "
            f"{len(data['doors'])} doors, {len(data['stairs'])} stairs\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

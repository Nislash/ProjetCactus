"""build_geometry.py — Orchestrateur de l'étape 3.

Prend en entrée le JSON parser (build/levels.json) et les layouts
(build/layouts/level_N.json), produit la géométrie 2D par strate :

- Stamp les rooms (FLOOR intérieur, WALL périphérie),
- Pour chaque edge :
  * corridor/stairs/ladder/elevator/jump : A* + tag de transition,
  * secret_passage : drunkard's walk,
  * one_way_drop : tuile DROP + corridor jusqu'à room cible,
  * zero_g_drift : pas de creusement, tag DRIFT aux 2 endpoints.
- Place portes (DOOR / BOSS_DOOR) sur le mur de room à l'endroit du couloir.
- Output : build/geometry/level_N.json
  {
    level_id, seed, grid_size: {x, z},
    strata: {
      "0":  {width, depth, cells: [...], owners: [...]},
      "-1": ...
    },
    edges_resolved: [...]   # avec waypoints
  }

Usage:
    python -m corridors.build_geometry build/levels.json [--layouts build/layouts] [--out-dir build/geometry]
"""
from __future__ import annotations

import argparse
import json
import random
import sys
from pathlib import Path

from .astar import astar_corridor, carve_corridor
from .drunkard import carve_drunkard, drunkard_walk
from .grid import (
    BOSS_DOOR,
    DOOR,
    DRIFT,
    DROP,
    FLOOR,
    Grid,
    JUMP_PAD,
    STAIR_DOWN,
    STAIR_UP,
    WALL,
    VOID,
)


# Edges qui demandent un couloir A* horizontal.
A_STAR_KINDS = {"corridor", "locked_passage"}
# Edges verticales : on creuse aussi un A* horizontal vers la position,
# puis on tag la cellule en stair/elevator/ladder.
VERTICAL_KINDS = {"stairs", "ladder", "elevator", "jump_required"}
DROP_KINDS = {"one_way_drop"}
SECRET_KINDS = {"secret_passage"}
ZERO_G_KINDS = {"zero_g_drift"}


def _door_slot(room: dict, target: dict) -> tuple[int, int]:
    """Trouve la cellule de mur de `room` la plus proche du centre de `target`."""
    rx, rz, rw, rd = room["x"], room["z"], room["w"], room["d"]
    tcx = target["x"] + target["w"] / 2
    tcz = target["z"] + target["d"] / 2

    # 4 candidates : centre de chaque mur (haut/bas/gauche/droite).
    candidates = [
        (rx + rw // 2, rz, "top"),                # haut
        (rx + rw // 2, rz + rd - 1, "bottom"),    # bas
        (rx, rz + rd // 2, "left"),               # gauche
        (rx + rw - 1, rz + rd // 2, "right"),     # droite
    ]
    # Choisit la plus proche du target.
    best = min(candidates, key=lambda c: (c[0] - tcx) ** 2 + (c[1] - tcz) ** 2)
    return best[0], best[1]


def _step_out_of_wall(room: dict, wall_pos: tuple[int, int]) -> tuple[int, int]:
    """Donne la cellule extérieure adjacente au slot mur."""
    rx, rz, rw, rd = room["x"], room["z"], room["w"], room["d"]
    wx, wz = wall_pos
    if wx == rx:
        return wx - 1, wz
    if wx == rx + rw - 1:
        return wx + 1, wz
    if wz == rz:
        return wx, wz - 1
    return wx, wz + 1


def build_strata_grids(layout: dict) -> dict[str, Grid]:
    """Crée une Grid par strate, avec rooms stampées."""
    g_size = layout["grid_size"]
    width, depth = g_size["x"] + 1, g_size["z"] + 1

    strata: dict[str, Grid] = {}
    for rid, r in layout["rooms"].items():
        s = r["stratum"]
        if s not in strata:
            strata[s] = Grid(width=width, depth=depth)
        # On stamp seulement les "vraies" rooms et les boss_arena/corridor.
        # Les doors ont type="door" et sont placées différemment.
        if r["type"] == "door":
            continue
        strata[s].stamp_room(rid, r["x"], r["z"], r["w"], r["d"])
    return strata


def _stratum_diff(stratum_a: str, stratum_b: str) -> int:
    """Retourne la diff numérique (b - a). Ex: -1 → +1 = 2."""
    def parse(s: str) -> int:
        s = s.replace("+", "").replace("−", "-")
        try:
            return int(s)
        except ValueError:
            return 0
    return parse(stratum_b) - parse(stratum_a)


def resolve_edge_endpoints(edge: dict, layout: dict) -> tuple[dict, dict]:
    """Retourne (room_from, room_to) en sautant les doors si l'edge en pointe une.

    Une boss_door se présente comme une room intermédiaire de type 'door' ;
    on remappe sur la room "réelle" de chaque côté en trouvant les edges
    qui pointent vers le door_id.
    """
    return layout["rooms"][edge["from"]], layout["rooms"][edge["to"]]


def carve_level_geometry(
    level: dict,
    layout: dict,
    config: dict,
    seed: int = 100,
) -> dict:
    """Construit la géométrie complète d'un niveau."""
    strata = build_strata_grids(layout)
    rng = random.Random(seed)
    edges_resolved: list[dict] = []

    astar_cfg = config.get("astar", {})
    drunkard_cfg = config.get("drunkard", {})
    wall_penalty = astar_cfg.get("wall_adjacency_penalty", 5)

    # Indexation des rooms par id (couvre rooms + doors via layout).
    by_id = layout["rooms"]

    for edge in level["edges"]:
        kind = edge["kind"]
        a = by_id.get(edge["from"])
        b = by_id.get(edge["to"])
        if a is None or b is None:
            continue

        # Cas zéro-G : pas de creusement, on tague juste les centres.
        if kind in ZERO_G_KINDS:
            for room in (a, b):
                grid = strata.get(room["stratum"])
                if grid is None:
                    continue
                cx = room["x"] + room["w"] // 2
                cz = room["z"] + room["d"] // 2
                if grid.get(cx, cz) == FLOOR:
                    grid.set(cx, cz, DRIFT, owner=grid.owner(cx, cz))
            edges_resolved.append({"from": edge["from"], "to": edge["to"], "kind": kind, "carved": False})
            continue

        # Pour les autres kinds, on creuse dans la strate de A (point d'entrée principal).
        diff = _stratum_diff(a["stratum"], b["stratum"])

        if a["stratum"] == b["stratum"]:
            # Même strate : couloir simple A* sur cette strate.
            grid = strata[a["stratum"]]
            slot_a = _door_slot(a, b)
            slot_b = _door_slot(b, a)
            ext_a = _step_out_of_wall(a, slot_a)
            ext_b = _step_out_of_wall(b, slot_b)
            forbidden = {rid for rid in by_id if rid not in (edge["from"], edge["to"]) and by_id[rid]["type"] != "door" and by_id[rid]["stratum"] == a["stratum"]}

            if kind in SECRET_KINDS:
                path = drunkard_walk(
                    grid, ext_a, ext_b, rng,
                    length_factor_min=drunkard_cfg.get("length_factor_min", 1.5),
                    length_factor_max=drunkard_cfg.get("length_factor_max", 2.0),
                    target_bias=drunkard_cfg.get("target_bias", 0.3),
                    max_iterations=drunkard_cfg.get("max_iterations", 200),
                )
                if path is None:
                    # Fallback A* si drunkard bloqué.
                    path = astar_corridor(grid, ext_a, ext_b, wall_penalty, forbidden_owners=forbidden)
                if path:
                    carve_drunkard(grid, path)
                    _place_door(grid, slot_a, secret=True)
                    _place_door(grid, slot_b, secret=True)
            else:
                path = astar_corridor(grid, ext_a, ext_b, wall_penalty, forbidden_owners=forbidden)
                if path:
                    carve_corridor(grid, path)
                    _place_door(grid, slot_a, locked=(kind == "locked_passage"))
                    _place_door(grid, slot_b, locked=(kind == "locked_passage"))

            edges_resolved.append({
                "from": edge["from"], "to": edge["to"], "kind": kind,
                "carved": path is not None, "stratum": a["stratum"],
                "waypoints_count": len(path) if path else 0,
            })
            continue

        # Strates différentes : transition verticale.
        # On place le marker de transition au centre de chaque room aux 2 strates.
        # (L'extrusion 3D côté Godot connectera les 2 cellules sur l'axe Y.)
        grid_a = strata[a["stratum"]]
        grid_b = strata[b["stratum"]]
        cax = a["x"] + a["w"] // 2
        caz = a["z"] + a["d"] // 2
        cbx = b["x"] + b["w"] // 2
        cbz = b["z"] + b["d"] // 2

        up_tag = STAIR_UP if diff > 0 else STAIR_DOWN
        if kind == "jump_required":
            up_tag = JUMP_PAD
        elif kind in DROP_KINDS:
            up_tag = DROP

        # Sur la strate A : marquer la cellule centrale comme transition (préserve FLOOR autour).
        if grid_a.get(cax, caz) == FLOOR:
            grid_a.set(cax, caz, up_tag, owner=grid_a.owner(cax, caz))
        # Sur la strate B : marquer la cellule centrale comme l'inverse.
        down_tag = STAIR_DOWN if diff > 0 else STAIR_UP
        if kind == "jump_required":
            down_tag = JUMP_PAD
        elif kind in DROP_KINDS:
            down_tag = "drop_landing"
        if grid_b.get(cbx, cbz) == FLOOR:
            grid_b.set(cbx, cbz, down_tag, owner=grid_b.owner(cbx, cbz))

        edges_resolved.append({
            "from": edge["from"], "to": edge["to"], "kind": kind,
            "carved": True,
            "stratum_from": a["stratum"], "stratum_to": b["stratum"],
            "stratum_diff": diff,
            "pos_from": [cax, caz], "pos_to": [cbx, cbz],
        })

    # Place les boss_doors comme verrou sur la dernière edge entrante.
    for door in level["doors"]:
        if not door["locked"]:
            continue
        # Trouve la room voisine non-door qui contient une edge vers le door.
        # Le door a sa propre cellule centrale, on tag BOSS_DOOR.
        d_layout = layout["rooms"].get(door["id"])
        if d_layout is None:
            continue
        grid = strata.get(d_layout["stratum"])
        if grid is None:
            continue
        cx = d_layout["x"] + d_layout["w"] // 2
        cz = d_layout["z"] + d_layout["d"] // 2
        grid.set(cx, cz, BOSS_DOOR, owner=door["id"])

    return {
        "level_id": layout["level_id"],
        "seed": seed,
        "grid_size": layout["grid_size"],
        "strata": {
            s: {
                "width": g.width,
                "depth": g.depth,
                "cells": g.cells,
                "owners": g.owners,
            } for s, g in strata.items()
        },
        "edges_resolved": edges_resolved,
    }


def _place_door(grid: Grid, pos: tuple[int, int], *, locked: bool = False, secret: bool = False) -> None:
    tag = BOSS_DOOR if locked else DOOR
    if secret:
        tag = "secret_door"
    grid.set(pos[0], pos[1], tag, owner=grid.owner(pos[0], pos[1]))


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("input", type=Path, help="Chemin vers build/levels.json")
    ap.add_argument("--layouts", type=Path, default=None, help="Dossier des layouts (défaut: <input_dir>/layouts)")
    ap.add_argument("--config", type=Path, default=None)
    ap.add_argument("--out-dir", type=Path, default=None, help="Dossier de sortie (défaut: <input_dir>/geometry)")
    ap.add_argument("--seed", type=int, default=100)
    args = ap.parse_args(argv)

    if args.config is None:
        args.config = args.input.parent.parent / "config.json"
    if args.layouts is None:
        args.layouts = args.input.parent / "layouts"
    if args.out_dir is None:
        args.out_dir = args.input.parent / "geometry"
    args.out_dir.mkdir(parents=True, exist_ok=True)

    config = json.loads(args.config.read_text(encoding="utf-8"))
    levels_data = json.loads(args.input.read_text(encoding="utf-8"))

    for i, lv in enumerate(levels_data["levels"]):
        layout_path = args.layouts / f"{lv['id']}.json"
        layout = json.loads(layout_path.read_text(encoding="utf-8"))
        geom = carve_level_geometry(lv, layout, config, seed=args.seed + i)
        out_path = args.out_dir / f"{lv['id']}.json"
        out_path.write_text(json.dumps(geom, ensure_ascii=False), encoding="utf-8")
        n_strata = len(geom["strata"])
        n_carved = sum(1 for e in geom["edges_resolved"] if e["carved"])
        sys.stderr.write(
            f"  ✓ {lv['name']}: {n_strata} strates, {n_carved}/{len(geom['edges_resolved'])} edges carved\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

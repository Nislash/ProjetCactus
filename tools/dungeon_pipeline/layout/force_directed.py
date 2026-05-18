"""force_directed.py — Étape 2 de la pipeline : layout 2D des rooms.

Lit le JSON canonique de l'étape 1 et place chaque room/door dans un plan
(x, z) discret par niveau. Le Y in-game vient de la strate (gérée à l'étape 5).

**Algo** (Fruchterman-Reingold simplifié) :
1. Init positions : cercle par strate (seedé).
2. Force-directed :
   - Répulsion Coulomb entre nœuds **de la même strate** uniquement
     (deux rooms en strates différentes peuvent partager le même (x, z)).
   - Ressorts d'attraction sur toutes les edges :
     * full strength sur edges intra-strate,
     * `cross_stratum_spring_factor` × strength sur edges inter-strates
       (objectif : aligner les staircases en (x, z)).
3. Snap sur grille entière.
4. Résout les overlaps restants en séparant d'une cellule à la fois
   (séparation sur l'axe de plus petit chevauchement).

Sortie : `build/layouts/level_N.json` — `{room_id: {x, z, w, d, stratum, type}}`.

Usage:
    python -m layout.force_directed build/levels.json [--out-dir build/layouts]
"""
from __future__ import annotations

import argparse
import json
import math
import random
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Optional


@dataclass
class Node:
    id: str
    kind: str       # "spawn"|"combat_*"|"boss_arena"|"loot"|"secret"|"corridor"|"door"
    stratum: str
    w: int          # taille X en cellules
    d: int          # taille Z en cellules
    x: float = 0.0
    z: float = 0.0
    fx: float = 0.0
    fz: float = 0.0
    gx: int = 0     # coord snap grille
    gz: int = 0


def _size_for_type(type_name: str, room_sizes: dict) -> tuple[int, int]:
    if type_name in room_sizes:
        return tuple(room_sizes[type_name])
    return tuple(room_sizes.get("combat_small", [9, 9]))


def _init_positions(nodes: list[Node], rng: random.Random) -> None:
    """Pose chaque nœud sur un cercle par strate (positions initiales aléatoires)."""
    by_stratum: dict[str, list[Node]] = {}
    for n in nodes:
        by_stratum.setdefault(n.stratum, []).append(n)
    for group in by_stratum.values():
        n_count = len(group)
        radius = max(15.0, 4.0 * n_count)
        for i, node in enumerate(group):
            angle = 2 * math.pi * i / max(n_count, 1) + rng.uniform(0, 0.5)
            node.x = radius * math.cos(angle) + rng.uniform(-2, 2)
            node.z = radius * math.sin(angle) + rng.uniform(-2, 2)


def _force_directed_step(
    nodes: list[Node],
    edges: list[tuple[str, str]],
    k_spring: float,
    k_repulse: float,
    cross_stratum_factor: float,
    step_size: float,
) -> float:
    """Une itération. Retourne le déplacement max."""
    for n in nodes:
        n.fx = 0.0
        n.fz = 0.0

    by_id = {n.id: n for n in nodes}

    # Répulsion : seulement entre nœuds de la même strate.
    by_stratum: dict[str, list[Node]] = {}
    for n in nodes:
        by_stratum.setdefault(n.stratum, []).append(n)
    for group in by_stratum.values():
        for i in range(len(group)):
            a = group[i]
            for j in range(i + 1, len(group)):
                b = group[j]
                dx = a.x - b.x
                dz = a.z - b.z
                dist2 = dx * dx + dz * dz
                if dist2 < 0.01:
                    dist2 = 0.01
                    dx = 1.0
                    dz = 0.0
                inv_d = 1.0 / math.sqrt(dist2)
                force = k_repulse / dist2
                a.fx += force * dx * inv_d
                a.fz += force * dz * inv_d
                b.fx -= force * dx * inv_d
                b.fz -= force * dz * inv_d

    # Attraction sur edges (intra-strate full force, inter-strate facteur réduit).
    for u, v in edges:
        a = by_id.get(u)
        b = by_id.get(v)
        if a is None or b is None:
            continue
        dx = a.x - b.x
        dz = a.z - b.z
        dist = math.sqrt(dx * dx + dz * dz)
        if dist < 0.01:
            continue
        k = k_spring if a.stratum == b.stratum else k_spring * cross_stratum_factor
        force = k * dist
        a.fx -= force * dx / dist
        a.fz -= force * dz / dist
        b.fx += force * dx / dist
        b.fz += force * dz / dist

    max_disp = 0.0
    for n in nodes:
        dx = step_size * n.fx
        dz = step_size * n.fz
        n.x += dx
        n.z += dz
        d = math.hypot(dx, dz)
        if d > max_disp:
            max_disp = d
    return max_disp


def _snap_to_grid(nodes: list[Node]) -> None:
    """Calcule les coords entières gx, gz à partir de x, z. Pas d'offset ici."""
    for n in nodes:
        n.gx = int(round(n.x - n.w / 2))
        n.gz = int(round(n.z - n.d / 2))


def _overlaps(a: Node, b: Node, spacing: int) -> tuple[int, int]:
    """Retourne (overlap_x, overlap_z) avec spacing inflate, 0 si pas d'overlap."""
    a_l = a.gx - spacing
    a_r = a.gx + a.w + spacing
    a_t = a.gz - spacing
    a_b = a.gz + a.d + spacing
    b_l = b.gx
    b_r = b.gx + b.w
    b_t = b.gz
    b_b = b.gz + b.d
    if a_r > b_l and a_l < b_r and a_b > b_t and a_t < b_b:
        return (min(a_r - b_l, b_r - a_l), min(a_b - b_t, b_b - a_t))
    return (0, 0)


def _resolve_overlaps(nodes: list[Node], spacing: int, max_iter: int = 200) -> int:
    """Sépare les rooms qui s'overlap au sein d'une même strate. Une cellule par itération."""
    by_stratum: dict[str, list[Node]] = {}
    for n in nodes:
        by_stratum.setdefault(n.stratum, []).append(n)
    for it in range(max_iter):
        any_overlap = False
        for group in by_stratum.values():
            for i in range(len(group)):
                a = group[i]
                for j in range(i + 1, len(group)):
                    b = group[j]
                    ox, oz = _overlaps(a, b, spacing)
                    if ox == 0:
                        continue
                    any_overlap = True
                    # Sépare sur l'axe de plus petit chevauchement (moins de mouvement).
                    if ox <= oz:
                        if a.gx <= b.gx:
                            a.gx -= 1
                            b.gx += 1
                        else:
                            a.gx += 1
                            b.gx -= 1
                    else:
                        if a.gz <= b.gz:
                            a.gz -= 1
                            b.gz += 1
                        else:
                            a.gz += 1
                            b.gz -= 1
        if not any_overlap:
            return it + 1
    return max_iter


def layout_level(level: dict, config: dict, seed: int = 42) -> dict:
    """Layout un niveau et retourne le dict JSON sérialisable."""
    rng = random.Random(seed)
    room_sizes = config["room_sizes"]
    fd_cfg = config["force_directed"]
    door_size = fd_cfg.get("door_size_cells", 3)
    spacing = config.get("room_spacing_cells", 3)

    nodes: list[Node] = []
    for r in level["rooms"]:
        w, d = _size_for_type(r["type"], room_sizes)
        nodes.append(Node(id=r["id"], kind=r["type"], stratum=r["stratum"], w=w, d=d))
    for door in level["doors"]:
        nodes.append(Node(id=door["id"], kind="door", stratum=door["stratum"], w=door_size, d=door_size))

    if not nodes:
        return {"level_id": level["id"], "seed": seed, "rooms": {}, "grid_size": {"x": 0, "z": 0}, "iterations_run": 0, "overlap_iterations": 0}

    _init_positions(nodes, rng)
    edges: list[tuple[str, str]] = [(e["from"], e["to"]) for e in level["edges"]]

    iterations_max = fd_cfg["iterations_max"]
    epsilon = fd_cfg["epsilon"]
    k_spring = fd_cfg["k_spring"]
    k_repulse = fd_cfg["k_repulse"]
    step_size = fd_cfg.get("step_size", 0.1)
    cross_factor = fd_cfg.get("cross_stratum_spring_factor", 0.5)

    iterations_run = 0
    for it in range(iterations_max):
        max_disp = _force_directed_step(nodes, edges, k_spring, k_repulse, cross_factor, step_size)
        iterations_run = it + 1
        if max_disp < epsilon:
            break

    _snap_to_grid(nodes)
    overlap_iters = _resolve_overlaps(nodes, spacing)

    # Recale tout pour que les coords soient ≥ 1 (marge de 1 cellule autour).
    min_x = min(n.gx for n in nodes)
    min_z = min(n.gz for n in nodes)
    margin = 1
    dx = -min_x + margin
    dz = -min_z + margin
    for n in nodes:
        n.gx += dx
        n.gz += dz
    max_x = max(n.gx + n.w for n in nodes) + margin
    max_z = max(n.gz + n.d for n in nodes) + margin

    rooms_out = {}
    for n in nodes:
        rooms_out[n.id] = {
            "x": n.gx,
            "z": n.gz,
            "w": n.w,
            "d": n.d,
            "stratum": n.stratum,
            "type": n.kind,
        }
    return {
        "level_id": level["id"],
        "seed": seed,
        "iterations_run": iterations_run,
        "overlap_iterations": overlap_iters,
        "grid_size": {"x": max_x, "z": max_z},
        "rooms": rooms_out,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("input", type=Path, help="Chemin vers build/levels.json")
    ap.add_argument("--config", type=Path, default=None, help="Chemin vers config.json")
    ap.add_argument("--out-dir", type=Path, default=None, help="Dossier de sortie (défaut: <input_dir>/layouts/)")
    ap.add_argument("--seed", type=int, default=42, help="Seed de base (chaque niveau N a seed=base+N-1)")
    args = ap.parse_args(argv)

    if args.config is None:
        args.config = args.input.parent.parent / "config.json"
    config = json.loads(args.config.read_text(encoding="utf-8"))
    levels_data = json.loads(args.input.read_text(encoding="utf-8"))

    out_dir = args.out_dir or args.input.parent / "layouts"
    out_dir.mkdir(parents=True, exist_ok=True)

    for i, lv in enumerate(levels_data["levels"]):
        seed = args.seed + i
        layout = layout_level(lv, config, seed=seed)
        out_path = out_dir / f"{lv['id']}.json"
        out_path.write_text(json.dumps(layout, indent=2, ensure_ascii=False), encoding="utf-8")
        sys.stderr.write(
            f"  ✓ {lv['name']}: {len(layout['rooms'])} rooms, "
            f"grid {layout['grid_size']['x']}x{layout['grid_size']['z']}, "
            f"{layout['iterations_run']} fd-iter, {layout['overlap_iterations']} overlap-iter\n"
        )
    return 0


if __name__ == "__main__":
    sys.exit(main())

"""drunkard.py — Drunkard's walk seedé pour passages secrets.

Marche aléatoire entre start et goal :
- biais target_bias vers la cible (sinon direction random),
- abandonne si on entre dans une room non-prévue (sauf start/goal voisin),
- borne par max_iterations et length_factor_max × distance directe.
"""
from __future__ import annotations

import random
from typing import Optional

from .grid import (
    DOOR,
    Grid,
    ROOM_INTERIOR,
    SECRET,
    TRAVERSABLE_TO_DIG,
    WALL,
)


def drunkard_walk(
    grid: Grid,
    start: tuple[int, int],
    goal: tuple[int, int],
    rng: random.Random,
    length_factor_min: float = 1.5,
    length_factor_max: float = 2.0,
    target_bias: float = 0.3,
    max_iterations: int = 200,
) -> Optional[list[tuple[int, int]]]:
    """Génère un chemin sinueux entre start et goal. Retourne None si bloqué."""
    direct = abs(start[0] - goal[0]) + abs(start[1] - goal[1])
    target_length = int(direct * length_factor_min)
    max_length = max(int(direct * length_factor_max), max_iterations)

    current = start
    path = [current]
    visited = {current}
    it = 0
    while it < max_length and current != goal:
        it += 1
        gx, gz = goal
        cx, cz = current

        # Détermine la direction privilégiée vers goal.
        bias_dirs: list[tuple[int, int]] = []
        if gx > cx:
            bias_dirs.append((1, 0))
        elif gx < cx:
            bias_dirs.append((-1, 0))
        if gz > cz:
            bias_dirs.append((0, 1))
        elif gz < cz:
            bias_dirs.append((0, -1))

        all_dirs = [(1, 0), (-1, 0), (0, 1), (0, -1)]

        # Bias : si proche du goal OU si on a déjà atteint target_length, biais 1.
        local_bias = target_bias
        if len(path) >= target_length:
            local_bias = 0.8

        if bias_dirs and rng.random() < local_bias:
            dx, dz = rng.choice(bias_dirs)
        else:
            dx, dz = rng.choice(all_dirs)

        nx, nz = cx + dx, cz + dz
        if not grid.in_bounds(nx, nz):
            continue
        if (nx, nz) in visited and (nx, nz) != goal:
            continue
        tag = grid.get(nx, nz)
        # Stop si on entre dans une room (sauf si c'est le goal, dans une room hôte légitime).
        if tag in ROOM_INTERIOR and (nx, nz) != goal:
            continue
        if tag == WALL and (nx, nz) != goal:
            continue
        current = (nx, nz)
        path.append(current)
        visited.add(current)

    if current != goal:
        return None
    return path


def carve_drunkard(grid: Grid, path: list[tuple[int, int]]) -> None:
    from .astar import carve_corridor
    carve_corridor(grid, path, tag=SECRET)

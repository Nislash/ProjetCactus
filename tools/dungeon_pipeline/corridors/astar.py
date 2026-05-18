"""astar.py — A* sur grille 2D pour couloirs normaux.

Coûts (depuis config.astar) :
- +1 par tuile vide ou corridor déjà creusé,
- +wall_adjacency_penalty si la tuile est adjacente à un mur de room
  (évite de raser les murs latéraux),
- +inf à l'intérieur d'une room (FLOOR) — bloqué.

Les murs de room (WALL) sont **interdits** sauf à la cellule de départ et
d'arrivée (door slot creusée explicitement).
"""
from __future__ import annotations

import heapq
from typing import Optional

from .grid import (
    CORRIDOR,
    DOOR,
    FLOOR,
    Grid,
    ROOM_INTERIOR,
    SECRET,
    TRAVERSABLE_TO_DIG,
    VOID,
    WALL,
)


def _heuristic(a: tuple[int, int], b: tuple[int, int]) -> int:
    return abs(a[0] - b[0]) + abs(a[1] - b[1])


def _is_wall_adjacent(grid: Grid, x: int, z: int) -> bool:
    for nx, nz in grid.neighbors4(x, z):
        if grid.get(nx, nz) == WALL:
            return True
    return False


def astar_corridor(
    grid: Grid,
    start: tuple[int, int],
    goal: tuple[int, int],
    wall_adjacency_penalty: int = 5,
    forbidden_owners: set[str] | None = None,
) -> Optional[list[tuple[int, int]]]:
    """Trouve le chemin de start à goal en évitant les rooms.

    forbidden_owners : si fourni, traverser une cell appartenant à ces
    room_ids est interdit. Sinon, toute room (FLOOR/WALL avec owner non-None,
    sauf le start/goal voisin) est interdite.
    """
    if start == goal:
        return [start]
    if not grid.in_bounds(*start) or not grid.in_bounds(*goal):
        return None

    open_heap: list[tuple[int, int, tuple[int, int]]] = []
    heapq.heappush(open_heap, (0, 0, start))
    came_from: dict[tuple[int, int], tuple[int, int]] = {}
    g_score: dict[tuple[int, int], int] = {start: 0}
    counter = 1

    while open_heap:
        _, _, current = heapq.heappop(open_heap)
        if current == goal:
            # Reconstruct path
            path = [current]
            while current in came_from:
                current = came_from[current]
                path.append(current)
            path.reverse()
            return path

        for nx, nz in grid.neighbors4(*current):
            if (nx, nz) != goal:
                tag = grid.get(nx, nz)
                owner = grid.owner(nx, nz)
                if tag in ROOM_INTERIOR:
                    continue
                if tag == WALL:
                    continue
                if forbidden_owners and owner in forbidden_owners:
                    continue
            base = 1
            penalty = wall_adjacency_penalty if _is_wall_adjacent(grid, nx, nz) else 0
            tentative = g_score[current] + base + penalty
            if tentative < g_score.get((nx, nz), 1_000_000_000):
                g_score[(nx, nz)] = tentative
                came_from[(nx, nz)] = current
                f = tentative + _heuristic((nx, nz), goal)
                heapq.heappush(open_heap, (f, counter, (nx, nz)))
                counter += 1

    return None


def carve_corridor(grid: Grid, path: list[tuple[int, int]], tag: str = CORRIDOR) -> None:
    """Marque les cellules du chemin comme corridor (préserve doors et stairs)."""
    for x, z in path:
        existing = grid.get(x, z)
        if existing in (DOOR, "boss_door", "stair_up", "stair_down", "drop"):
            continue
        if existing in TRAVERSABLE_TO_DIG:
            grid.set(x, z, tag, owner=None)

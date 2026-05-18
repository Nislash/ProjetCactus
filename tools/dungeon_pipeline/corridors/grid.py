"""grid.py — Représentation de la grille 2D par strate.

Une cellule contient un tag string :
- "void"        : extérieur (default)
- "floor"       : sol de room
- "wall"        : mur de room (périphérie)
- "corridor"    : sol de couloir creusé par A*
- "secret"      : sol de passage secret (drunkard)
- "door"        : porte normale (sur mur de room)
- "boss_door"   : porte verrouillée
- "stair_up"    : escalier montant (transition strate)
- "stair_down"  : escalier descendant
- "drop"        : one-way drop
- "jump_pad"    : pad de saut (gravité réduite)
- "drift"       : zéro-G drift point

Chaque strate a sa propre grille 2D (W x D).
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Iterator


VOID = "void"
FLOOR = "floor"
WALL = "wall"
CORRIDOR = "corridor"
SECRET = "secret"
DOOR = "door"
BOSS_DOOR = "boss_door"
STAIR_UP = "stair_up"
STAIR_DOWN = "stair_down"
DROP = "drop"
JUMP_PAD = "jump_pad"
DRIFT = "drift"

# Tags traversables pour pathfinding (A* peut passer dessus pour creuser).
TRAVERSABLE_TO_DIG = {VOID, CORRIDOR, SECRET}
# Tags qui appartiennent à une room (pas creusables par couloir).
ROOM_INTERIOR = {FLOOR}
ROOM_BOUNDARY = {WALL}


@dataclass
class Grid:
    """Grille 2D pour une strate."""
    width: int
    depth: int
    cells: list[str] = field(default_factory=list)
    # cell_owner[idx] = room_id de la cellule (None si void/corridor)
    owners: list[str | None] = field(default_factory=list)

    def __post_init__(self):
        if not self.cells:
            self.cells = [VOID] * (self.width * self.depth)
            self.owners = [None] * (self.width * self.depth)

    def _idx(self, x: int, z: int) -> int:
        return z * self.width + x

    def in_bounds(self, x: int, z: int) -> bool:
        return 0 <= x < self.width and 0 <= z < self.depth

    def get(self, x: int, z: int) -> str:
        if not self.in_bounds(x, z):
            return VOID
        return self.cells[self._idx(x, z)]

    def set(self, x: int, z: int, tag: str, owner: str | None = None) -> None:
        if not self.in_bounds(x, z):
            return
        idx = self._idx(x, z)
        self.cells[idx] = tag
        self.owners[idx] = owner

    def owner(self, x: int, z: int) -> str | None:
        if not self.in_bounds(x, z):
            return None
        return self.owners[self._idx(x, z)]

    def stamp_room(self, room_id: str, x: int, z: int, w: int, d: int) -> None:
        """Tag tous les bords en WALL et l'intérieur en FLOOR."""
        for zi in range(z, z + d):
            for xi in range(x, x + w):
                if not self.in_bounds(xi, zi):
                    continue
                is_boundary = (
                    xi == x or xi == x + w - 1 or zi == z or zi == z + d - 1
                )
                tag = WALL if is_boundary else FLOOR
                self.set(xi, zi, tag, owner=room_id)

    def neighbors4(self, x: int, z: int) -> Iterator[tuple[int, int]]:
        for dx, dz in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            nx, nz = x + dx, z + dz
            if self.in_bounds(nx, nz):
                yield nx, nz

    def to_ascii(self) -> str:
        """Render ASCII pour debug."""
        symbols = {
            VOID: ".", FLOOR: " ", WALL: "#", CORRIDOR: "·", SECRET: "~",
            DOOR: "D", BOSS_DOOR: "B", STAIR_UP: "^", STAIR_DOWN: "v",
            DROP: "↓", JUMP_PAD: "J", DRIFT: ":",
        }
        lines = []
        for zi in range(self.depth):
            row = "".join(symbols.get(self.cells[self._idx(xi, zi)], "?") for xi in range(self.width))
            lines.append(row)
        return "\n".join(lines)

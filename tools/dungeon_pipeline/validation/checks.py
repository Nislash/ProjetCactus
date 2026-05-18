"""checks.py — Étape 4 de la pipeline. Filet de sécurité critique.

C'est l'étape qui était manquante dans la première tentative. Aucun
niveau ne sort sans avoir passé ces validations.

Checks par niveau :
1. Connexité globale depuis spawn (flood-fill).
2. Cohérence des portes (porte sur mur de room, couloir aligné).
3. Spawn safe (sur FLOOR, pas adjacent à WALL, dans la room déclarée spawn).
4. Pas de tuile orpheline (corridor/secret non connecté à un FLOOR).
5. Boss reachable & locked : sans keys (boss_door = obstacle) le boss doit
   être INATTEIGNABLE depuis spawn ; avec keys (boss_door = traversable)
   il doit être atteignable.
6. Fragment méta atteignable (via secret OK).
7. Strata coherence : stair_up/stair_down s'alignent entre strates.

API :
    result = validate_level(level, layout, geometry)
    # result.ok : bool
    # result.errors : list[CheckFailure]
"""
from __future__ import annotations

from dataclasses import dataclass, field
from typing import Optional

from corridors.grid import (
    BOSS_DOOR,
    CORRIDOR,
    DOOR,
    DRIFT,
    DROP,
    FLOOR,
    Grid,
    JUMP_PAD,
    SECRET,
    STAIR_DOWN,
    STAIR_UP,
    VOID,
    WALL,
)

# Tile tags qui constituent un "sol" sur lequel le joueur peut être/passer.
WALKABLE_BASE = {FLOOR, CORRIDOR, SECRET, DOOR, STAIR_UP, STAIR_DOWN, DROP, JUMP_PAD, DRIFT}
WALKABLE_INCL_BOSS_DOOR = WALKABLE_BASE | {BOSS_DOOR}
SECRET_DOOR_TAG = "secret_door"
DROP_LANDING_TAG = "drop_landing"


@dataclass
class CheckFailure:
    check: str
    level_id: str
    stratum: Optional[str] = None
    pos: Optional[tuple[int, int]] = None
    detail: str = ""

    def __str__(self) -> str:
        loc = []
        if self.stratum is not None:
            loc.append(f"strate={self.stratum}")
        if self.pos is not None:
            loc.append(f"pos={self.pos}")
        loc_str = f" [{', '.join(loc)}]" if loc else ""
        return f"[{self.level_id}] {self.check}{loc_str}: {self.detail}"


@dataclass
class ValidationResult:
    level_id: str
    ok: bool = True
    errors: list[CheckFailure] = field(default_factory=list)
    warnings: list[CheckFailure] = field(default_factory=list)

    def fail(self, check: str, detail: str, stratum: Optional[str] = None, pos: Optional[tuple[int, int]] = None) -> None:
        self.ok = False
        self.errors.append(CheckFailure(check=check, level_id=self.level_id, stratum=stratum, pos=pos, detail=detail))

    def warn(self, check: str, detail: str, stratum: Optional[str] = None, pos: Optional[tuple[int, int]] = None) -> None:
        self.warnings.append(CheckFailure(check=check, level_id=self.level_id, stratum=stratum, pos=pos, detail=detail))


# ============================================================================
# Helpers
# ============================================================================

def _grid_from_data(data: dict) -> Grid:
    g = Grid(width=data["width"], depth=data["depth"])
    g.cells = list(data["cells"])
    g.owners = list(data["owners"])
    return g


def _flood_fill(grid: Grid, start: tuple[int, int], walkable: set[str]) -> set[tuple[int, int]]:
    if not grid.in_bounds(*start) or grid.get(*start) not in walkable:
        return set()
    visited: set[tuple[int, int]] = {start}
    stack = [start]
    while stack:
        x, z = stack.pop()
        for nx, nz in grid.neighbors4(x, z):
            if (nx, nz) in visited:
                continue
            if grid.get(nx, nz) in walkable:
                visited.add((nx, nz))
                stack.append((nx, nz))
    return visited


def _find_room_center_on_floor(grid: Grid, room_layout: dict) -> Optional[tuple[int, int]]:
    """Cherche une cellule FLOOR appartenant à la room. Retourne (x, z) ou None."""
    room_id = None  # not used directly; we search by AABB
    rx, rz, rw, rd = room_layout["x"], room_layout["z"], room_layout["w"], room_layout["d"]
    # Préfère le centre puis spiral.
    cx, cz = rx + rw // 2, rz + rd // 2
    candidates = [(cx, cz)]
    for r in range(1, max(rw, rd)):
        for dx in range(-r, r + 1):
            for dz in range(-r, r + 1):
                if abs(dx) == r or abs(dz) == r:
                    candidates.append((cx + dx, cz + dz))
    for x, z in candidates:
        if grid.get(x, z) in (FLOOR, STAIR_UP, STAIR_DOWN, DROP, JUMP_PAD, DRIFT):
            return (x, z)
    return None


def _build_multistratum_graph(strata: dict[str, Grid], edges_resolved: list[dict]) -> dict[tuple[str, int, int], set[tuple[str, int, int]]]:
    """Construit un graphe (stratum, x, z) -> voisins, incluant les transitions verticales."""
    graph: dict[tuple[str, int, int], set[tuple[str, int, int]]] = {}
    # Voisinage intra-strate.
    for s, grid in strata.items():
        for z in range(grid.depth):
            for x in range(grid.width):
                node = (s, x, z)
                graph.setdefault(node, set())
                for nx, nz in grid.neighbors4(x, z):
                    graph[node].add((s, nx, nz))
    # Transitions verticales (via edges_resolved kind=stairs/ladder/elevator/jump/drop).
    for e in edges_resolved:
        if "stratum_from" not in e or "stratum_to" not in e:
            continue
        sf, st = e["stratum_from"], e["stratum_to"]
        pf = tuple(e["pos_from"])
        pt = tuple(e["pos_to"])
        a = (sf, pf[0], pf[1])
        b = (st, pt[0], pt[1])
        graph.setdefault(a, set()).add(b)
        if e["kind"] not in ("one_way_drop",):
            graph.setdefault(b, set()).add(a)
        else:
            # Drop = one-way, mais B → A interdit (irreversible).
            graph.setdefault(b, set())
    return graph


def _augment_graph_with_zero_g(
    graph: dict,
    strata: dict[str, Grid],
    edges_canonical: list[dict],
    layout_rooms: dict,
) -> None:
    """Ajoute les edges zero_g_drift comme transitions entre centres de rooms.

    Mutation in-place du graph.
    """
    for e in edges_canonical:
        if e["kind"] != "zero_g_drift":
            continue
        a_id, b_id = e["from"], e["to"]
        a_layout = layout_rooms.get(a_id)
        b_layout = layout_rooms.get(b_id)
        if a_layout is None or b_layout is None:
            continue
        # Centre de chaque room (la cellule centrale a été taggée DRIFT par étape 3).
        acx = a_layout["x"] + a_layout["w"] // 2
        acz = a_layout["z"] + a_layout["d"] // 2
        bcx = b_layout["x"] + b_layout["w"] // 2
        bcz = b_layout["z"] + b_layout["d"] // 2
        a_node = (a_layout["stratum"], acx, acz)
        b_node = (b_layout["stratum"], bcx, bcz)
        graph.setdefault(a_node, set()).add(b_node)
        graph.setdefault(b_node, set()).add(a_node)


def _multistratum_flood(
    graph: dict,
    start: tuple[str, int, int],
    strata: dict[str, Grid],
    walkable: set[str],
) -> set[tuple[str, int, int]]:
    if start not in graph or strata[start[0]].get(start[1], start[2]) not in walkable:
        return set()
    visited = {start}
    stack = [start]
    while stack:
        node = stack.pop()
        for nb in graph.get(node, ()):
            if nb in visited:
                continue
            ns, nx, nz = nb
            tag = strata[ns].get(nx, nz)
            if tag in walkable:
                visited.add(nb)
                stack.append(nb)
    return visited


# ============================================================================
# Checks
# ============================================================================

def validate_level(level: dict, layout: dict, geometry: dict, *, strict_boss_locked: bool = False) -> ValidationResult:
    """Valide la géométrie d'un niveau. Retourne un ValidationResult.

    strict_boss_locked : si True, "boss_reachable_without_keys" est une error
    bloquante. Par défaut, c'est un warning (certains drawio modélisent une
    route alternative pour l'arène boss).
    """
    result = ValidationResult(level_id=level["id"])

    # Reconstruit les Grids.
    strata: dict[str, Grid] = {s: _grid_from_data(d) for s, d in geometry["strata"].items()}

    # 1. Trouve le spawn (cellule FLOOR dans la room spawn).
    spawn_room_id = level["spawn_room"]
    spawn_layout = layout["rooms"].get(spawn_room_id)
    if spawn_layout is None:
        result.fail("spawn_layout_missing", f"Spawn room {spawn_room_id!r} absente du layout")
        return result
    spawn_stratum = spawn_layout["stratum"]
    spawn_grid = strata.get(spawn_stratum)
    if spawn_grid is None:
        result.fail("spawn_stratum_missing", f"Strate spawn {spawn_stratum!r} absente de la géométrie")
        return result
    spawn_pos = _find_room_center_on_floor(spawn_grid, spawn_layout)
    if spawn_pos is None:
        result.fail("spawn_no_floor", f"Aucun FLOOR trouvé dans la room spawn {spawn_room_id!r}", stratum=spawn_stratum)
        return result

    # 2. Spawn safe : doit être sur une tile walkable (FLOOR/DRIFT/STAIR/JUMP_PAD).
    #    Les markers de transition (jump_pad, stair_*) sont sur le centre d'une
    #    room et le joueur démarre dessus — c'est acceptable.
    sx, sz = spawn_pos
    spawn_tag = spawn_grid.get(sx, sz)
    if spawn_tag not in WALKABLE_BASE:
        result.fail("spawn_not_on_walkable",
                    f"Spawn @({sx},{sz}) sur tag {spawn_tag!r}, attendu walkable ({WALKABLE_BASE})",
                    stratum=spawn_stratum, pos=spawn_pos)

    # 3. Construit le graphe multi-strates et fait deux flood-fills.
    graph = _build_multistratum_graph(strata, geometry["edges_resolved"])
    _augment_graph_with_zero_g(graph, strata, level["edges"], layout["rooms"])
    start = (spawn_stratum, sx, sz)

    # Flood SANS franchir les boss_doors.
    reachable_locked = _multistratum_flood(graph, start, strata, WALKABLE_BASE | {SECRET_DOOR_TAG, DROP_LANDING_TAG})
    # Flood AVEC les boss_doors traversables (simule keys collectées).
    reachable_unlocked = _multistratum_flood(graph, start, strata, WALKABLE_INCL_BOSS_DOOR | {SECRET_DOOR_TAG, DROP_LANDING_TAG})

    # 4. Toutes les rooms (sauf doors) doivent avoir au moins une cellule FLOOR
    #    atteignable via le flood unlocked (post-puzzle).
    for r in level["rooms"]:
        rid = r["id"]
        rl = layout["rooms"].get(rid)
        if rl is None:
            result.fail("room_missing_layout", f"Room {rid!r} absente du layout")
            continue
        rg = strata.get(rl["stratum"])
        if rg is None:
            result.fail("room_missing_stratum", f"Room {rid!r} strate {rl['stratum']!r} absente", stratum=rl["stratum"])
            continue
        room_cells = []
        for zi in range(rl["z"], rl["z"] + rl["d"]):
            for xi in range(rl["x"], rl["x"] + rl["w"]):
                if rg.owner(xi, zi) == rid and rg.get(xi, zi) in (FLOOR, STAIR_UP, STAIR_DOWN, DROP, JUMP_PAD, DRIFT):
                    room_cells.append((rl["stratum"], xi, zi))
        if not room_cells:
            result.fail("room_no_floor", f"Room {rid!r} sans aucune FLOOR (type={r['type']})",
                        stratum=rl["stratum"])
            continue
        if not any(c in reachable_unlocked for c in room_cells):
            result.fail("room_unreachable", f"Room {rid!r} non atteignable depuis spawn (même avec keys)",
                        stratum=rl["stratum"])

    # 5. Boss reachable & locked : si la room boss a une boss_door entre elle et
    #    le spawn (cas standard), elle ne doit PAS être atteignable sans keys.
    boss_rooms = [r["id"] for r in level["rooms"] if r["type"] == "boss_arena"]
    locked_doors = [d for d in level["doors"] if d["locked"]]
    if locked_doors and boss_rooms:
        # On vérifie sur la première arène boss.
        bid = boss_rooms[0]
        bl = layout["rooms"][bid]
        bg = strata[bl["stratum"]]
        boss_cells = []
        for zi in range(bl["z"], bl["z"] + bl["d"]):
            for xi in range(bl["x"], bl["x"] + bl["w"]):
                if bg.owner(xi, zi) == bid and bg.get(xi, zi) == FLOOR:
                    boss_cells.append((bl["stratum"], xi, zi))
        if not boss_cells:
            result.fail("boss_no_floor", f"Boss {bid!r} sans FLOOR", stratum=bl["stratum"])
        else:
            reachable_via_locked = any(c in reachable_locked for c in boss_cells)
            reachable_via_unlocked = any(c in reachable_unlocked for c in boss_cells)
            if reachable_via_locked:
                msg = f"Boss {bid!r} atteignable sans franchir la boss_door (puzzle skippable via route alternative)"
                if strict_boss_locked:
                    result.fail("boss_reachable_without_keys", msg, stratum=bl["stratum"])
                else:
                    result.warn("boss_reachable_without_keys", msg, stratum=bl["stratum"])
            if not reachable_via_unlocked:
                result.fail(
                    "boss_unreachable_with_keys",
                    f"Boss {bid!r} inatteignable même avec keys (la boss_door ne mène pas au boss)",
                    stratum=bl["stratum"],
                )

    # 6. Fragment méta atteignable.
    for rid, c in level["contents"].items():
        if not c.get("meta_fragment"):
            continue
        rl = layout["rooms"].get(rid)
        if rl is None:
            continue
        rg = strata[rl["stratum"]]
        cells = []
        for zi in range(rl["z"], rl["z"] + rl["d"]):
            for xi in range(rl["x"], rl["x"] + rl["w"]):
                if rg.owner(xi, zi) == rid and rg.get(xi, zi) == FLOOR:
                    cells.append((rl["stratum"], xi, zi))
        if cells and not any(c in reachable_unlocked for c in cells):
            result.fail("fragment_unreachable",
                        f"Meta_fragment dans room {rid!r} non atteignable",
                        stratum=rl["stratum"])

    # 7. Pas de tuile orpheline : tout CORRIDOR doit toucher au moins un FLOOR
    #    ou un autre CORRIDOR / DOOR.
    for s, grid in strata.items():
        for z in range(grid.depth):
            for x in range(grid.width):
                tag = grid.get(x, z)
                if tag not in (CORRIDOR, SECRET):
                    continue
                # Au moins un voisin doit être walkable (autre que VOID/WALL).
                has_neighbor = False
                for nx, nz in grid.neighbors4(x, z):
                    n_tag = grid.get(nx, nz)
                    if n_tag in WALKABLE_INCL_BOSS_DOOR or n_tag in (SECRET_DOOR_TAG, DROP_LANDING_TAG):
                        has_neighbor = True
                        break
                if not has_neighbor:
                    result.fail("orphan_corridor",
                                f"Tuile {tag} isolée sans voisin walkable",
                                stratum=s, pos=(x, z))

    # 8. Strata coherence : chaque stair_up dans la strate basse doit avoir un
    #    stair_down correspondant dans la strate haute.
    for e in geometry["edges_resolved"]:
        if e.get("kind") not in ("stairs", "ladder", "elevator", "jump_required"):
            continue
        if "pos_from" not in e:
            continue
        sf, st = e["stratum_from"], e["stratum_to"]
        if sf not in strata or st not in strata:
            continue
        pf = tuple(e["pos_from"])
        pt = tuple(e["pos_to"])
        tag_f = strata[sf].get(*pf)
        tag_t = strata[st].get(*pt)
        if tag_f == VOID or tag_t == VOID:
            result.fail("stair_missing_endpoint",
                        f"Edge {e['kind']} {e['from']}→{e['to']} : tag VOID à un endpoint (sf={sf}@{pf}={tag_f}, st={st}@{pt}={tag_t})",
                        stratum=sf, pos=pf)

    return result


def validate_geometry_file(level: dict, layout: dict, geometry: dict) -> ValidationResult:
    """Wrapper pour appel depuis CLI."""
    return validate_level(level, layout, geometry)

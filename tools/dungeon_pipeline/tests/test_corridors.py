"""Tests pour l'étape 3 : corridors A* + drunkard + orchestrateur."""
from __future__ import annotations

import json
import random
from pathlib import Path

import pytest

from corridors.astar import astar_corridor, carve_corridor
from corridors.build_geometry import carve_level_geometry, build_strata_grids
from corridors.drunkard import drunkard_walk
from corridors.grid import (
    BOSS_DOOR,
    CORRIDOR,
    DOOR,
    FLOOR,
    Grid,
    SECRET,
    STAIR_DOWN,
    STAIR_UP,
    VOID,
    WALL,
)
from layout.force_directed import layout_level
from parser.drawio_to_json import parse_drawio

REPO_ROOT = Path(__file__).resolve().parents[3]
DRAWIO_PATH = REPO_ROOT / "docs" / "design" / "levels" / "topology.drawio"
PIPELINE_DIR = Path(__file__).resolve().parents[1]
CONFIG_PATH = PIPELINE_DIR / "config.json"


@pytest.fixture(scope="module")
def config():
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def parsed():
    return parse_drawio(DRAWIO_PATH)


@pytest.fixture(scope="module")
def layouts(parsed, config):
    return {lv["id"]: layout_level(lv, config, seed=42 + i) for i, lv in enumerate(parsed["levels"])}


@pytest.fixture(scope="module")
def geometries(parsed, layouts, config):
    return {
        lv["id"]: carve_level_geometry(lv, layouts[lv["id"]], config, seed=100 + i)
        for i, lv in enumerate(parsed["levels"])
    }


# ============================================================================
# Grid basics
# ============================================================================

def test_grid_bounds():
    g = Grid(width=10, depth=8)
    assert g.in_bounds(0, 0)
    assert g.in_bounds(9, 7)
    assert not g.in_bounds(10, 0)
    assert not g.in_bounds(-1, 0)
    assert g.get(0, 0) == VOID


def test_grid_stamp_room():
    g = Grid(width=20, depth=20)
    g.stamp_room("R1", 5, 5, 5, 5)
    # Périphérie = WALL
    assert g.get(5, 5) == WALL
    assert g.get(9, 9) == WALL
    assert g.get(7, 5) == WALL
    # Intérieur = FLOOR
    assert g.get(6, 6) == FLOOR
    assert g.get(7, 7) == FLOOR
    # Hors de la room = VOID
    assert g.get(4, 5) == VOID
    assert g.get(10, 5) == VOID
    # Owner
    assert g.owner(7, 7) == "R1"
    assert g.owner(4, 5) is None


# ============================================================================
# A* unitaires
# ============================================================================

def test_astar_empty_grid_finds_path():
    g = Grid(width=10, depth=10)
    path = astar_corridor(g, (0, 0), (9, 9))
    assert path is not None
    assert path[0] == (0, 0)
    assert path[-1] == (9, 9)
    # Manhattan distance optimal sur grille vide
    assert len(path) == 19


def test_astar_avoids_rooms():
    g = Grid(width=20, depth=20)
    g.stamp_room("R1", 5, 3, 5, 14)  # Bloque le milieu, mais laisse passer en haut/bas
    path = astar_corridor(g, (2, 10), (15, 10))
    assert path is not None, "A* devrait contourner la room par le haut ou le bas"
    # Aucune cellule du chemin ne doit être à l'intérieur de la room
    for x, z in path:
        tag = g.get(x, z)
        assert tag != FLOOR, f"Cellule ({x},{z}) du chemin est FLOOR (intérieur room)"
        assert tag != WALL, f"Cellule ({x},{z}) du chemin est WALL"


def test_astar_no_path_when_blocked():
    g = Grid(width=10, depth=10)
    # Mur infranchissable
    g.stamp_room("R1", 0, 5, 10, 1)
    path = astar_corridor(g, (5, 2), (5, 8))
    assert path is None


def test_astar_carve_preserves_doors():
    g = Grid(width=10, depth=10)
    g.set(3, 3, DOOR)
    path = astar_corridor(g, (1, 3), (5, 3))
    assert path is not None
    carve_corridor(g, path)
    assert g.get(3, 3) == DOOR  # Door preserved


# ============================================================================
# Drunkard unitaires
# ============================================================================

def test_drunkard_finds_goal():
    g = Grid(width=30, depth=30)
    rng = random.Random(42)
    path = drunkard_walk(g, (5, 5), (25, 25), rng, max_iterations=500)
    assert path is not None
    assert path[0] == (5, 5)
    assert path[-1] == (25, 25)
    # Doit être plus long qu'un A* direct (sinuosity)
    direct = abs(5 - 25) + abs(5 - 25)
    assert len(path) >= direct


def test_drunkard_deterministic():
    g = Grid(width=20, depth=20)
    rng1 = random.Random(7)
    rng2 = random.Random(7)
    p1 = drunkard_walk(g, (1, 1), (15, 15), rng1)
    p2 = drunkard_walk(g, (1, 1), (15, 15), rng2)
    assert p1 == p2


# ============================================================================
# Niveau complet
# ============================================================================

def test_eight_geometries(geometries):
    assert set(geometries.keys()) == {f"level_{i}" for i in range(1, 9)}


def test_every_level_has_strata(geometries):
    for lid, geom in geometries.items():
        assert geom["strata"], f"{lid} n'a aucune strate"


def test_no_corridor_inside_room(geometries):
    """Les couloirs ne doivent jamais marcher dans le FLOOR d'une room."""
    for lid, geom in geometries.items():
        for s, grid_data in geom["strata"].items():
            cells = grid_data["cells"]
            owners = grid_data["owners"]
            for i, cell in enumerate(cells):
                if cell in (CORRIDOR, SECRET):
                    assert owners[i] is None, (
                        f"{lid}/{s}: tuile {cell} en idx {i} a un owner={owners[i]!r}"
                    )


def test_rooms_have_walls(geometries):
    """Chaque room doit avoir au moins quelques cellules WALL en périphérie."""
    for lid, geom in geometries.items():
        for s, grid_data in geom["strata"].items():
            cells = grid_data["cells"]
            owners = grid_data["owners"]
            wall_owners = {owners[i] for i, c in enumerate(cells) if c == WALL and owners[i]}
            floor_owners = {owners[i] for i, c in enumerate(cells) if c == FLOOR}
            # Toute room qui a un FLOOR doit avoir des WALL.
            assert floor_owners <= wall_owners, (
                f"{lid}/{s} : rooms sans walls : {floor_owners - wall_owners}"
            )


def test_n1_corridors_carved(geometries):
    g = geometries["level_1"]
    carved = [e for e in g["edges_resolved"] if e["carved"]]
    # N1 a 10 edges (parser)
    assert len(carved) >= 8, f"N1 n'a creusé que {len(carved)} edges"


def test_n1_has_stair_tags(geometries):
    """N1 a 3 escaliers verticaux (entree↔hall, hall↔profond, g3↔boss)."""
    g = geometries["level_1"]
    stair_tags = {STAIR_UP, STAIR_DOWN}
    found = 0
    for s, grid_data in g["strata"].items():
        for c in grid_data["cells"]:
            if c in stair_tags:
                found += 1
    assert found >= 4, f"N1 stairs trouvés: {found}"


def test_n1_has_boss_door_tag(geometries):
    g = geometries["level_1"]
    found = False
    for s, grid_data in g["strata"].items():
        if BOSS_DOOR in grid_data["cells"]:
            found = True
            break
    assert found, "N1 boss door non taggée"


def test_determinism_geometry(parsed, layouts, config):
    lv = parsed["levels"][0]
    layout = layouts[lv["id"]]
    g1 = carve_level_geometry(lv, layout, config, seed=999)
    g2 = carve_level_geometry(lv, layout, config, seed=999)
    assert g1 == g2


def test_build_strata_grids_n1(parsed, layouts):
    lv = parsed["levels"][0]
    strata = build_strata_grids(layouts[lv["id"]])
    assert set(strata.keys()) == {"0", "-1", "-2"}

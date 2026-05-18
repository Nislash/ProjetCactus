"""Tests pour layout/force_directed.py — étape 2."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from layout.force_directed import layout_level
from parser.drawio_to_json import parse_drawio

REPO_ROOT = Path(__file__).resolve().parents[3]
DRAWIO_PATH = REPO_ROOT / "docs" / "design" / "levels" / "topology.drawio"
PIPELINE_DIR = Path(__file__).resolve().parents[1]
CONFIG_PATH = PIPELINE_DIR / "config.json"


@pytest.fixture(scope="module")
def parsed():
    return parse_drawio(DRAWIO_PATH)


@pytest.fixture(scope="module")
def config():
    return json.loads(CONFIG_PATH.read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def layouts(parsed, config):
    return {lv["id"]: layout_level(lv, config, seed=42 + i) for i, lv in enumerate(parsed["levels"])}


# ============================================================================
# Sanity
# ============================================================================

def test_eight_layouts(layouts):
    assert set(layouts.keys()) == {f"level_{i}" for i in range(1, 9)}


def test_room_counts_match_input(parsed, layouts):
    for lv in parsed["levels"]:
        layout = layouts[lv["id"]]
        expected = len(lv["rooms"]) + len(lv["doors"])
        assert len(layout["rooms"]) == expected, (
            f"{lv['name']}: layout a {len(layout['rooms'])} nœuds, "
            f"attendu {expected} (rooms={len(lv['rooms'])} + doors={len(lv['doors'])})"
        )


def test_all_coords_positive(layouts):
    for lid, layout in layouts.items():
        for rid, r in layout["rooms"].items():
            assert r["x"] >= 0, f"{lid}/{rid}: x={r['x']} négatif"
            assert r["z"] >= 0, f"{lid}/{rid}: z={r['z']} négatif"


def test_grid_size_reasonable(layouts):
    for lid, layout in layouts.items():
        g = layout["grid_size"]
        assert 20 <= g["x"] <= 300, f"{lid}: grid x={g['x']} unreasonable"
        assert 20 <= g["z"] <= 300, f"{lid}: grid z={g['z']} unreasonable"


def test_room_metadata_preserved(parsed, layouts):
    for lv in parsed["levels"]:
        layout = layouts[lv["id"]]
        # Chaque room d'entrée doit avoir une coord sortie, et le stratum doit matcher.
        for r in lv["rooms"]:
            assert r["id"] in layout["rooms"], f"{r['id']} manque dans le layout"
            assert layout["rooms"][r["id"]]["stratum"] == r["stratum"]
        for d in lv["doors"]:
            assert d["id"] in layout["rooms"]


# ============================================================================
# Invariants critiques
# ============================================================================

def test_no_overlap_within_stratum(layouts):
    """Deux rooms d'une même strate ne doivent jamais se chevaucher."""
    for lid, layout in layouts.items():
        by_stratum: dict[str, list[tuple[str, dict]]] = {}
        for rid, r in layout["rooms"].items():
            by_stratum.setdefault(r["stratum"], []).append((rid, r))
        for stratum, group in by_stratum.items():
            for i in range(len(group)):
                aid, a = group[i]
                for j in range(i + 1, len(group)):
                    bid, b = group[j]
                    overlap = (
                        a["x"] < b["x"] + b["w"]
                        and a["x"] + a["w"] > b["x"]
                        and a["z"] < b["z"] + b["d"]
                        and a["z"] + a["d"] > b["z"]
                    )
                    assert not overlap, (
                        f"{lid} strate {stratum}: {aid}@({a['x']},{a['z']},{a['w']}x{a['d']}) "
                        f"overlap {bid}@({b['x']},{b['z']},{b['w']}x{b['d']})"
                    )


def test_determinism_same_seed(parsed, config):
    lv = parsed["levels"][0]
    a = layout_level(lv, config, seed=123)
    b = layout_level(lv, config, seed=123)
    assert a == b, "Même seed doit produire le même layout (déterminisme)"


def test_different_seeds_change_layout(parsed, config):
    lv = parsed["levels"][0]
    a = layout_level(lv, config, seed=123)
    b = layout_level(lv, config, seed=124)
    differences = [rid for rid in a["rooms"] if a["rooms"][rid] != b["rooms"][rid]]
    assert differences, "Seed différent doit changer au moins une position"


# ============================================================================
# Détails N1
# ============================================================================

def test_n1_strata_present(layouts):
    n1 = layouts["level_1"]
    strata = {r["stratum"] for r in n1["rooms"].values()}
    assert strata == {"0", "-1", "-2"}


def test_n1_all_rooms_in_grid(layouts):
    n1 = layouts["level_1"]
    g = n1["grid_size"]
    for rid, r in n1["rooms"].items():
        assert r["x"] + r["w"] <= g["x"], f"{rid} dépasse grid en X"
        assert r["z"] + r["d"] <= g["z"], f"{rid} dépasse grid en Z"


def test_door_node_size(layouts, config):
    """Les portes ont une taille fixe (config.door_size_cells)."""
    expected = config["force_directed"]["door_size_cells"]
    for lid, layout in layouts.items():
        for rid, r in layout["rooms"].items():
            if r["type"] == "door":
                assert r["w"] == expected and r["d"] == expected, (
                    f"{lid}/{rid} taille porte {r['w']}x{r['d']}, attendu {expected}"
                )


def test_room_sizes_from_config(parsed, layouts, config):
    """Chaque room a la taille déclarée pour son type."""
    sizes = config["room_sizes"]
    for lv in parsed["levels"]:
        layout = layouts[lv["id"]]
        for r in lv["rooms"]:
            n = layout["rooms"][r["id"]]
            expected = sizes.get(r["type"], sizes["combat_small"])
            assert (n["w"], n["d"]) == (expected[0], expected[1]), (
                f"{lv['id']}/{r['id']} type={r['type']} : taille {n['w']}x{n['d']}, attendu {expected}"
            )

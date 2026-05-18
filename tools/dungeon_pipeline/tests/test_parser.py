"""Tests pour parser/drawio_to_json.py.

Lance les tests :
    cd tools/dungeon_pipeline && pytest -v
"""
from __future__ import annotations

import re
from pathlib import Path

import pytest

from parser.drawio_to_json import (
    Edge,
    Vertex,
    classify_edge,
    classify_vertex,
    parse_drawio,
    parse_style,
)

REPO_ROOT = Path(__file__).resolve().parents[3]
DRAWIO_PATH = REPO_ROOT / "docs" / "design" / "levels" / "topology.drawio"


# ============================================================================
# Fixtures
# ============================================================================

@pytest.fixture(scope="module")
def parsed():
    assert DRAWIO_PATH.exists(), f"drawio absent à {DRAWIO_PATH}"
    return parse_drawio(DRAWIO_PATH)


def _level(parsed: dict, diagram_id: str) -> dict | None:
    return next((lv for lv in parsed["levels"] if lv["diagram_id"] == diagram_id), None)


def _error(parsed: dict, diagram_id: str) -> dict | None:
    return next((e for e in parsed["errors"] if e["diagram_id"] == diagram_id), None)


# ============================================================================
# Sanity checks sur le fichier source
# ============================================================================

def test_drawio_exists():
    assert DRAWIO_PATH.exists()


def test_schema_version(parsed):
    assert parsed["schema_version"] == 1


def test_legend_skipped(parsed):
    all_ids = [lv["diagram_id"] for lv in parsed["levels"]] + [
        e["diagram_id"] for e in parsed["errors"]
    ]
    assert "legend" not in all_ids


def test_eight_levels_processed(parsed):
    total = len(parsed["levels"]) + len(parsed["errors"])
    assert total == 8, f"Attendu 8 niveaux, vu {total}"
    ids = set(lv["diagram_id"] for lv in parsed["levels"]) | set(e["diagram_id"] for e in parsed["errors"])
    assert ids == {"n1", "n2", "n3", "n4", "n5", "n6", "n7", "n8"}


# ============================================================================
# Niveaux qui doivent parser OK (pas d'ambiguïté drawio)
# ============================================================================

@pytest.mark.parametrize("diagram_id", ["n1", "n2", "n6"])
def test_levels_without_ambiguities_parse_ok(parsed, diagram_id):
    lv = _level(parsed, diagram_id)
    err = _error(parsed, diagram_id)
    assert lv is not None, f"{diagram_id} devrait parser OK, erreur: {err['error'] if err else 'inconnue'}"


# ============================================================================
# Niveaux qui doivent échouer (ambiguïtés connues du drawio)
# ============================================================================

@pytest.mark.parametrize("diagram_id,expected_substring", [
    ("n3", "inatteignable"),       # plateformes non connectées latéralement
    ("n5", "unknown"),             # shaft #BBDEFB non classifié
    ("n7", "false_passage"),       # kind d'edge non supporté
    ("n8", "inatteignable"),       # plateformes ap1..ap7 non connectées au boss/dlock
])
def test_levels_with_ambiguities_raise(parsed, diagram_id, expected_substring):
    err = _error(parsed, diagram_id)
    lv = _level(parsed, diagram_id)
    assert err is not None, (
        f"{diagram_id} devrait échouer. Il a parsé OK avec "
        f"{len(lv['rooms']) if lv else '?'} rooms."
    )
    assert expected_substring.lower() in err["error"].lower(), (
        f"Erreur {diagram_id} attendue contenant {expected_substring!r}. "
        f"Reçu : {err['error']}"
    )


# ============================================================================
# Détails N1 (le niveau "modèle" — Caverne crystalline)
# ============================================================================

def test_n1_has_exactly_one_spawn(parsed):
    lv = _level(parsed, "n1")
    spawn_count = sum(1 for c in lv["contents"].values() if c.get("spawn"))
    assert spawn_count == 1
    assert lv["spawn_room"] == "entree"


def test_n1_has_boss(parsed):
    lv = _level(parsed, "n1")
    bosses = [r for r in lv["rooms"] if r["type"] == "boss_arena"]
    assert len(bosses) == 1
    assert "Golem" in bosses[0]["label"]


def test_n1_has_meta_fragment(parsed):
    lv = _level(parsed, "n1")
    frags = [rid for rid, c in lv["contents"].items() if c.get("meta_fragment")]
    assert len(frags) == 1


def test_n1_boss_door_unlock_keys(parsed):
    lv = _level(parsed, "n1")
    boss_doors = [d for d in lv["doors"] if d["locked"]]
    assert len(boss_doors) == 1
    assert set(boss_doors[0]["unlock_keys"]) == {"P1", "P2", "P3"}


def test_n1_puzzle_triggers_attached(parsed):
    lv = _level(parsed, "n1")
    triggers_seen: set[str] = set()
    for c in lv["contents"].values():
        for t in c.get("puzzle_triggers", []):
            triggers_seen.add(t)
    assert triggers_seen == {"P1", "P2", "P3"}


def test_n1_strata_assigned(parsed):
    lv = _level(parsed, "n1")
    strata = {r["stratum"] for r in lv["rooms"]}
    assert strata == {"0", "-1", "-2"}, f"N1 strata vues: {strata}"


def test_n1_inter_level_to_n2(parsed):
    lv = _level(parsed, "n1")
    assert lv["inter_level"] is not None
    assert lv["inter_level"]["target_level"] == "level_2"
    assert lv["inter_level"]["trigger"] == "on_boss_defeat"


def test_n6_no_level_after_or_inter_level_to_n7(parsed):
    lv = _level(parsed, "n6")
    assert lv["inter_level"]["target_level"] == "level_7"


# ============================================================================
# Tests unitaires des helpers
# ============================================================================

def test_parse_style_empty():
    assert parse_style("") == {}


def test_parse_style_basic():
    s = parse_style("rounded=1;fillColor=#fff;dashed")
    assert s == {"rounded": "1", "fillColor": "#fff", "dashed": "1"}


def test_parse_style_trailing_semicolon():
    s = parse_style("a=1;b=2;")
    assert s == {"a": "1", "b": "2"}


def test_classify_vertex_boss():
    v = Vertex(id="b", value="BOSS", style={"shape": "hexagon", "strokeWidth": "4"}, x=0, y=0, w=100, h=50)
    assert classify_vertex(v) == "boss_arena"


def test_classify_vertex_spawn():
    v = Vertex(id="s", value="P×4", style={"ellipse": "1"}, x=0, y=0, w=40, h=40)
    assert classify_vertex(v) == "spawn"


def test_classify_vertex_puzzle_trigger():
    v = Vertex(id="p1", value="P1", style={"ellipse": "1"}, x=0, y=0, w=40, h=40)
    assert classify_vertex(v) == "puzzle_trigger"


def test_classify_vertex_meta_fragment():
    v = Vertex(id="f", value="", style={"shape": "mxgraph.basic.star"}, x=0, y=0, w=40, h=40)
    assert classify_vertex(v) == "meta_fragment"


def test_classify_vertex_room():
    v = Vertex(id="r", value="Hall", style={"rounded": "1", "fillColor": "#9FA8DA"}, x=0, y=0, w=200, h=100)
    assert classify_vertex(v) == "room"


def test_classify_vertex_boss_door():
    v = Vertex(
        id="d",
        value="",
        style={"rhombus": "1", "strokeWidth": "4", "strokeColor": "#E53935"},
        x=0, y=0, w=50, h=50,
    )
    assert classify_vertex(v) == "boss_door"


def test_classify_vertex_normal_door():
    v = Vertex(
        id="d",
        value="",
        style={"rhombus": "1", "strokeWidth": "1", "strokeColor": "#000000"},
        x=0, y=0, w=40, h=40,
    )
    assert classify_vertex(v) == "door"


def test_classify_vertex_shaft_is_unknown():
    """Le shaft (lift_lbl) de N5 doit ressortir comme unknown pour erreur explicite."""
    v = Vertex(
        id="lift_lbl",
        value="Ascenseur central",
        style={"rounded": "0", "fillColor": "#BBDEFB", "strokeColor": "#1976D2"},
        x=0, y=0, w=60, h=600,
    )
    assert classify_vertex(v) == "unknown"


def test_classify_edge_secret():
    e = Edge(id="e", value="", style={"dashed": "1", "dashPattern": "2 2"}, source="a", target="b")
    assert classify_edge(e) == "secret_passage"


def test_classify_edge_stairs_label():
    e = Edge(id="e", value="↕ escalier", style={"endArrow": "classic", "startArrow": "classic"}, source="a", target="b")
    assert classify_edge(e) == "stairs"


def test_classify_edge_elevator():
    e = Edge(id="e", value="lift", style={"strokeColor": "#1976D2", "strokeWidth": "3"}, source="a", target="b")
    assert classify_edge(e) == "elevator"


def test_classify_edge_jump():
    e = Edge(id="e", value="jump", style={"dashed": "1", "dashPattern": "8 4"}, source="a", target="b")
    assert classify_edge(e) == "jump_required"


def test_classify_edge_one_way_drop():
    e = Edge(id="e", value="drop ↓", style={"strokeColor": "#FF6D00", "strokeWidth": "3"}, source="a", target="b")
    assert classify_edge(e) == "one_way_drop"


def test_classify_edge_zero_g():
    e = Edge(id="e", value="dérive", style={"dashed": "1", "dashPattern": "2 4"}, source="a", target="b")
    assert classify_edge(e) == "zero_g_drift"


def test_classify_edge_false_passage():
    e = Edge(id="e", value="faux passage", style={"dashed": "1", "strokeColor": "#9E9E9E"}, source="a", target="b")
    assert classify_edge(e) == "false_passage"


def test_classify_edge_default_corridor():
    e = Edge(id="e", value="", style={}, source="a", target="b")
    assert classify_edge(e) == "corridor"

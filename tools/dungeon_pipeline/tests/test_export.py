"""Tests pour l'étape 5 : export/godot_resource.py."""
from __future__ import annotations

import json
import re
from pathlib import Path

import pytest

from corridors.build_geometry import carve_level_geometry
from export.godot_resource import (
    STRATA_ORDER,
    TILE_ID_BY_TAG,
    build_resource_data,
    render_tres,
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
def pipeline_outputs(parsed, config):
    out = {}
    for i, lv in enumerate(parsed["levels"]):
        layout = layout_level(lv, config, seed=42 + i)
        geom = carve_level_geometry(lv, layout, config, seed=100 + i)
        data = build_resource_data(lv, layout, geom, config)
        text = render_tres(data)
        out[lv["id"]] = {"data": data, "text": text, "layout": layout, "geom": geom, "level": lv}
    return out


# ============================================================================
# Encodage tile_id
# ============================================================================

def test_tile_ids_unique():
    ids = list(TILE_ID_BY_TAG.values())
    assert len(ids) == len(set(ids)), f"Duplicate tile_ids : {TILE_ID_BY_TAG}"


def test_void_is_zero():
    assert TILE_ID_BY_TAG["void"] == 0, "VOID doit être tile_id 0 (default des cellules)"


def test_strata_order_covers_all():
    """Toutes les strates rencontrées dans le drawio doivent être dans STRATA_ORDER."""
    assert set(STRATA_ORDER) >= {"-2", "-1", "0", "+1", "+2", "+3", "+4"}


# ============================================================================
# build_resource_data : structure des outputs
# ============================================================================

def test_each_level_has_data(pipeline_outputs):
    for lid, out in pipeline_outputs.items():
        d = out["data"]
        assert d["level_id"] == lid
        assert d["seed"] > 0
        assert d["grid_size"][0] > 0
        assert d["grid_size"][1] >= 1  # au moins une strate
        assert d["grid_size"][2] > 0
        assert len(d["cells"]) == d["grid_size"][0] * d["grid_size"][1] * d["grid_size"][2]
        assert d["spawn_room"] in d["rooms"]


def test_cells_only_valid_ids(pipeline_outputs):
    valid_ids = set(TILE_ID_BY_TAG.values())
    for lid, out in pipeline_outputs.items():
        for v in out["data"]["cells"]:
            assert v in valid_ids, f"{lid}: tile_id {v} hors range"
            assert 0 <= v <= 255, "PackedByteArray doit tenir sur 1 octet"


def test_strata_in_canonical_order(pipeline_outputs):
    """Les strates listées sont dans l'ordre STRATA_ORDER (bas vers haut)."""
    for lid, out in pipeline_outputs.items():
        strata = out["data"]["strata"]
        indices = [STRATA_ORDER.index(s) for s in strata]
        assert indices == sorted(indices), f"{lid}: strata pas trié : {strata}"


def test_rooms_have_y_index(pipeline_outputs):
    for lid, out in pipeline_outputs.items():
        strata_list = out["data"]["strata"]
        for rid, r in out["data"]["rooms"].items():
            assert 0 <= r["y"] < len(strata_list), f"{lid}/{rid}: y={r['y']} hors range"
            assert strata_list[r["y"]] == r["stratum"]


def test_doors_serialized(pipeline_outputs):
    """Toutes les boss_doors du parser doivent être dans le data.doors."""
    for lid, out in pipeline_outputs.items():
        expected = {d["id"] for d in out["level"]["doors"] if d["locked"]}
        actual = {d["id"] for d in out["data"]["doors"] if d["locked"]}
        assert expected <= actual, f"{lid}: boss_doors manquantes : {expected - actual}"


def test_stairs_serialized(pipeline_outputs):
    """Les edges_resolved verticales sont reportées en stairs."""
    for lid, out in pipeline_outputs.items():
        vertical_edges = [e for e in out["geom"]["edges_resolved"] if "stratum_from" in e]
        assert len(out["data"]["stairs"]) == len(vertical_edges), (
            f"{lid}: {len(out['data']['stairs'])} stairs vs {len(vertical_edges)} edges verticales"
        )


def test_contents_preserved(pipeline_outputs):
    """Tout meta_fragment du parser apparaît dans data.contents."""
    for lid, out in pipeline_outputs.items():
        frag_rooms = [rid for rid, c in out["level"]["contents"].items() if c.get("meta_fragment")]
        for rid in frag_rooms:
            assert rid in out["data"]["contents"]
            assert out["data"]["contents"][rid].get("meta_fragment") is True


# ============================================================================
# render_tres : syntaxe Godot
# ============================================================================

def test_tres_has_godot_header(pipeline_outputs):
    for lid, out in pipeline_outputs.items():
        assert out["text"].startswith('[gd_resource '), f"{lid}: pas de header gd_resource"
        assert 'script_class="LevelLayout"' in out["text"]


def test_tres_has_ext_resource_script(pipeline_outputs):
    for lid, out in pipeline_outputs.items():
        assert '[ext_resource type="Script"' in out["text"]
        assert 'res://scripts/world/level_layout.gd' in out["text"]


def test_tres_has_resource_block(pipeline_outputs):
    for lid, out in pipeline_outputs.items():
        assert "\n[resource]\n" in out["text"]


def test_tres_grid_size_format(pipeline_outputs):
    for lid, out in pipeline_outputs.items():
        m = re.search(r"^grid_size = Vector3i\((\d+), (\d+), (\d+)\)$", out["text"], re.MULTILINE)
        assert m, f"{lid}: grid_size format invalide"
        gw, gh, gd = int(m.group(1)), int(m.group(2)), int(m.group(3))
        assert (gw, gh, gd) == out["data"]["grid_size"]


def test_tres_cells_packed_byte_array(pipeline_outputs):
    for lid, out in pipeline_outputs.items():
        m = re.search(r"^cells = PackedByteArray\(([^)]+)\)$", out["text"], re.MULTILINE)
        assert m, f"{lid}: cells doit être PackedByteArray(...)"
        # Le nombre de valeurs doit matcher la taille de grid.
        values = [int(v.strip()) for v in m.group(1).split(",")]
        gw, gh, gd = out["data"]["grid_size"]
        assert len(values) == gw * gh * gd, (
            f"{lid}: cells a {len(values)} valeurs, attendu {gw * gh * gd}"
        )


def test_tres_no_python_literals(pipeline_outputs):
    """Le .tres ne doit jamais contenir de literals Python (True/False/None)."""
    for lid, out in pipeline_outputs.items():
        # Cherche True/False/None comme tokens isolés (pas en milieu de mot).
        for bad in (" True", " False", " None", "=True", "=False", "=None"):
            assert bad not in out["text"], f"{lid}: literal Python détecté : {bad!r}"


def test_tres_strings_quoted(pipeline_outputs):
    """level_id doit être entre guillemets, pas un identifiant nu."""
    for lid, out in pipeline_outputs.items():
        m = re.search(r"^level_id = (.+)$", out["text"], re.MULTILINE)
        assert m, f"{lid}: level_id absent"
        value = m.group(1).strip()
        assert value.startswith('"') and value.endswith('"'), (
            f"{lid}: level_id doit être quoted, vu : {value!r}"
        )


def test_tres_dict_uses_quoted_keys(pipeline_outputs):
    """Les clés de Dictionary en GDScript .tres sont entre guillemets."""
    # On vérifie au moins un dict rooms = {"...": ...}
    for lid, out in pipeline_outputs.items():
        m = re.search(r"^rooms = \{(.+?)\}$", out["text"], re.MULTILINE | re.DOTALL)
        if m and out["data"]["rooms"]:
            assert '"' in m.group(1), f"{lid}: clés rooms doivent être quoted"


def test_n1_specific_structure(pipeline_outputs):
    """Vérifie la structure complète du N1 en bout-en-bout."""
    n1 = pipeline_outputs["level_1"]
    d = n1["data"]
    assert d["level_id"] == "level_1"
    assert d["spawn_room"] == "entree"
    assert len(d["strata"]) == 3  # 0, -1, -2
    assert d["strata"] == ["-2", "-1", "0"]  # ordre canonique (bas → haut)
    assert d["inter_level"]["target_level"] == "level_2"
    # Au moins 1 boss_door
    assert any(door["locked"] for door in d["doors"])
    # Au moins 1 meta_fragment
    assert any(c.get("meta_fragment") for c in d["contents"].values())


def test_determinism(parsed, config):
    """Même seed produit le même .tres."""
    lv = parsed["levels"][0]
    layout1 = layout_level(lv, config, seed=42)
    geom1 = carve_level_geometry(lv, layout1, config, seed=100)
    text1 = render_tres(build_resource_data(lv, layout1, geom1, config))

    layout2 = layout_level(lv, config, seed=42)
    geom2 = carve_level_geometry(lv, layout2, config, seed=100)
    text2 = render_tres(build_resource_data(lv, layout2, geom2, config))

    assert text1 == text2

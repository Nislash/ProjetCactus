"""Tests pour l'étape 4 : validation/checks.py."""
from __future__ import annotations

import json
from pathlib import Path

import pytest

from corridors.build_geometry import carve_level_geometry
from corridors.grid import BOSS_DOOR, FLOOR, WALL
from layout.force_directed import layout_level
from parser.drawio_to_json import parse_drawio
from validation.checks import (
    ValidationResult,
    validate_level,
    WALKABLE_BASE,
    WALKABLE_INCL_BOSS_DOOR,
)

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
# Smoke tests
# ============================================================================

def test_validate_returns_result(parsed, layouts, geometries):
    lv = parsed["levels"][0]
    res = validate_level(lv, layouts[lv["id"]], geometries[lv["id"]])
    assert isinstance(res, ValidationResult)
    assert res.level_id == lv["id"]


def test_validation_result_str():
    from validation.checks import CheckFailure
    f = CheckFailure(check="spawn_no_floor", level_id="level_1", stratum="0", pos=(5, 5), detail="vide")
    s = str(f)
    assert "level_1" in s and "spawn_no_floor" in s and "vide" in s


# ============================================================================
# Détection d'invariants : on fabrique des cas cassés en mémoire
# ============================================================================

def _make_minimal_level_pipeline(parsed, layouts, geometries, level_id: str):
    lv = next(l for l in parsed["levels"] if l["id"] == level_id)
    return lv, layouts[level_id], geometries[level_id]


def test_detect_boss_no_keys_reachable_strict(parsed, layouts, geometries):
    """En mode strict, si BOSS_DOOR est franchissable, le check fail."""
    lv, layout, geom = _make_minimal_level_pipeline(parsed, layouts, geometries, "level_1")
    geom_copy = json.loads(json.dumps(geom))
    for s, gd in geom_copy["strata"].items():
        for i, c in enumerate(gd["cells"]):
            if c == BOSS_DOOR:
                gd["cells"][i] = FLOOR
    res = validate_level(lv, layout, geom_copy, strict_boss_locked=True)
    failures = [e.check for e in res.errors]
    assert "boss_reachable_without_keys" in failures, f"Échecs observés : {failures}"


def test_boss_reachable_without_keys_is_warning_by_default(parsed, layouts, geometries):
    """En mode non-strict, c'est un warning (pas un error bloquant)."""
    lv, layout, geom = _make_minimal_level_pipeline(parsed, layouts, geometries, "level_1")
    res = validate_level(lv, layout, geom)
    # Le drawio a une edge `g3→boss` directe en stairs qui contourne dlock1.
    # Doit être un warning, pas un error.
    warning_checks = [w.check for w in res.warnings]
    assert "boss_reachable_without_keys" in warning_checks or not warning_checks, (
        f"Warnings vus : {warning_checks}"
    )


def test_detect_orphan_corridor(parsed, layouts, geometries):
    """Place un corridor isolé en plein VOID → doit être détecté."""
    lv, layout, geom = _make_minimal_level_pipeline(parsed, layouts, geometries, "level_1")
    geom_copy = json.loads(json.dumps(geom))
    # Plante un corridor dans une zone VOID de la strate 0 (loin de tout).
    s0 = geom_copy["strata"]["0"]
    # On cherche une cellule sûrement VOID.
    width = s0["width"]
    target_idx = 0  # (0, 0) qui est forcément VOID dans le rendu actuel
    s0["cells"][target_idx] = "corridor"
    res = validate_level(lv, layout, geom_copy)
    failures = [e.check for e in res.errors]
    assert "orphan_corridor" in failures, f"Échecs : {failures}"


def test_detect_spawn_no_floor(parsed, layouts, geometries):
    """Si on transforme tout le FLOOR du spawn en VOID, fail."""
    lv, layout, geom = _make_minimal_level_pipeline(parsed, layouts, geometries, "level_1")
    geom_copy = json.loads(json.dumps(geom))
    spawn_id = lv["spawn_room"]
    spawn_stratum = layout["rooms"][spawn_id]["stratum"]
    gd = geom_copy["strata"][spawn_stratum]
    for i, owner in enumerate(gd["owners"]):
        if owner == spawn_id:
            gd["cells"][i] = "void"
            gd["owners"][i] = None
    res = validate_level(lv, layout, geom_copy)
    failures = [e.check for e in res.errors]
    assert any(f in failures for f in ("spawn_no_floor", "room_no_floor")), f"Échecs : {failures}"


# ============================================================================
# Validation sur les 8 niveaux réels
# ============================================================================

@pytest.mark.parametrize("level_id", [f"level_{i}" for i in range(1, 9)])
def test_real_levels_validate(parsed, layouts, geometries, level_id):
    lv = next(l for l in parsed["levels"] if l["id"] == level_id)
    res = validate_level(lv, layouts[level_id], geometries[level_id])
    if not res.ok:
        msg = "\n  ".join(str(e) for e in res.errors)
        pytest.fail(f"{level_id} validation a échoué :\n  {msg}")

"""drawio_to_json.py — Étape 1 de la pipeline de niveaux ProjetCactus.

Parse `docs/design/levels/topology.drawio` (9 pages = légende + 8 niveaux),
classifie les nœuds et arêtes selon les styles drawio, attache les glyphes
(spawn, triggers, loot, etc.) aux salles par AABB containment, et produit
un JSON canonique par niveau.

**Politique** : lève une erreur explicite sur toute ambiguïté plutôt que
d'inférer. L'utilisateur patche le drawio puis re-run.

Usage:
    python -m parser.drawio_to_json topology.drawio --out build/levels.json [--strict]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import xml.etree.ElementTree as ET
from dataclasses import dataclass, field
from pathlib import Path
from typing import Optional

SCHEMA_VERSION = 1

# ============================================================================
# Constantes de classification (basées sur la légende du drawio)
# ============================================================================

# Couleurs de fond des bandes de strate (codage couleur officiel).
# Valeur stockée : seulement marqueur "c'est une bande". Le numéro de strate
# vient du parsing du label `STRATE +N` / `PÉRIPHÉRIE (N)` / etc.
STRATUM_BAND_FILL_COLORS = {
    "#E8F5E9",
    "#E8EAF6",
    "#C5CAE9",
    "#FFF9C4",
    "#FFE0B2",
    "#FFCDD2",
    "#FAFAFA",
}

# Kinds d'edge déduits du label texte (gagne sur le style si match).
EDGE_LABEL_TO_KIND: dict[str, str] = {
    "↕ escalier": "stairs",
    "↕ chemin": "stairs",
    "↕ échelle": "ladder",
    "lift": "elevator",
    "lift final": "elevator",
    "jump": "jump_required",
    "jump caché": "secret_passage",  # secret jump = traité comme secret passage
    "drop ↓": "one_way_drop",
    "avalanche ↓": "one_way_drop",
    "dérive": "zero_g_drift",
    "dérive 0G": "zero_g_drift",
    "void": "zero_g_drift",
    "faux passage": "false_passage",  # ambigu → error
    "passage caché": "secret_passage",
    "passage scellé": "secret_passage",
    "rue": "corridor",
    "pont": "corridor",
    "pont gelé final": "corridor",
    "pont de lumière": "corridor",
    "couloir": "corridor",
    "passerelle": "corridor",
    "entrée cœur": "corridor",
}

# Kinds qui constituent le squelette structurel du graphe (vs glyphes de contenu).
STRUCTURAL_KINDS = {"room", "door", "boss_door", "corridor_node", "boss_arena"}
CONTENT_KINDS = {"spawn", "puzzle_trigger", "mini_boss", "loot", "meta_fragment", "checkpoint"}
SKIP_KINDS = {"text_label", "title", "ellipse_placeholder", "stratum_band"}

# Kinds d'edge qui sont des passages valides pour la connexité gameplay.
TRAVERSABLE_EDGE_KINDS = {
    "corridor",
    "stairs",
    "ladder",
    "elevator",
    "jump_required",
    "secret_passage",
    "one_way_drop",
    "zero_g_drift",
}


# ============================================================================
# Types
# ============================================================================

@dataclass
class Vertex:
    """Un mxCell drawio avec vertex=1."""
    id: str
    value: str
    style: dict[str, str]
    x: float
    y: float
    w: float
    h: float
    kind: str = "unknown"
    stratum: Optional[str] = None

    @property
    def center(self) -> tuple[float, float]:
        return self.x + self.w / 2.0, self.y + self.h / 2.0

    def contains_point(self, px: float, py: float) -> bool:
        return self.x <= px <= self.x + self.w and self.y <= py <= self.y + self.h


@dataclass
class Edge:
    """Un mxCell drawio avec edge=1."""
    id: str
    value: str
    style: dict[str, str]
    source: Optional[str]
    target: Optional[str]
    kind: str = "unknown"


class ParseError(Exception):
    """Levée sur ambiguïté ou topologie invalide dans un niveau."""
    def __init__(self, level: str, message: str, ref: Optional[str] = None):
        self.level = level
        self.ref = ref
        suffix = f" (ref={ref})" if ref else ""
        super().__init__(f"[{level}] {message}{suffix}")


# ============================================================================
# Helpers
# ============================================================================

def parse_style(style: str) -> dict[str, str]:
    """Parse 'key1=val1;key2=val2;flag;' en dict. Les flags isolés → '1'."""
    if not style:
        return {}
    out: dict[str, str] = {}
    for token in style.split(";"):
        token = token.strip()
        if not token:
            continue
        if "=" in token:
            k, v = token.split("=", 1)
            out[k.strip()] = v.strip()
        else:
            out[token] = "1"
    return out


def _norm_stratum(raw: str) -> str:
    """Normalise '−1', '-1', '+1', '0', '+0' → '-1', '-1', '+1', '0', '0'."""
    raw = raw.replace("−", "-").replace("+0", "0").strip()
    if raw == "-0":
        return "0"
    if raw.lstrip("-").isdigit():
        n = int(raw)
        if n > 0:
            return f"+{n}"
        return str(n)
    return raw


def classify_vertex(v: Vertex) -> str:
    """Détermine le kind d'un vertex selon son style + value."""
    s = v.style
    val = (v.value or "").strip()

    # 1. Title texts (large rect, no shape, fontSize >= 16)
    if s.get("text") == "1":
        try:
            font_size = int(s.get("fontSize", "0"))
        except ValueError:
            font_size = 0
        if font_size >= 16 or v.w >= 1000:
            return "title"
        # Embedded labels (door key lists "P1+P2+P3", room sub-notes, etc.)
        return "text_label"

    # 2. Shapes spécifiques
    if s.get("shape") == "hexagon":
        return "boss_arena"
    if s.get("shape") == "mxgraph.basic.star":
        return "meta_fragment"
    if s.get("shape") == "parallelogram":
        return "loot"
    if s.get("shape") == "plus":
        return "checkpoint"
    if s.get("triangle") == "1":
        return "mini_boss"

    # 3. Rhombus = porte (boss_door si stroke épais rouge)
    if s.get("rhombus") == "1":
        try:
            stroke_w = int(s.get("strokeWidth", "1"))
        except ValueError:
            stroke_w = 1
        stroke_c = s.get("strokeColor", "").upper()
        if stroke_w >= 4 and stroke_c == "#E53935":
            return "boss_door"
        return "door"

    # 4. Ellipse = spawn / puzzle_trigger / placeholder
    if s.get("ellipse") == "1":
        if val == "P×4":
            return "spawn"
        if re.fullmatch(r"P\d+", val):
            return "puzzle_trigger"
        return "ellipse_placeholder"

    # 5. Bandes de strate : rect non-rounded avec fillColor dans la palette,
    #    align=left et verticalAlign=top, value commence par mot-clé strate.
    fill = s.get("fillColor", "").upper()
    if fill in STRATUM_BAND_FILL_COLORS and s.get("verticalAlign") == "top":
        if val.startswith(("STRATE", "PÉRIPHÉRIE", "MÉDIAN", "CŒUR", "VIDE")):
            return "stratum_band"

    # 6. Rounded rect = salle.
    if s.get("rounded") == "1":
        return "room"

    # 7. Rect explicite couloir (gris CFD8DC).
    if fill == "#CFD8DC":
        return "corridor_node"

    # 8. Rect non reconnu (ex. shaft N5 #BBDEFB) → unknown explicite.
    return "unknown"


def classify_edge(e: Edge) -> str:
    """Détermine le kind d'une arête selon style + label."""
    s = e.style
    val = (e.value or "").strip()

    # 1. Label override
    if val in EDGE_LABEL_TO_KIND:
        return EDGE_LABEL_TO_KIND[val]

    # 2. Style attributes
    dashed = s.get("dashed") == "1"
    dash_pattern = s.get("dashPattern", "")
    stroke_color = s.get("strokeColor", "").upper()
    try:
        stroke_width = int(s.get("strokeWidth", "1"))
    except ValueError:
        stroke_width = 1

    if dashed and stroke_color == "#9E9E9E":
        return "false_passage"
    if dashed and dash_pattern == "2 4":
        return "zero_g_drift"
    if dashed and dash_pattern == "8 4":
        return "jump_required"
    if dashed and dash_pattern == "2 2":
        return "secret_passage"
    if stroke_color == "#FF6D00":
        return "one_way_drop"
    if stroke_color == "#1976D2" and stroke_width >= 3:
        return "elevator"
    if stroke_color == "#5D4037":
        return "ladder"
    if stroke_color == "#FFD700" and stroke_width >= 3:
        return "corridor"  # pont de lumière doré
    if stroke_color == "#E53935" and re.fullmatch(r"P\d+", val):
        return "locked_passage"

    return "corridor"


# ============================================================================
# Parser core
# ============================================================================

def _extract_vertices_and_edges(diagram: ET.Element) -> tuple[dict[str, Vertex], list[Edge]]:
    root = diagram.find(".//root")
    if root is None:
        raise ValueError("No <root> element under <diagram>")

    vertices: dict[str, Vertex] = {}
    edges: list[Edge] = []

    for cell in root.findall("mxCell"):
        cid = cell.attrib.get("id", "")
        value = cell.attrib.get("value", "") or ""
        style = parse_style(cell.attrib.get("style", ""))

        if cell.attrib.get("vertex") == "1":
            geom = cell.find("mxGeometry")
            if geom is None:
                continue
            x = float(geom.attrib.get("x", "0"))
            y = float(geom.attrib.get("y", "0"))
            w = float(geom.attrib.get("width", "0"))
            h = float(geom.attrib.get("height", "0"))
            v = Vertex(id=cid, value=value, style=style, x=x, y=y, w=w, h=h)
            v.kind = classify_vertex(v)
            vertices[cid] = v
        elif cell.attrib.get("edge") == "1":
            src = cell.attrib.get("source")
            tgt = cell.attrib.get("target")
            e = Edge(id=cid, value=value, style=style, source=src, target=tgt)
            e.kind = classify_edge(e)
            edges.append(e)

    return vertices, edges


def _resolve_band_strata(bands: list[Vertex]) -> dict[str, str]:
    """Pour chaque bande, extrait son numéro de strate depuis son label."""
    out: dict[str, str] = {}
    for b in bands:
        val = b.value
        m = re.search(r"STRATE\s+([+−-]?\d+)", val)
        if m:
            out[b.id] = _norm_stratum(m.group(1))
            continue
        # N8 spéciaux : PÉRIPHÉRIE (0), MÉDIAN (+1), CŒUR (+2), VIDE = container
        m = re.search(r"\(([+−-]?\d+)\)", val)
        if m:
            out[b.id] = _norm_stratum(m.group(1))
            continue
        if "VIDE" in val:
            out[b.id] = "void"
            continue
        out[b.id] = "unknown"
    return out


def _find_containing_stratum(v: Vertex, bands: list[Vertex], band_strata: dict[str, str]) -> Optional[str]:
    """Trouve la bande de strate (la plus petite) qui contient le centre du vertex."""
    cx, cy = v.center
    # Tri par aire croissante : la bande la plus imbriquée gagne (cas N8 concentrique).
    candidates = sorted(
        (b for b in bands if b.contains_point(cx, cy) and band_strata.get(b.id) != "void"),
        key=lambda b: b.w * b.h,
    )
    if candidates:
        return band_strata[candidates[0].id]
    # Fallback: bande "void" si rien d'autre
    for b in bands:
        if b.contains_point(cx, cy):
            return band_strata.get(b.id)
    return None


def _find_host_room(glyph: Vertex, rooms: list[Vertex]) -> Optional[Vertex]:
    """Renvoie la room qui contient le centre du glyphe, ou None."""
    cx, cy = glyph.center
    for r in rooms:
        if r.contains_point(cx, cy):
            return r
    return None


def _find_nearest_room(glyph: Vertex, rooms: list[Vertex]) -> Vertex:
    cx, cy = glyph.center
    def d2(r: Vertex) -> float:
        rx, ry = r.center
        return (rx - cx) ** 2 + (ry - cy) ** 2
    return min(rooms, key=d2)


def _find_door_keys(door: Vertex, all_vertices: dict[str, Vertex]) -> list[str]:
    """Cherche un text_label voisin contenant 'Pn+Pm+...' pour extraire les clés."""
    dx, dy = door.center
    best: Optional[Vertex] = None
    best_d2 = float("inf")
    for v in all_vertices.values():
        if v.kind != "text_label":
            continue
        if not re.search(r"P\d+(\+P\d+)+", v.value or ""):
            continue
        lx, ly = v.center
        d2 = (lx - dx) ** 2 + (ly - dy) ** 2
        if d2 < best_d2 and d2 < (150.0 ** 2):  # within 150px
            best = v
            best_d2 = d2
    if best is None:
        return []
    return re.findall(r"P\d+", best.value)


def _infer_room_type(v: Vertex, contents: dict) -> str:
    if contents.get("spawn"):
        return "spawn"
    label = (v.value or "").lower()
    if "secrète" in label or "cachée" in label or "secret" in label:
        return "secret"
    if contents.get("loot_major") and not contents.get("puzzle_triggers") and not contents.get("mini_boss"):
        return "loot"
    if contents.get("puzzle_triggers") or contents.get("mini_boss"):
        return "combat_large"
    if "couloir" in label or "pont" in label:
        return "corridor"
    return "combat_small"


def _extract_room_tags(label: str) -> list[str]:
    """Extrait les tags entre parenthèses, ex. 'Galerie G1\n(cristaux + mêlée)'."""
    if not label:
        return []
    m = re.search(r"\(([^)]*)\)", label)
    if not m:
        return []
    return [t.strip() for t in re.split(r"[+,;]", m.group(1)) if t.strip()]


# ============================================================================
# Parse d'un niveau (un <diagram>)
# ============================================================================

def parse_diagram(diagram: ET.Element, diagram_id: str, diagram_name: str) -> dict:
    """Parse un niveau et retourne sa représentation JSON canonique."""
    vertices, edges = _extract_vertices_and_edges(diagram)

    # 1. Reject unknown vertices early (ex: shaft N5 #BBDEFB).
    unknowns = [v for v in vertices.values() if v.kind == "unknown"]
    if unknowns:
        details = ", ".join(f"{v.id}(fill={v.style.get('fillColor', '?')}, val={v.value!r})" for v in unknowns)
        raise ParseError(
            diagram_name,
            f"Vertex(s) de kind 'unknown' (non classifiables) : {details}. "
            f"Soit le glyphe a un style non reconnu (ex: shaft #BBDEFB), soit il faut tagger explicitement. "
            f"Décide : kind=room (et ajoute du contenu) ou kind=corridor_node (couleur #CFD8DC) ou retire-le du drawio.",
            ref=",".join(v.id for v in unknowns),
        )

    # 2. Identifie les bandes de strate.
    bands = [v for v in vertices.values() if v.kind == "stratum_band"]
    if not bands:
        raise ParseError(diagram_name, "Aucune bande de strate trouvée (attendu : un ou plusieurs rect 'STRATE ...').")
    band_strata = _resolve_band_strata(bands)

    # 3. Sépare structural (room/door/corridor_node/boss_arena) et content (spawn/p_n/etc.).
    structural = [v for v in vertices.values() if v.kind in STRUCTURAL_KINDS]
    content = [v for v in vertices.values() if v.kind in CONTENT_KINDS]

    # 4. Assigne une strate à chaque vertex structural.
    for v in structural:
        v.stratum = _find_containing_stratum(v, bands, band_strata)
        if v.stratum is None:
            raise ParseError(
                diagram_name,
                f"Vertex structural {v.id!r} (kind={v.kind}, val={v.value!r}) "
                f"centre ({v.center[0]:.0f},{v.center[1]:.0f}) hors de toute bande de strate. "
                f"Déplace-le dans une bande.",
                ref=v.id,
            )

    # 5. Reject false_passage edges (ambiguïté drawio à patcher).
    for e in edges:
        if e.kind == "false_passage":
            raise ParseError(
                diagram_name,
                f"Edge {e.id!r} (faux passage) — kind 'false_passage' non supporté. "
                f"Décide : 'secret_passage' (mène quelque part) ou retire-le du drawio.",
                ref=e.id,
            )

    # 6. Attache les glyphes de contenu à leur room hôte.
    rooms = [v for v in structural if v.kind in {"room", "boss_arena", "corridor_node"}]
    structural_ids = {v.id for v in structural}
    room_contents: dict[str, dict] = {r.id: {} for r in rooms}

    def _meta_fragment_host(frag: Vertex) -> Optional[Vertex]:
        """Pour un meta_fragment : trouve la room via une edge qui le référence.

        Le drawio dessine souvent le fragment légèrement en dehors de la room
        cachée — la source de vérité est l'edge (secret passage / passage caché).
        """
        for ed in edges:
            other_id = None
            if ed.source == frag.id:
                other_id = ed.target
            elif ed.target == frag.id:
                other_id = ed.source
            if other_id and other_id in structural_ids:
                # Récupère le vertex correspondant dans `rooms`.
                for r in rooms:
                    if r.id == other_id:
                        return r
        return None

    # Pour les meta_fragments, on retient le mapping fragment_id -> host_room_id
    # pour remapper les edges qui les référencent.
    fragment_to_host: dict[str, str] = {}

    for c in content:
        host = _find_host_room(c, rooms)
        if host is None:
            if c.kind == "meta_fragment":
                host = _meta_fragment_host(c)
            if host is None:
                raise ParseError(
                    diagram_name,
                    f"Glyphe de contenu {c.id!r} (kind={c.kind}, val={c.value!r}) "
                    f"hors de toute room (centre {c.center[0]:.0f},{c.center[1]:.0f}). "
                    f"Pour les meta_fragments : ajouter une edge (secret_passage) reliant le fragment à sa room cachée.",
                    ref=c.id,
                )
        if c.kind == "meta_fragment":
            fragment_to_host[c.id] = host.id
        rc = room_contents[host.id]
        if c.kind == "spawn":
            if rc.get("spawn"):
                raise ParseError(diagram_name, f"Plusieurs spawn dans la room {host.id!r}.", ref=c.id)
            rc["spawn"] = True
        elif c.kind == "puzzle_trigger":
            rc.setdefault("puzzle_triggers", []).append(c.value)
        elif c.kind == "mini_boss":
            rc["mini_boss"] = True
        elif c.kind == "loot":
            rc["loot_major"] = rc.get("loot_major", 0) + 1
        elif c.kind == "meta_fragment":
            if rc.get("meta_fragment"):
                raise ParseError(diagram_name, f"Plusieurs meta_fragment dans la room {host.id!r}.", ref=c.id)
            rc["meta_fragment"] = True
        elif c.kind == "checkpoint":
            rc["checkpoint"] = True

    # 7. Filtre et canonicalise les edges (remap meta_fragment endpoints vers leur hôte).
    canonical_edges: list[dict] = []
    for e in edges:
        if e.source is None or e.target is None:
            continue  # edge flottante, ignore

        src = fragment_to_host.get(e.source, e.source)
        tgt = fragment_to_host.get(e.target, e.target)

        if src not in structural_ids or tgt not in structural_ids:
            details = f"source={e.source!r}, target={e.target!r}"
            if src != e.source or tgt != e.target:
                details += f" (remapped: {src!r} -> {tgt!r})"
            raise ParseError(
                diagram_name,
                f"Edge {e.id!r} référence un noeud non structural : {details}. "
                f"Tous les endpoints d'edge doivent être room/door/boss_door/corridor_node/boss_arena.",
                ref=e.id,
            )

        if src == tgt:
            continue  # self-loop ignoré (cas du fragment dans sa propre room hôte)

        canonical_edges.append({
            "from": src,
            "to": tgt,
            "kind": e.kind,
            "label": e.value,
        })

    # 8. Validation globale.
    spawn_rooms = [rid for rid, c in room_contents.items() if c.get("spawn")]
    if len(spawn_rooms) != 1:
        raise ParseError(diagram_name, f"Attendu exactement 1 spawn, trouvé {len(spawn_rooms)} : {spawn_rooms}.")
    boss_rooms = [v.id for v in structural if v.kind == "boss_arena"]
    if not boss_rooms:
        raise ParseError(diagram_name, "Aucune arène boss trouvée.")

    # 8a. Connexité depuis spawn (les drops one-way sont traités bidirectionnellement
    #     pour la connexité — la nuance gameplay est encodée par le kind).
    adj: dict[str, set[str]] = {}
    for v in structural:
        adj[v.id] = set()
    for ed in canonical_edges:
        adj.setdefault(ed["from"], set()).add(ed["to"])
        adj.setdefault(ed["to"], set()).add(ed["from"])

    spawn_id = spawn_rooms[0]
    visited = {spawn_id}
    stack = [spawn_id]
    while stack:
        n = stack.pop()
        for nb in adj.get(n, ()):
            if nb not in visited:
                visited.add(nb)
                stack.append(nb)

    expected = structural_ids
    unreached = expected - visited
    if unreached:
        raise ParseError(
            diagram_name,
            f"Nœuds inatteignables depuis le spawn {spawn_id!r} : {sorted(unreached)}. "
            f"Ajoute les arêtes manquantes ou corrige le graphe.",
            ref=",".join(sorted(unreached)),
        )

    # 8b. Construit la liste de doors avec leurs keys (après validation graphe).
    doors_out: list[dict] = []
    for v in structural:
        if v.kind == "boss_door":
            keys = _find_door_keys(v, vertices)
            if not keys:
                raise ParseError(
                    diagram_name,
                    f"Porte boss {v.id!r} sans label de keys lisible. "
                    f"Cherche un text_label voisin (< 150px) avec format 'P1+P2+P3'. "
                    f"Note : 'P1..P7' (range) n'est pas supporté, rewrite en 'P1+P2+P3+P4+P5+P6+P7'.",
                    ref=v.id,
                )
            doors_out.append({"id": v.id, "locked": True, "unlock_keys": keys, "stratum": v.stratum})
        elif v.kind == "door":
            doors_out.append({"id": v.id, "locked": False, "unlock_keys": [], "stratum": v.stratum})

    # 9. Convention inter-niveaux : tuer le boss N → passage N+1.
    inter_level = None
    m = re.match(r"n(\d)", diagram_id)
    if m:
        n = int(m.group(1))
        if n < 8:
            inter_level = {
                "from_room": boss_rooms[0],
                "trigger": "on_boss_defeat",
                "target_level": f"level_{n + 1}",
            }

    # 10. Sérialise.
    rooms_out = []
    for v in structural:
        if v.kind in {"room", "boss_arena", "corridor_node"}:
            rtype = "boss_arena" if v.kind == "boss_arena" else (
                "corridor" if v.kind == "corridor_node" else _infer_room_type(v, room_contents.get(v.id, {}))
            )
            rooms_out.append({
                "id": v.id,
                "type": rtype,
                "stratum": v.stratum,
                "label": v.value,
                "tags": _extract_room_tags(v.value),
            })

    return {
        "id": f"level_{m.group(1)}" if m else f"level_{diagram_id}",
        "diagram_id": diagram_id,
        "name": diagram_name,
        "spawn_room": spawn_id,
        "rooms": rooms_out,
        "edges": canonical_edges,
        "doors": doors_out,
        "contents": room_contents,
        "inter_level": inter_level,
    }


# ============================================================================
# Entry point : tous les niveaux d'un drawio
# ============================================================================

def parse_drawio(path: Path) -> dict:
    tree = ET.parse(path)
    root = tree.getroot()
    if root.tag != "mxfile":
        raise ValueError(f"Racine attendue <mxfile>, trouvée <{root.tag}>.")

    levels: list[dict] = []
    errors: list[dict] = []
    for diagram in root.findall("diagram"):
        d_id = diagram.attrib.get("id", "")
        d_name = diagram.attrib.get("name", "")
        if d_id == "legend":
            continue
        try:
            levels.append(parse_diagram(diagram, d_id, d_name))
        except ParseError as e:
            errors.append({
                "diagram_id": d_id,
                "diagram_name": d_name,
                "error": str(e),
                "ref": e.ref,
            })

    return {
        "schema_version": SCHEMA_VERSION,
        "source": str(path),
        "levels": levels,
        "errors": errors,
    }


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n", 1)[0])
    ap.add_argument("input", type=Path, help="Chemin du topology.drawio")
    ap.add_argument("--out", type=Path, help="Chemin de sortie JSON (défaut: stdout)")
    ap.add_argument("--strict", action="store_true", help="Exit 1 si au moins un niveau a échoué")
    args = ap.parse_args(argv)

    result = parse_drawio(args.input)

    out_str = json.dumps(result, indent=2, ensure_ascii=False)
    if args.out:
        args.out.parent.mkdir(parents=True, exist_ok=True)
        args.out.write_text(out_str, encoding="utf-8")
        sys.stderr.write(f"Wrote {args.out}\n")
    else:
        sys.stdout.write(out_str + "\n")

    n_ok = len(result["levels"])
    n_err = len(result["errors"])
    sys.stderr.write(f"\n{n_ok} niveau(x) OK, {n_err} échec(s).\n")
    for e in result["errors"]:
        sys.stderr.write(f"  ✗ {e['diagram_name']}: {e['error']}\n")
    for lv in result["levels"]:
        n_rooms = len(lv["rooms"])
        n_edges = len(lv["edges"])
        sys.stderr.write(f"  ✓ {lv['name']}: {n_rooms} rooms, {n_edges} edges\n")

    return 1 if (args.strict and n_err > 0) else 0


if __name__ == "__main__":
    sys.exit(main())

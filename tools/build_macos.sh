#!/usr/bin/env bash
# Produit un build macOS jouable de ProjetCactus.
#
#   tools/build_macos.sh
#
# Trois choses que ce script fait et qu'un export depuis l'éditeur ne fait pas.
#
# 1. IL SYNCHRONISE LA LIB NATIVE. L'export n'empaquette que ce qui vit sous
#    `res://` ; les artefacts de `cargo build` sont recopiés dans le projet.
#
# 2. IL RETIRE PHYSIQUEMENT L'OUTILLAGE D'AGENT. `addons/godot_mcp` ouvre une
#    WebSocket locale et accepte des commandes, dont l'injection d'entrées.
#    L'`exclude_filter` du preset NE SUFFIT PAS : le plugin est déclaré dans
#    `[editor_plugins]` de `project.godot`, et Godot l'embarque malgré le
#    filtre (vérifié — les chemins étaient bien dans le .pck). On déplace donc
#    le dossier le temps de l'export. L'autoload `MCPBridge` est écrit pour
#    survivre à son absence.
#
# 3. IL VÉRIFIE LE RÉSULTAT. Un build qui embarque l'outillage ne se voit pas
#    à l'œil : le script fouille le .pck et échoue si une trace subsiste.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
cd "$root"

preset="macOS"
out="build/macos/ProjetCactus.app"
addon="godot/addons/godot_mcp"
stash="$(mktemp -d)/godot_mcp"
project="godot/project.godot"
project_backup="$(mktemp)"

# `cargo` vit dans ~/.cargo/bin, qui n'est pas dans le PATH d'un shell non
# interactif — le script échouait dès sa première ligne utile hors terminal.
[ -f "$HOME/.cargo/env" ] && . "$HOME/.cargo/env"

echo "==> Compilation de la lib Rust (release)"
(cd rust && cargo build --release --quiet)
tools/sync_native_lib.sh release

restore() {
  if [ -d "$stash" ]; then
    rm -rf "$addon"
    mv "$stash" "$addon"
  fi
  if [ -f "$project_backup" ]; then
    cp "$project_backup" "$project"
    rm -f "$project_backup"
  fi
}
trap restore EXIT

echo "==> Mise à l'écart de l'outillage d'agent"
cp "$project" "$project_backup"
mkdir -p "$(dirname "$stash")"
mv "$addon" "$stash"
# La déclaration de plugin doit partir avec le dossier, sinon l'éditeur cherche
# un plugin.cfg absent à chaque ouverture du projet pendant l'export.
python3 - "$project" <<'PY'
import sys, pathlib
p = pathlib.Path(sys.argv[1])
s = p.read_text(encoding="utf-8")
s = s.replace('enabled=PackedStringArray("res://addons/godot_mcp/plugin.cfg")',
              'enabled=PackedStringArray()')
p.write_text(s, encoding="utf-8")
PY

echo "==> Export « $preset »"
mkdir -p "$(dirname "$out")"
rm -rf "$out"
godot --headless --path godot --import >/dev/null 2>&1 || true
godot --headless --path godot --export-release "$preset" "../$out" 2>&1 \
  | grep -E "^ERROR|^SCRIPT ERROR" && { echo "Export en erreur." >&2; exit 1; } || true

if [ ! -d "$out" ]; then
  echo "Export échoué : $out absent." >&2
  exit 1
fi

echo "==> Vérification du paquet"
python3 - "$out" <<'PY'
import pathlib, sys
app = pathlib.Path(sys.argv[1])
packs = list(app.rglob("*.pck"))
if not packs:
    print("Aucun .pck dans le bundle.", file=sys.stderr); sys.exit(1)
data = packs[0].read_bytes()

# Ce qui ne doit PAS être là.
leaks = [n for n in (b"godot_mcp", b"mcp_runtime", b"127.0.0.1:6505") if n in data]
# Ce qui doit y être — un build amputé de son contenu passerait le test ci-dessus.
missing = [n for n in (b"cactus_native", b"level_01_cavern", b"antechamber", b"cave_drone") if n not in data]

for n in leaks:
    print(f"  FUITE : « {n.decode()} » est dans le .pck", file=sys.stderr)
for n in missing:
    print(f"  MANQUE : « {n.decode()} » absent du .pck", file=sys.stderr)
if leaks or missing:
    sys.exit(1)
print(f"  .pck propre et complet ({len(data) / 1048576:.0f} Mo)")
PY

echo "==> Build prêt : $out ($(du -sh "$out" | cut -f1))"
echo "    Lancer : open \"$out\""

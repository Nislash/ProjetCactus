#!/usr/bin/env bash
# Recopie les artefacts de `cargo build` dans le projet Godot.
#
# POURQUOI CETTE ÉTAPE EXISTE : l'export Godot n'empaquette que ce qui vit
# sous `res://`. Tant que le `.gdextension` pointait vers `rust/target/`, la
# lib native fonctionnait dans l'éditeur et DISPARAISSAIT du build — un jeu
# exporté qui démarre sans le moteur de boss, sans la moindre erreur.
#
# Usage :
#   tools/sync_native_lib.sh            # release (défaut)
#   tools/sync_native_lib.sh debug
set -euo pipefail

profile="${1:-release}"
root="$(cd "$(dirname "$0")/.." && pwd)"
src="$root/rust/target/$profile"
dst="$root/godot/addons/cactus_native/bin"
mkdir -p "$dst"

suffix=""
[ "$profile" = "debug" ] && suffix=".debug"

copied=0
for base in libcactus_native.dylib libcactus_native.so cactus_native.dll; do
  if [ -f "$src/$base" ]; then
    name="${base%.*}"; ext="${base##*.}"
    cp "$src/$base" "$dst/$name$suffix.$ext"
    echo "  $base → $dst/$name$suffix.$ext"
    copied=$((copied + 1))
  fi
done

if [ "$copied" -eq 0 ]; then
  echo "Aucun artefact dans $src — lancer d'abord : cd rust && cargo build --$profile" >&2
  exit 1
fi
echo "$copied bibliothèque(s) synchronisée(s) ($profile)."

# Rust / gdext setup

## Prérequis

- [rustup](https://rustup.rs/) installé
- Toolchain stable récente : `rustup default stable && rustup update`
- Targets cross-platform si on cross-compile (sinon, chaque machine compile pour son OS)

## Build

```bash
cd rust
cargo build           # debug → rust/target/debug/libcactus_native.{dylib,so,dll}
cargo build --release # release → rust/target/release/...
```

Le fichier `godot/addons/cactus_native/cactus_native.gdextension` pointe sur `../rust/target/debug/...` et `../rust/target/release/...`. Godot charge la lib au démarrage.

## Hot reload

`reloadable = true` dans `cactus_native.gdextension` permet à Godot 4.6 de recharger la lib sans relancer l'éditeur. Workflow :

1. Modifier code Rust
2. `cargo build`
3. Dans Godot, déclencher reload via menu Project > Reload Current Project (ou hot-reload auto sur certaines plateformes)

Si l'éditeur crashe au reload (problème connu sur certaines versions), relancer manuellement.

## Stratégie d'utilisation

GDScript par défaut. Rust pour les hotspots seulement :
- `combo_engine` — résolution arme×parchemin (M2)
- `boss_ai` — state machines de boss (M3)
- `procgen` — phase 2

Pour les nouvelles classes Rust :
```rust
#[derive(GodotClass)]
#[class(init, base=Node)]  // ou base=Node2D, Node3D, Resource selon besoin
struct MyClass {
    base: Base<Node>,
}

#[godot_api]
impl MyClass {
    #[func]
    fn my_method(&self, arg: GString) -> i32 { 42 }
}
```

## Tests

- Logique pure : `cargo test` dans `rust/`
- Tests d'intégration Godot : depuis GDScript via [GUT](https://github.com/bitwes/Gut) dans `godot/tests/`

## Debug

- `godot_print!("...")` pour logger depuis Rust → console Godot
- `breakpoint` GDB classique fonctionne sur la lib compilée en debug

## CI

Le workflow GitHub Actions doit :
1. `cargo check` (rapide)
2. `cargo build --release` (lent, parallèle par OS si on cross-compile)
3. `godot --headless --check-only godot/project.godot`


---

## La lib native doit vivre sous `res://` (● Opus, tâche #34)

Le `.gdextension` pointait vers `res://../rust/target/debug/…` — **hors du projet**. Ça fonctionne
dans l'éditeur, qui lit le disque librement. Mais **l'export Godot n'empaquette que ce qui vit sous
`res://`** : la bibliothèque disparaissait purement et simplement du build. Le jeu exporté démarrait
sans `BossAI`, sans erreur de compilation, sans message — juste sans boss.

Les chemins visent maintenant `res://addons/cactus_native/bin/`, et `tools/sync_native_lib.sh` y
recopie les artefacts de `cargo build`. Le dossier `bin/` est ignoré par git : c'est de la sortie de
compilation, elle se régénère.

```
cd rust && cargo build --release
tools/sync_native_lib.sh release     # ou: debug
```

`tools/build_macos.sh` enchaîne les deux automatiquement, et son contrôle final échoue si
`cactus_native` n'est pas dans le `.pck`.

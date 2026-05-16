//! Sélection de la cible. Scan le group "players" et garde le plus proche
//! dans aggro_range. Notion de focus : on garde la même cible pendant
//! `focus_duration` avant de potentiellement switcher (évite le yo-yo).

use godot::classes::SceneTree;
use godot::prelude::*;

/// Trouve / refresh la cible. Modifie `target_path` et `lock_time` en place.
/// Retourne la cible courante (Node3D) ou None si aucun joueur dans aggro.
pub fn pick_target(
    tree: Gd<SceneTree>,
    boss_pos: Vector3,
    aggro_range: f32,
    target_path: &mut NodePath,
    lock_time: &mut f32,
    focus_duration: f32,
) -> Option<Gd<Node3D>> {
    // Si on a déjà une cible verrouillée ET que le focus n'est pas écoulé,
    // on la garde tant qu'elle est encore vivante et à portée.
    if !target_path.is_empty() && *lock_time < focus_duration {
        if let Some(target) = resolve_target(&tree, target_path) {
            let pos = target.get_global_position();
            if boss_pos.distance_to(pos) <= aggro_range {
                return Some(target);
            }
        }
        // Cible invalide : on reset.
        *target_path = NodePath::default();
    }

    // Cherche le plus proche dans le group "players".
    let players_group: StringName = "players".into();
    let nodes = tree.clone().get_nodes_in_group(&players_group);
    let mut best: Option<Gd<Node3D>> = None;
    let mut best_dist_sq = aggro_range * aggro_range;
    for n in nodes.iter_shared() {
        let Ok(p) = n.try_cast::<Node3D>() else {
            continue;
        };
        let d = boss_pos.distance_squared_to(p.get_global_position());
        if d < best_dist_sq {
            best_dist_sq = d;
            best = Some(p);
        }
    }

    if let Some(t) = &best {
        *target_path = t.get_path();
        *lock_time = 0.0;
    }
    best
}

fn resolve_target(tree: &Gd<SceneTree>, path: &NodePath) -> Option<Gd<Node3D>> {
    let root = tree.clone().get_root()?;
    let node = root.get_node_or_null(path)?;
    node.try_cast::<Node3D>().ok()
}

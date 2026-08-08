//! Sélection de la cible. Scan le group "players" et garde le plus proche
//! dans aggro_range. Notion de focus : on garde la même cible pendant
//! `focus_duration` avant de potentiellement switcher (évite le yo-yo).
//!
//! # Combat en cuvette
//!
//! L'arène du niveau 1 est un bol de 5 m de creux : les joueurs peuvent se
//! tenir sur la crête, bien au-dessus du Golem. Deux règles en découlent.
//!
//! **La portée est HORIZONTALE.** Le déplacement du boss l'est déjà
//! (`movement::steering_velocity` annule la composante verticale) : mesurer
//! l'aggro en 3D rendrait la sélection incohérente avec la poursuite, et un
//! joueur à 4 m au-dessus paraîtrait plus loin qu'un joueur à 12 m sur le
//! même plan.
//!
//! **Un joueur trop haut ou trop bas n'est pas une cible.** Le boss le
//! poursuivrait sans jamais l'atteindre, et resterait planté sous lui à
//! tourner en rond — ce qui se lit comme une IA cassée. Hors de la fenêtre
//! verticale, il choisit quelqu'un d'autre.

use godot::classes::SceneTree;
use godot::prelude::*;

/// Trouve / refresh la cible. Modifie `target_path` et `lock_time` en place.
/// Retourne la cible courante (Node3D) ou None si aucun joueur dans aggro.
pub fn pick_target(
    tree: Gd<SceneTree>,
    boss_pos: Vector3,
    aggro_range: f32,
    max_vertical_reach: f32,
    target_path: &mut NodePath,
    lock_time: &mut f32,
    focus_duration: f32,
) -> Option<Gd<Node3D>> {
    // Si on a déjà une cible verrouillée ET que le focus n'est pas écoulé,
    // on la garde tant qu'elle est encore vivante et à portée.
    if !target_path.is_empty() && *lock_time < focus_duration {
        if let Some(target) = resolve_target(&tree, target_path) {
            let pos = target.get_global_position();
            if is_engageable(boss_pos, pos, aggro_range, max_vertical_reach) {
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
        let pos = p.get_global_position();
        if !is_engageable(boss_pos, pos, aggro_range, max_vertical_reach) {
            continue;
        }
        let d = horizontal_distance_sq(boss_pos, pos);
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

/// Distance au carré dans le plan horizontal — la seule que le boss puisse
/// réellement parcourir.
pub fn horizontal_distance_sq(a: Vector3, b: Vector3) -> f32 {
    let dx = b.x - a.x;
    let dz = b.z - a.z;
    dx * dx + dz * dz
}

/// Une cible est engageable si elle est à portée horizontale ET dans la fenêtre
/// verticale du boss. Poursuivre quelqu'un de perché n'aboutit jamais.
pub fn is_engageable(
    boss_pos: Vector3,
    target_pos: Vector3,
    aggro_range: f32,
    max_vertical_reach: f32,
) -> bool {
    if (target_pos.y - boss_pos.y).abs() > max_vertical_reach {
        return false;
    }
    horizontal_distance_sq(boss_pos, target_pos) <= aggro_range * aggro_range
}

fn resolve_target(tree: &Gd<SceneTree>, path: &NodePath) -> Option<Gd<Node3D>> {
    let root = tree.clone().get_root()?;
    let node = root.get_node_or_null(path)?;
    node.try_cast::<Node3D>().ok()
}


#[cfg(test)]
mod tests {
    use super::*;

    const AGGRO: f32 = 40.0;
    const REACH: f32 = 8.0;

    #[test]
    fn horizontal_distance_ignores_height() {
        let a = Vector3::new(0.0, 0.0, 0.0);
        let b = Vector3::new(3.0, 100.0, 4.0);
        assert!((horizontal_distance_sq(a, b) - 25.0).abs() < 0.001);
    }

    #[test]
    fn engages_a_target_on_the_same_level() {
        let boss = Vector3::new(0.0, -3.0, 0.0);
        let player = Vector3::new(10.0, -3.0, 0.0);
        assert!(is_engageable(boss, player, AGGRO, REACH));
    }

    #[test]
    fn ignores_a_target_perched_on_the_crest() {
        // Le joueur est à 4 m horizontalement mais 12 m plus haut, sur la
        // crête du seuil : le boss ne l'atteindra jamais en marchant.
        let boss = Vector3::new(0.0, -3.0, 0.0);
        let perched = Vector3::new(4.0, 9.0, 0.0);
        assert!(!is_engageable(boss, perched, AGGRO, REACH));
    }

    #[test]
    fn a_small_height_difference_is_still_engageable() {
        // La paroi du bol : un joueur à mi-pente reste une cible valide,
        // sinon le boss lâcherait prise dès qu'on recule d'un pas.
        let boss = Vector3::new(0.0, -3.0, 0.0);
        let on_slope = Vector3::new(8.0, 0.0, 0.0);
        assert!(is_engageable(boss, on_slope, AGGRO, REACH));
    }

    #[test]
    fn respects_horizontal_aggro_range() {
        let boss = Vector3::ZERO;
        let far = Vector3::new(AGGRO + 1.0, 0.0, 0.0);
        assert!(!is_engageable(boss, far, AGGRO, REACH));
    }

    #[test]
    fn height_alone_never_puts_a_target_in_range() {
        // Un joueur pile au-dessus du boss n'est pas "à distance zéro" :
        // sans la fenêtre verticale, il serait la cible prioritaire.
        let boss = Vector3::ZERO;
        let above = Vector3::new(0.0, 30.0, 0.0);
        assert!(!is_engageable(boss, above, AGGRO, REACH));
    }
}

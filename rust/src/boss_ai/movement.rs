//! Steering simple : vélocité horizontale vers la cible, freine quand on
//! arrive à `stop_distance`. Pas de pathfinding pour le POC — l'arène
//! est suffisamment ouverte (35×35m). On gardera de la place pour ajouter
//! un NavigationAgent3D plus tard si nécessaire.
//!
//! # La laisse
//!
//! L'arène du niveau 1 est une cuvette dont les parois sont marchables
//! (37° max, sous le seuil de glissement). Rien n'empêche donc un joueur
//! d'attirer le Golem hors de son bol en remontant la pente — et un boss
//! qui suit dans la Grande Nef, c'est le lock d'arène qui ne veut plus rien
//! dire. `leash_to_arena` borde le déplacement : le boss circule librement
//! dans son rayon, et la composante qui l'en ferait sortir est annulée.

use godot::prelude::*;

/// Calcule la vélocité horizontale (XZ) à appliquer pour avancer vers
/// `target_pos` à `speed` m/s, en s'arrêtant à `stop_distance`.
pub fn steering_velocity(
    boss_pos: Vector3,
    target_pos: Vector3,
    speed: f32,
    stop_distance: f32,
) -> Vector3 {
    let mut delta = target_pos - boss_pos;
    delta.y = 0.0;
    let d = delta.length();
    if d <= stop_distance || d <= 0.0001 {
        return Vector3::ZERO;
    }
    delta * (speed / d)
}

/// Largeur de la bande d'arrêt au-delà du rayon. Sans elle, un boss qui
/// dépasse d'un pas serait renvoyé au centre à pleine vitesse et oscillerait
/// autour de sa limite.
const LEASH_SOFT_BAND: f32 = 2.0;

/// Contraint `velocity` pour que le boss ne quitte pas son arène.
///
/// - `arena_radius <= 0` désactive la laisse (boss sans arène assignée).
/// - **Dans le rayon** : rien n'est touché. Le boss manœuvre librement, y
///   compris vers l'extérieur — c'est ce qui lui permet d'acculer un joueur
///   contre la paroi.
/// - **Dans la bande d'arrêt** (jusqu'à 2 m au-delà) : seule la part
///   *radiale sortante* est retirée. Le boss longe le bord au lieu de se
///   figer contre une limite invisible, et peut toujours revenir.
/// - **Au-delà** : retour vers le centre, à la vitesse qu'il avait.
///
/// Les distances sont **horizontales** : la cuvette fait 5 m de creux, et
/// mesurer en 3D rétrécirait le rayon utile selon l'altitude du boss.
pub fn leash_to_arena(
    velocity: Vector3,
    boss_pos: Vector3,
    arena_center: Vector3,
    arena_radius: f32,
) -> Vector3 {
    if arena_radius <= 0.0 {
        return velocity;
    }

    let mut offset = boss_pos - arena_center;
    offset.y = 0.0;
    let dist = offset.length();
    if dist <= 0.0001 {
        return velocity;
    }
    let outward = offset / dist;

    if dist <= arena_radius {
        return velocity;
    }

    if dist > arena_radius + LEASH_SOFT_BAND {
        // Traîné hors du bol : demi-tour, à la vitesse qu'on avait.
        let speed = velocity.length();
        if speed <= 0.0001 {
            return Vector3::ZERO;
        }
        return -outward * speed;
    }

    // Bande d'arrêt : on retire ce qui pousse dehors, on garde le tangentiel.
    let radial = velocity.dot(outward);
    if radial <= 0.0 {
        return velocity;
    }
    velocity - outward * radial
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn stops_at_target() {
        let v = steering_velocity(Vector3::ZERO, Vector3::ZERO, 5.0, 1.0);
        assert!(v.length() < 0.001);
    }

    #[test]
    fn stops_when_within_stop_distance() {
        let v = steering_velocity(
            Vector3::ZERO,
            Vector3::new(0.5, 0.0, 0.0),
            5.0,
            1.0,
        );
        assert!(v.length() < 0.001);
    }

    #[test]
    fn moves_toward_target() {
        let v = steering_velocity(
            Vector3::ZERO,
            Vector3::new(10.0, 0.0, 0.0),
            5.0,
            1.0,
        );
        assert!((v.x - 5.0).abs() < 0.001);
        assert!(v.y.abs() < 0.001);
        assert!(v.z.abs() < 0.001);
    }

    #[test]
    fn ignores_vertical_distance() {
        // Différence verticale ne doit pas casser le calcul (target perché
        // ne nous fait pas voler).
        let v = steering_velocity(
            Vector3::ZERO,
            Vector3::new(10.0, 20.0, 0.0),
            5.0,
            1.0,
        );
        assert!(v.y.abs() < 0.001);
    }

    const CENTER: Vector3 = Vector3::new(0.0, -3.0, 0.0);
    const RADIUS: f32 = 20.0;

    #[test]
    fn leash_is_inert_at_the_middle_of_the_arena() {
        let v = Vector3::new(5.0, 0.0, 0.0);
        let out = leash_to_arena(v, Vector3::new(0.0, -3.0, 0.0), CENTER, RADIUS);
        assert!((out - v).length() < 0.001);
    }

    #[test]
    fn leash_leaves_the_boss_alone_inside_its_radius() {
        // Il doit pouvoir acculer un joueur contre la paroi : à l'intérieur,
        // aucune contrainte, même en poussant vers l'extérieur.
        let boss = Vector3::new(19.0, -3.0, 0.0);
        let v = Vector3::new(5.0, 0.0, 0.0);
        let out = leash_to_arena(v, boss, CENTER, RADIUS);
        assert!((out - v).length() < 0.001);
    }

    #[test]
    fn leash_cancels_the_outward_push_in_the_soft_band() {
        // Le boss vient de franchir le bord, la cible l'attire plus loin.
        let boss = Vector3::new(21.0, -3.0, 0.0);
        let v = Vector3::new(5.0, 0.0, 0.0);
        let out = leash_to_arena(v, boss, CENTER, RADIUS);
        assert!(out.length() < 0.001, "sortie non annulée : {out:?}");
    }

    #[test]
    fn leash_keeps_the_tangential_component() {
        // Poussée à 45° : la part qui longe le bord doit survivre, sinon le
        // boss se fige contre la limite.
        let boss = Vector3::new(21.0, -3.0, 0.0);
        let v = Vector3::new(5.0, 0.0, 5.0);
        let out = leash_to_arena(v, boss, CENTER, RADIUS);
        assert!(out.x.abs() < 0.001, "radial non retiré : {out:?}");
        assert!((out.z - 5.0).abs() < 0.001, "tangentiel perdu : {out:?}");
    }

    #[test]
    fn leash_never_blocks_the_way_back_in() {
        let boss = Vector3::new(21.0, -3.0, 0.0);
        let v = Vector3::new(-5.0, 0.0, 0.0);
        let out = leash_to_arena(v, boss, CENTER, RADIUS);
        assert!((out - v).length() < 0.001);
    }

    #[test]
    fn leash_brings_a_strayed_boss_home() {
        // Traîné hors du bol : il rentre, à la vitesse qu'il avait.
        let boss = Vector3::new(30.0, 4.0, 0.0);
        let v = Vector3::new(6.0, 0.0, 0.0);
        let out = leash_to_arena(v, boss, CENTER, RADIUS);
        assert!(out.x < 0.0, "ne rentre pas : {out:?}");
        assert!((out.length() - 6.0).abs() < 0.001);
    }

    #[test]
    fn leash_ignores_height_when_measuring_the_arena() {
        // 19 m du centre mais 13 m plus haut : en 3D ça ferait 23 m, donc
        // hors laisse. Horizontalement il est dedans, et libre.
        let on_the_slope = Vector3::new(19.0, 10.0, 0.0);
        let v = Vector3::new(5.0, 0.0, 0.0);
        let out = leash_to_arena(v, on_the_slope, CENTER, RADIUS);
        assert!((out - v).length() < 0.001, "laisse mesurée en 3D : {out:?}");
    }

    #[test]
    fn a_zero_radius_disables_the_leash() {
        let v = Vector3::new(5.0, 0.0, 0.0);
        let boss = Vector3::new(500.0, 0.0, 0.0);
        let out = leash_to_arena(v, boss, CENTER, 0.0);
        assert!((out - v).length() < 0.001);
    }
}

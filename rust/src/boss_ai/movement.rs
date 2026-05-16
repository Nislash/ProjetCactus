//! Steering simple : vélocité horizontale vers la cible, freine quand on
//! arrive à `stop_distance`. Pas de pathfinding pour le POC — l'arène
//! est suffisamment ouverte (35×35m). On gardera de la place pour ajouter
//! un NavigationAgent3D plus tard si nécessaire.

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
}

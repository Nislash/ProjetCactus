//! Catalogue des attaques du boss et logique de sélection.
//!
//! Pour le POC Phase 2 : seul `Slam` est implémenté côté GDScript (telegraph
//! AoE au sol + dégât). Les autres entrées de l'enum sont prêtes mais
//! n'ont pas encore d'exécution VFX/dégât côté scène — viendront en
//! Phase 3 (#62 follow-up).

use crate::boss_ai::state::BossPhase;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Attack {
    // Phase 1
    Slam,
    ThrowRocks,
    // Phase 2
    Charge,
    ShardRain,
    // Phase 3 enrage
    Shockwave,
    CrystalBeam,
}

/// Paramètres balistiques d'une attaque (durées, portée, dégâts).
pub struct AttackConfig {
    pub name: &'static str,
    /// Telegraph / anim d'amorce avant l'effet réel.
    pub windup: f32,
    /// Temps pendant lequel l'effet est actif (laser, charge, etc).
    pub execute: f32,
    /// Recovery post-attaque (le boss "récupère" avant de reprendre la MAJ
    /// de l'action).
    pub recovery: f32,
    /// Cooldown du type d'attaque (CaC ou distance) avant de pouvoir
    /// rejouer une attaque du même type.
    pub cooldown: f32,
    /// Rayon de l'AoE (pour les attaques zone) ou portée du tir.
    pub aoe_radius: f32,
    /// Dégâts infligés.
    pub damage: f32,
    /// True si l'attaque est mêlée (compte dans le cooldown CaC).
    pub is_melee: bool,
}

impl Attack {
    pub fn config(self) -> AttackConfig {
        match self {
            Attack::Slam => AttackConfig {
                name: "slam",
                windup: 0.8,
                execute: 0.15,
                recovery: 0.7,
                cooldown: 3.5,
                aoe_radius: 4.0,
                damage: 30.0,
                is_melee: true,
            },
            Attack::ThrowRocks => AttackConfig {
                name: "throw_rocks",
                windup: 1.2,
                execute: 0.2,
                recovery: 0.8,
                cooldown: 4.0,
                aoe_radius: 1.5, // rayon impact de chaque rocher
                damage: 20.0,
                is_melee: false,
            },
            Attack::Charge => AttackConfig {
                name: "charge",
                windup: 1.0,
                execute: 1.5,
                recovery: 1.0,
                cooldown: 6.0,
                aoe_radius: 2.0,
                damage: 50.0,
                is_melee: true,
            },
            Attack::ShardRain => AttackConfig {
                name: "shard_rain",
                windup: 1.5,
                execute: 0.3,
                recovery: 1.0,
                cooldown: 5.0,
                aoe_radius: 2.0,
                damage: 25.0,
                is_melee: false,
            },
            Attack::Shockwave => AttackConfig {
                name: "shockwave",
                windup: 1.0,
                execute: 2.0,
                recovery: 1.2,
                cooldown: 5.0,
                aoe_radius: 20.0, // toute l'arène
                damage: 40.0,
                is_melee: true,
            },
            Attack::CrystalBeam => AttackConfig {
                name: "crystal_beam",
                windup: 1.5,
                execute: 3.0,
                recovery: 1.5,
                cooldown: 6.0,
                aoe_radius: 1.5, // largeur du beam
                damage: 60.0,
                is_melee: false,
            },
        }
    }
}

/// Sélectionne l'attaque à exécuter selon la phase, la distance au target
/// et les cooldowns. Préfère CaC quand on est dans `melee_range`, sinon
/// distance. Retourne None si tout est en cooldown (le boss ira chase).
pub fn select(
    phase: BossPhase,
    dist: f32,
    melee_range: f32,
    melee_cd_left: f32,
    ranged_cd_left: f32,
) -> Option<Attack> {
    let in_melee = dist <= melee_range;
    let (melee, ranged) = match phase {
        BossPhase::Phase1 => (Attack::Slam, Attack::ThrowRocks),
        BossPhase::Phase2 => (Attack::Charge, Attack::ShardRain),
        BossPhase::Phase3Enrage => (Attack::Shockwave, Attack::CrystalBeam),
        // Pas d'attaque hors combat actif.
        _ => return None,
    };
    if in_melee && melee_cd_left <= 0.0 {
        return Some(melee);
    }
    if !in_melee && ranged_cd_left <= 0.0 {
        return Some(ranged);
    }
    // Fallback : si CaC pas disponible mais on est à portée, essaie le
    // distance (et inversement). Évite que le boss reste figé.
    if melee_cd_left <= 0.0 {
        return Some(melee);
    }
    if ranged_cd_left <= 0.0 {
        return Some(ranged);
    }
    None
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn phase1_picks_slam_in_melee() {
        let a = select(BossPhase::Phase1, 3.0, 5.0, 0.0, 0.0).unwrap();
        assert_eq!(a, Attack::Slam);
    }

    #[test]
    fn phase1_picks_throw_at_range() {
        let a = select(BossPhase::Phase1, 15.0, 5.0, 0.0, 0.0).unwrap();
        assert_eq!(a, Attack::ThrowRocks);
    }

    #[test]
    fn phase2_picks_charge_in_melee() {
        let a = select(BossPhase::Phase2, 3.0, 5.0, 0.0, 0.0).unwrap();
        assert_eq!(a, Attack::Charge);
    }

    #[test]
    fn phase3_picks_beam_at_range() {
        let a = select(BossPhase::Phase3Enrage, 15.0, 5.0, 0.0, 0.0).unwrap();
        assert_eq!(a, Attack::CrystalBeam);
    }

    #[test]
    fn fallbacks_when_preferred_on_cooldown() {
        // En mêlée mais slam en cd : fallback sur throw_rocks.
        let a = select(BossPhase::Phase1, 3.0, 5.0, 2.0, 0.0).unwrap();
        assert_eq!(a, Attack::ThrowRocks);
    }

    #[test]
    fn returns_none_when_all_on_cooldown() {
        let a = select(BossPhase::Phase1, 3.0, 5.0, 2.0, 2.0);
        assert!(a.is_none());
    }

    #[test]
    fn idle_phase_returns_none() {
        let a = select(BossPhase::Idle, 3.0, 5.0, 0.0, 0.0);
        assert!(a.is_none());
    }
}

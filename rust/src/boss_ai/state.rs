//! Types d'état du boss en Rust. La machine à phases (HP %) est gérée
//! côté GDScript (BossBase) — l'IA Rust se contente de lire la phase
//! courante. Ici on définit la phase Rust + l'état d'action runtime.

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BossPhase {
    Idle,
    Phase1,
    Transition1to2,
    Phase2,
    Transition2to3,
    Phase3Enrage,
    Stunned,
    Dead,
}

/// Sous-état d'action de l'IA pendant le combat (orthogonal à la phase
/// principale). Une attaque suit le cycle Windup → Execute → Recovery,
/// après quoi on retombe en Chase.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum ActState {
    Idle,
    Chase,
    AttackWindup,
    AttackExecute,
    AttackRecovery,
}

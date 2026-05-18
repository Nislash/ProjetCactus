//! IA boss en Rust. Attachée comme enfant Node3D du `BossGolem` (issue #62).
//!
//! Lit l'état du boss parent (phase, HP, position) via les méthodes de
//! `BossBase` GDScript. Pousse les actions (déplacement, attaques) en
//! appelant des méthodes sur le boss parent.
//!
//! Architecture :
//! - `mod.rs` : classe `BossAI` exposée à Godot, tick principal
//! - `state.rs` : types d'état (phase, état d'action courant)
//! - `targeting.rs` : sélection du joueur ciblé + focus tracking
//! - `movement.rs` : steering / approche du target
//! - `attacks.rs` : enum `Attack` + table de config + helpers de sélection

use godot::classes::node::ProcessMode;
use godot::classes::{CharacterBody3D, Node3D};
use godot::prelude::*;

mod attacks;
mod movement;
mod state;
mod targeting;

use attacks::Attack;
use state::{ActState, BossPhase};

/// Normalise un angle dans [-PI, PI] pour éviter des rotations de plus
/// d'un demi-tour quand on calcule la différence cible - courant.
fn wrap_angle(a: f32) -> f32 {
    let two_pi = std::f32::consts::TAU;
    let mut x = a % two_pi;
    if x > std::f32::consts::PI {
        x -= two_pi;
    } else if x < -std::f32::consts::PI {
        x += two_pi;
    }
    x
}

#[cfg(test)]
mod tests {
    use super::wrap_angle;

    #[test]
    fn wrap_keeps_in_range() {
        let pi = std::f32::consts::PI;
        assert!((wrap_angle(0.5) - 0.5).abs() < 1e-5);
        assert!((wrap_angle(-0.5) + 0.5).abs() < 1e-5);
        // Plus d'un tour : ramène dans [-PI, PI].
        let w = wrap_angle(3.0 * pi);
        assert!(w.abs() <= pi + 1e-5);
    }
}

/// Conversion Phase int (côté BossBase GDScript) vers `BossPhase` Rust.
/// Doit rester aligné avec l'enum `BossBase.Phase` (boss_base.gd).
const PHASE_GD_IDLE: i32 = 0;
const PHASE_GD_PHASE_1: i32 = 1;
const PHASE_GD_TRANSITION_1_TO_2: i32 = 2;
const PHASE_GD_PHASE_2: i32 = 3;
const PHASE_GD_TRANSITION_2_TO_3: i32 = 4;
const PHASE_GD_PHASE_3_ENRAGE: i32 = 5;
const PHASE_GD_STUNNED_COMBO: i32 = 6;
const PHASE_GD_DEAD: i32 = 7;

#[derive(GodotClass)]
#[class(base=Node3D)]
pub struct BossAI {
    base: Base<Node3D>,

    // === Config exposée à l'inspector ===
    /// Distance d'agro : au-delà, le boss reste idle (ne devrait pas
    /// arriver en arène lockée mais garde la sécurité).
    #[export]
    aggro_range: f32,

    /// Distance pour préférer une attaque CaC (sinon distance).
    #[export]
    melee_range: f32,

    /// Distance minimale avant d'arrêter de poursuivre (évite de se coller).
    #[export]
    stop_chase_distance: f32,

    /// Cooldown entre 2 *décisions* d'attaque (limite la fréquence).
    #[export]
    attack_decision_cooldown: f32,

    /// Temps de focus avant de potentiellement switcher de target (s).
    #[export]
    target_focus_duration: f32,

    // === État runtime (pas exposé) ===
    act_state: ActState,
    state_time: f32,

    /// NodePath du joueur actuellement ciblé (vide = pas de cible).
    target_path: NodePath,
    target_lock_time: f32,

    /// Cooldowns indépendants CaC / distance (un boss peut alterner sans
    /// que le CaC bloque le distance).
    melee_cooldown_left: f32,
    ranged_cooldown_left: f32,

    /// Référence cachée vers le boss parent (BossBase GDScript). Set au
    /// `ready` puis utilisé pour appeler des méthodes (engage, attaque,
    /// etc).
    boss_parent: Option<Gd<Node3D>>,

    /// L'attaque actuellement en cours (ou None si chase/idle).
    current_attack: Option<Attack>,

    /// Vitesse de rotation Y du boss vers sa cible (rad/s).
    #[export]
    turn_speed: f32,

    /// Direction figée au début d'une charge (la charge ne peut pas être
    /// re-aimed pendant son exécution).
    charge_direction: Vector3,
    /// Vitesse de la charge (m/s) pendant l'execute.
    #[export]
    charge_speed: f32,
}

#[godot_api]
impl INode3D for BossAI {
    fn init(base: Base<Node3D>) -> Self {
        Self {
            base,
            aggro_range: 40.0,
            melee_range: 5.0,
            stop_chase_distance: 4.0,
            attack_decision_cooldown: 1.5,
            target_focus_duration: 8.0,
            act_state: ActState::Idle,
            state_time: 0.0,
            target_path: NodePath::default(),
            target_lock_time: 0.0,
            melee_cooldown_left: 0.0,
            ranged_cooldown_left: 0.0,
            boss_parent: None,
            current_attack: None,
            turn_speed: 3.0,
            charge_direction: Vector3::ZERO,
            charge_speed: 14.0,
        }
    }

    fn ready(&mut self) {
        // Tick à la physics frame pour cohérence avec move_and_slide() du
        // CharacterBody3D parent.
        self.base_mut()
            .set_process_mode(ProcessMode::INHERIT);

        // Le parent direct est BossBase (CharacterBody3D + script boss_base.gd).
        let parent = self.base().get_parent().and_then(|p| p.try_cast::<Node3D>().ok());
        if parent.is_none() {
            godot_warn!("[BossAI] Parent introuvable ou non-Node3D");
        }
        self.boss_parent = parent;
    }

    fn physics_process(&mut self, delta: f64) {
        let delta = delta as f32;
        self.state_time += delta;
        self.target_lock_time += delta;
        self.melee_cooldown_left = (self.melee_cooldown_left - delta).max(0.0);
        self.ranged_cooldown_left = (self.ranged_cooldown_left - delta).max(0.0);

        // Lit l'état du boss parent (avant les autres emprunts).
        let phase_opt = self.read_boss_phase();
        let Some(phase) = phase_opt else {
            return;
        };

        // Idle / dead / stunned : l'IA ne fait rien (BossBase gère les
        // transitions de phase et les stuns via timer côté GDScript).
        match phase {
            BossPhase::Idle | BossPhase::Dead | BossPhase::Stunned => {
                self.act_state = ActState::Idle;
                self.stop_movement();
            }
            BossPhase::Transition1to2 | BossPhase::Transition2to3 => {
                // Pendant la transition : le boss est invulnérable et ne
                // fait rien. À implémenter avec un timer plus tard.
                self.stop_movement();
            }
            BossPhase::Phase1 | BossPhase::Phase2 | BossPhase::Phase3Enrage => {
                // Combat actif.
                self.combat_tick(delta, phase);
            }
        }
    }
}

#[godot_api]
impl BossAI {
    /// Méthode exposable à GDScript : reset des cooldowns (utile après
    /// transition de phase pour ré-amorcer l'IA proprement).
    #[func]
    fn reset_cooldowns(&mut self) {
        self.melee_cooldown_left = 0.0;
        self.ranged_cooldown_left = 0.0;
        self.act_state = ActState::Idle;
        self.state_time = 0.0;
        self.current_attack = None;
    }

    fn read_boss_phase(&mut self) -> Option<BossPhase> {
        let boss = self.boss_parent.as_mut()?;
        // Boss.get_current_phase() → int (cf boss_base.gd Phase enum).
        let v = boss.call("get_current_phase", &[]);
        let i = v.try_to::<i32>().ok()?;
        Some(match i {
            PHASE_GD_IDLE => BossPhase::Idle,
            PHASE_GD_PHASE_1 => BossPhase::Phase1,
            PHASE_GD_TRANSITION_1_TO_2 => BossPhase::Transition1to2,
            PHASE_GD_PHASE_2 => BossPhase::Phase2,
            PHASE_GD_TRANSITION_2_TO_3 => BossPhase::Transition2to3,
            PHASE_GD_PHASE_3_ENRAGE => BossPhase::Phase3Enrage,
            PHASE_GD_STUNNED_COMBO => BossPhase::Stunned,
            PHASE_GD_DEAD => BossPhase::Dead,
            _ => return None,
        })
    }

    /// Cœur de l'IA pendant le combat : choisit une cible, se déplace,
    /// décide d'attaquer.
    fn combat_tick(&mut self, delta: f32, phase: BossPhase) {
        let Some(boss) = self.boss_parent.as_ref() else {
            return;
        };
        let boss_pos = boss.get_global_position();

        // 1) Sélection / refresh du target.
        let target = targeting::pick_target(
            self.base().get_tree(),
            boss_pos,
            self.aggro_range,
            &mut self.target_path,
            &mut self.target_lock_time,
            self.target_focus_duration,
        );
        let Some(target) = target else {
            self.stop_movement();
            return;
        };
        let target_pos = target.get_global_position();
        let dist = boss_pos.distance_to(target_pos);

        // Tourne progressivement le boss vers sa cible (sauf pendant charge
        // execute : la direction est figée au moment du windup).
        if !(self.act_state == ActState::AttackExecute
            && self.current_attack == Some(Attack::Charge))
        {
            self.face_target(delta, boss_pos, target_pos);
        }

        // 2) Si déjà en train d'attaquer, on laisse l'attaque dérouler.
        if self.act_state != ActState::Chase && self.act_state != ActState::Idle {
            self.tick_attack(delta, boss_pos, target_pos);
            return;
        }

        // 3) Décide d'attaquer si dans portée + cooldown OK.
        if let Some(att) = attacks::select(
            phase,
            dist,
            self.melee_range,
            self.melee_cooldown_left,
            self.ranged_cooldown_left,
        ) {
            self.start_attack(att, boss_pos, target_pos);
            return;
        }

        // 4) Sinon, chase le target.
        self.act_state = ActState::Chase;
        let want_dist = self.stop_chase_distance.max(self.melee_range * 0.9);
        let velocity = movement::steering_velocity(
            boss_pos,
            target_pos,
            self.get_move_speed(phase),
            want_dist,
        );
        self.apply_velocity(velocity);
    }

    fn start_attack(&mut self, att: Attack, boss_pos: Vector3, target_pos: Vector3) {
        let cfg = att.config();
        self.current_attack = Some(att);
        self.act_state = ActState::AttackWindup;
        self.state_time = 0.0;
        self.stop_movement();

        // Charge : on fige la direction au moment du windup. Pendant
        // l'execute, le boss avancera tout droit dans cette direction.
        if att == Attack::Charge {
            let mut dir = target_pos - boss_pos;
            dir.y = 0.0;
            let l = dir.length();
            self.charge_direction = if l > 0.001 { dir / l } else { Vector3::ZERO };
        }

        // Notifie le boss GDScript que le windup démarre : déclenche le
        // telegraph (decal au sol, anim d'amorce) côté scène.
        if let Some(boss) = self.boss_parent.as_mut() {
            boss.call(
                "ai_on_attack_windup",
                &[
                    cfg.name.to_variant(),
                    target_pos.to_variant(),
                    cfg.windup.to_variant(),
                    cfg.aoe_radius.to_variant(),
                ],
            );
        }
    }

    /// Fait pivoter le boss autour de l'axe Y pour faire face à la cible.
    /// move_toward angulaire — borné par `turn_speed * delta` par tick.
    fn face_target(&mut self, delta: f32, boss_pos: Vector3, target_pos: Vector3) {
        let Some(boss) = self.boss_parent.as_mut() else {
            return;
        };
        let mut dir = target_pos - boss_pos;
        dir.y = 0.0;
        if dir.length() < 0.001 {
            return;
        }
        let target_yaw = (-dir.x).atan2(-dir.z);
        let mut rotation = boss.get_rotation();
        let max_step = self.turn_speed * delta;
        let diff = wrap_angle(target_yaw - rotation.y);
        let step = diff.clamp(-max_step, max_step);
        rotation.y += step;
        boss.set_rotation(rotation);
    }

    fn tick_attack(&mut self, _delta: f32, boss_pos: Vector3, target_pos: Vector3) {
        let Some(att) = self.current_attack else {
            self.act_state = ActState::Chase;
            return;
        };
        let cfg = att.config();
        match self.act_state {
            ActState::AttackWindup if self.state_time >= cfg.windup => {
                self.act_state = ActState::AttackExecute;
                self.state_time = 0.0;
                // L'exécution : on demande au boss GDScript d'appliquer
                // l'effet (AoE damage, projectile spawn, etc.).
                if let Some(boss) = self.boss_parent.as_mut() {
                    boss.call(
                        "ai_on_attack_execute",
                        &[
                            cfg.name.to_variant(),
                            boss_pos.to_variant(),
                            target_pos.to_variant(),
                            cfg.aoe_radius.to_variant(),
                            cfg.damage.to_variant(),
                        ],
                    );
                }
            }
            ActState::AttackExecute => {
                // Pendant l'execute d'une Charge : déplacement linéaire
                // forcé selon la direction figée au windup. Les autres
                // attaques ne bougent pas pendant l'execute.
                if att == Attack::Charge {
                    let velocity = self.charge_direction * self.charge_speed;
                    self.apply_velocity(velocity);
                }
                if self.state_time >= cfg.execute {
                    self.act_state = ActState::AttackRecovery;
                    self.state_time = 0.0;
                    if att == Attack::Charge {
                        self.stop_movement();
                    }
                }
            }
            ActState::AttackRecovery if self.state_time >= cfg.recovery => {
                // Cooldown du type d'attaque concerné.
                if cfg.is_melee {
                    self.melee_cooldown_left = cfg.cooldown;
                } else {
                    self.ranged_cooldown_left = cfg.cooldown;
                }
                self.current_attack = None;
                self.act_state = ActState::Chase;
                self.state_time = 0.0;
            }
            _ => {}
        }
    }

    fn get_move_speed(&mut self, phase: BossPhase) -> f32 {
        // Demande la vitesse au boss GDScript (BossData.move_speed_*).
        let Some(boss) = self.boss_parent.as_mut() else {
            return 2.0;
        };
        let v = boss.call("get_ai_move_speed", &[(phase == BossPhase::Phase3Enrage).to_variant()]);
        v.try_to::<f32>().unwrap_or(2.0)
    }

    fn apply_velocity(&mut self, velocity: Vector3) {
        let Some(boss) = self.boss_parent.as_mut() else {
            return;
        };
        let Ok(mut body) = boss.clone().try_cast::<CharacterBody3D>() else {
            return;
        };
        // Conserve la composante verticale (gravité gérée par EnemyBase).
        let mut current = body.get_velocity();
        current.x = velocity.x;
        current.z = velocity.z;
        body.set_velocity(current);
    }

    fn stop_movement(&mut self) {
        self.apply_velocity(Vector3::ZERO);
    }
}

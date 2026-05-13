# Matrice des combos arme×parchemin (signature du jeu)

**Statut : STUB — POC matrix à figer en M1.** Owner partagé : design Machine B, implémentation moteur Machine A (`rust/src/combo_engine.rs`).

## Règle d'or

Le **gameplay et l'animation doivent se ressentir**. Un pistolet × parchemin de feu n'est **pas** un pistolet qui applique brûlure — c'est un *Pistolet Boule de Feu* qui :
- A une animation de tir différente (recoil plus lourd, lueur orange au canon)
- Tire un projectile boule de feu (sprite/mesh différent)
- Inflige brûlure DoT
- A un SFX différent
- Laisse une traînée de particules

Sinon ce n'est qu'un debuff visuel cheap.

## Matrice complète (4 armes × 5 écoles = 20 combos)

| | Feu | Glace | Foudre | Poison | Terre |
|---|---|---|---|---|---|
| **Pistolet** | Pistolet boule de feu (DoT) | Pistolet givre (slow+frozen) | Pistolet électrique (chain) | Pistolet toxique (DoT empilable) | Pistolet pierre (knockback) |
| **Shotgun** | Shotgun lance-flammes (cône brûlure) | Shotgun cryo (gel zone) | Shotgun foudre (chain 3) | Shotgun gaz (nuage toxique) | Shotgun mitraille (perforant) |
| **Fusil** (sniper) | Tir incendiaire (DoT 5s) | Tir glaçant (freeze 2s) | Tir laser (perçant) | Tir empoisonné (DoT cumul) | Tir explosif (AoE) |
| **Arme mêlée** | Lame enflammée (DoT au touché) | Lame glaciale (gel) | Lame foudroyante (chain) | Lame empoisonnée (DoT) | Lame de pierre (stun) |

## POC — 4 combos prioritaires (M1-M2)

Sélectionner 4 combos vraiment différents pour démontrer la mécanique :

1. **Pistolet × Feu** = Pistolet boule de feu (DoT)
2. **Pistolet × Glace** = Pistolet givre (slow + frozen)
3. **Shotgun × Foudre** = Shotgun chain lightning (3 cibles)
4. **Shotgun × Poison** = Shotgun nuage toxique AoE

## Format technique (Rust)

```rust
struct ComboInstance {
    projectile_scene: GString,        // override de WeaponData
    animation_override: Option<GString>,
    sfx_override: Option<GString>,
    status_effects: Vec<StatusEffect>,
    damage_multiplier: f32,
    aoe_radius: Option<f32>,
    chain_targets: Option<u8>,
    knockback: f32,
}
```

Voir `rust/src/combo_engine.rs`.

# Écoles de magie (5)

**Statut : STUB — à remplir lors de M1.** Owner : Machine B.

5 écoles élémentaires. Chaque école produit un parchemin (SpellData.tres) qui peut se combiner avec une arme (cf `combos_matrix.md`).

## Pistes

| # | École | Élément | Status effect signature | VFX dominant | Counter |
|---|---|---|---|---|---|
| 1 | Pyromancie | Feu | Brûlure (DoT 3s) | Particules orange/rouge | Glace |
| 2 | Cryomancie | Glace | Slow + Frozen (1.5s à seuil) | Particules cyan, traces de gel | Feu |
| 3 | Électromancie | Foudre | Stun (0.3s) + Chain (3 cibles) | Arcs bleus | Poison |
| 4 | Toxicologie | Poison | DoT 5s, empile 3 fois | Vapeur verte | Foudre |
| 5 | Géomancie | Terre/Physique | Knockback + slow | Pierres, poussière | Aucun |

## À définir

- Damage modifiers contre chaque type d'ennemi (résistances)
- Détails status effects (formule DoT, durée, cap)
- Animation override (un projectile glace **doit visuellement geler la cible**, pas juste appliquer un slow)
- Compatibilité par classe (Tank n'a peut-être pas Foudre, etc.)

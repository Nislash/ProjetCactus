# Puzzle méta cross-8-niveaux

**Statut : STUB — à designer après POC, mais le concept doit être posé dès M0.** Owner : Machine B.

## Concept

Chacun des 8 niveaux contient un **fragment** du puzzle global. Un joueur qui résout les 8 fragments dans un même run (ou cumulés sur plusieurs runs ?) débloque la **fin spéciale**.

## Questions ouvertes à trancher

1. **Persistance** : décisions actuelle = pure roguelike, rien ne persiste. Mais le puzzle méta a besoin de tracker la résolution sur 8 niveaux qui sortent rarement dans un seul run.
   - Option A : il faut résoudre les 8 fragments **dans un même run** (très hardcore, faisable seulement après mastery)
   - Option B : la résolution des fragments persiste (légère entorse à la règle "pure roguelike"), seul un compteur "fragment résolus" est sauvé
   - Option C : les fragments sont des indices sur une énigme finale unique, qu'on peut résoudre à n'importe quel moment du run final si on a vu les 8 indices auparavant
2. **Forme des fragments** : indice visuel caché, mini-énigme dans une salle secrète, interaction avec une statue, etc.
3. **Fin spéciale** : cinématique, salle bonus, boss caché, choix moral ?

## À définir lors du design pré-phase-2

- Décision sur la persistance (A/B/C ci-dessus)
- Forme exacte des 8 fragments
- Mécanisme de récompense / fin spéciale
- Indices visuels disséminés dans le jeu pour évoquer le puzzle sans le spoiler

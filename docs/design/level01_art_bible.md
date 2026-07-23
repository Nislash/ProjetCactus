# Niveau 1 « Caverne Cristalline » — Art Bible

> **Statut : E0 en cours (#94).** Ce document est rempli par **● Opus** (palette, matériaux, budget, liste d'assets, contraintes) ; la **conception géographique/topographique** (silhouette, relief, sightlines, puits de ciel) est produite par **◆ Fable** en Session 1 à partir du *brief créatif* en §6.
>
> Réf. plan : `docs/design/level01_openworld_plan.md`. Décision actée : **option A** (grande caverne continue faite main).

---

## 1. Pitch visuel en une ligne

Une **grande caverne cristalline fermée et vallonée**, plongée dans la pénombre, éclairée par des **cristaux qui glow sur les parois** et des **puits de jour** perçant la voûte — le contraste entre les zones sombres (où les cristaux sont la boussole) et les flaques de lumière naturelle porte toute l'ambiance.

## 2. Contraintes spatiales (dures — cf plan §2)

| Contrainte | Spec |
|---|---|
| Hauteur de voûte | **10–15 m** au-dessus du sol praticable |
| Sol | **vallonné** (pentes douces, bosses, creux), praticable **partout** |
| Bornes | volume **fermé** : impossible de sortir |
| Anti-chute | **aucune chute possible** — creux = cuvettes bordées, zéro vide, pas de kill-floor |
| Zones ouvertes | **trous dans la voûte/parois** → on voit le ciel, ≥ 1 landmark visible de loin |
| POI | 4–6 points d'intérêt (loot, combat, puzzle, respiration) |

## 3. Palette (source de vérité — reprise de l'artifact du plan)

Neutres à **biais bleu** (jamais un gris pur), accent cristal cyan émissif, contre-accent chaud réservé au danger/boss.

| Rôle | Hex | Usage |
|---|---|---|
| Roche profonde | `#0a0e15` | ombres de caverne, fond |
| Roche | `#1e2b3e` → `#3a4a60` | parois, sol (variations) |
| Cristal cyan (émissif) | `#66d9ff` | **source lumineuse** murale, veines — couleur signature |
| Cristal profond | `#2f7fd4` | facettes, dégradés de cristaux |
| Facette violette | `#a98bff` | variété de cristaux (rare) |
| Jour (puits de ciel) | `#cfe4f2` chaud légèrement | shafts volumétriques, flaques au sol |
| Danger / boss / lave | `#f2b45c` | **réservé** aux telegraphs boss et hazards |

> Cohérence avec l'existant : les colonnes de cristal du blockout actuel utilisent déjà `albedo Color(0.45,0.85,1)` + `emission Color(0.2,0.6,0.9)` — on s'aligne dessus.

## 4. Matériaux (PBR, cibles pour Meshy retexture — E3)

| Matériau | Notes |
|---|---|
| **Roche de caverne** | PBR mate, roughness haute, micro-relief ; trim sheet + tri-planar pour le vallonné |
| **Cristal émissif** | translucide/metallic léger, `emission` ON, sert de **vraie source** (OmniLight au cœur) |
| **Veines / lichen luminescent** | glow diffus secondaire sur la roche, guide discret dans le noir |
| **Sol détaillé** | éboulis, poussière cristalline, flaques sous les puits de jour |
| **Puits de jour** | pas un matériau : `FogVolume` + `DirectionalLight`/`SpotLight` shafts par trou de voûte |

## 5. Budget technique (cible 4-split 60 fps — **à confirmer sur la machine cible**)

Valeurs de départ à valider en E2/E3 (mesures avant/après) :

| Métrique | Cible de départ | Note |
|---|---|---|
| Draw calls / viewport | ≤ ~1200 | ×4 viewports simultanés |
| Triangles visibles / viewport | ≤ ~1,5 M | MultiMesh pour les cristaux répétés |
| Sources de lumière temps réel | ombres portées sur ~2-3 majeures (puits de jour) ; le reste en émissif/baked | perf-critique |
| Textures | atlas / trim sheets, 2K max par matériau | `.glb` embed (LFS) |
| Fallback | **renderer Mobile** prévu si le Forward+ 4-split ne tient pas | cf CLAUDE.md |

> ⚠️ Ces chiffres sont des points de départ raisonnables, pas des mesures. À caler dès qu'on a la machine de test (E0 final).

## 6. Liste d'assets à produire (priorisée)

1. **Terrain caverne** (roche sol + parois + voûte) — texturé E3
2. **Cristaux muraux émissifs** — ≥ 3 variantes de silhouette (E4), instanciés MultiMesh
3. **Formations/piliers de cristal** landmarks — 2-3 grosses pièces héro (E4)
4. **Props caverne** : stalactites/stalagmites, éboulis (E4)
5. **Coffres** : départ + reliques, retexturés (E4)
6. **Boss Golem de cristal** retexturé (E4, sans casser IA/hitbox — cf #62 fait, #63/#64 en cours)

---

## 6bis. Brief créatif pour la Session 1 (◆ Fable) — conception géo/topographique

> À donner tel quel en entrée de la session Fable. Fable **conçoit**, ne code pas ici ; sa sortie alimente l'exécution Opus en Session 2 (#96).

**Rôle** : tu es level designer/directeur artistique. Conçois la **structure géographique et topographique** d'une grande caverne cristalline jouable en FPS coop split-screen 1-4 joueurs.

**Livrable attendu** (un document + un schéma topographique) :
1. **Silhouette & parti-pris** : la forme d'ensemble du volume, son « geste » (ex. un grand bol descendant vers l'arène boss ? une faille traversante ? un dôme central ?).
2. **Carte topographique** : le sol vallonné décrit par zones (altitudes relatives, pentes, bosses, cuvettes), sur une emprise cohérente pour 1-4 joueurs (ordre de grandeur à proposer, ~60-90 m de large).
3. **Sightlines & landmarks** : 2-3 repères visibles de loin (grosse formation de cristal, puits de lumière géant, pic rocheux), et ce qu'on voit d'où — comment la caverne « se lit » à l'œil.
4. **Puits de ciel** : où percer la voûte/les parois (nombre, taille, ce qu'ils éclairent au sol), pour créer le contraste jour/profondeur.
5. **Placement des 4-6 POI** dans le relief : spawn, zones de combat, nid de puzzle (3 cristaux), respiration/loot, antichambre + arène boss — avec la logique « où va le joueur et pourquoi ».
6. **Circulation** : comment on traverse le vallonné sans se coincer, où sont les montées/descentes, où l'arène boss se révèle.

**Contraintes dures** (non négociables) : voûte **10–15 m** ; **fermé** (aucune sortie) ; **aucune chute possible** (creux = cuvettes bordées, zéro vide) ; sol **praticable partout** ; ≥ 1 zone ouverte à ciel ouvert servant de landmark.

**Hors périmètre** : pas de texturing (E3), pas de placement moteur (Opus/Session 2), pas de code. Uniquement la **conception spatiale** + justification.

**Format de sortie** : Markdown structuré + un schéma (ASCII/coordonnées ou description assez précise pour qu'Opus le rebuild au MCP Godot en E2).

---

## 7. Definition of Done (E0 — #94)

- [ ] Décision A notée dans `docs/design/levels.md`
- [x] Palette, matériaux, contraintes, budget de départ, liste d'assets (ce document)
- [ ] Budget technique **confirmé** sur la machine cible (remplacer les valeurs de départ)
- [ ] Brief créatif §6bis exécuté par Fable → carte topographique validée (alimente #96 E2)

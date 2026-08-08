# Niveau 1 — Onboarding diégétique : « L'Antichambre de Givre »

> **Produit par ◆ Fable (session créative, 2026-08-08).** Script de mise en scène des 8 beats du plan
> (§4), exécutable par Opus en E5 (tâche « antichambre + scripting »). Règles absolues : **zéro mur de
> texte** (glyphes manette et réactions du monde uniquement), progression validée **par l'action**
> (jamais par un timer), jouable **seul comme à quatre**, skippable en marchant.

## 0. Le lieu et la courbe

Une petite chambre de glace (~25 × 15 m, voûte 8 m — volontairement *sous* l'échelle de la caverne :
l'antichambre est un étui, la caverne sera la révélation d'échelle), scène séparée qui débouche par une
porte de glace sur la corniche Z1 (`level01_topography.md`). Un couloir en deux coudes : chaque beat
possède son alcôve, on ne voit jamais le beat suivant avant d'avoir joué le sien.

**Courbe d'intensité visée** : mystère (1–2) → agentivité (3) → **pic de plaisir** (4, le combo) →
lien (5) → tension (6) → récompense/ouverture (7). Le pic émotionnel est à la minute 1 et c'est le
combo — la signature du jeu offerte d'entrée, comme l'exige le plan.

**Grammaire transversale** (posée ici, valable tout le jeu) :
- **Froid cyan émissif** = chemin, objectif, interactif.
- **Chaud** = spécial/danger — utilisé UNE fois ici (le parchemin de feu), une fois dans la caverne
  (la lanterne), puis réservé aux telegraphs du boss.
- **Glyphe manette** = gravure de givre qui s'illumine au sol/mur près de l'objet concerné, dans le
  style du device détecté (Xbox/PS/générique via `InputRouter`). Jamais de HUD popup.

## Les 8 beats

### B1 — Le réveil *(0:00 → ~0:20 · mystère)*

Noir presque total ; quatre cristaux muraux éteints, en arc de cercle. Chaque manette qui fait `Start`
**allume son cristal** : montée de lumière 1,5 s, note tenue (une note différente par slot — à quatre,
le join compose un accord), la couleur du joueur s'installe dans les facettes. Le cristal EST le slot
de lobby : allumé = inscrit. Pas d'écran, pas de liste — on voit qui est là en regardant le mur.
*Validation : ≥ 1 cristal allumé + 3 s sans nouveau join, ou les 4 allumés.*

### B2 — Bouger & regarder *(~0:20 → 0:50 · première agentivité)*

Les cristaux de join s'éteignent doucement ; une **veine de givre lumineuse** s'allume dans le sol et
file vers le premier coude, en pulsant *dans le sens du chemin* (le pouls indique la direction — pas de
flèche). Glyphe stick gauche gravé au sol au point de départ, glyphe stick droit 3 m plus loin dans un
virage (le coude force à tourner la caméra : le level design enseigne le stick droit, le glyphe ne fait
que confirmer). *Validation : chaque joueur actif a parcouru 10 m et tourné la caméra de 90° cumulés.*

### B3 — Le premier tir *(0:50 → 1:10 · agentivité armée)*

Le passage est barré par un **cristal laiteux fragile** — visiblement différent (opale, veiné de
fissures) : la grammaire « fragile = cassable » naît ici. Glyphe gâchette sur la paroi à côté. Le viser
fait scintiller ses fissures (feedback de visée sans tutoriel) ; le tir le fait **voler en éclats**
avec un son sur-satisfaisant et une pluie de particules. Derrière lui, une alcôve.
*Validation : le cristal est brisé (n'importe quel joueur).*

### B4 — Le combo qui se ressent *(1:10 → 1:40 · LE PIC)*

Dans l'alcôve, sur un piédestal : **le parchemin de feu** — première et unique lumière chaude de
l'antichambre, halo orange dans un monde bleu. Impossible de ne pas le voir. Le ramasser déclenche la
transformation **sous les yeux du joueur, à la première personne** : l'arme s'embrase élément par
élément (canon, glyphes gravés, muzzle VFX), 2 s de métamorphose non-interactive puis rendu de la main.
Face à l'alcôve, **deux** nouveaux cristaux fragiles : le premier tir enflammé les brise ET les fait
**brûler** (DoT visible sur les débris incandescents). On ne dit pas « +brûlure » — on la voit.
En multi : un parchemin par joueur présent (le piédestal en distribue tant qu'il reste un joueur à main
nue ; personne ne repart sans son moment).
*Validation : chaque joueur actif a tiré ≥ 1 fois avec l'arme transformée.*

### B5 — Le drill de coop *(1:40 → 2:30 · lien)*

Au second coude, un pan de glace du plafond **s'effondre en douceur scripté** sur le joueur de tête et
l'emprisonne dans une gangue translucide — état DOWNED maquillé en piège de glace : **c'est la caverne
qui l'a eu, pas une faute de jeu**. Il peut ramper lentement dans sa gangue (les autres le voient
bouger : il est vivant, il attend). Glyphe `Interact` maintenu + anneau de progression de givre
au-dessus de lui : un allié maintient 3 s → la glace éclate, revive, 50 % HP, accolade de particules.
Au passage, les tirs qui touchent la gangue la **fissurent en rouge** une fraction de seconde : la
grammaire « vos tirs blessent vos alliés » est montrée dans un contexte sans enjeu.
**En solo** : l'effondrement piège un **écho gelé** — une silhouette de givre agenouillée (pas un
cadavre : une statue de glace habitée d'une lueur). Même verbe, même glyphe, même 3 s : l'écho se
relève, salue d'un mouvement de tête, et s'évapore en cristaux qui filent vers la sortie. Le verbe
`revive` est appris avec la même gestuelle, la leçon FF est portée par la fissure rouge (tirer sur
l'écho pendant le maintien la déclenche aussi). Dégradé mais présent, assumé.
*Validation : revive accompli (multi : sur le joueur piégé ; solo : sur l'écho).*

### B6 — L'obscurité qui tombe *(2:30 → 3:00 · tension)*

Dès le revive : **toutes les lumières de l'antichambre s'éteignent en cascade**, de l'entrée vers la
sortie — le noir avale le chemin parcouru et pousse dans le dos. Brume dense. Seule la veine du sol
survit, affaiblie. Puis, un par un, des cristaux muraux **se rallument devant** l'équipe, chacun à
~8 m du précédent, chacun ne s'allumant que quand on atteint le précédent. Premier grondement lointain
du Golem pendant la marche. La leçon : *quand tout s'éteint, les cristaux sont la boussole* — c'est
exactement le régime lumineux de la caverne (topographie §5).
*Validation : l'équipe atteint le dernier cristal du chapelet.*

### B7 — Le coffre en climax *(3:00 → 3:40 · récompense/ouverture)*

Le chapelet mène à un dais : **le coffre de départ**, seul objet éclairé. À l'ouverture (Interact),
deux choses en même temps : le tirage classe+arme se joue en **cartes de givre gravées** qui
s'élèvent du coffre (diégétique, pas un écran — la validation manette fige la carte en cristal), et
derrière le dais, la **porte de glace se fend** sur 40 s dans un grondement, révélant en contre-jour la
corniche Z1 et, au loin, la vista V1 : le halo du monolithe et la colonne du puits de jour dans la
brume. Le lobby est fini, le regard est déjà dans le niveau. Valider son loadout = franchir la porte.
*Validation : tous les joueurs actifs ont validé et franchi. La run commence.*

### B8 — Skip *(système, pas un beat vécu)*

Mémorisé **par device** (seule persistance inter-runs autorisée — ce n'est pas de la progression méta,
c'est du confort d'accessibilité ; à documenter comme tel dans le code, cf CLAUDE.md roguelike rules).
Au lancement suivant : l'antichambre apparaît **déjà éveillée** — lumières hautes, gangues fondues,
porte déjà fendue — et le coffre attend au pied de la porte. Marcher tout droit + ouvrir le coffre =
en jeu en < 40 s. Rejouer un beat reste possible (les cristaux fragiles ont repoussé), mais rien ne
l'exige. Le skip est un chemin, pas un menu.

## Filets & cas limites

- **Join tardif** (Start pendant B2–B7) : son cristal de B1 s'allume à distance (audio + lueur dans le
  dos), il spawn au dernier checkpoint de beat avec parchemin en attente au prochain piédestal.
- **Tous les joueurs dans la gangue** (FF trop enthousiaste en B5) : la glace fond d'elle-même en 6 s
  (l'antichambre ne peut pas game-over — c'est un berceau).
- **AFK en B2** : après 45 s d'immobilité totale de l'équipe, la veine pulse plus fort et un cristal
  proche « toussote » des particules. Jamais de texte, jamais de voix off.
- **Chrono cible** : première fois ~3 min 40 ; skip < 40 s ; aucune étape ne peut durer indéfiniment
  sans signal environnemental de relance.


---

## État d'exécution (● Opus, tâche #25, 2026-08-08)

**Ce qui est construit.** Le lieu (`tools/build_antechamber.gd` → `antechamber_terrain.tres`), la
scène (`scenes/levels/antechamber/antechamber.tscn`), la machine des 7 beats vécus
(`scripts/world/antechamber_director.gd`), le cristal fragile (`fragile_crystal.gd` + son shader
d'opale fissurée), le glyphe manette (`frost_glyph.gd`) et le skip par manette
(`onboarding_skip.gd`).

**Trois décisions d'exécution qui méritent d'être connues.**

*L'emprise n'est pas 25 × 15 m.* Le document demande sept beats en enfilade et, pour le seul B6, un
chapelet « à ~8 m les uns des autres » : le chemin fait au bas mot 70 m, qui ne rentrent pas dans
25 × 15. L'antichambre fait **52 × 72 m, voûte 5→8 m** — soit 1/25e de la caverne en surface, et une
voûte deux fois plus basse. L'intention (« un étui avant la révélation d'échelle ») est tenue ; la
cote littérale ne l'est pas.

*Rien n'est posé dans la scène.* Les positions des 21 objets de beat sont des constantes du director,
et chaque objet est recalé sur le sol réellement généré. Déplacer un beat, c'est changer deux nombres.
Le test vérifie que chacune tombe dans le volume creusé — une coordonnée hors chambre donnerait un
objet **enterré dans la roche, invisible et silencieux**.

*Le skip est un ET, pas un OU.* L'antichambre n'apparaît éveillée que si **toutes** les manettes
présentes l'ont déjà vue. Un seul nouveau venu et l'équipe rejoue les trois minutes — ensemble.
L'inverse laisserait un vétéran priver un débutant de son apprentissage.

**Ce qui manque encore.**

| Manque | Pourquoi |
|---|---|
| L'audio des beats — notes de join, accord à quatre, grondement du Golem | attend #31 ; quatre `TODO(audio)` marquent les points d'appel |
| L'écho gelé du B5 en solo | le drill fonctionne en multi ; en solo, le filet « la glace fond en 6 s » s'applique. La silhouette de givre reste à modéliser |
| Le tirage en cartes de givre du B7 | le coffre de départ existe et fait le tirage ; sa mise en scène diégétique reste à faire |
| La vista V1 en contre-jour derrière la porte | demande de raccorder l'antichambre à la caverne (une seule scène ou un fondu) |
| Le join tardif pendant B2–B7 | le cristal s'allume, mais le respawn au dernier checkpoint de beat n'est pas câblé |

**Vérification** : `godot --headless --path godot --script tests/test_antechamber.gd` (6 cas). La carte
vue de dessus : `tools/render_cavern_map.gd --terrain=res://data/levels/antechamber_terrain.tres`.

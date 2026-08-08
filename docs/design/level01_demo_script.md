# Niveau 1 — Script de démo (3 minutes)

> Pour montrer « La Faille du Pilier » à quelqu'un qui n'a jamais tenu la manette. Trois minutes,
> parce qu'au-delà on explique au lieu de faire jouer.
>
> **Le build** : `build/macos/ProjetCactus.app`. Le produire :
> ```
> tools/build_macos.sh
> ```
> Une manette USB minimum, quatre au mieux. Deux joueurs suffisent pour que la démo fonctionne :
> le tir ami et le relèvement demandent au moins deux mains.

---

## Avant de lancer (30 s, hors chrono)

Brancher les manettes **avant** de lancer le jeu. Puis, une seule phrase à dire, et pas une de plus :

> « Vous êtes quatre dans une caverne de glace. Tout ce qui tire fait mal, y compris vos amis. »

Ne pas expliquer les commandes. L'antichambre les enseigne, c'est son métier — et voir quelqu'un
les apprendre seul est la meilleure démonstration qu'elle marche.

---

## 0:00 → 0:40 — L'Antichambre : quatre cristaux s'allument

Chaque manette appuie sur **Start**. Un cristal s'allume au mur par joueur, dans sa couleur.

**Ce qu'il faut faire remarquer** : il n'y a pas d'écran de lobby. Le mur *est* la liste des joueurs.

Puis laisser marcher. La veine de givre au sol pulse dans le sens du chemin, et le premier coude
force à tourner la caméra — personne n'a besoin qu'on lui dise d'utiliser le stick droit.

## 0:40 → 1:10 — Le cristal fragile, puis le combo

Un cristal laiteux barre le passage. Le viser le fait scintiller, le tirer le fait éclater.

Derrière, sur un piédestal : **le parchemin de feu** — la seule lumière chaude d'un couloir
entièrement bleu. Impossible de le manquer. Le ramasser transforme l'arme **sous les yeux du
joueur**, et le tir suivant enflamme les cristaux au lieu de simplement les briser.

**C'est le pic de la démo, et il arrive à la minute un.** Ne rien dire pendant ces vingt secondes.

## 1:10 → 1:40 — Le piège de glace : la coop

Au second coude, le plafond cède sur le joueur de tête et l'emprisonne dans une gangue. Il peut
ramper, pas tirer.

Un allié maintient **Interact** trois secondes : la glace éclate, il est debout à moitié vie.

**Ce qu'il faut faire remarquer** : les tirs qui touchent la gangue la fissurent en rouge. C'est
la leçon du tir ami, apprise sans qu'elle coûte rien.

## 1:40 → 2:00 — Le noir, puis le coffre

Tout s'éteint derrière l'équipe. Des cristaux se rallument devant, un par un, chacun seulement
quand on atteint le précédent. C'est le régime lumineux de la caverne, appris avant d'y entrer.

Au bout : le coffre de départ. L'ouvrir tire la classe et l'arme. Derrière lui, la porte de glace
se fend.

## 2:00 → 2:40 — La caverne : la révélation d'échelle

**Le moment de la démo.** L'antichambre faisait 8 m de haut ; la Grande Nef en fait quinze, et
310 m de long. Le contraste est le sujet.

Laisser les joueurs lever la tête. Deux puits de jour percent la voûte et posent des colonnes de
lumière dans la brume. Au centre, **le lac** et la colonnade qui soutient le plafond effondré.

Trois choses à montrer, dans cet ordre :

1. **La brume change selon l'endroit.** Dix mètres de visibilité dans la forêt de cristaux, trente-
   cinq au bord du lac. On n'avance pas de la même façon.
2. **L'oreille sert de boussole.** Le vent vient des puits, le clapot du lac, le scintillement des
   cristaux. Fermer les yeux une seconde : on sait encore où on est.
3. **La chaussée sur le lac.** Quatre dalles, pas de rambarde, tir ami actif.

## 2:40 → 3:00 — Le Golem

Descendre dans le bol de l'arène. Le boss s'éveille quand tous les joueurs sont entrés, et la
sortie se ferme.

**Ce qu'il faut faire remarquer** : ses veines sont cyan. Quand elles battent, un coup part — la
lueur s'éteint pile à l'impact, personne n'a besoin de compter. À 35 % de vie elles virent à
l'orange et un éclat s'ouvre sur sa poitrine : c'est le point faible, il est **en face avant**,
donc y tirer veut dire tirer vers l'allié qui le maintient occupé.

**S'arrêter là.** Le combat n'a pas besoin d'être gagné pour que la démo ait fonctionné.

---

## Ce qu'on ne montre pas, et pourquoi

| | Pourquoi |
|---|---|
| Le puzzle des trois cristaux et le fragment méta | trois minutes n'y suffisent pas, et le trouver soi-même est tout l'intérêt |
| Le Pilier | ce sont encore des colonnes cylindriques ; l'asset héros n'est pas fait |
| Les sons d'action (impacts, voix du boss) | seules les nappes d'ambiance existent |

## Si quelque chose se passe mal

| Symptôme | Cause probable |
|---|---|
| Un joueur ne bouge pas | sa manette n'a pas fait `Start` — son cristal n'est pas allumé |
| L'antichambre est déjà éveillée | **normal** : toutes les manettes présentes l'ont déjà vue. Pour rejouer l'introduction, supprimer `~/Library/Application Support/Godot/app_userdata/ProjetCactus/onboarding.cfg` |
| Pas de boss | la lib Rust n'est pas dans le build — relancer `tools/build_macos.sh`, qui la synchronise |

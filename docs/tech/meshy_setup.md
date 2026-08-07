# Meshy — setup MCP, licence et règles de production d'assets

> **Zone partagée.** Toute modif de `.mcp.json` passe par une **PR isolée** (cf `CLAUDE.md`).
> Contexte : pipeline de texturing du niveau 1 « Caverne Cristalline » — cf
> [`docs/design/level01_openworld_plan.md`](../design/level01_openworld_plan.md) §3 (étape E1, issue #95).

Meshy est le générateur/retextureur 3D du projet. Il est branché comme serveur **MCP**, au même titre que
`godot-mcp` : un agent peut générer, retexturer, poller l'avancement et télécharger les modèles en autonomie.

---

## 1. Installation par machine

### 1.1. Récupérer une clé API

Chaque machine utilise **sa propre clé**, depuis le dashboard Meshy (`Settings → API Keys`). Format : `msy_…`.

### 1.2. Exporter la clé dans l'environnement

**La clé ne va JAMAIS dans le repo.** `.mcp.json` est versionné et ne contient que l'expansion
`${MESHY_API_KEY}` ; c'est le shell qui fournit la valeur.

```bash
# ~/.zshrc (macOS, shell par défaut du projet)
export MESHY_API_KEY="msy_xxxxxxxxxxxxxxxxxxxx"
```

Puis recharger le shell (`source ~/.zshrc`) **et relancer Claude Code** — les serveurs MCP héritent de
l'environnement du processus qui les lance, une clé exportée après coup n'est pas vue.

### 1.3. Vérifier

```
meshy_check_balance   # doit renvoyer le solde de crédits
```

Si le serveur ne démarre pas ou renvoie une erreur d'authentification :
- `echo $MESHY_API_KEY` dans le shell qui a lancé Claude Code (vide = expansion échouée) ;
- vérifier qu'aucune définition **concurrente** du serveur `meshy` n'existe en scope utilisateur
  (`~/.claude.json`) : elle prendrait le pas sur celle du projet. Si tu avais configuré Meshy à la main
  avant cette PR, supprime ton entrée personnelle et laisse la config du repo faire foi.

### 1.4. Ce qui est dans `.mcp.json`

```json
"meshy": {
  "command": "npx",
  "args": ["-y", "@meshy-ai/meshy-mcp-server"],
  "env": { "MESHY_API_KEY": "${MESHY_API_KEY}" }
}
```

Serveur officiel Meshy (`@meshy-ai/meshy-mcp-server`), lancé par `npx` — rien à installer globalement.

---

## 2. Licence — **validé, on peut embarquer les assets** (2026-08-07)

Garde-fou bloquant du plan (§3 et tableau des risques) : lever le doute **avant** d'embarquer le moindre
asset généré dans le jeu.

**Conclusion : le compte du projet est un compte payant (Pro) → droits commerciaux pleins, sans attribution.**

C'est ce qui rend les assets Meshy compatibles avec la **licence propriétaire du jeu** (cf `LICENSE`) : sur un
plan gratuit, les assets seraient en CC BY 4.0 — attribution obligatoire, donc **incompatible** avec un
« tous droits réservés » propre. Le plan payant n'est pas un confort, c'est une condition.

| | Plan gratuit | **Plan payant (Pro) — notre cas** |
|---|---|---|
| Propriété des assets | Meshy reste titulaire, licence **CC BY 4.0** accordée à l'utilisateur | **L'utilisateur possède les assets** qu'il crée |
| Usage commercial | oui, **mais avec attribution obligatoire** | oui, **sans restriction** |
| Attribution | obligatoire (« Model created with Meshy – CC BY 4.0 License ») | **non requise** |

Formulations de référence (Meshy Help Center) :
- « Under our Terms of Use, if you are a paid customer, you own the assets created through our platform »
- « you retain full private ownership of all assets you create with Meshy, **provided you do not publish
  them publicly to the Meshy Community** »

### 2.1. Les deux conditions à ne pas casser

1. **Ne jamais publier les générations du projet sur la Meshy Community.** La propriété pleine est
   conditionnée à ce que les assets restent privés. Vérifier que les tâches lancées ne sont pas partagées
   publiquement dans le dashboard.
2. **Ne pas nourrir Meshy de matériel sous copyright.** La propriété n'est accordée que si le matériau
   source ne viole pas les droits d'un tiers : donc **pas de prompt du type « dans le style de <jeu ou
   artiste existant> »**, et pas d'image de référence tierce en entrée d'`image_to_3d`. Notre vocabulaire de
   prompt décrit des matériaux et des formes, jamais une œuvre existante — cf l'art bible.

### 2.2. Traçabilité

Chaque asset embarqué porte son champ `license` dans `godot/assets/level01/assets_manifest.yaml`
(valeur attendue : `meshy-paid-full-ownership`), avec le `meshy_task_id` qui permet de remonter à la
génération. Si le plan du compte changeait (retour au gratuit), les assets générés **sous le plan payant**
restent acquis, mais les nouveaux basculeraient en CC BY 4.0 : le champ `license` par asset existe
précisément pour que cette bascule reste traçable.

> ⚠️ Les conditions Meshy peuvent évoluer. Ce constat est daté du **2026-08-07**. À revérifier avant toute
> distribution publique du jeu.

Sources : [Terms of Use](https://www.meshy.ai/terms-of-use) ·
[Can I use my generated assets for commercial projects?](https://help.meshy.ai/en/articles/9992001-can-i-use-my-generated-assets-for-commercial-projects) ·
[What is the ownership of the generated models?](https://help.meshy.ai/en/articles/10137554-what-is-the-ownership-of-the-generated-models)

---

## 3. Crédits — les appels coûtent, on annonce avant

Le serveur MCP impose d'**annoncer le coût et d'obtenir confirmation avant tout appel payant**. Barème :

| Outil | Crédits |
|---|---|
| `meshy_text_to_3d` | 5–20 |
| `meshy_text_to_3d_refine` | 10 |
| `meshy_image_to_3d` / `multi_image_to_3d` | 5–30 |
| **`meshy_retexture`** | **10** |
| `meshy_remesh` | 5 |
| `meshy_uv_unwrap` | 5 |
| `meshy_rig` | 5 |
| `meshy_animate` | 3 |
| `meshy_convert` / `meshy_resize` | 1 |

Solde suivi via `meshy_check_balance` (**1100 crédits** au 2026-08-07). Le coût réel de chaque génération
embarquée est consigné dans le manifest (`credits_spent`), pour qu'on sache ce que le niveau a coûté.

---

## 4. Règles de production (garde-fous perf et cohérence)

Ces règles existent parce que le jeu tourne en **split-screen 4 viewports à 60 fps** : un asset généré sans
contrainte de topologie tue le budget, et un style de prompt qui dérive rend la caverne incohérente.

1. **Retexture-first.** Par défaut on **retexture une géométrie propre** qu'on maîtrise (faite dans Godot ou
   low-poly contrôlée) plutôt que de générer de la géométrie. La topologie générative est imprévisible en
   nombre de triangles.
2. **Génération de géométrie réservée aux hero assets** : les 2-3 landmarks vus de loin, le boss. Pas les
   props semés en nombre.
3. **Prouver la boucle sur UN asset** avant d'industrialiser (c'est la DoD d'E1).
4. **Vocabulaire de prompt figé** dans l'art bible (matériaux, palette, niveau de détail) — c'est le
   garde-fou contre la dérive de style entre deux sessions de génération.
5. **Décider le format de sortie AVANT de générer** : `target_formats` se fixe à la création de la tâche et
   ne se rattrape pas après. Pour Godot : **`glb`**.
6. **Tout asset embarqué a une entrée de manifest.** Pas d'entrée = pas de merge.
7. **LFS** : `.glb`, `.png`, `.obj`, `.fbx` sont déjà couverts par `.gitattributes`. Vérifier avec
   `git lfs status` avant de commiter qu'un binaire n'est pas passé en clair.

## 4bis. Le probe E1 — ce qu'il a appris (2026-08-07)

Boucle prouvée de bout en bout sur **un seul** asset (`crystal_wall_a`), pour **25 crédits**. Trois
enseignements qui changent la façon de produire, et qui sont la raison d'être de la règle « prouver sur
un asset avant d'industrialiser ».

### ⚠️ 1. `target_polycount` est SILENCIEUSEMENT IGNORÉ par `meshy_text_to_3d`

On a demandé 2 000 triangles. On a reçu **838 872 triangles** et un `.glb` de **15 Mo**. Aucune erreur,
aucun avertissement. La cause : `meshy-6` a `should_remesh: false` par défaut, et sans remesh le
paramètre de polycount ne s'applique pas.

Mis en face du budget mesuré (cf `perf_budget.md` : décrochage vers 43 M de primitives cumulées sur
4 viewports), **un seul** de ces cristaux coûte 3,35 M de primitives en 4-split. Une vingtaine
suffisait à faire tomber le jeu sous 60 fps. Un asset généré tel quel est **inutilisable**.

→ **Règle : tout asset généré passe obligatoirement par `meshy_remesh` avant import.** Jamais
d'exception, pas même pour un hero asset. Le remesh a ramené le cristal à **2 046 triangles** et
**114 Ko** — un facteur 410 sur la géométrie, 130 sur le fichier — sans changer sa silhouette
(bounding box identique à 2 mm près). Coût : 5 crédits.

### 2. `meshy_text_to_3d` ne produit qu'un *preview*, non texturé

Le modèle sort avec une normal map mais **sans albedo**. Le texturing demande un
`meshy_text_to_3d_refine` séparé (**+10 crédits**). À budgéter : un asset texturé coûte donc
**20 (génération) + 10 (refine) + 5 (remesh) = 35 crédits**, pas 20.

### 3. Vérifier le remesh dans Godot exige un réimport explicite

Godot conserve son cache d'import quand un fichier est remplacé au même chemin : après téléchargement
du modèle remeshé, l'inspection renvoyait toujours 838 872 triangles. Il faut lancer
`godot --headless --path godot --import` (ou déclencher un rescan) **avant** de mesurer, sinon on
valide l'ancien asset en croyant vérifier le nouveau.

### Coût réel constaté

| Étape | Outil | Crédits | Durée |
|---|---|---|---|
| Génération | `meshy_text_to_3d` (meshy-6) | 20 | 105 s |
| Optimisation | `meshy_remesh` (2 000 tris) | 5 | 14 s |
| *(non fait)* texturing | `meshy_text_to_3d_refine` | *10* | — |

Solde après probe : **1 075 crédits**.

### Point ouvert

La normal map livrée fait **4096²** (4,4 Mo), au-dessus de la règle « 2K max par matériau » de l'art
bible. À réduire avant la production E3/E4.

## 5. Boucle de l'agent texture

```
brief (art bible)
  → meshy_retexture / meshy_text_to_3d      (coût annoncé et confirmé)
  → meshy_get_task_status                    (poll, les tâches sont asynchrones)
  → meshy_download_model                     (glb → godot/assets/level01/)
  → import Godot + vérif tri_count + LFS
  → entrée dans assets_manifest.yaml         (prompt + task_id + licence + coût)
```

Le choix entre **MCP interactif** et **skill CLI reproductible** pour la phase de production (E3/E4) est
tranché après le probe E1 — cf la tâche « Figer le pipeline de production assets ».

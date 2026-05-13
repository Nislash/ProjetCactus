# Godot MCP setup (`tomyud1/godot-mcp`)

## Pourquoi ce MCP

Cf justification dans le plan : 42 tools (édition profonde scènes/scripts, debug, visualization, find usages), plugin Godot embarqué via WebSocket, dernière release v0.5.0 (avril 2026). Préféré à `Coding-Solo/godot-mcp` malgré moins de stars car bien plus complet pour le vibe coding 2-machines.

## Installation

### 1. Serveur MCP (Node.js)

Le repo a `.mcp.json` à la racine qui pointe sur `npx -y godot-mcp-server`. Au démarrage de Claude Code dans le projet, npm va télécharger et lancer le serveur depuis le package npm officiel.

**Prérequis** : Node.js ≥ 18 LTS installé sur chaque machine.

### 2. Plugin Godot

Le plugin est **committé dans le repo** : `godot/addons/godot_mcp/` (version 0.5.0 figée). Pas besoin de cloner le repo amont — il est synchronisé entre les 2 machines via git.

Activation (à faire sur chaque machine, **une seule fois**, après clone) :

1. Ouvrir Godot 4.6+ → ouvrir `godot/project.godot`
2. Le plugin devrait être déjà activé via `[editor_plugins] enabled` dans `project.godot`
3. Sinon : Project → Project Settings → Plugins → cocher "Godot MCP" → Restart Project

Au démarrage, le plugin lance un serveur WebSocket sur **port 6505** (et **6510** pour le visualizer navigateur).

**Indicateur de connexion** : top-right corner de l'éditeur Godot doit afficher "MCP Connected" en vert.

### 3. Vérification

Dans Claude Code, après ouverture du projet et démarrage de Godot :

1. Demander : *"Liste les outils du MCP godot disponibles"* — on doit voir ~42 tools (file/scene/script/project/asset/visualization)
2. Tester : *"Donne-moi le scene tree de `level_01_poc.tscn`"*

Si Godot n'est pas lancé ou si le plugin n'est pas activé, le MCP tournera mais les tools `scene.*` runtime échoueront.

## Workflow recommandé

- **Édition `.tscn`** : passer par les tools `scene.*` du MCP. Édition texte brute de `.tscn` interdite sauf cas justifié (cf `CLAUDE.md` instructions agent).
- **Refactor** : utiliser `find_usages` avant tout renommage ou déplacement (évite de casser les références de l'autre machine)
- **Debug** : utiliser les tools de lecture Output panel + Debugger panel pour récupérer les erreurs runtime sans copier-coller depuis Godot

## Mise à jour du plugin

Le plugin est figé en `godot/addons/godot_mcp/` à la version 0.5.0. Pour bumper :

1. Cloner la nouvelle version : `git clone --depth 1 -b v<X.Y.Z> https://github.com/tomyud1/godot-mcp.git /tmp/godot-mcp-new`
2. Remplacer le contenu : `rm -rf godot/addons/godot_mcp && cp -r /tmp/godot-mcp-new/addons/godot_mcp godot/addons/`
3. Tester la connexion
4. Commit dans une **PR isolée** (le plugin touche les zones partagées)

## Limitations connues

- "No undo" — les modifications sauvent directement. Mitigation : feature branches + commits fréquents.
- Si Godot n'est pas lancé, les tools `scene.*` runtime ne fonctionnent pas (besoin de la connexion WebSocket vivante).

## Fallback

Si tomyud1 pose problème (instabilité, bug bloquant, abandon upstream) : bascule sur [`Coding-Solo/godot-mcp`](https://github.com/Coding-Solo/godot-mcp) en moins de 30 min — modifier `.mcp.json`, désactiver le plugin tomyud1, installer Coding-Solo. Les `.tscn` restent éditables manuellement entre temps.

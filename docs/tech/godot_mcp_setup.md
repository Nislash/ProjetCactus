# Godot MCP setup (`tomyud1/godot-mcp`)

## Pourquoi ce MCP

Cf justification dans le plan : 42 tools (édition profonde scènes/scripts, debug, visualization, find usages), plugin Godot embarqué via WebSocket, dernière release v0.5.0 (avril 2026). Préféré à `Coding-Solo/godot-mcp` malgré moins de stars car bien plus complet pour le vibe coding 2-machines.

## Installation (à faire sur chaque machine, M0)

### 1. Serveur MCP (Node.js)

Le repo a `.mcp.json` à la racine qui pointe sur `npx godot-mcp`. Au démarrage de Claude Code dans le projet, npm va télécharger et lancer le serveur.

**Vérifier le nom exact du package** sur le repo amont : https://github.com/tomyud1/godot-mcp — il peut s'appeler `godot-mcp`, `godot-mcp-server`, ou autre selon la release. Adapter `.mcp.json` si nécessaire.

### 2. Plugin Godot

Cloner le repo amont :
```bash
git clone https://github.com/tomyud1/godot-mcp.git /tmp/godot-mcp
```

Copier le dossier `addons/godot_mcp` (ou nom équivalent dans le repo amont) dans `godot/addons/` du projet. **Ne pas committer** ce dossier — il est dans `.gitignore` à terme (à ajouter), chaque machine l'installe localement.

Activer le plugin :
- Ouvrir Godot → Project Settings → Plugins
- Activer "Godot MCP" (ou nom équivalent)
- Redémarrer Godot

Au démarrage, le plugin lance un serveur WebSocket sur **port 6505** (et **6510** pour le visualizer navigateur).

### 3. Vérification

Dans Claude Code, après ouverture du projet, demander : *"Liste les outils du MCP godot disponibles"*. On doit voir ~42 tools (file/scene/script/project/asset/visualization).

Tester un appel : *"Donne-moi le scene tree de `level_01_poc.tscn`"*.

## Workflow recommandé

- **Édition `.tscn`** : passer par les tools `scene.*` du MCP. Édition texte brute de `.tscn` interdite sauf cas justifié (cf `CLAUDE.md` instructions agent).
- **Refactor** : utiliser `find_usages` avant tout renommage ou déplacement (évite de casser les références de l'autre machine)
- **Debug** : utiliser les tools de lecture Output panel + Debugger panel pour récupérer les erreurs runtime sans copier-coller depuis Godot

## Limitations connues

- "No undo" — les modifications sauvent directement. Mitigation : feature branches + commits fréquents.
- Si Godot n'est pas lancé, les tools `scene.*` dynamiques ne fonctionnent pas (besoin de la connexion WebSocket vivante). Démarrer Godot et activer le plugin avant de commencer la session.

## Fallback

Si tomyud1 pose problème (instabilité, bug bloquant, abandon upstream) : bascule sur [`Coding-Solo/godot-mcp`](https://github.com/Coding-Solo/godot-mcp) en moins de 30 min — modifier `.mcp.json`, désactiver le plugin tomyud1, installer Coding-Solo. Les `.tscn` restent éditables manuellement entre temps.

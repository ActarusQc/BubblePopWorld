# Bubble Pop World — projet Roblox

Implémentation Luau complète et jouable du GDD : grille de papier bulle géante,
éclatement satisfaisant, régénération, économie, niveaux, objets, coffres,
classements, objectif communautaire mondial et boutique d'améliorations.

---

## 1. Installation (Rojo)

```bash
# une seule fois
aftman add rojo-rbx/rojo   # ou : cargo install rojo

# dans le dossier du projet
rojo serve
```

Puis dans Roblox Studio : plugin Rojo → **Connect**.

Sans Rojo, tu peux copier chaque fichier manuellement :

| Fichier | Emplacement Studio | Type |
|---|---|---|
| `src/Shared/*.lua` | `ReplicatedStorage/Shared/` | ModuleScript |
| `src/Server/init.server.lua` | `ServerScriptService/Server` | **Script** |
| `src/Server/*.lua` (autres) | enfants de `Server` | ModuleScript |
| `src/Client/init.client.lua` | `StarterPlayerScripts/Client` | **LocalScript** |
| `src/Client/*.lua` (autres) | enfants de `Client` | ModuleScript |

## 2. Réglages obligatoires dans Studio

1. **Game Settings → Security → Enable Studio Access to API Services** : ON
   (sinon aucune sauvegarde ni classement).
2. **Workspace → StreamingEnabled** : ON (déjà dans le `.project.json`).
3. Remplace les IDs sonores dans `src/Client/PopEffects.lua`
   (`POP_SOUND_ID`, `RARE_SOUND_ID`) par tes propres sons — c'est **le** levier
   n°1 de la sensation de satisfaction.

## 3. Architecture

```
Shared/     GameConfig · BubbleTypes · ToolDefs · Remotes
Server/     DataService · BubbleService · ToolService · DropService
            ChestService · ShopService · LeaderboardService · GlobalCounterService
Client/     PopController · PopEffects · ToolClient · HUD · ShopUI · GridUtil
```

Principes appliqués :

- **Serveur autoritaire.** Le client dit « je pense être sur la case (x,z) »,
  le serveur vérifie la distance, applique un *token bucket* (45 pops/s max)
  et décide seul des récompenses.
- **Effets groupés.** Les POP sont mis en file et diffusés par lots toutes les
  100 ms (`PopEffects`), au lieu d'un RemoteEvent par bulle. C'est ce qui permet
  de tenir des dizaines de joueurs sans saturer la bande passante.
- **Régénération sans instanciation.** On ne détruit jamais une bulle : on
  bascule `Transparency`/`CanCollide` et on retire une nouvelle rareté après
  5 s. Zéro pression sur le GC.
- **Réconciliation de données.** `DataService.reconcile` ajoute les nouvelles
  clés du template aux profils existants : tu peux faire évoluer le jeu sans
  casser les sauvegardes. Si le chargement échoue, la sauvegarde est bloquée
  (jamais d'écrasement de profil).
- **Compteur mondial** : accumulation locale → `IncrementAsync` toutes les 30 s
  → diffusion inter-serveurs via `MessagingService`.

## 4. Équilibrage

Tout est dans `src/Shared/GameConfig.lua` et `BubbleTypes.lua` :
raretés, poids, coûts d'amélioration, intervalles de coffres, multiplicateurs
de monde. Aucune valeur numérique n'est codée en dur ailleurs.

## 5. Ce qui reste à brancher (par ordre de priorité)

1. **Sons et VFX customs** — le POP doit être parfait avant tout le reste.
2. **Téléportation entre mondes** : `BubbleService.BuildWorld(worldDef)` est
   déjà prêt ; il manque un portail + vérification `profile.Worlds`.
3. **Cosmétiques** (skins, traînées, pets, titres) : le champ `Cosmetics` existe
   dans le profil, il faut l'UI + les modèles.
4. **Monétisation** : `MarketplaceService` pour les gamepasses VIP / x2 pièces.
   Rappel du GDD : jamais de pay-to-win.
5. **Événements temporaires** : un `EventService` qui applique un multiplicateur
   global piloté par `os.date` ou un DataStore de configuration.
6. **PvP épingle** : le `Knockback` de l'épingle est déclaré mais pas encore
   appliqué — il suffit d'ajouter une impulsion aux joueurs au-dessus des
   cases éclatées dans `ToolService`.

## 6. Notes de performance

- 40×40 = 1600 parts. C'est confortable. Au-delà de 60×60, passe les bulles
  lointaines en `MeshPart` unique ou active le culling par chunk.
- `StreamingEnabled` gère déjà la distance d'affichage.
- Les effets client sont filtrés à 140 studs et limités à 4 sons simultanés.

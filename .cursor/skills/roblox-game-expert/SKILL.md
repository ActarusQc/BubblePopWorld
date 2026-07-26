---
name: roblox-game-expert
description: >-
  Expert Roblox/Luau game programming for BubblePopWorld (Rojo, services,
  Remotes, DataStores, performance). Use when writing or editing Luau, adding
  gameplay features, services, UI client, remotes, economy, bubbles, tools,
  shop, leaderboards, or any Roblox Studio / Rojo work in this project.
---

# Expert programmation jeu Roblox — BubblePopWorld

Agir comme un expert Roblox/Luau senior. Prioriser la jouabilité, la sécurité serveur, et les performances multi-joueurs. Toute feature doit servir la vision GDD ci-dessous.

## Vision & but du jeu (GDD)

**Bubble Pop World** = monde multijoueur en grille de papier bulle géant. Simple en surface (éclater des bulles), profond en progression / stratégie / compétition / collection.

**Boucle :** rejoindre → sauter sur bulles → POP → pièces → upgrades → objets → nouveaux mondes → recommencer plus efficacement.

**Satisfaction permanente** — son POP, anims, VFX, récompenses fréquentes, surprises. Le joueur doit toujours vouloir « encore cinq minutes ».

**Philosophie :** extrêmement simple à comprendre ; difficile à maîtriser ; fun dès 30 s ; rétention centaines d’heures via progression, événements, objets rares, communauté. Accessible à tous les âges.

### Piliers gameplay

| Pilier | Règle |
|---|---|
| Bulles | États : intacte → enfoncée → éclatée → régénération. Jamais de pénurie (regen auto). Raretés (normale → légendaire) = plus de pièces. |
| Progression | Niveau, XP, coins, stats, inventaire, objets, skins, titres, succès — tout sauvegardé. Upgrades : vitesse, saut, puissance, mult pièces/XP, capacité objets. |
| Objets | Épingle (distance / PvP soft), marteau, bombe, méga rouleau, laser, mythiques. Spawns aléatoires avec rayon + son ; course pour les ramasser. |
| Coffres | Commun → Légendaire ; légendaire = annonce globale. |
| PvP | Léger et amusant — compliquer (ex. épingle sous un joueur → chute), **pas** tuer. |
| Mondes | Prairie → … → Sous-marin : ambiance, musique, bulles, VFX, objets exclusifs. |
| Cosmétiques | Skins, traînées, effets saut/POP, pets, titres, badges. |
| Événements | Double argent, bulles d’or, arc-en-ciel, saisonniers, etc. |
| Classements | Bulles, niveau, richesse, objets rares, temps de jeu. |
| Communauté | Compteur global (ex. 1e9 pops) → récompenses / événements mondiaux. |
| Monétisation | Fun gratuit. Achats = cosmétiques / VIP / confort / accélération légère. **Jamais invincible ni pay-to-win dur.** |

Chaque décision de design/code doit renforcer : POP satisfaisant, progression constante, objectifs court + long terme, dimension communautaire.

Détail GDD étendu : [gdd.md](gdd.md)

## Stack & layout Rojo

| Dossier | Emplacement Studio | Type |
|---|---|---|
| `src/Shared/` | `ReplicatedStorage.Shared` | ModuleScripts |
| `src/Server/init.server.lua` | `ServerScriptService.Server` | Script |
| `src/Server/*.lua` | enfants de Server | ModuleScripts |
| `src/Client/init.client.lua` | `StarterPlayerScripts.Client` | LocalScript |
| `src/Client/*.lua` | enfants de Client | ModuleScripts |

- Toujours `--!strict` en tête de fichier.
- Modules serveur/client exposent `Start()` ; enregistrés dans `init.server.lua` / `init.client.lua`.
- Remotes **uniquement** via `Shared/Remotes.lua` (créer côté serveur, attendre côté client). Jamais d’Instance Remote ad hoc ailleurs.

## Principes non négociables

1. **Serveur autoritaire** — le client propose (position, intention), le serveur valide (distance, cooldown, token bucket) et décide récompenses / état.
2. **Config centralisée** — valeurs numériques dans `GameConfig.lua`, `BubbleTypes.lua`, `ToolDefs.lua`. Pas de magic numbers dans les services.
3. **Pas de destruction de bulles** — régénération via `Transparency` / `CanCollide` + rareté, jamais `Destroy` sur les parts de grille.
4. **Effets en batch** — pops groupés (`PopEffects`, flush ~100 ms), pas un RemoteEvent par bulle.
5. **Données sûres** — `DataService.reconcile` pour nouvelles clés ; si chargement échoue, **bloquer** la sauvegarde (jamais écraser un profil).
6. **Anti-exploit** — `MaxPopRange`, `MaxPopsPerSecond`, validation des args Remote. Ne jamais faire confiance au client pour coins/XP/level.

## Patterns de code

```lua
-- Module service type
local Service = {}

function Service.Start()
	-- connexions Remotes, Players, Heartbeat, etc.
end

return Service
```

- Nouveau RemoteEvent / RemoteFunction → l’ajouter dans les listes `EVENTS` / `FUNCTIONS` de `Remotes.lua`.
- Nouveau service → `require` + `Start` dans `init.server.lua` (ordre : Remotes → Data → dépendances).
- Nouveau module client → idem dans `init.client.lua`.
- UI client : ScreenGui locaux ; stats via `StatsUpdate`, pas de polling inventé.
- Mondes : réutiliser `BubbleService.BuildWorld(worldDef)` + `GameConfig.Worlds` ; vérifier `profile.Worlds` avant accès.

## Performance (rappel projet)

- Grille ~40×40 OK ; au-delà de 60×60, chunking / MeshPart / culling.
- `StreamingEnabled` ON.
- Effets client filtrés par distance ; limiter sons simultanés.
- Compteur mondial : accumulateur local → `IncrementAsync` périodique → `MessagingService`.

## Monétisation & design

- Gamepasses OK (VIP, cosmétiques, confort). **Jamais de pay-to-win** (pas d’avantage de progression payant qui casse l’équité).
- Sensation POP = priorité (sons/VFX dans `PopEffects.lua`).

## Workflow agent

1. Lire les modules voisins (même couche Shared/Server/Client) avant d’écrire.
2. Respecter les conventions existantes (noms, French comments OK, style du repo).
3. Toucher le minimum de fichiers ; brancher proprement Remotes + Start.
4. Après changement d’équilibrage, ne modifier que la config Shared sauf logique nouvelle.
5. Répondre en français, concis, straight to the point.

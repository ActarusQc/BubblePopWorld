# BubblePopWorld — Boucle de progression (Lobby / Sac / Vente)

**Date :** 2026-07-25  
**Statut :** Approuvé (sections 1–3 + corrections finales)  
**Contraintes :** Rojo sync uniquement (`rojo serve`) ; pas de `rojo build` ; pas de publication ; pas d’écrasement Workspace

---

## 1. Objectif

Transformer la boucle actuelle (apparition sur la planche → pop → pièces immédiates) en :

Lobby → salle de bulles → remplir le sac → retour lobby → vendre → pièces → (upgrades) → rejouer

Les pièces des bulles normales ne sont attribuées qu’à la vente. Les coffres restent une source directe de pièces.

---

## 2. Décisions validées

| Sujet | Décision |
|---|---|
| Économie sac | Hybride : `CurrentBubbles` (UI) + `PendingSellValue` (vente) |
| XP bulles | Immédiate au pop réussi |
| Pièces bulles | Uniquement à la vente (`BubbleSale`) |
| Coffres | `AddCoins(..., "Chest")` direct ; hors sac |
| Plancher grille | **Aucun** plancher continu sous les bulles ; chute entre cases vides |
| FallReset | Défaut `GameRoom` ; option `Lobby` via config |
| Monde | Hybride minimal : code crée le fonctionnel ; décor Studio plus tard |
| Multiplicateurs | Appliqués au pop sur `PendingSellValue` (combo, CoinMult, monde, outil) ; XP avec ses mults |
| Services | Approche 1 : `BackpackService` + `ZoneService` + DataService étendu |
| UI | Étendre `HUD.lua` existant (pas de `BackpackUI` sauf isolation claire) |

---

## 3. Architecture

### 3.1 Services

| Service | Responsabilité |
|---|---|
| **BackpackService** | Capacité, ajout atomique, rollback, vente atomique (`IsSelling`) |
| **ZoneService** | Dossiers/zones idempotents, téléports, FallReset, prompts entrée/sortie/vente |
| **DataService** | Profil, reconcile, `AddCoins(player, amount, source)`, push stats, sauvegardes |
| **BubbleService** | Grille, verrou cellule, pop central |
| **ToolService** | Appelle uniquement `BubbleService.PopCells` |
| **ChestService** | Pièces/XP directs via DataService ; hors sac |

**LobbyService / CurrencyService :** non créés.

### 3.2 Fichiers prévus

**Créés**
- `src/Server/BackpackService.lua`
- `src/Server/ZoneService.lua`

**Modifiés**
- `src/Shared/GameConfig.lua`
- `src/Shared/BubbleTypes.lua`
- `src/Shared/Remotes.lua` (si besoin)
- `src/Server/DataService.lua`
- `src/Server/BubbleService.lua`
- `src/Server/AmbianceService.lua` (barrières déléguées / adaptées)
- `src/Server/ChestService.lua`
- `src/Server/ToolService.lua` (si besoin)
- `src/Server/init.server.lua`
- `src/Client/HUD.lua` — jauge sac (préférence vs nouveau fichier)
- `src/Client/PopEffects.lua`
- `src/Client/init.client.lua` (si besoin)

### 3.3 Ordre de démarrage serveur

```
Remotes
→ DataService
→ BackpackService
→ ZoneService
→ BubbleService
→ ToolService
→ DropService
→ ChestService
→ ShopService
→ LeaderboardService / GlobalCounter / Combo / Ambiance (selon dépendances existantes)
```

**Règle :** `BackpackService` démarre après `DataService`, et **avant** tout service pouvant ajouter au sac ou vendre (`BubbleService`, `ToolService`, `ZoneService` pour Sell).

`AmbianceService` / `ComboService` / `GlobalCounterService` peuvent rester avant ou après tant qu’ils n’ajoutent pas au sac ; l’ordre ci-dessus est la référence pour la boucle progression.

---

## 4. Données joueur (DataStore)

**Store inchangé :** `BPW_PlayerData_v1`  
**Migration additive uniquement.**

```lua
CurrentBubbles = 0,
BackpackCapacity = 25, -- Config.Backpack.DefaultCapacity
PendingSellValue = 0,  -- entier
```

**Pas de `PendingXP`.**

### 4.1 Réconciliation au chargement

1. Bornes : capacité, clamp `CurrentBubbles` dans `[0, BackpackCapacity]`, `PendingSellValue` entier ≥ 0  
2. Invariant : `CurrentBubbles == 0 ⇔ PendingSellValue == 0`  
3. Si `CurrentBubbles == 0` → forcer `PendingSellValue = 0`  
4. Si `CurrentBubbles > 0` et `PendingSellValue <= 0` → remettre sac à zéro (`CurrentBubbles = 0`, `PendingSellValue = 0`) et `warn` serveur (données anciennes insuffisantes pour reconstruire une valeur sûre)  
5. Ne jamais payer `PendingSellValue` si `CurrentBubbles == 0`  
6. **Ne jamais réinitialiser `Coins`**

### 4.2 Sauvegarde

`CurrentBubbles` et `PendingSellValue` font partie du profil et passent par :
- sauvegarde périodique DataService (60 s)
- `PlayerRemoving` / `Release`
- `BindToClose`

Pas de `SetAsync` à chaque pop. Une vente réussie marque le profil dirty / pousse immédiatement les attributs ; inclusion au prochain cycle Save normal. `PlayerRemoving` ne doit pas persister un état intermédiaire incohérent pendant `IsSelling` (attendre fin du verrou vente ou finaliser atomiquement avant Save).

---

## 5. BackpackService — API

```
IsFull(player) -> boolean
CanAdd(player, storageAmount) -> boolean
GetRemainingCapacity(player) -> number
AddBubbles(player, storageAmount, sellValue) -> ok, err, snapshot?
  -- snapshot = { CurrentBubbles, PendingSellValue } avant mutation (pour rollback)
RollbackAdd(player, snapshot) -> ()
GetStoredAmount(player) -> number
GetSellValue(player) -> number
Sell(player) -> soldBubbles, earnedCoins, err
ReconcileProfile(data) -> ()  -- appelé au Load
```

### 5.1 StorageValue > espace restant

Pas de remplissage partiel. Si `not CanAdd` : bulle intacte, pas d’XP, pas de pending, pas d’effet.

### 5.2 Arrondi PendingSellValue (au pop uniquement)

1. Calculer `raw = SellValue * coinMult * worldMult * toolMult * comboMult`  
2. `rounded = math.floor(raw + 0.5)`  
3. Si `SellValue > 0` et bulle valide → `rounded = math.max(1, rounded)`  
4. Refuser NaN / infini / négatif (`sellValue` stocké doit être un entier fini ≥ 0)  
5. Stocker `PendingSellValue` comme **entier**  
6. **Ne pas ré-arrondir à la vente** — payer exactement `PendingSellValue`

### 5.3 Sell atomique + verrou `IsSelling`

1. Si `IsSelling[player]` → refuser  
2. Poser `IsSelling = true`  
3. `pcall` / cleanup `finally` : toujours libérer le verrou  
4. Lire `CurrentBubbles` et `PendingSellValue`  
5. Refuser si `CurrentBubbles <= 0` ou `PendingSellValue <= 0` (après reconcile, invariant respecté)  
6. Copier valeurs ; zéroer immédiatement en mémoire  
7. `DataService.AddCoins(player, earned, "BubbleSale")`  
8. Échec → restaurer valeurs  
9. Push attributs ; marquer dirty ; Announce  
10. Libérer `IsSelling`

ZoneService déclenche Sell après validation distance — jamais de montant client.

---

## 6. Pop — verrou cellule + rollback

### 6.1 Verrou atomique par cellule

Avant toute mutation du sac, pour chaque cellule :

1. Vérifier `alive`  
2. Vérifier pas déjà en pop (`IsBeingPopped` / `PoppingBy`)  
3. Poser verrou serveur temporaire  
4. Un seul joueur réussit  

Ordre par cellule réussie :

1. Joueur + profil valides  
2. Distance / budget (niveau requête)  
3. **Claim cellule** (alive + verrou)  
4. Type valide  
5. `CanAdd` pour tout `StorageValue`  
6. `AddBubbles` (retourne snapshot)  
7. Pop réel (désactiver bulle, queue effets)  
8. Si pop réel échoue → `RollbackAdd` + libérer verrou + bulle reste/redevient active ; **pas d’XP** ; **pas d’effet**  
9. XP immédiate  
10. Libérer / nettoyer verrou  
11. Réplication UI  

Si `AddBubbles` échoue après claim : retirer verrou ; bulle active ; aucun effet ; aucune XP.

Ne pas se fier à `Alive` seul puis mutation différée (course entre deux joueurs).

### 6.2 Batch Power / outils

Cellule par cellule avec claim individuel. Pas de pop partiel d’une bulle. Outils → uniquement `BubbleService.PopCells`.

### 6.3 Multiplicateurs

Sur SellValue → Pending (arrondi §5.2) : CoinMult, world Mult, tool mult, combo.  
XP : XPMult + combo + tool ; immédiate après pop réel réussi.

---

## 7. BubbleTypes

```lua
StorageValue = def.StorageValue or 1
SellValue = def.SellValue or def.Coins or 1
-- conserver Coins temporairement pour refs legacy ; ne plus l’utiliser comme pièce immédiate
```

| Id | StorageValue | SellValue | XP |
|---|---|---|---|
| Normal | 1 | 1 | 1 |
| Rare | 1 | 8 | 5 |
| Golden | 1 | 45 | 22 |
| Diamond | 1 | 220 | 95 |
| Legendary | 1 | 1800 | 700 |

```lua
Config.Backpack = {
  DefaultCapacity = 25,
  MaxCapacity = 1000,
  NearlyFullRatio = 0.75,
  FullNotifyCooldown = 3,
}
```

---

## 8. ZoneService — monde additif

### 8.1 Hiérarchie

```
Workspace.BubblePopWorld
├── Lobby
│   ├── LobbySpawn
│   ├── SellZone
│   ├── GameEntrance
│   └── Signs (Studio)
└── GameRoom
    ├── GameRoomSpawn
    ├── ExitZone
    ├── SafetyBorders
    └── (BubbleWorld = BubbleService)
```

### 8.2 Objets GeneratedByCode

| Cas | Comportement |
|---|---|
| Objet absent | Créer depuis `GameConfig` ; `GeneratedByCode = true` |
| Objet existe | **Réutiliser sans modifier position ni taille** |
| Rebuild layout | Option dév `Config.World.RebuildGeneratedLayout = false` (défaut) ; si true, repositionne uniquement les objets `GeneratedByCode` |
| Suppression | **Jamais** automatique |
| ProximityPrompt | Réparer additivement si propriétés indispensables manquent |

Un marker ajusté dans Studio ne revient pas à l’ancienne position au prochain lancement (défaut).

### 8.3 Téléports

`TeleportToLobby` / `TeleportToGameRoom` : serveur ; attendre Character + HRP ; offset Y léger ; vélocité 0 ; anti-spam 1–2 s ; sac/outils conservés ; `PlayerArea` seulement après succès.

Spawn initial : profil chargé → Lobby ; debounce CharacterAdded.

### 8.4 Interactions

| Zone | Prompt | Action |
|---|---|---|
| GameEntrance | Entrer dans la salle de bulles | → GameRoom |
| ExitZone | Retourner au lobby | → Lobby |
| SellZone | Vendre mes bulles | distance + `BackpackService.Sell` |

### 8.5 SafetyBorders & FallReset

Quatre côtés, coins fermés, ouverture entrée/sortie ; collision réelle ; transparence modérée ; pas de chevauchement bulles ; idempotent.

```lua
Config.World.FallResetY = -25
Config.World.FallResetDestination = "GameRoom" -- ou "Lobby"
Config.World.RebuildGeneratedLayout = false
```

### 8.6 Plancher

Retirer le `Floor` continu sous la grille. Sol lobby + plateformes périphériques / passages seulement. Chute entre bulles autorisée ; barrières = côtés uniquement.

---

## 9. Réplication & UI

**Autorité :** profil serveur.  
**Miroir :** attributs Player mis à jour par le serveur.

**UI :** étendre `HUD.lua` (pièces / XP / niveau / Announce déjà présents) avec jauge sac. Créer `BackpackUI.lua` seulement si composant clairement isolé consommé par le HUD — **préférence : pas de second ScreenGui stats**.

HUD principal : `Sac : 12 / 25` + barre + pièces.  
Lobby / près SellZone : « Valeur du sac : X pièces » (`PendingSellValue`).  
États barre : 0–74 % / 75–99 % / 100 %.  
Sac plein : message + cooldown notification ; pas de spam.

**StatsUpdate :** étendre avec champs sac si encore utilisé ; synchroniser avec attributs (une logique Push serveur).

**PopEffects :** plus de `+Coins` bulles ; `+1` / `+1 bulle` ; XP OK ; coffres `+N pièces` OK.

---

## 10. Sécurité

Client n’envoie jamais montants / capacité / type récompense.  
Serveur : distances, alive + verrou cellule, capacité, cooldowns, budget, profil, nombres finis/bornés, `IsSelling`, distance SellZone.

---

## 11. Tests manuels

- Nouveau joueur lobby, sac 0/25  
- Entrée / sortie / anti-spam téléport  
- Pop : sac ↑, pièces inchangées, XP ↑  
- Outils / Épingle : capacité  
- Sac plein + cooldown message  
- StorageValue > reste  
- Vente OK / vide / incohérences réconciliées  
- Double vente ; déconnexion pendant vente (`IsSelling`)  
- Respawn / reconnexion sac partiel  
- Coffre pièces directes  
- Chute → GameRoomSpawn  
- Barrières  
- **Deux joueurs même bulle → un seul gagnant**  
- Migration profil ; HUD reconnexion  
- Marker Studio non repositionné (Rebuild=false)

---

## 12. Hors scope / interdit

- `rojo build`, publication, `.rbxl` généré  
- Vider Workspace  
- Plancher sous toutes les bulles  
- Pièces immédiates bulle normale  
- Réinit DataStore / perte Coins  
- Contournement capacité outils  

---

## 13. Studio manuel / Rojo

Décor plus tard. Test : `rojo serve` → sync Studio → Play Solo → section 11. Ne pas publier.

---

## 14. Self-review

- [x] Ordre Start : Backpack avant Bubble  
- [x] Verrou cellule + un seul gagnant  
- [x] Rollback sac si pop échoue  
- [x] Arrondi PendingSellValue explicite  
- [x] Réconciliation profils incohérents  
- [x] GeneratedByCode : pas de repositionnement par défaut  
- [x] UI = extension HUD  
- [x] Save périodique + BindToClose + dirty vente  
- [x] IsSelling + cleanup  
- [x] Pas de PendingXP  
- [x] Pas de plancher grille continu  

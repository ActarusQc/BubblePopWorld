# Design — Boutique walk-in (ItemShop)

**Date :** 2026-07-30  
**Projet :** Bubble Pop World (`BubblePopWorld`)  
**Approche retenue :** Refactor ciblé — remplacer le kiosque d’achat par un bâtiment walk-in ; réutiliser `ShopService` / upgrades / sacs ; SellBooth inchangé.

## 1. Objectif

Remplacer la boutique kiosque actuelle par un magasin immersif dans le lobby :

- le joueur entre physiquement dans le bâtiment ;
- trois murs thématiques (Skills / Items / Cosmetics) ;
- browse par mur avec caméra verrouillée locale, navigation gauche/droite, UI compacte ;
- achats sécurisés serveur pour les items déjà live ;
- items futurs visibles en Coming Soon / Locked, sans achat ni persistence.

## 2. Hors scope (v1)

- Aucune modification du SellBooth / vente auto de bulles.
- Aucun gameplay nouveau (Magnet, Luck, Pin shop, Hammer shop, cosmétiques équipables).
- Pas de faux achats ni écriture profil pour `Available = false`.
- Pas de porte physique.

## 3. Architecture

```
src/Shared/ShopCatalog.lua       — catégories + items (Available, Type, prix)
src/Shared/GameConfig.lua        — dims / offsets ItemShop (SellBooth intact)
src/Shared/LocalizationStrings.lua — textes EN boutique
src/Server/ItemShopBuilder.lua   — bâtiment walk-in, prompts, présentoirs
src/Server/ShopService.lua       — GetShopData enrichi + garde Available
src/Client/ShopUI.lua            — browse local (caméra, freeze, UI)
```

Remotes existants réutilisés : `GetShopData`, `BuyUpgrade`, `BuyItem`, `EquipBackpack`.  
Aucun nouveau remote d’achat pour Coming Soon.

## 4. Monde — bâtiment `Workspace.ItemShop`

### 4.1 Placement

- Emplacement général de l’ancien ItemShop (`Lobby.ItemShop` / `ItemShopPosition`).
- Taille raisonnablement augmentée pour circulation intérieure multi-joueurs.
- Ne chevauche pas SellBooth, téléporteur, chemins, ni ne bloque la vue principale du lobby.
- Circulation boutique ↔ SellBooth ↔ téléporteur reste fluide.

### 4.2 Structure Workspace (noms exacts)

```
Workspace.ItemShop                -- Model racine (conservé pour compatibilité)
  Entrance
  Wall_Skills
  Wall_Items
  Wall_Cosmetics
  PromptAnchor_Skills
  PromptAnchor_Items
  PromptAnchor_Cosmetics
  CameraPoint_Skills
  CameraPoint_Items
  CameraPoint_Cosmetics
  Display_Skills
  Display_Items
  Display_Cosmetics
```

Chaque catégorie a son propre `CameraPoint_*` et `Display_*`.  
Enseignes murales clairement lisibles : Skills / Items / Cosmetics.  
Enseigne façade : SHOP (clé L10n existante ou dédiée).

### 4.3 Entrée & collisions

- Entrée large, ouverte, sans porte, sans collision invisible bloquante.
- Plancher, murs porteurs, limites utiles : `CanCollide = true`.
- Décorations non nécessaires : `CanCollide = false`.
- Toutes les parts générées : `Anchored = true`.

### 4.4 Idempotence Builder

- `ItemShopBuilder.Build` détruit **uniquement** le modèle racine existant nommé `ItemShop` (et legacy `BubbleShop` si encore présent).
- Ne touche jamais SellBooth, décorations manuelles du lobby, ni téléporteur.
- Un refresh ne crée pas de doubles prompts / doubles boutiques.
- Attribut `BPW_ItemShop = true` conservé sur le modèle.

### 4.5 ProximityPrompts

| Ancre | ActionText (EN) | ObjectText |
|---|---|---|
| `PromptAnchor_Skills` | Browse Skills | Skills |
| `PromptAnchor_Items` | Browse Items | Items |
| `PromptAnchor_Cosmetics` | Browse Cosmetics | Cosmetics |

Prompts larges (MaxActivationDistance confortable, HoldDuration 0, RequiresLineOfSight false si besoin) : PC / mobile / console, sans viser un petit objet.

## 5. Data — `ShopCatalog`

### 5.1 Catégories

`Skills` | `Items` | `Cosmetics` — extensibles pour futures catégories.

### 5.2 Schéma item (minimum)

| Champ | Rôle |
|---|---|
| `Id` | Identifiant unique |
| `Name` | Affichage (ou clé L10n) |
| `Category` | Skills / Items / Cosmetics |
| `Price` | Prix affiché ; pour upgrades live = coût calculé serveur |
| `Description` | Courte description EN |
| `IconKey` / `ModelName` | Visuel UI / présentoir |
| `UnlockRequirement` | Optionnel (futur) |
| `Type` | `Upgrade` \| `Tool` \| `Cosmetic` \| `Backpack` |
| `Equipable` | boolean |
| `Available` | `true` = achetable / upgradable ; `false` = Coming Soon |

### 5.3 Catalogue v1

**Available = true (prix & effets inchangés) :**

- Skills : `Speed`, `Jump`, `Power`, `CoinMult` (via `GameConfig.Upgrades` + `UpgradeOrder`)
- Items : `BackpackGold`, `BackpackEmerald`, `BackpackNeon` (via `GameConfig.ShopItems`)

**Available = false (visibles, non achetable) :**

- Skills : ex. Magnet, Luck, Capacity Boost (placeholders catalogue)
- Items : ex. Pin, Hammer, Multi Pop Tool, Special Tool (shop permanente — distincte des drops monde)
- Cosmetics : ex. Cap, Hat, Vest, Shirt, Accessory

Aucun profil modifié pour ces IDs en v1.

## 6. Client — browse local

### 6.1 Isolation multi-joueurs

Caméra, freeze contrôles et UI sont **100 % locaux** au joueur. Aucun RemoteEvent pour entrer/sortir du browse. Les autres joueurs dans la boutique ne sont pas affectés.

### 6.2 Entrée browse

1. ProximityPrompt catégorie → ouvrir browse.
2. Mémoriser **avant freeze** : `WalkSpeed`, `JumpPower` et/ou `JumpHeight`, `AutoRotate`, état contrôles (`PlayerModule` / `Controls:Disable` si utilisé).
3. Freeze : vitesse/saut à 0, contrôles désactivés. **Pas de téléport** du personnage.
4. Désactiver temporairement les **autres** prompts de `ItemShop` pour ce client (éviter double catégorie / multi-tweens).
5. Tween caméra douce vers `CameraPoint_<Category>`, focus `Display_<Category>`.
6. Afficher UI compacte ; charger `GetShopData` ; montrer l’item courant (modèle/icône sur Display).

### 6.3 Navigation & UI

- Gauche / droite : boucle (après le dernier → premier, et inversement).
- Afficher : nom, prix, description, bouton d’action.
- États bouton possibles : Buy, Equip, Equipped, Upgrade, Too Expensive, Coming Soon / Locked, Max.
- `Available = false` : **aucun** bouton d’achat actif ; libellé Coming Soon ou Locked uniquement ; **aucun** InvokeServer d’achat.
- Après achat/équip réussi : rafraîchir immédiatement coins, owned, niveau upgrade, texte bouton **sans** fermer le browse.

### 6.4 Sortie — `ExitBrowse()` unique

Tous les chemins appellent une seule fonction sécurisée `ExitBrowse()` :

- bouton Close (mobile) ;
- Escape (PC) ;
- bouton B (console / gamepad) ;
- mort, respawn, suppression du personnage ;
- fermeture UI / erreur.

`ExitBrowse()` doit être idempotente (appels répétés sans effet de bord) et :

1. restaurer **exactement** les valeurs mémorisées (pas de constantes hardcodées) ;
2. restaurer caméra (Custom / sujet joueur) ;
3. réactiver les prompts ItemShop pour ce client ;
4. cacher l’UI ;
5. annuler tweens caméra en cours.

## 7. Serveur — achats

- `GetShopData` : retourne lignes par catégorie avec `Available`, niveaux, owned, equipped, coûts live.
- `BuyUpgrade` / `BuyItem` / `EquipBackpack` : logique prix/effets **inchangée** pour items live.
- Garde serveur : si l’id n’est pas dans le catalogue live / `Available ~= true`, **rejeter** (même si le client triche et envoie manuellement).
- Pas d’écriture `OwnedItems` / `Cosmetics` / upgrades pour Coming Soon.
- Persistance existante inchangée : upgrades, OwnedItems, EquippedBackpack.

## 8. Localisation

Tous les textes visibles restent en **anglais** (source AutoLocalize).  
Nouvelles clés dans `LocalizationStrings` : Browse Skills/Items/Cosmetics, Coming Soon, Locked, Cosmetics, Too Expensive, etc.

## 9. Fichiers

| Action | Fichier |
|---|---|
| Créer | `src/Shared/ShopCatalog.lua` |
| Réécrire | `src/Server/ItemShopBuilder.lua` |
| Réécrire | `src/Client/ShopUI.lua` |
| Modifier | `src/Server/ShopService.lua` |
| Modifier | `src/Shared/GameConfig.lua` (ItemShop dims/offsets seulement) |
| Modifier | `src/Shared/LocalizationStrings.lua` |
| Touch léger | `init.client.lua` / `init.server.lua` si besoin |
| Inchangé | SellKioskBuilder, AutoSell, InventoryUI (sauf si GetShopData shape), prix upgrades/sacs |

## 10. Critères de succès

- [ ] Un seul `Workspace.ItemShop` après refresh ; pas de reste du vieux kiosque.
- [ ] Joueur entre, circule, browse chaque mur PC / mobile / console.
- [ ] Browse local : 2 joueurs peuvent browse des murs différents sans interférence.
- [ ] ExitBrowse restaure contrôles/caméra dans tous les cas listés.
- [ ] Speed/Jump/Power/CoinMult + sacs achetable avec prix/effets identiques.
- [ ] Coming Soon : pas d’achat client ni serveur, pas de mutation profil.
- [ ] SellBooth et téléporteur intacts.

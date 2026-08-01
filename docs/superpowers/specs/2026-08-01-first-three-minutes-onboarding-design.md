# Spec — Refonte des trois premières minutes (onboarding / rétention D1)

- **Date** : 2026-08-01
- **Priorité** : 2 — Première session du nouveau joueur
- **Statut** : Spécification approuvée. Aucune modification de script de production effectuée. Les 5 décisions ouvertes ont été validées le 2026-08-01 (§14).
- **Portée** : de l'apparition du joueur jusqu'à son premier achat d'amélioration (~0 → 180 s).
- **Hors portée** : rééquilibrage global de l'économie, refonte de la Summer Zone, nouveaux items.

---

## 1. État actuel confirmé dans le code

Toutes les valeurs ci-dessous ont été relevées directement dans les fichiers, pas déduites.

### 1.1 Géométrie du monde

| Élément | Valeur | Source |
| --- | --- | --- |
| Grille | 40 × 40, Spacing 6, Origin `(0, 6, 0)` | `src/Shared/GameConfig.lua` L7-13 |
| Bornes grille | X ∈ [-120, 120], Z ∈ [-120, 120] | `GameConfig.GetGridBounds()` |
| Première rangée de bulles (sud) | `z = 1` → Z monde = **-114** | `ZoneDefs.CellToWorld` L243-249 |
| Racine lobby | `(0, 0, -240)` | `GameConfig.lua` L115 |
| Plancher lobby | 110 × 80 → Z ∈ [-280, -200] | `GameConfig.Lobby.FloorSize` L136 |
| `LobbySpawn` | `(0, 4, -240)` | `Lobby.SpawnOffset` L140 |
| Kiosque de vente (SellPad) | ≈ `(-34, 1.2, -223.2)` — **ouest** de l'allée | `Lobby.SellPosition` L132/143 |
| ItemShop | ≈ `(34, 0, -230)` — **est** de l'allée (miroir) | `Lobby.ItemShopPosition` L533 |
| Arche d'entrée lobby | `(0, 3, -204)` | `Lobby.EntrancePosition` L210 |
| `ExitPad` (salle) | centre `(0, 6, -184)`, Z ∈ [-192, -176] | `GameRoom.ExitOffset` L224 |
| `SpawnPad` (salle) | centre `(0, 8, -164)`, Z ∈ [-176, -152] | `GameRoom.SpawnOffset` L223 |
| `AreaSplitZ` | -198 (Z < -198 → `Lobby`) | `World.AreaSplitZ` L101 |

### 1.2 Point d'apparition réel

**Il n'existe aucun `SpawnLocation` dans le projet** (`rg SpawnLocation src/` → 0 résultat, aucun dans `default.project.json`).

Conséquence vérifiée dans `src/Server/ZoneService.lua` L2492-2506 :

```2492:2506:src/Server/ZoneService.lua
local function onCharacterAdded(player: Player)
	if spawningInProgress[player] then
		return
	end
	spawningInProgress[player] = true
	task.spawn(function()
		local deadline = os.clock() + 10
		while not DataService.Get(player) and os.clock() < deadline do
			task.wait()
		end
		-- Seul téléport de gameplay : apparition initiale dans le lobby.
		ZoneService.TeleportToLobby(player, true)
		spawningInProgress[player] = nil
	end)
end
```

1. Roblox fait apparaître le personnage au comportement par défaut, c'est-à-dire **au-dessus de l'origine du monde `(0, ~y, 0)`, soit en plein centre du plateau de bulles**.
2. Le serveur attend le chargement du DataStore (`DataService.Get`, jusqu'à 10 s de deadline).
3. Puis il téléporte vers `LobbySpawn` `(0, 7, -240)`.

Le joueur voit donc, pendant 0,3 à 2 s (plus selon la latence DataStore), le plateau de bulles depuis son centre, puis se fait projeter 240 studs plus au sud. `LobbySpawn` est un `Part` non-`SpawnLocation` (`ZoneService.lua` L1965-1969) : **aucune orientation n'est appliquée**, le joueur conserve l'orientation par défaut de Roblox (regard vers -Z), donc **dos à la salle de bulles**.

### 1.3 Distance et temps avant la première bulle

- `LobbySpawn` Z = -240 → première rangée Z = -114 → **126 studs** en ligne droite, plus **6 studs de dénivelé** (escalier de 6 marches, `ZoneService.lua` L2099-2141).
- `PlayerMovement.WalkSpeed = 16` (`GameConfig.lua` L425).
- **Minimum théorique** : 126 / 16 ≈ **7,9 s** de course parfaitement rectiligne, sans temps de réaction, sans demi-tour.
- **Réalité mesurée sur le parcours** : demi-tour initial (le joueur regarde au sud), traversée de l'allée entre les deux bâtiments, arche, pont d'approche, escalier, `ExitPad`, `SpawnPad`, `ArrivalPath` → **14 à 25 s** pour un nouveau joueur, davantage s'il s'arrête lire le panneau.

**La cible « première bulle en moins de 10 secondes » est géométriquement impossible avec le point d'apparition actuel**, même pour un joueur parfait.

### 1.4 Éléments qui distraient ou ralentissent

| Élément | Où | Effet |
| --- | --- | --- |
| Flash d'apparition sur le plateau | `ZoneService.onCharacterAdded` | Désoriente, peut déclencher un rebond/pop involontaire avant le téléport |
| Orientation dos à la salle | absence de `SpawnLocation` | Le joueur doit chercher la sortie |
| Panneau « HOW TO PLAY » 5 lignes | `Lobby.SignText` L214 | Texte long, mur du fond, lecture optionnelle mais chronophage |
| Pad « Bubble Transit » | `TravelConfig.ResolveLobbySpawnPlatformPosition` | Sur le trajet naturel spawn → arche ; **ouvre une modale plein écran** (`src/Client/TravelController.lua`, `openMenu`) |
| Kiosque + boutique 3D | ouest/est de l'allée | Vitrine, prompts `E` / `ButtonX` (`ItemShopBuilder.lua` L247-257) avant même d'avoir des pièces |
| Escalier 6 marches | `ZoneService` L2128-2141 | Ralentit, casse la ligne de vue vers la salle |

### 1.5 Comportement du sac en première session

- `Backpack.DefaultCapacity = 25` (`GameConfig.lua` L31).
- Chaque bulle vaut `StorageValue = 1` quelle que soit sa rareté (`BubbleTypes.lua` L8-12).
- → **25 pops exactement remplissent le sac initial.**
- `NearlyFullRatio = 0.75` → alerte visuelle à 19 bulles ; `FullNotifyCooldown = 3`.
- `BackpackService.NotifyFull` envoie un toast `Announce` (« Your backpack is full! »), la barre HUD passe en rouge (`src/Client/HUD.lua`) et le compteur 3D du sac passe en rouge (`src/Server/BackpackVisual.lua`). **Aucune indication directionnelle.**
- Les pièces ne sont créditées qu'à la vente (`BackpackService.Sell`), l'XP/`TotalBubblesSold` étant traité par `DataService.AddBubblesSold`.

### 1.6 Logique des bulles spéciales

`src/Shared/BubbleTypes.lua` — tirage pondéré, **par cellule, à la construction et à chaque régénération** (`RegenTime = 30 s`). Le plateau est partagé : il n'y a **aucun tirage par joueur**.

| Rareté | Weight | Part | SellValue |
| --- | --- | --- | --- |
| Normal | 1000 | 87,11 % | 1 |
| Rare | 110 | 9,58 % | 8 |
| Golden | 30 | 2,61 % | 45 |
| Diamond | 7 | 0,61 % | 220 |
| Legendary | 1 | 0,087 % | 1800 |
| **Total** | **1148** | | |

- P(≥1 spéciale sur 25 pops) = 1 − (1000/1148)²⁵ = **96,8 %** ✅
- P(≥1 spéciale **visuellement évidente**, Golden+) = 1 − (1110/1148)²⁵ = **56,9 %** ⚠️
- Pops moyens avant la première Golden+ : **≈ 30** → au-delà du premier sac.

Le problème n'est donc pas la fréquence des spéciales mais leur **lisibilité** : `Rare` est teinté `RGB(90,170,255)` contre `RGB(145,225,255)` pour Normal — un bleu à peine plus soutenu, sur un matériau `Glass` translucide à 0,35. `src/Client/PopEffects.lua` L117-122 n'affiche du texte flottant **que** pour les non-Normal, mais le burst reste discret et le texte n'indique pas la valeur.

### 1.7 Valeur de la première vente

Formule de combo (`src/Server/ComboService.lua`, `Combo.Step = 4`, `Bonus = 0.5`, `Max = 6`) : le multiplicateur monte de 0,5 tous les 4 rebonds enchaînés.

Sur un sac de 25 avec une chaîne parfaite, la somme des multiplicateurs est **61** (moyenne **2,44**). Une chaîne cassée — cas normal d'un débutant — donne une moyenne réelle de **1,3 à 1,6**.

Valeur moyenne d'une bulle : 6570 / 1148 = **5,72** (4,16 en excluant la Legendary, qui n'apparaît que dans ~2 % des sacs de 25).

| Scénario | Première vente |
| --- | --- |
| Débutant, chaîne cassée, sans Golden (43 % des cas) | **≈ 90 – 140 pièces** |
| Débutant avec 1 Golden | **≈ 160 – 220 pièces** |
| Joueur qui enchaîne bien | **≈ 250 – 320 pièces** |

**Valeur de référence retenue : ≈ 150 pièces.**

### 1.8 Prix des premières améliorations

`GameConfig.Upgrades` L365-403. `UpgradeOrder = { "Speed", "Jump", "Power", "CoinMult" }` — `XPMult` (300) existe encore en config mais **n'est plus vendue** (absente de `UpgradeOrder`).

| Amélioration | Coût niveau 1 | PerLevel | Effet réel au niveau 1 |
| --- | --- | --- | --- |
| Speed | **750** | +1,0 WalkSpeed | 16 → 17 = **+6 %**, imperceptible |
| Jump | **1000** | +1,5 JumpPower | 35 → 36,5 = **+4 %**, imperceptible |
| Power | **3000** | +1 rayon | `r = math.floor(power / 2)` → **r = 0 → aucun effet** |
| CoinMult | **2500** | +0,05 | +5 %, invisible sur le moment |

Deux constats indépendants et importants :

1. **La moins chère (Speed, 750) demande 5 à 7 ventes**, soit **8 à 12 minutes** au rythme actuel. Très au-delà des 3 minutes cibles.
2. **`Power` niveau 1 ne fait littéralement rien** (`src/Server/BubbleService.lua` L767-773) : 3000 pièces pour zéro changement. C'est un bug d'équilibrage à part entière.

```767:773:src/Server/BubbleService.lua
	local power = Config.EffectiveUpgradeLevel("Power", profile.Upgrades.Power or 0)

	local cells: { { any } } = { { x, z, zoneId } }
	if power > 0 then
		local r = math.floor(power / 2)
		if r > 0 then
			cells = {}
```

### 1.9 Systèmes de notification / guidage déjà présents

| Système | Fichier | Réutilisable ? |
| --- | --- | --- |
| Toast `Announce` (auto-disparition ~4 s, non bloquant) | `Remotes` `Announce` + `src/Client/HUD.lua` | ✅ base du guidage textuel léger |
| Barre de sac + compteur, coloration rouge à saturation | `src/Client/HUD.lua` | ✅ |
| Compteur 3D sur le sac du personnage | `src/Server/BackpackVisual.lua` | ✅ |
| Burst + texte flottant au pop de spéciale | `src/Client/PopEffects.lua` | ✅ à enrichir |
| Camera shake sur Diamond/Legendary | `src/Client/JuiceController.lua` | ✅ |
| Attributs joueur répliqués (`Coins`, `CurrentBubbles`, `PlayerArea`, `HasWings`) | `DataService`, `ZoneService` | ✅ canal de guidage sans nouveau Remote |
| Modale « Bubble Transit » | `src/Client/TravelController.lua` | ⚠️ à neutraliser en première boucle |
| Panneaux statiques (HOW TO PLAY, SELL YOUR BUBBLES, gate Summer) | `ZoneService`, `ZoneBuilder` | ⚠️ passifs |

**Il n'existe aucune flèche, aucun beam, aucun waypoint, aucun highlight de guidage.** Rien qui pointe vers un objectif.

### 1.10 Visibilité de la Summer Zone

- Verrou : `ZoneDefs` `SummerZone.RequiredLevel = 5`, appliqué par collision group (`src/Server/ZoneAccess.lua`).
- Le panneau « UNLOCKS AT LEVEL 5 » (`L10n.SummerZoneUnlocksAt`) est sur le gate, **à l'extrémité est du plateau classique** (X ≈ +120).
- Depuis le `SpawnPad` `(0, 8, -164)`, le gate est à ~130 studs, hors de tout trajet naturel de première boucle.
- Le pad « Bubble Transit » du lobby liste bien Summer Zone avec « Requires Level 5 » (`TravelConfig`), mais via une **modale plein écran** — mauvais véhicule pour un nouveau joueur.
- Analytics existants déjà branchés : `SawSummerZoneRequirement`, `OpenedBubbleTransit`, `SelectedSummerZone`.

**En pratique, un nouveau joueur ne voit jamais la Summer Zone dans ses trois premières minutes.**

### 1.11 Instrumentation analytics existante

`src/Shared/AnalyticsConfig.lua` + `src/Server/GameAnalyticsService.lua`.

| Nom demandé | Nom réel en place | Type |
| --- | --- | --- |
| `JoinedGame` | `JoinedGame` | Funnel onboarding, étape 1 |
| `ReachedBubbleRoom` | `ReachedMainBubbleRoom` | étape 2 |
| `PoppedFirstBubble` | `PoppedFirstBubble` | étape 3 |
| `BackpackFull` | `BackpackFullFirstTime` | étape 4 |
| `ReturnedToLobby` | `ReturnedToLobbyAfterFullBackpack` | étape 5 |
| `SoldFirstBackpack` | `SoldFirstBackpack` | étape 6 |
| `BoughtFirstUpgrade` | `PurchasedFirstUpgrade` | étape 7 |
| `PoppedFirstSpecialBubble` | `FirstSpecialBubble` | Custom event (lifetime, one-shot) |
| `ReachedLevel2` | `PlayerLevelReached` (value = 2) + `LogProgressionCompleteEvent` `Level_2` | Custom + progression |

**Aucun renommage n'est nécessaire.** Les 9 événements demandés existent déjà tous.

Timings déjà collectés : `SecondsToFirstBubble`, `SecondsToBackpackFull`, `SecondsToFirstSale`, `SecondsToFirstUpgrade` (`AnalyticsConfig.FirstTimingByStep`). Budget custom events : **22 / 100 utilisés**.

Persistance : `profile.Analytics.OnboardingStarted`, `OnboardingCompleted`, `Onboarding[stepName]`, `Lifetime.FirstSpecialBubble` — tous déjà dans le `TEMPLATE` de `DataService` (L62-70) et réconciliés par `ensureAnalytics`.

### 1.12 Drapeaux de développement encore actifs

- `GameConfig.World.RebuildGeneratedLayout = true` (L97) — le commentaire du code dit lui-même « true une fois … puis false ».
- `BubbleValue.DEBUG_BUBBLE_VALUE = true` — log à chaque pop.

Sans lien direct avec l'onboarding, mais à corriger avant toute mesure de performance de la première session.

---

## 2. Problèmes observés (synthèse priorisée)

| # | Problème | Gravité | Impact D1 |
| --- | --- | --- | --- |
| P1 | Première bulle à **14–25 s** (minimum théorique 7,9 s) | **Bloquant** | Abandon avant le premier pop |
| P2 | Apparition parasite au centre du plateau puis téléport | **Élevée** | Désorientation immédiate |
| P3 | Joueur orienté dos à la salle de bulles | **Élevée** | +3 à 6 s perdues, sentiment d'être perdu |
| P4 | Modale Bubble Transit sur le trajet, plein écran, masque le joystick mobile | **Élevée** | Interruption du premier trajet |
| P5 | Aucun guidage directionnel quand le sac est plein | **Élevée** | Le joueur continue à popper sans effet |
| P6 | Première amélioration à 750 pièces ≈ 5–7 ventes ≈ 8–12 min | **Élevée** | Aucune récompense de progression dans les 3 min |
| P7 | Effet du premier niveau d'amélioration imperceptible (+6 % / +4 %) | **Élevée** | L'achat ne « paie » pas |
| P8 | Spéciales visuellement évidentes (Golden+) dans seulement 57 % des premiers sacs | Moyenne | Loop perçu comme uniforme |
| P9 | Récompense de vente peu spectaculaire (toast + compteur) | Moyenne | Le lien pop → vente → pièces reste flou |
| P10 | Summer Zone invisible en première session | Moyenne | Aucun objectif à moyen terme |
| P11 | `Power` niveau 1 = rayon 0, aucun effet pour 3000 pièces | Moyenne | Bug d'équilibrage |
| P12 | Panneau « HOW TO PLAY » de 5 lignes comme seul tutoriel | Faible | Ignoré par la majorité |

---

## 3. Expérience cible, minute par minute

### 0 – 10 s — « Je comprends et j'agis »
- Apparition **directement sur le `SpawnPad` de la salle**, face nord, plateau de bulles plein cadre.
- Aucun téléport visible, aucune modale, aucun panneau obligatoire.
- 38 studs jusqu'à la première rangée ≈ 2,4 s de marche.
- **Premier pop cible : 4 – 7 s.**

### 10 – 30 s — « C'est satisfaisant et varié »
- Rebonds enchaînés, burst + son + shake léger.
- Barre de sac HUD et compteur 3D qui montent visiblement.
- **Au moins une bulle spéciale nettement identifiable** rencontrée dans les 30 premiers pops (contre 57 % actuellement).
- Texte flottant indiquant la **valeur** gagnée, pas juste « +1 ».

### 30 – 90 s — « Mon sac est plein, je sais quoi faire »
- Sac plein (25 bulles) vers **35 – 50 s**.
- Déclenchement immédiat d'un **guidage visuel non bloquant** vers le kiosque : waypoint 3D « SELL » toujours visible + flèche d'écran quand la cible est hors champ.
- Le joueur garde 100 % du contrôle ; il peut ignorer le guidage.
- Retour lobby ≈ 10 – 15 s. Vente **automatique** à l'entrée de la zone (inchangé).
- **Récompense de vente très visible** : gerbe de pièces au pad, gros « +N COINS » flottant, son dédié, compteur HUD qui compte progressivement.
- Le guidage disparaît de lui-même dès la vente encaissée.
- **Première vente cible : 55 – 75 s.**

### 90 s – 3 min — « Je progresse et j'ai un objectif »
- Deuxième boucle plus rapide (le joueur connaît le trajet) : deuxième vente vers **110 – 140 s**.
- Dès que le solde atteint le prix de la première amélioration, guidage vers la boutique (même système de waypoint) et **ligne « RECOMMENDED » mise en avant dans `ShopUI`**.
- **Premier achat cible : 130 – 170 s**, avec un **effet immédiatement ressenti** (voir §6).
- Une **bannière teaser Summer Zone** visible depuis le plateau, lisible sans détour : « SUMMER ZONE — LEVEL 5 ». Objectif futur, pas de déviation de la boucle.

---

## 4. Parcours avant / après

### 4.1 Avant (mesuré)

| t | Événement |
| --- | --- |
| 0 s | Apparition au centre du plateau de bulles |
| 0,3 – 2 s | Téléport surprise vers le lobby, dos à la salle |
| 2 – 8 s | Recherche d'orientation, lecture éventuelle du panneau |
| 5 – 12 s | Pad Bubble Transit croisé → modale plein écran → fermeture |
| 12 – 22 s | Traversée allée, arche, escalier, pads |
| **14 – 25 s** | **Première bulle** |
| 60 – 90 s | Sac plein, toast texte, aucune direction |
| 75 – 120 s | Retour lobby par tâtonnement, vente automatique, toast |
| 120 s+ | Boucles suivantes |
| **8 – 12 min** | **Première amélioration** (Speed 750) |

### 4.2 Après (cible)

| t | Événement | Écart |
| --- | --- | --- |
| 0 s | Apparition sur `SpawnPad`, face au plateau | −1 téléport |
| 2,4 s | Bord de la grille | −120 studs |
| **4 – 7 s** | **Première bulle** | **−10 à −18 s** |
| 10 – 30 s | Rebonds, spéciale évidente rencontrée | +39 pts de fiabilité |
| 35 – 50 s | Sac plein → waypoint « SELL » | nouveau |
| 55 – 75 s | Vente automatique + gerbe de pièces | −20 à −45 s |
| 110 – 140 s | Deuxième vente → waypoint « SHOP » | nouveau |
| **130 – 170 s** | **Premier achat, effet ressenti** | **−6 à −10 min** |
| ≤ 180 s | Teaser Summer Zone vu | nouveau |

### 4.3 Ce qui change

**Supprimé**
- Le téléport lobby au spawn pour un joueur en première session (le joueur apparaît directement au bon endroit).
- L'ouverture automatique de la modale Bubble Transit tant que la première vente n'est pas faite.

**Déplacé**
- Le point d'apparition initial : lobby → `SpawnPad` de la salle (uniquement première session).
- Le message Summer Zone : du gate distant → bannière lisible depuis le plateau.

**Accéléré**
- Le coût de la première amélioration (§6).
- Le rythme de rencontre d'une spéciale lisible (§6).

**Ajouté**
- `OnboardingService` (serveur) + `OnboardingGuide` (client) : waypoints, flèche d'écran, contextuels.
- FX de vente (gerbe de pièces + « +N COINS »).
- Badge « RECOMMENDED » dans `ShopUI`.

---

## 5. Décisions de design

### D1 — Apparition directe dans la salle, première session uniquement

Le joueur en première session apparaît sur `GameRoomSpawn` (`ZoneService.TeleportToGameRoom`, fonction **déjà existante**, utilisée pour le FallReset). Ce n'est pas un téléport de gameplay supplémentaire : c'est le remplacement de l'unique téléport d'apparition déjà en place, donc la contrainte « pas de téléport inutile » est respectée — on en retire un, on n'en ajoute pas.

Le joueur découvre le lobby quand son sac se remplit, guidé (§D4). L'ordre d'apprentissage devient **action → conséquence** au lieu de **lecture → action**.

Les joueurs existants conservent strictement le comportement actuel (apparition lobby).

### D2 — Ajout d'un vrai `SpawnLocation`

Créer un `SpawnLocation` ancré, invisible, `Neutral = true`, `Duration = 0`, posé sur le `SpawnPad` avec un `CFrame.lookAt` vers le nord (+Z). Cela règle simultanément P2 (plus d'apparition parasite sur le plateau) et P3 (orientation correcte), et supprime la dépendance à la latence DataStore pour le positionnement initial.

Pour les joueurs existants, `ZoneService.onCharacterAdded` conserve son `TeleportToLobby`, mais il part désormais du `SpawnPad` au lieu du centre du plateau : leur flash d'apparition disparaît aussi.

### D3 — Détection « nouveau joueur » sans migration

Aucun nouveau champ persisté. On lit ce qui existe déjà :

```lua
-- Serveur, source unique de vérité
local a = profile.Analytics
local isVeteran   = a.OnboardingCompleted == true
local hasSold     = a.Onboarding.SoldFirstBackpack == true
local hasPopped   = a.Onboarding.PoppedFirstBubble == true
local onboarding  = a.OnboardingStarted == true and not isVeteran
```

Propriétés :
- `OnboardingStarted` n'est mis à `true` que si `DataService` a signalé `__isNewProfile == true` (`GameAnalyticsService.InitPlayer` L1288-1293).
- Les profils antérieurs au déploiement analytics ont `OnboardingStarted = false` → traités comme vétérans → **aucun guidage, aucun changement de spawn, aucun risque de régression**.
- `ensureAnalytics` remplit déjà les champs manquants à la volée : rien à migrer.
- `GameConfig.Data.StoreVersion = "v2"` (namespace récent) rend de toute façon la quasi-totalité de la base « nouvelle ».
- Le guidage est **repris de zéro à chaque session** tant que l'objectif n'est pas atteint (état en mémoire de session) : c'est le comportement souhaité, un joueur qui se déconnecte avec un sac plein doit revoir la flèche.

### D4 — Guidage contextuel : règles

1. **Un seul objectif actif à la fois**, calculé côté serveur, exposé via un attribut joueur `OnboardingObjective` (`""`, `"Pop"`, `"Sell"`, `"Shop"`).
2. Le client affiche pour cet objectif : un `BillboardGui` `AlwaysOnTop` au-dessus de la cible + une flèche d'écran (`ImageLabel` pivoté) quand la cible est hors champ.
3. **Rien ne capte l'input.** Pas de `ContextActionService`, pas de `Modal`, pas de gel de caméra.
4. **Disparition automatique** dès que l'objectif change côté serveur (sac vendu, achat fait).
5. **Aucun texte critique** : la flèche + l'icône (sac / pièce) portent le sens ; le mot anglais est un renfort, pas une dépendance.
6. **Pas de répétition** : un objectif déjà validé sur le profil ne réapparaît jamais.
7. **Zéro attente imposée** : un joueur qui connaît le chemin arrive avant la flèche et celle-ci s'éteint.

Transitions serveur :

| État profil | Objectif |
| --- | --- |
| `OnboardingCompleted == true` | `""` |
| `PoppedFirstBubble ~= true` | `"Pop"` |
| `CurrentBubbles >= Capacity` et `SoldFirstBackpack ~= true` | `"Sell"` |
| `SoldFirstBackpack == true`, aucun upgrade acheté, `Coins >= coût le moins cher` | `"Shop"` |
| sinon | `""` |

### D5 — Neutralisation de la modale Transit en première boucle

`TravelController` ne déclenche pas `openMenu` tant que `player:GetAttribute("OnboardingObjective")` vaut `"Pop"` ou `"Sell"`. Le pad reste physiquement présent et fonctionnel ; il redevient actif dès la première vente. Cela règle P4 sans supprimer la fonctionnalité ni toucher au serveur `TravelService`. **Décision approuvée** (§14, décision 4).

### D6 — Lisibilité des spéciales, sans système parallèle

Deux leviers purement visuels, pas de tirage par joueur :

- `Rare` : couleur nettement plus saturée (bleu profond) + `MeshScale` × 1,08.
- `Golden` et au-dessus : `Material = Neon` + `PointLight` léger. À 3,31 % de 1600 cellules, cela représente ~53 instances, budget acceptable (à comparer aux 1600 `Highlight` explicitement refusés en L273-274 de `GameConfig`).
- `PopEffects` : le texte flottant affiche la **valeur de vente** obtenue (`+45`) plutôt qu'un marqueur générique.

### D7 — Récompense de vente spectaculaire

Nouvel event Remote `SellResult` (serveur → client, `{ sold: number, earned: number }`), déclenché par `BackpackService.Sell`. Le client joue, au niveau du `SellPad` : gerbe de particules dorées, texte 3D « +N COINS », son, et compteur HUD animé de l'ancien au nouveau solde.

Un event dédié plutôt qu'un parsing du toast `Announce` : pas d'analyse de chaîne, compatible localisation.

### D8 — Recommandation de la première amélioration

`ShopService.GetShopData` ajoute `Recommended = true` sur la ligne d'upgrade la moins chère **si et seulement si** `Analytics.OnboardingCompleted ~= true` et aucun upgrade acheté. `ShopUI` affiche un badge « RECOMMENDED ». Aucune nouvelle structure : un champ booléen dans une réponse existante.

### D9 — Teaser Summer Zone

Bannière verticale haute posée **au-dessus du gate est**, dimensionnée pour être lisible depuis le centre du plateau (texte « SUMMER ZONE » + « LEVEL 5 » + icône cadenas), construite par `ZoneBuilder` avec le marqueur `GeneratedByCode` habituel et positionnée à partir de `ZoneDefs` (aucune coordonnée absolue). Aucune interaction, aucun prompt : pur décor informatif.

L'event `SawSummerZoneRequirement` reste déclenché par les triggers existants (`ZoneAccess.NotifyBlocked`, liste Transit). On n'en ajoute pas pour la bannière : la mesure utile est le passage effectif au gate.

---

## 6. Ajustements économiques minimaux

Trois seuls changements, tous ciblés, aucun rééquilibrage global.

### A6.1 — Coût du premier niveau d'amélioration

Ajouter un champ optionnel `FirstLevelCost` et le respecter dans `GameConfig.UpgradeCost` :

```lua
function GameConfig.UpgradeCost(id: string, currentLevel: number): number
	local def = GameConfig.Upgrades[id]
	if not def then return math.huge end
	if currentLevel <= 0 and def.FirstLevelCost then
		return def.FirstLevelCost
	end
	return math.floor(def.BaseCost * (def.Growth ^ currentLevel))
end
```

Avec `Speed.FirstLevelCost = 250` :

| Niveau | Actuel | Proposé |
| --- | --- | --- |
| 1 | 750 | **250** |
| 2 | 1087 | 1087 |
| 3+ | inchangé | inchangé |

Deux ventes (≈ 300 pièces) suffisent. **La courbe au-delà du niveau 1 est strictement inchangée** : aucun impact sur l'économie mid/late, aucun impact sur les joueurs existants ayant déjà Speed ≥ 1. Tous les chemins de prix passent déjà par `UpgradeCost` (`ShopService`, `ShopUI`), un seul point de modification.

Le SKU analytics `Speed` est inchangé (`AnalyticsConfig.BuildEconomySkuSet`).

### A6.2 — Rendre le premier niveau perceptible

`Speed.PerLevel : 1.0 → 2.0`. WalkSpeed 16 → **18** au niveau 1 (+12,5 %, sensible), maximum 16 + 15 × 2 = **46**, sous `MaxWalkSpeed = 80`, clamp déjà appliqué par `DataService.ApplyCharacterStats`.

Impact sur les joueurs existants : leur vitesse augmente rétroactivement (un joueur Speed 5 passe de 21 à 26). C'est un **buff**, jamais une perte, et il reste sous le plafond. **Décision approuvée** (§14, décision 3) : le buff rétroactif est accepté.

### A6.3 — Corriger `Power` niveau 1

`math.floor(power / 2)` → `math.ceil(power / 2)` dans `BubbleService`, ou table de rayons explicite. Le niveau 1 donne alors un rayon 1 (pop 3×3). **Ne fait pas partie du chemin d'onboarding** (Power reste à 3000) mais élimine un achat inerte. **Décision approuvée** (§14, décision 5).

### A6.4 — Ce qui n'est PAS touché

Valeurs de vente des bulles, poids de rareté, capacité de sac, courbe de combo, `BubblesForLevel`, prix des sacs boutique, `CoinMult`, `Jump`, coûts `Power`/`CoinMult`. Aucune injection de pièces, aucun cadeau de bienvenue.

### A6.5 — Chronologie résultante

| Étape | Cumul |
| --- | --- |
| Premier pop | 4 – 7 s |
| Sac plein (25 pops) | 35 – 50 s |
| Retour + vente 1 (≈ 150 pièces) | 55 – 75 s |
| Boucle 2 + vente 2 (≈ 300 cumulé) | 110 – 140 s |
| Achat Speed 1 à 250 | **130 – 170 s** ✅ |
| WalkSpeed 16 → 18 ressenti immédiatement | — |

---

## 7. Architecture proposée

```
Shared/
  OnboardingConfig.lua      [NOUVEAU]  Objectifs, textes EN, distances, seuils
Server/
  OnboardingService.lua     [NOUVEAU]  État autoritatif → attribut OnboardingObjective
Client/
  OnboardingGuide.lua       [NOUVEAU]  Waypoint 3D + flèche d'écran, lit l'attribut
  SellFeedback.lua          [NOUVEAU]  FX de vente (ou intégré à PopEffects)
```

Canal de communication : **attribut joueur `OnboardingObjective`** (string). C'est exactement le mécanisme déjà utilisé pour `Coins`, `CurrentBubbles`, `PlayerArea`, `HasWings` — donc « réutiliser les systèmes existants » plutôt qu'un nouveau protocole. Réplication automatique, pas de nouveau Remote, pas de désynchronisation possible.

Un seul Remote ajouté : `SellResult` (pour les FX de vente, qui portent des valeurs numériques ponctuelles inadaptées à un attribut).

`OnboardingService` recalcule l'objectif sur quatre déclencheurs déjà existants : chargement du profil, changement de `CurrentBubbles`, vente encaissée, achat d'upgrade. Pas de boucle de polling.

Aucun `Highlight` sur les bulles. Les cibles de waypoint sont résolues par nom depuis les dossiers générés (`Lobby/SellPad`, `Lobby/ItemShop`) avec repli sur `GameConfig.Lobby.SellPosition` / `ItemShopPosition` — pas de coordonnées en dur.

---

## 8. Liste précise des fichiers concernés

### Nouveaux
| Fichier | Rôle |
| --- | --- |
| `src/Shared/OnboardingConfig.lua` | Constantes, textes anglais, seuils |
| `src/Shared/OnboardingStateTests.lua` | Tests purs de la machine à états |
| `src/Server/OnboardingService.lua` | Calcul et publication de l'objectif |
| `src/Client/OnboardingGuide.lua` | Rendu waypoint + flèche |
| `src/Client/SellFeedback.lua` | FX de vente |

### Modifiés
| Fichier | Modification |
| --- | --- |
| `src/Server/ZoneService.lua` | `SpawnLocation` sur le `SpawnPad` ; branchement première session sur `TeleportToGameRoom` |
| `src/Server/ZoneBuilder.lua` | Bannière teaser Summer Zone |
| `src/Server/init.server.lua` | Démarrage `OnboardingService` |
| `src/Server/BackpackService.lua` | Émission `SellResult` ; notification `OnboardingService` |
| `src/Server/ShopService.lua` | Champ `Recommended` dans `GetShopData` |
| `src/Server/BubbleService.lua` | (A6.3 optionnel) `math.ceil` pour le rayon Power |
| `src/Client/init.client.lua` | Démarrage des deux nouveaux modules client |
| `src/Client/TravelController.lua` | Suppression de l'auto-ouverture pendant l'onboarding |
| `src/Client/ShopUI.lua` | Badge « RECOMMENDED » |
| `src/Client/PopEffects.lua` | Texte flottant = valeur ; renfort visuel des spéciales |
| `src/Shared/Remotes.lua` | Ajout de `SellResult` |
| `src/Shared/GameConfig.lua` | `FirstLevelCost`, `Speed.PerLevel`, `RebuildGeneratedLayout = false` |
| `src/Shared/BubbleTypes.lua` | Couleur `Rare`, flags visuels Golden+ |
| `src/Shared/LocalizationStrings.lua` | Nouvelles chaînes anglaises |
| `src/Shared/AnalyticsConfig.lua` | 3 nouveaux custom events |
| `src/Shared/BubbleValue.lua` | `DEBUG_BUBBLE_VALUE = false` |
| `default.project.json` | Aucune modification attendue |

---

## 9. Stratégie analytics

### 9.1 Aucun renommage

Les 9 événements demandés existent tous (§1.11). Le mapping documenté est la référence pour la lecture des dashboards.

### 9.2 Mesure de chaque changement

| Changement | Métrique de validation | Cible |
| --- | --- | --- |
| Spawn dans la salle (D1/D2) | `SecondsToFirstBubble` (p50) | 22 s → **< 8 s** |
| Spawn dans la salle | Taux `PoppedFirstBubble` / `JoinedGame` | **+15 pts** |
| Nouveau : temps d'arrivée salle | `SecondsToBubbleRoom` **[nouveau]** | p50 < 3 s |
| Lisibilité spéciales (D6) | `FirstSpecialBubble` par session initiale | **> 90 %** |
| Guidage vente (D4) | `SecondsToFirstSale` (p50) | 150 s → **< 80 s** |
| Guidage vente | `ReturnedToLobbyAfterFullBackpack` / `BackpackFullFirstTime` | **> 85 %** |
| Efficacité du waypoint | `OnboardingGuideSellShown` **[nouveau]** vs `SoldFirstBackpack` | conversion > 80 % |
| FX de vente (D7) | Sacs 2 / sacs 1 (`SessionSalesCount`) | **> 70 %** |
| Coût 250 + recommandation (A6.1/D8) | `SecondsToFirstUpgrade` (p50) | 600 s → **< 180 s** |
| Recommandation | `OnboardingGuideShopShown` **[nouveau]** vs `PurchasedFirstUpgrade` | conversion > 60 % |
| Teaser Summer (D9) | `SawSummerZoneRequirement` en session initiale | en hausse |
| Rétention globale | `FirstSessionDuration`, `PlayerLevelReached` = 2 | en hausse |

### 9.3 Ajouts

Trois entrées dans `AnalyticsConfig.CustomEvents` (22 → 25, plafond 100) :
- `SecondsToBubbleRoom` — plus une entrée `FirstTimingByStep.ReachedMainBubbleRoom = "SecondsToBubbleRoom"`.
- `OnboardingGuideSellShown`
- `OnboardingGuideShopShown`

Les deux « GuideShown » sont émis **une seule fois par profil**, gardés par `Analytics.Lifetime` comme `FirstSpecialBubble` (`GameAnalyticsService` L800-807) — même patron, pas de nouveau mécanisme.

### 9.4 Garanties d'unicité

Le mécanisme `drainOnboarding` (`GameAnalyticsService` L487-530) impose déjà : progression séquentielle stricte, marquage seulement après succès du sink, arrêt en cas d'échec, reprise à la session suivante. Ne rien y toucher. Toutes les nouvelles notifications passent par `ObserveOnboarding` / `_logCustom`, jamais par `AnalyticsService` directement.

`OnboardingVersion` reste à 1 : la sémantique des étapes ne change pas, seul le temps pour les atteindre change. **Ne pas incrémenter**, sinon les funnels des joueurs en cours se réinitialisent.

---

## 10. Compatibilité avec les sauvegardes

- **Zéro nouveau champ persisté.** Tout l'état d'onboarding lit `profile.Analytics.*`, déjà présent dans le `TEMPLATE` (`DataService` L62-70).
- **Zéro migration.** `ensureAnalytics` (`GameAnalyticsService` L104-130) complète déjà les profils incomplets à chaque chargement.
- **`StoreVersion` inchangé** (`"v2"`). Le faire évoluer effacerait tout le monde.
- **Joueurs existants** : `OnboardingStarted == false` ou `OnboardingCompleted == true` → spawn lobby actuel, aucun waypoint, aucun badge. Comportement bit-à-bit identique à aujourd'hui.
- **Achats déjà faits** : `FirstLevelCost` ne s'applique qu'à `currentLevel <= 0`. Un joueur ayant Speed ≥ 1 voit exactement les mêmes prix.
- **Seul effet rétroactif** : `Speed.PerLevel = 2.0` augmente la vitesse des possesseurs de Speed (buff, clampé). Décision à valider.
- **Rollback** : chaque phase est indépendante. Revenir en arrière ne laisse aucun champ orphelin en base.

---

## 11. Phases d'implémentation

Chaque phase est livrable, testable et réversible seule.

---

### Phase 1 — Première bulle en moins de 10 secondes

**Fichiers** : `src/Server/ZoneService.lua`, `src/Shared/OnboardingConfig.lua` (nouveau), `src/Server/OnboardingService.lua` (nouveau, socle), `src/Server/init.server.lua`

**Comportement attendu**
- `SpawnLocation` ancré, invisible, `Neutral`, `Duration = 0`, sur le `SpawnPad`, orienté vers +Z.
- Première session (`OnboardingStarted == true` et `PoppedFirstBubble ~= true`) → aucun téléport, le joueur reste sur le pad.
- Toute autre situation → `TeleportToLobby` comme aujourd'hui.
- `ReachedMainBubbleRoom` déclenché dès la détection de `PlayerArea == "GameRoom"`.

**Risques de régression**
- Un `SpawnLocation` mal configuré peut supplanter tous les respawns, y compris pour les vétérans → forcer `Duration = 0`, `Neutral = true`, et laisser `TeleportToLobby` s'exécuter pour eux.
- `AreaSplitZ = -198` : le `SpawnPad` (Z = -164) est bien côté `GameRoom`, à revérifier après ajout.
- `RebuildGeneratedLayout` doit être vrai une fois pour créer la nouvelle pièce, puis remis à `false`.
- Interaction avec `FallResetDestination = "GameRoom"` : à retester.

**Tests automatisés**
- `OnboardingStateTests` : la résolution du spawn renvoie `GameRoom` pour un profil neuf, `Lobby` pour `OnboardingCompleted`, `Lobby` pour `OnboardingStarted == false`.
- Test géométrique : distance `SpawnPad` → première rangée ≤ 60 studs ; le `SpawnLocation` n'intersecte aucune bulle (réutiliser les assertions `assertOutsideGrid` de `GameConfig`).

**Tests Studio manuels**
- Profil neuf (`DataService` wipe) : apparition sur le pad, face aux bulles, aucun flash au centre du plateau, chronométrer le premier pop.
- Profil vétéran simulé (`OnboardingCompleted = true`) : apparition lobby inchangée.
- Mort / FallReset : destination correcte.
- Rejoindre à 2 joueurs simultanément.

**Critères d'acceptation**
- Premier pop < 10 s, mesuré 5 fois de suite sur profil neuf.
- Zéro apparition visible au centre du plateau.
- Aucun changement observable pour un profil vétéran.
- `ReachedMainBubbleRoom` et `PoppedFirstBubble` logués une seule fois.

---

### Phase 2 — Lisibilité des bulles spéciales

**Fichiers** : `src/Shared/BubbleTypes.lua`, `src/Server/BubbleService.lua` (application visuelle), `src/Client/PopEffects.lua`

**Comportement attendu**
- `Rare` visuellement distinct du Normal (couleur + échelle).
- Golden+ en `Neon` avec halo léger.
- Texte flottant = valeur de vente obtenue.

**Risques de régression**
- Coût de rendu : ~53 `PointLight` sur 1600 bulles. Vérifier au profiler ; si dégradation, se limiter au `Neon`.
- `ZoneBubblePalettes` ne teinte que les Normal : les spéciales ne doivent pas être écrasées par la palette Summer.
- La régénération (30 s) doit réappliquer correctement l'apparence.

**Tests automatisés**
- Test de contraste : distance RGB entre `Rare` et chaque `TintVariants` au-dessus d'un seuil.
- Test existant de palette de zone : toujours vert.

**Tests Studio manuels**
- Parcourir le plateau : repérer une spéciale sans effort en < 30 pops.
- Vérifier en Summer Zone que la teinte orange des Normal n'affecte pas les spéciales.
- Contrôler les FPS mobile (émulateur) avant/après.

**Critères d'acceptation**
- Une spéciale est identifiable à 40 studs sans zoom.
- `FirstSpecialBubble` continue d'être logué une seule fois par profil.
- Aucune perte de FPS mesurable en émulation mobile.

---

### Phase 3 — Guidage vers la vente

**Fichiers** : `src/Server/OnboardingService.lua`, `src/Client/OnboardingGuide.lua` (nouveau), `src/Client/init.client.lua`, `src/Server/BackpackService.lua`, `src/Shared/LocalizationStrings.lua`

**Comportement attendu**
- Sac plein + première vente non faite → `OnboardingObjective = "Sell"`.
- Waypoint 3D « SELL » au-dessus du `SellPad` + flèche d'écran hors champ.
- Extinction immédiate à la vente.
- Aucune capture d'input.

**Risques de régression**
- Fuite d'instances si le personnage meurt ou si le joueur part : nettoyage sur `CharacterRemoving` et `PlayerRemoving`.
- Le waypoint ne doit pas masquer le HUD (`ZIndex`, `DisplayOrder`).
- `StreamingEnabled = true` : la cible peut ne pas être streamée depuis la salle → utiliser une position issue de `GameConfig`, pas l'instance.
- Ne pas déclencher pour les vétérans.

**Tests automatisés**
- `OnboardingStateTests` : table de vérité complète de la machine à états (sac plein / vide × vendu / non vendu × vétéran / neuf).
- Test d'idempotence : deux appels consécutifs ne produisent qu'une transition.

**Tests Studio manuels**
- Remplir le sac, vérifier l'apparition de la flèche, la suivre, constater l'extinction à la vente.
- Ignorer la flèche et continuer à popper : le personnage reste pleinement contrôlable.
- Se déconnecter sac plein, revenir : la flèche revient.
- PC, tactile, manette.

**Critères d'acceptation**
- La flèche apparaît en < 0,5 s après saturation du sac.
- Elle disparaît en < 0,5 s après la vente.
- Zéro flèche pour un vétéran.
- Aucun blocage de mouvement, de saut ou de pop.
- `BackpackFullFirstTime` et `ReturnedToLobbyAfterFullBackpack` logués une fois.

---

### Phase 4 — Récompense de vente lisible

**Fichiers** : `src/Shared/Remotes.lua`, `src/Server/BackpackService.lua`, `src/Client/SellFeedback.lua` (nouveau), `src/Client/HUD.lua`, `src/Client/init.client.lua`

**Comportement attendu**
- `SellResult` émis à chaque vente réussie.
- Gerbe de pièces + « +N COINS » au `SellPad` + son.
- Compteur HUD animé de l'ancien au nouveau solde.
- La vente reste **automatique** : aucun changement de la condition de déclenchement ni du montant.

**Risques de régression**
- Ventes rapides successives : limiter le nombre de FX simultanés.
- Le compteur animé ne doit jamais afficher une valeur fausse en fin d'animation (toujours converger sur l'attribut `Coins`).
- Ne pas rendre le nouveau Remote obligatoire côté serveur (un client ancien ne doit pas casser).

**Tests automatisés**
- Tests existants de `BackpackService.Sell` (montant, remise à zéro, économie) : inchangés et verts.
- Test : le payload `SellResult` correspond exactement aux valeurs créditées.

**Tests Studio manuels**
- Vendre un petit sac et un gros sac : FX proportionné, lisible.
- Vendre 3 fois en 5 s : pas d'accumulation d'instances.
- Vérifier que le solde final est exact.

**Critères d'acceptation**
- Les pièces ne sont créditées qu'à la vente (invariant préservé).
- Le montant affiché est identique au montant crédité.
- `SoldFirstBackpack` et l'économie (`LogBackpackSaleEconomy`) inchangés, logués une fois.

---

### Phase 5 — Guidage vers la première amélioration

**Fichiers** : `src/Shared/GameConfig.lua`, `src/Server/ShopService.lua`, `src/Server/OnboardingService.lua`, `src/Client/ShopUI.lua`, `src/Client/OnboardingGuide.lua`, `src/Client/TravelController.lua`

**Comportement attendu**
- `Speed.FirstLevelCost = 250`, `Speed.PerLevel = 2.0`.
- Après la première vente, si le solde couvre le coût → `OnboardingObjective = "Shop"`, waypoint vers l'`ItemShop`.
- `ShopUI` affiche « RECOMMENDED » sur la ligne Speed.
- Le pad Transit n'ouvre plus automatiquement sa modale pendant `"Pop"` / `"Sell"`.
- Après achat : objectif vidé, effet de vitesse immédiat.

**Risques de régression**
- **`UpgradeCost` est le point de passage unique des prix** : vérifier `ShopService`, `ShopUI`, et tous les tests d'économie.
- Le buff rétroactif de `Speed.PerLevel` touche les joueurs existants → clamp `MaxWalkSpeed` déjà en place, mais à retester avec Speed 15.
- La suppression de l'auto-ouverture Transit ne doit pas rendre le pad inutilisable après la première vente.
- Les SKU analytics restent `Speed` (inchangé).

**Tests automatisés**
- `UpgradeCost("Speed", 0) == 250` ; `UpgradeCost("Speed", 1) == 1087` ; toutes les autres améliorations inchangées.
- `ApplyCharacterStats` : Speed 15 → WalkSpeed 46, sous `MaxWalkSpeed`.
- `GetShopData` : `Recommended` présent uniquement pour un profil non complété sans upgrade.
- `OnboardingStateTests` : transition vers `"Shop"` uniquement quand `Coins >= coût`.

**Tests Studio manuels**
- Parcours complet profil neuf : chronométrer jusqu'à l'achat.
- Ressentir la différence de vitesse avant/après.
- Vétéran avec Speed 3 : prix inchangé, vitesse ajustée sans erreur.
- Marcher sur le pad Transit avant et après la première vente.
- ShopUI en portrait mobile : le badge ne casse pas la mise en page.

**Critères d'acceptation**
- Premier achat réalisable avec les gains de la vente 1 ou 2.
- Différence de vitesse perçue à l'aveugle par un testeur.
- Aucun prix modifié au-delà du niveau 1 de Speed.
- `PurchasedFirstUpgrade` logué une fois, `OnboardingCompleted` passe à `true`.

---

### Phase 6 — Teaser Summer Zone

**Fichiers** : `src/Server/ZoneBuilder.lua`, `src/Shared/LocalizationStrings.lua`, `src/Shared/ZoneDefs.lua` (lecture seule)

**Comportement attendu**
- Bannière haute au-dessus du gate est, lisible depuis le plateau : « SUMMER ZONE » / « LEVEL 5 » / cadenas.
- Marquée `GeneratedByCode`, positionnée depuis `ZoneDefs`, sans coordonnée absolue.
- Aucun prompt, aucune interaction.

**Risques de régression**
- Ne pas obstruer le passage ni intersecter des cellules (`assertOutsideGrid`).
- Nécessite `RebuildGeneratedLayout = true` une fois, puis `false`.
- Ne pas dupliquer le panneau existant du gate.

**Tests automatisés**
- Test de bornes : la bannière ne recouvre aucune cellule de la grille classique.
- Tests `ZoneDefs` existants toujours verts.

**Tests Studio manuels**
- Lisible depuis le centre du plateau et depuis le `SpawnPad`.
- Traverser le gate au niveau 5 : le message de blocage disparaît correctement.
- Vérifier qu'aucun doublon n'apparaît après un second rebuild.

**Critères d'acceptation**
- Bannière visible en première session sans quitter le trajet de la boucle.
- Verrou niveau 5 strictement inchangé.
- `SawSummerZoneRequirement` toujours logué une fois.

---

### Phase 7 — Analytics et multiplateformes

**Fichiers** : `src/Shared/AnalyticsConfig.lua`, `src/Server/GameAnalyticsService.lua`, suites de tests analytics, `src/Shared/BubbleValue.lua`, `src/Shared/GameConfig.lua`

**Comportement attendu**
- Ajout de `SecondsToBubbleRoom`, `OnboardingGuideSellShown`, `OnboardingGuideShopShown`.
- `FirstTimingByStep.ReachedMainBubbleRoom = "SecondsToBubbleRoom"`.
- `DEBUG_BUBBLE_VALUE = false`, `RebuildGeneratedLayout = false`.
- Passage complet PC / tactile / manette.

**Risques de régression**
- Ne pas dépasser 100 custom events (25 après ajout).
- Ne pas incrémenter `OnboardingAnalyticsVersion`.
- `drainOnboarding` : la séquentialité stricte doit rester intacte.

**Tests automatisés**
- Suites analytics existantes (`src/Server/*AnalyticsTests*`) : vertes.
- Nouveaux tests : chaque nouvel event est dans l'allowlist et n'est émis qu'une fois par profil.
- `rojo build` réussi.

**Tests Studio manuels**
- Parcours complet clavier/souris, puis émulation tactile, puis manette (`ButtonX` sur les prompts, navigation `ShopUI`).
- Vérifier les logs `[GameAnalytics]` en Studio : chaque étape apparaît une fois, dans l'ordre.
- Reconnexion en cours d'onboarding : pas de double log.

**Critères d'acceptation**
- Les 9 événements demandés apparaissent une fois, au bon moment, dans le bon ordre.
- Parcours complet réalisable sur les trois plateformes.
- Tous les tests existants verts, `rojo build` réussi.

---

## 12. Critères d'acceptation globaux

| # | Critère | Vérification |
| --- | --- | --- |
| 1 | Première bulle en < 10 s | Chrono Studio × 5 + `SecondsToFirstBubble` p50 |
| 2 | Aucun écran obligatoire ne bloque déplacement ou pop | Revue manuelle des 3 plateformes |
| 3 | Spéciale rencontrée rapidement | `FirstSpecialBubble` > 90 % des sessions initiales |
| 4 | Sac initial rempli en durée adaptée | 25 pops en 30–50 s, chrono |
| 5 | Guidage clair quand le sac est plein | Waypoint + flèche visibles < 0,5 s |
| 6 | Vente toujours automatique | Tests `BackpackService` inchangés |
| 7 | Pièces uniquement à la vente | Revue de code + tests économie |
| 8 | Première amélioration compréhensible et rapide | Badge visible, achat < 180 s |
| 9 | Guidage ignorable | Contrôle personnage total pendant l'affichage |
| 10 | Pas de répétition pour un joueur existant | Test profil `OnboardingCompleted = true` |
| 11 | Clavier / tactile / manette | Parcours complet × 3 |
| 12 | Analytics une seule fois, au bon moment | Logs Studio + tests unitaires |
| 13 | Tests existants verts | Suites serveur et partagées |
| 14 | `rojo build` réussi | CI / commande locale |

---

## 13. Risques et solutions

| Risque | Probabilité | Impact | Mitigation |
| --- | --- | --- | --- |
| Le `SpawnLocation` capture aussi les respawns des vétérans | Moyenne | Élevé | `Duration = 0`, `Neutral = true` ; `TeleportToLobby` conservé pour eux ; test explicite profil vétéran |
| Le nouveau spawn casse le FallReset | Faible | Moyen | `FallResetDestination` déjà `"GameRoom"` ; test de chute depuis les deux zones |
| Le joueur ne trouve jamais le lobby sans le guidage | Moyenne | Élevé | Phase 3 est un prérequis du déploiement de la Phase 1 en production ; l'arche « ← Lobby » existe déjà au sud du `SpawnPad` |
| Buff rétroactif de vitesse mal reçu | Moyenne | Moyen | Décision explicite du propriétaire ; repli sur l'option FX de la §A6.2 |
| `FirstLevelCost` déséquilibre l'économie | Faible | Moyen | Une seule injection de −500 pièces par joueur, une fois dans sa vie ; courbe ≥ 2 inchangée |
| Coût de rendu des halos Golden+ | Faible | Moyen | ~53 instances ; repli `Neon` seul si le profiler le demande |
| Fuite d'instances du waypoint | Moyenne | Faible | Nettoyage sur `CharacterRemoving` / `PlayerRemoving` ; test d'instances en Studio |
| `StreamingEnabled` empêche de résoudre la cible | Moyenne | Moyen | Positions issues de `GameConfig`, jamais des instances |
| Double log analytics après reconnexion | Faible | Moyen | `drainOnboarding` gère déjà l'idempotence ; ne pas y toucher ; test de reconnexion |
| Régression sur la modale Transit | Faible | Faible | Suppression de l'auto-ouverture uniquement pendant `"Pop"` / `"Sell"` ; test avant/après première vente |
| `RebuildGeneratedLayout` oublié à `true` | Moyenne | Faible | Point de contrôle explicite en fin de Phase 7 |

---

## 14. Décisions validées (2026-08-01)

Les cinq décisions ouvertes ont été soumises au propriétaire du jeu et **toutes approuvées**. Elles sont désormais des prérequis fermes du plan d'implémentation.

| # | Décision | Statut | Phase |
| --- | --- | --- | --- |
| 1 | Apparition en première session sur le `SpawnPad` de la salle plutôt que dans le lobby. Seul moyen d'atteindre « première bulle < 10 s » : la distance actuelle impose un plancher de 7,9 s en course parfaite. Contrepartie assumée : le lobby, le kiosque et la boutique sont découverts plus tard, via le guidage de la Phase 3. | ✅ **Approuvé** | 1 |
| 2 | `Speed.FirstLevelCost = 250` (750 aujourd'hui), courbe strictement inchangée à partir du niveau 2. | ✅ **Approuvé** | 5 |
| 3 | `Speed.PerLevel : 1.0 → 2.0` (WalkSpeed 16 → 18 au niveau 1), buff rétroactif sur les joueurs possédant déjà Speed, clampé par `MaxWalkSpeed = 80`. | ✅ **Approuvé** | 5 |
| 4 | Neutralisation de l'ouverture automatique de la modale Bubble Transit tant que la première vente n'est pas faite. | ✅ **Approuvé** | 5 |
| 5 | Correction de `Power` niveau 1 : `math.floor(power / 2)` → `math.ceil(power / 2)`, rayon 0 → 1. | ✅ **Approuvé** | 5 (ou lot séparé) |

Conséquences directes sur la spec :

- L'option de repli de la §A6.2 (garder `PerLevel = 1.0` et compenser par des effets visuels) est **abandonnée**.
- L'alternative de la §D5 (déplacer le pad Transit hors de l'axe central) est **abandonnée**.
- L'ajustement A6.3 (`Power`) n'est plus optionnel et entre dans le périmètre.
- Aucune décision ne reste bloquante : le plan d'implémentation peut être rédigé sur la base des 7 phases de la §11.

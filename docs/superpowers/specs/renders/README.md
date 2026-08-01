# Captures de validation — hub central Concept 2

Dossier de référence artistique du hub central. Plan associé :
`docs/superpowers/plans/2026-08-01-central-hub-concept2-asset-pack.md` (Phase 0).

## Contenu attendu

| Fichier | Nature | État |
|---|---|---|
| `2026-08-01-concept2-reference.png` | maquette approuvée « Concept 2 — Équilibré » | **manquant — à copier par l'utilisateur** |
| `2026-08-01-prototype-reference.png` | prototype, caméra de référence frontale | à capturer dans Studio |
| `2026-08-01-prototype-spawn.png` | prototype, vue joueur au spawn | à capturer dans Studio |
| `2026-08-01-prototype-from-bubbles.png` | prototype, vue depuis les bulles | à capturer dans Studio |
| `2026-08-01-prototype-back.png` | prototype, vue arrière | à capturer dans Studio |
| `2026-08-01-prototype-top.png` | prototype, vue de dessus | à capturer dans Studio |
| `2026-08-01-prototype-side.png` | prototype, vue latérale | à capturer dans Studio |
| `2026-08-01-prototype-mobile.png` | prototype, cadrage mobile | à capturer dans Studio |
| `anchors.txt` | inventaire des ancres relevé depuis le code | **présent** |

Aucun fichier fictif ni substitut n'est créé : ces captures ne peuvent pas être produites
sans piloter Roblox Studio, ce qui n'est pas automatisable ici.

## Maquette de référence

L'image exacte `Concept 2 — Équilibré` approuvée n'est pas présente dans le dépôt et
n'a pas été retrouvée sur un chemin local identifiable de façon fiable. Elle doit être
copiée manuellement, sans redimensionnement ni recompression, sous :

```text
docs/superpowers/specs/renders/2026-08-01-concept2-reference.png
```

Tant que ce fichier et les 7 captures du prototype sont absents, le commit final de la
Phase 0 n'est pas créé.

## Procédure Studio (une seule fois par lot de captures)

Le hub central n'est construit qu'au lancement du serveur : les captures se prennent donc
**pendant un test `F5`**, pas en mode Edit. Les repères sont créés en Edit et restent
présents pendant le test.

1. Lancer `rojo serve` puis `Connect` dans Studio.
2. Installer le plugin : copier `studio-plugins/HubValidationCameras.plugin.lua` dans
   `%LOCALAPPDATA%\Roblox\Plugins\HubValidationCameras.lua`, puis redémarrer Studio.
3. **En mode Edit**, onglet `Plugins` → barre `BPW Hub Cameras` →
   **Create/Refresh Hub Validation Cameras**. Les 7 repères apparaissent sous
   `Workspace.StudioDecoration.CentralHubVisual.ValidationCameras`.
4. Lancer un test avec `F5` et attendre que `Workspace.BubblePopWorld.CentralHub` existe.
5. Pour chaque vue : sélectionner le repère dans l'Explorer, cliquer
   **Go To Selected Validation View**, puis capturer. Le premier clic mémorise l'état de la
   caméra du joueur et bascule la caméra en `Scriptable` pour que le cadrage tienne ;
   les vues suivantes ne réécrivent pas cet état mémorisé.
6. Régler la fenêtre de rendu au bon rapport avant capture (`View → Screenshot` conserve
   le rapport de la fenêtre 3D) et enregistrer sous le nom exact indiqué ci-dessous.
7. Masquer les aides d'affichage avant capture : sélection, `Show Welds`,
   `Constraint Details`, et désélectionner le repère après le déplacement de caméra.
8. Les 7 captures faites, cliquer **Restore Test Camera** pour rendre la caméra au joueur
   (`CameraType`, `CameraSubject`, `CFrame`, `Focus`, `FieldOfView`), puis arrêter le test.
9. **En mode Edit**, cliquer **Remove Validation Cameras** avant toute publication du lieu.

## Correspondance repère → capture

| Repère à sélectionner | Fichier de sortie | Rapport | Résolution | FOV |
|---|---|---|---|---|
| `CentralHubConcept2ReferenceCamera` | `2026-08-01-prototype-reference.png` | 16:9 | 1920 × 1080 | 36 |
| `ValidationCam_Spawn` | `2026-08-01-prototype-spawn.png` | 16:9 | 1920 × 1080 | 70 |
| `ValidationCam_FromBubbles` | `2026-08-01-prototype-from-bubbles.png` | 16:9 | 1920 × 1080 | 55 |
| `ValidationCam_Back` | `2026-08-01-prototype-back.png` | 16:9 | 1920 × 1080 | 40 |
| `ValidationCam_Top` | `2026-08-01-prototype-top.png` | 16:9 | 1920 × 1080 | 40 |
| `ValidationCam_Side` | `2026-08-01-prototype-side.png` | 16:9 | 1920 × 1080 | 40 |
| `ValidationCam_Mobile` | `2026-08-01-prototype-mobile.png` | 20:9 | 2160 × 972 | 68 |

Le bouton **List Validation Views** réaffiche à tout moment positions, cibles, FOV,
résolutions, fichiers attendus et la dérivation géométrique de chaque cadrage.

## Cadrages et origine des valeurs

| Repère | Position | Cible | Origine |
|---|---|---|---|
| `CentralHubConcept2ReferenceCamera` | `(0, 74, 124)` | `(0, 15, 4)` | imposé par la spécification |
| `ValidationCam_Side` | `(120, 30, 0)` | `(0, 16, 0)` | imposé par la spécification |
| `ValidationCam_Spawn` | `(0, 17.5, 9)` | `(0, 21, -23)` | spawn `(0, 12, 8)` + 5.5 d'yeux, +1 en Z pour dégager le médaillon ; cible = panneaux arrière `Z = -23` à `27 - 6` |
| `ValidationCam_FromBubbles` | `(0, 13.85, 77.3)` | `(0, 16, 0)` | marche des bulles `7.35` + 6.5 d'yeux ; bord avant du palier `51.3` + 26 de recul |
| `ValidationCam_Back` | `(0, 45, -92)` | `(0, 20, -10)` | centre des panneaux `27` + 18 ; `-23 - 69` de recul |
| `ValidationCam_Top` | `(0, 150, 20)` | `(0, 12, 0)` | deck `12` + 138 ; `+20` en Z pour incliner de ~8° et éviter un regard strictement vertical |
| `ValidationCam_Mobile` | `(0, 20, 44)` | `(0, 15, -6)` | deck `12` + 8 de hauteur, `Z = 44` au milieu de l'escalier (`37.75 → 51.3`), FOV large |

Aucune valeur n'est devinée : les cotes utilisées viennent de `anchors.txt`, relevé depuis
le code.

## Modes autorisés et garanties du plugin

Cinq actions, deux niveaux d'autorisation :

| Action | Edit | Test (F5) | Effet |
|---|---|---|---|
| `Create/Refresh Hub Validation Cameras` | oui | non | écrit dans la hiérarchie Studio |
| `Go To Selected Validation View` | oui | oui | déplace la caméra courante |
| `List Validation Views` | oui | oui | lecture seule, Output |
| `Restore Test Camera` | oui | oui | rétablit l'état caméra mémorisé puis l'efface |
| `Remove Validation Cameras` | oui | non | supprime le dossier de repères |

- Les deux actions qui écrivent dans la hiérarchie exigent `RunService:IsEdit()` ; les
  trois autres se contentent de `RunService:IsStudio()`, puisque les captures se font
  pendant un test.
- Pendant un test, le premier cadrage mémorise `CameraType`, `CameraSubject`, `CFrame`,
  `Focus` et `FieldOfView` avant toute modification. Cet état n'est pas réécrit par les
  vues suivantes, ce qui permet d'enchaîner les 7 captures. `Restore Test Camera` le
  rétablit — le `CameraSubject` seulement si l'instance existe encore et a toujours un
  parent — puis efface la mémoire. Sans état mémorisé, il affiche
  `[HubValidationCameras] No saved test camera state to restore.`
- Repères `Part` ancrés, `Transparency = 1`, `CanCollide`, `CanTouch` et `CanQuery` à
  `false`, `Locked`, `Massless`, `CastShadow = false`, aucun script enfant.
- Idempotent : relancer met à jour les repères existants sans les dupliquer.
- Ne touche jamais `Players` ni `StarterPlayer`, ne crée aucun `LocalScript` et ne modifie
  aucun script de production. La caméra du joueur n'est modifiée que sur clic explicite, et
  toujours restaurable.
- Les repères vivent sous `Workspace.StudioDecoration`, zone que le code du jeu ne touche
  jamais. Ils restent des instances sauvegardées dans le lieu : le bouton **Remove
  Validation Cameras** doit être utilisé avant publication, et la Phase 1 ajoutera une
  règle de contrat interdisant leur présence dans un build publié.

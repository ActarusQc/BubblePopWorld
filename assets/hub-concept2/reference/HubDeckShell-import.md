# HubDeckShell — fiche d'import Roblox

Statut : **en attente de validation visuelle** (passage artistique Phase 2).

## Fichiers

- Blend : `E:/roblox/BubblePopWorld/assets/hub-concept2/blender/HubDeckShell.blend`
- FBX : `E:/roblox/BubblePopWorld/assets/hub-concept2/export/HubDeckShell.fbx`
- Textures :
  - `E:/roblox/BubblePopWorld/assets/hub-concept2/textures/HubStructureAtlas_Color.png` (1024 × 1024)
  - `E:/roblox/BubblePopWorld/assets/hub-concept2/textures/HubStructureAtlas_Normal.png` (1024 × 1024)
  - `E:/roblox/BubblePopWorld/assets/hub-concept2/textures/HubStructureAtlas_Roughness.png` (1024 × 1024)
  - `E:/roblox/BubblePopWorld/assets/hub-concept2/textures/HubStructureAtlas_Metalness.png` (1024 × 1024)

## Dimensions

- Bbox Roblox : `84.000 × 8.700 × 60.000` (cible 84 × 8.7 × 60)
- Pivot local `(0,0,0)` / ancre monde `(0, 8.25, 0)` — centre bbox `(0, 8.85, 0)`
- Deck central Y=12.00 · ailes dessus Y=13.20 · marches 2×0.6

## Triangles

| Base | 1476 |
| Moulding | 2480 |
| Wings | 3216 |
| NeonTrim | 108 |
| **Total** | **7280** / 13000 |

## Matériaux

- Jupe `#23262E` R0.72 M0.05 · Socle `#31353F` R0.52 M0.35
- Dalle `#3A3F4B` R0.62 M0.08 · Moulures `#4A505E` R0.38 M0.55
- Neon `#4FD8FF` émission modérée (pas blanche)

```lua
model:SetAttribute("BPW_HubAsset", true)
model:SetAttribute("BPW_HubAssetKey", "Deck")
model:SetAttribute("BPW_AssetVersion", 1)
model:SetAttribute("BPW_AuthoredSize", Vector3.new(84, 8.7, 60))
model:SetAttribute("BPW_AuthoredYaw", 0)
```

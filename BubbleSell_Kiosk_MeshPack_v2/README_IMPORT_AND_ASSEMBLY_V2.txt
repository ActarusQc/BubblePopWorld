BubblePopWorld — Sell Kiosk Mesh Pack V2
========================================
This version is a more premium modular kit designed to better match the concept maquette.

Included meshes
---------------
- MainSign_V2.obj
- RoofCanopy_V2.obj
- KioskColumn_V2.obj
- CounterBody_V2.obj
- FrontDisplayFrame_V2.obj
- BubbleTankBase_V2.obj
- BubbleTankTop_V2.obj
- BubbleTankChamberCollar_V2.obj
- TerminalFrame_V2.obj
- SellPad_V2.obj
- CoinBadge_V2.obj
- BubbleDecoCluster_V2.obj
- SellKiosk_AssemblyReference_V2.obj   (full assembled visual reference)

Recommended Studio workflow
---------------------------
1. Import each OBJ with Home > Import 3D.
2. Anchor them while placing.
3. Create a folder/model such as Workspace.BubblePopWorld.Lobby.SellKioskMeshes.
4. Use the full assembly reference only as visual alignment aid, OR keep it as a single locked reference model.
5. Prefer the modular pieces for the final kiosk, because Cursor can position them individually.

Recommended assembly positions (relative to kiosk center)
---------------------------------------------------------
RoofCanopy_V2                : (0, 14.0, 0)
MainSign_V2                  : (0, 19.25, -0.55)
KioskColumn_V2 x4            : (-9.2,4.0,2.8), (9.2,4.0,2.8), (-8.45,4.0,-2.45), (8.45,4.0,-2.45)
CounterBody_V2               : (0, 5.0, 0.95)
FrontDisplayFrame_V2         : (0, 4.8, 3.55)
BubbleTankBase_V2            : (-1.7, 8.2, -0.55)
BubbleTankTop_V2             : (-1.7, 12.35, -0.55)
BubbleTankChamberCollar_V2 x2: (-1.7, 8.65, -0.55) and (-1.7, 11.95, -0.55)
TerminalFrame_V2             : (5.95, 8.35, -0.2)
SellPad_V2                   : (0, 0.18, 7.1)
CoinBadge_V2                 : (-10.8, 8.7, 1.45)
BubbleDecoCluster_V2         : duplicate around sign or tank

Still best done directly in Roblox Studio
-----------------------------------------
- Transparent tank cylinder
- SurfaceGui text:
  * 'VENDRE LES BULLES'
  * 'Transforme tes bulles en pièces !'
  * 'Valeur du sac : ...'
- Neon border strips
- Bubble animation inside the tank
- Sell pad symbol decal or UI

Suggested colors/materials
--------------------------
- Main structure: dark navy / deep blue
- Accent structure: electric blue
- Neon accents: cyan + violet
- Text: white
- Coin accents: gold / yellow
- Use Roblox Neon for thin accent strips only, not for every whole mesh.
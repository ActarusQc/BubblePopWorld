# Summer Zone compacte — conception

## Objectif

Réduire uniquement l’emprise de la Summer Zone de 240 × 240 à 120 × 180 studs, sans modifier la Classic Zone, l’économie, les niveaux, les sauvegardes ou le fonctionnement des bulles.

## Géométrie retenue

- Largeur Z : 120 studs (−50 %).
- Profondeur X : 180 studs (−25 %).
- Bord d’entrée ouest conservé à X = 168.
- Centre de zone déplacé de `(288, 6, 0)` à `(258, 6, 0)`.
- Axe d’entrée conservé à Z = 0 avec `EntryCenterOffset = 0`.
- Le pont, son milieu, l’arche et le LevelGate restent alignés sur cet axe.

La réduction est asymétrique dans le repère du monde : la largeur se contracte autour de Z = 0, tandis que la profondeur se contracte vers le fond pour ne pas déplacer l’arrivée du pont.

## Configuration

Créer `src/Shared/SummerZoneConfig.lua` comme source unique des constantes propres à cette zone :

- `ZoneWidth = 120`
- `ZoneDepth = 180`
- `SideDecorMargin = 16`
- `EntranceDecorMargin = 14`
- `RearDecorMargin = 24`
- `BubbleRowReduction = 2`
- `LightPerimeterSpacing = 30`
- `EntryCenterOffset = 0`

`ZoneDefs.lua` dérive de cette configuration l’origine de zone, les demi-emprises, les dimensions du BubbleBoard, ses bounds et la géométrie d’accès. Les consommateurs existants utilisent le layout dérivé au lieu de dimensions Classic implicites.

## BubbleBoard

Conserver `GameConfig.Grid.Spacing = 6` et `BubbleSize = (5.4, 2, 5.4)`.

- Ancienne grille : 33 × 32 bulles.
- Nouvelle grille : 23 × 12 bulles.
- Ancienne emprise jouable : 201,4 × 195,4 studs.
- Nouvelle emprise jouable : 141,4 × 75,4 studs.

La grille reste centrée sur Z = 0. Elle reste ancrée à 14 studs du bord d’entrée, avec environ 24,6 studs au fond et 22,3 studs de chaque côté. La taille, le style, l’espacement, les états et la régénération des bulles ne changent pas.

## Structure et accès

`Floor`, `Bounds`, murs, `DecorPerimeter`, `ZoneTrigger`, `LevelGate`, point d’arrivée et offsets dérivent des demi-emprises Summer 90 × 60.

Le bord d’entrée restant à X = 168, le pont existant continue d’arriver naturellement au centre. Le LevelGate et l’arche restent calculés depuis ce bord et l’axe Z = 0.

Les positions qui dépendent de l’emprise, notamment les feux d’artifice et l’exclusion du décor d’horizon, utilisent les nouveaux bounds.

## Contour lumineux

Le générateur recalcule les points depuis les bounds Summer compacts et `LightPerimeterSpacing`.

- Répartition régulière sur les quatre côtés.
- Aucun poteau dans le passage d’entrée ni sur le BubbleBoard.
- Base des poteaux au niveau du dessus du `ZoneFloor`.
- Hauteur et taille des personnages inchangées.
- Attaches près du sommet.
- Courbe orientée vers le bas, avec point bas dans la plage de sécurité existante.
- Nombre de poteaux automatiquement réduit avec le périmètre.

## Preview Studio et décors manuels

`SummerZoneEditingPreview` utilise le même layout que la vraie zone pour le sol, les bounds, le BubbleBoard, l’entrée, le gate et le périmètre décoratif.

Le code ne supprime, ne vide et ne reconstruit jamais `Workspace/StudioDecoration/SummerZoneDecor`. L’arche, les palmiers, le mirador, le coin détente et les autres objets manuels restent intacts. Leur position n’est pas automatiquement ajustée ; certains pourront être replacés manuellement.

Le plugin source devra être recopié vers `%LOCALAPPDATA%\Roblox\Plugins\LobbyEditingPreview.lua` seulement s’il est modifié. Le bouton **Create/Refresh Summer Preview** régénère uniquement `SummerZonePreview`.

## Tests et validation

Les tests couvrent :

- dimensions 120 × 180 et réductions attendues ;
- bord et axe d’entrée inchangés ;
- pont, gate et arrivée centrés ;
- BubbleBoard 23 × 12, espacement et taille de bulles inchangés ;
- marges décoratives minimales ;
- bounds de tous les éléments structurels ;
- périmètre lumineux compact, sol, hauteur, attaches, courbe et gap d’entrée ;
- cohérence preview/runtime ;
- préservation explicite de `SummerZoneDecor`.

Validation finale : tests existants, tests géométriques mis à jour et `rojo build`.

## Hors périmètre

- Aucun changement d’économie, niveau, récompense ou sauvegarde.
- Aucun changement de thème ou de fonctionnement des bulles.
- Aucune montagne verte ajoutée.
- Aucune publication du jeu.

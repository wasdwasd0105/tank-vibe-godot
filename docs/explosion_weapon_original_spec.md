# Explosion Weapon — the original's rules, and the remake's

Read from `Tank V1.22/Tank.exe` (Delphi, DelphiX): weapon 4, its shell (`TArmsSprite`) and its blast (`TExploseSprite`, VMT 0x004902dc). The earlier version of this file was written from guesses in places, and the remake followed it: a circular ring of whole fireballs, a flat spray of damage, full bricks removed, a strong direct hit. Sean saw that the blast's wave and effect were "pretty different from the original game" (2026-10-07), so it was researched again from the code and ported rule for rule (2026-10-08).

Units: one original 16 px cell is one remake 32 px tile, so an original pixel is two remake pixels, and an original half cell (8 px) is a remake quarter tile (16 px). At the default game speed a tick is 0.75 ms and a logic frame is 20 ticks, 15 ms.

---

## Part A — The rules (remake numbers, original addresses)

### The shell

1. **It leaves at 355.6 px/s and speeds up by 948 px/s a second to 711**, which it reaches after 0.375 s (tables 0x004d2c48, 0x004d2c60, 0x004d2c78). No spread.
2. **Its heat is its HP: 1 at gun levels 0 and 1, 2 at levels 2 and 3** (created with 1, `SetLevel` 0x00494088 raises it). A shot carries its tank's gun level (`Fire` 0x004931e0 calls `SetLevel(shell, tank level)`), and its blast is that level. The same goes for the enemies' explosion shells.
3. **It takes and gives heat as the original's Clash (0x004951f0):** against a tank, a shell or the base, both lose the lesser of the two. So a level 2 or 3 shell (2) finishes a tank of 1 and flies on with 1, and wins against a 1-heat shell and flies on. A moon shield's front stops it.
4. **Walls (`TileHit`, 0x004940e4):** it loses the most any wall under its front costs it: a whole brick broken whole by a 2-heat shell costs 2 (a 1-heat shell breaks the near half, for 1); any other brick costs 1; a hard brick its points up to the shell's heat; iron and super steel all of it. So a level 2 or 3 shell goes through half bricks and on to the next wall.
5. **It goes off wherever it dies** (`Die` 0x004939f4 → 0x00493aec): a wall, a tank, a shell, the field's edge. (Its 2.06 s life never runs out first.) Its small impact flash (`_B_32B`) plays as before.
6. **2, 3, 4 and 4 shells in flight** at levels 0-3: each costs 12 heat of the tank's gun, which fires under 24 + 8 per level (`CanFire` 0x00491946). Ammo 20 a pack, 100 at most. The launch plays `S_Explose`.

### The blast

7. **Where:** a square 8 tiles a side, on the tile grid, centred on the tile corner nearest what went off (an exact half goes right, or down). The original puts its left edge at `Trunc(sprite_left / 16 - 3) * 16` (0x00493aef; mines 0x0049a390; a mine-thrown tank's landing 0x0049a797), so near the field's top and left edges, where that's negative, it sits a tile further in. (`ExplosionBlast.grid_origin`.)
8. **Heat:** power 250 + 25 per level, falloff 60 - 5 per level. Each quarter tile's heat is `round(power - distance * falloff)`, the distance from the centre in quarter tiles (banker's rounding, as Delphi's `Round`); 0 if that's not above 0, or if a wall stands in the way (0x0049696e).
9. **Walls in the way** (0x004969d7): a wall's quarters stop it (a brick's standing ones; all of a hard brick, iron or super steel; never grass, water, ice, tanks or the base). A quarter is lit only if two straight marches out from the centre to it, column by column and row by row, meet no wall quarter; its own quarter never counts, so the first wall in line is reached and everything behind it is in its shadow. The walls are read once, as it starts.
10. **Per tile:** its heat in per mille of the power (its hottest quarter), and which of the fireball's 3x3 pieces it shows, by which quarters are lit (table 0x004d2e48). On open ground the tiles' heat, top half (mirrored below):

    ```
    L0 rows 2-3:  .  .  152 388 388 152  .   .     L1 rows 1-3:  .  .   .   94  94   .   .  .
                  .  .  388 832 832 388  .   .                   .  .  294 490 490 294  .  .
                                                                 . 94  490 858 858 490 94  .
    L2 rows 1-3:  .  .  143 246 246 143  .   .     L3 rows 0-3:  .   .  36  98  98  36   .   .
                  . 143 410 576 576 410 143  .                   .  120 286 372 372 286 120  .
                  . 246 576 883 883 576 246  .                  36 286 510 646 646 510 286 36
                                                                98 372 646 901 901 646 372 98
    ```

    So 16, 24, 32 and 52 tiles show at levels 0-3.
11. **Its frames:** 15 of 15 ms (it lives 300 ticks, 20 a frame). Each tile shows fireball frame `trunc(heat / 250 + frame - 7.5)` while that's 0 to 7 (0x00497258), so the hotter tiles start sooner (the centre on frame 4 at level 0, frame 3 at levels 2 and 3), and frame 0 shows for two frames. It draws each tile's own 16 px slice of that frame (32 here) from `_B_Explose` (the remake's `explosion_wave_1..8.png`), so the tiles make one body of fire: puffs, then a sheet of fire, then embers.
12. **Walls change once, on frame 8** (120 ms in, 0x00497022), on every tile whose heat times the power reaches 25000 (the tiles that would hurt a tank):
    - burned grass goes;
    - a whole brick keeps half: the top half on the tiles above the grid's diagonal, the left half on and below it. (The code compares against `15 - y`, so its other two branches, the right and bottom halves, never run: it meant to keep the half facing away from the blast.);
    - what's left of a brick goes;
    - a hard brick loses a point (its last one, and it goes);
    - iron, super steel, grass, water, ice and the base don't change.
13. **Tanks:** while a tile burns (its own frames 1 to 6), an opposing tank on it is hurt by the hottest such tile, `round(heat * power / 100000 + 0.25)`: 2 at the centre at level 0, 3 at levels 1-3, 1 out towards the edge (0x00497415). It's one hit, however many points (`Damage`, 0x00492640: one downgrade, one sound, a player's 0.5625 s of grace), and then no blast hurts that tank for 0.1875 s (250 ticks, its +0xc0). A tank's reach is its picture less 6 px a side, 12 px more a side while it blinks; a blinking tank takes no damage but still gets the 0.1875 s. Not a materializing or airborne tank.
14. **Its tank too:** a tank the shell hit is in its blast as well. An enemy hit directly loses 3, 4, 5, 5 in all at levels 0-3; a player hit directly by an enemy's shell 1 or 2, the grace after the shell's hit taking the blast.
15. **Moon shield** (0x004974a6): a tile up-left of the centre is covered by a shield facing right or down, up-right by one facing down or left, down-left up or right, down-right up or left. A shield never breaks. Saved from all of it, the tank sounds the shield (HitTank2).
16. **Shells** on its burning tiles lose that much heat (a 1-heat shell goes; an explosion shell going off in turn), then 0.1875 s of immunity.
17. **Mines:** an opposing armed mine of no higher a level that it reaches goes off if the blast's level plus its heat there, less 2 (less 3 above level 0), comes to the mine's level (0x0049753f).
18. **Sides:** a player's blast never hurts a player, an enemy's never an enemy. A mine-thrown tank's landing blast belongs to neither side and hurts everyone. The blast never touches the base.
19. **Sound:** the blast itself is silent; the launch plays `S_Explose`, a tank it hurts or finishes its hit or explosion sound.

### Steel

20. **No level of the original's explosion gun breaks iron.** Its blast leaves every wall from iron up alone (0x004970ca), and its shell (1 or 2 heat) dies on iron: only a shell with 6 or more heat breaks iron (0x00494269), which in practice is an AP shell. Iron has no damaged states (its 4 ids are picture variants); the wall with stages is the hard brick.

---

## Part B — The remake

Ported as above: `ExplosionBlast` (the grid, its frames, picture, walls, damage, shells, mines), `Bullet` (heat, Clash, walls by heat: `hit_tiles`, `wall_cost`, `_explode_direct_hit`), `CookieData.EXPLOSION_FIRE_CONFIG` (speeds, heat, in flight), `BaseTank.take_hit` / `EnemyTank.take_hit` / `PlayerTank.take_hit` (one hit of several points), `LevelManager.spawn_explosion_blast`, `blast_shadow_quarters`, `blast_wall`. Online, the host sends where its 8x8 goes (`NetWorld.EV_BLAST`: its top-left tile and level), and a client works out the same grid from its own copy of the map, for the picture only.

**Sean's rule (2026-10-08): the players' explosion gun at its top level (4 in play, level 3 in the code) breaks one layer of iron, by its shell's own hit only.** The shell breaks the iron in its way, the tiles under its front (`Bullet.breaks_iron`, `Bullet.hit_tiles`), and goes off there as on any other wall, so a shot at an iron wall makes a hole a tank wide and one tile deep. Its blast changes no iron (rule 12 as the original), so the layer behind the hole and the iron beside it stay. A client breaks the iron its own shell hits at once, as it does other walls (`NetClientWorld.predict_wall`). Not the enemies' explosion shells, nor mines. (The rule's first build, the same day, had the blast break the iron it reached; Sean asked for the direct hit only.)

**The original's quirks, kept as it played:** a half brick's left and right halves shadow the wrong side (its wall mask, 0x00496859, swaps ids 30/31 and 34/35), the shadow's march towards the left and top tests its line mirrored, and a whole brick keeps only its top or left half (rule 12).

**Not changed:** the cooldown still goes by the gun level (the original's by the speed level, 0.45 s to 0.225 s, shared with the plain gun; the remake has its own cooldowns for every special weapon); the plain gun's and the explosion gun's shells don't share one heat budget; the enemies' explosion tanks keep level 0 (the original gave them `TYPE_GUN` 0-3 plus the difficulty's bonus: a decision Sean hasn't made).

## Part C — Found on the way (not changed)

- **Enemy tanks' side is 0, not -1** (`TEnemyTank.Create` 0x00494b78): so enemy fire has owner 0 and melts ice too (the fire spec and the remake say enemy fire doesn't).
- **AP and iron:** the original breaks iron only for a shell with 6 or more heat, at a cost of 8; the remake's AP pays 4 with no such limit.
- **Mines come 15 a pack** (75 at most) in the original; the remake gives 25.

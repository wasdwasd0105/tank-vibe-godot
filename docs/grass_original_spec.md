# Grass — the original's rules, and the remake's

How Tank.exe v1.22's grass works, read from the binary (`Tank V1.22/Tank.exe`), and what the remake does. Sean asked to review the grass logic (2026-10-08), after the fire, whose spec (fire_weapon_original_spec.md) has grass burning.

Units: one original cell (16 px) is one remake tile (32 px). Addresses are Tank.exe virtual addresses.

## Part A — The original

**What grass is:** ids 8–11 of the wall layer (`[0x4d74cc]`), and burned grass 12–15: the remake's foreground tiles 0x09–0x0C and 0x0D–0x10. Each id is its own 16 px picture in the map's image ("Back", image-list item 18), so the map's id picks which of the 4. None of them animates: the map's animation (0x00490660) steps only water, ice and super steel.

**What grass does: nothing but hide what's under it.**
- Tanks drive through it: only wall ids 24 and up stop a tank (0x00492be0).
- Shells fly through it: a shell's wall hit (TileHit, 0x004940e4) passes ids below 24, whatever its heat.
- Mines may be laid on it and tanks may appear on it: those checks refuse only ids 24 and up (mine_weapon_original_spec.md, enemy_spawn_original_spec.md).
- The enemies' way to the base costs the same over grass as over open ground (enemy_ai_original_spec.md). Their firing never looks at the map, so grass doesn't hide a tank from their aim.
- A blast leaves green grass and clears burned grass (explosion_weapon_original_spec.md).
- Fire burns green grass grey, with burning grass on it, which burns both sides and walks on along the grass (fire_weapon_original_spec.md, section 5).
- While the base is guarded, its ring is paved over whatever was there, grass too, and comes back as brick (0x004947c8, 0x00494404).

**How it's drawn.** The whole wall layer (bricks, steel, grass and burned grass) is one tile map (DelphiX's TChipsSprite) drawn at draw order (Z) 8 (0x004c8680). Its layers draw at alpha 255 (SetMapSize, 0x0046aa1a; only the floor's wall-shadow layer gets an alpha, from an options slider), and the tile map draws those as a plain copy with its colour key (0x0046ae43): solid, but for the picture's magenta pixels. Those are 66 of 256 in green grass (a quarter) and about 135 in burned grass (half). So what's under grass shows only through those holes.

The draw order of everything on the field (set by each sprite's constructor, through 0x004690a8):

| Z | What | Where |
|---|---|---|
| −3 | the floor: ice, water, and the walls' shadows | 0x004c859d |
| −2, −1 | the players' fire, the enemies' fire | 0x00497b34 |
| 0 | mines | 0x0049a2d6 |
| 1, 2 | tanks: 1 with an add-on, 2 without (0x004935f8). An appearing tank shows image 12, Tank Out, itself (0x00491690); a tank blowing up turns into image 9, _B_48, itself (0x00491fb1) | 0x004916c5 |
| 6 | the base flag | 0x00494311 |
| 7 | shells, and the hit pictures they turn into (0x00493a5f) | 0x0049383f |
| **8** | **the wall layer: bricks, steel, grass, burned grass** | 0x004c8680 |
| 9 | burning grass | 0x00497b4c |
| 10 | blasts (TExploseSprite) | 0x00496d5b, 0x00496e71 |
| 11 | items (12 once taken, as they go) | 0x0049560e, 0x00496351 |
| 20 | words: text sprites (the damage, kill and item words) | 0x0049644d |
| 50 | a tank thrown by a mine | 0x0049a61d |

So grass covers the tanks (appearing and blowing up too), shells and their hits, mines, the base and the sides' fire, all but through its holes. Burning grass, blasts, items, words and thrown tanks show over it.

## Part B — The remake

**Before (2026-10-08):** the grass was drawn at 55% (a fade from the first map code), so every tank under it showed. Its tiles sat at z 20 (z 10 on a layer of z 10), over the burning grass on them. Items and their words drew under it, and shell hits, tank explosions and appearing tanks over it.

**Now, as the original:**
- **Grass and burned grass** draw solid in the TreeLayer (z 10), but for their pictures' own holes, which are the original's.
- **Under it** (z 0 in Entities, over the tanks and walls): shells' hits (HitEffect, and the built-in flash, explosion.gd), tanks' explosions, the spawn burst (SpawnBurst). Tanks, shells, mines, the base and the sides' fire were already under it.
- **Over it:** burning grass (GroundFire.GRASS_Z 11), blasts (z 20), items (Cookie.ITEM_Z 21), words (KillText.Z_INDEX 21, PickupText the same, drawn after the items), and thrown tanks (BaseTank.FLY_Z_INDEX 30).
- **The HUD** (its side panels and the rejoin countdown) now draws over everything on the field (z 40), so words spilling off the field's edge still go under the panels, as the item words did before.
- **Kept the remake's:** an item, once taken, is gone at once (no flying off). The base flag draws under the tanks and shells, as before (the original's was over the tanks, Z 6).

**Already the original's, and checked:** tanks and shells go through grass; its 4 pictures by the map's code, never animated; burned grass keeps its picture's number; blasts clear burned grass only; fire burns it (fire_weapon_original_spec.md); the enemies' way over it; mines and appearing tanks on it.

**Tests:** scenes/test/grass_test.tscn: its pictures (solid, the original's holes, picked by code, kept when burned); what draws under it and over it, on the host and on an online client, and the HUD over all of it; tanks and shells through it. 17 broken versions of these rules all fail it.

## Found on the way (not changed)

- **Iron doesn't animate in the original**: its map animation steps only super steel (60–63) on the wall layer, and water and ice on the floor. The remake animates iron too.
- **The base's guard ring** comes back as brick in the original whatever it was before (grass, open ground or brick), every time a guard runs out. The remake puts back the stage's own tiles.

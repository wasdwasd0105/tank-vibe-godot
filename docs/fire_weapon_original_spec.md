# Fire Weapon — the original's rules, and the remake's

How Tank.exe v1.22's fire weapon and ground fire work, rule for rule, read from the binary (`Tank V1.22/Tank.exe`), and what the remake does. The first version of this spec (2026-09-24) had about a dozen things wrong, the main one that enemy tanks are side −1 (they're side 0, so their fire melts ice too). Sean asked to recheck whether fire breaks the ice and the fire logic (2026-10-08): every rule below was re-read from the code, and the remake's fire, which had followed Sean's early draft rules (a field growing a ring at a time), was ported to the original's (Part B).

Each rule carries its address and a tag: **[CONFIRMED]** (the first spec said so and the code agrees), **[CORRECTED]** (old -> new), **[NEW]**, **[UNCONFIRMED]**.

## Part A — The original

### 0. What changed from the first spec

| # | Old claim | Verified rule | Where |
|---|---|---|---|
| 1 | Enemy tanks are side -1 | **Side 0.** TEnemyTank.Create calls the tank ctor (which writes -1 at 0x4917a4), then writes **0** | 0x494b78 |
| 2 | Only player fire melts ice; enemy and grass fire never | **Any fire with owner >= 0** melts the ice under it: player fire, **enemy fire**, and their spread children. Only grass-chain fire (owner -1) never melts | 0x497a4e-0x497a80 |
| 3 | 1.125 s window vs enemy fire, 0.5625 s vs player fire | 750 ticks vs **any owner >= 0** fire (player fire on enemies, **enemy fire on players**). 1500 ticks only vs grass-chain fire (-1), which burns **both** sides. Enemies are immune to enemy fire | 0x491d34-0x491d48 |
| 4 | Enemy fire (if -1) draws above tanks | Enemy fire: row 1 (orange), Z -1, **below** tanks. Only grass-chain fire draws above tanks (row 0, red, Z 9) | 0x497b34 |
| 5 | Only player fire can diffuse | **Enemy fire can diffuse too** (gate is owner >= 0, strength >= 1, fuel >= 7000) | 0x49771e |
| 6 | Stamp centre = Round(X/16) ("Round better-evidenced") | **Trunc**(X/16), Trunc(Y/16) of the shell's top-left. The inner 2x2 is the 4 tiles round the tile corner nearest the shell's centre | 0x493b5a, 0x493b6d |
| 7 | One fire grid | **Three grids, one per side** (owner >0 / =0 / <0). Restacking only merges same-side fires. A player fire and an enemy fire can burn on the same tile | 0x490a3c, 0x490a70 |
| 8 | Spread gives (myFuel - neighbourFuel)/4 per neighbour | Uses the giver's fuel **at the start of the pulse** (F0) for all 4 neighbours, so a fire with 4 open empty neighbours gives away nearly all its fuel in one pulse. New children are never registered, so later pulses into the same tile stack more children there | 0x49775e, 0x4978c8-0x497912 |
| 9 | Cooldown -60 per logic frame: 0.27 / 0.225 / 0.18 / 0.135 s | -60 per **think**, and tanks think every other frame: **0.54 / 0.45 / 0.36 / 0.27 s** at speed level 0-3. Goes by speed level, not gun level | 0x491e22, 0x4c7bb7, 0x49355f |
| 10 | Range 244 px (integral) | **61 moves, 248 px** (15.5 cells; 496 remake px) | 0x493fc8 |
| 11 | Shell degrades steel one stage (40..55 -> +4) | Hard brick 40..51 -> +4; its **last stage 52..55 is destroyed** (-1) | 0x494200-0x494233 |
| 12 | A tank hit stamps the patch centred on the tank | Centred on the **shell's** position at impact, at the tank's near edge | 0x493a28 |
| 13 | Grass-chain children are visible and burn at once | Visible at once, but **harmless for 100 ticks** (6 frames) | 0x4979f0, 0x497a85 |
| 14 | No sound while burning | Each burn that a tank survives plays **HitTank (wave 10)** and runs the whole generic hit path | 0x4926c9 |
| 15 | Round vs Trunc, eagle immunity: UNCERTAIN | Both settled: Trunc (#6), and the eagle is proven fire-proof (section 7) | |

Port-facing consequences of #1 to #5 are listed in section 8.

---

### Units and engine

- **Ticks.** 1 tick = 0.75 ms at default speed. One logic frame = 20 ticks = 15 ms. Engine.Move(20) runs every frame (0x4c7d20). Tanks "think" (commands, firing, cooldown) only on even frames (0x4c7bb7). [CONFIRMED]
- **Map.** 1 original px = 2 remake px. One original cell (16 px) = one remake tile (32 px). The playfield is cells 1..40 x 1..30 (remake 0..39 x 0..29). Cells 0/41 and 0/31 are border (wall id 64). [CONFIRMED]
- **Sprite update order.** A sprite's X/Y is its top-left. Engine.Move iterates its list with the count read once (0x468ee3), so a sprite created during Move gets its first DoMove next frame. Shells are created in the think, which runs before Move, so they move in their creation frame. [NEW]
- **Collisions.** Only three sprites ever start a collision test (TSprite.Collision 0x468d34): tanks (0x492272), shells (0x493e14) and mines (0x49a41b). Fires, flags and cookies never do. [NEW]
  - The target must be Collisioned (+0x54) and not dead (Collision2 0x468dbc).
  - Rect overlap is strict (0x4681f0).
  - The "Done" flag doesn't stop the outer loop, so the starter's DoCollision runs for **every** overlapping sprite each frame.

**Wall ids** (layer `[0x4d74cc]`; remake code = id + 1). Naming follows enemy_ai_original_spec.md:

| Ids | Meaning |
|---|---|
| -1 | empty |
| 8-11 | grass |
| 12-15 | burned grass |
| 24-27 | brick |
| 28-35 | half brick |
| 36-39 | quarter brick |
| 40-43 | hard brick |
| 44-55 | damaged hard brick |
| 56-59 | iron |
| 60-63 | super steel |
| 64 | border |

**Ice/water layer** `[0x4d74c8]`: 0-3 ice, 4-7 water, -1 none.

---

### 1. The fire shell (TArmsSprite, weapon 2)

| Property | Original | Remake | Address | Status |
|---|---|---|---|---|
| HP (damage) | 1. SetLevel changes HP only for armor (3) and explosive (4), never fire | 1 | 0x4937b3 (table 0x4d2c30), 0x494088 | CONFIRMED |
| Speed | 7000 units; px/tick = speed/30000. That is 4.667 px a frame at the start | 622 px/s at the start | 0x4937c0, 0x493d7e | CONFIRMED |
| Deceleration | speed += -1500 * 20 div 1000 = **-30 a frame**; capped at max 7000 | about -178 px/s^2 | 0x493f84-0x493fc2 | CONFIRMED |
| Lifetime | 1200 ticks; -20 a frame, dies on the frame it is <= 0, so **61 moves**; last speed 5200 | 0.915 s | 0x4937cd, 0x493fc8-0x493fdf | CONFIRMED (frame count NEW) |
| Range | sum of 61 steps = **248.07 px** (15.5 cells) | **496 px** | — | CORRECTED (old 244 / 488) |
| Collision box | 16x16 sprite inset 1 px = 14x14 | 28x28 | 0x494004 | CONFIRMED |
| Spread / side offset | none. Lateral offset applies only to weapons 0/1 | — | 0x49341c-0x4934e0 | CONFIRMED |
| Muzzle position | X = tank.X + (dx+1)*8, Y = tank.Y + (dy+1)*8 (16x16 shell at the front centre of the 32x32 tank) | ×2 | 0x4934e3-0x493545 | NEW |
| Level | shell.+0xdc := tank gun level (+0x128, 0..3) | — | 0x4933f0 | CONFIRMED |
| Owner | shell.+0x74 := tank.+0x74 (players 1/2, enemies 0). 0x493375 is the same copy for mines | — | 0x4933de | CONFIRMED |
| Heat | +8 to tank.+0xf8 per shot. Tank fires only while heat < cap, cap = 24 + 8 * gun level (0x492d7c). Heat is shared with all the tank's weapons. Refunded when the shell dies (by tank UID) | **3 + gun level fire shells in flight** | 0x49354d, 0x491946, 0x493a2d-0x493a59 | CONFIRMED |
| Cooldown | tank.+0xfc += 180 * (6 - speed level). The base think subtracts 60 if > -180. Fire allowed at <= 0. Think = every 2nd frame, so the period is **6*(6-s) frames** | **0.54 / 0.45 / 0.36 / 0.27 s** at speed level 0..3 (players clamp 0..3; enemies -4..4, 0x492ec1) | 0x49355f-0x493573, 0x491e16-0x491e22 | CORRECTED (old: half) |
| Ammo | 30 a pickup, cap 5 * 30 = 150, -1 a shot. A Fire cookie with another weapon held zeroes ammo first. With ammo 0, the special-fire command fires the plain gun | — | 0x492f60, 0x495d11-0x495d56, 0x49357f, 0x491962 | CONFIRMED |
| Sprite | `B_Fire` 128x16. 8 patterns = 2 frames x 4 directions. AnimSpeed 0.03/tick (25 ms a frame). Z 7. Hidden at creation, shown on its first move | — | 0x4937e2-0x493838, 0x493549, 0x493d5f | CONFIRMED |
| Impact | Die swaps to `_B_32A` (image 7, table 0x4d2cd8), re-centred, non-looped. About 13 frames (0.2 s) | — | 0x493a5f-0x493ade | CONFIRMED |
| Sound | S_Fire (wave 2) on firing, enemies too (weapon != 0). Nothing on drop | — | 0x49358d-0x4935ab | CONFIRMED |

**Where it drops.** Every death goes through `TArmsSprite.Die` (0x4939f4). Die runs once (0x4939fa), stops the shell, calls the ignition stamp (0x493a28) at the shell's **current X/Y**, refunds heat, then shows the impact image. A shell dies on the first of these: [CONFIRMED]

- **Lifetime.** After its 61st move.
- **Walls.** In its own DoMove, per frame, after moving (0x493e19-0x493f81):
  - TileHit (0x4940e4) runs on every wall cell under the shell:
    - 1 or 2 columns: by Round(X/8)+1, so it straddles when X is about 16k+8.
    - 2 rows: Trunc(Y/16) and +1.
    - Horizontal flight swaps the axes.
  - The shell takes the **max** result as damage (source 0).
  - **All** touched cells are changed, so one shot can break two bricks.
- **Clash** (0x4951f0), started by any shell's collision test:
  - Hits only TLifeSprite targets (tanks, shells, the flag; 0x4938a0) that are not SameSide (0x493893).
  - Damage n = min(both HPs) to each: the other first, then the shell.
  - The fire shell (HP 1) therefore always dies.
  - It deals 1 HP to a tank, or takes 1 HP off an enemy shell (kills HP-1 shells; armor shells survive with a clink, wave 12, 0x493982).
  - A shielded tank (+0xbd) takes no HP, but the shell still dies.
  - Its box is then 44x44 (0x49306b), so the shell dies 6 px early.
- **Fire is invisible to shells.** Shells ignore fires, mines and cookies: none of these is a TLifeSprite. [NEW]

**TileHit with HP 1** (0x4940e4). All results kill the fire shell, except "pass". The tile change happens **before** the stamp in the same frame, so a brick just broken to a half brick (or a destroyed cell) can take fire at once.

| Wall id | Effect | Address |
|---|---|---|
| <= 23, -1, >= 68 | pass, no change | 0x494297 |
| 24-27 brick | -> half brick 28 + 2*dir + Random(2) | 0x494169-0x494192 |
| 28-35 half brick | -> table 0x4d2d94[dir][variant]: a quarter brick 36-39, or -1 | 0x49419c-0x4941dc |
| 36-39 quarter brick | -> -1 | 0x4941e6 |
| 40-51 hard brick | -> id + 4 (one stage) | 0x494237-0x494261 |
| 52-55 hard brick, last stage | **-> -1** (hardness 1 <= HP 1) | 0x494200-0x494233 (CORRECTED) |
| 56-59 iron | no change (needs HP >= 6) | 0x494269-0x494289 |
| 60-67 super steel / border | no change | 0x494290 |

---

### 2. The ignition stamp (0x493b44)

Only Die calls it (0x493a28).

- **Anchor.** a = **Trunc**(shell.X/16), b = Trunc(shell.Y/16): the cell holding the shell's top-left (0x493b4e-0x493b72). [CORRECTED: was "Round"]
  - Remake: with the shell's centre c in remake px (origin at the playfield's top-left), a = floor((c - 16)/32).
  - The stamp's geometric centre is the tile corner nearest the shell's centre.
- **Cells.** for dy in -1..2 (outer), dx in -1..2 (inner): cell (a+dx, b+dy). [CONFIRMED]
  - Skip the cell unless 1 <= x <= 40 and 1 <= y <= 30 (0x493b7f-0x493b95).
  - Skip unless dx+dy is in -1..3 and dy-dx is in -2..2 (0x493b9b-0x493bb2).
  - That leaves 12 cells: 4x4 minus (-1,-1), (2,-1), (-1,2), (2,2).
- **Wall gate.** Wall id must be in **[-1..23] or [28..35]** (0x493bb8-0x493bd9). [CONFIRMED]
  - Fire can sit on empty ground, grass, burned grass and **half bricks**.
  - It cannot sit on brick, quarter brick, hard brick, iron, super steel, border or item bricks (>= 68).
  - The ice/water layer is **not** read, so fire lands on water and ice.
- **Per cell**, look up the **shell's side grid**: f = Grid(shell.owner)[x][y] (0x493bdf-0x493bf6). [CORRECTED: per-side grid]
  - **Fresh** (f = nil), 0x493bfc-0x493cb2:
    - f := TFireSprite.Create.
    - strength := shell level (0..3).
    - SetOwner(shell.owner).
    - arm := 50 if dx,dy are both in {0,1} (the inner 2x2), else 100 (the ctor default).
    - fuel := Random(500) + 1750 + 1500*strength.
    - AnimPos := (dx+dy+2) mod 8.
    - X,Y := cell*16.
    - **Register** in the shell's side grid. [CONFIRMED]
  - **Restack** (f exists), 0x493cb9-0x493d2b. [CONFIRMED]
    ```
    f.strength := shell level;  SetOwner(f, shell.owner)       // P1 <-> P2 only: same side
    fresh := Random(500) + 1750 + 1500*f.strength               // new strength
    boost := (f.strength + 3) * fresh div 9
    f.fuel := (boost >= f.fuel) ? fresh : f.fuel + boost
    ```
    Arm timer, visibility, AnimPos, terrain timer and spread timer are left alone. So a restack never re-runs the terrain step. A lower-level shell lowers the strength: a level-0 shell turns off that fire's spreading.

**The three fire grids** (0x490a3c get / 0x490a70 set; picked by the sign of the owner argument). [NEW]

| Owner | Grid | Who registers there |
|---|---|---|
| > 0 (P1, P2) | 0x4d7504 | stamps from player shells |
| = 0 (enemies) | 0x4d8a04 | stamps from enemy shells |
| < 0 (neutral) | 0x4d9f04 | **nobody**: no shell has owner < 0, and children are never registered |

- Each grid is 42x32 pointers, indexed x*32 + y.
- All three are zeroed at stage setup (0x49977c, 0x499ee6).
- A fire unregisters itself on death and in its destructor, but only if the slot still points to itself (0x497ab5-0x497b0c, 0x497698).
- Network clients see fire only through these grids, as tile bits: bit 0 player, bit 1 enemy, bit 2 neutral (0x490870). Unregistered children never reach clients.

**Duplicates.** [NEW]

- The stamp never makes two fires of one side on a tile.
- A player fire and an enemy fire can burn on the same tile.
- Unregistered spread children and grass children can pile up on a tile, alongside any registered fire.

---

### 3. The fire sprite (TFireSprite, VMT 0x49035c, size 0xcc)

**Fields** (TImageSprite 0xb4 + own):

| Field | Meaning |
|---|---|
| +0x74 | owner |
| +0xb8 | fuel |
| +0xbc | terrain timer |
| +0xc0 | spread timer |
| +0xc4 | arm timer |
| +0xc8 | strength |

It overrides only Create (0x4975bc), DoMove (0x497710) and Destroy (0x497698). It has no DoCollision of its own.

**Constructor defaults** (0x4975bc). [CONFIRMED]

| Field | Value | Address |
|---|---|---|
| Image | 11 `_B_Fire` (128x48, 24 patterns) | 0x4975d7 |
| AnimCount | 24 div 3 = 8, looped | 0x4975f2 |
| AnimSpeed | 0.015/tick (8 frames in 400 ms) | 0x49760d |
| Fuel | Random(500) + 3750 | 0x497621 |
| Terrain timer | Random(500) + 500 | 0x497636 |
| Spread timer | Random(500) + 250 | 0x49764b |
| Arm | 100 | 0x497660 |
| Visible, Collisioned | False | 0x49766a |
| Z | 9 | 0x497672 |
| Owner | -1 (base sprite ctor, 0x468b7e) | |
| Strength | 0 (zero-filled) | |

**Kinds of fire.**

| Kind | Made at | Owner | Strength | Fuel | Arm | Seen before armed | Registered | Status |
|---|---|---|---|---|---|---|---|---|
| Stamp, fresh | 0x493c09 | shell's (0x493c22) | shell level | Rnd(500)+1750+1500*s | 50 inner 2x2 / 100 | no | yes, own side | CONFIRMED |
| Spread child | 0x497823 | parent's (0x49783e) | parent's | 0, then + F0 div 4 | 100 | no | **no** | CONFIRMED |
| Grass child | 0x4979e3 | **-1** (never SetOwner) | 0 | Rnd(500)+3750 | 100 | **yes** (0x4979f0) | **no** | CONFIRMED / CORRECTED (harmless while unarmed) |

**DoMove, each frame, MoveCount = 20, in this order** (0x497710):

```
// (A) spread: 0x49771e-0x49791f   (section 4)
if owner >= 0 and strength >= 1 and fuel >= 7000:
    spreadTimer -= 20
    if spreadTimer < 0: pulse()                              // spreadTimer += 600 - 100*strength

// (B) terrain step, once: 0x497925-0x497a80   (section 5)
if terrainTimer > 0:
    terrainTimer -= 20
    if terrainTimer <= 0: scorch_and_chain();  if owner >= 0: melt_own_tile()

// (C) arming: 0x497a85-0x497a9d
if arm > 0: arm -= 20  else: Visible := true; Collisioned := true

// (D) fuel: 0x497aa1-0x497b13
if fuel > 0: fuel -= 20
else: if Grid(owner)[tile] == self: Grid(owner)[tile] := nil;  Dead

// (E) animation: TImageSprite.DoMove 0x469468 (AnimPos += 0.3, wrapped mod 8)
```

**Timings in frames.** The fire's first DoMove is the frame after its creation.

| Thing | Rule | Frames | Time |
|---|---|---|---|
| Arm 100 | visible and burning from its **6th** DoMove | 6 | 90 ms |
| Arm 50 | from its **4th** DoMove | 4 | 60 ms |
| Alive | ceil(fuel/20) + 1 frames | | |
| Stamp, L0 | | 89-114 | 1.33-1.71 s |
| Stamp, L1 | | 164-189 | 2.46-2.84 s |
| Stamp, L2 | | 239-264 | 3.59-3.96 s |
| Stamp, L3 | | 314-339 | 4.71-5.09 s |
| Grass child | | 189-214 | 2.84-3.21 s |
| Terrain step | ceil(T/20), T = 500..999 | 25-50 | 0.375-0.75 s |
| First spread pulse | counted only while the spread gate holds | 13-38 | |
| Spread period, s = 1/2/3 | | 25/20/15 | 375/300/225 ms |

There is no other way out: no random snuff and no timer. A fire dies only when its fuel runs out. [CONFIRMED]

**Drawing: SetOwner** (0x497b34). [CONFIRMED, with enemies now row 1]

| Owner | Who | Row (AnimStart) | Z | Colour |
|---|---|---|---|---|
| < 0 | grass chain | 0 | **9**, above tanks (Z 1/2) and shells (Z 7) | red |
| = 0 | **enemies** | 1 (= 8) | -1, below tanks | orange |
| > 0 | players | 2 (= 16) | -2, below tanks | yellow |

- Draw index = AnimStart + Trunc(AnimPos) (0x469530).
- Phases:
  - stamp: (dx+dy+2) mod 8
  - spread child: (x + y + Trunc(parent AnimPos)) mod 8 (64-bit mod, 0x406561)
  - grass child: (x+y) mod 8

---

### 4. Spreading by fuel (the pulse, 0x49775e-0x49791f)

**Gate**, checked every frame: owner >= 0 **and** strength >= 1 **and** fuel >= 7000 (0x49771e-0x497742).

- The timer runs only while the gate holds.
- A fresh fire never passes: at most 6749 fuel at L3.
- It takes a restack. Roughly: L3 needs 2 hits on a tile, L2 2 quick hits, L1 about 3; L0 never spreads. [CONFIRMED; enemy fire now included: CORRECTED]

```
F0 := fuel                                     // 0x49775e: fixed for the whole pulse
spreadTimer += 600 - 100*strength
for (dx,dy) in (0,-1), (1,0), (0,1), (-1,0):   // table 0x4d2970: up, right, down, left
    n := own tile + (dx,dy)
    if Wall[n] not in [-1..23, 28..39]: continue           // 0x4977ba: hard brick+, brick, item bricks block
    if IceWater[n] in [4..7]: continue                      // 0x4977dd: water blocks
    f := Grid(owner)[n]                                     // same-side registered fire only
    if f == nil:                                            // 0x497819
        f := new TFireSprite; f.strength := strength; SetOwner(f, owner); f.fuel := 0
        f.AnimPos := (n.x + n.y + Trunc(AnimPos)) mod 8; f.X,Y := n*16    // NOT registered
    d := F0 - f.fuel                                        // 0x4978c8
    if d > 0:
        f.strength := strength; SetOwner(f, owner)          // overwrite (same side)
        f.fuel += d div 4;  fuel -= d div 4
```

- **Spread gate vs stamp gate.** [NEW]
  - The spread allows quarter bricks (36-39); the stamp doesn't.
  - Neither looks at grass.
  - There is no bounds check: the border (64) stops it.
- **Transfer.** [CORRECTED]
  - Every neighbour gets (F0 - its fuel) div 4, from the **same F0**.
  - Total fuel is conserved.
  - A fire with k empty open neighbours loses at least k*F0/4: with 4 it drops to F0 mod 4 and dies next frame.
- **Children.** [NEW detail]
  - A new child gets exactly F0 div 4, at least 1750. It is not registered.
  - So when the parent pulses again (if still >= 7000), that tile still looks empty and gets **another** child.
  - A child spreads further only if it was given >= 7000, i.e. its parent had F0 >= 28000.
- **Registered neighbours** take the difference and can be pushed over 7000. They then pulse in turn.
  - So a stack levels out inside the patch and pushes a one-tile ring of children outward.
  - It stops once every giver is under 7000.
  - Size has no cap; fuel is the only limit. [CONFIRMED]
- **Fires of the other side** are invisible to the pulse: their tile counts as empty. [NEW]

---

### 5. Terrain step: grass chain and ice melt (0x497925-0x497a80)

It runs **once**, on the frame the terrain timer reaches <= 0: 25-50 frames, 0.375-0.75 s after creation. Every fire kind runs it: stamped, restacked (but only its first timer), spread child, grass child. [CONFIRMED]

1. **Grass.** For the 4 orthogonal neighbours only (table 0x4d2970), never its own tile: if the wall id is 8-11:
   - Wall := id + 4, burned grass, for good (0x4979a1-0x4979bd).
   - Then, if the **neutral** grid has no fire there (always true, since it is never written; 0x4979c2-0x4979d7), make a grass child:
     - owner -1, strength 0
     - Visible at once
     - AnimPos (x+y) mod 8
     - fuel Rnd(500)+3750
     - arm 100: harmless for 6 frames
   - Each grass tile can make only one child (it stops being grass).
   - Children run the step themselves, so the fire walks along the grass about one tile every 0.375-0.75 s. [CONFIRMED / CORRECTED arming]
   - **Weapon fire on grass.** The stamp can put weapon fire **on** grass. That grass is burned (and a neutral child added on top) by a neighbouring fire's step, not its own.
   - So a stamp in a grass field ends up with neutral fire under and around the whole patch. That fire burns **both sides**, the shooter's team included. [NEW]
2. **Ice.** If **owner >= 0** (0x497a4e-0x497a57) and the ice/water id at the fire's **own** tile is 0-3, set it to -1 (0x497a59-0x497a80). [CORRECTED: enemies melt too]
   - The tile becomes bare ground: no more slide.
   - Water (4-7) is untouched.
   - Grass children (-1) never melt.
   - Spread children of player or enemy fire do.

---

### 6. Damage to tanks (TTankSprite.DoCollision 0x491aac, fire branch 0x491cf0-0x491d4e)

**When the check runs.** Each frame in TTankSprite.DoMove (0x492244), the tank runs Collision (0x492272) unless it is:

- **dying** (+0xbc, 0x49224f), or
- **materializing** (+0xd8 > 0, 0x49225c).

The enemy override (0x494ba8) calls this first. A tank thrown by a mine has Moved/Collisioned/Visible cleared by TFlyingTank (0x49a6da-0x49a6e2) until it lands (0x49a77b). So it is neither tested nor hit. [NEW]

**Overlap.**

- Tank box: (X+3, Y+3, 26, 26). Remake: 52x52 inset 6.
- Tank box while invulnerable (+0xbd): (X-6, Y-6, 44, 44) (0x49305c).
- Fire box: its 16x16 cell (0x469e74 -> 0x468f78).
- Overlap is strict.
- The fire must be armed: Collisioned (0x468dbc), and arm <= 0 at 0x491d0d.

**The branch** (every overlapping sprite gets it in turn). [CONFIRMED]

```
if tank.fireTimer(+0xc4) > 0: return           // 0x491d04
if fire.arm(+0xc4) > 0: return                 // 0x491d0d
if SameSide(tank, fire): return                // 0x491d1b
tank.Damage(1, fire.owner)                     // vmt+0x2c = 0x492640
tank.fireTimer := (fire.owner < 0) ? 1500 : 750 // 0x491d34-0x491d48, set even if Damage did nothing
```

- **SameSide** (0x4690d0) = (a > 0 and b > 0) or (a == 0 and b == 0). A negative side is never the same side as anything. [CONFIRMED]
- **Timer.** tank.+0xc4 counts down by 20 a frame in TLifeSprite.DoMove (0x49514b). That runs at the **end** of the same DoMove. [NEW frame counts]
  - **750 -> next burn after 38 frames (0.57 s).**
  - **1500 -> 75 frames (1.125 s).**
- **One timer per tank, shared by all fires.** Several fires never stack damage. In a mixed blaze, the first hostile armed fire in sprite-list order picks the window. [CONFIRMED]

| Fire owner | Burns | Window | Rate |
|---|---|---|---|
| player 1 / 2 | enemies (side 0) | 750 | 1 HP / 38 frames (0.57 s) |
| enemy (0) | players (1/2). **Not enemies** | 750. Players also get 750 ticks of invulnerability per hit, ending the same frame | 1 HP / 38 frames (0.57 s) |
| grass chain (-1) | **everyone** | 1500 | 1 HP / 75 frames (1.125 s) |

**Damage path** (TTankSprite.Damage 0x492640). Fire damage is ordinary damage; nothing is special to fire. [NEW]

- **No effect** if HP <= 0 or the tank is invulnerable (+0xbd): spawn shield 5000 ticks for players (0x4948e3), 750 for enemies (0x494b6a), helmet, or post-hit. The window timer above is still reset.
- **Hit chain.** Recorded via 0x498b4c, skipped only for attacker < 0.
- **Survivor.**
  - Hit flash +0xd0 = 250.
  - **HitTank sound (wave 10)** (0x4926bf-0x4926d0).
  - Players: drop the body item as a cookie or lose a speed/gun level, then 750 ticks of invulnerability (0x49273c).
  - Enemies: the drop/downgrade rules (enemy_pickups_original_spec.md).
  - No "turn toward the shooter": that is only in the shell's DoCollision.
- **Kill.** Score, combo and kill text only if attacker > 0 (0x492801). So kills by enemy fire (0) or grass fire (-1) credit nobody.

---

### 7. Other interactions (all CONFIRMED unless marked)

**What fire never touches.**

- Bricks, hard brick, iron: section 2 gates. A fire on a tile that later becomes a wall burns on: fires never re-check walls.
- Water: blocks the spread only.
- **The eagle/flag** (TFlagSprite, side -1). [now PROVEN, was inferred]
  - Its DoCollision is TSprite's empty one (VMT slot 0xc = 0x468ebc), and it never starts Collision.
  - The TFireSprite class ref [0x490310] is used only by the tank fire branch (0x491cf2), the 3 constructors, and the network sprite sender, which skips fires (0x4ccff9).
  - So ground fire cannot hurt it.
  - The fire **shell** hits the flag like any shell (side -1 is never same side), and then drops fire around it.
- **Mines, cookies, explosions** (TMineSprite, TCookieSprite, TExploseSprite): no fire code reads them, and theirs never reads fire. A mine's own Collision (0x49a41b) ignores what it finds.
- **Shells** fly through fire (section 1). **Tanks** drive through it: fire never blocks (0x4919c8 blocks only tanks and the flag).

**Fire and Hold Enemy.**

- The Hold timer [0x4d74d8] is used only by the enemy think (0x494c38), the pickup that sets it (0x49593c) and the game setup (0x498018). So fires and shells keep running.
- A held enemy's DoMove still runs Collision, so **held enemies still burn**. [NEW]

**Enemy AI.** The AI never looks at fire (no grid or class reference in the think), so enemies don't steer round it. [NEW]

**Sounds.**

| Event | Wave |
|---|---|
| Fire shot | S_Fire (2) |
| Burn the tank survives | HitTank (10) |
| Shell clash the other shell survives | HitWall (12) |
| Armor-shield absorb (tanks in armor mode) | HitTank2 (11) |

There is no burning loop.

**Persistence.**

- Fires outlive their shooter.
- Heat is refunded by the shell's tank UID (0x493a2d).
- Stage reset kills every sprite and zeroes the grids (0x499e34, 0x499ee6).

**Network.**

- Clients learn about fire only from per-tile side bits (0x490870). The sprite sender skips TFireSprite (0x4ccff9).
- Unregistered spread/grass children are invisible online.

---

### 8. Consequences of enemies being side 0 (old spec assumed -1)

| Topic | With side 0 (the truth) | What the -1 assumption predicted |
|---|---|---|
| SameSide vs enemy fire | enemy-tank vs enemy-fire = same side, so **enemies never burn in enemy fire** | enemies burnt by their own fire |
| SameSide vs grass fire | -1 matches nothing, so grass fire burns enemies, **even grass fire their own shots lit** | same |
| Window vs enemy fire | players: **750 ticks, 0.57 s** | 1500 ticks, 1.125 s |
| Drawing | enemy fire **row 1 (orange), Z -1, below tanks** | row 0 (red), Z 9, above tanks |
| Spreading | enemy fire **can** spread (owner >= 0), at enemy gun level >= 1 (0x499fbd) | never |
| Ice | enemy fire **melts ice** under itself, and so do its spread children | never |
| Fire grid | enemy fire has its own grid 0x4d8a04. It restacks only with enemy fire and shares tiles with player fire | would have shared the neutral grid |
| Network | enemy fire shows as tile bit 1 | bit 2 |
| Kill credit | attacker 0: no score, combo or kill text (0x492801) | same (attacker <= 0) |
| Hit chain (side note) | attacker 0 passes 0x498b6f (only < 0 is skipped). It feeds record 0 of the player-record array: the enemy side's slot, which the fold at 0x498dc4 also walks. That slot has no corner text [UNCONFIRMED whether anything shows] | skipped |
| Enemy shells | pass through enemy tanks and don't clash with enemy shells. A fire shell from an enemy never drops on another enemy | would hit each other |
| The flag | side -1: hit by both sides' shells | same |

The same -1 error was in `docs/ice_original_spec.md` ("A player's fire melts it") and in `docs/damage_text_original_spec.md` sections 1 and 4 (an enemy weapon's attacker is 0, not -1); both fixed 2026-10-08. The remake melted ice only under the players' fire until its fire was ported (Part B).

---

### 9. Sean's early draft rules (corrected)

1. **4x4 minus corners = 12 tiles: MATCH.**
   - Anchor = the shell's top-left cell (Trunc).
   - The inner 2x2 arms first (50 ticks).
2. **5 s burn, then a random 6th second: PARTLY.**
   - Burn time depends on level: 1.33-1.71 s at L0, up to 4.71-5.09 s at L3.
   - The ragged end is the per-tile ±0.375 s fuel spread.
3. **Ring growth, shrink by one ring: NO.**
   - Restacking adds fuel to the same 12 tiles.
   - Growth is fuel spreading (section 4). It needs stacked fuel >= 7000 and moves about one tile per pulse, mostly a single ring unless the stack is huge.
4. **Range 15 tiles, then drop and ignite: MATCH.** 248 px = 15.5 cells, by lifetime.
5. **Hit a tank -> drop and ignite: MATCH.**
   - The clash also does 1 HP.
   - The patch is centred on the shell at the tank's near edge.
6. **Crossing enemy shell -> drop, ignite, weaken the shell: MATCH in effect.**
   - The rule is min-HP exchange.
   - An enemy fire shell and a player fire shell that meet both drop: two patches in two grids.

---

## Part B — The remake

**Ported (2026-10-08), rule for rule:**
- **A burning tile** (`GroundFire`) is the original's TFireSprite: its side (1 a player's, 0 the enemies', −1 burning grass, nobody's), strength (the shell's gun level), fuel in the original's ticks, and its own clock in the original's order each frame: spread, its terrain step (once), arming, burning its fuel.
- **The patch** (`LevelManager.ignite_fire_patch`, `fire_anchor`): 12 tiles round the cell under the shell's top-left corner, the middle 2x2 armed after 0.06 s, the rest 0.09 s, on open ground, grass, burned grass, water, ice and half bricks (`fire_can_lie`); fuel 1750–2249 ticks, 1500 more a level.
- **The two grids**, players' and enemies' (`_fire_grid`): a shell on its own side's fire feeds it (`GroundFire.restack`), the other side's burns beside it.
- **Spreading** (`spread_fire`): a side's fire of strength 1 or more with 7000 ticks of fuel or more gives each side of it a quarter of what it had above the fire there, a new unregistered fire if there's none, every 600 − 100·strength ticks; not onto walls (half and quarter bricks aside) or water.
- **The terrain step** (`fire_terrain_step`), 500–999 ticks after a fire starts: the grass beside it burns grey with nobody's fire on it, which does the same in turn; a side's fire melts the ice under itself.
- **Burning tanks** (`_burn_tanks`), every frame: a tank's box is its picture less 6 px a side (while it blinks, its picture and 12 px more a side), and the first armed fire it strictly overlaps that isn't its side's burns it, one point, as any hit (`BaseTank.burn`); then none for 0.5625 s, 1.125 s after burning grass, even if it blinked. Not a tank appearing, dying or thrown by a mine. A player's fire burns enemies, the enemies' fire players, burning grass everyone.
- **The shell:** damage 1 at every level; 622 px/s, slowing by 178 px/s a second, dropping its patch 496 px out (`Bullet._change_speed`, and `Bullet.flight` for a joining player's screen); its gun level is the fire's strength (`Bullet.fire_level`).
- **Drawing:** burning grass red, over the tanks and the grass (grass_original_spec.md); the enemies' orange and the players' yellow, under them (the sheet's files r1, r2, r3: the original's rows 0, 1, 2).

**What it replaced:** a field of 12 tiles that grew a ring with each shell up to 8x8, burning 5 s a ring and then shrinking a ring at a time; one point a second from any fire; fire shells of 2 at gun levels 3 and 4; only the players' fire melting ice; burning grass started from the field's edge, burning 3 s and spreading every 0.5 s.

**Kept the remake's:**
- **The fire rate:** the remake's cooldowns by gun level (0.27–0.135 s). The original's go by the speed level, 0.54 / 0.45 / 0.36 / 0.27 s, as its plain gun's.
- **What a joining player sees:** every burning tile is sent to it. The original sent only the grids' tiles, so its spread and burning grass didn't show online.
- **A safety cap** of 2000 burning tiles; the original had none, fuel being what stops a fire.

**Tests:** scenes/test/fire_test.tscn (the patch and its arming, where fire lies, fuel by level, feeding, the other side's fire beside, spreading, its amounts and how often, burning tanks and the box, a blinking tank's, grass, ice, the shell, meeting shells); scenes/test/grass_fire_test.tscn (rows by side, burning grass walking along a strip, burning out, burning both sides).

## Still unconfirmed

1. Wall ids 0-7 and 16-23 have no known meaning. Both gates treat them as open ground.
2. Item bricks 160/170/171 (remake A1/AB/AC): both gates exclude them, and TileHit lets the shell pass over them. Not checked whether these raw ids survive into the live wall layer or are converted at load.
3. Tie-breaks inside one frame: which of several overlapping fires sets a tank's window; whether a fire armed this frame hurts a tank moved earlier in the list. These follow sprite-list (creation) order, not checked case by case.
4. Hit-chain record 0 for enemy attackers (section 8): whether anything visible or scored comes of it.

# Mine weapon: how the original works

The mine system of `Tank.exe` v1.22, read from the disassembly and checked
against the game's readme. Units are the original's unless marked *remake*. One
original cell is 16 px and one remake tile is 32 px, so the grids line up
cell for cell. The engine tick is 0.75 ms, and there are 20 ticks per 15 ms logic
frame.

`scripts/tests/mine_test.gd` checks every rule below that the remake ports
(`Godot --headless res://scenes/test/mine_test.tscn`).

**This page replaces an earlier draft**, which had several things wrong. The
real rules:
- Levels run **0-3**, not 1-4.
- **Bullets never** set a mine off; only explosions do.
- Mines **do** chain, across sides.
- A mine sits on a **2×2 block, centred on a tile corner**, not on a tile centre.
- The "proximity indicator" is how **enemy mines stay hidden**.
- The mystery "stun" is a **quarter-speed slow**.
- The "type gating" is really the **add-on rules**.

## 1. Laying a mine

`TTankSprite.Fire` (`0x004931e0`), the branch for weapon type 5.

**Where it goes.**

1. The tank's own 2×2 block is `c = (Round(X/16), Round(Y/16))`. X and Y are the
   tank's top-left corner, and `Round` is Delphi's, which sends halves to the
   even neighbour.
2. The game tries up to 12 spots on a ring around the tank:
   `spot = c - RING[(3*facing + ORDER[i]) mod 12]`, where facing is 0 up, 1 right,
   2 down, 3 left.
   - `RING` (`0x004d29d0`) = (0,-2) (1,-2) (2,-1) (2,0) (2,1) (1,2) (0,2) (-1,2)
     (-2,1) (-2,0) (-2,-1) (-1,-2)
   - `ORDER` (`0x004d2d64`) = 0, 1, -1, 2, -2, 3, -3, 4, -4, 5, -5, 6
3. The first spot tried is **straight behind**. The next two are shifted one
   cell either way (one side, then the other). The search works round both
   sides of the tank and ends **straight ahead**. Every spot is 2 cells out.
4. The mine goes at `(tx*16+8, ty*16+8)`. That centres its 16 px image on the
   corner its 2×2 block shares, **32 px (remake 64 px) from the tank centre**.
   Behind a tank that is sitting still, that leaves an 8 px gap.

**When a spot is refused.** A spot is skipped if any of these holds:
- A wall is on any of its 4 cells. The test is FG code ≥ `0x18`, so grass is
  fine.
- Water is on any of its 4 cells (BG code ≥ 4). **Anti-water tanks lay on water
  anyway.**
- A mine is already keyed to that block. The key is the top-left cell, in the
  mine grid at `0x004db404`.
- Something collidable is close by. The test takes each Collisioned sprite's
  corner + 16 px (the centre of a tank, the base or a bonus) and refuses the spot
  if that point lies in `Bounds(tx*16-8, ty*16-8, 48, 48)`. This counts armed
  mines, whose point sits off-centre. It also counts the laying tank itself: one
  caught between cells can block its own rear slots, so the mine lands at the
  side.

If all 12 spots are refused, nothing is laid, and no ammo or cooldown is spent.

**What a laid mine inherits.** It takes the layer's side. Its level is
`SetLevel(tank.gun)`, the tank's gun upgrade level **0-3**.

**Sound.** `S_Mine` plays on every successful lay, **for enemies too**. The
fire tail (`0x0049354d`) sounds every special weapon from any tank. Only the
plain gun is silent for enemies.

**Off-field spots.** The map reader returns -1 for cells off the field, and -1
passes both terrain checks. So the original can drop a mine partly or wholly
off-field, where no tank can reach it. **The remake skips those spots.**

## 2. The mine

`TMineSprite` (VMT `0x004903d8`, `Create` `0x0049a26c`, `DoMove` `0x0049a3e4`).

**Sprite.** Image 5, `B_Mine`, is 5 rows of four 16 px frames.
- Row = level (`AnimStart = 4*level`):
  - Row 0 is a plain ball, shrinking.
  - Row 1 is spiked.
  - Row 2 has a red centre.
  - Row 3 turns its spikes into a ring.
  - Row 4 is the ringed loop.
- A new mine is **invisible and inert** (Visible = Collisioned = 0) while its row
  plays once, at 0.01 frame per tick (75 ms a frame).
- When the frame first rounds to 3 (**2.5 frames = 0.1875 s**), the mine
  becomes visible and armed. It then holds frame 3, which is why a settled mine
  is the small ball.
- A **level-3** mine then switches to row 4 and loops it at 0.002 frame a tick,
  1.5 s per loop.

**Enemy mines are hidden** (side ≤ 0). The per-frame code, which runs while the
frame rounds to 3, computes a distance in 8 px steps:

```
d = min( Round(dist(mine, base)/8) - 6,
         Round(dist(mine, player)/8) - (8 if airborne, else 4 with anti-ice, else 0) )
alpha = min((16 - d) * 16, 192);  Visible = alpha >= 64
```

Distances are centre to centre, and there is one player term for each player
tank.
- A player sees an enemy mine within **100 px** (remake 200). At that edge the
  alpha is 64, and it reaches the full 192 from 36 px in.
- The base reveals mines within 148 px.
- A tank that is **flying** sees 64 px further.
- An anti-ice tank sees 32 px further.
- The flag `+0x12c` that marks a tank as airborne is set in the tank's
  constructor and on landing, and cleared by `TFlyingTank`.
- Player mines are always drawn fully opaque.
- A level-3 enemy mine re-checks only during the part of each ring loop that
  rounds to frame 3, so it can lag up to about 1.1 s behind.

## 3. A tank touches a mine

`TTankSprite.DoCollision` (`0x00491aac`). L is the mine level. The add-on byte
`+0x12d` is 1 anti-water, 2 anti-ice, 3 moon shield or 4 memory-save.

1. An **anti-ice tank ignores mines below L3**. It rolls over them, and the mine
   stays.
2. The mine's own side never sets it off.
3. **The mine goes off**, spawning its blast.
4. **Slow.** This applies at L ≥ 1, unless the tank is invulnerable, has
   anti-ice, or has memory-save and L < 3. The slow quarters the tank's move
   speed (`0x00492f24`: `speed >> 2`).
5. **Flight.** This applies at L ≥ 2, unless the tank has memory-save.
   1. The tank goes airborne (`+0x12c = 0`).
   2. Unless it is invulnerable, it pays a direct hit:
      - Anti-ice is torn off, with no damage.
      - Any other add-on is torn off, plus `Damage(L-2)`.
      - With no add-on, `Damage(L-1)`.

      A torn-off add-on is simply cleared; no cookie drops.
   3. `TFlyingTank` throws it. The launch speed is 5 × (tank centre − mine
      centre), rising speed L+2, gravity −5 and spin L×200. The flight lasts
      1.2 s at L2 and 1.5 s at L3.
   4. It lands facing where the spin stopped. A **neutral** blast (side −1) goes
      off at the landing spot, at the **victim's own gun level**, and hits
      everyone, the victim included.

An airborne tank is uncollidable, so **the mine's own blast misses a tank it
threw**. In total a flown tank takes the direct hit plus its landing blast.

| Mine | Plain tank | Anti-water / moon shield | Anti-ice | Memory-save |
|---|---|---|---|---|
| L0 | blast | blast (a front shield blocks it) | ignored | blast |
| L1 | blast + slow | blast + slow | ignored | blast |
| L2 | slow + 1 HP + flight | slow + add-on lost + flight | ignored | blast |
| L3 | slow + 2 HP + flight | slow + add-on lost + 1 HP + flight | anti-ice lost + flight | blast + slow |

This matches the readme. It also shows the readme overstating one rule:
memory-save **is** slowed by L3.
- AntiSkid is safe on enemy LV0-LV2 mines.
- The moon shield clears LV0 mines safely, because its front blocks the L0
  blast.
- Memory of Sea never flies.

**The slow ends only on death, or on a pickup:**
- **Add-on cookies** (5-8) free the tank that takes them.
- **MAX** (4) frees every player.

(When an *enemy* takes MAX or bonus 18, all enemies are freed. The remake has no
enemy pickups.)

## 4. Going off, and chains

`Detonate` (`0x0049a360`):
- Plays `ExploseMine1`/`2` at L ≥ 2 only; L0 and L1 mines go off silently.
- Spawns a `TExploseSprite` at the mine's level and side, centred on the mine.
  That is the explosion weapon's blast, with power 250 + 25L and falloff
  60 − 5L per half-cell.

**Mine chains.** A blast sets off a mine from its `DoCollision`, `0x00497550`.
Only explosions do this, which matches the readme's "explosive shells detonate
mines of equal or lower level":
- The mine must be armed.
- The mine must not be on the blast's side. A neutral landing blast is on
  neither side.
- The blast level must be ≥ the mine level.
- Then, with `heat` as defined below:
  `level + heat - (2 if level <= 0 else 3) >= mine level`.

`heat` (`0x004972a4`) is `Round(best * power / 100000 + 0.25)`. Here `best` is
the hottest cell overlapping the mine, and each cell holds the best of its four
half-cells, scaled to per-mille of power. Each half-cell stores
`Round(power - d * falloff)`, where d is its distance from the blast centre in
half-cells. Walls shadow cells, and the heat counts only while the wave is
passing.

In practice:
- A mine of the **same level** goes off only from the next tile.
- A blast one level stronger reaches 2 tiles.
- A blast 2-3 levels stronger reaches 3-4 tiles.

Your own blasts never touch your own field, but an enemy mine you set off can
set off yours.

## 5. Enemy mine levels

The enemy spawn (`0x00499f30`) sets:
`gun = clamp(TYPE_GUN[type] + DIFFICULTY_BONUS[difficulty], 0, 3)`.

- `TYPE_GUN` (`0x004d2af0`) runs by family of 4 types: plain 0 1 1 2, rapid
  0 1 2 3, fire 0 1 2 3, AP 0 1 1 2, explosion 0 1 2 3, mine 0 1 1 2.
- Difficulty runs 0-5, and a new game starts at 2. `SetDifficulty`
  (`0x00499130`) copies an 8-value record from `0x004d2860`. The gun bonus is
  −1 0 0 0 +1 +1, and the speed bonus is −1 −1 0 +1 +1 +1.
- The per-type add-on table (`0x004d2b50`) matches the remake's `TYPE_ADDONS`
  exactly.

So mine tanks 21-24 lay L0/L1/L1/L2 mines up to HARD, and L1/L2/L2/L3 on EXPERT
and INSANE. The remake's difficulty 1-5 is the original's 1-5; the save
importer copies it straight across. The remake caps enemy mines at L2 (see
section 6).

## 6. What the remake does differently

- **Enemy mines stop at level 2** (`EnemyTank.ENEMY_MINE_MAX_LEVEL`), by design.
  The original's type-24 tank lays ringed L3 mines on EXPERT and INSANE; in the
  remake it lays L2 there. Only the mine is capped: the tank's gun level stays
  3, and that still sets its landing blast after a mine flight. Player mines
  still reach L3.
- **The flight** is the original's, integrated the same way
  (`BaseTank._update_flying`). The tank moves at 5 × its offset from the mine
  centre per time unit, so driving into a mine (contact about 22 px short of its
  centre) throws it back the way it came: about 11 cells at L2 and 14 at L3. It
  never lifts off its spot on screen; it only grows to (altitude + 1) times its
  size, 2.6× and 3.5× at the top, while it tumbles. The one change is the edge
  clamp. The original kept the tank's centre 32 px from the left and top edges
  but let it reach the right and bottom edges; the remake keeps the whole tank
  on the field. (Before 2026-09-23 the remake threw tanks to a random spot.)
- **Chains** are judged once, when the blast appears. Each chained mine then
  goes off as the wave ring reaches it, 50 ms a tile. The original re-tests
  every frame while the wave passes, which gives the same result.
- **The crowd check** uses bullets' centres. The original used their corner +
  16 px.
- **Not modelled:** off-field spots (skipped), enemy pickups, and the
  random "aim at targets" flag set at spawn (`+0x13c`; mine tanks get it at a
  third of the usual odds).
- **Other enemy families' gun levels** do not use the table in section 5. The
  rapid tanks take theirs from `tank_table.xlsx` (`CookieData.TYPE_WEAPON_LEVELS`),
  and fire, AP and explosion tanks are still level 0.
- **Laying cooldown.** The original adds heat `350 × (6 − speed level)`; the
  remake keeps its own per-level cooldowns in `CookieData.MINE_FIRE_CONFIG`.

## Addresses

| What | Where |
|---|---|
| `TTankSprite.Fire`, mine branch / common tail | `0x004931e0` / `0x0049354d` |
| Placement terrain checks: walls / water | `0x00492cdc` / `0x00492b6c` |
| Ring table / try order | `0x004d29d0` / `0x004d2d64` |
| Mine grid | `0x004db404` |
| `TMineSprite.Create` / `DoMove` / `Detonate` / `SetLevel` | `0x0049a26c` / `0x0049a3e4` / `0x0049a360` / `0x0049a5d4` |
| `TTankSprite.DoCollision` (mine part) | `0x00491aac` |
| Slow flag set / speed setter | `0x00493644` / `0x00492e08` |
| `TFlyingTank.Create` / landing | `0x0049a5ec` / `0x0049a740` |
| Blast sets off a mine / heat lookup / heat grid | `0x00497550` / `0x004972a4` / `0x004967cc` |
| Enemy spawn / `SetDifficulty` / difficulty records | `0x00499f30` / `0x00499130` / `0x004d2860` |
| Pickup dispatch (type → handler bytes, jump table) | `0x004959d4`, `0x004959ed` |

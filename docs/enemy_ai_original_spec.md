# Enemy AI — the original's rules, and the remake's

How Tank.exe v1.22's enemy tanks move, turn and fire, rule for rule, read from the binary (`Tank V1.22/Tank.exe`), and what the remake ported. Sean found (2026-10-08) that enemies under a wall with gaps only at its far ends never came down (his saves: stage 81 "MARIO classical" and stage 55 "Love ICE" of his 114-stage map). The remake's own AI steered every enemy toward the eagle and turned aside when blocked, so they shuffled under the wall. The original's AI was researched again from the code and its moves ported (Part B).

Addresses are Tank.exe virtual addresses.

## Part A — The original

**Units and conventions.**
- 1 tick = 0.75 ms at 100 % game speed. A logic frame is 20 ticks (15 ms). An **AI step** runs
  every other frame: 40 ticks = 0.03 s. Seconds below are at 100 % game speed.
- **Cells.** The map is 42 × 32 cells of 16 original px (one remake tile of 32 px). Map cell
  (x, y) is stage tile (x − 1, y − 1). Rows and columns 0 and 41/31 are the steel border
  (id 64). The base (eagle) is map cells x 20–21, y 29–30, i.e. stage tiles 19–20, 28–29.
- **A tank** is 2 × 2 cells. Its X, Y (doubles at +0x58, +0x60) is the sprite's top-left in
  map px, so the playfield starts at (16, 16). The AI works on its **rounded cell**
  cx = Round(X/16), cy = Round(Y/16). Round is banker's rounding (FPU default, 0x4029b8).
- **Directions**, the table at 0x4d2970: 0 up (0, −1), 1 right (1, 0), 2 down (0, 1),
  3 left (−1, 0).
- **Commands** to the tank (0x49180c): 0–3 drive that way, 4 stop, 5 fire the plain gun,
  6 fire the special weapon.
- `Random(n)` (0x402b8c) returns 0 … n−1 from Delphi's LCG.
- **Wall ids** (wall layer `[0x4d74cc]`; Stage.dat byte = id; the remake's code = id + 1):

  | Ids | What |
  |---|---|
  | 8–11 | grass |
  | 12–15 | burned grass |
  | 24–27 | brick |
  | 28–39 | partial brick |
  | 40–43 | hard brick, full |
  | 44–55 | hard brick, damaged |
  | 56–59 | iron |
  | 60–63 | super steel |
  | 64 | border |
  | 160, 170, 171 | hidden-item bricks (remake codes A1/AB/AC) |

  Ice/water layer `[0x4d74c8]`: ice 0–3, water 4–7, border 64. Empty = −1 in both layers.
- **Types.** The original's type is 4–27 (remake id + 3). An **odd original type is an even
  remake id**: the upgraded tank of each pair.

**Tank fields used below.**

| Field | Meaning |
|---|---|
| +0x58 / +0x60 | X / Y (double, map px, top-left) |
| +0x110 | type 4–27 |
| +0xbc | dead |
| +0xbd | invulnerable |
| +0xd0 | hit timer, ticks |
| +0xd4 | invulnerability, ticks |
| +0xd8 | materialising timer |
| +0xdc | weapon 0–5 |
| +0xe0 | speed, integer |
| +0xe4 | max speed |
| +0xe8 | acceleration a |
| +0xec | facing 0–3 |
| +0xf0 | on ice |
| +0xf4 | most shells in flight |
| +0xf8 | shells in flight |
| +0xfc | gun heat |
| +0x100 | not blocked by a tank (this frame) |
| +0x11c | special ammo |
| +0x12c | on the ground (not on a mine flight) |
| +0x12d | add-on: 1 AmphiTank, 2 AntiSkid, 3 Shield of Moon, 4 Memory of Sea |
| +0x130 | special-weapon timer T |
| +0x134 | stored command 0–4 |
| +0x138 | AI step counter |
| +0x13c | hunt flag |

The difficulty fields f0 … f7 are the globals 0x4d74e0 … 0x4d74fc (difficulty_original_spec.md).

---

### 0. In short

- **Two kinds of enemy, decided at spawn.**
  - A **hunter** (flag +0x13c) follows a cost map spread out from the base.
  - A **wanderer** drives at random, with a pull downward.
  - Nothing else steers an enemy. There's no chasing or aiming at players, no seeking or
    avoiding items, and no reaction to the base being attacked.
- **The hunter.**
  - Where it decides: in the half cell before each grid line it is driving toward, and whenever
    it is stopped.
  - What it compares: the sum of the map over its 2 × 2 footprint, at its rounded cell and at
    the four one-cell shifts. It takes the lowest. Each tie is taken 1 time in 3. If nothing is
    lower or equal, it stops.
  - The map treats iron as passable at 4096 a cell, and super steel as effectively impassable
    (100000).
  - It closes 1-cell gaps between iron, super steel and water ("narrow" cells), and treats
    stopped tanks as obstacles.
  - So hunters drive around unbreakable walls through any gap at least 2 cells wide, however
    far away. They go through bricks, shooting them as they push.
- **The wanderer.**
  - At random moments (1 in P per step), or when blocked or facing the field edge, it picks
    Random(5) among up/right/down/left/stop.
  - It never reverses, except to go down. It never picks stop twice in a row.
  - The edge rule makes it re-pick exactly at the far ends of a wall, so it finds end gaps.
- **Firing.**
  - The plain gun fires with chance 1/P per step, along the tank's last commanded direction.
  - The special weapon fires in bursts.
  - When a player's shell hits an enemy and it survives:
    - half the time it turns toward the shot;
    - for 250 ticks it changes nothing and fires twice as often.

---

### 1. Where the AI runs (timing and entry points)

**The frame loop** (DXTimerTimer 0x4c7960; one 20-tick frame per pass of 0x4c7aa4 … 0x4c7d4f):

1. Frame counter +0x418 += 1.
2. On even frames (`test [form+0x418],1`, 0x4c7bb7): for every tank in the manager's tank list
   (manager `[0x4d74d4]` +0x1e0, players and enemies alike), call VMT slot 12, the "think".
   For TEnemyTank that's **0x494c38**.
   - The TTankSprite constructor adds a tank to the list (0x4917e2) and Destroy (0x493108)
     removes it.
3. In the demo (state 1) or play (state 5), every frame: manager tick 0x498dac, which first runs
   the **distance-map scheduler 0x499dd0** (§3.2). The rest of 0x498dac is score bookkeeping.
4. Sprite engine Move(20) (0x4c7d20): every sprite's DoMove. For tanks that's **0x492244**: the
   movement step, with collisions (§6).

**So:**
- Enemies decide every 0.03 s.
- Maps are rebuilt between decisions.
- Movement runs every 15 ms, as two moves per decision.

**Also in the inherited think 0x491d7c**, which the enemy's think calls first:
- A tank still materialising (+0xd8 > 0; set to 1000 at construction, 0x49179a) loses 33 per
  AI step. That's 31 steps, about 0.93 s, and then its sprite is set up.
- Otherwise the gun heat +0xfc drops by 60 per step, while above −180.
- While materialising, both the think and DoMove skip the tank.

---

### 2. The think routine (TEnemyTank VMT slot 12 = 0x494c38)

TEnemyTank's VMT is 0x4901c8, instance size 0x140. It overrides these slots:

| Slot | Address | What |
|---|---|---|
| 3 | 0x494ba8 | DoCollision |
| 7 | 0x494b34 | Create |
| 10 | 0x49509c | Die |
| 12 | 0x494c38 | Think |

**The constructor (0x494b34):**
- Command +0x134 = Random(4) + 1, so right, down, left or stop.
- Special timer +0x130 = 120.
- Invulnerable 750 ticks.
- Side +0x74 = 0.
- Gun and speed set to 0, then the spawn routine sets them.
- Facing +0xec and speed +0xe0 stay 0, i.e. facing up and standing still.
- Spawn 0x499f30 then sets type, weapon, ammo, HP, speed, gun and add-on, and rolls the hunt
  flag (§4.1).

Complete flow, in order:

```pascal
procedure TEnemyTank.Think;                                    { 0x494c38, every AI step }
begin
  inherited Think;                                             { 0x491d7c: materialise / gun heat }
  { 0x494c4a..0x494cee: hold-web overlay frames, cosmetic }
  if Dead then exit;                                           { +0xbc, 0x494cee }
  if not OnGround then exit;                                   { +0x12c, 0x494cfb: on a mine flight }
  if EnemyHoldTicks > 0 then exit;                             { [0x4d74d8], 0x494d08: Hold Enemy }
  if Materialise > 0 then exit;                                { +0xd8, 0x494d15 }

  if Odd(Type) then P := f4 else P := (3*f4) div 2;            { 0x494d22 }
  cx := Round(X/16);  cy := Round(Y/16);                       { 0x494d54 }
  Inc(StepCounter);                                            { +0x138, 0x494d76 }

  { ---------------- hunter, 0x494d7c ---------------- }
  if HuntFlag and (HitTicks <= 0) then begin                   { +0x13c, +0xd0 }
    if Speed = 0 then Decide := True                           { +0xe0 }
    else case Facing of                                        { +0xec }
      0 {up}:    Decide := cy*16 <= Y;                         { 0x494db7 }
      1 {right}: Decide := cx*16 >= X;                         { 0x494dce }
      3 {left}:  Decide := cx*16 <= X;                         { 0x494de5 }
      else {down}: Decide := cy*16 >= Y;                       { 0x494dfc }
    end;
    if not Decide then goto Issue;                             { keep the stored command }
    case AddOn of                                              { +0x12d, 0x494e19 }
      1: Map := AmphiMap;      { 0x4dde04 }
      2: Map := AntiSkidMap;   { 0x4df304 }
      else Map := NormalMap;   { 0x4dc904 }
    end;
    Best := Sum2x2(Map, cx, cy);                               { 0x494be0 }
    if Best >= 400000 then goto Wander;                        { 0x494e50 }
    Cmd := 4;                                                  { stop }
    for i := 0 to 3 do begin                                   { up, right, down, left }
      S := Sum2x2(Map, cx + DX[i], cy + DY[i]);
      if S < Best then begin Best := S; Cmd := i end
      else if (S = Best) and (Random(3) = 0) then Cmd := i;    { 0x494e95 }
    end;
    Command := Cmd;                                            { +0x134 }
    goto Issue;
  end;

  { ---------------- wanderer, 0x494ebd ---------------- }
Wander:
  Allowed := [0, 1, 2, 3, 4];                                  { byte 0x1f at 0x495088 }
  if cx <= 1  then Exclude(Allowed, 3 {left});
  if cx >= 39 then Exclude(Allowed, 1 {right});
  if cy <= 1  then Exclude(Allowed, 0 {up});
  if cy >= 29 then Exclude(Allowed, 2 {down});
  if HitTicks > 0 then goto Issue;                             { 0x494f15: no re-pick while hit }
  if (Speed <> 0) and (Facing in Allowed)
     and (Random(P) <> StepCounter mod P) then goto Issue;     { 0x494f22..0x494f54 }
  repeat                                                       { 0x494f56 }
    R := Random(5);
    if not (R in Allowed) then continue;
    if R = 4 then begin
      if Command <> 4 then break;                              { no stop after stop }
    end
    else if (R <> (Command + 2) and 3) or (R = 2) then break;  { no reverse, except down }
  until False;
  Command := R;

  { ---------------- issue and fire, 0x494fa5 ---------------- }
Issue:
  DoCommand(Command);                                          { 0x49180c, §6.1 }
  Pf := P;
  if HitTicks > 0 then Pf := P div 2;                          { 0x494fb2 }
  if Random(Pf) = StepCounter mod Pf then begin
    DoCommand(5);                                              { plain gun }
    SpecialTimer := 3*P;                                       { +0x130, 0x494fe9 }
  end else begin
    T := SpecialTimer;
    if Random(T) = StepCounter mod T then begin                { 0x494ffa }
      if (Weapon = 5 {mine}) and (Random(5) <> 0) then DoCommand(5)
                                                   else DoCommand(6);
      if T < 2 then SpecialTimer := 3*P                        { 0x495041 }
      else if T < 3*P then Dec(SpecialTimer)
      else SpecialTimer := f7 + 6;                             { 0x49506c }
    end;
  end;
end;

function Sum2x2(Map, x, y): Integer;                           { nested, 0x494be0 }
  Result := Map[x][y] + Map[x+1][y] + Map[x][y+1] + Map[x+1][y+1];
```

**Notes on that flow.**
- **"Random(P) = StepCounter mod P"** is simply a 1-in-P chance per step.
- **P**, in AI steps, by difficulty 0–5 (f4 = 80, 65, 50, 40, 32, 25):
  - odd original types (remake even ids): 80, 65, 50, 40, 32, 25;
  - even original types (remake odd ids): 120, 97, 75, 60, 48, 37.

  At medium that's 1.5 s or 2.25 s.
- **A hunter that isn't at a decision point** just re-issues its stored command. That holds even
  when its footprint is unreached: the wander fallback is only reached at decision points, so an
  "unreached" hunter re-picks less often than a true wanderer.
- **A hit freezes all choice.** While HitTicks > 0, neither branch changes the command. The tank
  keeps driving (or pushing) the way it was told for 250 ticks. The earlier summary said "just
  hit → wanders"; that is wrong (§10).

---

### 3. The walking-distance map

#### 3.1 Grid and storage

- Three arrays of 42 × 32 dwords, `map[x][y]` at `base + 128·x + 4·y`:

  | Map | Address | Used by |
  |---|---|---|
  | normal | 0x4dc904 | every tank whose add-on isn't 1 or 2 |
  | AmphiTank | 0x4dde04 | add-on 1 (anti-water) |
  | AntiSkid | 0x4df304 | add-on 2 (anti-ice) |

  They are zeroed at unit start (0x49ad94).
- **One value per cell**, not per tank position. A tank reads the sum of its 4 footprint cells.
- **Which tanks use which map.** The add-on byte decides (0x494e19). Shield of Moon (3) and
  Memory of Sea (4) use the normal map. Per type (table 0x4d2b50):
  - AmphiTank: remake ids 2, 16, 18;
  - AntiSkid: remake ids 6, 20, 22.
  - Any enemy that picks up an add-on switches maps at once.

#### 3.2 When it's built (0x499dd0)

The manager's counter +8 drops by 1 every frame (15 ms) in demo or play.

| Counter | What happens |
|---|---|
| 180 | build the AmphiTank map (mode 1) |
| 120 | build the normal map (mode 0) |
| 60 | build the AntiSkid map (mode 2) |
| ≤ 0 | build the normal map, counter := 240 |

- **So** the normal map is rebuilt every 120 frames (1.8 s), and the other two every 240 frames
  (3.6 s).
- **At the start of play** the manager reset 0x499688, called from 0x4c9a19, sets the counter to
  0 and runs the scheduler once. That builds the normal map at once; the other two follow
  0.9 s and 2.7 s later. That's before the first enemy can move: first wave at 3 s, plus
  0.93 s materialising.
- **Nothing else rebuilds a map.** A broken wall or a moved tank reaches the AI only at the next
  scheduled build (0x490eec has no other callers).

#### 3.3 The builder (0x490eec(map, mode))

Mode 0 normal, 1 AmphiTank, 2 AntiSkid.
- **Queues.** Four Contnrs `TQueue`s (FIFO: PushItem inserts at index 0, PopItem takes the last).
  - Q1: line of fire
  - Q2: the rest
  - Q3: tanks
  - Q4: narrow cells
- **Push(q, x, y, v)** (0x490ea4) writes `map[x][y] := v` and enqueues (x, y, v).
- **The procedure is a label-correcting search.** It is not a BFS, and it is order-dependent
  enough that a port should copy it exactly, the order of its queues included.

```text
Phase 1 (0x490f4e)   for y in 0..31: for x in 0..41:
    blocked[x][y] := wall in 56..64  or  (mode <> 1 and ground in 4..7)   { iron, super steel, border, water }
    if x in {0,41} or y in {0,31}:             map := -4                 { border }
    elif x in 20..21 and y in 29..30:          Push(Q1, x, y, 0)         { the base = the only sources }
    elif x in 19..22 and y in 28..30:          map := -1                 { ring round the base }
    else:                                      map := -2                 { ordinary }
Phase 2 (0x491029)   lines of fire above the base:
    for x in 19..22: for y = 27 down to 1: if blocked[x][y] break; map[x][y] := -1
Phase 3 (0x49106d)   lines of fire beside the base:
    for y in 28..30: for x = 18 down to 1:  if blocked break; map := -1
                     for x = 23 up to 40:   if blocked break; map := -1
Phase 4 (0x4910dc)   "narrow" cells, for y in 0..29: for x in 2..39:
    skip if x in 19..22 and y in 28..30; skip unless blocked[x][y]
    for e in [E, SE, S, SW] (table 0x4d29a0; prev/next = the neighbouring entries of the
             8-direction table 0x4d2990 = N, NE, E, SE, S, SW, W, NW):
        n := (x,y) + e;  if blocked[n] continue
        if blocked[(x,y) + 2e] or blocked[n + prev(e)] or blocked[n + next(e)]:
            Push(Q4, n, -6)
Phase 5 (0x4911d8)   tanks as obstacles: for every tank in the list, players included:
    if Speed > 100 or Dead: skip
    tx := Round(X/16); ty := Round(Y/16)
    Push(Q3, (tx,ty), -5); Push(Q3, (tx+1,ty), -5); Push(Q3, (tx+1,ty+1), -5); Push(Q3, (tx,ty+1), -5)
Phase 6 (0x491289)   while Q1 not empty: (x,y,v) := Pop(Q1)
    if map[x][y] <> v: continue                                  { stale }
    for d in up, right, down, left:
        n := (x,y)+d; cur := map[n]
        if cur < -2: continue                                    { border, tank, narrow: impassable }
        c := Cost(n, firstQueue = True)
        if cur >= 0 and cur <= v + c: continue
        if cur >= -1: Push(Q1, n, v + c)                         { line of fire, or an improvement }
        else:         Push(Q2, n, v + c)                         { first touch of an ordinary cell }
Phase 7 (0x49137f)   while Q2 not empty: (x,y,v) := Pop(Q2)
    if v <> -1 and map[x][y] <> v: continue
    for d in up, right, down, left:
        n := (x,y)+d; cur := map[n]
        if cur < -2: continue
        c := Cost(n, firstQueue = False)
        if cur >= 0 and cur <= v + c: continue
        Push(Q2, n, v + c)
Phase 8 (0x491449)   border cells := 100000
Phase 9 (0x491491)   tank cells, while Q3 not empty: (x,y) := Pop(Q3)
    best := 0
    for d in 4 dirs: walk from (x,y) along d until map >= 0; if best < that < 100000: best := that
    map[x][y] := best > 0 ? best : 100000                        { the HIGHEST nearby value }
Phase 10 (0x49155a)  narrow cells, while Q4 not empty: (x,y) := Pop(Q4)
    s := sum over the 4 dirs of the first map >= 0 walking along d
    map[x][y] := s div 4                                         { the AVERAGE, walls' values included }
Phase 11 (0x4915e6)  for y in 1..30: for x in 1..40: if map < 0: map := 100000
```

**Cost(x, y, firstQueue)** (0x490db0) is the cost of entering a cell.

| Cell (wall layer) | Q2 (rest) | Q1 (line of fire, ×2/3) |
|---|---|---|
| empty, grass, burned grass (−1, 0–23) | 3 | 2 |
| brick 24–27 | 8 | 5 |
| partial brick 28–39 | 6 | 4 |
| hard brick, full, 40–43 | 16 | 10 |
| **hard brick, damaged, 44–55** | **3** | **2** |
| iron 56–59 | 4096 | 2730 |
| super steel 60–63, border 64 | 100000 | 100000 (no ×2/3) |
| hidden-item bricks 160/170/171, other ids | 3 | 2 |

Then the ground layer adds, on top of any of those except 100000:
- **Water 4–7, unless AmphiTank (mode 1):** +6144 in Q2, +4096 in Q1, and it returns.
- **Ice 0–3, unless AntiSkid (mode 2):** +12 in Q2, +8 in Q1.

#### 3.4 What the map means for a 2 × 2 tank

**The sources.** Only the 4 base cells start at 0. Everything is distance from the base, as a
cost of cells entered.

**Lines of fire** (−1 cells) are where a tank can shoot the base from:
- the four columns over the base, x 19–22, up to the first blocked cell;
- the three rows 28–30, left and right, out to the first blocked cell.

They're searched first and at 2/3 cost, so they're cheap corridors. Hunters make for the nearest
line of fire and drive along it toward the base. Bricks and hard bricks don't end a line; only
iron, super steel, the border and water do (water not for AmphiTank).

**How a tank's width is handled.** Not per footprint: the search is per cell. Two rules stand in
for the width.
1. **Narrow cells.** A free cell squeezed between blocked cells (iron, super steel, border,
   water) is marked −6 (phase 4), and the search can't pass it. In effect a 1-cell gap between
   such cells is closed. Its value is filled in later as an average of its surroundings, wall
   values included, so it's high.
   - It's a heuristic. It looks only "forward" from each blocked cell (E, SE, S, SW).
   - It skips blocked cells in column 1 and 40 and in row 30, and the base area. The left and
     right borders are never used as the first wall, only as the second.
   - Example: in a wall with 1-cell gaps at its ends, it marks the cell under the gap, not the
     gap itself. That still closes it.
   - **2-cell gaps stay open**, including gaps against the field edge (§9).
2. **The sum.** The hunter sums its 2 × 2 footprint, so a step that would put any footprint cell
   on iron (4096+) or super steel (100000+) looks expensive.

**Bricks and hard bricks are cheap walls**, not obstacles: hunters route through them and break
them by firing (§4.3).

**Tanks as obstacles.**
- Any tank, player or enemy, moving at speed ≤ 100 is an obstacle cell block (−5) for the search
  (phase 5): standing, braking, or blocked.
- **The hunter itself is included.** After the search the tank's cells get the highest value seen
  around them, so a stopped tank is "uphill": others steer around it. A stopped hunter is pushed
  off its own spot at the next rebuild, which also breaks it out of local minima.
- A tank in a 2-cell corridor cuts it, and everything behind becomes unreached (100000) until a
  rebuild after it moves.
- **Quirk:** speed level −4 tanks have a max speed of 97, so they are always obstacles, even at
  full speed. Mine-slowed tanks (max speed ÷ 4) usually are too.

**The values.**
- 0 at the base.
- Small numbers (tens to a few hundred) for the open field.
- About 2700–2800 offsets when the base ring is iron.
- At least 100000 for anything reachable only through super steel, and exactly 100000 for
  unreachable cells.
- A footprint sum of at least **400000** (0x61a80; all four cells "unreached") makes the hunter
  fall back to wandering.

**Quirks worth knowing** (keep them for faithfulness, or decide to drop them):
- Damaged hard bricks (44–55) and the hidden-item bricks cost like open ground. Hunters treat a
  half-shot hard brick as free, and push into it.
- The narrow scan's asymmetric bounds, as above.
- **A base sealed in super steel switches hunting off.** Every cell is then ≥ 100000, so every
  hunter wanders. On the shipped map that's stages 1, 2, 46, 53, 54, 55, 57, 58, 61, 62 and 64
  (worked out for every shipped stage). On stage 1, Tourist, nobody hunts.

---

### 4. Hunters

#### 4.1 Who hunts

Rolled once at spawn (0x49a009 … 0x49a07c): the hunt flag = `Random(100) <= x`, where x depends
on the weapon.

| Weapon (by type) | x | Hunters at difficulty 0–5 |
|---|---|---|
| Plain, rapid, AP, explosive | f0 | 21, 36, **51**, 66, 76, 86 % |
| Fire | 2·f0 div 3 | 14, 24, **34**, 44, 51, 57 % |
| Mine | f0 div 3 | 7, 12, **17**, 22, 26, 29 % |

- Weapon = (type − 4) div 4: remake ids 1–4 plain, 5–8 rapid, 9–12 fire, 13–16 AP,
  17–20 explosive, 21–24 mine.
- The flag never changes afterwards.
- With an even mix of the six weapon families, about **42 %** of enemies hunt at medium
  (51 × 4 + 34 + 17, over 6). The rest wander.
- On a stage whose base is sealed in super steel, effectively 0 % hunt.

#### 4.2 Deciding

**When it decides** (0x494d96 … 0x494e11):
- **Stopped** (speed exactly 0): every AI step.
- **Moving:** every AI step while it is in the half cell before the grid line it is driving
  toward, the exact line included. For facing up: `cy·16 ≤ Y`, where cy = Round(Y/16) is that
  line. Likewise right `cx·16 ≥ X`, left `cx·16 ≤ X`, down `cy·16 ≥ Y`.
  - At level-0 speed (0.78 px a frame) that's about 5 decisions per crossing. In the other half
    of each cell it keeps its last command.

**How it scores:** the footprint sums at (cx, cy) and the four shifts (cx ± 1, cy), (cx, cy ± 1).
- The best start is the current sum, with command "stop".
- Each direction, in the order up, right, down, left:
  - strictly lower: it becomes the best;
  - equal: it is taken with probability 1/3, using one Random(3) per tie.
- So with the current sum S0 and neighbours all > S0, the hunter **stops**. With one neighbour
  equal to S0, it moves there 1/3 of the time per decision.
- Several tied best neighbours are order-biased:
  - two: first 2/3, second 1/3;
  - three: first 4/9, second 2/9, third 1/3.

**It may reverse or stop.** No direction is forbidden: reversing is fine, and stopping happens at
any local minimum.

**After a stop** it re-decides every step (speed 0). If the stop came from a tie, it moves off
within a few steps. A true local minimum holds until the next map rebuild marks its own cells
(§3.4), which usually pushes it on.

**Unreached** (own sum ≥ 400000): it wanders at its decision points (§5). It hunts again as soon
as a decision point finds a lower sum, for example after a rebuild.

**Just hit** (HitTicks +0xd0 > 0, 250 ticks after any damaging hit it survives, set in Damage
0x4926bf):
- no decisions at all (§2);
- doubled fire chance (§7).

#### 4.3 What a blocked hunter does

**Turning** happens at the line the tank was approaching (§6.1), because the cross axis snaps to
the nearest 16 px line.

**A brick, hard brick or other breakable wall ahead:**
- The movement step stops it dead (speed 0, §6.2). It re-decides the same way (the map still
  says that way is cheapest) and pushes again.
- It fires its plain gun along that direction with chance 1/P a step, plus its special bursts,
  until the wall is gone.
- There is **no extra firing for being blocked**. It is the same random fire as always; it just
  happens to point at the wall.

**A tank, a player or the base ahead:**
- Blocked the same way (0x4919c8, §6.3). It keeps pushing and firing that way.
- At the next rebuild (≤ 1.8 s), the stopped tank becomes an obstacle in the map and the hunter
  steers around it.
- It shoots players in its path. Its shells pass harmlessly over enemies (§7).

**Iron, super steel or water ahead:**
- It only pushes into these if the map's cheapest route crosses them. That means the region is
  closed off except through iron (4096 a cell) or water (6144 a cell).
- It then pushes and fires forever. Only an AP or explosive shell that breaks iron changes that.

**At the base:** its last step is into the base sprite, which blocks like a tank. It keeps
pushing into the base and firing at it.

**On the shipped stages** (worked out from the map for each spawn spot; dithering is the original's own behaviour):
- many end at the base;
- many push into an iron ring round the base;
- many dither on equal sums next to an iron or super-steel ring.

---

### 5. Wanderers

All of §2's `Wander:` block (0x494ebd … 0x494f9f).

**When it re-picks:**
- when stopped (speed exactly 0: blocked by a wall, water, a tank or the base, or braked to 0);
- when its facing is a direction the edge mask forbids (i.e. it reached the field edge in that
  direction);
- otherwise with chance 1/P per AI step.

While HitTicks > 0, never.

**The pick:** R = Random(5), mapped 0 up, 1 right, 2 down, 3 left, 4 stop. It retries until R
passes all of these:
- **Edges.** Not left if cx ≤ 1, not right if cx ≥ 39, not up if cy ≤ 1, not down if cy ≥ 29.
- **No stop after stop.** Not 4 when the stored command is already 4.
- **No reversing, except down.** Not the reverse of the stored command, (command + 2) and 3,
  unless R is down.
  - So down is always allowed (above the bottom edge).
  - Up is forbidden right after a down command.
  - After a stop command, the "reverse" works out as down, which is allowed anyway.
  - The rule uses the **stored command**, not the facing.

**Stop handling:**
- A stop command brakes by 2a per AI step to 0. At level 0 that's 390 → 0 in 6 steps (0.18 s),
  gliding about 3.5 px.
- At the next step the speed is 0, so it re-picks, and stop is excluded. A stop therefore lasts
  only until the tank stands still.
- A stop picked while already standing lasts exactly one step.

**Its first move.** A fresh enemy stands still, facing up, with command Random(4) + 1. So its
first wander pick excludes:
- left, if the command was right;
- up, if it was down;
- right, if it was left;
- stop, if it was stop.

**It never looks at walls ahead.** It learns of one only by being stopped by it. Then it
re-picks among the allowed directions, possibly the same one again; it bumps until it gets
another.

**The bias.** Excluding "up after down" and never excluding down gives a steady drift downward.
Being forced to re-pick at the field edge is what makes wanderers find gaps at the far ends of a
wall (§8).

---

### 6. Movement and collision the AI relies on

#### 6.1 Commands (DoCommand 0x49180c)

**Speeds** (enemy, setter 0x492e08):
- Level L = clamp(type speed + f6 (+ items), −4, 4).
- T = [150, 216, 300, 432, 600, 864, 1200, 1728, 2400][L + 4].
- MaxSpeed = T·650 div 1000. Accel a = T·60 div 1000.
- Mine-slowed tanks: MaxSpeed div 4.
- One frame moves Speed/500 original px. Level 0 (T 600) has max 390, a = 36: 0.78 px a frame,
  52 px/s original, **104 px/s remake**.

```pascal
procedure DoCommand(Cmd);                         { 0x49180c, once per AI step }
  if Dead then exit;
  case Cmd of
  0..3: if Cmd <> Facing then begin
          Speed -= OnIce ? (2*a) div 8 : 2*a;
          if Speed <= 200 then begin Facing := Cmd; Speed := 200 - Speed end;   { turn }
        end else
          Speed := Min(Speed + (OnIce ? a div 8 : a), MaxSpeed);
        SpriteFrame := direction Cmd;             { the sprite shows the command at once }
  4:    Speed := Max(0, Speed - (OnIce ? (2*a) div 8 : 2*a));
  5, 6: if (ShellsInFlight < MaxShells) and (Heat <= 0) then
          if (Cmd = 5) or (SpecialAmmo <= 0) then Fire(0) else Fire(Weapon);   { 0x491946 }
  end;
```

What follows:
- **From standing**, a direction command turns at once and starts at speed 200 + 2a (272 at
  level 0).
- **Moving**, a new direction brakes by 2a per step until ≤ 200, then turns with speed
  200 − remaining. At level 0 it turns on the third step (390 → 318 → 246 → 174); 8× longer on
  ice without AntiSkid. Meanwhile it slides on along its old facing.
- **A blocked tank's facing becomes its last commanded direction.** When speed is 0, DoMove
  re-reads the facing from the sprite frame (0x492597).
- Shells fly in the sprite-frame direction (Fire 0x4933fd), i.e. the last direction command.

#### 6.2 The movement step (DoMove 0x492244, every frame, MoveCount 20)

```pascal
if Dead or Materialise > 0 then skip;
NotBlockedByTank := True;  Collision;            { DoCollision with each overlapping sprite, §6.3 }
(timers: invulnerability +0xd4, hit timer +0xd0 count down by 20)
if Speed > 0 then begin
  cx := Round(X/16); cy := Round(Y/16);
  OnIce := (AddOn <> AntiSkid) and (at least 2 of the 4 footprint cells are ice);
  if Facing in [up, down] then X := cx*16 else Y := cy*16;   { snap the cross axis, every frame }
  NX := X + Speed/10000*20*DX[Facing];  NY := Y + Speed/10000*20*DY[Facing];
  px := Round((8*DX[Facing] + NX)/16);  py := Round((8*DY[Facing] + NY)/16);
  if LeadCellsClear(px, py) then                 { walls 0x492be0, water 0x492a60 }
     if NotBlockedByTank then begin X := NX; Y := NY end else Speed := 0
  else begin NotBlockedByTank := False; Speed := 0 end;
end else Facing := SpriteFrameDirection;
```

**The lead cells** are the two cells the tank's front edge enters:

| Facing | Cells |
|---|---|
| up | (px, py), (px+1, py) |
| right | (px+1, py), (px+1, py+1) |
| down | (px, py+1), (px+1, py+1) |
| left | (px, py), (px, py+1) |

- **Blocked** if a wall id ≥ 24 (any brick, hard brick, iron, super steel, border; grass is
  passable).
- Or, without AmphiTank, if the ice/water id ≥ 4 (water, border).

**What a block does:**
- **Stopped dead:** no partial step and no sliding. It stops up to one step short of the wall.
- **Speed exactly 0:** this is the "stopped" every AI branch tests.
- The next same-direction command restarts from a + 0 and tries again. That's the "pushing".
- **The snap** only matters after a turn. A straight run is already aligned, so turning happens
  at, and jumps to, the nearest grid line.

#### 6.3 Tanks and the base (0x4919c8, from TTankSprite.DoCollision 0x491aac)

**When it applies.** DoCollision runs for every sprite whose **collision rect** overlaps
(VMT slot 0, 0x49305c):
- a tank's rect is its 32 × 32 sprite inset by 3 px (26 × 26);
- while invulnerable, it grows by 6 px all round (44 × 44).

**The rule.** If the other is a tank (either side) or the base, and it is at least 8 px ahead
along this tank's facing and within ±24 px across, this tank's NotBlockedByTank := False, so it
can't move this frame (speed 0).
- **It is asymmetric:** each tank checks only what is ahead of itself.
- **Nothing pushes back.** Tanks can overlap by a few px before they block.

**The guarded base kills.** TEnemyTank.DoCollision 0x494ba8: an enemy that touches the base
while the base is invulnerable (Flag On Guard: TFlagSprite +0xbd, set by 0x4948a4) has its HP
set to 0. It dies.

---

### 7. Firing

**The plain gun** (0x494fb2):
- Chance 1/P per AI step. While HitTicks > 0, 1/(P div 2).
- At medium: once every 1.5 s (odd types) or 2.25 s (even types) on average; 0.75 / 1.1 s when
  just hit.
- **It can't fire while** shells in flight ≥ the gun level's limit, or gun heat > 0. A refused
  shot is lost; there's no retry or queue.
- **No aiming.** The shell flies in the last commanded direction (§6.1). A hunter therefore
  shoots along its route: at the brick blocking it, or along a line of fire at the base. A
  wanderer shoots wherever it happens to drive.

**The special weapon**, timer T (+0x130):
- Starts at 120.
- Each plain-gun try resets T to 3P.
- Per step, if the plain gun didn't fire: chance 1/T of a special try. Then:

  | T | New T |
  |---|---|
  | T ≥ 3P | f7 + 6: a burst starts |
  | 2 ≤ T < 3P | T − 1 |
  | T = 1 | 3P (a try is certain at T = 1) |

- **A burst** is f7 + 7 special tries (7 at medium). It speeds up as T falls, about 21 steps
  (0.6 s) at medium, unless a plain-gun try cuts it short by resetting T.
- **Mine tanks** use the plain gun for 4 in 5 special tries (0x495016), so they lay a mine on
  20 % of them.
- **Out of special ammo** (+0x11c ≤ 0), command 6 fires the plain gun (0x491962). Packs are in
  the table at 0x4d2c18: plain 1000, rapid 50, fire 30, AP 10, explosive 20, mine 15 (see
  difficulty_original_spec.md f1).
- **Fire, AP and explosive tanks** have no AI of their own; they differ only in what Fire
  launches, and in the hunt chance (§4.1).

**Friendly fire is off** (0x4690d0 compares sides; enemies are side 0, players 1 and 2). Enemy
shells pass over enemies.

---

### 8. Everything else

**Hit by a player's shell** (TArmsSprite.DoCollision 0x493868, after the hit 0x4951f0, if the
enemy survives):
- With chance 1/2, or always if it wears Shield of Moon, its stored command := reverse of the
  shell's flight direction (shell +0xd0). It turns to face the shooter's line (0x4939ba).
- If its original type is odd (remake even id), its special timer := 6. A near-certain special
  burst follows: 6 tries in about 21 steps, unless the plain gun fires first.
- Damage sets HitTicks = 250 (any hit it survives: shell, fire, blast). For those 250 ticks:
  - no hunter or wanderer decisions (it holds the new command);
  - the plain gun's chance doubles.
- Fire and blasts set only HitTicks; there's no turn.

**Other states:**
- **Hold Enemy** (a player's pickup, `[0x4d74d8]` > 0): the think returns at once, with no
  commands and no fire. The movement step runs on, so a moving tank glides straight until
  blocked (enemy_pickups_original_spec.md §5).
- **Materialising** (≈ 0.93 s) and **mine flights**: no think and no movement.

**Not in the AI:**
- **Players:** nothing chases or aims at them. Players only matter as obstacles: blocking
  physically, and as −5 cells when slow.
- **Items:** none are sought or avoided (enemy_pickups_original_spec.md).
- **The base being attacked:** no reaction.
- **Other enemies:** avoided only through the map's −5 obstacle cells and physical blocking.

---

### 9. Sean's case: a wall under the top, gaps only at its far ends

Worked out from the map and the rules above, and in a model of one tank driving by the original's movement rules (no other tanks, no shooting):

| Wall under the top | End gaps | What hunters do |
|---|---|---|
| Iron or super steel | a tank wide (2 cells) or more | Make for the **nearer** end gap along the row above the wall, go down it, cut back to the lines of fire and push into the base. From every spawn spot, in about 5-10 s. |
| Iron | 1 cell | The gaps are narrow, so closed. The cheapest way is through the iron (4096 a cell): every hunter drives down to the iron under it and pushes and fires there for good. |
| Super steel | 1 cell | Nothing above it reaches the base: every hunter wanders. |
| Hard brick | any | Straight down through it (16 a cell is cheaper than going round), shooting. |

**Wanderers**, a wall with end gaps a tank wide: half are through in about 24 s at medium (P 75), 9 in 10 within about 65 s. What does it is the edge rule: a wanderer driving along the wall reaches the field's edge exactly at the gap's column, must pick again there (the edge and the way back are ruled out), takes down 1 time in 3, and goes through. Its drift downward brings it back to the wall whenever it heads up.

**Sean's two saves** (stage 81, "MARIO classical", and stage 55, "Love ICE", of his 114-stage map) both have the base sealed in super steel, as the shipped stages 1, 2, 46, 53, 54, 55, 57, 58, 61, 62 and 64 do. There no enemy can hunt, and every one wanders.

### 10. Corrections to the earlier summary (difficulty_original_spec.md)

1. **"An enemy that can't reach the base, or was just hit, wanders instead."**
   - Half right. One that can't reach the base (own footprint sum ≥ 400000) wanders, but only at
     its decision points.
   - One that was just hit (250 ticks) **doesn't wander**: neither branch may change its command
     (0x494f15), so it holds its course.
   - Separately, a player's shell turns it to face the shot half the time (always with Shield of
     Moon), and gives odd types an immediate special burst (0x4939a3).
2. **"Indestructible steel (ids 56–64) and water are walls on the map; bricks and ordinary steel
   aren't (0x490f69)."**
   - 0x490f69 is only the "blocked" test. It is used for the line-of-fire scans and the narrow
     cells.
   - In the search itself, iron 56–59 is passable at 4096 a cell (2730 on a line of fire), and
     super steel 60–64 costs 100000 (in effect a wall). Water costs +6144 / +4096 without
     AmphiTank.
   - 40–55 aren't "ordinary steel" but hard bricks: 16 a cell when full (40–43), but only 3 when
     damaged (44–55, apparently a range slip in the original's `case`).
   - Other costs: brick 8, partial brick 6, open 3, ice +12 without AntiSkid.
3. **"At each tile boundary, or when stopped, it steps to the neighbouring tile nearest the
   base."**
   - It decides on every AI step throughout the half cell before each line.
   - It compares 2 × 2 footprint sums, including its own: it stops when no shift is lower or
     equal, and each tie is taken with 1/3.
   - The map is **per cell, not per tank position**. A tank's width is handled only through the
     narrow-cell marking and the summing.
4. **"Three maps rebuilt in turn every 240 frames."** The normal map is rebuilt every 120 frames
   (twice per 240-frame cycle). AmphiTank and AntiSkid are rebuilt once per cycle, 60 frames
   apart. Also, maps are only rebuilt on that schedule, never on a wall change.
5. **What the search starts from.**
   - The 4 base cells are the only sources.
   - Beyond the plain walking distance, the map also builds lines of fire (columns 19–22 above,
     rows 28–30 beside), searched first at 2/3 cost.
   - Narrow cells next to iron, super steel or water are impassable.
   - Slow or stopped tanks (players too) are impassable.
6. **"Won't pick stop when already stopped."** It is when its stored **command** is stop, not
   its state; the "reverse" rule likewise uses the stored command.
7. **"P = 1.5 × f4 for even types"**: it's (3·f4) div 2, i.e. 37 at f4 = 25 and 97 at 65. The
   just-hit fire divisor is P div 2.
8. **A fresh enemy**: facing up, standing, command Random(4) + 1 (right, down, left or stop).
   That command decides which direction its first wander pick may not reverse into.
9. **Grid snap.** Tanks snap the cross axis to the 16 px grid on **every** moving frame, not only
   on a change of axis. It only shows after a turn.
10. **Stage 1 (Tourist) and ten other shipped stages have the base sealed in super steel.** No
    enemy hunts there in the original.

---

---

## Part B — The remake

**Ported (2026-10-08), rule for rule:**
- **The map** (`EnemyRoutes`, scripts/level/enemy_routes.gd, one per `LevelManager`, the host's): the builder's phases in order, its costs, the lines of fire, the narrow cells, the tanks in the way (players' too: any slower than the original's speed 100, 26.7 px/s here) and its first-in-first-out queues; the three maps (anti-water tanks use the second, anti-ice the third) and the original's clock: the normal map at once as a stage loads and every 1.8 s, the other two every 3.6 s, never on a wall change. Map cell (x, y) is the field's tile (x − 1, y − 1); a tank's cell is its centre ÷ 32 px from the field's corner, rounded as Delphi rounds. The remake's tiles are read as the original's ids: a brick missing a quarter is a partial brick, a hard brick's id goes by its points left, a brick hiding an item costs 3.
- **The hunter** (`EnemyTank._hunt`): every 0.03 s of play, standing or on the half cell before the grid line it drives to, the footprint sums where it is and one cell each way; the lowest wins, each tie taken 1 time in 3, nothing lower and it stops; a footprint of 400000 or more and it wanders instead.
- **The wanderer** (`EnemyTank._wander`): standing, facing the field's edge, or 1 step in P at random, Random(5) of up, right, down, left and stop, never off the field, never stop twice, never back the way it was told unless that's down. P is the difficulty's f4 (80, 65, 50, 40, 32, 25 steps), half as long again for the basic type of each pair (an odd remake id). A new enemy's first command is right, down, left or stop, as the original's.
- **The grid**: a moving enemy keeps to the grid line across its way, as the original snapped it every frame, so it turns on a line and lines up with a gap a tank wide. (Before, enemies snapped to half tiles on a turn, as players did.) Players keep to it too since 2026-10-08 (`BaseTank._keep_to_grid`, every moving frame): Sean found gaps a tank wide hard to get through, as a player's turn snapped to the half tile, so from 9–15 px off a gap's line it came out 16 px off it, against the wall (scenes/test/tunnel_test.tscn).
- **A hit it survives** holds its course for 0.1875 s, deciding nothing.

**Kept from the remake (Sean's 2026-09-25 call to keep its AI's pressure):**
- **Every enemy hunts the base.** The original rolled it per enemy at spawn: f0 of them (36 % on EASY, 51 % at NORMAL, 86 % on INSANE; fire tanks 2/3 of that, mine tanks 1/3), the rest wandering. Where the base can't be reached (sealed in super steel), every enemy wanders here too, as in the original.
- **Its firing**, along the facing: every 0.1-0.25 s lined up facing the base close by, 0.15-0.3 s stopped at a brick, 0.15-0.4 s within 6 tiles of the base, 0.3-0.6 s at a player in the way, else 0.5-2 s; its special weapons as before. The original fired the plain gun 1 step in P, wherever it faced, in bursts for the specials (§7).
- **A shot turns it on the shooter**, always, and it fires back at once (the original: half the time, always with a moon shield, and only the upgraded types answered with a burst).
- **Players and enemies don't shove each other or block each other's way** as in the original (BaseTank._opponent_ahead): an enemy stops for a player ahead and fires at them.

**Dropped from the remake's old AI:** the pull toward the eagle (75 % of its turns, 95 % near it, and 1-2 % of frames), the first 2 s heading down, turning aside on a collision, going round water for 4 s, the 3 s "wall attack" mode and turning to face the eagle when lined up near it. A tank near a base it can't reach no longer sits facing it.

**Not ported:** an enemy touching the base while Flag On Guard protects it dies (0x494ba8); the original's braking before a turn and speed-up from standing off ice (the remake's tanks move at their speed or stand there; on ice they follow the original's rule, ice_original_spec.md).

**Checked:** the remake's map equals the original's builder value for value on all 64 shipped stages, its three maps each, and with tanks in the way (a step-by-step model of 0x490eec on the same ids), and the remake reads every shipped stage's tiles as the original's ids. Test: scenes/test/enemy_ai_test.tscn (the maps, the costs, the hunter's and the wanderer's choices, the decision points, the grid, the hit hold, the clock, and Sean's case played out: hunters through their nearer gaps, wanderers through the end gaps with the base sealed). Sean's saves, watched for 2 minutes of play: on stage 81, 14 enemies got below the wall, where 1 did before; on stage 55, 20 did, where about half stayed on top before.


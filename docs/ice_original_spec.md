# Ice — the original's rules, and the remake's

How Tank.exe v1.22's ice works, read from the binary (`Tank V1.22/Tank.exe`), and what the remake does. Sean asked to review the ice logic (2026-10-08), after the enemy AI (enemy_ai_original_spec.md, whose research found most of this).

Units: one original cell (16 px) is one remake tile (32 px). An AI step is 0.03 s (every other 15 ms frame). Addresses are Tank.exe virtual addresses.

## Part A — The original

**What ice is:** ids 0–3 of the ice/water layer (`[0x4d74c8]`; the remake's background tiles 0x01–0x04). Tanks drive over it. Shells, mines and blasts take no notice of it.

**A tank is on ice** (its +0xf0) when at least 2 of the 4 cells under it are ice: its footprint at Round(X/16), Round(Y/16) and the cells right of and below that (DoMove, 0x004923cd). A tank with the AntiSkid add-on (anti-ice) never is. It's worked out only while the tank moves, so one standing keeps what it had.

**On ice, a tank answers its controls 8 times slower.** Every AI step each tank gets one command (DoCommand, 0x0049180c), players and enemies alike. A player's is the way held (up before down before left before right), or stop with none held (TPlayerTank's think, 0x00494950); an enemy's is its AI's.
- **Told its own way:** speed + a, on ice + a div 8, up to its top speed.
- **Told to stop:** speed − 2a, on ice − (2a) div 8, down to 0.
- **Told another way** (a turn, or back): speed − 2a, on ice − (2a) div 8, still going the way it faces. Once that's 200 or less it turns, and goes on at 200 less what it had.
- a = T·60 div 1000, top speed = T·650 div 1000. T goes by its speed level: players 1000, 1260, 1588, 2000 (levels 1–4 in play, 0x004d2cf0); enemies 150 to 2400 by level −4 to 4 (0x004d2d00, setter 0x00492e08). A speed of s moves a tank s/500 px a 15 ms frame (s × 0.267 px/s in the remake's pixels).
- A tank that runs into a wall, water, a tank or the base stops dead: speed 0 (DoMove).

So on ice, a player's tank at its slowest (top speed 650, 173 px/s in the remake's pixels):
- **let go** at its top speed, it slides on about 3.5 tiles over 1.3 s;
- **told to turn**, it slides on about 3 tiles over 0.9 s, turns at a crawl and needs about 2.8 s more to reach its top speed;
- **from standing**, the way it faces, 2.8 s to its top speed; another way, it turns at once and is off at 215 (a third of its top speed), then 1.9 s.

**Off ice the same rules run 8 times faster:** from standing 0.2–0.3 s to its top speed; let go, it slides on about half a tile; told to turn, it slides on a little under half a tile before it turns.

**Other uses of ice:**
- The add-on is drawn 1 px further in while the tank is on ice or standing (0x00493720).
- The enemies' way to the base costs 12 more a cell of ice (8 on a line of fire), but not for anti-ice tanks (enemy_ai_original_spec.md).
- A side's fire, the players' or the enemies', melts the ice under itself 500-999 ticks after it starts; burning grass, nobody's, doesn't (fire_weapon_original_spec.md).

Nothing else reads it: not shells, mines (anti-ice skates over mines below level 3 because of its add-on, not the ice), blasts or damage.

## Part B — The remake

**Before (to 2026-10-08):**
- A player's tank was on ice when the tile under its centre was.
- On ice, let go, it kept its full speed until it left the ice or met a wall.
- Any key turned it and set it going at full speed at once.
- Enemies took no notice of ice.

**Now (2026-10-08): the original's rule on ice** (`BaseTank._ice_steer`). Players use it (`PlayerTank._drive`, so a joining player's own screen too, the host following its reports), and so do enemies (`EnemyTank._physics_process`).
- **On ice:** 2 or more of the 4 tiles under it (`BaseTank._on_ice_terrain`, `LevelManager.ice_tiles_under`), never with anti-ice.
- **Speed:** its speed along its facing (`ice_speed`) goes up by an eighth of the original's step and down by an eighth of two, with the step 60/650 of its top speed every 0.03 s.
- **Turning:** told another way, it brakes so, sliding on, and turns once it's down to the original's 200 (53.3 px/s here), going on at 53.3 less what it had. A player's turn snaps to the half tile as ever, an enemy's to the tile.
- **Blocked:** against a wall or a tank it stops dead.

**With the remake's own top speeds** (players 96–192 px/s, enemies 64–192), a player at 128 px/s on ice:
- let go, slides on about 83 px (2.6 tiles) over 1.3 s;
- told to turn, slides on about 65 px over 0.77 s, then needs about 2.6 s to reach 128 again.

**Kept the remake's:**
- **Off ice**, tanks answer at once: no speeding up, no braking, no slide before a turn.
- **The top speeds.** The original's players were faster: 173–347 px/s in the remake's pixels.
- **Smooth steps** in place of the original's 0.03 s ones.
- **The turn speed is the original's 200 as it is**, not a share of each tank's top speed. The remake's tanks are slower than the original's, so they turn sooner on ice: a player at 128 px/s turns at 42 % of its top speed, where the original's slowest turned at 31 %.

**Test:** scenes/test/ice_test.tscn checks the 2-of-4 rule and anti-ice, the slide when let go (and none off ice), the slide on before a turn and the slow start after it, both starts from standing, the dead stop at a wall, and an enemy sliding and turning onto its grid line.

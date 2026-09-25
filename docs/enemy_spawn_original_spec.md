# Enemy Spawning — Reverse-Engineered Spec

How Tank.exe v1.22 sends a stage's enemies onto the field: when (the waves, in the play tick 0x4cbae4), and where and which (the spawn try, 0x498190). How many a stage sends, and how many may be on the field at once, are the difficulty's (difficulty_original_spec.md).

**Units.** 1 tick = 0.75 ms at the original's default game speed (section 5). The map is 40×30 tiles of 16 px; the remake doubles them. Tank types are the original's numbers 0–23 (the remake's type IDs 1–24).

## 1. The map's border

The stage loader (0x4caa7b) builds each layer 42×32: a ring of steel (id 0x40) around the stage's 40×30, so map cell (x, y) is stage tile (x − 1, y − 1). The layers are the wall layer `[0x4d74cc]` (grass 8–11, scorched grass 12–15, brick 24+, steel 40+) and the ice/water layer `[0x4d74c8]` (ice 0–3, water 4–7).

## 2. The waves — 0x4cbbbe

The game's timer (+0x420) counts down by each frame's ticks during play.

- **Play starts:** the timer is set to **4000 ticks (3 s)** (0x4c99fc).
- **The timer runs out:**
  1. k = Random(4) + 1, so 1–4 tries.
  2. Up to k spawn tries, **stopping at the first refused**.
  3. The timer += **k × 1250 ticks (0.9375 s a try)**, whether the tries came or not.
- So when there's room, enemies come 1–4 at a time, on average one every 0.94 s.
- **No waves once every player is out of lives** (0x4cbb05). This is the rejoin window of stage_screens_original_spec.md: the enemies on the field play on, but none come.
- **No waves once the stage is clear** (none left to come and none on the field, 0x4cbb86): its end wait instead (stage_screens_original_spec.md).

## 3. A spawn try — 0x498190

1. **Refused** if the field already holds the stage's limit (+0x10 ≥ +0x0c), or none are left to come (0x498918 ≤ 0).
2. **Type** (0x4981d6): t = Random(24), again until type t has any left (its count at +0x18 + 2t).
   - Every type still to come is as likely as any other, however many of it are left. For example, with nineteen of one type and one of another, the lone one comes first half the time.
3. **Place** (0x4981ea): c = Random(39) + 1, again until map cells c..c+1 × 1..2 (a tank's 2×2, on the top two rows of the stage) are free:
   - on the ice/water layer, every id below 4: **no water**, but ice is fine (0x490d48, 0x498209);
   - on the wall layer, every id below 24: **no brick or steel**, but grass and scorched grass are fine (0x498224).
   - That is one of the 39 tank-sized spots along the top, stage columns 0–38, picked evenly among the free ones.
4. The field's count +1, the tank made (0x499f30), and placed with its top-left at (16c, 16) in map pixels (0x498239), i.e. its top on the stage's top row. The type's count −1, and the HUD's "Enemy NN" updated.

**What it doesn't check:**
- **Tanks:** a new enemy can appear on top of another tank, even one just made in the same wave.
- **A way out:** if no spot along the top is free, the place loop never ends and the game hangs. The shipped stages always leave at least two free spots.

## 4. The shipped stages

Free spots along the top, of 39 (maps/v1_2_2.dat):
- Most stages leave many.
- Stage 1, Tourist, has 9, one between each pair of its brick posts (columns 3, 7, …, 35).
- Stages 50–52, X, have only their two corners (0 and 38). Stage 48, Frame, has its two gaps (15 and 22). Stage 38, the Silk Road, has 4.

The remake's old fixed points (columns 1, 19 and 37) were walled in on many stages, and it broke the walls there. On all of stages 38, 48 and 50–52, for example.

## 5. The game's speed — 0x4c7a1e

Every tick count above runs on the game's clock, which its speed option sets.
- DXTimerTimer (0x4c7960) gets DelphiX's lag count: the 5 ms timer intervals since the last frame (the form's DXTimer has Interval 5; DelphiX's idle handler, 0x452660).
- It turns that into ticks: `min(lag × 5, 100) × speed / 75`, speed from the table at 0x4d3c58, indexed by the options' GameSpeed −1..3: **83, 100, 117, 133, 150 %**, with 0 (100 %) the default.
- So at 100 %, 1 tick = 0.75 ms; at 150 %, 0.5 ms. The first wave comes after 3 s at 100 % (2 s at 150 %), and a wave's gap per try is 0.94 s (0.63 s).
- The readme's "enemies appear 4 sec after you" counts ticks as ms. The copy in `Tank V1.22` has `GameSpeed=3` (150 %) in TANK.ini, and the readme calls 150 % fun.
- Frames never lose more than the few ms short of a whole 5 ms interval, so the clock runs at or just under its rate.

## The remake

`EnemySpawner` (scripts/level/enemy_spawner.gd), with `LevelManager.is_open_ground` for the free-spot test:
- **Waves:** `_send_wave`: `randi_range(1, 4)` tries, stopping at the first refused, then the timer is set to tries × 0.9375 s. The first comes after `begin()`'s delay: `game.gd`'s `FIRST_WAVE_DELAY`, 3 s.
- **Refused:** the field at `max_concurrent_enemies`, or none left to come (`_spawn_enemy`).
- **Type:** `_take_type`: a random one of the distinct types in `_spawn_queue`, one of it taken off. The queue's order means nothing now; `LevelData.get_enemy_spawn_queue` no longer shuffles it.
- **Place:** `_pick_spot`: a random one of the 39 spots (a 2×2 block whose top-left is on tile row 0, columns 0–38) with no wall, water or base on it. The tank's centre goes to the block's centre.
- **Everyone out:** `game.gd` holds the timer (`hold`) for the rejoin countdown, as before.

- **Game speed:** the GAME SPEED setting (title and pause settings, `InputSettings.GAME_SPEEDS`, 100 % by default) sets `Engine.time_scale` while a stage runs (`game.gd _apply_game_speed`). Tanks, shells, timers, waves and the stage screens all follow it; sounds keep their pitch, and the menus outside a stage run at normal time. The remake's times above are the 100 % ones.

**Deliberate differences:**
- **Never on a tank.** A spot is passed over while a tank overlaps it (hitboxes within 60 px on both axes), whether on the field, in the air or still appearing. With none free, the try is refused, which ends the wave. The original stacked them; the remake used to wait for its fixed point to clear.
- **No hang.** If every spot along the top is walled or flooded (not a shipped stage), any tank-free spot is taken, and its walls are cleared for the tank, as the remake's spawn points were before.
- **The waves go on** after the queue runs dry, as the original's timer did, so enemies that a "+1 UP" adds still come.

**Test:** scenes/test/enemy_spawn_test.tscn.

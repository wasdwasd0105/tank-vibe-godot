# Difficulty — Reverse-Engineered Spec

What Tank.exe v1.22's difficulty level changes, and how the remake compares. `SetDifficulty` (0x499130) copies an 8-dword record from 0x4d2860 into the globals 0x4d74e0..0x4d74fc, and those eight fields are the whole of it (a scan of the code found no other readers). Difficulty never touches enemy HP or anything on the player's side, apart from the stage-end reward.

**Units.** 1 tick = 0.75 ms. An enemy's AI step runs every other 20-tick frame (0x4c7bb7), so **one AI step = 40 ticks = 0.03 s**.

**Types** are the original's numbers. The original's type = the remake's id + 3, so an odd type here is a remake even id: the upgraded tank of each pair (the one a MAX item promotes to).

## The levels

The options dialog (rgDifficult in TfmOption) offers five levels; the sixth is reached only by looping the map:

| # | Original name | Meaning |
|---|---|---|
| 0 | 极容易 | very easy |
| 1 | 容易 | easy |
| 2 | 中等 | medium (the default; the title demo also plays at 2) |
| 3 | 困难 | hard |
| 4 | 极困难 | very hard |
| 5 | — | only by looping |

When the stages run out, the map wraps to its first record and difficulty goes up by 1, capped at 5 (0x4caa01, 0x499132). The remake's EASY..INSANE are the original's 1..5; its 0 isn't offered.

**Stage order.** Record 0 of Stage.dat is the title demo's "Splash Stage" (24 enemies, one of each type, 18 at once). A new game starts at record 1 (0x4ca4b8), so the demo map is only played on a loop, just before record 1. The remake skips record 0 (`LevelData.load_stages_from_dat`), so its stage 1 is record 1, "Tourist", as in the original; its loops go straight back to stage 1.

## The record, field by field

| Field | Use | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|---|
| f0 | Chance an enemy hunts the base (%) | 20 | 35 | 50 | 65 | 75 | 85 |
| f1 | Special ammo and the reward (%) | 33 | 66 | 100 | 150 | 200 | 250 |
| f2 | Enemies per stage (%) | 50 | 75 | 100 | 125 | 150 | 175 |
| f3 | Most enemies on screen at once (%) | 67 | 83 | 100 | 117 | 133 | 150 |
| f4 | AI decision period P (AI steps) | 80 | 65 | 50 | 40 | 32 | 25 |
| f5 | Enemy gun bonus | −1 | 0 | 0 | 0 | +1 | +1 |
| f6 | Enemy speed bonus | −1 | −1 | 0 | +1 | +1 | +1 |
| f7 | Special-weapon burst length | −2 | −1 | 0 | 1 | 2 | 3 |

### f0: hunting the base
Rolled once per enemy at spawn into flag +0x13c (0x49a009). The flag is set when Random(100) ≤ the chance, which depends on the gun:
- Plain, rapid, AP or explosive: f0, i.e. 21/36/51/66/76/86 %.
- Fire: 2·f0/3, i.e. 14/24/34/44/51/57 %.
- Mine: f0/3, i.e. 7/12/17/22/26/29 %.

**How a flagged enemy moves (0x494d7c):**
- It follows a walking-distance map to the base tiles (x 20–21, y 29–30), searched out from them (0x490fb7).
- At each tile boundary, or when stopped, it steps to the neighbouring tile nearest the base, breaking ties 1 in 3 at random (0x494e59).
- Indestructible steel (ids 56–64) and water are walls on the map; bricks and ordinary steel aren't (0x490f69).
- There are three maps (normal, AmphiTank, AntiSkid), rebuilt in turn every 240 frames (0x499dd0).
- An enemy that can't reach the base, or was just hit, wanders instead.

**Every other enemy wanders:**
- It picks Random(5) among up, right, down, left and stop, excluding directions off the edge of the map (0x494ebd).
- It never reverses, unless the reverse is down, so wanderers drift toward the base. It won't pick stop when already stopped (0x494f56).
- It re-picks at once when stopped or at an edge; otherwise with chance 1/P per AI step (0x494f3e).

### f1: special ammo and the reward
- **Ammo at spawn:** Round(pack × f1 / 100) (0x499f7b): one pack at medium, scaled by f1. Doubled for odd types (0x499fdf), at most 5 packs (0x492f70). A pack holds rapid 50, fire 30, AP 10, explosive 20 or mine 15 shots. An enemy out of ammo uses its plain gun (0x491962).
- **The stage-end reward:** f1 × 10, or × 30 for the 2-player winner (0x4cb6c2). The remake has this (`StageOverlay.REWARD_FACTORS`).

### f2: enemies per stage
At the stage start (0x4cabb0–0x4cac57), for each of the 24 types:
- A count over 99 counts as 0 (0x4cabb0).
- x = count × f2 / 100 + 0.0005 (0x4cabbe); n = Trunc(x) (0x4029c4); frac = x − n.
- If frac ≥ 0.001 and Random(1000) < Trunc(frac × 1000), n + 1 (0x4cac0a–0x4cac48).
- In whole numbers: n = count × f2 div 100, plus one with a chance of (count × f2 mod 100) %. So 2 × 75 % is 1, or 2 half the time.

The scaled counts replace the stage's list, and their sum is the stage's reserve (0x4cac68). Nothing guarantees at least one.

### f3: enemies on screen
The stage's own figure (the word 64 bytes after the counts, file offset 208) × f3 / 100, rounded the same way (0x4cac91), then clamped to 4–20 by the setter at 0x4991b8. The number of players plays no part. The setter's only other caller (0x4cafe1) builds a random map with its own limit, (a counter ÷ 3) + 8; normal stages never reach it.

### f4: how often enemies turn and fire
P = f4 AI steps for odd types, 1.5 × f4 for even types (0x494d38):

| | 0 | 1 | 2 | 3 | 4 | 5 |
|---|---|---|---|---|---|---|
| Odd types | 2.4 s | 1.95 s | 1.5 s | 1.2 s | 0.96 s | 0.75 s |
| Even types | 3.6 s | 2.9 s | 2.25 s | 1.8 s | 1.4 s | 1.1 s |

- **Turning:** a wanderer re-picks its direction with chance 1/P per step.
- **The plain gun:** fires with chance 1/P per step, so once every P on average. For 250 ticks after the enemy is hit, the chance is 1/(P/2) (0x494fb2).
- There is no aiming: an enemy fires along its facing. Hunters face the base, so their shots go that way.

### f5 / f6: gun and speed at spawn
- **Gun** = the type's table value (0x4d2af0) + f5, clamped 0–3 (0x499fc4).
- **Speed** = the type's table value (0x4d2a90) + f6, clamped −4..4 (0x499fb0). See the speed table in enemy_pickups_original_spec.md.
- **HP** = the type's table value (0x4d2a30), with no difficulty term.
- f5 and f6 are also the baselines for the hit downgrade: only gun or speed above them is knocked back out.

### f7: special-weapon bursts
- Each plain shot sets the special-weapon timer to 3P (0x494fe9).
- The next special shot then resets it to f7 + 6 (0x49506c). Each special shot after that lowers it by 1, with a chance of 1/timer per step. Below 2, it goes back to 3P (0x495041).
- So a burst is about f7 + 7 special shots, speeding up as it goes.
- Mine tanks use their plain gun instead 4 times in 5 (0x495016).

## What difficulty doesn't touch

- **Spawning:** waves of k = Random(4) + 1 attempts, then a wait of k × 1250 ticks (0x4cbbc7). The first wave comes at 4000 ticks.
  - An attempt is refused while the screen is full or the reserve is empty.
  - The type is random among those with any left, not weighted by how many (0x4981d6).
  - The place is a random free spot along the top row.
  - All of it is in enemy_spawn_original_spec.md, and ported (2026-09-25).
- **Enemy HP.**
- **The player:** 4 lives per credit (credits 5–30 in the options, default 10), 5000 ticks of invulnerability on spawn and 750 after a hit, speed, gun, item drops, item lifetimes, kill scores, the extra-life thresholds.

## The remake

**Ported (2026-09-25; Sean asked for the level and count to match):**
- f2 and f3: `LevelData.enemies_for_difficulty` and `on_screen_for_difficulty`, with the rounding above (`scale_by_chance`). `EnemySpawner.prepare_stage` takes both from `GameManager.difficulty` once per stage.
  - The remake's old rule of at least 6 enemies at once with two players is gone; the original has no such rule.
  - A stage whose enemies all round away is won as it starts (`EnemySpawner.begin`), so it can't hang. A stage listing none at all still gets the remake's fallback of 20 basic tanks.
- The loop's difficulty step stops at 5 (`GameManager.advance_stage`).
- Test: scenes/test/difficulty_count_test.tscn.

**Changing it mid-game (Sean, 2026-10-02):** the original fixed the difficulty when a game began. In the remake, the settings' GAME tab changes it any time, the pause menu's too (`GameManager.set_difficulty`, which also makes it new games' difficulty). A stage in play takes it up at once (`EnemySpawner.apply_difficulty`):
- Of each type, as many come in all as the new level sends, less those already sent. Reinforcements an enemy won with "+1 UP" stay on top.
- The limit on the field is worked out again at the new level.
- New enemies come with the new level's gun levels. The tanks already on the field keep theirs, and a hit takes back only what items gave them (`EnemyTank._base_weapon_level`), so lowering it shakes no Power Up loose.
- The stage-end reward goes by the difficulty at the stage's end.
- Test: scenes/test/game_tab_test.tscn.

On the bundled map, stage 1 (4, 2, 4, 2 = 12 tanks, 4 at once) now sends 8–10 tanks on EASY, 12 on NORMAL and 20–22 on INSANE. The limit is 4 at once up to NORMAL, 4–5 on HARD, 5–6 on EXPERT and 6 on INSANE.

**Not ported (Sean's call, 2026-09-25):** every other field. The remake keeps its own enemy AI, so difficulty still doesn't change these:

| | Remake, every level | Original medium (2) | Original easy (1) |
|---|---|---|---|
| Heading for the base | every enemy, 75 % of turns (95 % near the base) | 51 % of enemies | 36 % of enemies |
| Plain-gun fire | every 0.5–2 s; 0.15–0.4 s within 6 tiles of the base; 0.1–0.25 s lined up with it; 0.15–0.3 s breaking a wall; 0.3–0.6 s against a player | every 1.5 s / 2.25 s | every 1.95 s / 2.9 s |
| Turning | every 2–4 s (0.5–1.5 s near the base), and a pull toward the base 1–2 % of frames | 1/P per step (wanderers) | 1/P per step (wanderers) |
| Speed | the tank table's | + 0 | − 1 |
| Gun | tank table (rapid), original (mine), 0 (others) | + 0 | + 0 |
| Special ammo | unlimited | 1 pack (2 for odd types) | medium's × 66 %, rounded |

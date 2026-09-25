# Original Stage Screens — Reverse-Engineered Spec

How Tank.exe v1.22 opens and closes a stage: the intro, the "Mission" screen, the results panels with their reward, and "Game Over". The remake draws all of them in `StageOverlay` (scripts/ui/stage_overlay.gd) over the playfield; `scripts/game.gd` runs the stage around them.

**Units.** 1 tick = 0.75 ms at the default game speed (a logic frame is 20 ticks = 15 ms; 1000 ticks = 0.75 s). Positions are pixels on the original's 640×480 screen. The remake's playfield is that screen at 2×, so every position and size below doubles in the remake. The sprite engine shifts sprites and panel children 16 px up-left of their stored X/Y (0x4c8454); the positions here already include that shift.

**States.** The game changes state by posting message 0x8001 (0x4ce024), dispatched through the jump table at 0x4c8af8:

| State | Function | Screen |
|---|---|---|
| 1 | 0x4c988c | demo |
| 2 | 0x4ca448 | title |
| 3 | 0x4c8d90 | hiscore table |
| 4 | 0x4c9a20 | stage intro |
| 5 | — | play |
| 6 | 0x4ca03c | Mission Complete / Mission Fail |
| 7 | 0x4c90b4 | results |
| 8 | 0x4c8b74 | Game Over |

Entering any state zeroes the end timer `[form+0x424]`. Holding a fire button speeds up states 4, 7 and 8: each player holding adds a `Move(50)` per 20-tick step (0x4ce31e), so one player makes it 3.5× and both make it 6×. Nothing speeds up state 6, and nothing skips any state.

The three fonts: **Text3** (gold, 18×36 cells, `tank_font`), **Text** (white, 12×24, `tank_font_small`) and **Text2** (8×16, `tank_font_tiny`). Glyph index = ASCII code in every sheet.

---

## 1. Stage intro (state 4, 0x4c9a20)

- **Setup:** the previous screen freezes for `Sleep(250)`, then LoadStage builds the new map.
- **Picture:** named in Stage.dat at record offset 0xE0 (length-prefixed; records 1–9 name SI01–SI09, record 10 names SI00). It is loaded into image-list item 24 and cut into four 320×240 quarters, drawn 1:1 at draw order 12 over the map.
  - The shipped "Boxes" record names a missing SI5.JPG, so that stage's intro has no picture and plays over the bare map.
- **"Stage %2.2d"** in Text3 drawn at 2× (36×72 cells), centred: x = (640 − 36·len)/2.

  | Ticks | Time | Stage text | Caption (Text font) | Picture quarters |
  |---|---|---|---|---|
  | 0–500 | 0–0.375 s | above the screen at y −72 | hidden | cover the screen |
  | 500–1000 | 0.375–0.75 s | slides down to y 150 | fades in | cover the screen |
  | 1000–3000 | 0.75–2.25 s | holds | holds | cover the screen |
  | 3000–3500 | 2.25–2.625 s | cells grow to 72×144 (the box ends at x 32, y 78, its bottom still at 222); fades 255→0; each letter spins one full turn clockwise | fades out | slide off the screen |

- **Caption:** the stage's caption, split into lines at every byte ≥ 0x80 (0x4c7758). It is a left-aligned block centred on the longest line (x = 320 − 6·longest), top y 279, 24 px per line.
- **How the quarters leave:** one `Random(3)` per intro:
  - 0: top pair up, bottom pair down;
  - 1: each quarter out through its own corner;
  - 2: left pair left, right pair right.
- **End:** state 5 at 2.625 s. The tanks are created now, and the first enemies arrive 3.0 s into play. There's no sound.

## 2. Stage clear and loss triggers (state 5, 0x4cbae4)

- **Clear:** enemies in reserve (0x498918) plus enemies on the field (game+0x10) ≤ 0. The mission screen starts once `bonusItemsOnField − timer div 3000 ≤ 0` (0x4cbb96). That means at once if no bonus items are left, otherwise up to 2.25 s for each item still lying there. The field never freezes; only spawning stops.
- **Loss:** P1 + P2 lives ≤ 0, with no hiscore name still to enter (0x498848).
  - With credits left, the mission screen comes after 7000 ticks (5.25 s), a window to rejoin; enemies keep moving and firing but none spawn.
  - With no credits, it comes at once.
- **Base destroyed** (0x494338): it has 1 HP. Every player's lives go to 0 and their tanks explode. Its grey eagle row plays once (about 0.66 s), then the sprite is removed.
- **Rejoin:** a dead player holding any of their controls plays SignIn, spends a credit and gets 4 lives. If the eagle had died, it is rebuilt at (304,448) with 22.5 s of invulnerability.
  - While dead, the HUD's lives slot reads **"Game Over"** (Text font at (12,38) / (506,38); 0x499a05).
  - With credits left, a pulsing **"Press Fire Start"** appears in Text2 at (12/506, 446).

## 3. Mission screen (state 6, 0x4ca03c) — 4000 ticks = 3.0 s

| | Won (TotalLives > 0) | Lost |
|---|---|---|
| Picture | `Map\StageWin.BMP` | `Map\StageLose.BMP` |
| Title | "Mission Complete" | "Mission Fail" |
| Sound (played at once, 0x4ca1dd) | 19 StageWin (17.5 s, never stopped) | 20 StageLose (15.6 s) |

- **Title:** Text3 at 1× (18×36), centred (x = 320 − 9·len), starting at y 222. It rises to y 50 over 500 ticks, at draw order 13. It has no alpha flag, so it always draws solid.
- **Picture:** the same four quarters, drawn opaque at draw order 12.
  - `Random(3)` picks their start: vertical (top quarters at y −240, bottom at 480), diagonal, or horizontal (left at x −320, right at 640).
  - They wait off-screen for 3000 ticks (2.25 s) while the field keeps playing, slide in over 500 ticks, hold 500 ticks, then go to state 7 (0x4ca6d4).

## 4. Results (state 7, 0x4c90b4)

- **Setup:**
  - If lives remain, the stage number increments.
  - All tanks, shells and bonus items are removed, and the map is hidden.
  - The picture and title stay.
  - One panel appears for each player who spawned this stage (flag +0x45).
- **Panel:** image 25 "StageScore", 264×307, pure blue (0,0,255) as the transparent colour. Its interior is a checkerboard of transparent pixels and (84,78,63), so it reads as a 50% see-through panel. The icons, 总计 ("total") and the header are part of the picture.
  - P1's panel sits at (28,110), sliding in from x −264.
  - P2's panel sits at (348,110), sliding in from x 904.
- **Text on the panel** (positions from the panel's top-left):

  | Item | Font | Position | Value |
  |---|---|---|---|
  | `MaxHits %2d` | Text2 | (28,74) | the stage's best hit chain |
  | `MaxCombos %2d` | Text2 | right edge at x 240, y 74 | the stage's best kill combo |
  | `'%2d      %2d    x%1d ='` | Text2 | (60, 110+32r) | row r's left and right kill counts, then its weight r+1 |
  | `%2d` | Text2 | right edge 240, y 106+32r | row points = (L+R)·(r+1) |
  | `%3d` | Text3 | right edge 240, y 256 | total = sum of row points |

- **Kill cells** (table 0x4d2bb0; the remake's types are the original's minus 3). Each icon is the up-facing frame of the last type in its cell.

  | Row (weight) | Left | Right |
  |---|---|---|
  | 0 (×1) | normal, types 1–2 (icon 2) | normal, 3–4 (icon 4) |
  | 1 (×2) | rapid, 5–8 (icon 8) | mine, 21–24 (icon 24) |
  | 2 (×3) | explosive, 17–20 (icon 20) | fire, 9–12 (icon 12) |
  | 3 (×4) | AP, 13–14 (icon 14) | AP, 15–16 (icon 16) |

- **Timeline:**

  | Ticks | Time | What happens |
  |---|---|---|
  | 0–1000 | 0–0.75 s | the panels slide in, linearly |
  | at 0 | — | the kill counts show their final values |
  | 1000–2000 | 0.75–1.5 s | everything scored rolls up from 0: row points, MaxHits, MaxCombos, total (each frame adds `Round((target − v)·20/remaining)`, with no tick sound) |
  | 2000 | 1.5 s | the reward (§5) |
  | until 7000 (won) / 5000 (lost) | until 5.25 s / 3.75 s | hold |
  | + 333 | 5.5 s / 4.0 s | the panels slide back out, then the state ends (0x4cb9f0) |

- **Next:**
  - Won: an autosave, then the next stage's intro (state 4).
  - Lost: Game Over (state 8). There's no reward, no stage increment and no save.
- **MaxHits / MaxCombos** (player record +0x2c / +0x30; per player at game+0x1c0 + 0x50·p):
  - **Hits:** every damage point a player's weapon deals to a live, vulnerable enemy adds to a chain (0x498b4c). The chain lapses 60 frames (0.9 s) after its last hit.
  - **Combos:** every kill adds to a combo (0x498c60), which lapses after 180 frames (2.7 s).
  - A lapsed chain folds into the best (0x498dac). Folding only runs in states 1 and 5, so a stage's last chain slips into the next stage's best.
  - The bests reset at stage start (0x4996e0).
  - The original also scores these: `5·h·(h+1)/2` for a hit chain, and a kill is worth `5·(n + type div 2 − 1)·(combo+3)`.

## 5. Reward (callback 0x4cb660, at results t = 2000, only if lives remain)

- **Who gets it:**
  - Beating the other player's total (they played this stage too): ×30, in 6 text copies.
  - Otherwise, a total above 0 that is alone or level with the other player's: ×10, in 4 copies.
  - Anything else gets nothing.
- **Amount:** the difficulty factor (table 0x4d2860: 33/66/100/150/200/250 for difficulty 0–5) times the multiplier. At the default difficulty 2 that is 1000 or 3000.
- **Scoring:** AddScore runs at once, and an extra life comes if the new score crosses a threshold.
- **"Reward +N" copies** (Text3 at 1×, alpha always on, children of the panel, draw order 25 − k). For copy k:
  - **Start:** `Random(2)` picks one of two places:
    - top: x = Random(640) − 16, y −216;
    - side: P1 at x 624, P2 at −18·len − 16, with y = Random(480) − 16.
  - **Wait:** 100k ticks at alpha 64.
  - **Fly in:** 333 ticks, linear, to x = panel + (264 − 18·len) div 2, y 426 (just under the panel), with alpha rising 64→128.
  - **Settle:** in place, the lead (k = 0) goes 128→255 over 333 ticks, the others 128→48 over 333 − 60k.
  - **Hold:** 750 ticks.
  - **Fly off:** to y −52 over (N + 7500) div 6 ticks, linear.
- **Sound:** **Reware** (16) plays as the lead copy settles, but only when the reward is exactly 3000 (0x4cb92a).
- **HUD:** the score counter counts up the reward.

## 6. Game Over (state 8, 0x4c8b74) — 5500 ticks = 4.125 s

- **Letters:** "Game Over" as 9 letter sprites in Text3 at 2× (36×72); the space draws nothing. Letter i (1–9) sits at x = 140 + 36·i, y 204. They draw over the lose picture and "Mission Fail", which both stay.

  | Ticks | Time | Letters |
  |---|---|---|
  | 0–1500 | 0–1.125 s | fade in, 0→255 |
  | 1500–3000 | 1.125–2.25 s | hold |
  | 3000–4500 | 2.25–3.375 s | fly off to their own spots, stretching, spinning and fading (below) |
  | 4500–5500 | 3.375–4.125 s | nothing visible |
  | 5500 | 4.125 s | the title (state 2) |

- **Flying off:** each letter picks `Random(4)` for its destination:
  - (Random(640), −272)
  - (Random(640), 680)
  - (−236, Random(480))
  - (840, Random(480))

  As it flies, it grows to 72×216 (2× wide, 3× tall), fades to 0, and turns (Random(1024) − 512)/256 turns about its centre.
- **Sound:** none.
- **Afterwards:** the title offers "Press Fire Button to Continue" if credits remain past stage 1.

---

## Remake notes

- The overlay covers the 1280×960 playfield at (160,16), which is the original's screen at 2×. The remake's HUD sits in side panels outside it.
- **Pictures** are the game's own since 2026-09-25, drawn by `tools/make_screens.py` into `assets/screens/` as 320×240 dithered pixel art, shown at 4×. The original's photos are gone from the JueZhuanTanKe theme.
  - **Stage intros:** one for each of the original's names, SI00–SI09, so the stages keep their pairing: 0 midnight searchlights, 1 dawn, 2 desert convoy, 3 red dusk over ruins, 4 storm, 5 snow, 6 aurora, 7 burning front, 8 twilight city, 9 golden hour. The "Stage NN" drop stays in the sky and the caption over the horizon; the tanks keep low.
  - **Stage won** (`stage_win`): a gold-on-navy blueprint of the game's tank, a nod to the original's. The bottom strip is left clear, because each player's "Reward" lands under their panel there.
  - **Stage lost** (`stage_lose`): the base burning at night, with smoke, flames, broken brick walls and a torn flag.
  - A theme can still bring its own: its `[screens]` `dir` for the intros (found by the Stage.dat name, whatever its case), and `stage_win` / `stage_lose`.
  - A name the original never had (the "Boxes" record's SI5.JPG) still finds none, so that intro plays over the bare map as in the original.
- **The results panel** is the remake's own box, in the menus' style, laid out on the original's 264×307 panel so the counts fall where the original's did:
  - the menus' panel, with "RESULTS" in gold and the player's "I P" / "II P" tag in the HUD's colours. With the menus in Chinese the header reads 战斗成绩 and the total 总计, the original panel's words (Sean, 2026-09-25); the rest of the stage screens stay English;
  - a band for MaxHits / MaxCombos and one per kill row, with icons from the theme's tank sprites;
  - gold rules under the header and over "TOTAL".

  The JueZhuanTanKe theme's picture of the original's StageScore panel (with "战斗成绩") was dropped on 2026-09-25. A theme can still name a `results_panel` picture to show instead.
- **Kill credit:** every kill goes to the player whose weapon dealt the last point, and it counts for that player's score, panel and combo.
  - Shells carry their owner.
  - Fire fields and their tiles, mines, blasts and the bomb pickup carry it too.
  - Grass fire and enemy weapons are nobody's.

  (Before this, every kill went to P1.)
- **Deliberate differences:**
  - The last chain of a stage counts toward that stage's MaxHits/MaxCombos. The original's slip into the next stage is a bug.
  - Hits and combos are shown but don't change the score. The remake keeps its own per-type points and its 20k extra-life rule.
  - The Reware sound plays for any winner's reward. The original compares the amount with 3000, which only matches at the default difficulty.
  - The rejoin window is 5 s (Sean's choice; the original's is 5.25 s), shown as a countdown. Enemies hold their reinforcements during it, and with no credits the stage is lost at once, as in the original.
  - The stage number advances when the next stage starts rather than during the results. The HUD's lives line reads "GAME OVER" for a player who is out.
  - There's no hiscore name entry and no "Continue" prompt on the title; saves cover continuing.

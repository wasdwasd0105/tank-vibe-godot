# Hit and Kill Text — Reverse-Engineered Spec

The words Tank.exe v1.22 shows when a player hits and kills tanks: a hit counter in the player's corner, and the kill's score over the wreck. Both come from the tank's Damage routine (0x492640), with the per-frame chain fold (0x498dac) taking the counter down.

**Units.** 1 tick = 0.75 ms; 1 frame = 20 ticks. Positions are the original's 640×480 pixels; the remake doubles them. Tank types are the original's numbers (the remake's id + 3). A sprite's X/Y is its top-left, and a tank is 32×32.

## 1. Damage(tank, amount, attacker) — 0x492640

`attacker` is the player number (1 or 2), 0 for an enemy's weapon (enemies are side 0, TEnemyTank.Create 0x494b78), or −1 for burning grass, nobody's.

1. Nothing happens if the tank has no HP left, `amount` ≤ 0, or it is invulnerable (+0xbd).
2. HP −= amount (SetHP, vmt+0x24).
3. **Hit chain** (0x498b4c): skipped for an attacker below 0. The player's chain += amount (damage points, not shots), and its timer is set to 60 frames (0.9 s).
4. If the tank survives: the hit flash, the hit sound and the downgrade (see enemy_pickups_original_spec.md). Nothing more here.
5. If it dies and the attacker is a player (attacker > 0):
   - **Combo** (0x498c60): +1, and its timer is set to 180 frames (2.7 s).
   - **Score** (0x49282a–0x49284b): k = amount + type div 2 − 1; the kill scores 5·k·(combo + 3).
   - **Kill text** (0x492886–0x4929e9), section 3.

## 2. The hit counter — 0x498b4c, 0x498dac

- When a player joins (0x499258), their record gets an array of 8 text sprites for their corner of the screen (+0xc). Element 0 is the counter:
  - Text2 (image 22, the 8×16 font), drawn solid;
  - at x = 12 + 494·(p − 1), y 66, just under the player's score lines (y 10 and 38);
  - hidden until needed.
- **From a chain's second point:** the counter shows `Format('%3d', [chain]) + ' Hits +%4d'`, e.g. `  5 Hits +  75`. Its number rolls up to 5·h·(h+1)/2 over 500 ticks (a keyframe on the sprite).
- **The chain lapses** 60 frames after its last point (the fold, 0x498df1):
  - the counter hides (+0x56 = 0);
  - the chain's 5·h·(h+1)/2 is added to the score (0x498e29);
  - the chain goes into the stage's best (MaxHits) and back to 0.

## 3. The kill text — 0x492886

- A new text sprite (class at 0x48fda4). Its constructor (0x496410) picks image 21, **Text** (the white 12×24 font), at draw order 20.
- Damage then halves its glyphs to 6×12 (+0x6c, +0x70) and turns its alpha on (+0xb1).
- **Lone kill** (combo 1): `"+ " + IntToStr(20·k)`, e.g. `+ 40`, with its top-left at (tank x, tank y + 8).
- **Combo of 2 or more:** `Format('%2d Combos' + #$FF + '+%3d x%3d%%', [combo, 20·k, 25·(combo + 3)])`, e.g. ` 2 Combos` over `+ 40 x125%` (0xFF breaks the line). Its top-left is at (tank x − 16, tank y + 12).
  - Base × multiplier is the score: 20·k × 25·(combo + 3) % = 5·k·(combo + 3).
- Both layouts roughly centre the monospace lines on the tank.
- **Motion** (two keyframes, 0x495238):
  1. 300 ticks: down 3 px, solid.
  2. 1500 ticks: up 30 px while the alpha falls to 128.
  3. Then the sprite frees itself (callback 0x495278).

## 4. Kills that show nothing

- **The bomb item**, taken by a player (case 7 of the pickup dispatch, 0x495bc5):
  - every enemy that isn't materializing gets its HP set to 0 through SetHP;
  - Damage never runs, so there's no chain, no combo, no score and no kill text.
- **An enemy's weapon** (attacker 0): the chain call takes it (only below 0 is skipped) into record 0, the enemies' slot, where nothing is known to show; the kill branch needs attacker > 0. (Corrected 2026-10-08: first written as −1.)

## 5. Other corner text, for reference

- The game makes two more Text2 sprites of its own (0x4980b4): one at (288, 10), and the credit count at (288, 454), `Credit %1.1d` (0x499054).
  - On a change, the credit count flashes to alpha 255 over 300 ticks, then goes back to 96 over another 300.
- The players' corner sprites 1–7 rest at alpha 96.

## The remake

**Kill text:** `KillText` (scripts/effects/kill_text.gd).
- `game.gd` spawns it in the kill handler for a kill credited to a player when the tank's health ran out. That means shells, fire, mines and blasts; the bomb leaves health untouched, so its kills show nothing, as in the original.
- **Look:** `white_font` (the stand-in for Text) at 24 px, i.e. Text at half size, doubled.
- **Position:** centred across the tank, its top 16 px (lone) or 24 px (combo) under the tank's top edge.
- **Motion:** down 6 px over 0.225 s, then up 60 px over 1.125 s while fading to 128/255.
- **Layer:** z 21, over the tank's explosion (z 20).

**Hit counter:** the `P1Hits` / `P2Hits` labels in game.tscn, driven by `GameManager.get_hit_chain`.
- It reads "N Hits", in the cyan of the Credit line, just above each player's "I P" / "II P" tag.
- It shows from a chain's second hit until the chain lapses.

**Deliberate differences:**
- **The numbers are the remake's own.** Hits and combos don't change its score (see stage_screens_original_spec.md), so:
  - the kill text shows the points the kill scored (the tank type's points) without a multiplier: `+ 100`, `2 Combos` over `+ 300`;
  - the counter shows the count alone, without the chain bonus.
- **Bomb kills** show no text, as in the original. But the remake still scores them and counts them in the combo (its kill-credit rule).
- **Placement:** the counter sits in the remake's side panel, not over the map's corner.

**Test:** scenes/test/kill_text_test.tscn.

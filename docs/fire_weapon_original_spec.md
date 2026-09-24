# Original Fire Weapon — Reverse-Engineered Spec

**Unit conventions used throughout.** The original runs a fixed-timestep loop: every logic frame consumes **20 "ticks" (MoveCount units)**; at the default game speed **1 tick = 0.75 real ms** (logic frame = 15 ms, 66.7 Hz). One original tile = 16 px; one remake tile = 32 px (double everything spatial). All conversions below use default speed. *(Evidence: DXTimerTimer @0x4c7960, `units = min(ms,100)·SPEED/75`, SPEED table {83,100,117,133,150} default 100; `Engine.Move(20)` @0x4c7d1b.)*

> ⚠️ One sub-report quoted bullet timings "in ms" by assuming 1 tick = 1 ms. The engine-level analysis (three independent traces) is authoritative: **1 tick = 0.75 ms**. Both raw ticks and converted seconds are given below.

---

## 1. Fire bullet (TArmsSprite, weapon type 2)

| Property | Original value | Converted (real time / remake px) |
|---|---|---|
| Damage / HP | 1 (table @0x4d2c30) | 1 HP; does **not** scale with gun level |
| Muzzle speed | 7000 speed-units = 0.2333 px/tick | **311 px/s** original → **622 px/s** remake |
| Deceleration | −1.5 speed-units/tick (table @0x4d2c60) | −88.9 px/s² → **−178 px/s²** remake |
| End-of-life speed | 5200 units | 231 px/s → 462 px/s remake |
| Lifetime | 1200 ticks (@0x4d2c90) | **0.9 s** |
| Max range | ∫v dt = **244 px ≈ 15.25 tiles** (distance is speed-independent) | **488 px ≈ 15.25 remake tiles** |
| Fire-rate cooldown | 180·(6−speedLevel) cooldown-units, −60/logic frame | **0.27 / 0.225 / 0.18 / 0.135 s** at speed level 0/1/2/3 |
| In-flight cap ("heat") | cost 8, cap 24+8·gunLevel; refunded on bullet death (@0x493a41) | **3 / 4 / 5 / 6 simultaneous fire bullets** at gun level 0–3 |
| Ammo | 30 per pickup, cap 150 (= 5× pack, @0x4d2c18); −1 per shot | same |
| Spread / lateral offset | **none** — spread tables apply only to Normal/Rapid (@0x49341c) | single straight bullet, no drift |
| Collision box | 14×14 (16px sprite inset 1px/side, @0x494004) | 28×28 remake |
| Sprite | `B_Fire` 128×16, 8 patterns = **2 frames × 4 directions**, AnimSpeed 0.03 fr/tick | ~**25 ms per frame** (2-frame flicker), Z=7 |
| Impact anim | `_B_32A` (imagelist idx 7, @0x4d2cd8) | play a 32px impact flash at drop point |
| Sound | wave 2 `S_Fire`, played **on shot only** (@0x4935a4); no burn loop | |
| Upgrade scaling | Gun level (0–3, from Power-Up/LEVEL-UP cookies, **not** from re-picking the Fire cookie) is copied onto the bullet (`+0xdc`) and only affects the **ground fire** it leaves (fuel, spread rate) plus the in-flight cap. Speed/range/damage never change. | |

**Movement & drop behavior.** The bullet flies straight, decelerating linearly. It "drops" (dies → ignites) on the **first** of: lifetime expiry (~15.25 tiles), hitting a wall tile it can't pass, hitting a tank, clashing with an opposing bullet, or the map border. Death always routes through `TArmsSprite.Die` (@0x4939f4), which for weapon 2 calls the ignition routine (@0x493b44) **at the bullet's current position**, then plays `_B_32A`. Range is therefore time-based (1200 ticks), not distance-tracked — but since decay is deterministic it is equivalent to a fixed ~15-tile range.

Wall behavior (TileHit @0x4940e4, damage-1 bullet): passes freely over all tile ids ≤23 (floor/ice/grass/scorch) and ≥68; **half-breaks one intact brick** (24..27 → half-broken variant facing shot direction) and dies; advances a half/corner brick one stage and dies; **degrades steel one hardness stage** (40..55 → +4) and dies; dies with no effect on super-steel (56..59) and border (60..67). It igniting "the wall face" is emergent: the 12-tile patch is stamped around the impact point and brick/steel tiles inside the stamp are simply skipped.

---

## 2. Ignition patterns

**Single universal stamp — every death cause uses the same routine** (@0x493b44):

- Center tile = `Round(bullet.X/16), Round(bullet.Y/16)` *(one trace read this as Trunc; Round is better-evidenced — minor UNCERTAIN, only matters for a half-tile bias)*.
- Loop `dx,dy ∈ [−1..2]` (4×4) with corner exclusion `dx+dy ∈ [−1..3]` and `dy−dx ∈ [−2..2]` → **exactly 12 tiles = 4×4 minus the 4 corners**. Clamped to playfield x∈1..40, y∈1..30.
- Per tile, the wall-layer tile must be in [−1..23] or [28..35]; **intact brick (24..27), steel/fortification/border (≥36) are skipped** (fire never sits on solids). Note: the original placement gate does **not** check the water/overlay layer — only *spread* does. Whether fire could visually sit on water is UNCERTAIN (tile-id semantics ≤23 not fully recovered).
- **Range-end drop, wall hit, tank hit, bullet-vs-bullet: identical pattern**, just centered wherever the bullet died. A tank hit therefore stamps the 12 tiles centered on the tank (the tank also takes 1 HP bullet damage from the clash itself).

**Fresh tile:** spawn fire with `strength := gunLevel (0..3)`, `fuel := Random(500)+1750+1500·strength` ticks, animation phase `(dx+dy+2) mod 8` (staggered so the patch doesn't blink in unison), arm delay 100 ticks (center 2×2 tiles: 50), registered in the fire grid.

**Stacking on burning ground (the real "growth" rule):** there is **no ring-size progression**. A new volley landing on an existing fire re-sets `strength` and pumps fuel:
```
fresh := Random(500) + 1750 + 1500·strength
boost := fresh·(strength+3)/9
fuel  := (boost ≥ fuel) ? fresh : fuel + boost
```
Growth beyond 12 tiles happens only via **fuel diffusion**: a fire with `strength ≥ 1`, owner-field ≥ 0, and **fuel ≥ 7000 ticks (5.25 s of burn)** pulses every `600−100·strength` ticks, transferring `(myFuel−neighborFuel)/4` to each of the 4 orthogonal neighbors (spawning a 0-fuel fire there if empty). Spread is blocked by brick/steel (wall-layer 24..27, ≥40) and by overlay-layer tiles 4..7. **Maximum size is emergent, not capped** — each pulse gives fuel away, so spreading self-quenches when fuel drops below 7000. Repeated volleys are the only way to reach the threshold.

---

## 3. Ground fire lifecycle (TFireSprite)

| Phase | Original | Converted (s) |
|---|---|---|
| Arm delay (invisible + harmless) | 100 ticks ring / 50 center 2×2 | 0.075 / 0.0375 s |
| Burn time (per tile, placement) | `Rnd(500)+1750+1500·L` ticks | L0: 1.31–1.69 s · L1: 2.44–2.81 s · L2: 3.56–3.94 s · **L3: 4.69–5.06 s** |
| Burn time (wildfire children / ctor default) | `Rnd(500)+3750` | 2.81–3.19 s |
| Terrain-ignite one-shot delay | `Rnd(500)+500` | 0.375–0.75 s after spawn |
| Spread pulse period (strength 1/2/3) | 500/400/300 ticks | 0.375 / 0.30 / 0.225 s |
| Extinguish | fuel −= 20/frame; at ≤0 → unregister + die | pure fuel exhaustion |

- **Decay/shrink:** none. There is **no random-extinguish roll and no fixed 5 s timer**; the ±500-tick (0.375 s) random term in each tile's initial fuel means tiles of one patch wink out **in random order over a ~0.4 s window** at the end — which *looks like* random tile-by-tile disappearance.
- **Animation:** `_B_Fire` sheet is 128×48 = 24 frames (16×16), i.e. **3 rows × 8 frames**. `AnimCount` is forced to 8 — a fire loops **one row forever** at AnimSpeed 0.015 fr/tick = **8-frame loop per 400 ms (50 ms/frame)**. The row is selected by the fire's owner field, **not by age**: owner<0 → row 0, Z=9 (drawn **above** tanks); owner=0 → row 1, Z=−1 (below tanks); owner>0 → row 2, Z=−2. *(One trace reported AnimSpeed 0.06 — the raw constant 0x3F8EB851EB851EB8 decodes to 0.015; 0.015 is correct.)*
- **Damage:** fire has no collision handler of its own; **tanks initiate** (TTankSprite.DoCollision @0x491cf0, shared by players and enemies). On overlap with an **armed** fire, if the tank's fire-immunity timer ≤ 0 and the sides differ: `tank.TakeDamage(1)`, then tank immunity := **1500 ticks (1.125 s)** if fire owner<0, **750 ticks (0.5625 s)** if owner≥0. So: 1 HP per immunity window while standing in fire (~0.9 HP/s vs owner<0 fire). Tank HP: default 2, max 8 — fire is lethal to loiterers.
- **Friend/foe:** `SameSide` (@0x4690d0) = true iff both owner fields >0, or both ==0. Player tanks are +0x74 = 1 (P1; presumably 2 = P2), so **player-owned fire never hurts players**. Enemy tanks: ctor default −1, one trace claims init to 0 — **UNCERTAIN** (see §5/§7). If enemies are 0: enemy fire never hurts enemies, hurts players (0.5625 s window). If enemies stay −1: enemy fire hurts *everyone including enemies* and draws above tanks. Kill credit: the fire's owner id is passed as damage source.
- **Wildfire chain (terrain ignition):** once, 0.375–0.75 s after spawn, each fire scorches adjacent grass tiles (wall-layer ids 8..11 → +4, permanent scorched 12..15) **and spawns a child fire** on each (immediately visible, strength 0, owner default −1, fuel 2.8–3.2 s, never diffusion-spreads, damages tanks, and repeats the char step itself) → a **slow grass-fire wave, one tile-generation per ~0.5 s**. Owner≥0 fires (the players', owner 1/2) additionally **melt the ice under themselves**: in the same one-shot step they read the ice/water layer `[0x4d74c8]` at their own tile and, if the id is below 4 (ice, ids 0..3), write −1 (bare ground) (@0x497a4e–0x497a80). *(Corrected 2026-09-24; this was first misread as "erase overlay ids 4..7".)* *(Known original quirk: diffusion-spawned and wildfire-child fires are never registered in the fire grid — duplicates can stack on one tile and they are invisible to the network sync. Replicate or fix consciously.)*

---

## 4. Interactions

- **Bricks/steel:** fire is never *placed* on them and never spreads through them; the *bullet* half-breaks brick / degrades steel one stage on impact (§1). Shovel-fortification walls (ids 40..64) are fully fireproof.
- **Water:** blocks fire **spread**: the spread step reads the ice/water layer `[0x4d74c8]` and stops on ids 4..7 (@0x4977e1–0x4977f2). Initial placement does not check that layer, so fire can land on water (and on ice).
- **Ice:** fire lands and spreads on ice freely, and a **player's fire melts the ice tile under it** once, 0.375–0.75 s after landing (the terrain step above); the tile becomes bare ground, so tanks stop sliding there. Enemy fire and grass-chain fire (owner −1) never melt ice. The ids are certain: the tank's own on-ice check (@0x4923dc–0x49244a) counts ids 0..3 of the same layer `[0x4d74c8]` as ice, and the remake's Stage.dat import agrees (ice codes 0x01–0x04 = file bytes 0..3, water 0x05–0x08 = 4..7).
- **Trees/grass:** grass (8..11) → scorched (+4) permanently + chain fire (§3). Remake equivalents: GRASS 0x09–0x0C → BURNED_GRASS 0x0D–0x10 (same +4 relationship already in `LevelData`, level_data.gd:160-163).
- **Powerups/cookies:** **no interaction** — cookies only react to tank contact; neither fire bullets nor ground fire touch them.
- **Eagle/base:** **no evidence of any fire→eagle damage path** (fire damage lives only in the tank collision handler; TFlagSprite has no fire branch). Treat the eagle as fire-immune. Its shovel wall ring is fireproof by the ≥36 gate.
- **Bullets over fire:** ground fire is non-solid; bullets and tanks pass through freely (tanks just burn).
- **Sounds:** `S_Fire` (wave 2) on firing only. No burning loop. Standard clink (12) when the surviving bullet of a clash is bigger; HitTank2 (11) on shield absorb.
- **Scoring:** normal kill credit via the damage-source id (fire passes its owner); no special fire scoring found.

---

## 5. Discrepancies vs the user's draft rules

1. **Rule 1 (4×4 minus corners = 12 tiles): ✅ EXACT MATCH.** Loops dx,dy∈[−1..2] with the two diagonal cuts (@0x493b9b/0x493ba8).
2. **Rule 2 (burns 5 s; 6th second random tile-by-tile disappearance): ❌ PARTLY WRONG.** Burn time is **level-dependent**: 1.3–1.7 s at gun level 0 up to **4.7–5.1 s at level 3** (`Rnd(500)+1750+1500·L` ticks × 0.75 ms). There is no separate random-extinguish phase; the per-tile ±0.375 s fuel randomness makes tiles die in random order over a ~0.4 s window. The "5 s + ragged end" description matches **only a level-3 fire**.
3. **Rule 3 (ring growth 5×5−4 → 8×8−4, shrink by 1 on expiry): ❌ DOES NOT MATCH.** Restacking re-stamps the **same 12 tiles** and adds fuel (`fresh·(s+3)/9`, or resets to fresh). Growth beyond 12 tiles is **fuel diffusion** to 4-neighbors, gated on fuel ≥ 7000 ticks (only reachable by stacking), pulsing every 0.225–0.375 s, transferring ¼ of the fuel difference. No ring shapes, no max cap, no shrink step — extinguish is per-tile fuel exhaustion. (The user's rule is a reasonable *approximation* of how stacked fires visually creep outward ~1 tile per pulse.)
4. **Rule 4 (max range 15 tiles, drops & ignites): ✅ MATCH.** 244 px ≈ 15.25 original tiles, implemented as a 1200-tick lifetime on a decelerating bullet; ignition on expiry confirmed.
5. **Rule 5 (hit enemy tank → drop & ignite at tank): ✅ MATCH,** with one addition: the clash itself also deals **1 HP direct bullet damage** to the tank (min-HP mutual exchange @0x4951f0) before the patch spawns centered on the impact point.
6. **Rule 6 (crossing enemy bullet → drop, ignite, reduce enemy bullet damage by fire's damage): ✅ MATCH in effect, mechanism differs.** The original rule is **mutual damage = min(HP_a, HP_b)** — since the fire bullet has HP 1, the enemy bullet loses exactly 1 (kills any 1-HP bullet outright, only dents AP at HP 8–14), and the fire bullet dies and ignites the crossing point. Implement it as min-HP exchange, not "subtract attacker damage", so AP behaves correctly later.

---

## 6. Proposed rule 7+ (original behaviors not in the draft)

7. **Ammo & throughput economy:** 30 ammo per pickup, cap 150; re-picking the Fire cookie only refills ammo (power comes from separate level-up cookies); at most **3+gunLevel fire bullets in flight**; cooldown 0.27→0.135 s by speed level.
8. **Arming grace:** each fire tile is invisible and harmless for 75 ms (center 2×2: 37.5 ms) — prevents point-blank self-immolation and gives the patch a staggered pop-in.
9. **Damage cadence, not contact damage:** 1 HP per tank per **1.125 s** (enemy-owned fire) / **0.5625 s** (player-owned) while overlapping; per-tank immunity timer, applies equally to players and enemies; **owner's own side is immune** to its fire (with the enemy-side UNCERTAIN noted in §3).
10. **Wildfire terrain propagation:** one-shot, ~0.5 s after each tile ignites: adjacent grass is permanently scorched (tile+4) and sprouts a chain fire → a creeping grass-fire wave (~1 tile per 0.5 s, each child burning ~3 s). This is the fire gun's signature map-altering effect and the draft misses it entirely.
11. **Layered rendering:** ground fire renders **below tanks for player/neutral owners** (rows 1–2 of the 24-frame sheet) and the sheet's 3 rows encode owner, not age; phase-staggered 8-frame loop at 20 fps.
12. **Fuel-stacking spread** (the faithful version of draft rule 3): threshold 5.25 s of fuel, pulse 0.375/0.30/0.225 s at strength 1/2/3, ¼-difference transfer, blocked by walls and water.
13. **Bullet utility vs terrain:** the fire bullet itself half-breaks bricks and degrades steel one stage on impact (then ignites around the impact) — it's a weak wall-breaker, not terrain-inert.
14. **Fire persists after the shooter dies**; heat (in-flight slot) is refunded to the owner when the bullet drops, tracked by tank UID.

---

## 7. Godot implementation blueprint

### Constants (remake units: 32 px tiles, seconds, per fire-strength L = weapon_level 0–3)

| Constant | Value | Source |
|---|---|---|
| `FIRE_BULLET_DAMAGE` | 1 | §1 |
| `FIRE_BULLET_SPEED` | 622 px/s start, decel 178 px/s² (or simplified: constant ~500 px/s) | §1 |
| `FIRE_BULLET_RANGE` | 480 px (15 tiles; original 488/15.25) | §1 |
| `FIRE_COOLDOWN` | 0.27 s (scale to 0.135 s at max speed level) | §1 |
| `FIRE_MAX_IN_FLIGHT` | 3 + weapon_level | §1 |
| ammo reload/cap | 30 / 150 — **already present** (cookie_data.gd:124) | §1 |
| `FIRE_PATCH_OFFSETS` | 12 tiles: dx,dy∈[−1..2] minus (−1,−1),(2,−1),(−1,2),(2,2) | §2 |
| `BURN_TIME` | `1.3125 + 1.125·L + randf()·0.375` s | §3 |
| `RESTACK_BOOST` | `fresh·(L+3)/9.0`; `fuel = fresh if boost ≥ fuel else fuel + boost` | §2 |
| `SPREAD_THRESHOLD` / `SPREAD_PULSE` / transfer | 5.25 s fuel / `0.45 − 0.075·L` s (L≥1) / ¼ of fuel difference | §2 |
| `CHAR_DELAY` (one-shot grass ignite) | `0.375 + randf()·0.375` s; child fire burn `2.8125 + randf()·0.375` s | §3 |
| `ARM_DELAY` | 0.075 s (0.0375 s center 2×2) | §3 |
| `REBURN_INTERVAL` | 1.125 s vs enemy fire / 0.5625 s vs player fire (or a single 1.0 s if simplifying) | §3 |
| Ground-fire anim | 8 frames @ 0.05 s (assets `ground_fire_r{1..3}_f{1..8}.png` already exist) | §3 |
| Fire-bullet anim | 2 frames; original 0.025 s/frame — add per-style `FRAME_DURATIONS` (current flat 0.5 s is far too slow for fire) | §1 |

### Files to create
- **`scripts/effects/ground_fire.gd` + `scenes/effects/ground_fire.tscn`** — Area2D, 28×28 RectangleShape2D, no collision layer, **mask bits 3 (player_tanks) + 4 (enemy_tanks)** (project.godot:120-129). Fields: `strength`, `fuel: float`, `hurts_players: bool`, `armed: bool`, `char_done: bool`. `_process`: arm-delay countdown → visible+active; char one-shot (ask LevelManager to scorch/chain neighbors); fuel countdown → `queue_free()` + grid unregister; 8-frame loop. Damage via periodic `get_overlapping_bodies()` (0.1 s poll) — **not** `body_entered` only (stationary-tank miss; precedent powerup.gd:100-102) — with a **per-tank reburn timestamp dict** implementing the immunity window; call `EnemyTank.take_damage(Vector2.ZERO)` (zero avoids retaliation-turn, enemy_tank.gd:591-595) and `PlayerTank.take_damage()` guarded by `is_invincible`. **Parent into `Playfield/TerrainLayer`** so it draws under tanks but over terrain (z rationale in codebase map; effects_container would draw over tanks).
- **`assets/sprites/bullets/fire/fire_1.png`, `fire_2.png`** — do not exist yet; 6–8×16 RGB, magenta (248,0,248) key, per bullet convention (bullet.gd:255-276).

### Files to modify
- **`scripts/tanks/bullet.gd`** — add `"fire"` to `BULLET_TEXTURE_PATHS` (:25-34); replace `FRAME_DURATION` (:23) with per-style `FRAME_DURATIONS`; add `max_range: float = -1.0` + `_traveled` accumulated in `_physics_process` (:98-116), destroy at 480 px; add `ignites_ground: bool` and `fire_strength: int`; in `_destroy()` (:206-229) — the single choke-point covering range-end, wall (:153-170), tank (:172-195), bullet-vs-bullet (:197-204) and boundary deaths, exactly mirroring the original's `Die` — call `_level_manager.ignite_fire_patch(_level_manager.world_to_tile(global_position), fire_strength, is_player_bullet)` (`_level_manager` resolved at :67-69). Keep 1:1 bullet annihilation for now (correct for HP-1 fire; revisit min-HP exchange when AP lands — bullets currently have **no HP/damage field**, see codebase-map gap 1). Optional deceleration for fidelity.
- **`scripts/tanks/base_tank.gd`** — extend `_spawn_bullet` (:89-128) / `_spawn_single_row_bullet` (:138-151) with optional fire params (or a `_spawn_fire_bullet` helper). Decide `can_destroy_steel` interplay (:106-107): original fire bullets *degrade* steel one stage regardless of level — flag as a deliberate remake choice.
- **`scripts/level/level_manager.gd`** — the fire grid lives here (it owns tiles, transforms, and the fortify-timer precedent :57-61): `var _fire_tiles: Dictionary # Vector2i -> GroundFire`; `func ignite_fire_patch(center: Vector2i, strength: int, from_player: bool)` stamping the 12 offsets, skipping out-of-bounds, WATER (BG 0x05-0x08), and solid FG (SOFT/HARD_BRICK, IRON, SUPER via `LevelData.get_tile_category`/`is_solid_tile` level_data.gd:60-102); `func ignite_tile(...)` handling dedup/restack-boost, GRASS→BURNED_GRASS (`code += 4`, retexture per `_update_hard_brick_visual` pattern :437-448); clear `_fire_tiles` in `load_stage` (:96-99). Spread/char callbacks land here too. Optionally route through a new `Events.ignite_tiles` signal (events.gd:19-21 pattern).
- **`scripts/autoload/cookie_data.gd`** — add `FIRE_FIRE_CONFIG` (mirror `RAPID_FIRE_CONFIG` :130-145; keys: cooldown, ammo_per_count, speed, range_px, plus burn constants) + `"fire"` branch in `get_weapon_fire_config` (:185-189); add tank-type rows **9–12** to `TYPE_WEAPON_LEVELS` (:105-110).
- **`scripts/tanks/player_tank.gd`** — `_shoot_secondary_fire()` mirroring `_shoot_secondary_rapid()` (:384-403); branch in `shoot_secondary()` (:374-382). Pickup/HUD/persistence already work for `"fire"` end-to-end (powerup.gd:186-187, game_manager.gd:181-196, game_hud.gd:96-99).
- **`scripts/tanks/enemy_tank.gd`** — clone the rapid trio: `_has_fire_special()` (:506-507 pattern), `_shoot_special_fire()` (:509-525), branch in `_fire_weapon()` (:492-504). Enemy ground fire: `hurts_players = true`, and per the original's friendly-fire rule enemies should be immune to enemy fire (subject to the UNCERTAIN below).

### UNCERTAIN items (do not silently guess)
1. **Enemy tank owner id — RESOLVED 2026-09-24: −1.** The tank constructor writes −1 (@0x4917a4) and nothing on the enemy spawn path overwrites it; the only other owner writes (@0x499316, @0x4993a0) give the players 1 and 2 by their slot number. determines whether enemy-lit fire hurts other enemies, its reburn interval (1.125 vs 0.5625 s), and whether it draws above tanks. Recommended remake stance: enemies immune to enemy fire, players immune to player fire, 1.125 s reburn vs hostile fire.
2. **Ice/water-layer ids — RESOLVED 2026-09-24:** ids 0..3 are ice (melted under a player's fire), ids 4..7 are water (block spread). Remake: fire burns on water and ice; a player's fire melts the ice.
3. **Round vs Trunc** for the patch center tile (half-tile bias only).
4. **Water under initial placement** — original stamp didn't check the water layer; recommend blocking it anyway.
5. **Eagle fire-immunity** — inferred from absence of a damage path, not from positive proof.
6. **Original quirk**: diffusion/wildfire child fires were never grid-registered (duplicate sprites per tile possible). The remake's `_fire_tiles` dict should register everything — a deliberate bug-fix.
7. Ground-fire PNGs have **no `.import` files yet** — load via `Image.load(ProjectSettings.globalize_path(...))` per project convention (MEMORY.md) or open the editor once before relying on `load()`.
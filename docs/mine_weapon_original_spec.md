# Mine Weapon — Reverse-Engineering Findings & Proposed Rules

*(6th / final secondary weapon. Reconstructed from `TMineSprite` @VMT 0x004903d8 and `TFlyingTank` @VMT 0x00490454. Blast reuses the same `TExploseSprite` as the explosion weapon. Please read Part B — one finding directly contradicts your current understanding.)*

---

## Part A — Mine weapon rules (please confirm)

### Laying a mine

1. **A mine is placed on a grid tile near/behind the tank — never under it, never free-floating.** When you fire the mine weapon, the game scans up to 12 candidate tiles on a ring about **2 tiles (64 px)** out from the tank, in an order rotated by which way the tank faces so the tiles **behind and beside** the tank are tried first. The first tile that is in-bounds, passable/empty, has no mine already on it, and isn't too close to another sprite wins.

2. **One mine per tile, hard rule.** If every one of the 12 candidate tiles is blocked, **no mine is laid at all**. The mine snaps to the center of its tile.

3. **Each mine costs 1 ammo; a pickup pack gives 15 mines.** There is **no simultaneous cap** in the original — you're limited only by ammo, the one-per-tile rule, and the fact that **mines never expire on their own** (infinite lifetime). So a tank can have a whole field of mines out at once, one per tile.

4. **Laying a mine plays a "lay" sound (orig sound id 5, `S_Mine`) and adds a cooldown** before the next secondary shot (orig `350 × (6 − fire-rate-upgrade)` heat units — higher fire-rate upgrade = shorter cooldown; exact seconds TBD, see Part B).

5. **The mine inherits the layer's side (owner) and takes its level from the tank's current mine-weapon level (1–4).**

### Arming & friend/foe

6. **A freshly-laid mine is INERT for ~0.22 s (≈15 frames) while it "arms."** During this window the engine excludes it from collisions, so the layer can drive off their own mine without setting it off. After arming, it becomes triggerable.

7. **Mines only hurt the enemy.** The mine remembers who laid it; the layer and their allies **never** trigger it (same-side check). Only an opposing tank driving onto the tile sets it off. (Player mines hit enemies; enemy tanks can lay mines that hit the player.)

8. **The mine is a CONTACT mine, not a proximity mine.** There is a proximity/blink indicator that lights up as an enemy nears (for player/neutral mines only), but that is **cosmetic** — the mine detonates on actual overlap/contact, not from distance.

### Triggering & detonation

9. **When an armed enemy tank overlaps the mine, the mine detonates immediately (all 4 levels).** Detonation spawns the **same `TExploseSprite` blast used by the explosion weapon**, centered on the mine tile.

10. **Blast footprint = an 8×8-tile box (256×256 px in the remake), with power scaling by mine level:** blast intensity `250 + 25 × level`, distance falloff `60 − 5 × level`. So level 1 ≈ power 275 / falloff 55, level 4 ≈ power 350 / falloff 40 (bigger, harder-hitting blast at higher levels). The blast does **line-of-sight-falloff area damage** to enemy tanks and **destroys destructible terrain** in the box — identical to the explosion weapon, just level-driven.

11. **Detonation sound:** at level ≥ 2 it plays a random mine-explosion sound (orig id 8 or 9, `ExploseMine1`/`ExploseMine2`). Level-1 detonation uses only the blast's own sound.

### The 4-level system

12. **Level sets the mine's sprite row and its blast strength (rule 10), and unlocks the fly effect.** In the `B_Mine` sheet (64×80 px = **4 columns × 5 rows** of 16×16; the 4 columns are the blink-animation frames, **not** levels), **the row = the level**: row 1 → lvl 1 … row 4 → lvl 4 (row 0 unused). Level 3 additionally switches to a slower "hot" blink on row 4 (a visual quirk — see Part B).

13. **Level 1: blast only** — no direct contact damage, no fly.

14. **Level ≥ 2 (the "fly" levels — SEE PART B, this may instead be levels 3–4): blast + a small direct hit + the victim is launched into the air.** Direct contact damage applied just before launch is small: **`level − 1` HP** to a basic tank, **`level − 2` HP** to other tank types — on top of the area blast. Higher level = longer/higher/farther fly (see rule 16).

### The fly mechanic

15. **On a qualifying hit the victim tank is thrown into the air as a `TFlyingTank`.** The real tank sprite is **hidden and deactivated (not destroyed)**; a stand-in "flying" sprite draws in its place, using the tank's own image. **The tank is helpless while airborne** — its move/collision flags are cleared and its position is force-set each frame, so it can't be controlled, hit, or hit anything until it lands.

16. **The throw is a spinning parabolic arc away from the mine.** Launch velocity = **5 × the tank's off-center offset from the mine** (a dead-center hit ≈ straight up; an off-center hit is thrown that direction). Altitude is a parabola (`altVel₀ = level + 2`, gravity `−5`); the sprite **grows as it rises** to fake height (peak size ≈ peak-altitude + 1). It also **tumbles/spins** (`spinVel₀ = level × 200`, decelerating), and a **coin-flip picks clockwise vs counter-clockwise**. Two simulated cases: input value 2 → **~1.2 s aloft, ~2.6× peak size, ~2.3 tumbles**; input value 3 → **~1.5 s aloft, ~3.6× peak size, ~4.3 tumbles** (which mine levels these map to depends on the indexing question in Part B). The tank is clamped to stay inside the 40×30 playfield.

17. **On landing (altitude returns to 0) the tank re-appears and gets hit by a SECOND blast.** It's restored to visible/active, dropped facing a **pseudo-random cardinal direction** (wherever the spin stopped), and a fresh `TExploseSprite` detonates on the **landing tile** — this one at **power = the victim's own weapon-upgrade level** (NOT the mine level) and **side = neutral (−1), so it damages the just-landed victim itself**. This is the "explosion effect on return" you described.

18. **Net result: a flown victim can eat up to three damage sources** — the small direct contact hit (rule 14), the mine's blast at the mine tile (rule 10), and the neutral landing blast at the touchdown tile (rule 17).

### Interactions

19. **Bullets can detonate a mine remotely, if strong enough.** A shot that hits a mine detonates it only when its power clears the mine's level (orig test: `round(bulletPower/25) − 10 ≥ mine.level`, re-checked after a small penalty). Weak shots do nothing. (Detonating a mine by shooting likely uses orig sound id 11 — inferred.)

20. **No chain reaction between mines was found, and eagle interaction is not covered by the RE.** A mine's blast damages *tanks* and *terrain*, not other mines, so mines don't set each other off (only bullets or tank-contact do). Whether a mine's blast can destroy the eagle / eagle walls is not evidenced — likely it destroys the surrounding brick like any terrain, but treat this as a remake design decision.

21. **Type-gating (only if the remake has heavy/special enemy types):** a "heavy" tank (orig type 2) only reacts to **level-3** mines and never flies; a "special" tank (orig type 4) never flies (and only reacts to fly-level mines from level 3 up). Normal tanks follow rules 13–17.

*todo: confirm the level-indexing (does the fly start at level 2 or only 3–4?), the cooldown→seconds conversion, and the eagle behavior before I write any mine code…*

---

## Part B — Notes for the reader

### Recovered constants (original → remake units)

| Quantity | Original | Remake |
|---|---|---|
| Tile size | 16 px | 32 px |
| Playfield | 640×480 px = 40×30 tiles | 40×30 tiles (1280×960 px) |
| Arm delay | ~15 frames (~0.22 s) | ~0.22 s |
| Placement ring | ~2 tiles (32 px) from tank | ~2 tiles (64 px) |
| Candidates tried | 12 tiles, facing-rotated | 12 tiles |
| Ammo per mine / pack size | 1 / 15 | 1 / 15 |
| Mine lifetime | 0 = infinite | infinite |
| Cooldown added | `350 × (6 − fireRate)` heat | **needs heat→seconds mapping** |
| Blast box | 8×8 tiles (128×128 px) | 8×8 tiles (256×256 px) |
| Blast power / falloff | `250 + 25·L` / `60 − 5·L` | same formula (scale HP to remake) |
| Direct contact dmg | `L−1` (basic) / `L−2` (other) HP | same |
| Fly launch velocity | `5 × center-offset` (px/sim-sec) | ×2 for 32 px tiles |
| Fly altVel₀ / gravity | `L+2` / `−5` | same |
| Fly spin₀ / spin decel | `L×200` / `−55`, random ± dir | same |
| Flight duration | 81 / 102 frames (1.215 / 1.530 s) | ~1.2 / 1.5 s |
| Peak size / spins | ~2.6× / ~2.3 rev vs ~3.6× / ~4.3 rev | same |
| Landing blast | power = victim's weapon level, side = **neutral** | same |
| Sounds | lay 5, detonate 8/9, bullet-kill 11 | map to remake SFX |

### Flagged UNCERTAIN items

- **⚠️ BIGGEST ONE — does the fly start at level 2 or only 3–4?** The two REs disagree. The deeper mine-side trace (which actually located `SetLevel` reading `tank[+0x128]` with values **1–4**) reads the fly guard `level ≥ 2` as **levels 2, 3, 4 fly** — which would *correct* your "levels 3–4" understanding. The flying-tank-side trace *assumes* the field is 0-based (0–3) and therefore lands back on **only levels 3–4**, matching you — but it admits it never found the code that writes the field. **My lean: the 1-based reading (fly at ≥ 2) has the stronger evidence, but this is exactly the thing to verify against the powerup/upgrade code before implementing.** It changes rules 14–16.
- **Cooldown in seconds** — `350 × (6 − fireRate)` is in engine "heat" units; the heat→seconds constant wasn't pinned. Absolute flight seconds (1.2 / 1.5 s) also assume 20 move-units/frame at 15 ms/frame; the *frame counts* are exact, so port the integrator (`alt += 20·altVel/1000` per frame, gravity −5, land at `alt ≤ 0`) rather than hard-coding seconds.
- **Level-3 "hot" look** — level 3 forces display to row 4 at a slow blink, so **levels 3 and 4 may render the same row**. Unclear if intentional art reuse; check `B_Mine` frame-by-frame.
- **The pre-launch "stun/immobilize" (orig `0x493644`)** applied on level ≥ 1 hits — its exact effect (freeze? duration?) was not disassembled.
- **`tank[+0x128]`** is read both as "the tank's mine-weapon level" (when laying) and "the victim's gun/upgrade level" (landing-blast power). Likely one "current weapon/upgrade level" field; confirm from the powerup code.
- **Chain detonation & eagle** — not evidenced (rule 20). Treat as design choices.
- **Placement spacing threshold** (min distance to other sprites) — exact units not extracted; only matters for faithful AI mine-spam.

### Suggested design choices

1. **Skip `TMineClient` (VMT 0x0049054c, instsize 21664).** With that instance size and only two `.rsrc` refs plus one code ref, it's almost certainly the **network/replay mine-field serializer**, not the in-game mine. Single-player mines don't route through it — leave it for a future networking pass.
2. **Reuse what you already have.** The detonation is literally your existing `ExplosionBlast` — instantiate it at the mine tile with `power = mineLevel` (intensity `250 + 25·L`, falloff `60 − 5·L`, LOS + terrain-destroy you already built), and again at the landing tile with `power = victim's weapon level, side = neutral`. No new blast code needed.
3. **Render the fly with the tank's own sprite:** hide the real tank (disable input/collision, don't free it), spawn a lightweight fly node that draws the tank sprite, drives the parabola + spin from rule 16, and **scales the sprite up with altitude** (`scale = altitude + 1`) for the "in the air" read. On landing, restore the tank facing the spin-derived direction and fire the neutral landing blast. Since the remake already flips `flying`-style flags for other effects, gate player input on that same flag.
# Explosion Weapon — Rules & Notes (for review before coding)

This is reverse-engineered from the old Delphi Battle City clone. Numbers are given in **remake units** (32px tiles, seconds) with the original values kept in Part B. The explosion is weapon type 4, the 5th secondary weapon.

---

## Part A — Explosion weapon rules (please confirm)

1. **The explosion bullet flies straight and fast.** It launches at ~356 px/s and accelerates (~940 px/s²) up to a cap of ~705 px/s. It has no spread, so it goes dead straight. Its lifetime is ~2.06 s, but at that speed it crosses the whole map long before then — so in practice its **range is "until it hits something."**

2. **The bullet explodes on impact with anything: a wall/brick/steel tile, an enemy tank, an enemy bullet, or when its 2.06 s lifetime runs out.** Every one of those causes it to die and spawn one big **shockwave** at the impact point.

3. **On a direct tank hit the bullet also does a small direct hit** (1 HP at gun level 0, scaling to 1 / 1 / 2 / 9 HP at gun levels 0/1/2/3) and leaves a little 32x32 impact flash — separately from the shockwave.

4. **The shockwave is an 8x8 tile box (256x256 px) centered on the impact.** It is strongest at the center and fades with distance (linear falloff), and **walls block it by line-of-sight** — tiles/tanks hidden behind a solid wall are shadowed and take nothing (it is NOT a plain square).

5. **The shockwave lasts ~0.225 s.** It animates outward from the center over 8 frames (center lights up first, wave expands as it fades out).

6. **The shockwave destroys terrain** — but only **once**, during the **second half of its life (last ~0.11 s)**. Inside the destroy radius, full bricks are broken and already-damaged bricks step to their next damage state; steel/water/base tiles are left alone. Destroy radius grows with level: **~1.9 tiles at L0 up to ~3.3 tiles at L3**.

7. **The shockwave damages tanks by area.** Every enemy tank overlapping a "hot" cell takes damage ≈ `round((power − distance·falloff)/100 + 0.25)` → about **3 HP at the center (4 at L3), tapering to 0 near the edge** (~2 tiles out at L0, ~3.6 tiles at L3). **No friendly fire** (same-side tanks are skipped), **any number of tanks** can be hit at once, and each hit tank gets ~0.19 s immunity so one blast hits it only once.

8. **Damage level = gun upgrade level 0-3** (same upgrade/star mechanic as the fire gun). Higher level makes everything bigger: power 250→325, gentler falloff 60→45, destroy radius ~1.9→3.3 tiles, direct bullet damage 1/1/2/9, and more bullets in flight at once (2/2/3/4). Fire cooldown is driven by the separate **speed** upgrade (~0.45 s down to ~0.225 s), and ammo comes in packs of 20 (cap 100).

9. **Interactions & chaining:** vs another bullet → both take `min(HP)` damage and the loser detonates at the crossing point; a strong-enough explosion can **set off a nearby mine (chain reaction)**, and a mine's own detonation spawns the exact same shockwave. **Two overlapping explosions do NOT merge** — each is independent.

10. **Sounds:** plays the explosion-weapon firing sound on the shot; the blast most likely uses an `S_Explose` / `ExploseShort` sound (mines use `ExploseMine1/2`) — exact sound wiring was not confirmed.

11. **todo:** decide (a) whether a normal explosion shot carries the **tank's gun level** so upgrades actually grow the blast, or always fires at level 0 (power 250, ~1.9-tile destroy radius) — the original didn't clearly show where the bullet's level field gets written; and (b) whether an **armored tank face** should reduce blast damage from that side (the original had a facing-based reduction we only partly decoded).

---

## Part B — Notes for the reader

### Recovered constants (original vs remake)

| Constant | Original | Remake | Notes |
|---|---|---|---|
| Tile size | 16 px | 32 px | double all spatial values |
| Bullet muzzle speed | 177.8 px/s | ~355.6 px/s | accelerates from launch |
| Bullet acceleration | 470 px/s² | ~940 px/s² | reaches cap ~0.37 s after launch |
| Bullet speed cap | 352.7 px/s | ~705.4 px/s | |
| Bullet lifetime | 2750 ticks | ~2.06 s | range-end detonation if it never hits |
| Bullet direct damage | 1 / 1 / 2 / 9 HP | same | by gun level 0/1/2/3 |
| Ammo per pickup / cap | 20 / 100 | same | |
| Cooldown (by speed lvl) | ~0.45 / 0.375 / 0.30 / 0.225 s | same | |
| Max bullets in flight | 2 / 2 / 3 / 4 | same | by gun level 0/1/2/3 |
| Shockwave box | 8x8 tiles = 128x128 px | 8x8 tiles = 256x256 px | centered on impact |
| Shockwave lifetime | 300 ticks | ~0.225 s | |
| Terrain-destroy window | last 150 ticks | last ~0.11 s | one-shot, second half of life |
| Tank hit-immunity | 250 ticks | ~0.19 s | so a blast hits each tank once |
| Power (by level) | 250 / 275 / 300 / 325 | same | unitless intensity |
| Falloff (by level) | 60 / 55 / 50 / 45 | same | intensity lost per half-tile of distance |
| Full blast radius | 2.08 / 2.50 / 3.00 / 3.61 tiles | 67 / 80 / 96 / 116 px | intensity > 0 |
| Terrain-destroy radius | 1.88 / 2.27 / 2.75 / 3.33 tiles | 60 / 73 / 88 / 107 px | intensity ≥ 25 |
| Center area damage | 3 HP (4 at L3) | same | `round((power − dist·falloff)/100 + 0.25)` |
| Intensity formula | `power − dist·falloff` | same | dist in half-tiles from center |
| Terrain-destroy threshold | intensity ≥ 25 | same | |
| Impact flash sprite | `_B_32B`, 32x32 | 64x64 | small hit flash, separate from shockwave |
| Shockwave sprite sheet | `_B_Explose`, 48x384 | scale up | 8 anim frames × 9 sub-tiles (marching-squares tiles) |

Timing note: the original runs at 0.75 ms/tick, 20 ticks per logic frame (~66.7 Hz). All the tick counts above are exact; the seconds assume 20 ticks/frame. If the remake's frame step differs, keep the **tick-count ratios** (e.g. terrain destroys in the second half of the shockwave's life) rather than the literal ms.

### UNCERTAIN — please double-check these

- **Bullet's gun-level source (biggest one).** Where the bullet's level field gets written was never traced. A standard shot is *likely* level 0 (power 250, ~1.9-tile destroy radius, 3 HP center), but it's plausible the intent was for it to inherit the tank's gun level. This decides whether upgrading the gun actually grows the blast. → tied to rule 11.
- **Armored-face damage reduction.** The blast's tank-damage code builds a per-face table from the target's facing so an armored side *can* block/reduce damage, but the exact face→direction mapping and the reduction amount were not fully enumerated. Structurally real, numerically unconfirmed.
- **`Add_ExploseData` queue is NOT a gameplay feature — it's multiplayer netcode.** One analysis first guessed it was a "secondary/queued blast" system; a deeper pass proved it is a **network delta-replication queue** (it broadcasts local explosions to peers and re-spawns remote ones, which run in a "don't touch terrain" mode so map edits aren't applied twice). **For a single-player remake, ignore it entirely** — every explosion is a local, terrain-destroying blast.
- **Does the shockwave damage tanks?** Confirmed **yes** (the blast's own collision handler applies `TakeDamage` to overlapping enemy tanks). One of the three analyses initially marked this "uncertain" only because it looked at the wrong method — the other two decoded the damage path clearly. Treat area tank damage as real.
- **Sounds.** The firing sound (weapon slot 4) is confirmed; the blast's own `S_Explose` / `ExploseShort` and mine `ExploseMine1/2` wiring was not traced. Pick reasonable SFX.
- **Exact damaged-brick tile codes.** Only the *transformation bands* were recovered (which tile-code ranges clear vs. step to the next damage state); the concrete brick/steel/water tile-ID taxonomy lives in the remake's own `LevelData`/`LevelManager`, so map the bands onto our existing tile codes rather than copying raw numbers.

### Suggested design choices where the original is ambiguous

1. **Drop the netcode entirely and make every explosion a local terrain-destroying blast** (the `flag = 0` path). This removes the `Add_ExploseData` queue, the double-buffer offset mismatch, and the client/host authority questions in one stroke — none of it matters single-player.
2. **Have a normal explosion shot carry the tank's current gun level** (like the fire gun's strength), so the star/upgrade meaningfully grows the blast (power 250→325, destroy radius ~1.9→3.3 tiles). It's the more fun and consistent reading; confirm in rule 11.
3. **Skip the armored-face damage reduction for v1** unless our tanks already model directional armor — just apply the falloff damage to every overlapping enemy tank. It's a small, unverified refinement that can be added later without changing the core feel.
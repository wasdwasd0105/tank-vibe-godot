## AP weapon — revised rules (please confirm before I code)

### Part A — AP weapon rules (remake units: 32px tiles, seconds)

1. **Slow but powerful — with a twist.** The AP bullet launches slow (222 px/s, about 1/3 of a normal bullet) but it *accelerates* (+889 px/s²) and after 0.5 s it tops out at 667 px/s — actually faster than a normal bullet at the end. It's the only bullet besides explosion that speeds up. Single straight shot, no spread at any level. It effectively never expires (lifetime 2.06 s ≈ flies the whole map) — it goes until it spends all its damage points or hits the map border.

2. **Damage pool by weapon level.** The bullet carries one number that is both its HP and its damage: **8 / 10 / 12 / 14 points at level 0/1/2/3**. Much greater than any tank's HP (enemies are 1-7), just like the draft says.

3. **Pass-through tanks — exactly as the draft.** Hit a tank: both sides lose `min(pool, tankHP)`. If pool > tank's HP, the tank dies and the bullet keeps flying with `pool − tankHP` remaining, then goes through the next tank, and so on until the points run out. If the remaining points < the next tank's HP, that last tank just takes all the remaining damage and the bullet dies there. If exactly equal, both die. (Original quirk: the leftover was clamped to max 8 after the first hit, so a level-3 bullet killing a 2-HP tank continued with 8, not 12 — see todo.)

4. **Bullet-vs-bullet.** Same min-damage exchange the remake already has: AP eats a normal/rapid bullet losing only 1 point and flies on; AP vs AP, both lose the smaller pool (equal levels = both die).

5. **Walls — AP drills through them too.** Every wall tile it touches costs points from the same pool: full brick destroyed outright = 2, half/quarter brick = 1, steel = its remaining stages (1-4; destroyed if the pool covers it, else the steel is degraded and the bullet is spent), fortified super-steel needs current pool ≥ 6 and costs 8, map border always kills the bullet. So roughly: level 0 drills 4 brick rows or 1 super-steel; level 3 drills ~5-7 bricks or a super-steel plus more. When the shell straddles two tile rows it breaks both but only pays the more expensive one (carves a 2-tile-wide channel).

6. **Moon shield front hit — draft was almost right.** Original: any bullet front-hitting the moon shield dies harmlessly (tank takes zero). Special: an AP bullet whose *current* pool is ≥ 6 first **destroys the shield**, tank still takes no damage, AND the tank gets a **1.125 s invulnerability grace** — then the AP bullet is used up (it does NOT continue). A fresh AP always qualifies (8-14 ≥ 6); an AP already ground down below 6 by walls/tanks is just absorbed and the shield survives. The draft said "destroy shield, no damage" — same spirit; the ≥6 condition and the grace timer are what the binary adds. Pick in todo.

7. **Mines.** AP cannot set off mines — not by touching, not remotely. Only blasts detonate mines. No interaction at all.

8. **Eagle.** No special rule: eagle has 1 HP, AP kills it losing 1 point and flies on (a normal bullet would die on it).

9. **Ammo / rate / in-flight.** 10 per pickup, cap 50 (already in WEAPON_DATA). Cooldown ≈ 0.6 s — in the original this scaled with the *speed* upgrade (0.60/0.51/0.40/0.30 s), NOT the gun level. Max AP shells in flight: **2/2/3/3** at level 0-3 (heat 16 vs cap 24+8·level; heat refunds when the bullet dies).

10. **Death effect.** Plain 64px impact flash, no blast, no terrain mark. Fire sound = S_Armor; shield absorb = clang.

**todo…** (a) moon shield: keep original's "pool ≥ 6 + 1.125 s grace", or the draft's simpler "always destroy, no grace"? (b) keep the wall-drilling from rule 5 (recommend yes — it's AP's identity) and keep or drop the original's "remainder clamps to 8" quirk? (c) cooldown: fixed 0.6 s, or scale 0.6→0.3 with weapon level since the remake has no separate speed upgrade?

---

### Part B — Notes

#### Constants (original → remake ×2 spatial)

| Constant | Original | Remake |
|---|---|---|
| Weapon index | 3 (of 0-5) | `"ap"` |
| Damage pool (= bullet HP) by level 0-3 | 8 / 10 / 12 / 14 | same |
| Muzzle speed | 111 px/s | **222 px/s** |
| Acceleration | +444 px/s² | **+889 px/s²** |
| Max speed (reached 0.5 s) | 333 px/s | **667 px/s** |
| Lifetime / range | 2.0625 s ≈ 39.5 tiles (whole map) | 2.0625 s ≈ 1264 px |
| Ammo pack / cap | 10 / 50 | same (already coded) |
| Heat cost / cap → in flight | 16 / 24+8L → 2/2/3/3 | same counts |
| Cooldown (by SPEED level 0-3) | 0.60 / 0.51 / 0.40 / 0.30 s | see todo (c) |
| Collision box | 14×14 px | 28×28 px |
| Wall costs | brick 2, half/¼ 1, steel 1-4, super-steel 8 (needs ≥6), border ∞ | same points |
| Shield front strip | 48×16 px on facing edge | 96×32 px |
| Shield-break threshold / grace | pool ≥ 6 / 1.125 s invuln | same |
| Post-exchange HP clamp | remainder capped at 8 | see todo (b) |
| Impact flash | 32×32 (_B_32B) | 64×64 |

#### UNCERTAIN (flagged from RE)

- **1.125 s shield-break timer semantics**: code-verified as the standard invulnerability flag/timer, but whether it also gates the tank's other actions was not fully traced.
- **Enemy knockback on surviving hit**: shielded enemies always turn to face the shooter, unshielded 50%; the "slide 6" side-effect and its gating tank field are unverified — treat as optional flavor, skip initially.
- **Enemy gun level source**: enemies observed firing 8-14 HP AP bullets, but the AI path assigning per-type levels wasn't traced. Remake: give enemy AP a per-enemy-type level like other weapons.
- **Stale-stack shield rect quirk** (unshielded tanks could theoretically fake a front block in the binary): clearly unintended — implement the intended semantics (shield test only when the addon is active).
- **Cooldown drain cadence** (affects seconds slightly, not ticks): mild uncertainty.
- Earlier explosion spec's in-flight cap (2/2/3/4) conflicts with this trace's gate math (2/3/4/4) — worth a one-line re-check when convenient.

#### Suggested design choices

1. **Moon shield**: adopt the original in full — the ≥6 threshold means a worn-down AP can't strip the shield (rewards clean shots), and the 1.125 s grace prevents an instant follow-up cheese kill. The draft's version is a strict subset, so this only adds depth.
2. **Wall pierce + clamp**: keep wall-drilling (it makes AP feel different from every other gun and pairs naturally with rule 3), but **drop the ≤8 remainder clamp** — it's a Delphi SetHP artifact that silently nerfs levels 2-3 and contradicts the clean "pool" mental model in the draft. If authenticity is preferred, keep it; it only matters after the first hit.
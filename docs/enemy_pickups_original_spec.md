# Enemy Pickups — Reverse-Engineered Spec

How enemy tanks take bonus items in Tank.exe v1.22, what each item does in an enemy's hands, and how the upgrades an enemy took come back out. In the remake, `Cookie` (scripts/powerups/powerup.gd) handles the pickup, `EnemyTank` (scripts/tanks/enemy_tank.gd) holds the stats, and `game.gd` handles the effects aimed at the players. The test is `scenes/test/enemy_pickup_test.tscn`.

**Units.** 1 tick = 0.75 ms (1000 ticks = 0.75 s). The remake's positions are the original's at 2×.

**Numbering.**
- Item numbers below are the original's. The remake's `CookieType` agrees for 0–12 and 20–24. The original's 13–19 are the remake's `INVINCIBLE_HELMET` (13), `FLAG_PROTECTION` (14), `TANK_WEB` (15), `TANK_BOMB` (16), `TANK_LIFE` (17), `BULLETS_MAX` (18) and `BULLET_REFILL` (19).
- An enemy's original type is 4–27, its remake id + 3. So an **odd original type is an even remake id**: the stronger tank of each pair, the one with the add-on.

---

## 1. Who may take what (0x49595b–0x4959b0)

Players take everything. An enemy takes an item only if one of these holds:

- **Its own gun's item:** item − 19 equals its weapon (e div 4: 0 plain, 1 rapid, 2 fire, 3 AP, 4 explosive, 5 mine). So a plain-gun tank takes "Caisson" (19), a rapid tank "Rapid Gun" (20), and so on to "Mine" (24).
- **An upgrade or add-on (0–8),** if its original type is odd (remake id even).
- **An upgrade, add-on or special (0–8, 13–19),** if it wears memory-save (add-on 4).

Beyond the filter:
- The score items (9–12) always fail it.
- A tank still materializing can't take anything, nor can one on a mine flight: the flight hides it and turns off its collision (0x49a6d4).
- A frozen enemy still takes items; its movement step still runs collision (0x492272).
- A refused item stays where it is, and the enemy drives over it.
- No AI seeks items or avoids them.

The remake checks overlap every frame, as the original did. An enemy parked on an item it couldn't take picks it up as soon as it may, for example once a MAX has made it the stronger type.

## 2. Every pickup

- The taker gets **+1000 ticks of invulnerability, added to whatever it has** (0x4960ba). It can't be hurt or mine-slowed meanwhile.
  - Below 3000 ticks the tank blinks, drawn every other frame (0x4921b0).
  - A bomb or a mine throw still gets through.
- **Sound:** GetCookie plays.
- **Words:** the item's words show, as for a player (see `PickupText`).
- **Score:** none. The pickup's +100 goes to taker id −1, which the score routine ignores (0x498c9f).

## 3. What each item does

| Item | Taken by an enemy |
|---|---|
| 0 Speed Up | speed +1 |
| 1 Armor Up | HP +1 (to 8) |
| 2 Power Up | gun +1 (to 3) |
| 3 LEVEL UP | all three |
| 4 MAX | **every** enemy not materializing, the taker included: even original type → type + 1, speed +1, gun +1, memory-save if it wears no add-on; HP unchanged (0x495de9) |
| 5–8 add-ons | the taker's add-on becomes this one (a tank has one add-on slot) |
| 9–12 score | never taken |
| 13 Who PA Who | every enemy, materializing ones too, gets the moon shield in place of its add-on |
| 14 Flag On Guard | the base's own tick routine runs once with 30000 ticks (0x494710): every guard timer drops by 30000 |
| 15 Hold Enemy | the **players** are held for 10000 ticks (7.5 s) |
| 16 Bomb !! | every player tank that exists and isn't materializing has its HP set to 0, whatever its invulnerability; it dies as usual (a life, then respawn) |
| 17 +1 UP | +1 enemy for every type with enemies still waiting, and +1 of the taker's own type (once, even if it is also waiting); the reserve grows by as many; UpRest plays once per type (0x495c9a) |
| 18 MAX Caisson Armor | every enemy not materializing: even type → type + 1, HP +2, +1 ammo pack |
| 19 Caisson, 20–24 guns | +1 ammo pack of its own weapon; the weapon never changes |

- **Mine slow:** items 0–3 and 5–8 clear the taker's (0x495a21, 0x495a8a). MAX and MAX Caisson Armor clear it for every enemy they reach. No other item does.
- **Caps:** HP 0–8, gun 0–3, speed −4..4, ammo 0–5 packs.
- **What the type change affects:**
  - The sprite column.
  - The pickup filter.
  - The type +1 UP adds.
  - The hit downgrade's base values (§4).
  - The death drop.
  - Not the kill score: `type div 2` is the same for the pair. Not the results cell either.

### The remake

- **Speed.** The original's speeds step by about ×1.4 (table 0x4d2d00). The remake's enemy speeds are its own (64 / 96 / 128 px/s from Sean's tank table), so a speed item adds one remake step, +32 px/s, up to 192 px/s, the players' top speed.
- **Gun level.** Items raise `special_weapon_level`: rapid, fire, AP and explosive enemies fire at the higher level, and mine enemies lay higher-level mines (still capped at L2). The plain gun has no levels in the remake. In the original, gun levels allow more shells in flight: 3/4/5/6.
- **Ammo.** The remake's enemies never run out of special ammo, so ammo packs add nothing. Caisson and the gun items are still taken, which denies them to the players. In the original, an enemy spawns with one pack (two for an odd type) at normal difficulty and falls back to the plain gun when empty (0x491962).
- **Flag On Guard.** A player's pickup gives the wall ring 30000 ticks (0x494555), so an enemy's pickup ends a single fortification at once; only a ring stacked from several pickups survived it. The remake's fortification never stacks, so an enemy's Flag On Guard ends it at once. The walls go back to the map's own, the remake's existing revert.
- **Hold Enemy on the players.** The hold is GameManager `players_frozen`. The remake's GameManager is pausable, so the hold stops while paused.

## 4. Knocking an upgrade back out (Damage, 0x492763–0x4927f7)

**When it applies:**
- Only on a hit the enemy survives: a fatal hit goes straight to the kill.
- Only on the ground: a mine's hit lands while the tank is airborne.
- Only when it takes damage: an invulnerable tank ignores the hit, and a shot the moon shield blocks deals none.
- Any attacker counts.

**At most one loss per hit, in this order:**
1. The add-on, if 2 × HP ≤ the type's base HP: it loses the add-on and drops its item.
2. Otherwise the gun: if gun > the type's base + the difficulty bonus, gun −1 and it drops **Power Up**.
3. Otherwise the speed: if speed > the type's base + the difficulty bonus, speed −1 and it drops **Speed Up**.

**The drop:**
- It lands on a random tile-aligned spot, sliding there from the tank (0x492fdc).
- It becomes pickable after 1500 ticks.
- It lasts 11,500 ticks, against 36,500 for other items.

**The remake:**
- Steps 2 and 3 are ported (`EnemyTank._lose_an_upgrade`). The base is the enemy's current type's own gun level (`CookieData.get_enemy_weapon_level`) and speed (`TYPE_STATS`).
- Only upgrades an enemy took, or a MAX gave it, are ever above base. Enemies that took nothing never drop anything this way.
- The item is flung like the remake's other drops (`_spawn_cookie_at_position`) and keeps its normal lifetime.
- Step 1 stays the remake's own rule: an add-on drops on the second hit of a tank that started with more than 2 HP. On a hit where that rule drops an add-on, nothing else is lost.

**Not ported (Sean's own drop rules stay):**
- The original's death drop. Every odd-type tank, whether that is its own type or one a MAX gave it, always drops one item on death, drawn from Random(140) (0x491e2c). Even types drop nothing.
- The remake keeps its 60% death drop from its cookie table.

## 5. Hold Enemy on the players (0x49495a–0x4949e0)

- Every player's update checks one global timer (0x4949fd). A held player can't drive or fire; a player who spawns during the hold is held too.
- Held players still take damage: the damage routine has no hold check.
- **Overlay:** Tank_T (48×48, drawn at −8, −8, so centred on the tank):

  | Hold left | Shown |
  |---|---|
  | above 5000 ticks | the ringed web (row 2: remake `freeze/`) |
  | 1000–5000 | the bare web (row 3: remake `thaw/`, cut from `extracted_bitmaps/png/Tank_T.png` like the others) |
  | 1000 and below | nothing |

- **The helmet:** its wreath shares the overlay slot, and the hold's frames cover it while they show. Once the hold is down to 1000 ticks, the wreath is back.

### How a held tank moves (both sides)

A hold stops a tank's commands, not its motion: players and enemies share one movement step (0x492244), and the hold only skips the update that issues commands (enemies 0x494d08, players 0x4949fd).

**The movement step.** Every frame (20 ticks), a tank with speed above 0 steps speed/10000 × 20 px along its facing (0x49248e). It first snaps across its travel to the 16 px grid (0x4923ab). If either tile ahead is a wall (id ≥ 24, 0x492be0), water without AmphiTank (0x492a60), or a tank is in the way (+0x100), speed becomes 0 instead (0x492586).

**Speed.** Only the commands change it, sent every 40 ticks (0x49180c):
- The facing direction: speed + a, where a = T·60/1000, up to T·650/1000.
- Another direction: speed − 2a, turning once at 200 or below.
- No direction: speed − 2a, down to 0.
- On ice, a and 2a are divided by 8.

**So a held tank:**
- If it was moving, it glides on straight at the speed it had, since nothing brakes it. Blocked, it stops dead: no sliding, no corner-cutting, no turning. It stays there until the hold ends.
- If it was standing still, it stays put.
- Nothing pushes it sideways. The only sideways shift in the movement code is the 16 px snap on a change of axis, which a straight glide never needs.
- When the hold ends, an enemy re-issues its stored direction (+0x134) and a player reads input again.

**The remake:** `BaseTank.glide_while_held(opponents)`. A held tank keeps its velocity and moves with `move_and_collide`, so it never slides. It stops at the first contact, or when a tank of the other side is ahead (`_opponent_ahead`). Frozen enemies and held players both use it. The remake's tanks drive at full speed at once, so a moving tank glides at full speed. Test: `scenes/test/hold_glide_test.tscn`.

## 6. Losing anti-water on water

- The movement check tests only the two leading-edge tiles in the direction of travel (0x492a60). There's no sinking.
- A tank that loses AmphiTank in open water is stuck there until it gets AmphiTank back. Near the shore it can drive out, then water blocks it as ever.
- The enemy's Who PA Who makes this common, since it strips every enemy's add-on.
- **The remake:** Godot would shove the tank out of the water in sudden jumps. So `EnemyTank` puts the water tiles it's sitting on into its collision exceptions (`_stay_afloat`), and drops each one once the tank has driven off it (`_tick_afloat`).
- Players are unchanged: the remake still sinks a player who loses the boat afloat.

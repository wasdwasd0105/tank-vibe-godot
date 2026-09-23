# Original sound set — reverse-engineering findings

Where every sound in `res://assets/sounds/` came from and what fired it in the
original `Tank.exe` v1.22 (Delphi + DelphiX, PE32). Extracted and mapped
2026-09-22 from `Tank V1.22/Tank.exe`.

## Where the sounds live in the exe

19 waves are embedded in a DelphiX `TDXWaveList` resource; **the item's position
in that collection is the integer sound id the game code passes around**. Two
more are loaded from disk at runtime and appended to the same list as items
**19** and **20**, so ids 0-20 form one continuous table.

The collection order was proven, not assumed: in the resource each item's `Name`
property is followed by its own `RIFF/WAVE` blob with no other `Name` in
between, 19 times, with no empty items — so file order and collection order
cannot disagree.

## The dispatcher

```
PlaySound(Id: Integer /* EAX */; Replicate: Boolean /* DL */)   @ 0x00490cd4
  if Replicate and MsgServer <> nil:  Add_SoundData(...)     ; network replication
  item := TDXWaveList([0x4d74c4] + 0x28).Items[Id]           ; via TCollection.GetItem
  if item.loaded: item.Play(Wait := False)
```

There is no volume, pan or position argument — the original mixes every sound
flat. `Replicate` only broadcasts to network peers; it does not affect local
playback.

## The mapping

Confirmed by five independent agents reading the disassembly plus adversarial
re-derivation; every row below was traced to a concrete call site.

| id | original name | remake file | fires when |
|----|---------------|-------------|------------|
| 0 | `S_Normal` | `fire_primary.wav` | Primary gun shot — **player tanks only**; enemy normal shots are silent |
| 1 | `S_Rapid` | `fire_rapid.wav` | Rapid weapon shot, any tank, **one per bullet** |
| 2 | `S_Fire` | `fire_fire.wav` | Fire weapon shot, any tank. On the shot only — there is no burning loop |
| 3 | `S_Armor` | `fire_ap.wav` | AP weapon shot, any tank |
| 4 | `S_Explose` | `fire_explosion.wav` | Explosive shell **launch** — not its detonation |
| 5 | `S_Mine` | `lay_mine.wav` | A mine is laid, **only if a free tile was found** |
| 6 / 7 | `ExploseShort1/2` | `explode_1.wav`, `explode_2.wav` | A tank is destroyed, **or the eagle/base is destroyed** — `Random(2)` picks one |
| 8 / 9 | `ExploseMine1/2` | `mine_explode_1.wav`, `mine_explode_2.wav` | A mine detonates **and its level ≥ 2** — level-1 mines detonate silently. `Random(2)` |
| 10 | `HitTank` | `tank_hit.wav` | A tank took damage and **survived** it |
| 11 | `HitTank2` | `shield_absorb.wav` | Damage fully **absorbed by the directional/moon shield** — no HP lost |
| 12 | `HitWall` | `bullet_clink.wav` | Bullet-versus-bullet clash: the **surviving** bullet's clink |
| 13 | `HitWall2` | `powerup_appear.wav` | **A bonus appears on the field.** Despite the name this is not a wall sound — it fires where the stage's hidden power-ups are revealed |
| 14 | `GetCookie` | `powerup_pickup.wav` | Any power-up/cookie collected (all 25 types) |
| 15 | `UpRest` | `extra_life.wav` | A life counter goes up by one — an extra life |
| 16 | `Reware` | `bonus_reward.wav` | End-of-stage bonus award (the name is a misspelling of "Reward") |
| 17 | `Select` | `ui_select.wav` | Menu selection / confirmation |
| 18 | `SignIn` | `player_join.wav` | A player spends a credit and joins |
| 19 | `StageWin.wav` | `stage_win.wav` | Stage-end screen with lives remaining |
| 20 | `StageLose.wav` | `stage_lose.wav` | Stage-end screen with **zero** lives left — game over |

Ids 19/20 are chosen by a two-entry table at `0x004d40bc` = `{20, 19}` indexed
by `Ord(total_lives > 0)`, at the single call site `0x004ca1dd`.

### Two names that mislead

`HitWall2` is not a wall sound (1.73 s is far too long for a clink), and
`Reware` is not a typo-free word. Both were traced to their real call sites
rather than guessed from the name, which is why the remake renames them.

## Several sounds are derived from others

Measured directly from the PCM, not inferred:

- `HitTank2` **is** `HitTank` at half speed — decimating it by two reproduces
  `HitTank` sample-for-sample (100% exact), with linear interpolation filling
  the gaps. One octave lower, twice as long.
- `ExploseMine1/2` are `ExploseShort1/2` an octave down the same way
  (r = 0.97, exactly 2× the samples at the same rate).
- `ExploseShort1` vs `ExploseShort2` **are** genuinely different recordings
  (r = −0.14) — a real variation pair, as are the two mine blasts.

So the original built its "bigger" variants by halving playback speed. A remake
can do the same with one file and `pitch_scale = 0.5` instead of shipping both.

## Audio format

All mono 8-bit PCM except `S_Armor` (16-bit). Sample rates vary per sound and
are part of the character — 22050 Hz for the crisp ones, and deliberately odd
rates (2919 Hz, 4133 Hz, 8363 Hz) for the low, crunchy explosions and the rapid
gun. Resampling them to a uniform rate would change how they sound.

## Completeness

The 21 sounds are the whole set. `winmm.dll` is imported only for `timeGetTime`
and joystick calls — there is no `PlaySound`/`sndPlaySound`/`waveOut`/MCI/MIDI
path, no CD audio, and no other audio resource in the binary. The game has **no
background music during play**; the only long tracks are the two stage-end
jingles.

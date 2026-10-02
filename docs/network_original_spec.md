# Network Play — Reverse-Engineered Spec

How Tank.exe v1.22 plays over a network (联网游戏): the session, who runs the game, what goes over the wire, and the host's controls. It comes from the readme (sections 三 and 四, the v1.0.0–v1.1.1 notes and the 关于联网 FAQ) and the disassembly. The network code is DelphiX's `TDXPlay` component (a DirectPlay 4 wrapper from DirectX 7) on the main form, with the game's own messages on top.

**In one line:** only the host runs the game. The clients are remote screens: each sends its players' keys, and draws whatever sprites the host last sent.

## 1. The session

- **Transport:** DirectPlay 4 (`IDirectPlay4A`), over IPX or TCP/IP, whichever the wizard picks. Every message is sent **guaranteed** (reliable and in order, `DPSEND_GUARANTEED`, 0x47a7ac). The component has `Async = False`, and a message must be at least 4 bytes.
- The component's DFM holds the fixed session GUID {61AE8614-4993-4AE2-AC8E-CC7440F7A594} and `MaxPlayers = 4`. So there's one host and up to 3 clients.
- The session is created with `DPSESSION_MIGRATEHOST | DPSESSION_KEEPALIVE` (0x44, 0x47a4d0). The game never handles a host migration.
- **Starting:** the title's 联网游戏 button (`bbnNetworkClick`, 0x4cf9d8) runs DirectPlay's wizard (TDelphiXDXPlayForm, captioned "决战坦克 通讯设置……", via `Open` 0x479e14).
  - The pages are: provider, then new game or join.
  - **New game:** enter a session name and a player name (14 characters at most).
  - **Join:** enter the host's IP, pick the session from the downloaded list, and enter a player name.
  - Cancelling returns to the title.
- **Host or client:** after opening, the local player is Players[0]. **IsHost := the session held only this player** (0x47a09b–0x47a0ad), i.e. "I was alone", not "I created it". The mode byte (form+0x328) is 1 for the host and 2 for a client (0x4cfa10), and 0 in single player.
  - The window caption gets the suffix 单机, 联网主机 or 联网客户机.
- **The readme's advice:**
  - The fastest machine should host.
  - A virtual IP gateway (NAT) between the machines breaks the session list.
  - The FAQ adds: the game can't cross two different regional networks. A client must go fullscreen (F4), which "matters a lot for speed". If it's slow, turn the host's effects off, set its network speed to the maximum, or swap host and client.
- **Version check:** the host's hello carries the words 1, 2, 2, 184 (0x4cca51). A client checks only the first two (0x4ce1fd). On a mismatch it shows "游戏主机的版本跟您的版本不一样。" and closes itself.

## 2. Who runs what

**The host** runs the whole game as in single player: states, AI, collisions, scores, saves. Each frame it also applies its own keyboard through the network input path (section 5), then sends an update when due (section 4).

**A client never simulates.** Its DXTimer is never enabled, and its state handlers return at once for mode 2 (0x4c7810, 0x4c81d0, 0x4c8aaa). It only reacts to host messages. When a frame arrives (type 3, 0x4cde5d), it:
1. replies with an ack (type 3, 4 bytes);
2. sends its keys (type 12), if it may control a tank;
3. draws one frame from the sprite list it last received, advancing animations by the frame's elapsed time from the host (0x4cd6b4, 0x4cd753);
4. asks for any text it doesn't have yet (type 11).

- The HUD, the title, the stage screens and the game itself are all sprites on the host, so a client sees exactly the host's screen.
- There's no prediction or smoothing. A client's frame rate is the host's update rate, and a key press takes a round trip plus the wait for the next update.
- The client's own settings do nothing ("杂项" and "性能" have no effect, except shadow opacity), and **a client can't pause**.

## 3. Messages

Byte 0 of every message is its type. The host builds them in its `TMsgServer` (form+0x320; HostSend 0x4cc9f8), and a client reads them with its `TMsgClient` (form+0x324).

| Type | Direction | Content | Sent |
|---|---|---|---|
| 1 | host → client | hello: version 1, 2, 2, 184 | on joining |
| 2 | host → clients | permission table: `[02][n]` then n × (DPID int32, 4 permission bytes); the first entry, DPID −1, is the default for newcomers | on joining, and when the host confirms its network page |
| 3 | host → client | frame end, with the elapsed ticks | each update, to acked clients only; and on joining |
| 3 | client → host | ack (4 bytes) | in reply to each frame |
| 4 | host → clients | the tile image set's name (loaded from `Map\`) | when the host loads one (0x4cb4c4); on joining |
| 5 | host → clients | the background: a value and an image name from `Map\` | when the host loads one (0x4cb390); on joining |
| 6 | host → client(s) | the whole map, 3602 bytes (three 40×30 grids) | at the stage intro and the demo; on joining |
| 7 | host → clients | changes: map cells, fire tiles and explosions, 3-byte records | each update |
| 8 | host → client | every sprite on screen, background then foreground | each update, to acked clients only |
| 9 | host → clients | the sounds played since the last update (a word each) | each update |
| 10 | host → clients | new text strings for text sprites (34-byte records) | each update; or to one client, answering type 11 (not fully verified) |
| 11 | client → host | a request for text it lacks | when needed |
| 12 | client → host | keys: `[0C][?][P1 bits][P2 bits]` | in reply to each frame, if the client may control a tank |
| 13 | host → clients | clear the map | at the title |
| 99 | either way | chat | F12 |

- **Sprites** are sent whole every update, with no deltas. Each is 6 bytes on the wire: X and Y in 15 bits each (biased +0x4000), an image index (5 bits), and a pattern or text index (11 bits). A sprite drawn translucent carries 4 more bytes (width, height, angle and alpha; 0x4cd149).
- **Text** is sent once: the host keeps a dictionary (2024 entries), and text sprites carry only the index.
- **Explosions** are rebuilt on the client with their damage already marked as applied (+0x6c4 = 1), so they only animate.
- **Map changes** are diffed against a cache on the host, so none are lost when an update is skipped. Sounds queued while no client has acked are dropped.
- **Key bits:** 0 up, 1 down, 2 left, 3 right, 4 fire 1, 5 fire 2 (packed at 0x4c7770). A client sends both its P1 and P2 key sets, zeroed for a tank it may not control. The readme's "half the keyboard is your partner's" means exactly this.

## 4. Updates and the network speed

- Every host frame adds its ticks (the game clock of enemy_spawn_original_spec.md §5: `min(lag × 5, 100) × speed / 75`) to a counter (form+0x334, 0x4c7a5a).
- **When the counter passes `200 div (n + 2)`**, n being the network speed, the host sends one update and zeroes the counter (0x4c7fa3, 0x4c807c). The update is types 7, 10, 8, 9, 3, in that order (0x4c7feb–0x4c802a).
- **Flow control:** each client that acks a frame goes on a list (form+0x330). The sprites (8) and the frame end (3) go only to clients on the list, which is then cleared. So a client gets at most one frame per round trip, and a slow one simply gets fewer.
  - Types 7, 9 and 10 go to every client.
  - If nobody has acked, nothing is sent and the queues are reset.
- **The network speed** is on the host's 性能 page: a slider from 0 to 8, labelled "网络速度：%2dFPS" as (n + 2) × 5, so 10–50 FPS (0x4bcc70).
  - It's stored as [Performance] NetworkSpeed, default 5 (35 FPS); values outside 0–8 are ignored (0x4c6b30).
  - It changes only how often updates go, not what's in them.
  - A send waits for a whole frame past the threshold, and the leftover is thrown away, so the real rate depends on the host's frame rate. For example, a 60 FPS host adds about 20 ticks a frame (a tick is 0.75 ms at 100 %). There, settings 4–8, the default included, all send every second frame, about 30 a second. Settings 0–3 send about 10, 15, 20 and 20 a second.
- **Translucent screen indicators** (使用半透明的屏幕指示, F7) add 4 bytes to every such sprite and alpha blending on every machine. That's why the readme says to turn them off on the host.
- The host's ShowFPS reads "%5.1fkbps FPS:%4d", from a running byte count (form+0x338, 0x340).
- There are **no pings, timeouts or input expiry**. A client's last keys stay in force until its next type 12. A dead peer is left to DirectPlay's keepalive.

## 5. Tanks and control

There are still only **two tanks**. Up to four machines share them, and the rest watch.

**Permissions:** each player has 4 bytes (TDXPlayPlayer.Data; if unset, the default at form+0x444, which starts as 00 01 01 01):
- byte 0: kicked. In the default record it means "newcomers refused".
- byte 1: accept this player's chat (a local preference, not synced).
- bytes 2 and 3: may control P1, P2.

**Applying keys** (`ApplyNetInput`, 0x4cd358): the host's own keyboard also goes through it every frame, as its local player. For each tank:
- If the sender may not control it, the keys are ignored.
- If the sender controls it, the keys are applied.
- If nobody controls it, the keys are applied and the join routine runs (0x4ce294). If that succeeds, the sender becomes its controller and the tank takes the sender's name (0x499590).
- If someone else controls it, the keys are ignored.

**The join routine** is the same one single player uses (the "coin"):
- Fire skips the demo or hiscore to the title, and speeds up the intro, results and game-over screens.
- A tank can only be taken on the title or during play, and only while credits remain (+0x1d0 > 0).
- **A tank with lives left is taken without a fire press** (0x4ce369). So when a controller leaves, the next allowed sender takes the tank at once, usually the host, whose keys run every frame.
- A tank with no lives needs its join cooldown up and fire. That costs a credit, plays sound 0x12 and gives 4 lives. It also zeroes a counter that is most likely the score. On the title it starts the game (state 4); during play the tank spawns at once.

**Control ends** when the tank's lives run out (0x4995e0), its player leaves, or the host takes the permission away. The readme's version: press the matching tank's fire to take it, e.g. with the host on tank 1, press tank 2's fire.

## 6. Joining, leaving and host controls

**Joining** (OnAddPlayer, 0x4cda6c):
- Anyone can join at any time, even mid-stage. Everyone sees "（系统信息）<name> 加入游戏。".
- The host sends the newcomer, directly: 1 and 2, then, unless newcomers are refused, 4, 5, 6 and 3. The newcomer acks the 3 and gets the next update.
- A refused newcomer gets only 1 and 2. Its own entry is the default with byte 0 set, so it kicks itself.

**Leaving** (OnDeletePlayer, 0x4cdc58):
- Everyone sees "<name> 离开游戏。".
- The tanks it controlled lose their controller but stay in play.
- If the host leaves, clients see "游戏主机已经退出，请按[ESC]退出游戏。". On a lost session (0x4cdbec) they see "跟游戏主机失去联系，请按[ESC]退出游戏。".
- A client never quits on its own; ESC asks "真的要退出游戏吗？".

**The host's 联网 page** (F9, TfmOption's `tsNetwork`; only shown in network play):
- A row for [新玩家] and one per player, each with a name button and the checkboxes 控制P1, 控制P2 and 信息.
- Row 1 is always the local machine. Its button is disabled, with the hint "你不会想踢走自己吧？！".
- **Press a name to kick** that player. Press [新玩家] to refuse newcomers. Untick 控制P1/P2 to take a tank away or forbid it. Untick them on [新玩家] to make later players watch only. 信息 mutes a player's chat.
- The changes apply on OK (0x4bce60): taken-away tanks are released, and a type 2 goes to everyone.
- **A kick is the client closing itself:** on seeing its own byte 0 it shows "游戏主机结束了您的游戏。" and closes (0x4ce16e). The host never drops the DirectPlay player.
- Clients see the same page, kept in sync, but can only change 信息.
- **While the page is open on the host, the game freezes for everyone** (form+0x350 skips the DXTimer). AutoPause (F8) only pauses the host, and has been off by default since v1.1.1 so clients don't freeze.

**Other network features:**
- F12 chat (0x4ce550), to everyone or one player.
- F11 hides the messages.
- The 信息 button shows "你的主机地址是：" and the local IP.

**Saves:**
- A host's save stores the mode, the provider, the session name and the player name (0x4cebec). Loading it re-hosts without the wizard (`Open2`, 0x479ecc; 0x4cff68).
- A client can't load a client save, and a client never autosaves (0x4cba28).

## The remake

The remake has no network play.

The original's model is about the simplest there is:
- the host runs the game;
- clients send 6 key bits per tank and draw the host's sprite list;
- messages are reliable and in order;
- one ack per frame is the only flow control.

Godot's high-level multiplayer (ENet) could carry the same model. The same limits would come with it: the host plays with no delay while clients see a round trip of lag, and joining across NAT still needs a direct IP or a relay.

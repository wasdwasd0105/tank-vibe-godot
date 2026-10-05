# Online Play — Design and Implementation

How the remake plays over a network. It keeps the original's model (network_original_spec.md): one player hosts and runs the game, up to three others join, and there are still two tanks. The machinery is modern: Godot's high-level multiplayer, snapshot interpolation and one port for everything, TCP or UDP as the host picks.

## 1. Framework and transport

- **Godot 4.7's high-level multiplayer:** `SceneMultiplayer` on the scene tree. Nothing outside Godot.
- **One port, TCP or UDP** (Sean, 2026-10-04). The host listens on a single port (default **24680**). Its type is the ONLINE tab's PORT TYPE: TCP (the default, as before) or UDP. Every client connection and every message goes over it: the handshake, the lobby, inputs, snapshots, events and map sets.
  - **TCP:** a `WebSocketMultiplayerPeer`. Nagle's algorithm is off on each connection.
  - **UDP:** an `ENetMultiplayerPeer` with two channels: RPCs on the first, the world's snapshots on the second, so a big snapshot never holds up a key press.
    - Everything stays reliable and in order. The snapshot deltas count on every snapshot arriving, so this changes nothing above the transport; ENet's own resending is quicker than TCP's, and there's no Nagle.
    - ENet takes up to 8 connections, so a newcomer turned away still hears why.
    - ENet doesn't say how much it has queued, so over UDP only the snapshots' acks hold back a slow client (section 5).
  - **A client finds out which by itself:** a join tries both at once (`Net._find_transport`).
    - A plain TCP connection probes the port while the UDP join itself goes ahead.
    - The UDP join connecting means a UDP host: the probe stops.
    - The probe connecting means a TCP host. The UDP try then gets 0.4 s more, in case something else answers on a UDP host's TCP port, before the join turns to TCP.
    - Neither within 8 s: "No game answered at that address." (A UDP join never fails by itself, so this is the wait at a closed port.)
  - Nothing else is needed: no discovery port and no port range (the original needed DirectPlay's 47624 plus 2300–2400).
  - Behind a router, only that one port needs forwarding on the host's side, as TCP or UDP to match PORT TYPE.
  - Clients type the host's address (with ":PORT" when the host's port isn't 24680). The ONLINE tab's YOUR ADDRESS and the lobby show the host's LAN address to share, as the original's 信息 button did.
- **The handshake** is `SceneMultiplayer`'s authentication. The client sends its protocol number (`Net.PROTOCOL`, now 5) and name.
  - The host turns it away, with a reason the client shows, when the protocol differs, the name is empty, the game is full (MAX PLAYERS, 1 to 3 besides the host), or new players aren't allowed.
  - **A game with a password** then challenges the newcomer with 32 random bytes. The newcomer answers with their HMAC-SHA256, keyed with the password it was given (`Net.password_proof`). The host compares that with its own in constant time.
    - So the password itself never crosses the network, and an answer overheard is no use against the next challenge.
    - No password given: "This game needs a password." A wrong one (case counts): "Wrong password."
    - Full and locked out are checked again once the answer comes.
  - A clashing name becomes "NAME 2".
- **Hardening:**
  - `server_relay` is off: clients only ever talk to the host.
  - Object decoding stays off, on the handshake and on snapshots.
  - Every client message is size- and range-checked, and only a peer that passed the handshake is heard.
- **Liveness:** each side says something at least once a second, if only a keepalive. A peer silent for 10 s is dropped. A host that ends the game, or a kick, says why before closing.
- **Latency:** a key press goes out at once: over TCP, Nagle's algorithm is off; ENet never holds packets back.

## 2. Roles

- **Host:** runs the game exactly as offline: AI, collisions, scores, saves. It also applies its remote players' inputs, and streams snapshots and events to the clients.
- **Client:** runs no game logic. It shows the host's game in the same scenes (game.tscn in *mirror mode*), so it looks identical. It sends its players' inputs, and handles only its own menus.
- **Offline play is unchanged.** Every network path is inactive unless a session is open.

## 3. Screens and flow

- **Title → ONLINE BATTLE** (Sean, 2026-10-01) is a list of saved connections, like bookmarks, laid out as LOAD GAME is. Each connection is:
  - a USERNAME to play as;
  - the host's ADDRESS ("IP", "IP:PORT", a name, or IPv6 as "[ADDRESS]:PORT");
  - the game's PASSWORD, if it has one.

  The list:
  - Each row shows the address, the name, PASSWORD SAVED when there is one, and when it last got in (or NOT JOINED YET). The most recently used connection comes first.
  - A click on a row (or fire on it) connects. Its MORE pops up CONNECT, EDIT and DELETE (which asks CONFIRM? first), as a save's MORE does.
  - The footer has CREATE and BACK.
  - The connections are kept in the settings file, `[online] connections`. Passwords are kept there as typed, as most games keep their server lists.

  **The connection window.** CREATE opens it (NEW CONNECTION: USERNAME, ADDRESS, PASSWORD, JOIN, CANCEL); EDIT opens the same window with SAVE.
  - It opens with the name last played under, ready to type the address.
  - Enter moves on to the next field, and from the last to JOIN; Tab and Shift+Tab move too; Esc stops typing, then closes it.
  - JOIN and SAVE check the fields first: a name, an address, a port from 1 to 65535. They say what's wrong in red under the fields.
  - JOIN keeps the connection at the top of the list (the same address under the same name is kept once) and joins, even if the join then fails, so it can be put right with EDIT.

  **Joining.** The hint line says how a join goes and why one failed. Esc stops a join under way. When a session ends under a client (the host ended it, a kick, a lost connection), the client comes back here and the hint says why.
- **Hosting** (Sean, 2026-10-02, after Counter-Strike 1.6's listen servers) is in a running game: pause → SETTINGS → the **ONLINE** tab, beside GAME and GENERAL. Start a game as ever (NEW GAME or LOAD GAME), then open it to others there. The tab has:
  - **ALLOW REMOTE PLAYERS**, ON or OFF (not kept: every game starts offline).
    - ON opens the game on the port, or lets newcomers in again.
    - OFF turns newcomers away; the players already in stay. With nobody connected it also closes the game to the network, and play goes on offline.
  - **PORT**, typed. It's kept, and fixed while the game is open.
  - **PORT TYPE**, TCP or UDP (section 1). It's kept, and fixed while the game is open.
  - **PASSWORD**, optional, typed and shown as dots. It's kept, and applies to newcomers at once.
  - **MAX PLAYERS**: 1 to 3 others besides the host's machine ("3 + YOU"), so 4 in all. It's kept, and applies to newcomers at once.
  - **YOUR ADDRESS**: the LAN address and port to give the others. Activating it copies it.
  - **CONNECTED PLAYERS**: who is connected, what each drives (or WATCHING), and their ping once timed ("84 ms", section 7).
  - A line under them says what the tab is doing, or what went wrong (a port in use, a bad port), in red.

  More about it:
  - The host goes by the name it last played under in ONLINE BATTLE (PLAYER if none).
  - Player 1 keeps their tank. Tank 2 is free for whoever presses fire first, the host's own P2 included (Sean, 2026-10-06, section 19): if player 2 is in the game (a two-player game, or a saved one), they sit out until then, keeping all they had. Joining a tank whose player never joined is joining mid-game, with fresh lives (credits are unlimited); one sitting out comes back with all it had.
  - Clients joining see the stage at once, and take a free tank with their fire.
  - A client's MENU has an ONLINE tab of its own instead: how the host's game shows on that machine (LAG COMPENSATION, SMOOTHING and its ping, section 7).
- **HOST**: once someone has joined, the host's pause menu has HOST under SETTINGS (section 8).
- A host's BACK in the lobby goes to the title.
- **The online lobby** is the join screen, networked:
  - The cards show who drives each tank.
  - The top shows the host's address (on the host) or "HOSTED BY" (on a client), and everyone connected.
  - Anyone takes a free tank with their own fire, or a click on its card. A new game's players join (credits are unlimited); a loaded game's players are already in.
  - Only the host starts: its fire again, or START.
- **In the game:**
  - Clients see the host's screen, including the stage intro, results and game over.
  - Anyone without a tank can take a free one with fire (credits are unlimited).
- **Game over** returns everyone to the lobby, still connected.
- **The host leaving** (MAIN MENU, the lobby's BACK, QUIT) ends the session for everyone.

## 4. Tanks and controls

- **Seats:** each tank (P1, P2) has at most one driver: a local player on some machine, or nobody (`PlayerInput.seats`).
- **Each machine has two local players**, its P1 controls and its P2 controls, as set on its own controls pages. A local player presses fire to take a free tank, then drives it with **their own controls**.
  - So someone alone at a client uses their P1 keys or pad, even for tank 2.
  - A local player's fire takes their own number's tank if it's free, else the other.
  - (The original made you press the tank's own fire key, e.g. P2's keys for tank 2. Sean chose own controls.)
- **Permissions** (the host's, as the original's 联网 page): per player, which tanks they may drive, and whether newcomers may join at all.
- **A driver who leaves** (or loses the right to drive it): their tank sits out, as with PLAYER 2 OFF. It keeps its HP, add-ons, lives and score, and anyone allowed can take it back with fire, at no cost.
  - A tank left without a driver doesn't start the lose countdown: the stage waits for one.
  - (In the original, the next allowed player's input grabbed it at once, usually the host's.)
  - PLAYER 2 ON / OFF is offline only: online, the seats do that job.
  - Online saves keep whoever had no driver as sitting out. Loading one offline puts player 1 back in play, since only player 2 can sit out offline.
- **Rumble** goes to the machine and local player driving that tank, with that player's own vibration setting.

## 5. Replication (host → clients)

**Snapshots.** The host sends one snapshot 30 times a second (every other physics frame), `var_to_bytes` of an Array (NetWorld has the layout). Each carries:
- its number (acknowledged back), the world it belongs to (each stage, or a restart, is a new world) and the host's real-time clock (game speed doesn't stretch it);
- **entities:** every tank, shell, bonus item, mine and burning tile. Each is an id, its type, and a state of ints and floats: position first, then what its look depends on (facing, add-ons, invincibility, flight, damage flash…).
  - New entities come whole, with their spawn data.
  - Changed ones come as a bit mask of changed values, 32-bit floats and zigzag varints.
  - Gone ones are listed as removed.
- **map changes:** each changed cell's bg code, fg code and standing brick quarters;
- **game state**, only what changed: stage, lives, scores, levels, weapons, HP, add-ons, chains, the enemies' count, holds and freezes, the lose countdown, pause, game speed, the base, and the stage screen showing (with its random draws) and its clock;
- **events:** sounds and music, and one-shot effects (hit sparks, tank explosions, spawn bursts, blasts, kill and pickup text). A player tank's shot sounds say whose tank fired, so the client driving it, which heard it as it fired, leaves it out (section 7).

Rumbles go straight to the peer they're for, outside the snapshots.

**Deltas.** Each client gets only what changed since the snapshot sent to it last. TCP keeps every snapshot in order, so nothing is ever resent. A new client, or a new world, starts with a full one: the whole map and every entity.
- The host's world sends only to clients whose connection is open (`Net.connected_client_ids`).
- A newcomer is in the session from the end of its handshake, a moment before its connection opens. A full world sent then would be lost, and every later snapshot only adds to it.
- (This bit joins into a running stage, once hosting moved into the game.)

**Flow control** is the original's ack gate, made gentler:
- Each client acknowledges the newest snapshot it has received, with its input messages.
- The host skips a client that is more than 15 snapshots behind on its acks, or (over TCP) whose connection has more than 48 KB still waiting.
- When it has caught up, that client gets one delta covering the gap. So a slow client gets fewer, bigger updates, never a growing backlog.

**The client's view** is snapshot interpolation:
- It buffers snapshots and draws the world 100 ms (three snapshots) behind its estimate of the host's clock.
- Positions, a mine flight's tumble and an item's size and fade glide between snapshots.
- Everything else (spawns, removals, state changes, sounds, effects) happens as that point in time is reached.
- More than 45 snapshots waiting means the client stalled: it catches up at once.
- How far behind is the client's SMOOTHING setting: AUTO by default, which goes by how late the snapshots have been coming (section 7).
- The client's own tanks and its own shells are the exception: they run ahead of that (section 7).

**Mirror mode.** On a client the game's own scenes run with their logic off (`Net.is_client()` guards):
- Tanks, shells, items, mines and fires are built from the same scenes and scripts, with no collision. They draw themselves from the replicated state (`net_setup`, `net_apply`), so the same code draws them on every machine.
- The stage overlay follows the host's screen and clock.
- The HUD reads the replicated game state.
- The map is built from the host's tile data, so an imported map plays even if the client doesn't have it. The client can still keep a copy of the map set (next part).
- A client's game plays only the host's sounds; its menus click as ever.

**The host's map set** (Sean, 2026-10-03, like Counter-Strike 1.6 keeping a server's maps):
- A map set is known by the SHA-256 of its .dat file (`LevelData.pool_hash`), whatever it's called. The host's session info carries its set's name, hash and size (the set in play: the game's MAP pick, else the one loaded). It goes out again whenever the host enters its lobby or a game, in case the set changed.
- A client whose maps have nothing of that hash is asked once a session, by a window over whatever screen it's on (`NetMapPrompt`). The window gives the name and size and offers DOWNLOAD or NOT NOW. Its players hold still while the window is open, and the keys don't reach the screen under it.
- DOWNLOAD asks the host for it (`_c_map_request`). The host sends it in 32 KB pieces, one a frame while that connection has less than 128 KB waiting, so the snapshots keep flowing (`_h_map_piece`). The window shows how far it has got.
- The whole file must match the hash it was announced with, and be a map file, before it's kept. It's saved with the imported maps, under the host's name (name_2 beside a different map of that name), so it's on the MAP setting for later games. The screen then says it's saved, or why not.
- NOT NOW: the game goes on all the same; it isn't asked again until the next session. Map files over 8 MB aren't offered.

## 6. Inputs (clients → host)

- A client samples both local players every physics frame. It sends a 36-byte message when anything changes, which a new snapshot's ack always does. The message holds:
  - the newest snapshot;
  - per player: the direction, both fire buttons held and a press counter per button;
  - per player: whether the client runs its own tanks (its LAG COMPENSATION on) and, while that player drives one there, where that tank is on the client, its facing, whether it moves, the last correction it has taken, and the client's physics frame it was there (0-255, wrapping; section 7). So a tank driving there sends one every frame.
- Press counters make a quick tap impossible to lose, even if its press and release land between two host frames.
- Once a second a client times a trip to the host and back (`_c_ping`, `_h_pong`) and tells the host its latest ping.
- While the client's own menu is open, its players are sent as idle.
- All game code that reads player keys goes through `PlayerInput`: PlayerTank, the rejoin check, the lobby and the stage screens' speed-up. It answers from the host's own keys or a remote player's latest message, depending on who drives that tank.

## 7. Timing and feel

- **What a client sees** of the host's world is about half a round trip plus its smoothing delay old. Its own tank and shots are the exception (lag compensation, below).
- **Smoothing** (Sean, 2026-10-05, from players' feedback): how far behind the host's clock a client shows the world, so a snapshot arriving late doesn't stop the picture.
  - AUTO, the default, goes by the snapshots themselves (`NetClientWorld.auto_delay`): their spacing (33 ms) plus how late nine in ten of the last 60 came, compared with the quickest, plus 10 ms, between 40 and 250 ms. About 45 ms on a steady line, more on a jittery one; one stall alone changes nothing. It starts at 100 ms until a second of snapshots has been measured.
  - Or a client picks 50, 75, 100, 150 or 200 ms on its MENU's ONLINE tab: less is quicker but jerkier when the connection stutters.
  - The delay moves to a new aim smoothly: up at 100 ms a second, down at 20, so the picture never jumps.
- **A client's ONLINE tab** (its MENU's SETTINGS) has LAG COMPENSATION (ON / OFF), SMOOTHING (AUTO, with what it comes to now, or a figure) and the ping, with a line on what the focused row does. Both are kept in the settings file, `[online] lag_compensation` and `smoothing`.
- **Lag compensation** (Sean, 2026-10-05): a client's own tank and its shots answer its keys at once, however far away the host is. Before it, a key press took a whole round trip plus 0.1 s to show, which players found unplayable above about 100 ms.
  - **The client drives its own tank** (`PlayerTank._predict`) with the same movement code as the host's: turns and their snap to the half-tile grid, ice, and walls, water and the base on its copy of the map. Enemies it sees stop it too. Its speed and a mine's slowing come from the host. Each input message carries where it is (section 6).
  - **The host's copy follows it** (`PlayerTank._follow_client`) at up to twice the tank's speed. It goes the way the client went: on to a turn's corner first, then round it, with a turn's grid snap at once. What stops any tank stops it there: walls, water, the base and enemies. So the host still decides what the tank runs into, what hits it and what it picks up, and its shots leave from where the copy is.
  - **Played back steadily** (Sean, 2026-10-05: in 1.1.3 the copy moved by fits and starts on the host, even on a LAN). The reports come one per client frame, but a network brings them unevenly: two in one host frame, then none, and TCP holds the rest back while it resends a lost one. Chasing the newest, the copy lurched, then stood. Now the host plays them back as the client's snapshots are shown on a client (section 5), one client frame per host frame:
    - Each report carries the client's frame (`PlayerInput.set_remote_report` queues them). How far ahead of the host's physics frames the quickest of the last 120 came (2 s) is the reports' clock; how much later than that each of the last 300 came (5 s) says how late they come.
    - The copy plays them that clock less a delay (`PlayerTank._play_reports`): how late 98 in 100 came plus a frame, 1 to 15 frames (up to 250 ms), 3 until 30 have come. Off that place (the delay changed, the clock moved), the playback gets there by running up to a tenth slower or faster, never by going back, so the picture doesn't jump.
    - Between two reports it shows the way between them (a turn's snap or a correction taken, not halfway); past the newest, a moving tank carries on its way up to 2 frames rather than stopping.
    - **Either machine's frames can slip against the other's for good** (Sean, 2026-10-06, section 18). A machine whose main loop stands still runs at most 8 physics frames for it afterwards; the rest never happen, and its frame count is behind from then on. On a Mac, a game's window going out of sight or coming back costs about half a second of them (measured here: 25 to 40 frames each time); a stage loading or a window going fullscreen can too. So the playback doesn't trust the two counts to keep step:
      - The clock goes by the latest reports only, and within half a second it follows when 30 in a row have all come later than it says (the client's frames fell behind): those weren't late.
      - Whatever the clocks say, what's played is never more than 18 frames behind the newest report, nor more than 2 past it.
      - After the host stood still, its copy makes up the way at its catching-up speed and is back in its place within a few seconds. After the client did, the copy goes on with it at once, and as evenly as before within about a second.
  - **A quick tap of fire** that comes and goes between two host frames, its press and release in one bunch, still fires: the host fires on a press as well as a hold (the press counters, section 6), and so does the client's own prediction.
  - **Corrections.** Held up for 0.3 s more than 24 px behind (by an enemy the client hadn't seen yet, say), the host sends a correction: a counter in the tank's state (`net_override`). The client's tank goes where the host has it, and drives on from there. Until a client's report has taken the correction, the host ignores it. Catching up after a stall (a pause, a hitch) is no correction.
  - **Spells.** While the host drives the tank itself (materializing, a mine's flight, an enemy's hold), the client shows the host's tank. Each one starts with a correction, so the client drives on from wherever it ends, with nothing to put right.
  - **Its own shots go off at once** (Sean, 2026-10-05, from players' feedback: firing still felt late once the tank moved at once). The client fires them as the host will when its keys arrive, with the host's weapons, levels, ammo and the shells it has in flight (`PlayerTank._predict_fire`): each shot is a ghost shell (`Bullet.net_ghost`) that flies at once from the barrel, and its sound plays at once.
    - The host still fires the real shell, which decides every hit. When it shows on the client, it takes over from the oldest ghost of that player's with its look and way, easing from where the ghost was over 0.15 s (`NetClientWorld._take_over_ghost`).
    - The host's sound for that shot carries the tank's number, and the client, having heard it, leaves it out (`SoundManager.play_predicted`).
    - A ghost hides where the host's shell would end (a wall, an enemy, its range); the host's word of the hit shows it go. A ghost no host shell takes over within the round trip, the smoothing and 0.3 s was a shot the host didn't fire, and goes. Mines are left to the host.
  - **Its own shells** are then drawn where they are by the client's clock: from where the host had one at the snapshot that brought it, on at its speed for the time since plus the round trip (`NetClientWorld._shell_now`). That's worked out from the shell's speed, which the host sends, rather than from the snapshots' timing, which the host's frames make uneven, so the shell flies on as smoothly as its ghost did. One that would be past a wall, an enemy or the end of its range by then is hidden until the host's word of its hit comes. AP shells drill on.
  - **LAG COMPENSATION OFF** (the client's choice) gives the picture from before: its tank and shots show where the host has them, its keys a round trip late. The host then drives that tank from the client's keys as they come (`PlayerTank._drive_for_client`); turned on again, the host corrects it first, since the keys moved it meanwhile.
  - **Everything else** stays where the host had it, the smoothing plus half a round trip ago: enemies, the other players' tanks, and every other shell. So an enemy shell can still hit a client's tank that seemed just clear of it, and an enemy can stop it a little short of where it looked free. Its tank goes back by that much when that happens.
  - **The trust this takes:** the host takes a client's word for where its tank drove, within what the host's own walls and enemies allow, at no more than twice the tank's speed. A cheating client could steer perfectly, but not drive faster or through walls.
  - **Ping:** clients time the round trip once a second, the first a second after joining, and go by the middle one of the latest five, so a stall (a stage loading) doesn't count. The host's CONNECTED PLAYERS list shows each one's.
- **Game speed:** clients run at the host's GAME SPEED, so their local animations keep pace with it.
- **Pause:** the host's pause menu pauses everyone, as the original's F9 did; clients see PAUSED BY THE HOST. A client's menu (MENU: resume, fullscreen, settings, LEAVE GAME, quit) pauses nothing.

## 8. Host controls

Opening the game, its port, password and most players, and who is connected are on the pause menu's SETTINGS → ONLINE tab (section 3). Once someone has joined, the pause menu also has a **HOST** page:
- a row per player, the host included, for what they may drive: P1 + P2, P1 ONLY, P2 ONLY or WATCH ONLY, with the tank they're driving now;
- a KICK row per client.

Changes apply at once. Taking a tank away from its driver frees it and it sits out. When the last player leaves, HOST goes away again.

## 9. Code

New:
- `scripts/autoload/net.gd` (autoload `Net`): the session, over a WebSocket (TCP) or ENet (UDP), and a joining client's choice between them.
  - host and join, the handshake, keepalives, peers, names and permissions;
  - the lobby's state, RPCs, raw snapshot packets, rumble routing, notices and why a session ended.
- `scripts/autoload/player_input.gd` (autoload `PlayerInput`): the input layer and the seats.
- `scripts/net/net_world.gd` (`NetWorld`): the snapshot layout, entity types, events, game-state keys and the update encoding.
- `scripts/net/net_host_world.gd` (`NetHostWorld`): host side, added to the game scene. It gathers everything and sends each client its delta, with flow control. Its static `record()` and `mark_tile()` are how the game reports events and map changes.
- `scripts/net/net_client_world.gd` (`NetClientWorld`): client side, added to the game scene. It decodes, buffers, interpolates, builds the mirrored nodes, applies the game state and plays the events.
- `scripts/net/net_toasts.gd` (`NetToasts`): "NAME joined / left the game." over any screen, in each machine's language.
- `scenes/online_screen.tscn`, `scripts/ui/online_screen.gd`: ONLINE BATTLE, the saved connections and the connection window.

Changed:
- **Mirrored entity scripts** (BaseTank, PlayerTank, EnemyTank, Bullet, Cookie, Mine, GroundFire): `net_type`, `net_spawn_args`, `net_state` on the host; `net_setup`, `net_apply` on a client; a client guard in front of their logic.
- **Lag compensation** (section 7): PlayerTank drives a client's own tank there (`set_net_predicted`, `_predict`), fires its shots there (`_predict_fire`, `_take_host_weapons`), and has the host's copy follow it (`_follow_client`, `net_override`) or, with the client's compensation off, its keys drive it (`_drive_for_client`); BaseTank's `_spawn_bullet` makes a client's shot a ghost (`Bullet.net_ghost`, `_fly_ghost`); NetClientWorld picks the client's own tanks, keeps the ghosts and hands them to the host's shells, draws its own shells ahead (`_take_own_tanks`, `add_ghost`, `_take_over_ghost`, `_lead_shell`, `_shell_now`) and sets the smoothing (`render_delay`, `auto_delay`); a shell's spawn data says whose it is and how it flies; SoundManager leaves out the host's sound of a shot the client heard already; PlayerInput keeps each client's reports; Net carries them, times the ping, and has `--net-lag-ms=N` for tests (a client's line made N ms longer each way); GameManager's ammo setter does nothing on a client (its numbers are the host's).
- **Effects** (HitEffect, SpawnBurst, KillText, PickupText, ExplosionBlast, the explosion scene): the host records them as events; a client's blast is only its picture.
- **LevelManager:** marks changed tiles; `net_map`, `net_cell`, `net_load_map`, `net_set_cell`; mirror mode.
- **StageOverlay:** `net_screen`, `net_show`, `net_set_time`; follow mode.
- **game.gd:** host mode (a NetHostWorld, seats, tanks without drivers sit out), opening and closing a running game to others (`hosting_started`, `session_ended`), and mirror mode.
- **Screens:** title (ONLINE BATTLE), join screen (the lobby), pause menu (SETTINGS' ONLINE tab, the HOST page, the client's MENU).
- **SoundManager:** sounds to clients; a client plays only the host's.
- **InputSettings:** `[online]` the host's `port`, `port_type`, `host_password` and `max_players`, a client's `lag_compensation` and `smoothing`, and the saved `connections`; `--test-profile=NAME` gives a test process its own settings file (and, through LevelData.user_map_dir, its own maps folder).
- **LevelData:** `pool_hash`, `bytes_hash`, `pool_with_hash`, `find_pool`, and `save_map_bytes` for a map set that came from a host.
- `scripts/net/net_map_prompt.gd` (`NetMapPrompt`): the question about the host's map set.
- **SaveManager:** player 1 never loads as sitting out.

## 10. Testing

`scenes/test/online_test.tscn` (with its client half, `online_client_test.tscn`, which it starts as a second headless process on a random port) covers the following over TCP. `online_udp_test.tscn` runs all of it again with the host on UDP, and the client finds out which by itself each time:
- **the parts:** the encoding, names, seat rules, remote presses, and a busy port refusing to host;
- **the handshake:** another version, no name, no password, a wrong password and a locked game are each turned away with the reason (an in-process fake client), and each challenge is fresh;
- **the flow:**
  - an offline game opened to others from its pause menu's ONLINE tab, with a password;
  - the client's ONLINE BATTLE screen: CREATE with a wrong password, turned away, EDIT to put it right, a click to join the running stage;
  - the client taking tank 2 with its own P1 fire, mid-stage; newcomers turned away while the host's game is locked, then full;
  - the game, the client driving tank 2, rumble reaching the client's pad, sounds and effects playing there;
- **the world:** a busy field (enemies, shells, an item, mines, a fire field, a blast) frozen and compared on the client, entity for entity, state for state, cell for cell, and the HUD's numbers;
- **then:**
  - the next stage, through the host's mission, results and intro screens;
  - a tank taken away and given back;
  - game over: the online lobby, each machine taking its tank again with its own P1 fire, and another game;
  - a kick, and the client told why, back on ONLINE BATTLE, its connection showing when it got in.

It prints the client's checks with its own and fails if either side does.

The client half starts with an empty maps folder of its own while the host plays a map set of its own. The client is asked about it, DOWNLOADs it (in pieces, checked), keeps it with its maps, and isn't asked again later.

`scenes/test/map_download_test.tscn` covers a map set's hash, keeping one that came from a host (names, refusals), when a client is asked (not for a map it has or nonsense, once), and the question by keys and mouse.

`scenes/test/online_screen_test.tscn` covers ONLINE BATTLE on its own:
- the address parser and the password's proof;
- the empty list, and the connection window typed in by keys (Enter, Tab, Esc; the mouse doesn't take the keys while typing);
- JOIN's checks, what it keeps and where, a join failing and saying why without leaving the screen, and Esc stopping one;
- a connection kept once, the order, MORE's options by keys, EDIT, DELETE after CONFIRM?, and a game that ended saying why once.

`online_screen_test.tscn` [L] covers a join finding out the transport: a TCP host, a UDP host, and a UDP host with something else on its TCP port.

`scenes/test/net_follow_test.tscn` covers lag compensation's parts in one process: the host's copy of a client's tank waiting for word, following at up to twice its speed and round a turn the way it went, a turn's snap, standing still; a wall or an enemy holding it up and the correction after 0.3 s, reports that haven't taken it ignored; a mine's flight and a hold each starting with a correction and none at their end; its shots and the state it sends; reports coming unevenly (two at once, then none) played back a frame's way every frame, a connection that stalls 80 ms and catches up (the playback learning to wait far enough behind), and a line that gets three frames quicker (no jump); either machine standing still, its frames behind the other's for good from then on (the host four times over: the copy never left behind; the client: followed at once, and as evenly as before two seconds on), and the two machines' frames running a twentieth apart either way; a tap between two frames firing; a client with lag compensation off driving it with its keys, and a correction when it turns it on; then the client's side: its own tank driven at once and reported in the input message, not while its menu has the keys, a stale report not sent; a correction putting it back; its own shells drawn ahead (hidden past a wall, an enemy or a flame's range; AP drilling on); its own shots fired at once as ghosts (the cooldown, the host's weapon and ammo, AP's limit in flight, no mines, none of the host's numbers spent), flying as the host's will, hiding at a wall, taken over by the host's shells where they are and eased to their own place, or going when no shell comes, and their sounds heard once; and AUTO smoothing's figure, a picked one, and the settings. And the ping in the host's list of players.

`pause_menu_test.tscn` [H] covers a client's ONLINE tab: GENERAL and ONLINE only, LAG COMPENSATION and SMOOTHING by keys and kept, what each does, and the ping as it's timed.

`scenes/test/online_lag_test.tscn` plays a session over a long line: it hosts, and starts itself again as a client with 75 ms added each way (`--net-lag-ms`). `online_lag_jitter_test.tscn` does it again with up to 40 ms more each way at random, in order as over TCP (`--net-jitter-ms`), the host at 120 frames a second and the client at 60. The client's tank answers its keys within 3 frames; the host's copy moves every frame as smoothly as the client drives five seconds on end (counted frame by frame: at most a few stalls, a turn's snap the only lurches) and ends where the client's tank is, with no corrections in open ground; AUTO smoothing comes down (aiming at about 45 ms); the client's shot shows within 3 frames out of its tank's barrel and is heard once, the host's shell takes over from it where it was (never both at once) and flies on as smoothly; both sides know the ping (about 160 ms), and the host's list shows it; a correction from the host puts the client's tank where the host has it, and the host follows it again from there; with LAG COMPENSATION off, the client's keys move its tank only once the host has, the host driving it from them, and on again the host corrects it first. Last, each machine really stands still in turn (0.7 s, the host four times) while the client drives up and down: the host's copy plays no more than 18 frames behind, goes as smoothly as before within a second or two, and ends where the client's tank is, never corrected. online_test's client also checks its own tank, standing still, is where the host has it.

`scenes/test/pause_menu_test.tscn` [H] covers the ONLINE tab and HOST, PORT TYPE too (an ENet server over UDP, a busy UDP port): the tabs by keys and LB / RB, typing the port (a bad one refused) and the password, MAX PLAYERS, opening the game (the seats it leaves, its NetHostWorld), the port fixed while open, HOST appearing once someone joins and its rows, OFF locking with someone there and closing with nobody, a port in use, and no ONLINE tab on a client.

`pause_menu_test.tscn` [H2] covers hosting a game with both players in: player 1 keeps tank 1, player 2 waits off the field with their lives, score and HP, and another machine's fire (a stand-in) takes tank 2 with all of it.

## 11. Sean's calls (2026-09-29)

- **Controls:** a joining player drives with their own controls (section 4), not the original's "press the tank's own fire key".
- **Extras:** the first version has the host's ONLINE page (section 8). Not included:
  - chat;
  - UPnP;
  - a network speed setting. Snapshots stay fixed at 30 a second.

## 12. Sean's calls (2026-10-01)

- **ONLINE BATTLE** replaces ONLINE on the title: a list of saved connections, like the saved games' list, with CREATE, EDIT, DELETE and CONNECT. CREATE's window takes a username, the remote address (ip:port), an optional password, and JOIN (section 3).
- **No host screen for now:** its design comes later.

## 19. Sean's report and call (2026-10-06)

- **"My remote player still can't move."** The other machine never had a tank. Sean had loaded a saved game with both players in and opened it from the pause menu, and hosting kept every player on the field on this machine's own controls: tank 2 stayed on the host's P2 keys, which nobody pressed, and the other machine's fire had nothing to take. A temporary log of what the host received showed it: the client's keys and fire arriving every second, both seats the host's.
- **Sean's call:** hosting keeps tank 1 on the host's machine; tank 2 goes to whoever presses fire first, the other machine or the host's own P2. Player 2, if in the game, sits out until then with all they had (section 3).

## 18. Sean's report (2026-10-05, on 1.1.3)

- **A joining player's tank moved by fits and starts on the host's screen, even on a LAN** (the host's tank looked fine on the client). The host's copy chased the newest report, so the network's unevenness showed as stop-and-go. It now plays the reports back steadily (section 7). Protocol 5.
- **Still not smooth** on his machines after a first fix (a playback a few frames behind, which shrank every two seconds and stopped at 133 ms). Here, two windowed processes with up to 100 ms of jitter showed that one still stopping and lurching now and then, mid-drive. Now the playback sizes its delay from how late the reports come, up to 250 ms, as the client's own view does, and carries a moving tank on past a late report; with the same jitter it goes on evenly. Testing that also turned up quick taps of fire lost on the host when a press and release came in one bunch: fixed.
- **"My remote can't move now"** (2026-10-06, on that second fix). Its cause was a hosting rule (section 19). Looking for it turned up a real fault in the second fix, though: it kept time by the two machines' physics frame counts, and a count that slips was taken for the network, so each time the host's window went out of sight or came back, the copy played another half second further behind, for good, and past two seconds behind it stopped altogether. Two real windows showed it here. The playback now goes by the latest reports only and never plays more than 18 frames behind the newest (section 7).

## 17. Sean's calls (2026-10-05, again)

- **From players' feedback on 1.1.2:** under 100 ms of ping, firing felt late on a client (the tank moved at once, its shots didn't), and the host's and a client's pictures differ. They asked for a way to set the lag compensation themselves. Section 7.
- My choices:
  - A client's own shots go off at once too, as ghosts the host's shells take over, with their sounds heard once.
  - The smoothing delay, a fixed 100 ms before, now follows the connection (AUTO, about 45 ms on a good line), which brings everything a client sees nearer the host's.
  - Players set it on their MENU's ONLINE tab: LAG COMPENSATION ON / OFF (off is the picture from before: exactly the host's, a round trip late) and SMOOTHING, AUTO or 50 to 200 ms. On and AUTO by default.
  - Protocol 4: a 1.1.2 player can't join a newer host, or the other way round.

## 16. Sean's calls (2026-10-05)

- **Lag compensation** (from players' reports: over about 100 ms of ping the game was unplayable). Section 7.
- My choices:
  - Only the client's own tank runs ahead, with the host following it and correcting it when held up. Its own shells are drawn to match. Enemies and everything else stay interpolated, as before.
  - The client is trusted with where its own tank drives, within the host's walls and enemies and twice the tank's speed. Fine among friends; a cheater could only steer well.
  - The host's list of players shows each one's ping.

## 15. Sean's calls (2026-10-04)

- **UDP support** (from players' feedback): the host's ONLINE tab has PORT TYPE, TCP or UDP. Clients detect which and connect with it.
- My choices:
  - TCP stays the default.
  - Over UDP everything stays reliable and in order, on ENet: the same game, a quicker transport. Unreliable snapshots, with deltas against the last snapshot acked, could come later if play over poor links needs them.

## 14. Sean's calls (2026-10-03)

- **Downloading the host's map set:** a client without it (checked by hash) is asked whether to download it, and it's saved with their maps, like Counter-Strike 1.6.
- My choices: the question comes over the host's screen, not before entering it, since the game itself doesn't need the file; NOT NOW holds for the session; downloaded sets go with the imported maps under the host's name.

## 13. Sean's calls (2026-10-02)

- **Hosting is in the pause menu, like Counter-Strike 1.6:** SETTINGS → an ONLINE tab with: allow remote players to join, the game port, the password (optional), max players 1 to 3 (4 in all), and the connected players (section 3).
- **HOST on the pause menu once anyone has joined** (section 8).
- My additions, flagged to him: YOUR ADDRESS on the tab (to give to the others, and copy); the host's name comes from ONLINE BATTLE; OFF with players connected only locks the game; the old NEW PLAYERS row became ALLOW REMOTE PLAYERS.

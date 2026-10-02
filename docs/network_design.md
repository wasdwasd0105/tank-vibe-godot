# Online Play — Design and Implementation

How the remake plays over a network. It keeps the original's model (network_original_spec.md): one player hosts and runs the game, up to three others join, and there are still two tanks. The machinery is modern: Godot's high-level multiplayer, snapshot interpolation and one TCP port for everything.

## 1. Framework and transport

- **Godot 4.7's high-level multiplayer:** `SceneMultiplayer` on the scene tree, with `WebSocketMultiplayerPeer` as the transport. Nothing outside Godot.
- **One TCP port.** The host listens on a single port (default **24680**, set on the pause menu's ONLINE tab). Every client connection and every message goes over it: the handshake, the lobby, inputs, snapshots and events.
  - Nothing else is needed: no UDP, no discovery port and no port range (the original needed DirectPlay's 47624 plus 2300–2400).
  - Behind a router, only that one TCP port needs forwarding on the host's side.
  - Clients type the host's address (with ":PORT" when the host's port isn't 24680). The ONLINE tab's YOUR ADDRESS and the lobby show the host's LAN address to share, as the original's 信息 button did.
- **The handshake** is `SceneMultiplayer`'s authentication. The client sends its protocol number (`Net.PROTOCOL`, now 2) and name.
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
- **Latency:** Nagle's algorithm is off on every connection, so a key press goes out at once.

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
  - **PASSWORD**, optional, typed and shown as dots. It's kept, and applies to newcomers at once.
  - **MAX PLAYERS**: 1 to 3 others besides the host's machine ("3 + YOU"), so 4 in all. It's kept, and applies to newcomers at once.
  - **YOUR ADDRESS**: the LAN address and port to give the others. Activating it copies it.
  - **CONNECTED PLAYERS**: who is connected, and what each drives (or WATCHING).
  - A line under them says what the tab is doing, or what went wrong (a port in use, a bad port), in red.

  More about it:
  - The host goes by the name it last played under in ONLINE BATTLE (PLAYER if none).
  - The players on the field keep their tanks. A tank nobody plays (player 2 never joined, or sitting out) is free for whoever presses fire first, the host's own P2 included. Joining it is joining mid-game, with fresh lives (credits are unlimited); one sitting out comes back with all it had.
  - Clients joining see the stage at once, and take a free tank with their fire.
  - A client's MENU has no ONLINE tab.
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
- **events:** sounds and music, and one-shot effects (hit sparks, tank explosions, spawn bursts, blasts, kill and pickup text).

Rumbles go straight to the peer they're for, outside the snapshots.

**Deltas.** Each client gets only what changed since the snapshot sent to it last. TCP keeps every snapshot in order, so nothing is ever resent. A new client, or a new world, starts with a full one: the whole map and every entity.
- The host's world sends only to clients whose connection is open (`Net.connected_client_ids`).
- A newcomer is in the session from the end of its handshake, a moment before its connection opens. A full world sent then would be lost, and every later snapshot only adds to it.
- (This bit joins into a running stage, once hosting moved into the game.)

**Flow control** is the original's ack gate, made gentler:
- Each client acknowledges the newest snapshot it has received, with its input messages.
- The host skips a client that is more than 15 snapshots behind on its acks, or whose connection has more than 48 KB still waiting.
- When it has caught up, that client gets one delta covering the gap. So a slow client gets fewer, bigger updates, never a growing backlog.

**The client's view** is snapshot interpolation:
- It buffers snapshots and draws the world 100 ms (three snapshots) behind its estimate of the host's clock.
- Positions, a mine flight's tumble and an item's size and fade glide between snapshots.
- Everything else (spawns, removals, state changes, sounds, effects) happens as that point in time is reached.
- More than 45 snapshots waiting means the client stalled: it catches up at once.

**Mirror mode.** On a client the game's own scenes run with their logic off (`Net.is_client()` guards):
- Tanks, shells, items, mines and fires are built from the same scenes and scripts, with no collision. They draw themselves from the replicated state (`net_setup`, `net_apply`), so the same code draws them on every machine.
- The stage overlay follows the host's screen and clock.
- The HUD reads the replicated game state.
- The map is built from the host's tile data, so an imported map plays even if the client doesn't have it.
- A client's game plays only the host's sounds; its menus click as ever.

## 6. Inputs (clients → host)

- A client samples both local players every physics frame. It sends a 12-byte message when anything changes, which a new snapshot's ack always does. The message holds the newest snapshot, then per player: the direction, both fire buttons held and a press counter per button.
- Press counters make a quick tap impossible to lose, even if its press and release land between two host frames.
- While the client's own menu is open, its players are sent as idle.
- All game code that reads player keys goes through `PlayerInput`: PlayerTank, the rejoin check, the lobby and the stage screens' speed-up. It answers from the host's own keys or a remote player's latest message, depending on who drives that tank.

## 7. Timing and feel

- A client's key press takes about: half a round trip to the host, plus up to one frame there, plus half a round trip back, plus the 100 ms interpolation delay.
  - On a LAN that's about 0.1 s.
  - Over the internet it's about 0.1 s plus the round trip.
- There's no client-side prediction. The original had none either, and the tanks' grid moves and collisions would make it error-prone. It can come later if play over long distances needs it.
- **Game speed:** clients run at the host's GAME SPEED, so their local animations keep pace with it.
- **Pause:** the host's pause menu pauses everyone, as the original's F9 did; clients see PAUSED BY THE HOST. A client's menu (MENU: resume, fullscreen, settings, LEAVE GAME, quit) pauses nothing.

## 8. Host controls

Opening the game, its port, password and most players, and who is connected are on the pause menu's SETTINGS → ONLINE tab (section 3). Once someone has joined, the pause menu also has a **HOST** page:
- a row per player, the host included, for what they may drive: P1 + P2, P1 ONLY, P2 ONLY or WATCH ONLY, with the tank they're driving now;
- a KICK row per client.

Changes apply at once. Taking a tank away from its driver frees it and it sits out. When the last player leaves, HOST goes away again.

## 9. Code

New:
- `scripts/autoload/net.gd` (autoload `Net`): the session.
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
- **Effects** (HitEffect, SpawnBurst, KillText, PickupText, ExplosionBlast, the explosion scene): the host records them as events; a client's blast is only its picture.
- **LevelManager:** marks changed tiles; `net_map`, `net_cell`, `net_load_map`, `net_set_cell`; mirror mode.
- **StageOverlay:** `net_screen`, `net_show`, `net_set_time`; follow mode.
- **game.gd:** host mode (a NetHostWorld, seats, tanks without drivers sit out), opening and closing a running game to others (`hosting_started`, `session_ended`), and mirror mode.
- **Screens:** title (ONLINE BATTLE), join screen (the lobby), pause menu (SETTINGS' ONLINE tab, the HOST page, the client's MENU).
- **SoundManager:** sounds to clients; a client plays only the host's.
- **InputSettings:** `[online]` the host's `port`, `host_password` and `max_players`, and the saved `connections`; `--test-profile=NAME` gives a test process its own settings file.
- **SaveManager:** player 1 never loads as sitting out.

## 10. Testing

`scenes/test/online_test.tscn` (with its client half, `online_client_test.tscn`, which it starts as a second headless process on a random port) covers:
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

`scenes/test/online_screen_test.tscn` covers ONLINE BATTLE on its own:
- the address parser and the password's proof;
- the empty list, and the connection window typed in by keys (Enter, Tab, Esc; the mouse doesn't take the keys while typing);
- JOIN's checks, what it keeps and where, a join failing and saying why without leaving the screen, and Esc stopping one;
- a connection kept once, the order, MORE's options by keys, EDIT, DELETE after CONFIRM?, and a game that ended saying why once.

`scenes/test/pause_menu_test.tscn` [H] covers the ONLINE tab and HOST: the tabs by keys and LB / RB, typing the port (a bad one refused) and the password, MAX PLAYERS, opening the game (the seats it leaves, its NetHostWorld), the port fixed while open, HOST appearing once someone joins and its rows, OFF locking with someone there and closing with nobody, a port in use, and no ONLINE tab on a client.

## 11. Sean's calls (2026-09-29)

- **Controls:** a joining player drives with their own controls (section 4), not the original's "press the tank's own fire key".
- **Extras:** the first version has the host's ONLINE page (section 8). Not included:
  - chat;
  - UPnP;
  - a network speed setting. Snapshots stay fixed at 30 a second.

## 12. Sean's calls (2026-10-01)

- **ONLINE BATTLE** replaces ONLINE on the title: a list of saved connections, like the saved games' list, with CREATE, EDIT, DELETE and CONNECT. CREATE's window takes a username, the remote address (ip:port), an optional password, and JOIN (section 3).
- **No host screen for now:** its design comes later.

## 13. Sean's calls (2026-10-02)

- **Hosting is in the pause menu, like Counter-Strike 1.6:** SETTINGS → an ONLINE tab with: allow remote players to join, the game port, the password (optional), max players 1 to 3 (4 in all), and the connected players (section 3).
- **HOST on the pause menu once anyone has joined** (section 8).
- My additions, flagged to him: YOUR ADDRESS on the tab (to give to the others, and copy); the host's name comes from ONLINE BATTLE; OFF with players connected only locks the game; the old NEW PLAYERS row became ALLOW REMOTE PLAYERS.

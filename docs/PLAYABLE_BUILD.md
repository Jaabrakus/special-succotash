# SOCOM-141 playable build

The packaged game starts at `game_launcher.tscn`.

- **QUICK MATCH 2V2** instantly hosts a Gunfight room (shared-loadout
  elimination rounds, first to 6).
- **CREATE PRIVATE ROOM** opens the dial surface: MODE (Demolition or
  Gunfight) and TEAM SIZE (2v2 through 8v8) next to the map selector. The
  room admits both sides' worth of players, host included, and rejects
  further joiners.
- **HOST TOURNAMENT** opens THE SQUARE: up to 16 two-player squads
  register, the server seeds the bracket, and pods play as Gunfight
  matches until one squad holds the TENET. (A full 32-player Square needs
  the transport soak; smaller brackets work today.)
- **JOIN INVITE** connects to the address entered beside it on UDP port
  `14141`.
- **TRAINING RANGE** opens the canonical `main.tscn` test range; press `P`
  anywhere for the free-issue armory buy menu.
- **MAP EDITOR / STUDIO WORKBENCH** open the shared-profile authoring
  tools.

Studio and Gunsmith save project profiles under `res://config`. Training and
multiplayer read those same files. Package the game after a profile change so
remote players receive the same content.

## Local validation (two Godot instances)

1. Open the game twice — e.g. run it from the editor in one window and from
   a terminal in the other:
   `Godot --path . game_launcher.tscn`
2. In the first window: **CREATE PRIVATE ROOM** (pick MODE and TEAM SIZE,
   then create). Or **QUICK MATCH 2V2** for the default Gunfight room.
3. In the second window: type `127.0.0.1` in the invite field and press
   **JOIN INVITE**.
4. Verify movement, stance, shots, damage, elimination, respawn (Demolition)
   or round rotation (Gunfight), and the team words on the round strip
   (SATOR vs ROTAS on a default-axis map).

Headless equivalent of the same wire path:

```sh
Godot --headless --path . multiplayer_slice.tscn -- --mp-host --mp-port=14199
Godot --headless --path . multiplayer_slice.tscn -- --mp-join=127.0.0.1 --mp-port=14199
```

## Internet validation

Forward UDP port `14141` to the host computer, or use a private test network.
Steam lobby and relay support is a later transport layer. It requires a valid
Steamworks App ID and the selected Godot Steam integration. Do not put Steam
credentials in this repository.

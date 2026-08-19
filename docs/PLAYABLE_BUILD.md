# SOCOM-141 playable build

The packaged game starts at `game_launcher.tscn`.

- **Training Playground** opens the canonical `main.tscn` test range.
- **Host 8v8 Match** starts the server-authoritative 16-player ENet session.
- **Join Match** connects to the host address on UDP port `14141`.
- **Open Creator Studio** opens the shared-profile authoring tools.

Studio and Gunsmith save project profiles under `res://config`. Training and
multiplayer read those same files. Package the game after a profile change so
remote players receive the same content.

## Local validation

1. Open the game twice.
2. Select **Host 8v8 Match** in the first window.
3. Enter `127.0.0.1` and select **Join Match** in the second window.
4. Verify movement, stance, shots, damage, elimination, and respawn.

## Internet validation

Forward UDP port `14141` to the host computer, or use a private test network.
Steam lobby and relay support is a later transport layer. It requires a valid
Steamworks App ID and the selected Godot Steam integration. Do not put Steam
credentials in this repository.

# 141 restricted Web release

This package is the public browser boundary. It excludes creator labs,
regression tools, editable source art, reference media, design boards, and
development documentation. Scripts are exported as compiled bytecode.

## Build

1. Install the Godot 4.7.1 Web export templates.
2. Run `tools/export_restricted_web.sh`.
3. Upload the contents of `builds/web/` as one website or itch.io HTML project.
4. Confirm that `robots.txt`, `ai.txt`, the policies, `BUILD_ID.txt`, and
   `SHA256SUMS.txt` are available at the deployed origin.
5. Test in a clean browser profile before sharing the URL.

The preset is single-threaded for broad browser-host compatibility. Recording
is allowed. The launcher displays an ownership watermark without identifying a
player.

## Multiplayer boundary

The current multiplayer implementation uses ENet. Browsers cannot use ENet and
cannot directly host the existing authoritative server. Keep browser Host and
Join disabled until a native authoritative WebSocket service is deployed over
`wss://`.

For immediate public access, publish the restricted Training Playground in the
browser and distribute the native desktop build for multiplayer host/join.

Do not place private server code, credentials, lobby secrets, or signing keys in
the Web package.

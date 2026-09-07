# Browser/runtime parity repair

- Player intent: browser multiplayer must show the canonical character, animations and weapon identities, and load the server's actual map.
- Acceptance: native and packaged checks agree on saved actor settings and all public weapon names/models; the browser joins a local authority without dropping the map packet.
- Owners: existing presentation/weapon contracts own identity and appearance; `SocomTransportFactory` alone configures transport capacity. No new movement, aim or damage writer.
- Protected: server shot/damage authority, movement collision, RPC signatures, remote team identity, weapon balance, other ongoing animation work, existing public ZIP and running web build.
- Focused proof: network operator animation, canonical tuning and weapon-name regressions; an actual WebSocket map round-trip; exported package audit and browser join.

## New evidence: admission payload exceeds default WebSocket buffer

The browser join emitted `ERR_OUT_OF_MEMORY` at `receive_server_map.rpc_id` in `socom_multiplayer_admission.gd`. The current Relic Depot document alone is 75,608 JSON bytes before runtime normalization and RPC encoding; the transport factory used the engine's 65,535-byte buffers. The map could be dropped while lobby and actor spawn messages continued, producing mismatched client/server worlds.

MERGE a bounded shared transport-capacity profile into the factory before creating either endpoint. Validate it with the actual normalized deployed map, not a tiny echo. This changes capacity, not authority or RPC protocol. Keep packet count bounded and do not use unlimited buffers. The server also needs this patch deployed; a client ZIP alone cannot fix its sending buffer.

## Export dependency evidence

Dynamic JSON references do not establish every export dependency. Explicitly export the assigned M4/AK scenes and the AK's imported material textures. Packaged weapon tests must load each selected model without fallback.

## New evidence: lobby input capture on camera creation

The browser rendered its lobby but menu clicks fired the weapon. `SocomCamera._ready` captures the mouse; the first warm-up lobby snapshot disabled movement without restoring a visible mouse. The local firing path did not check `local_input_enabled` either. The existing warm-up coordinator must release capture while the player is in its lobby, and the existing shot-submission owner must honor the same input-disable flag. Preserve camera aim, server acceptance, live input and round rules. Prove both spawn-before-snapshot behavior and blocked menu firing in the rendered network animation regression, then enter practice from the browser without pressing Escape first.

The browser trace proved a further asynchronous race: the first post-join click arrived in captured mode at the previous pointer position, despite the lobby snapshot having released capture. After Escape, the identical click hit the expected button. MERGE an explicit `capture_mouse_on_ready` startup policy into the existing camera (default true for canonical solo play). The multiplayer session sets it false before adding its camera and only captures for active play. This avoids issuing a browser pointer-lock request behind the lobby rather than fighting its later completion. Protected camera aim/reticle transforms and profile values do not change. Focused proof asserts that network camera creation does not request capture, plus browser entry without an Escape workaround.

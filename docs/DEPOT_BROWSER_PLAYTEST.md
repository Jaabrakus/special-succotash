# Depot browser playtest pass

Intent: default to the existing Relic Depot (user called it Recon Depot), reduce
packet-arrival character jolts, and restore browser gunshot audio.
Acceptance: depot is bundled in browser and server; small snapshots preserve
predicted velocity/yaw and apply collision-aware corrections in CharacterBody
physics; large errors still snap; browser audio output is measurably nonzero.
Owners: saved map profile; existing SocomNetworkOperator; existing audio pools.
Protected: damage authority, weapon timings, camera aim, character/animation assets.
Proof: local_snapshot_smoothing_regression, relic_depot_regression, feature
contracts, actual package audit and browser shot/audio probe.

Server deployment is manual: changing the browser ZIP alone cannot change the
server-sent map. Restarting the server disconnects any current players.
The smoothing change is not full input-history reconciliation and is not proof
of fixed 32-player performance. CPU/frame-rate and Safari remain separate checks.

Audio investigation: sample-mode browser context was running and six sources
started, but analyser output was zero during the shot probe. Test stream playback
on the existing acoustic and Effects pools; do not bypass the user's volume/mute.
Godot documents sample playback limitations and the stream override:
https://docs.godotengine.org/en/4.4/tutorials/export/exporting_for_web.html

Verified 2026-09-06: all 71 integration contracts pass; depot resource regression,
acoustic routing regression, and small/large snapshot correction regression pass.
The latter also steps physics and checks partial correction and remaining-error
decay. Browser connects to the live dedicated endpoint and receives snapshots.
Temporary mixer diagnostics showed four requested/four played gunshots and a
Master peak of -15.09 dB. Diagnostics were removed from the final export.
Final clean-build Chrome probe: after disabling Playwright's default
`--mute-audio` flag, the browser destination analyser measured peak amplitude
0.0425872802734375 after firing, with AudioContext running. The earlier zero
readings were not reliable evidence of silence because the test browser was
muted. Safari/itch playback remains unverified; this does not establish that
sample playback was the sole cause of the user's original silence.

Code evidence:

- `config/network/browser_multiarena_deployment.json:15`:
  `"server_map_document": "res://config/maps/relic_depot.json"`
- `scripts/audio/acoustic_propagation_engine.gd:52`:
  `player.playback_type = AudioServer.PLAYBACK_TYPE_STREAM` (web only).
- `scripts/network/socom_network_operator.gd:52`:
  `var correction := pending_position_correction * (1.0 - exp(-12.0 * delta))`
  followed by `move_and_collide(correction)` in the CharacterBody physics step.

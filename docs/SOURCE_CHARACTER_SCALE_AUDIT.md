# Selected character and source-world scale audit

## Translation card — 2026-09-13

- Intent: distinguish selected-character size from camera framing before any
  user-authorized model resizing is implemented.
- Acceptance: measure selected main-game model/skeleton transforms, current
  standing/crouch/prone skinned bounds, capsule and camera marker points; compare
  homologous rest landmarks with preserved decoded source values.
- Owner: read-only `tools/source_character_scale_audit.gd` observer/report only.
- Protected: all saved models, skins, animation profiles, capsule/movement,
  camera configuration and runtime scripts. Test-only posture changes exercise
  the existing owner; they do not persist or override a saved implementation.
- Proof: fresh headless `main.tscn`, CPU skinning of selected mesh/binds,
  source metadata/hash, explicit transform scales and source-world unit factor.

System delta: KEEP current assets until dimensions are measured; MERGE numerical
evidence into camera work. Correctness and integration coverage improve without
new runtime writers or runtime cost. A measurement is not rendered proof or
permission to infer guessed human dimensions.

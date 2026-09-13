# Braced hang and warehouse awning follow-up

## Translation card: braced presentation

- Player intent: knees tucked toward the wall while hanging, using the existing
  AGLS braced animation rather than the straight-legged FreeHang variant.
- Acceptance: real jump enters the tucked pose on the current character; both
  wrists remain on the ledge, knees/feet stay outside the wall, matching pull-up
  plays once and returns the rifle to the hands. Render early/middle/late views.
- Owner: existing operator animation driver and traversal presentation modifier,
  with source selection and calibrated offsets in shared saved profiles.
- Must not change: CharacterBody movement/collision, reach, jump velocity,
  camera/aim, server damage, reload duration, or original animation assets.
- Proof: actual-main traversal hand-contact regression, source-pose knee checks,
  mantle/input regressions, and feature contract gate.

## Translation card: awning diagnosis and bounded correction

- Intent: hang on the shown warehouse awning when physically reachable and safe.
- Acceptance: actual map approach records the rejecting condition; a reachable
  approach succeeds while unreachable, ceiling-blocked and unsupported cases reject.
- Owner: existing traversal eligibility motor; map collision owner only if a
  measured visual/collision mismatch is demonstrated and separately documented.
- Must not change: camera, combat, jump physics, global reach or collision bypasses.
- Proof: warehouse awning main-scene regression with ground and raised approaches.

## System delta

Decision MERGE: user clarifies braced-wall pose, so use the existing braced source
and matching pull-up with recalibrated contact, not a new controller. Scores 0–5
current→candidate: correctness2→4 pending runtime proof, ownership5→5,
runtime parity5→5, editor usability4→4, performance4→4, regression4→4.
Evidence: `config/operator_animation_map.json`,
`scripts/player/operator_traversal_hand_modifier.gd`,
`docs/AGLS_TRAVERSAL_CLIP_REVIEW.md`,
`tools/traversal_hand_contact_regression.gd`.

The previous FreeHang result passed its contact test but did not meet the newly
clarified tucked-knee pose. Retain original assets and change only saved selection
and presentation calibration after source review.

## Translation card: support-aware hang presentation

- Intent: an edge without standing room can still support a safe hang; choose
  wall-braced legs only when collision evidence supplies a wall below the grip.
- Acceptance: motor supplies `hang_style`; the existing presentation owner maps
  free hangs/pull-ups to their own FreeHang source/contact profile. Braced and
  free sources must never share displacement curves accidentally. Camera/body
  ownership stays unchanged, and the weapon remains stowed throughout.
- Owner: operator animation driver/modifier; motor alone classifies the surface.
- Protected: reach, capsule dimensions, shot/damage, jump and reload timing.
- Proof: focused main contact test, hang-only eligibility test, actual awning
  renders, invalid-source/profile regression and feature gate.
- Delta: MERGE support-aware selection (correctness2→4, ownership5→5,
  runtime parity5→5, editor4→4, performance4→4, regression4→4). Forcing the
  braced source on an unsupported awning clipped the torso in the rendered
  midpoint, so a blanket source replacement is not accepted as universal.

## Translation card: supported narrow-top runtime handoff

- Intent: finish a safe climb onto a narrow supported top in an arms-out AGLS
  idle/shuffle instead of immediately running. This is not thin-rail balancing.
- Acceptance: unchanged full five-point standing support and capsule clearance;
  detect a narrow strip on both cross-ledge sides, cap A/D tangent travel at
  saved speed, stop at unsafe ends, leave on broad support or a deliberate jump.
  Loop the shuffle by actual collision-body travel; hold the idle pose-bank frame.
- Owner: CharacterBody movement branch consumes existing traversal runtime plus
  query-only narrow motor. Existing operator driver owns authored presentation.
- Protected: camera/aim, damage authority, jump impulse, unrelated locomotion,
  current character, original animation assets and existing climb safety rules.
- Proof: motor regression plus physical jump/hang/pull-up/narrow A/D movement
  through main.tscn, rendered idle/movement, endpoint stop and jump exit.
- Delta MERGE: existing narrow mode is vocabulary only; add its saved motor and
  canonical consumers (correctness1→4, ownership5→5, runtime1→5, editor2→4,
  performance5→4, regression1→4), pending the stated proof. Dedicated narrow
  Hang_To_Stand_01 replacement remains unapproved until source/contact calibrated.

## Translation card: player's saved warehouse collision

- New evidence: checked-in current_map.json has detailed_mesh for relic_014;
  both user://maps/active_map.json and user://maps/relic_depot.json still say box.
  load_active() prioritizes the user's saved document over the checked-in map.
- Intent/acceptance: preserve all saved layout and other properties, replace
  ONLY relic_014's collision_mode with detailed_mesh in those two copies, then
  test the actual saved map. Preserve byte-for-byte backups before editing.
- Owner: saved map document consumed by the existing imported-asset collider.
- Protected: all other objects/settings, movement reach and runtime ownership.
- Delta MERGE: correctness1→4, ownership5→5, canonical parity2→5, usability4→4,
  performance5→4, regression3→4. Do not force detailed collision on every mesh.
- Proof: structural diff must show only these two collision_mode fields;
  actual-user-map physical awning approach test, no running-instance reload.

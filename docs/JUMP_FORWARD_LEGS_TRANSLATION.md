# Jump-forward legs only

## Translation card

- Player intent: Use the available forward-jump leg animation during a normal jump, keeping the equipped weapon's upper-body pose.
- Acceptance rule: Canonical jump input uses `jump_forward_action` only on thigh-to-toe tracks, with one continuous playhead through takeoff and fall. Landing releases the overlay. Missing/disabled source preserves the old route.
- System owner: `SocomOperatorLocomotionBlendTree`, the existing animation presentation graph.
- Must not change: Hips/root motion, spine/head/arms, weapon/reload/fire ownership, jump controls and `CharacterBody3D` physics, camera/reticle, networking, other movement states.
- Proof: `tools/jump_forward_legs_regression.gd`, `tools/jump_forward_legs_visual_probe.gd`, feature contract gate, canonical boot, and rendered jump inspection.

## Saved contract and integration

The existing shared `config/operator_animation_map.json` selects the already imported Shooter Pack `jump forward.fbx` through `jump_lower_body`. The animation profile loads that section; the existing graph adds a filtered source before its reload/fire layers. A `TimeSeek` resets it only at airborne entry. Takeoff and fall requests share the same playhead. Only eight leg/toe chains are included; pelvis translation and upper-body tracks remain excluded. The existing Animation Workshop preserves the section when saving clip assignments.

## System-delta review

Decision: MERGE. Retain the physics-owned jump stages and existing upper-body graph; add one bounded, saved lower-body presentation route.

| Axis | Current | Candidate | Evidence |
| --- | --- | --- | --- |
| Correctness | 2 | 4 | Existing `jump_up`/`jump_loop` differ from the requested imported forward-jump source. The new filtered layer selects that source. |
| Ownership clarity | 5 | 5 | Existing animation graph only; no new physics or bone-update owner. |
| Runtime parity | 5 | 5 | Shared animation map is loaded by canonical `main.tscn`. |
| Editor usability | 3 | 3 | Existing Animation Workshop assignments and readable shared JSON remain the saved source. |
| Performance | 5 | 4 | One additional animation input runs only during its active blend; no skeleton search per frame. |
| Regression coverage | 3 | 4 | Focused filter, single-entry seek, actual jump, disabled/missing fallback and protected upper-body checks. |

Sources: `scripts/player/operator_locomotion_blend_tree.gd`, `scripts/player/operator_animation_profile.gd`, `scripts/labs/animation_workshop_repository.gd`, `tools/jump_forward_legs_regression.gd`.

Godot API reference: AnimationNodeBlend2 filter and AnimationNodeTimeSeek seek_request; installed 4.7.1 must pass runtime verification. No unverified API-specific property is used.

## Verification, September 6

- `jump_forward_legs_regression.gd`: PASS. Actual canonical jump rises 0.6112 m;
  non-looping source is 0.9 s and its playhead advances through takeoff/fall
  without restarting. The landing fade releases it; walking off a ledge does
  not invent a jump. Before/after graph evaluation at identical times changes
  leg rotations but produces exactly zero change in hips and upper-body tracks,
  including fire and reload overlays.
- Hybrid locomotion/action regression PASS. Feature manifests 77/77 PASS.
- Display-backed canonical probe PASS: `/private/tmp/jump-forward-reviewed.json`
  and 44 rear/side frames. Stationary/forward takeoff, bent trailing leg,
  forward lead leg, falling and returned idle/run were inspected. No script
  errors in `/private/tmp/jump-forward-native-output2.log`.
- Initial capture was discarded because it overlapped another coordinated
  posture-signature edit. The successful run above loaded the completed files.
- This verifies the requested leg substitution, not the unrelated full-right
  rifle firing pose. Existing upper-body jump/weapon poses were preserved.
- No browser export, commit or push was performed for this change.

Source audit: the fingerprint-matching packaged library contains `jump_forward_action` as a 0.9-second non-looping animation with 53 tracks. The runtime filter excludes its spine and arm keys. Normal-hop physics ends airborne motion before this clip ends; landing then fades the leg-only layer out. No loop or action-duration change is introduced.

## Forward-heading diagnosis card

Latest player observation: forward jumping appears crooked. Diagnose whether
the imported thigh-local rotations are being evaluated under a differently
oriented base jump pelvis. The existing legs-only graph excludes source Hips,
so filter correctness alone does not prove source-frame correctness. A readonly
canonical/source FK probe will compare real jump hips, knees/feet and source
hip heading at the same source playhead. No runtime, profile, timing, physics,
camera, upper body, hand contacts or natural bob changes during diagnosis.
Owner is the existing graph's test fixture. MERGE diagnostic coverage; defer
implementation choice until actual frame evidence establishes the cause.

### Source-parent frame adapter translation

Measured at 0.25 s: source forward-jump lead knee -0.43 degrees versus live
-43.66 degrees, because source hip bar -99.57 degrees is replaced by base hip
bar -144.22 degrees. Parent frame mismatch varies through takeoff; reject a
constant yaw patch. MERGE exact source-frame rebasing within the existing graph,
called once after its evaluated pose and final parent posture. Saved
`jump_lower_body.match_source_parent_frame` controls it; cache source rotation
track indices at graph construction, sample the existing jump playhead only.

Integration-order delta: the existing posture pass changes the base pelvis
slightly even in an airborne standing stance. Capture the graph's evaluated
weight/playhead pair at process entry, before next-frame graph commands; apply
the same source frame once after posture, before weapon processing. The pair
is a snapshot, not an animation clock. This avoids both downstream parent drift
and accidentally applying next frame's blend weight to the current pose.

For source hip-global Hs, source thigh-local Ls and evaluated hip-global Ha,
desired thigh-local is inverse(Ha)*Hs*Ls. Blend the two thigh rotations using
the existing jump layer amount. Source knee/foot orientation is then restored
without another clock, hips/root or local-position writes. No dormant leg
stabilizer is revived. No upper-body, weapon, body, camera or phase changes.
This intentionally does not straighten the whole airborne pelvis: it repairs
the legs-only source frame under the existing protected hips contract. Native
visual review must reject any unnatural groin/leg deformation.

Acceptance: thigh-to-toe world rotations match the actual source at full blend;
all upper-body and pelvis transforms and bone lengths remain unchanged. Partial
blend and zero/disabled/missing routes remain bounded; takeoff/fall playhead and
landing behavior stay unchanged. Correctness3->4, ownership/parity5->5,
editor3->3, performance4->4 (cached constant-size sample), coverage3->4.

Final source-frame proof: canonical stationary and forward jumps at 0.183,
0.25 and 0.317 seconds have zero measured thigh-to-toe rotation difference
from source. At 0.25 seconds the lead knee is -0.433002 degrees versus source
-0.433010 degrees, replacing the original -43.66-degree skew. Focused graph
tests pass upper-body/pelvis global parity, all local positions/joint lengths,
zero/partial/full/disabled weights and captured-current-weight versus queued
next-weight separation. Actual jump rise remains 0.6112 m with one playhead and
normal landing. Reports: `/private/tmp/jump-frame-fixed.json` and
`/private/tmp/jump-snapshot-fixed.log`. Native visual acceptance remains separate.

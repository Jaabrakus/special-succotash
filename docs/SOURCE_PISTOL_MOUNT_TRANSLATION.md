# Source pistol palm-contact calibration

## Translation card (2026-09-12)

- Player intent: the source-pose pistol sits inside the closed right-hand grasp,
  while source arms and the free left hand retain their authored pose.
- Acceptance: a saved palm-local offset moves only the existing rigid weapon
  contact; disabled and zero settings are identical to the old mount; repeated
  calls do not accumulate; calibration stays within 80 mm.
- Owner: existing operator weapon-pose ownership contract. The new helper is a
  pure contact-transform consumer, not another weapon transform writer.
- Must not change: arm/wrist bones, source clips, character selection, camera,
  movement/collision, reload or combat timing, damage and networking.
- Proof: `tools/source_pistol_mount_regression.gd`, canonical main pistol
  regression, and rear/side close-up renders with descendant transforms flushed.

## Evidence and bounded delta

The existing palm anchor averages finger-base joints. On the selected modern
ISO skin, this lies outside the volume enclosed by curled fingers. Roll tests
show the original orientation is appropriate (bore +Y, gun up +X in the palm
frame); a 90-degree rotation is rejected. Offset candidates of 20–45 mm were
rendered without changing arms. The selected candidate is `(0, .015, .035)`
metres in the orthonormal right-palm frame. This is target-rig grip calibration,
not a claim of exact original-game hand proportions or perfect thumb contact.

The shared probe previously flushed only the weapon root while sampling a
paused tree. Descendant mesh transforms could still show an earlier mount.
Recursively flushing Node3D descendants before rendering fixes that proof bug;
it does not advance animation or change runtime gameplay.

Decision: **MERGE** a bounded saved contact offset into the existing getter.
Scores (old -> candidate, 0–5): correctness 2->4, ownership 5->5,
runtime parity 3->5, editor usability 2->4, performance 5->5,
regression coverage 2->4. Evidence: `operator_weapon_pose_kinematics.gd`,
`operator_source_pistol_mount.gd`, `source_pistol_mount_regression.gd`, and
`rifle_reference_visual_probe.gd`. Root agent owns the shared profile field,
runtime flag propagation, and feature manifest update.

## Limits

Finger surface and trigger/thumb placement still require final artistic review;
the contact offset cannot repair skin topology or skeleton proportions. No
original animation or character asset is overwritten.

## Verification

- Helper regression: PASS, `/private/tmp/source-pistol-mount-unit.log`.
- Probe inheritance parse: clean, `/private/tmp/source-pistol-mount-probe-parse.log`.
- Canonical main selected-character candidate render:
  `/private/tmp/pistol-palm-offset-runtime.log`. All five sampled contacts remain
  exact and every synchronous capture preserves source pose/time/body invariants.
- Baseline side image:
  `/private/tmp/pistol-palm-offset-runtime/proof-palm_offset_0_0_0_mm-side.png`.
- Chosen candidate side/rear images:
  `/private/tmp/pistol-palm-offset-runtime/proof-palm_offset_0_15_35_mm-side.png`,
  `/private/tmp/pistol-palm-offset-runtime/proof-palm_offset_0_15_35_mm-rear.png`.

The diagnostic assigns the shared solver field temporarily, never writes a
saved profile, and restores it before exit. The root implementation owns saving
the chosen value, final whole-pistol action regression and feature gate. The
driver restricts authored settings to 50 mm; this helper also rejects non-finite
input and defensively limits direct consumers to 80 mm. Chosen magnitude is
38.1 mm. Do not interpret zero marker error as perfect skinned finger contact.

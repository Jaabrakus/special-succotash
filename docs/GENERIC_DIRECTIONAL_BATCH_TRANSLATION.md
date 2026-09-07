# Generic long-gun directional carry candidate batch

## Shared-baseline budget pass

One roster sweep `/private/tmp/shared-roster-once.json` completed 14,388 frames:25 pass/8 fail. Held IDs:9mm_sub,aks-74,hk5,m14,m16a2-m203,m4a1-m203,m4a1_sd,mark_46_mod_0. Current geometry was preserved in the test rather than importing earlier support-marker experiments. Native examples of9mm_sub stop andAKS crouch fire confirm poor hand presentation, so neither is assigned. Concurrent work changed `operator_animation_driver_runtime.gd` and `operator_posture_layer.gd` during the sweep. Retain its evidence as a running-snapshot result, not proof of the latest runtime. Recheck only the two newly eligible assignments870/F90 against stable current sources; do not repeatedly rerun the entire roster. Preserve all unrelated edits. No full-roster release claim follows this bounded pass.

The current-source870/F90 follow-up passes872 frames with stable runtime hashes, contact maxima1.860/4.013 mm and unchanged saved human bounds. Its initial text-level geometry hold was a false positive: JSON socket X differs only by ~3e-18 after normalization through Godot vectors. Compare both sides through the same canonical normalizer rather than serialized source text; no contact tolerance is loosened and centimeter-scale experimental contact changes remain blocked. Assign only these two existing directional rigs, preserving every other raw JSON line. This brings17 long-gun profiles onto shared directional behavior; eight pistols remain separate and eight failed long-gun upgrades remain unassigned. Neither native all-weapon parity nor browser/roster release is claimed.

Intent: reuse the existing AK/M4 authored-stock, directional carry and recovery implementation across long guns, retaining each gun's geometry, gameplay and separate pistol route. Acceptance: one actual-input roster matrix with the existing contact/bore/anatomy limits; keep failed or geometry-changing candidates unassigned. Owner: existing visual-rig resolver and weapon pose solver, not another runtime system. Protected: current models, scale, all contacts, weapon stats/reload/recoil/sounds, pistols, movement/camera/network and unrelated dirty work. Proof: `generic_directional_batch_regression.gd --all-firearms --use-candidate`; existing canonical fixture covers 33 IDs. Only candidates whose visual geometry equals their current normalized profile can be assigned in this pass. Native review targets failures; no new art or per-gun redesign. Existing approved per-model pocket calibration stays distinct from shared behavior. Six-axis delta: correctness3→4 conditional, ownership5→5, parity5→5, editor5→5, performance4→4 (no new runtime code), coverage4→5. **MERGE passing geometry-preserving profiles; KEEP the previous assignment on failures.** Full roster/name release remains separate and gated. This narrows the previous all-state/model investigation for credit efficiency; it does not claim unmeasured prone parity.

## Translation card — 2026-09-06

- **Player intent:** Extend the corrected AK/M4 movement/aim semantics to the remaining generic rifles, SMGs, machine guns, shotguns and snipers without replacing their current models or moving their existing grip contacts.
- **Acceptance:** Each real firearm passes actual standing/crouched A/D/accepted-fire/reversal/stop physical checks with unchanged 42–150° rifle elbow limits, 5 mm contacts and 1° fully-ready bore. Existing family/action/reload routes, meshes, scales, mounts and all seven socket values remain exact. Both identities in a shared-model pair are tested. Candidate data alone is not approval; native and prone/action/reload negative controls remain mandatory before promotion.
- **One owner:** Existing saved visual-rig resolver and authored weapon presentation owner. New immutable directional revisions plus explicit raw visual-rig references only; no global family-default replacement or second pose writer.
- **Protected:** Pistols, AK/M4/M16/M40 and their rigs; CharacterBody movement/collision, camera/reticle, server weapon authority, gameplay statistics/timing, source animations, original immutable rigs, all raw model paths, roster and display names. The 870 and 9mm_sub keep their current models; separate 1212 asset candidates are not assigned here.
- **Focused proof:** New batch proof validates exact visual-field deltas, legacy stock policy and raw identity/gameplay parity, then reuses `firearm_family_transition_regression.gd`. Begin with 870, HK5SD and M82A1A only after the parent-owned authored-stock-only API is parse-clean; run remaining candidates only after those pass. Preserve every failing result instead of adjusting thresholds.

## Data boundary and candidate seeds

The read-only inventory in `LONG_GUN_CONTACT_REUSE_AUDIT.md` identified 21 generic
records using 17 rigs, with no ordinary stance/clip/frame contact overrides.
Each revision copies its own literal source JSON, changing only revision/id,
review metadata, and the explicitly listed handling fields. Original numeric
text is retained so the Godot reader sees identical model/contact values.

Add authored shoulder stock opt-in, locomotion-ready carry 1, square idle pelvis,
right turn weight 1, left elbow flare 12°, chest-forward right release .33 m,
ready-pocket downward .03 m and right wrist roll −15°. The existing generic base
pocket defaults downward .035 m, yielding the .065 m seed overall. These are
**candidate seeds**, not universal calibration or certified anatomy. Preserve
`buttstock_constraint.enabled=false`; parent separately adds explicit opt-in
access to a valid stock marker only inside the new strategy, so old prone/action
fallbacks remain inactive. Do not globally enable the legacy stock constraint.

Add only four locomotion aliases (`run_left/right`, `crouch_left/right`) for the
existing full-lateral leg presentation. Preserve `LONG_GUN` where authored;
there is no need to relabel shotguns/snipers as rifles. The family-ready and
reload/action slots continue through the shared normalizer unchanged.

## System-delta review

Current generic presentation scores (0–5): correctness2, ownership5, canonical
parity5, editor5, performance4, coverage3. Candidate target: correctness4 and
coverage5 **only after** physical/native/action proofs; all protected-owner
scores stay unchanged. **MERGE candidate data for testing; reject promotion of
any failed geometry.** Source evidence: existing immutable rig/assignment
resolver, driver evaluated carry inputs and authored stock helper named in the
read-only audit. No roster expansion accompanies this pass.

## Status

Prepared candidates are not a release. First-trio and subsequent results are
recorded below when actually run against the parent-owned stable API.

### First-trio seed result

Parent's authored-stock-only access API passed parse/scope proof before this
run. Exact candidate validation passes all17 new rig visuals and the three
selected canonical raw/gameplay signatures. Only 870, HK5SD and M82A1A have raw
candidate references; remaining18 records remain unassigned.

`/private/tmp/generic-trio-seed.json` exercises1,308 actual canonical frames.
M82A1A passes.870 fails right-elbow minimum42° (41.389–41.927°) during A-fire,
A-to-D and standing ready-stop. HK5SD fails left-elbow maximum150°
(155.225–160.802°) in the same phases. Both retain valid contacts/bore; D release
passes. These are per-model reach failures, not permission to lower the existing
anatomical bounds. The batch is held before assigning the remaining records.

Proposed isolated calibration: open870's right elbow with a slightly lower
ready pocket; reduce HK5SD's support reach with a higher ready pocket. Keep all
sockets and D release fixed, verify in the same canonical matrix, and publish a
new immutable revision rather than overwriting the seed. The separate1212 asset
owner controls future870/9mm_sub mesh candidates and must coordinate their raw
references; this batch does not overwrite those assignments.

The integration graph gate passes all87 current contracts with exit0 in
`/private/tmp/generic-feature-contract-output.log`. Structural completeness is
separate from the failed870/HK5SD geometry; neither is marked accepted.

### Per-model calibration delta — approved continuation

The first-trio failure establishes that one pocket seed cannot fit every model.
**MERGE** bounded per-model saved pocket calibration into the existing candidate
strategy; do not change contact positions, meshes, gameplay or physical limits.
HK5SD first changes only `ready_shoulder_pocket.downward_m` from .03 to .00 to
reduce its overextended left arm. The registry records this exact exception,
and the batch proof compares against it rather than relaxing any measured bound.
These newly authored, unapproved candidate revisions may be iterated with a
recorded result; none of the old immutable source revisions may be edited.
Passing candidates stay assigned. Failed candidates are unassigned while their
next bounded calibration is prepared, so known failed geometry is not left live.
Independent models may proceed without waiting for an unrelated model blocker.
The 870 seed pointer is removed now with the separate1212 asset owner's consent;
that owner controls the next870 and9mm_sub model-specific assignments.

HK5SD pocket-down0 result:436 frames retain valid palms and bore, but maximum
left elbow157.219° still fails150°. The minimum extra-down setting is exhausted.
Next isolated candidate shifts the existing base pocket forward offset from its
default+.015 m to−.010 m (25 mm toward the back of the shoulder); no socket moves.
This uses the existing saved stock-pocket configuration and keeps its legacy
`enabled=false`. The batch proof allows only the explicitly recorded base-pocket
offset exception. A saved forward-offset change also affects the authored D
target, so the complete A/D/reversal/stop matrix must pass, not only static A.
Independent remaining generic seeds are assigned temporarily for their complete
matrix; any failed weapon's pointer is removed after that result is recorded.

HK5SD back-pocket candidate passes436 actual frames (palms≤1.17 mm) with legacy
stock still disabled; native and action/prone proof remains pending. The next
17-record preflight caught an assignment-tool mistake before any gameplay ran:
three extension shotgun records already contain explicit rig pointers and nested
source metadata. Remove only the newly inserted duplicate pointer/schema lines,
then replace the existing top-level pointer in place. The registry records the
original pointer so the proof reconstructs exact original raw text, preserving
nested metadata and all gameplay values. Do not strip every matching JSON key.

The first expanded actual-input seed pass finds substantial model-dependent
failures: M16/M4 grenade variants, suppressed M4,552/M60,AKS/Mark46,M14,HK5 andF90
exceed contact or elbow bounds. Their candidate assignments are removed as each
weapon finishes; no failed seed is treated as playable approval. M63A andM87
retain millimetre-level contact so far, pending the completed assertions. This
baseline began before a separately owned test-only throwable-input isolation
fix; final candidates must rerun the corrected visible-weapon fixture too.

### Per-model second-pass candidates

The expanded baseline distinguishes three reach conditions.552/M60 elbows clear
42° but trigger palm misses24.4 mm near the lower limit; extra pocket-down .06 m
(was .03) opens that same ready-only bend without new IK passes.12-gauge pump
right elbow41.37° similarly gets extra-down .05 m. F90 needs both a more open
right elbow (extra-down .055 m) and a larger existing right carry release .36 m
(was .33) for its left elbow36.8° during D-stop. All four changes use existing
authored-only saved fields and retain action/prone routes.

AKS/Mark46 andHK5 show much shorter stock-to-trigger spans and genuine right-arm
folds. Their next pocket-only trial uses extra-down .05 m and base forward .07 m
(default .015), bringing the trigger farther from the shoulder. This may only
be accepted after visible stock/chest clearance review; a numeric pass is not a
claim that a forward stock placement looks correct. Base-pocket offsets remain
inactive in legacy action/prone consumers because `enabled=false` is unchanged.
M14 and the longer M16/M4 variants remain unassigned pending a distinct support
reach review; do not compensate for long fore-ends by stretching the arm.

Second pass:12-gauge pump,552 andM60 pass (palms≤2.23 mm). F90 still loses a palm
briefly during crouch stopping despite valid measured final elbow bounds;
AKS/Mark46 andHK5 also retain transient contact/fold failures. Their raw candidate
assignments are restored to baseline. These are held, not accepted.

### Read-only surface and reach diagnostic delta

Use the existing M16 triangle-surface inspector as a template for the four
unassigned long-fore-end models. Inspect each model in its actual calibrated
socket-parent space; compare the original grip to 4/8/12/16/20 cm rearward points
at unchanged lateral/vertical coordinates. Report nearest real triangles and
render side/oblique/underside witnesses. The diagnostic never saves a contact
or changes a runtime model. A close triangle must also be an appropriate fore-end
surface before any new candidate can be authored. This is test-only evidence,
not a geometry threshold waiver or permission to move sockets into empty space.

For the short-stock transients, add read-only requested wrist distance and
two-bone reach-envelope observations to the existing matrix. Those distinguish
an unreachable requested endpoint from a finite IK/override residual without
adding passes, moving markers or changing the solver.

The batch diagnostic may now use `--use-candidate`, matching the existing1212
fixture: canonical gameplay equips the original saved weapon, then the same
normal visual-contract merge/equipment handoff loads the saved unassigned rig
in memory. Prove unchanged mechanics and model, and label this explicitly as a
preview rather than saved assignment approval. This avoids repeatedly enabling
known-failing raw assignments while measuring reach. Final acceptance must rerun
without this flag after the saved pointer is assigned. No runtime file changes.

### Third short-stock fit — measured requested endpoint clearance

The read-only wrist target report proves the large residuals occur just above
the lower reach envelope: F90 left requested234.951 mm vsminimum232.192 mm;
AKS right232.669 vs232.065 mm; HK5 right243.416 vs232.064 mm. These are finite
near-fold IK failures, not support overextension. Do not add iterations or loosen
angles. Increase F90's existing right-front release .36→.40m (within its saved
API limit) to open the left bend through stop, and AKS/Mark46/HK5 ready-only extra
down .05→.07m to give their trigger wrist more bend clearance. Keep the prior
base forward .07m trial and all physical markers exact. These remain in-memory
candidates until the full matrix and native shoulder/hand appearance pass.

### Four evidenced support contacts — approved scope expansion

Parent approved correcting the persistent support contact on these four existing
models, including revalidation in prone/reload rather than preserving an
incorrect point solely for field equality. Original source revisions stay
immutable; candidates stay unassigned until full proof. Nearest-triangle data
comes from `/private/tmp/generic-fore-end-exact-<id>-surface.json`, with native
side/oblique/underside witnesses at `/private/tmp/generic-fore-end-native-*`.

- M14: use the rear receiver/magwell support surface160 mm behind the old point,
  2.31 mm from the triangle before projection; this is a rear receiver grip on
  the existing placeholder model, not a claim of a historically exact M14.
- M16/M203 andM4/M203:40 mm rearward fore-end point projected upward to the real
  lower handguard; old points were18.69/18.67 mm below the mesh.
- M4SD:80 mm rearward point projected to the actual handguard surface; old point
  was19.55 mm below the mesh.

Keep original lateral coordinate, replace only support Y/Z with the recorded
triangle witness, and preserve the other six markers, all mesh/mount/scale and
gameplay/action fields. The shared saved contract remains the owner. Update
exact-data proof with only these named per-model exceptions; require unchanged
balance, actual standing/crouch transitions, prone/reload/regrip and native grip
review. **MERGE only after proof**, not automatic approval of a nearest triangle.

The derived generic reload proof reuses the current canonical reload lifecycle
test for standing/crouch/prone. It may load saved unassigned candidates through
the same normal in-memory visual handoff, preserving gameplay fields. Require
trigger-palm contact and ammo/cadence/reload-duration conservation as before;
also check authored stock stays inactive in prone/action ownership and support
contact returns within10 mm after completed regrip. This is test-only coverage,
not a new reload implementation. Existing reload is free to release the support
hand while the action itself is active.

After the interrupted worker's second pass finished, the parent inspected all3052
frames.12-gauge,552 andM60 pass the unchanged measured bounds. F90,AKS,Mark46 and
HK5 still fail; their candidate pointers were removed, preserving the raw weapon
files and keeping candidate visual documents for further calibration. No failed
assignment is accepted just because its process was interrupted.

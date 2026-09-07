# AK/M4 upper-body stability — diagnostic translation

CURRENT INTENT OVERRIDE: keep natural head bob. Vertical gait suppression below
is historical/rejected and is removed from runtime. Retain relaxed square carry,
readiness-gated directional torso, and scoped exact local-pose rotational
isolation for larger lateral leg yaw. No head/Spine position stabilization.

Player intent: remove visible shoulder sway and head bob while keeping the
moving legs and camera unchanged. Latest clarification: relaxed movement keeps
square shoulders in every direction; the directional right-turning frame enters
only during accepted fire/recovery, then returns with existing readiness.

Acceptance for this diagnostic: measure complete settled A/D cycles in standing
and crouch, both relaxed and repeated accepted fire. Report actual head, spine,
hips and shoulder movement/rotation ranges in canonical main.tscn. Separate
hip translation from upper-chain height variation. Do not claim a fix yet.

One owner for a later candidate: existing operator posture/animation driver.
The diagnostic only reads evaluated bones and issues canonical movement/fire
inputs in the existing distant flat test fixture. No profile or runtime edits.

Protected: CharacterBody3D movement/legs/collision, camera/reticle, shot rules,
weapon sockets/stock, joint limits, reload, prone, other weapons and dirty work.
Full-D arm-fold failure remains unresolved and must not be hidden by this pass.

Chain under inspection: input -> canonical player/mannequin visual contract ->
saved AK/M4 handling profile -> existing locomotion masks + posture layer ->
rendered upper-body motion. Current evidence: AIM_FRAME excludes Hips; posture
separates hip rotation but not translation; gait roll retention defaults to .18.

Focused proof: tools/rifle_upper_body_cycle_probe.gd, with separate AK/M4 output
prefixes. Head/chest/hip position ranges, world rotation ranges, shoulder-bar
roll/yaw and exact actual speed/readiness are diagnostic outputs, not relaxed
new acceptance thresholds. Parent may authorize a bounded stabilization only
after these measurements and a new candidate delta entry.

System delta: KEEP current runtime during diagnosis. Correctness unresolved;
ownership5->5, parity5->5, editor4->4, performance4->4 (diagnostic only),
coverage2->4 through reproducible cycle measurements. No implementation or
publication decision is made by a successful diagnostic run.

## Authorized candidate: steady square carry, September 6

Measured baseline (both AK/M4, canonical cycles): standing hip Y range 7.73 cm,
head 8.65–10.10 cm; crouch hip 3.70 cm, head 4.39–4.82 cm. Head/hip Y correlation
is .92–.99. Camera yaw/pitch range zero and body Y range under 0.01 mm. This
identifies source hip translation as the dominant inherited bob, with remaining
rotation leak from retained gait roll and fractional crouched separation.

Player intent: relaxed movement always uses a square, steadier upper body;
rightward torso turn begins only with existing shot/recovery readiness. Preserve
the moving hips and legs and the authored crouched idle-to-move height change.

Owner: existing posture layer, configured by its existing animation coordinator
and AK/M4 saved strafe-carry opt-in. Sample the mean hip position of the actual
standing/crouched moving clips once during driver setup. Counter only the moving
hip's small vertical cycle at Spine, never Hips, and fade corrections outside the
cycle envelope so the kneeling-to-moving transition is not flattened. Preserve
same-frame idempotence and clear the correction when the opt-in is inactive.
Use zero inherited roll and settled separation only within the opted-in movement
scope. Scale D yaw/hip follow by existing presentation readiness, not a new timer.

Acceptance: lower evaluated head/chest height ranges without changing measured
hip range, legs/phase, body/camera or accepted firing; relaxed A/D/forward square;
actions/air/prone/other weapons unaffected. Retain existing physical hand/stock
limits. Full-D folded arms remain an independent blocker; no export approval.

System delta: MERGE bounded candidate. Correctness 2->4 pending measured proof,
ownership 5->5, canonical parity 5->5, editor usability 4->4 (same saved opt-in),
performance 4->4 (one-time source sampling, constant-cost bone correction),
coverage 3->4 via before/after cycles and frozen-frame/guard regression.

## Candidate measurements and limits

Canonical M4 cycle ranges in centimetres, before -> candidate (AK agrees within
sampling/recoil variation):

| State | Hip Y | Head Y | Chest Y | Shoulder-centre X |
| --- | --- | --- | --- | --- |
| Standing A relaxed | 7.73 -> 7.73 | 8.65 -> 1.08 | 7.73 -> .24 | 2.41 -> 1.80 |
| Standing D relaxed | 7.73 -> 7.73 | 10.10 -> 1.18 | 8.04 -> .24 | 8.01 -> 1.74 |
| Crouch A relaxed | 3.70 -> 3.70 | 4.62 -> 1.55 | 3.59 -> .20 | 3.46 -> 1.65 |
| Crouch D relaxed | 3.70 -> 3.70 | 4.71 -> 1.78 | 3.61 -> .18 | 3.72 -> 1.32 |
| Standing D fire | 7.71 -> 7.71 | 9.89 -> 3.51 | 8.04 -> .90 | 8.27 -> 8.34 |

Evidence: `/private/tmp/upper-cycle-{ak,m4}.json` and
`/private/tmp/upper-steady-{ak,m4}.json`. Both diagnostic runs PASS their actual
movement/readiness assertions; this is not a physical contact or visual-parity
approval. Unchanged camera aim yaw/pitch range zero, body Y range ~6 micrometres.

Remaining failures are explicit: A shoulder bar remains ~18.9–19.3 degrees off
the actual reticle frame (not a camera-heading artifact), relaxed head angular
motion ~4 degrees persists, and full-D fire support-hand errors remain 2.8–3.7 cm.
The candidate is a measurable reduction of bob, not complete requested parity.
No socket, stock, arm-length or elbow-limit changes were made to conceal this.

`rifle_upper_body_stability_regression.gd` PASS: rotated/scaled fixture height
error under .000001 m; no Hip/leg writes; frozen-frame idempotence; zero-weight
restore; kneeling-transition exclusion; prone/actions/air/other-profile guards;
all movement directions square-gated, D target follows only existing readiness.
Its additional diagnostic proves legacy rest-conjugated hip rotation can leave
8.75 degrees of world-head residual in a nonidentity-rest fixture; exact
evaluated local-pose compensation yields zero. This rotational candidate has
NOT been applied: the newest user clarification prioritizes leg travel direction.

Protected checks PASS after this candidate: `strafe_head_orientation_regression`
(18 matrix cases), `operator_pose_pipeline_regression`,
`pistol_compressed_idle_regression` (4 cases/2 reloads),
`fire_recoil_live_regression`, and `feature_contract_regression` (78 contracts).

## Latest delta: legs do not fully face A/D

Read-only foot evidence, standing M4: foot-to-toe horizontal headings during the
lowest 25% of each foot cycle are A left -38.9/right -4.4 degrees and D left
+9.1/right +43.6 degrees (zero camera-forward, +90 right). The exact ~48-degree
A->D change matches the saved +/-24-degree source clip offsets, not +/-90.
Files: `/private/tmp/upper-feet-left.json`, `/private/tmp/upper-feet-right.json`.
Raw airborne toe headings wrap and should not be mistaken for planted facing.
Root agent owns the next lower-body direction delta; this subtask leaves that
map/graph, camera, CharacterBody and all weapon contacts untouched.

## Authorized exact local-pose isolation delta

Before larger lateral hip yaw, parent authorized the proven scoped rotational
correction. Code evidence: `_apply_bone_additive` left-multiplies the correction
onto `get_bone_pose_rotation`, whose evaluated local rotation already includes
the rest orientation. The previous `_upper_body_hip_correction` additionally
conjugated through Spine rest, giving H * S^-1 * H^-1 * N * S instead of N for
the parent chain. The nonidentity-rest live Skeleton3D fixture measures 8.75
degrees residual for that legacy route versus zero for H * H^-1 * N.

Owner/chain unchanged. MERGE an optional exact-local-pose blend within the same
hip-compensation method, controlled only by existing saved rifle-movement
stability weight. Use the same scoped weight for baseline and retained-hip
corrections so the existing head counter cancels their exact world delta.
Defaults preserve all other weapons, actions and postures. No torso target,
stock/contact, joint-limit, camera or CharacterBody changes. Accept only with
synthetic default-route parity, fractional gating, head/pose regressions and
canonical before/after cycles. Full-D physical contact remains separately gated.

## User override: keep head bob

REJECT only the newly added vertical suppression: remove mean-source hip-height
sampling/binds, posture height reference/cache, and Spine position writes. Keep
the scoped square relaxed movement/readiness gate and exact-local-pose rotation
needed for lower-body direction isolation. Rename the final posture parameter to
`rifle_movement_isolation_weight` to state its remaining responsibility. Natural
hip-driven vertical head movement is the acceptance rule now, not low Y range.
The focused regression must prove hip/head vertical motion remains present,
Hip/leg transforms stay unchanged, and rotational/default-route guards still
pass. Historical before/after suppression numbers above are NOT current claims.

Current override proof: `rifle_upper_body_stability_regression` PASS with equal
9.5215 cm hip/head vertical range in the scaled/rotated fixture, exact local-pose
rotation zero-error and legacy/default route unchanged. Head regression also
PASS with 18 additional exact-scope/fractional-ready/frozen-cache cases.
Canonical M4 standing A now again has hip 7.73 cm/head 8.65 cm/chest 7.72 cm Y
ranges; AK crouched D has hip 3.74/head 4.99/chest 3.79 cm. Camera aim yaw range
zero. Reports `/private/tmp/upper-natural-m4.json` and
`/private/tmp/upper-natural-ak.json` confirm vertical head bob is restored.

## Scoped articulated hip-counter candidate

Player intent: keep fully lateral moving legs and reticle-facing A shoulders,
without the visible waist pinch caused by applying the entire hip counter at
Spine. Natural head bob stays. Acceptance: identical net chest/head rotations,
unchanged hips/legs and no position writes; visibly improved waist/armor before
publication. Owner is the same posture layer and saved rifle movement opt-in.
No stock, contact, grip, camera, body, joint-limit or other-profile changes.

Let H be Spine's parent rotation, C the existing hip counter and B0/B1/B2 the
three authored local rotations including existing aim additives. Existing final
chest is H*C*B0*B1*B2. Define Q=H*C*inverse(H). Applying skeleton-space powers
Q^.18, Q^.32 and Q^.50 successively at Spine/Spine1/Spine2 yields exactly
Q*H*B0*B1*B2, the same final chest rotation. The shared fixed-axis powers commute.
Intermediate origins articulate naturally about their bones; none is rewritten.
For smooth scope w use fractions (1-.82w, .32w, .50w), sum1. Preserve literal
old path when w=0, normalize over unique present bones for safety. Existing head
counter remains valid because the net chest rotation is identical.

System delta: MERGE candidate pending rendered proof. Correctness3->4,
ownership5->5, parity5->5, editor4->4 (same opt-in), performance4->4 (three bounded
bone rotations), coverage3->4. Proof: mixed-base/rest/scale mathematical fixture,
head/cache/guard regressions, canonical physical A regression and native views.
Reject on worse waist/armor or failed contacts. Full-D grip remains independent.

## Idle-pelvis mathematical proof card

Player intent: the opted standing stationary pelvis faces straight without
flattening its natural lean or changing movement. This test-only addition owns
the regression fixture, not runtime behavior. Acceptance: zero weight preserves
all bones; full weight aligns the measured upper-leg root bar to canonical
horizontal X; fractional weights apply exactly the requested portion of yaw;
settled frozen calls are idempotent. Mixed evaluated parent/hip rotations, rest
bases, mirrored canonical-side fixtures and uniform world scales must preserve
every local bone position and each world-space vertical origin. All existing
runtime, profiles, camera, CharacterBody and weapon contacts stay unchanged.
System delta: MERGE proof, coverage3->4, all other scores unchanged. Native
stationary contact/transition verification remains a separate canonical gate.

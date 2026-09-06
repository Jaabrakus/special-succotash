# Reticle climb, armory slots, and original team characters

## Translation cards

1. VRC intent: shots go where the raised reticle points, while camera orientation stays fixed.
   Acceptance: repeated accepted shots accumulate to each gun's cap, then return;
   the sight ray and replicated aim packet project to the displayed reticle.
   Owner: SocomCameraRig through its existing input presenter and aim resolver.
   Protected: camera yaw/pitch, body movement, damage/spread rules, authoritative
   server validation. Proof: vrc_armory_regression and lobby_warmup_regression.
2. Armory intent: no visible SOCOM reference; carry one primary and one pistol.
   Acceptance: purchasing replaces only that slot; keys 1/2 and local equipment
   wheel switch between held guns without refilling ammo. Training controller
   owns local carried slots; warmup server owns network carried slots. Existing
   ammo owners retain counts. Protected: live tournament shared random weapon,
   throwables, reload timings and gun tuning. Proof: the same two regressions.
3. Appearance intent: return to the original character, blue against green.
   Acceptance: original FBX is selected by canonical scene, runtime fallback,
   and preload path; team colors affect cloth but not weapon attachments.
   Owner: SocomOperatorAssetRuntime with shared TeamAppearance presentation.
   Protected: skeleton, collision, hand attachment and animation selection.
   Proof: blue_green_operator_regression plus firearm live contact regression.

## Configuration

`config/reticle_climb.json` enables VRC and supplies defaults. Per-weapon
`reticle.shot_kick_px` is rise per shot; `maximum_shot_kick_px` is its height cap.
`vrc_enabled`, `vrc_recovery_delay_seconds`, and
`vrc_return_speed_px_per_second` override the shared defaults in each weapon JSON.
Gunsmith exposes those controls and saves them through its existing repository.
Armory details read the saved weapon profile, not the old catalog tuning snapshot.
They show VRC statistics, not competitive tuning controls.

Units are reference pixels at 1080 viewport height: the same normalized offset
is used at other resolutions. Default recovery delay is 0.18s, return 180px/s.
Recovery waits at least 1.05 firing intervals so sustained legal fire can climb.
The recoil from a shot moves the aim for subsequent shots, not retroactively.
The server still validates the ordinary aim-intent packet and owns damage.
This is reference-inspired provisional tuning, not measured original game data.

The old independent cosmetic upward bounce is suppressed while camera-owned
VRC is active. Radial spread bloom remains separate. Swapping weapon profiles
resets the climb; routine HUD refreshes do not reset it.

Training owns two carried IDs in SocomWeaponController. The buy-menu driver
reads that state rather than committing purchases before a successful equip.
Press 1 for primary, 2 for pistol, or choose either from the training wheel.
Switching during a pending local reload is blocked. Ammo stays with each gun.
Lobby warmup enforces the same two-slot category rule on the host and replicates
the approved slots. Slot switching passes the same authority and cooldown checks
as selection. Stored magazine/reserve counts are restored instead of refilled.
Live tournament rounds still use their existing identical random gun assignments.

`config/operator_team_appearance.json` selects the original gas-mask source and
blue/green cloth colors. A body-only shader recolors blue cloth; BoneAttachment3D
descendants (weapons and gear) are excluded. Tan character assets are retained
on disk but are no longer the active character.

## Boundaries and proof

The user's later clarification supersedes the earlier cosmetic-only design:
bullet direction DOES follow the raised reticle. No second camera, movement,
animation, damage or network authority is introduced.

Godot projection reference:
https://docs.godotengine.org/en/stable/classes/class_camera3d.html#class-camera3d-method-project-ray-normal

The restricted local-network test could not create an ENet host; the same test
passed with localhost socket permission. A first shader render failed because
source_color is a reserved identifier; it was renamed base_tint and rerendered.
Headless checks alone are not accepted as shader/render proof. RichTextLabel
content appended with append_text is asserted through get_parsed_text.
Global editor settings/certificate/asset-case warnings remain unrelated.
No browser ZIP, published build, remote service or git branch is changed.

## Verification results and remaining issue

- VRC/armory regression: PASS for capped climb, fixed camera orientation,
  aim target and replicated aim packet projecting to the reticle, no independent
  cosmetic kick, two slots, replacement and ammo preservation.
- Two-peer localhost warmup: PASS for replicated primary/pistol slots, preserved
  magazine counts on switching, accepted-shot climb, damage and round transition.
- Original blue/green operator: PASS headless and clean rendered check; armory
  rendered and inspected. Shared reticle, public training, sound bank and
  multiplayer architecture focused regressions passed. Feature manifest gate: 51.
- Broad firearm contact check: FAIL, 14 assertions across seven standing pistols
  (226, 9mm_pistol, de__50, f57, m9, mark_23sd, model_18). Support-hand gaps are
  about 0.013 m against the unchanged 0.010 m limit in
  `tools/firearm_family_live_contact_regression.gd`.
- Diagnostic `--pistols-only --comparison-tan` substitutes the prior tan model
  before scene initialization and reproduces all seven affected variants and
  both Ready Aim/FIRE_RECOVERY states. This isolates the failure from the model
  selection change, but does not establish when the underlying contact error
  began. No pose/IK tuning or test tolerance was changed to hide the failure.
- Broad integration remains BLOCKED: `codex/render-deployment` is not `main`.
  No branch switch, browser export, internet or 32-player load test performed.

Current decision: retain the verified VRC/armory changes and original team
appearance; do not claim complete animation readiness while the contact gate
fails. Pistol contact needs a separate bounded pose-owner diagnosis.

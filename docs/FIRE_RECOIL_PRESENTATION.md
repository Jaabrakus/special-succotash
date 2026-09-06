# Contact-preserving firing pulse

Player intent: visible small recoil/right-elbow flare when a gun fires.
Acceptance: accepted shots produce a bounded outward-and-back elbow pulse;
both palms stay within 1 cm of their sockets and bore alignment is retained.
Owner: existing operator weapon-pose socket solver; the envelope writes no bones.
Protected: camera/reticle, shot direction, damage, cadence, locomotion, reload,
and the existing 1.2-second fire-recovery hold.
Proof: fire_recoil_pulse_regression, firearm_family_live_contact_regression,
pistol_fire_direction_pose_regression and rendered early/peak/return samples.

MERGE: retain the stable aim-recovery animation and add a five-degree elbow
swivel inside the existing pose owner. Do not restore the distorted combat-fire
clip. Rotate the upper arm and forearm around the shoulder-to-wrist axis in
skeleton-global space; preserve the final wrist transform exactly. The base
owner clears overrides each frame. Prone uses 35% amplitude. Smooth retriggering
is bounded, not additive. An IK-pole prototype was rejected because it could
snap the arm plane. The final approach does not rerun IK to create recoil.
This pass adds elbow recoil, not independent weapon-root/muzzle rotation.

System delta scores (current -> candidate, 0–5): correctness 2->4,
ownership 5->5, runtime parity 5->5, editor usability 3->3, performance 5->5,
regression coverage 3->4. Evidence: operator_animation_driver_presentation.gd
already routes accepted shots; operator_weapon_pose_kinematics.gd owns the
arm solve; the new envelope reads config/fire_recoil_presentation.json and
adds no runtime nodes or competing bone owners. Shared JSON remains editable directly.

Godot Skeleton3D documentation distinguishes skeleton-global bone poses from
world space. This implementation uses the existing world-position accessor;
it uses the existing pose owner's global override mechanism, not a new modifier lifecycle.

Validation note: Mark 23 standing idle entry still fails the aim-plane limit
at frames 1 and 2 with recoil enabled AND disabled (--no-recoil). This predates
the pulse. The recoil test compares the same solved frame, not two calls to the
full driver, which would also advance the weapon ownership handoff.

Final proof: bounded-envelope test PASS; six M4/Mark23/870 standing/crouched
fixed-palm and shoulder tests PASS; rendered checks PASS; 42 weapons / 84
standing/crouched contact cases PASS; 66 feature contracts PASS. Whole integration
gate remains blocked by its main-branch requirement. Editor parsing had no
script errors; macOS certificate/editor-settings permission warnings remain.

Browser export: builds/SOCOM-141-browser-tournament.zip (about 75 MiB compressed,
114,000,875 bytes extracted), archive integrity and exported hashes PASS.
Chrome loaded the launcher and entered Training Grounds. Remote auth signup
returned HTTP 422 and the launcher reported cloud offline; online matchmaking
was not verified. Browser voice capture also reports disabled audio input.
No deployment was made. Localhost:8060 serves builds/web for playtesting.

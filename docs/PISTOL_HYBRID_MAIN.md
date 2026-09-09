# Main-game pistol fallback

Player intent: keep SEAL movement but restore legacy pistol torso/arm poses and fitted hands in the normal game.
Acceptance: normal main.tscn loads the saved hybrid map; standing/crouched pistols use masked legacy upper poses, rifles retain SEAL routes. Physical grip checks and rendered moving/fire/idle samples must pass.
Owner: existing OperatorAnimationTree for pose, existing WeaponPoseSolver for contact.
Protected: CharacterBody movement, camera/reticle, damage/network authority, original clips, prone/dive/jump source poses.
Proof: seal_locomotion_visual_probe --main-profile, focused hybrid regression, feature-contract gate and rendered review.

System delta (correctness, ownership, runtime parity, editor usability, performance, coverage): current 2/5/2/3/4/4 (candidate source wrists visually failed despite numeric contact); candidate target 4/5/5/4/4/4 (saved hybrid, existing masked graph and legacy contact owner). MERGE, not a second skeleton writer. Scores are intended acceptance, not proof of visual completion.

Activation: config/operator_animation_map.json is the normal default; previous bytes are preserved in config/animation_presets/pre_seal_main.json. Pure SEAL candidate remains separately selectable. Already-running processes retain their loaded map until relaunched; no process was restarted for the user.

Proof checkpoint: pistol_hybrid_main_regression PASS for nine normalized pistols and rifle re-equip. Main-profile input-driven strafe/fire/return PASS with override disabled. Full hybrid standing/crouched forward/left/right and jump PASS before final wrist correction; final wrist pass separately passes standing strafe. Render5 captures both sides and firing/recovery without altering gameplay aim. Pose is the user's legacy fallback, not a claim of exact original SOCOM fidelity or perfect finger articulation.

Regression lesson: profile numeric merging only accepts registered default keys; test active graph nodes and loaded feature flags, not only contact metrics. Matching palm positions alone does not establish wrist orientation. A masked torso requires the source pelvis frame to be reconciled at the spine without writing hips/legs.

Integration gate remains blocked by its main-branch requirement (current branch preserved). Skill workflow updated to implement approved bounded changes rather than repeat proposals. Its Python validator cannot run because PyYAML is absent; frontmatter unchanged and edit reviewed directly.

Catalog scope: nine records normalize as pistols, including Designator. The extended grip run found Designator failing (~7 cm gap); it is already explicitly excluded in weapon_family_visual_assignments and marked “Targeting device, not a firearm” in weapon_roster_extensions. Do not misreport this as nine firearms passing. Eight playable pistol profiles pass the extended contact run; the test now logs/skips the existing non-firearm presentation exclusions, without altering runtime catalog eligibility or Designator data.

Final saved-main proof: `/private/tmp/pistol-main-catalog.json` PASS for AK-47 plus 226, 9mm_pistol, de__50, f57, m9, mark_23, mark_23sd, model_18. Largest settled ready contact gap 0.000744 m; largest settled bore-to-reticle error 0.03348 degrees. `/private/tmp/pistol-main-full-final.json` PASS for Mark23 standing/crouched forward/left/right firing and actual airborne/landing transitions after the final wrist change. Feature graph gate PASS 100 contracts; mobility-fire-lock and preserved SEAL data PASS. Rendered standing captures `/private/tmp/pistol-hybrid-render5-*.png` match the saved main profile by parsed JSON parity. Tests do not establish perfect finger articulation, every extreme aim angle, or online load performance.

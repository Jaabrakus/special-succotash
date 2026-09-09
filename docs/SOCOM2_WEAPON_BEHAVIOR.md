# SOCOM II weapon settings — bounded first pass

## Translation card

Player intent: replace SOCOM 1-derived weapon feel with SOCOM II evidence. Acceptance for this pass: exact-name firearm matches use SOCOM II FireWait and standing/crouching/prone reticle kick, cap and return settings; posture changes do not erase accumulated climb, equipping another gun does; canonical main and multiplayer use the same saved profile. Owner: existing weapon profile contract (shot cadence consumed by existing authoritative ballistics; reticle intent remains owned by SocomCameraRig). Protect movement, animations, damage, ammunition, shotgun pellets, shot validation, network transport, current bloom/dispersion until original conversion is established, nonmatching weapons, open game and browser export. Proof: byte-complete reader decoding, source-hash/mapping checks, focused main/multiplayer runtime tests, existing reticle/rapid-tap tests and feature-contract gate.

## Evidence and limits

The local USA ISO contains RUN/ZWEAPON.ZAR, containing one zweapon.rdr compiled reader. This was not part of the earlier animation extraction. The extractor reads the ISO without modifying it and reuses the existing archive parser. It retains numeric stance fields including TargetMin/Max, TargetDilateUponFire/Movement, TargetConstrict, KnockCount and accuracy scalars. These are source values, not recovered executable equations. Do not reinterpret KnockCount as burst length or a count of guaranteed accurate shots.

FireWait is imported as 60 / FireWait RPM, without integer rounding. ReticleKnock/Max use the existing project's reference-pixel convention; ReticuleKnockReturn is connected to its explicit VRC return-speed setting. That unit convention and the existing delayed linear recovery are adaptations, not verified PS2 pixel scaling or a complete SOCOM II runtime port. The original movement multiplier, bloom-to-angle conversion, burst accuracy equations and sniper drift remain research-only. This pass deliberately does not install another arbitrary conversion to bullet angles or claim all gunplay is now original.

## System delta

MERGE exact source identity/settings into canonical profiles; KEEP unrecovered equations unchanged. Current -> candidate scores: correctness 2->3, ownership clarity 5->5, canonical parity 4->5, editor usability 4->4, performance 5->5, regression coverage 3->5. Evidence: tools/import_recom_weapons.py uses data/s1 and heuristic angle conversions; scripts/weapons/weapon_ballistics.gd and scripts/network/socom_multiplayer_rounds.gd consume saved RPM; scripts/camera/reticle_climb_profile.gd previously ignores stance. Candidate adds a pure profile resolver, not a second simulation or camera writer. Gunsmith already preserves unknown reticle-section fields when saving.

Godot Dictionary duplicate(true) is used to avoid mutating saved nested stance data: https://docs.godotengine.org/en/latest/classes/class_dictionary.html . Verified against installed Godot 4.7.1; latest documentation can describe unreleased APIs.

## Integration and proof

Startup-loadout delta: use the existing `m4a1` profile instead of the generic `assaultrifle_1` in `config/weapons/operator_loadout.json`, so a new canonical local launch actually starts with source-configured cadence/reticle values. No tournament or live-session loadout is changed. The generic profile remains intact and selectable.

86 source weapon/gear records decoded with complete reader-byte coverage. 29 exact-name firearm profiles imported; unmatched profiles and non-guns excluded. Two original records contain loose annotation atoms (M16A2 and SA-80), including three stray zeroes in stance blocks. The importer retains these in `unparsed_atoms`; it accepts only explicit tag/list fields and never guesses positional pair alignment.

Reference re-extraction against the original ISO passed: `node tools/socom2_weapon_reference_test.cjs <iso>`. The reader SHA256 is `8f1027edc1e3d0d6a936e13f3bcc2f2ee785148d1acbe550776e3b844058d67b`. Protected-profile hash comparison confirmed all fields outside RPM and reticle sections unchanged across the 29 firearms.

Focused headless and rendered main-scene test passed for 29 profiles and three stances, including source return values, rejected early shots, posture clamp without zero reset, weapon-switch reset, and legacy fallback. Multiplayer cadence/standing reticle checked for AK/M4/Mark23. Existing VRC armory, shared reticle and rapid-tap bloom regressions passed. 106 feature contracts passed. Separate rendered standing/prone AK reticle cap images were inspected at `/private/tmp/socom2-reticle-STANDING.png` and `/private/tmp/socom2-reticle-PRONE.png`; these are reticle-setting samples with the actor held still, not stance-animation proofs. No original-game pixel-perfect comparison was performed.

Logs: `/private/tmp/socom2-weapon-behavior.log`, `/private/tmp/socom2-render.log`, `/private/tmp/socom2-vrc.log`, `/private/tmp/socom2-shared-reticle.log`, `/private/tmp/socom2-rapid-tap.log`, `/private/tmp/socom2-feature.log`. Headless runs emitted the environment's macOS certificate warning, disabled microphone-capture warning, and three exit ObjectDB leaks in main-scene tests; those are not claimed fixed. Aggregate quick gate is blocked: current branch `codex/render-deployment`, required `main`. No branch switch, commit, push, open-game restart or ZIP export.

Remaining: original bloom/accuracy equations, source target-unit-to-angle mapping, burst/knock semantics, sniper drift and original recovery interpolation. Numeric extraction is exact; full SOCOM II gunplay is not yet claimed. Source stance values can be edited in each shared profile's `reticle.socom2_stances`; Gunsmith preserves that section, but does not yet expose a dedicated three-stance editor. Source data is not silently regenerated on startup.

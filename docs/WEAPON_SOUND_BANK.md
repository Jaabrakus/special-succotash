# Existing weapon reference sounds

Current coverage is 33 actual firearms using 29 WAVs; see
`docs/WEAPON_AUDIO_COVERAGE.md` for the five added assignments, two explicitly
provisional substitutes, and catalog-wide coverage proof. The 28-entry counts
and M14 deferral below document the original pass, not current coverage.

## Translation card

- Player intent: Each existing matching gun plays its extracted reference shot.
- Acceptance: One matching cached stream for each accepted shot in canonical training and multiplayer; unmatched guns keep their original fallback.
- Owner: LabLeakAudioEngine selects the stream; AcousticPropagation retains spatial playback.
- Protected: Damage, cadence, reloads, recoil, reticle, movement, animation, networking authority, grenades, roster and published exports.
- Proof: weapon_sound_bank_regression, shared_weapon_reticle_regression, hit_feedback_performance_regression, grenade_acoustic_audio_regression and feature_contract_regression.

## Saved contract and limitations

`config/weapon_sound_bank.json` maps 28 existing profile IDs to imported mono WAVs.
Edit that mapping directly in the editor; restart the scene/process to rebuild the cached bank.
Set `enabled` false and restart to use the previous generated sounds for all guns.
No new runtime/editor audio owner is introduced. Existing callers without a weapon ID keep their original preview sound.
Both accepted-shot presenters pass the equipped profile ID and suppression flag.
The bank is warmed during scene startup. No file reads or WAV synthesis occur on repeated shots.

Source: https://www.youtube.com/watch?v=oI3NiRLeRhs
User confirmed reuse permission in this conversation. Cut timestamps and original
WAV hashes are saved beside every mapping. The review extraction pack remains
unchanged under artifacts/audio/socom2_weapon_samples and is excluded from export.
These are recording-derived candidate cuts, not original isolated game assets;
background ambience/mechanical tails may remain. Final listening/mix review is pending.
No normalization was applied; quieter suppressed recordings retain source level.

25 clear catalog matches plus the three already-added training-only prototype
shotguns are enabled. M14 is deferred because its video label describes a
Mini-14/AC-556. 870, Mark 46 and other unmatched weapons retain their fallback.
No automatic family aliases, grenade/launcher substitutions or roster additions.
The prototype profiles' old audio_reference fields describe extraction review
status only; this bank is the sole runtime sound-selection contract.

## Damage and kick audit

Historical audio-pass audit below. The later VRC/armory pass supersedes its
cosmetic-only/default-disabled aim-climb description: see
`docs/VRC_ARMORY_TEAM_PASS.md`. Sound mappings and balance values are unchanged.

Damage and spread bloom are consumed by WeaponBallistics; recoil bloom starts
after the first two continuous shots. SocomDynamicReticle.notify_shot applies
the saved per-shot pixel impulse and cap after the accepted shot. Functional
aim climb is a separate opt-in ballistic flag, false by default. Saved values
are existing game tuning/SOCOM I-derived conversions, not reconstructed exact
SOCOM II statistics. No balance fields change in this pass.

Resource loading follows Godot's imported-resource/cache contract:
https://docs.godotengine.org/en/stable/classes/class_resourceloader.html

## Verification, 2026-09-05

- Import and canonical main-scene boot completed; 28 imported WAVs.
- weapon_sound_bank_regression: PASS, 28 matches, cached identity, PCM hashes,
  non-looping, canonical/multiplayer event selection, suppression and fallback.
- shared_weapon_reticle_regression: PASS, local-only kick/cap and stable aim center.
- hit_feedback_performance_regression and grenade_acoustic_audio_regression: PASS.
- feature_contract_regression: PASS, 48 contracts. All weapon JSON hashes unchanged.
- Full quick integration did not run: tools/run_integration_gate.sh requires
  main, but the preserved branch is codex/render-deployment.
- Tests report the existing macOS certificate-store warning. The editor import
  also reports a duplicate m16a2 scene UID, modular_pack SubMachineGun filename
  case mismatch, and restricted global editor-settings write/ADB access.
  These are not fixed by the bounded audio pass; export/platform readiness is
  not claimed. No parser error or focused test failure occurred.
- Browser export and live internet/listening tests have not been performed.

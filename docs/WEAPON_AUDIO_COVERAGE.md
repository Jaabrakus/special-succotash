# Weapon audio coverage pass

The subsequent cleanup pass preserves these 33 assignments and source hashes,
while selecting separate cleaned derivatives at runtime. See
`docs/WEAPON_AUDIO_CLEANUP.md` for processing, reversion and proof.

## Translation card

- Player intent: Every actual firearm available in training has an intentional gunshot instead of silently falling back to one generic report.
- Acceptance: All 33 firearm IDs have cached, non-looping recordings; both canonical training and multiplayer emit exactly one matching event. Exact, variant and provisional family mappings are distinguished.
- Owner: LabLeakAudioEngine selects streams from config/weapon_sound_bank.json; existing AcousticPropagation owns playback.
- Must not change: Weapon roster, buy rules, damage, cadence, reload, recoil, reticle, camera, movement, animation, networking authority, grenade audio or published builds.
- Focused proof: weapon_sound_bank_regression (catalog coverage, provenance, PCM identity, runtime events and fallback); feature_contract_regression; existing hit-feedback and grenade-audio tests.

## Reference and decision

The supplied, permission-confirmed video is https://www.youtube.com/watch?v=oI3NiRLeRhs (Feral Cat, SOCOM II PS2 All Weapons Demonstration). Its local extraction manifest contains 53 events: 41 fire, 8 launch, 3 detonation and 1 smoke-onset candidate. This is not the playable roster count.

Current 28 mappings omitted both underbarrel rifle variants, the M14 game-labeled recording, and two existing firearms without exact recordings. MERGE: retain the shared cached owner, extend only its saved bank, and test the complete catalog rather than only whichever entries happen to be mapped.

| Added firearm | Sound | Status |
| --- | --- | --- |
| M4A1-M203 | M4A1 | Same rifle's bullet report, not launcher discharge |
| M16A2-M203 | M16A2 | Same rifle's bullet report, not launcher discharge |
| M14 | M14-labeled section at 1827.74 seconds | Game-label match; source's Mini-14/AC-556 annotation retained |
| 870 | 12 Gauge Pump (Mossberg 590) | Provisional family substitute, NOT an exact 870 recording |
| Mark 46 Mod 0 | M63A | Provisional 5.56 machine-gun substitute, NOT an exact Mark 46 recording |

The inspected local source frame /private/tmp/socom-audio-extract.CPc7j5/verify/m14_before.jpg explicitly shows the M14 label. The existing Mark 46 profile references stoner_m63a model data and 5.56 ammunition; this supports a temporary family assignment, not a claim of sound authenticity. The 870 profile specifies 12 Gauge. Web reference searches did not produce usable exact 870 or Mark 46 game recordings; no unverified external audio was imported.

Total: 33 firearm assignments using 29 distinct source WAVs. 29 game/reference-label matches, 2 parent-rifle variants and 2 provisional family substitutions. The four legacy non-firearm records in firearm categories are explicitly audited as exclusions, not silently counted as covered guns: designator, mk_3-a2, air_to_ground_missile, exploding_fuel. Their buy-menu classification is not changed in this audio pass.

The extraction archive remains immutable and is not the runtime bank. Unused launcher/throwable events do not become firearm audio. The two provisional mappings remain clearly marked in JSON so exact replacements are simple and reviewable. Listening/mix approval remains separate from waveform and event tests. No new per-shot disk reads or runtime owner.

## Verification

- Godot 4.7.1 import: M14 WAV imported; no script/parser errors.
- weapon_sound_bank_regression: PASS, matches=33, failures=0. Checks all selectable firearm IDs, 29 distinct WAV paths, source hashes/events, exactly two provisional substitutes, cached resource reuse, and canonical/multiplayer event selection.
- feature_contract_regression: PASS, all 54 feature contracts.
- hit_feedback_performance_regression: PASS, cached audio and 256-hit checks.
- grenade_acoustic_audio_regression: PASS, unchanged frag/flash layers and acoustic policy.
- Quick integration gate: BLOCKED with `FAIL: this is codex/render-deployment; canonical integration is main`. Branch and unrelated dirty work preserved. No full integration or promotion claimed.
- Import emitted existing duplicate m16a2 scene UID and SubMachineGun filename-case warnings, macOS certificate-store error, and restricted editor-settings/ADB errors. These do not fail the focused runtime checks, but are not represented as fixed.
- Final subjective listening/mix review and exact 870/Mark 46 source recordings remain pending. This source pass does not rebuild or publish the browser ZIP.

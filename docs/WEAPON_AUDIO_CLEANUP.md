# Transient-preserving weapon cleanup

## Translation card

- Player intent: Keep the approved weapon character but reduce the impression of a recording playing inside the game.
- Acceptance: Preserve the shot attack PCM exactly, remove excess pre-shot lead-in, reduce low-level source ambience/tail without clipping, and route the selected files through the existing acoustic owner in training and multiplayer.
- Owner: Offline cleanup tool authors derivatives; LabLeakAudioEngine selects the saved bank at startup. AcousticPropagation remains the only runtime spatial audio owner.
- Must not change: Original 53 extracted clips, weapon identity assignments, suppressed/loud relative attack levels, gameplay cadence/damage/recoil, animation or networking authority. No added per-shot processing or global echo effect.
- Proof: Deterministic offline PCM check; all 33 mappings and 29 derivatives; canonical/multiplayer sound regression; acoustic routing regression separately; feature contract gate.

## Method and limits

This is conservative DSP, not a trained AI enhancement model. Speech enhancers such as DeepFilterNet explicitly target speech and can treat a gunshot as unwanted noise, so that candidate is REJECTED for these assets. See https://github.com/Rikorose/DeepFilterNet . Audacity likewise recommends restrained noise reduction to avoid metallic artifacts: https://www.audacityteam.org/manual/effects/noise-removal-and-repair/ .

The approved source WAVs stay untouched. A shared offline profile controls a short-time spectral noise estimate from the clip lead-in, bounded attenuation, smooth late-tail reduction, and removal of excess lead-in. The entire first 100ms after detected onset remains bit-for-bit source PCM; no compressor, normalizer, generated replacement, voice model, pitch shift, or attack EQ. This cannot reconstruct detail already lost to YouTube encoding or fully unmix reverberation baked into the shot itself.

Derivatives are separately named in assets/audio/weapons/socom2_cleaned. The bank retains each original stream/hash and adds cleaned_stream/cleaned_sha256. use_cleaned_streams selects derivatives at scene startup, with original fallback if a derivative is absent. Set it false and restart to restore approved raw recordings. No runtime DSP cost or second audio owner.

Processing is deterministic and local; no clips are uploaded to a third-party service. The profile, tool and manifest retain source provenance. Listen to the provided original/cleaned audition pairs before calling the result subjectively superior.

## Validation

- Initial build safely stopped with `AssertionError: cannot safely identify onset` on 12 Gauge Pump before writing any derivative. Inspection showed five source cuts already contain high-energy signal at the start. They now preserve the full lead and bypass spectral subtraction; quiet-leading clips trim 24–56ms. This policy lives in maximum_noise_to_peak_ratio and is regression-visible in the manifest. A subsequent documentation-context patch failed atomically and was reapplied with the correct scope.
- Offline deterministic build/check: PASS, 29 derivatives, source hashes unchanged, no clipped samples, attack PCM identical. Most long clips' final tail is 3dB lower (552 3.7dB). Short suppressed clips' measured final sample is already silent; 0dB there is not claimed as a reduction.
- Godot 4.7.1 weapon_audio_cleanup_regression: PASS29. Derivatives use lossless 16-bit mono PCM imports; loaded runtime attack bytes match original PCM exactly. This avoids an additional QOA encoding step. See https://docs.godotengine.org/en/latest/classes/class_audiostreamwav.html for format/data semantics; verified against the installed engine rather than assuming every latest-doc API exists.
- weapon_sound_bank_regression: PASS33, both canonical training and multiplayer select the cleaned cache. Original paths/hashes and the bank switch remain available.
- acoustic_recorded_weapon_route_probe: PASS33 clear shots, real wall/doorway physics and actual playback buses. Separate routing fixes are documented in WEAPON_ACOUSTIC_ROUTING.md; no extra reverb layer or mix-preset change.
- feature_contract_regression: PASS57 across combined audio and pistol idle work.
- Quick integration: blocked with `FAIL: this is codex/render-deployment; canonical integration is main`. Branch unchanged. No browser ZIP rebuild or publication.
- Import emits existing macOS certificate/editor-settings/ADB restrictions, duplicate m16a2 UID and SubMachineGun asset-case warnings. No new script/parser errors. Initial bundled Python lacked SciPy; processing used the existing extraction environment (NumPy2.0.2/SciPy1.13.1), with no dependency install or upload.
- Subjective superiority is not claimed from PCM tests. Audition pairs in artifacts/audio play original then cleaned. Baked source reverberation and compression cannot be perfectly reconstructed by this process.

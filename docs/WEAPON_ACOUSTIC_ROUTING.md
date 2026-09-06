# Weapon acoustic routing repair

## Translation card

1. Player intent: Weapon sounds respond to clear space, walls, and doors in the actual game, without treating every shot as an indoor recording.
2. Acceptance rule: All 33 imported firearm assignments enter a direct route with clear line of sight; a same-zone solid wall uses muffled transmission; an authored open doorway uses a real portal path; closing it returns to blocked transmission.
3. System owner: `AcousticPropagationEngine`, using `AcousticPropagationSolver`; `LabLeakAudioEngine` only supplies the selected source and optional debug override.
4. Must not change: Weapon sample identity, audio cleanup, gun timing/damage, networking authority, camera, movement, animation, acoustic mix values, suppression, collision exclusions, and voice limits.
5. Focused proof: `tools/acoustic_recorded_weapon_route_probe.gd`, the existing acoustic and grenade regressions, the sound-bank consumer regression, and the feature-contract gate. This repairs routing; final auditory preference needs listening.

## Baseline and delta

The real gunshot path supplied `direct_clear: false` for every ordinary shot. The engine correctly treats a present key as an explicit override, so its physics line-of-sight result could never select direct playback. The solver also considered two positions in the same zone a completed portal path with zero actual portals. Together, all 33 clear firearm shots entered the 7200 Hz portal/reverb bus, and an outdoor wall did not apply wall transmission.

Baseline runtime probe: 36 failed assertions, including all 33 clear shots, blocked wall filtering, and collision exclusion recovery. The existing solver-only regression passed because it supplied `direct_clear = true` directly. Its pass did not prove the weapon producer contract.

Decision: **MERGE** two corrections into existing owners. Omit the gunshot override when normal physics routing is wanted; preserve explicit `force_direct = true`. Reject zero-hop same-zone pseudo-portals, so obstruction falls back to the existing blocked route. Leave all bus/reverb settings unchanged. A same-zone obstacle has no authored alternative path in this zone graph; it is conservatively muffled instead of inventing a route around it.

Scores, current -> candidate (0–5): correctness 1 -> 4; ownership clarity 5 -> 5; canonical runtime parity 3 -> 5; editor usability 4 -> 4; performance 5 -> 5; regression coverage 2 -> 5. Evidence is in the source/solver and runtime probe named above. The candidate is still a bounded portal approximation, not wave simulation, geometry-traced reflections, or automatic room reconstruction.

## Existing chain retained

- Canonical accepted shot: `MainWeaponRuntime.on_authoritative_shot` -> `LabLeakAudioEngine.play_gunshot`.
- Replicated accepted shot: `SocomShotPresentation.present_shot` -> the same audio source selector.
- Shared `config/weapon_sound_bank.json` chooses cached source audio.
- `AcousticPropagationEngine.play_event` checks range/physics/zones, calls the solver, and assigns a pooled `AudioStreamPlayer3D` to the direct/portal/material-blocked bus.
- Sound Lab saves `config/acoustic_propagation.json`; training and multiplayer configure zones/portals from the active map document.

Current budgets remain 24 acoustic voices, 10 simultaneous weapon voices, 14 new events per frame, 220 m weapon range, 343 m/s delay, and at most six portal hops. Direct gunfire retains its existing early-reflection bus; no additional reverb is introduced here. Uploaded video ambience is part of the source and is a separate offline-cleanup concern.

## Known scope limits

Portal routing needs authored map zone/door metadata (or the existing limited grouped-floor/roof inference). The solver tracks one portal route, not multiple reflected/diffracted arrivals. Spatial attenuation uses the emitted source/last portal location; full-path delay is modeled, but the entire portal path is not separately applied to amplitude attenuation. Shared reverb settings are not unique room impulse responses. These pre-existing limits are not changed by this repair.

Official Godot 4.7 references consulted: [AudioStreamPlayer3D](https://docs.godotengine.org/en/4.7/classes/class_audiostreamplayer3d.html), [AudioEffectReverb](https://docs.godotengine.org/en/4.7/classes/class_audioeffectreverb.html), [PhysicsDirectSpaceState3D](https://docs.godotengine.org/en/4.7/classes/class_physicsdirectspacestate3d.html).

## Verified result (2026-09-05)

- `acoustic_recorded_weapon_route_probe.gd`: PASS, all 33 clear firearm routes direct; concrete wall blocked at 1100 Hz / -16 dB; true one-hop doorway at 31.2 ms versus the 23.3 ms direct route; closing the door blocks it. Actual pooled playback reaches the direct, concrete-blocked, and portal buses. Range culling, force-direct, exclusions, and voice limits pass.
- `acoustic_propagation_regression.gd`: PASS.
- `grenade_acoustic_audio_regression.gd`: PASS.
- `weapon_sound_bank_regression.gd`: PASS, all 33 assignments through canonical and replicated shot consumers.
- `feature_contract_regression.gd`: PASS, 56 contracts at this checkpoint (includes concurrent pistol-family contract).

The diagnostic initially retained ten playing audio resources at exit; explicitly stopping and clearing its pooled voices resolved that teardown warning. Final focused runs retain only the existing restricted macOS certificate warning. This does not prevent acoustic assertions. These checks validate real physics routes and the actual playback buses, not subjective sound quality, a browser export, or real-internet multiplayer listening. No source clips, mixer values, browser ZIP, or deployed build were changed by this routing repair.

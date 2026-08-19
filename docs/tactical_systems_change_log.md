# Tactical systems change log

## 2026-08-19 — Initial tactical and foley foundation

- Added server-authoritative grenade base, smoke, flashbang, frag and throw modes.
- Added shared smoke transmittance service and local smoke/flash screen effects.
- Added procedural 3D tactical foley and animation event dispatcher.
- Added the shared `config/audio_animation_events.json` authoring contract.
- Added Sound Engine Lab and Tactical Grenade Lab to the canonical Studio.
- Added focused regression tests and registered them in the integration manifest.
- Integrated foley with every rendered operator. Animation remains visual only.
- Preserved the existing camera, movement, reticle and weapon authority boundaries.

### Verification baseline

- Script and scene load validation: pass.
- Tactical grenade math: pass.
- Foley profile validation: pass.
- Integration manifest: pass.
- Multiplayer slice: pass.
- Canonical main scene smoke test: pass.
- Sound and grenade lab smoke tests: pass.
- Existing animation regression still reports its prior jump-up/jump-down selection mismatch.
- Camera shell gate needs its legacy direct-scene launch repaired; it starts the launcher and records zero audit frames.

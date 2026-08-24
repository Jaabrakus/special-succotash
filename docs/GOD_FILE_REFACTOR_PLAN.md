# God-file refactor plan

This plan reduces oversized production scripts without changing verified game
behavior. Each extraction uses the existing public contract, runs focused
regressions, and lowers the matching ceiling in
`tools/god_file_budget_regression.gd`.

## Rules

1. Preserve `main.tscn`, the canonical PS1 operator, saved profiles, and input.
2. Move one responsibility per change. Do not rewrite a working subsystem.
3. Keep gameplay authority outside Labs. Labs edit shared profiles and preview
   the same contracts that gameplay consumes.
4. Keep new components at 500 lines or fewer. Prefer 200 to 350 lines.
5. Record failing baseline tests before extraction. Require no new failures.
6. Run the focused regression after each extraction. Run the quick integration
   gate at checkpoint boundaries.
7. Lower the old file's budget after every verified reduction.

## Priority queue

### 1. Gunsmith — `gun_calibration_lab.gd`

Initial size: 6,658 lines. Target: coordinator below 500 lines.

Completed checkpoint 2026-08-24: the coordinator is 458 lines, down from
6,658. Every Gunsmith component is below 500 lines; the largest is 427. The
budget regression now enforces 500 lines for both the coordinator and every
script under `scripts/labs/gunsmith/`. Full animation-catalog, save/hitbox UI,
eye-line, Aim-Idle weapon visibility, and weapon-fire regressions cover the
split. The separate full-project budget can still report unrelated parallel
work that exceeds its own ceiling.

- [x] Extract composure and hurtbox panel construction.
- [x] Extract stateless gizmo mesh construction.
- [x] Extract frame-editor control construction and presentation refresh.
- [x] Extract fire/reticle calibration panel construction.
- [x] Extract the persistent save/play/status action footer.
- [x] Extract the Studio shell and weapon-setup view.
- [x] Extract rig-and-hands panel construction.
- [x] Extract Lab input routing for camera, gizmos, sockets, and frame controls.
- [x] Extract the ordered per-frame preview scheduler.
- [x] Extract 3D gizmo picking and drag interaction.
- [x] Extract weapon preview loading, materials, and attachment setup.
- [x] Extract animation preview and frame-editor coordination.
- [x] Extract saved-profile loading and fire-control refresh.
- [x] Extract profile validation and save coordination.
- [x] Extract debug-line and marker presentation.
- [x] Leave one coordinator that wires components and shared contracts.

### 2. Map Lab — `map_creation_lab.gd`

Initial size: 2,845 lines. Target: coordinator below 500 lines.

- [ ] Extract document and selection controller.
- [ ] Extract object transform/gizmo controller.
- [ ] Extract environment, lighting, and ambience panel.
- [ ] Extract demolition and spawn validation panel.
- [ ] Extract map save/load/export coordinator.
- [ ] Extract training-dummy authoring.

### 3. Map runtime — `socom_map_runtime.gd`

Initial size: 1,387 lines. Target: runtime coordinator below 500 lines.

- [ ] Extract geometry/material instantiation.
- [ ] Extract gameplay markers, borders, and objectives.
- [ ] Extract environment and ambience application.
- [ ] Extract runtime validation and diagnostics.

### 4. Character and animation scripts

- [ ] Split `operator_asset_runtime.gd` into asset loading, skeleton contract,
      and animation-library assembly.
- [ ] Split `operator_locomotion_blend_tree.gd` into selection, transitions,
      and playback synchronization.
- [ ] Split `operator_posture_layer.gd` into posture profile, aim distribution,
      and bounded procedural application.
- [ ] Split `player_controller.gd` into input intent, movement simulation, and
      gameplay-state coordination without changing authority.
- [ ] Reduce remaining Animation Studio files to focused view/controller/model
      components.

### 5. Camera and combat presentation

- [ ] Split `socom_camera.gd` into intent, composition, and presentation wiring.
- [ ] Split `camera_recovery_solver.gd` into recovery state and geometry queries.
- [ ] Split `socom_animated_hurtbox_rig.gd` into profile binding, bone following,
      and debug presentation.

### 6. Grenade, audio, networking, and support Labs

- [ ] Split `main_grenade_runtime.gd` into inventory/action, trajectory, and
      presentation coordination.
- [ ] Split `acoustic_propagation_engine.gd` into propagation, voice budgeting,
      and environment sampling.
- [ ] Split `sound_engine_lab.gd`, `keyboard_mapping_lab.gd`, and
      `composure_reticle_lab.gd` into small panel builders and shared models.
- [ ] Keep every multiplayer authority component at or below its existing
      500-line budget.

## Verification matrix

| Area | Required checks |
| --- | --- |
| Gunsmith | hitbox UI, persistence parity, animation catalog, eye-line, Studio navigation |
| Weapon/character | operator animation, weapon pose, reload handoff, dive attachment |
| Map | map document, map Lab, playable map load, borders/objectives |
| Camera | camera regression, passage/perception, reticle authority |
| Grenades | profile, trajectory collision, animation release, multiplayer authority |
| Integration checkpoint | `tools/run_integration_gate.sh quick` |

## Known baseline defects

Before the first Gunsmith extraction on 2026-08-24,
`test_gunsmith_persistence_regression.gd` passed 7 of 9 checks. Its existing
failures were Studio/runtime parity and stance switching that rebases the
weapon in world space. The composure-panel extraction did not change this
baseline.

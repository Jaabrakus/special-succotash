# 1212 selected candidate export

- Player intent: prepare the supplied Uzi-style SMG and pump shotgun as complete, correctly textured game assets for the matching gun families.
- Acceptance: deterministic GLBs preserve source mesh/UV/bone data and one assembled magazine, contain no first-person arms/camera/light/script objects, load in Godot, and render correctly. SMG candidate is unsuppressed to match existing `9mm_sub` presentation. Runtime assignments remain pending the root task's pose/contact gate.
- One system owner: existing `SocomWeaponRigContract`/published visual-rig resolver will consume the future calibrated assets. This export is an offline preparation tool, not a new runtime owner.
- Must not change: original source meshes, existing weapon/model/rig assignments, firearm balance, animation policy, player/camera/network authority, AK/M4 assets, unmatched pistol.
- Focused proof: source/export mesh counts and triangles, material/texture presence, exact selected objects and bones, GLB content inspection, selected Godot import/load, independent native previews.

Bounded files: `tools/blender/export_retro_1212_weapons.py`, inspection-only `tools/retro_1212_asset_regression.gd`, `assets/weapons/retro_1212/`, source-only `1212/.gdignore`, and intake evidence docs. No source `.blend` or `.fbx` is saved/overwritten. The `.gdignore` marker prevents the730MB raw source archive from automatic whole-folder import.

System delta: **MERGE isolated asset candidates**, contingent on their artifact checks; **REJECT enabling a replacement rig before the canonical physical pose/contact gate**. Compared with raw FBX intake (correctness1, ownership3, parity0, editor1, performance1, coverage0), scoped assembled GLBs target correctness4, ownership5, parity0 until bound, editor4, performance4, coverage3 after artifact checks. Evidence will be recorded in `docs/WEAPON_1212_INTAKE_AUDIT.md`; scores do not certify runtime hand alignment or exact manufacturer identities.

## Offline seven-socket calibration extension

- Intent: locate real hand contact surfaces, bore, stock, sights and ejection points on the two prepared candidates before replacing any working weapon.
- Acceptance: draft `GunsLab2VisualRigContract` documents for `9mm_sub` and `870` contain seven finite sockets in meter-scale model/pivot coordinates; native marker-overlay views verify contact landmarks. The GLBs are already meters, +X bore and +Y up, so model rotation is zero and scale is one. Existing per-family handling, support-hand posture, mount and action policy are retained provisionally, not copied from M4 or certified as fitting the new geometry.
- One owner: the existing visual-rig contract. Drafts are offline data only, consumed by an inspection tool, not the canonical runtime resolver.
- Protected: all gameplay/profile pointers, firing/animation/weapon authority, source models, current AK/M4 contacts, balance, player/camera/physics and the parent's pending physical-pose gate.
- Bounded additions: `art_source/retro1212_calibration/`, `tools/retro_1212_socket_review.gd`, optional source-geometry inspection under `/private/tmp`, and this intake evidence. No runtime assignment or publication.
- Focused proof: exact source-bone and mesh-surface landmarks; canonical draft-schema validation; positive +X bore and +Y optic-up; source material/geometry integrity; native side, opposite-side, top and close-up marker views. Character palm/shoulder contacts remain a separate required gate.
- Delta: **MERGE** authored geometry-based offline sockets over family bounding-box templates (correctness 2→4, ownership 5→5, parity 0→0 until bound, editor 2→4, performance 5→5, coverage 1→4). **REJECT** treating this offline calibration as a published or character-fit-certified rig.

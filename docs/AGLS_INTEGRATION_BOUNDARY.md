# SOCOM-141 and AGLS integration boundary

This document is the permanent ownership contract for importing AGLS content
into SOCOM-141. It prevents an imported system from replacing the gameplay feel
or multiplayer authority that SOCOM-141 already owns.

The integration goal is:

> Use AGLS for character content, authored animation, traversal references, and
> world interactions. Keep SOCOM-141 as the only owner of camera, aim, gunplay,
> hit resolution, damage, and multiplayer truth.

The machine-readable implementation backlog is
`res://config/agls_player_framework_port.json`. Its target is the complete AGLS
player framework: ground locomotion, stance, jump and landing, roll and dive,
mantle and vault, climbing, ladders, rope, zipline, swimming, narrow ledges,
equipment, reload, recoil presentation, pickups, grenades, wheel and valve
interactions, and the workbench. A module marked `assets_ready_logic_pending`
has imported presentation content, not finished gameplay.

## Protected SOCOM-141 systems

The following systems stay in SOCOM-141. An AGLS import may consume their state
for presentation, but it must not replace them or create a second owner.

| System | SOCOM-141 owner | Required boundary |
| --- | --- | --- |
| Camera framing and collision | `scripts/camera/socom_camera.gd` | AGLS animation may not rotate or reposition the gameplay camera. |
| Mouse/right-stick aim intent | Camera aim resolver and `scripts/network/socom_aim_intent.gd` | There is one yaw, pitch, and convergence target. |
| Reticle, visual kick, and bloom feedback | `scripts/ui/socom_dynamic_reticle.gd` | Visual bounce may not redirect a shot. |
| Weapon input, fire modes, cadence, ammunition, reload, and recoil state | `scripts/weapons/socom_weapon_controller.gd` and shared weapon profiles under `config/weapons/` | Imported weapon logic may not spend ammunition or authorize fire. |
| Weapon sockets and rig data | `scripts/weapons/weapon_rig_contract.gd` | Imported meshes and animations conform to the SOCOM weapon contract. |
| Ballistic trace and dispersion | `scripts/weapons/weapon_ballistics.gd` | AGLS traces, spread formulas, and weapon authority stay disabled. |
| Penetration | `scripts/combat/socom_bullet_penetration.gd` | Material and penetration results use the SOCOM rules. |
| Hurtbox definitions and damage regions | `scripts/combat/socom_hurtbox_profile.gd`, `scripts/combat/socom_animated_hurtbox_rig.gd`, and `scripts/combat/socom_hurtbox_area.gd` | Imported skeleton bones are attachment targets, not damage authority. |
| Anatomical hit selection | `scripts/combat/socom_anatomical_hit_resolver.gd` | Overlapping hurtboxes resolve through the SOCOM resolver. |
| Authoritative muzzle validation | `scripts/network/socom_shot_authority.gd` | A client or animation cannot choose the authoritative muzzle. |
| Server hit and damage result | `scripts/network/socom_multiplayer_combat.gd` and `scripts/network/socom_network_operator.gd` | The server decides accepted shots, hit regions, damage, and elimination. |
| Player movement, stance, and collision | `scripts/player/player_controller.gd` and its `CharacterBody3D` contract | Animation and root motion may not move the authoritative body. |

These ownership rules also apply to labs. Gunsmith and other tools edit shared
profiles. They do not implement a separate runtime weapon, camera, or damage
system.

## Content that AGLS may provide

AGLS may provide these systems after conversion to Godot contracts:

- Native character meshes, skeletons, materials, and authored animations.
- Locomotion and traversal animation assets.
- Reload, equip, fire, inspection, hit-reaction, climbing, swimming, rope, and
  interaction presentation.
- Weapon, prop, workbench, backpack, door, drawer, cabinet, locker, chest,
  valve, and pickup models.
- Interaction concepts for loot, ammunition, backpacks, bandages, buttons,
  containers, and carried objects.
- Data references that help tune animation selection or presentation.

All Unreal C++, Gameplay Ability System code, Blueprint graphs, Actor
Components, and PhysicsAssets are reference implementations. Reimplement the
required behavior with Godot scenes, resources, and GDScript. Do not treat a
binary `.uasset` as portable runtime code.

## Character and animation contract

The native AGLS skeleton may replace the current visual skeleton after its
skinned mesh, rest pose, bone orientation, and animation playback pass visual
inspection. Preserve the raw AGLS rest skeleton as animation truth.

Create one semantic bone map for at least:

- root and pelvis;
- spine, chest, neck, and head;
- left and right clavicle, upper arm, forearm, and hand;
- left and right thigh, calf, foot, and toe.

Use that map for animation, IK, sockets, and hurtbox attachment. Do not hard-code
a second set of gameplay rules for the AGLS bone names.

Authored animation is presentation. It may show locomotion, stance, recoil,
reload, climbing, swimming, or an interaction. It must not:

- move the authoritative `CharacterBody3D` through root motion;
- change stance or collision by itself;
- redirect aim or the authoritative muzzle;
- spend ammunition, apply damage, or confirm a hit;
- decide a traversal result without a Godot gameplay motor.

## Hitbox and damage contract

Keep SOCOM-141's hurtbox shapes, region names, precision-core rules, and damage
flow. When the AGLS skeleton becomes the visible rig, attach each SOCOM hurtbox
to the matching semantic AGLS bone. Do not import Unreal PhysicsAsset bodies as
authoritative Godot hitboxes.

The required shot path is:

`aim intent -> authoritative muzzle -> SOCOM dispersion -> server trace -> SOCOM hurtbox -> damage region -> server damage result`

Animation, hit reactions, blood effects, sound, and UI are consumers of the
confirmed result.

Before accepting the native rig, verify at least head, chest, pelvis, both arms,
and both legs while standing, crouched, prone, moving, aiming, firing, and
reloading. A visible mesh and its hurtboxes must remain aligned throughout the
pose.

## Workbench and survival contract

The audited AGLS content contains a workbench prop and rifle-inspection
presentation. It does not establish a complete weapon-customization backend.
Build the playable workbench in Godot on the existing Gunsmith repositories and
weapon profiles.

The workbench may let a player preview and select permitted attachments or
tuning. It must send a bounded loadout request to the server. The server must
validate ownership, compatibility, and allowed gameplay values. A client may
not directly set damage, fire cadence, ammunition, penetration, or hitbox
multipliers in a competitive session.

AGLS loot, ammunition, backpack, bandage, and container content may be ported as
Godot interactions. Hunger, thirst, temperature, sleep, and fatigue are new
SOCOM-141 features unless their complete source and data contracts are verified
later. Do not describe those systems as already ported from AGLS.

## Forbidden integration patterns

Do not:

- activate an AGLS weapon component beside `socom_weapon_controller.gd`;
- calculate spread, damage, or hit results in an animation state;
- make the temporary visual reticle bounce become the shot direction;
- let an imported camera controller write SOCOM aim intent;
- attach gameplay collision directly to unverified imported bone names;
- allow root motion to compete with `CharacterBody3D`;
- copy Blueprint behavior without a written Godot owner and contract;
- call a model, animation, or UI mock-up a completed gameplay system;
- let a lab save to a profile that `main.tscn` does not load.

## Required port sequence

1. Import and verify the native AGLS skinned mesh, rest skeleton, and animation
   playback.
2. Publish and test the semantic bone map.
3. Attach the existing SOCOM hurtboxes to the semantic bones and run hit-region
   regressions.
4. Connect AGLS animation as a consumer of SOCOM movement, stance, aim, weapon,
   and interaction state.
5. Reimplement selected AGLS interactions in Godot one feature at a time.
6. Build the workbench on the SOCOM Gunsmith and weapon-profile contracts.
7. Add new survival simulations only under separate owners and tests.

## Acceptance checklist

An AGLS integration is not complete until all applicable answers are **yes**:

- Does one SOCOM system still own each gameplay decision?
- Does `main.tscn` load the same shared camera and weapon profiles as the labs?
- Does camera aim still move immediately and preserve the intended framing?
- Do reticle feedback and authoritative dispersion still represent the same
  gameplay state without sharing the temporary visual offset?
- Does the server still validate the muzzle, trace, hit region, and damage?
- Do hurtboxes follow the visible AGLS pose in every supported stance?
- Does animation remain a visual consumer?
- Does the authoritative body move without animation root motion?
- Are workbench and inventory changes validated before they affect gameplay?
- Did the focused camera, weapon, hurtbox, movement, animation, and networking
  regressions pass?

If any answer is **no**, stop the port at that boundary. Fix the existing owner
or define a new explicit contract before continuing.

# SOCOM-141 gameplay-intent dictionary

Use this page when a design note is written in player language. It turns the
note into a small, testable game-development request before code changes.

The executable companion is `docs/GODOT_FEATURE_INTEGRATION_CONTRACT.md`.
Every new feature also needs a machine-checked manifest in
`config/feature_contracts/` and must pass
`tools/feature_contract_regression.gd`.

## Translation card

Every player-visible change starts with these five lines:

1. **Player intent:** What should the player feel or observe?
2. **Acceptance rule:** What exact result proves it works?
3. **System owner:** Which one system owns the behavior?
4. **Must not change:** Which nearby systems stay unchanged?
5. **Proof:** Which focused regression and live check verify it?

Then perform a **system readiness check**:

1. Find the canonical runtime owner and any existing editor tool for the request.
2. If the owner exists, extend it through its shared profile or contract.
3. If the required system does not exist, build one bounded system and connect it
   to the canonical runtime owner.
4. If the required editor tool does not exist, build the tool, make it save the
   shared runtime profile, and connect its Play action to `res://main.tscn`.
5. Prove the complete path: tool or input -> saved contract -> runtime consumer ->
   visible result.

A feature is not complete when it exists only as an isolated script, scene, lab,
or asset. It is complete when the canonical game loads and uses it. Never create
a second camera, movement, animation, weapon, damage, or network authority when
the canonical owner can be extended.

Example:

> Player intent: A three-round burst is one committed pull, not a queue of
> bursts.  
> Acceptance rule: Holding or clicking again during a burst cannot start the
> next burst; release, then a fresh press, starts it.  
> System owner: `SocomWeaponFireModePolicy`.  
> Must not change: Ballistic cadence, damage, camera, animation, and networking.  
> Proof: `tools/weapon_fire_mode_policy_regression.gd` and a live rifle check.

## Common player language

| Player language | Engineering translation | Owner and boundary |
| --- | --- | --- |
| “The gun stays in the hands.” | One equipped-weapon root stays parented to the canonical right-palm mount. The left hand targets the rifle foregrip. No animation may move the weapon root. | Operator rig/weapon attachment. Do not change shot authority. |
| “The blue dot follows the head.” | When the optional aim guide is visible, it follows local camera/head aim only. It must not pull the weapon, arms, torso, collision body, or shot direction. | Camera/reticle presentation. |
| “Keep the shoulders square.” | Apply a bounded presentation posture after the base locomotion pose. Do not use it to rotate the collision body or redirect the camera. | Animation presentation layer. |
| “Movement feels like a joystick.” | Accelerate toward an input direction, decelerate when input ends, preserve momentum through turns, and use an explicit turn-in-place threshold. Never teleport the body transform. | `CharacterBody3D` movement owner. |
| “Use crouch aim for this action.” | Reuse the named authored upper-body action only. Keep lower-body locomotion state-owned; do not create a competing movement path. | Animation-state mapping. |
| “The grenade arc shows where it lands.” | Preview and authoritative throw use the same launch state, collision inputs, and material response. | Grenade trajectory contract. |
| “Wallbang works.” | The server decides material, thickness, exit, remaining damage, and eligible target. The client shows only prediction and presentation. | Server ballistics contract. |
| “Make it like SOCOM 2.” | Treat this as a feel reference, not a specification. First list the observable behavior, game constraints, and acceptance check. | The relevant owned system. |

## Change agreement

Before editing player-facing code, state the translation card in plain words.
List the files and systems affected. If an implementation expands into camera,
movement, weapon authority, animation, or networking beyond that card, stop and
write a new card before continuing.

After editing, report the exact behavior changed, the proof run, and any known
limit. A passing code test does not replace a live visual check for posture,
hands, weapon attachment, or foot contact.

## Hard stops

Do not add a feature on top of any of these conditions:

- A parser or boot error in the affected runtime path.
- A failing focused regression for the changed owner.
- Two systems writing the same gameplay transform or input result.
- An unverified lab save that can overwrite canonical gameplay data.

Fix or isolate the first failing owner before continuing.

## Vocabulary

- **Owner:** The one system allowed to make a gameplay decision.
- **Consumer:** A system that reads the decision for presentation or tooling.
- **Contract:** The data and limits exchanged between an owner and consumer.
- **Acceptance rule:** An observable condition that decides pass or fail.
- **Regression:** A repeatable check that prevents a confirmed bug from returning.
- **Restore point:** A small verified commit that can be safely returned to.

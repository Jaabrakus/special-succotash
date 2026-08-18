# Operator 3D animation reference

These sheets are pose and timing guides for a rigged 3D operator. They are not runtime 2D sprites. The playable deliverable must be a Godot-ready `.glb` containing one humanoid skeleton and skeletal animation clips.

## Sheet index

### `operator_locomotion_sheet_v1.png`

- Row 1: rifle idle breathing
- Row 2: walk-forward cycle
- Row 3: jog-forward cycle
- Row 4: standing turn

### `operator_stealth_stances_sheet_v1.png`

- Row 1: stand to crouch
- Row 2: crouch-walk cycle
- Row 3: stand to prone
- Row 4: prone-crawl cycle

### `operator_combat_sheet_v1.png`

- Row 1: low ready to aimed ready
- Row 2: fire, recoil, and recovery
- Row 3: tactical reload
- Row 4: close-wall weapon tuck

### `operator_traversal_interaction_sheet_v1.png`

- Row 1: low mantle
- Row 2: ladder climb
- Row 3: cautious door interaction
- Row 4: ground-level objective interaction

### `operator_reactions_sheet_v1.png`

- Row 1: light frontal hit and recovery
- Row 2: directional hit and recovery
- Row 3: heavy stagger
- Row 4: non-graphic death fall

### `operator_squad_medical_sheet_v1.png`

- Row 1: halt signal
- Row 2: move signal
- Row 3: rally signal
- Row 4: teammate assessment and revive

### `operator_jump_dive_roll_sheet_v1.png`

- Row 1: controlled jump and landing
- Row 2: forward combat dive into prone
- Row 3: left shoulder roll and kneeling recovery
- Row 4: right shoulder roll and kneeling recovery

## Runtime 3D requirements

- Use one shared 32-45 bone operator skeleton with weapon, muzzle, and hand-IK sockets.
- Export animation clips at 30 fps. Keep idle and locomotion loops seamless.
- Use in-place animation for ordinary networked locomotion; the authoritative character controller owns translation.
- Mantles, dives, rolls, and death falls may contain authored motion curves, but gameplay collision and multiplayer authority must validate and drive their displacement.
- Blend lower-body locomotion separately from upper-body aim, recoil, reload, and weapon obstruction.
- Keep the existing camera/weapon target authoritative. Animation follows the target and never changes shot direction by itself.
- Add animation events for footsteps, takeoff, landing, muzzle flash, magazine release/insertion, mantle contact, revive completion, and return of player control.

## Mobility rules

- Jump is a short deliberate traversal move with landing recovery, not repeatable bunny hopping.
- Dive commits the operator into prone and temporarily limits aim until ground contact.
- Rolls require sufficient lateral input and clearance, preserve collision fairness, and finish in crouch or kneel.
- Prone has enter, idle, directional crawl, aim, fire, reload, turn, and exit variants.
- Heavy equipment and low ceilings may disable or shorten jump, dive, mantle, and roll actions.

## AnimationTree layout

- Root state machine: `STANDING`, `CROUCHED`, `PRONE`, `AIRBORNE`, `DIVE`, `ROLL`, `TRAVERSAL`, `INCAPACITATED`.
- Standing and crouched states use directional `BlendSpace2D` locomotion.
- An upper-body blend layer supplies aim offsets, fire recoil, reloads, squad gestures, and weapon tuck.
- One-shot nodes handle jump, landing, dive, roll, stance transitions, mantle, interactions, hit reactions, and death.


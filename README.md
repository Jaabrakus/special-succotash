# SOCOM-141 Camera Lab — v2.0 restored baseline

A runnable Godot 4 prototype for developing a SOCOM-style independent tactical camera and body/aim relationship.

## Current build: exact pre-enclosed-space v2.0 rollback

This is reconstructed from the recorded v2.0 file changes immediately before
the low-poly/enclosed-space request. It preserves the v1.9 camera placement,
collision, aim authority, and original calibration mannequin. Severe level
compression may widen the lens from 60 to 80 degrees, but does not move the
camera vertically or replace the operator mesh.

The experimental head fade, legal interior lift, smaller collision probe, and
playable low-poly mannequin are absent. The low-poly operator remains only as a
separate concept image under `assets/characters/`.

## Separate low-poly operator concept

- The playable mannequin remains the original v1.9 calibration model.
- An original, unbranded low-poly tactical operator concept is available under
  `assets/characters/` for future art direction only.

## Clean capture toggle

Press `H` to toggle a clean capture view for screenshots and video. It hides
the complete diagnostics and calibration layer while preserving the centered
gameplay reticle. Launching with `--clean-hud` starts in the same clean mode.

An original operator art-direction asset is included at
`assets/characters/socom_141_operator_concept.png`. It is a transparent,
unbranded tactical character concept with a proportionate helmet and readable
third-person silhouette; it is reference art for a future production 3D mesh,
not a copied SOCOM character.

## v1.9: aim-authoritative camera collision

Camera collision and aiming are now strictly separated. Raw mouse yaw/pitch
sets the rendered view immediately in every state; walls cannot damp, redirect,
or retain an older aim angle. Collision solves the current boom ray every frame
and controls only lens distance and vertical placement. It compresses inward
immediately for fairness and smooths only the unobstructed outward release.

The old close-target subject steering, orientation lock, previous-yaw safe hold,
and alternating-frame collision hold are removed. The character remains on a
centerline boom with no movement lead or lateral wall election. Gameplay aim
still originates from raw player intent, while the separate muzzle ray keeps a
wall in front of the rifle authoritative for shot blocking.

The 500-sample moving-interior turn keeps head X between `0.500` and `0.510`
with zero off-screen frames. The deliberately impossible part of the full wall
sweep may spend composition rather than steal aim or expose the far side of a
solid wall.

## v1.8: centered deterministic SOCOM boom

The character and fixed center reticle now share one horizontal centerline in
the preferred shot. The boom has no shoulder displacement or movement
look-room; camera collision never overrides the user's horizontal aim.

Wall collision now behaves as a deterministic classic boom: compress inward
first, release outward more slowly, and use only vertical corrections. The
camera never chooses a lateral escape candidate, eliminating corner-to-corner
jumps and keeping collision response independent from horizontal aim.

Regression results: open head X is `0.500`, moving head X is approximately
`0.506`, and the 730-sample wall sweep stays between `0.492` and `0.506` while
closing from `4.90 m` to `2.99 m`. Collision sweeps complete with zero
off-screen frames while raw yaw/pitch remains authoritative.

## v1.7: hard on-screen subject guard

Every retained collision shot, legal smoothing step, cached fallback, and
relaxed orbit now has to keep the character readable in screen space. A camera
position is no longer accepted merely because its collision volume is legal.
The yaw accumulator is normalized as well, preventing long continuous turns
from carrying stale multi-revolution state into wall selection.

This fixes the recorded interior failure where head X progressed from `0.004`
to `-0.589` and then `-2.667` while the camera displayed only wall and ceiling.
Automated stationary and moving interior turns now complete with zero offscreen
frames; the moving test keeps head X between approximately `0.465` and `0.795`.

## v1.6: restored close boom and independent weapon intent

Wall contact once again spends boom distance quickly, restoring the compact
head-and-shoulders view from the earlier calibration. Radial compression is
fast and independent from the slower world-space orbit and release motion, so
stability no longer fights the SOCOM-style close shot.

Gameplay aim now originates at the player pivot along raw yaw/pitch intent,
rather than from a camera lens displaced by collision. A wall behind or beside
the camera therefore cannot make the hands and rifle point at it. The separate
muzzle-to-target ray remains authoritative: walls in front of the weapon still
block the shot, preserving fair sightlines and preventing wall penetration.

## v1.5: stable close-wall state

Close-wall behavior is now stateful instead of electing and teleporting to an
unrelated discrete orbit every physics frame. The rig favors continuity in
world space, blends the two-meter close aim target, keeps the character locked
near center, and follows the selected camera on a volume-validated spherical
path. A short release blend prevents a one-frame clear cast from popping the
camera back toward its open position.

Camera movement during wall contact is capped at 4.5 m/s. The expensive orbit
search runs on alternating physics frames while the retained solution receives
a fresh safety cast every frame. The automated wall audit measures the complete
turn: the worst one-frame position change is about 0.076 m (down from 0.31 m),
with no geometry hiding or interpolation through walls.

## v1.4: responsive close-camera solve

The v1.3 close-wall composition is preserved without moving the live camera for
every candidate projection. Candidate framing is now calculated directly, the
collision pass reuses its camera shape, and post-collision composition performs
one correction plus one legality validation instead of repeating the full orbit
search three times. The HUD reports solve time and cast count so future camera
changes cannot silently reintroduce the hitch.

The open-space preferred boom is also 0.35 m shorter and 0.15 m lower. This
makes the mannequin read larger—closer to the SOCOM traversal scale—while the
collision shot still compresses independently and the rooftop crane retains its
full look-down authority.

## v1.3: collision-aware SOCOM composition

The collision result now receives its own screen-space framing pass. When a wall
or low ceiling shortens or orbits the boom, the camera raises from that actual
legal position to place the head lower in frame, then validates the corrected
position with a second camera-volume cast. Collision escapes preserve one world
convergence point instead of preserving a rigid camera vector. This lets the
lens slide along a wall or rise while continuing to look toward the same aim
point, retaining a compact low-center character silhouette without consuming
turn input or hiding the local player.

The close-quarters calibration is taken from the reference transition around
10:31–10:36: collision shortens the boom toward a roughly two-meter upper-body
shot, raises the lens enough to keep the view useful, and holds the head around
the lower-middle band rather than allowing the camera to enter the model.

The camera also caches the last body-safe lens position. Collision candidates
inside the player are invalid; if no new legal composed shot exists during a
flush-wall turn, the rig holds that safe lens until a side or higher solution
opens. The automated wall sweep begins from a valid playable shot so it covers
the same transition a player actually makes when turning toward nearby cover.

This changes composition only; walls and ceilings remain fully rendered and
continue to block both the camera and weapon path.

## v1.2: fair sightlines and low-room composition

Camera collision no longer hides any wall, ceiling, or level surface. If the
preferred observer position is obstructed, the solver searches wider horizontal
orbits, shorter booms, and both upward and downward vertical escapes. If none is
available, it accepts the closest physical position rather than revealing space
through the blocker.

The constrained-interior calibration now uses a 64% head line, an 84% torso
guardrail, and a small interior-only view-pitch bias. In the low-room test this
keeps the head near the calibrated line, moves the pelvis below frame, and
preserves useful view in front of the reticle without crossing the ceiling.

Fair-shot rules:

- The center-reticle ray selects the intended world aim point
- A second ray validates the path from the weapon muzzle to that point
- A nearer obstruction becomes the actual shot impact
- Camera collision and rendering never remove gameplay collision
- HUD diagnostics show whether the muzzle path is clear or blocked
- The normal `B` wall test faces along the playable space; the automated sweep
  still includes the deliberately impossible aim-into-wall angles

## v1.1: higher ledge look and stability audit

Downward aim now uses a smooth crane state with an additional mid-angle ledge
lift. The camera rises substantially above the normal traversal shot, moves
forward without crossing the player, and preserves an upper-body crop as pitch
approaches top-down aim.

Audit fixes:

- FOV is updated before screen-space framing, so composition and rendering use
  the same projection in the same frame
- Moderate and extreme downward angles use separate body-height and lens targets
- A smooth crane curve removes hard transitions at the start and end of the state
- A mid-angle ledge lift adds clearance where parapets most often block the view
- Lower-body framing weights fade during downward aim
- Framing movement is no longer incorrectly reported as collision compression
- Camera height, crane amount, ledge lift, and aim collider are visible in the HUD
- Automated 45° and 58° rooftop checks cover moderate and steep downward aim

## v1.0: centered reticle and explicit SOCOM shot states

The aim reticle is permanently fixed at the exact viewport center. The camera
composes the character beneath it, with the head kept close to the horizontal
center instead of treating the reticle as a movable shoulder-camera marker.
Open traversal, confined interiors, flush walls, and steep downward aim now
select distinct shot dimensions before collision is solved.

Implemented:

- Fixed screen-center reticle and camera-center world aim ray
- Near-centered character composition with only a small movement look-room shift
- Tighter open traversal crop that normally excludes the boots
- Shorter, higher-feeling interior upper-body shot
- Scale-preserving rooftop/downward shot that spends the legs before aim authority
- Full mouse orbit retained while the player is flush with a wall
- Single-blocker near-camera cull for physically impossible flush-wall views
- No circular cutout through unrelated floor, ceiling, or level geometry
- Automated open, movement, interior, rooftop, wall, and full wall-turn checks

## v0.9: stable wall view and two-dimensional composition

The camera now treats the SOCOM shot as a two-dimensional composition instead of only a vertical crop. Head X/Y, torso, pelvis and foot guardrails are solved before one authoritative camera-volume collision pass. A blocked wall first searches for a readable legal orbit without changing aim. Its former circular cutout rule is superseded by the v1.0 single-blocker cull.

Implemented:

- Fixed 60-degree FOV during calibration, including walls and interiors
- Camera-sized sphere sweep instead of a point ray
- One authoritative collision result per physics frame
- Legal orbit candidates rejected when they lose the player composition
- Local shader cutout for impossible flush-wall and low-ceiling cases
- Head X/Y and torso-aware composition below-left of the crosshair
- Lower-body crop tightened in open turns and constrained spaces
- Movement look room driven by screen-relative travel direction
- Gameplay aim remains independent from collision and composition

## v0.8: yaw-safe wall cutaway and movement follow (superseded)

Collision no longer changes the user's aim yaw. Under direct back-to-wall pressure, the camera keeps a readable boom and temporarily cuts away only the blocking wall's rendering while its gameplay collision remains active. A stronger shoulder composition places the character below-left of the crosshair, matching the SOCOM reference relationship. Movement now has a small velocity lead so the camera opens space in the travel direction and returns smoothly when movement stops.

Implemented:

- Removed collision-driven view rotation
- Severe-wall render cutaway with physics collision preserved
- Head around 75% screen height under wall pressure, below-left of the crosshair
- Full automated yaw sweep while pressed against a wall
- Velocity-based movement lead with separate acceleration and return responses
- Movement lead is capped so the player cannot drift out of the composition
- Stable head/pelvis/feet crop throughout clear, cutaway and wall-exit transitions

## v0.7: wall-aware escape and turn-stable crop (superseded)

This pass introduced alternate orbit/distance/height searches and controlled FOV relief. Its collision-driven view redirection was removed in v0.8 because camera collision must never consume the user's turning authority.

Implemented:

- Wall-aware orbit/dolly/height escape before accepting severe compression
- Minimum readable boom radius for alternate camera positions
- Controlled tight-space FOV widening from 60° toward 72°
- Additional framing authority during wall escape
- Turn-stable head, pelvis and foot guardrails
- `B` toggles a deterministic back-to-wall pressure test

## v0.6: tighter traversal scale

Mission 3 reference calibration showed that the normal traversal observer was still slightly too distant. The preferred boom is now about nine percent shorter, increasing the player's screen presence while preserving the 60-degree vertical field of view and the adaptive outdoor/interior crop behavior.

## v0.5: adaptive outdoor / interior body framing

The complete Mission 2 reference timeline shows that SOCOM II does not use one permanent lower-body crop. Open traversal often retains the legs, with the boots near or just beyond the lower edge. Walls, corners, ceilings and close aim compress the camera and progressively spend the legs and lower torso. The lab now models that continuous response.

Implemented:

- Head + pelvis + stable ground-level foot-marker framing
- Clear outdoor default shot with legs visible and boots at the frame edge
- Pelvis crop guardrail that avoids camera hunting from gait animation
- Outdoor-only foot guardrail whose influence fades under camera compression
- Terrain-slope relaxation that temporarily reveals a little more lower body
- Tight-space state driven by camera compression and overhead clearance
- Upper-body crop authority for buildings, corridors and severe wall compression
- Smooth state transitions between outdoor tactical and constrained framing
- A final collision legality pass after framing so composition cannot push through ceilings
- Live pelvis/feet targets, crop state, terrain slope and relaxation diagnostics
- `C` toggles the calibration overlay
- `[` and `]` adjust reference-frame opacity
- Reference guides for aim, head, torso and pelvis screen heights
- Optional reference image loaded from `res://reference/reference_frame.png`
- Downward aim authority for rooftops and ledges
- Camera-center world aim ray shared by body and weapon
- Rifle convergence on the camera's world aim point
- Procedural two-bone arm solving that keeps both hands on the rifle grips
- `T` toggles a raised roof/parapet test area
- `I` toggles a constrained interior test bay

## v0.3: rifle + split body aim

The procedural test character is now a bone-like articulated hierarchy instead of a collection of unrelated body parts.

Implemented:

- Pelvis → spine → chest → neck → head hierarchy
- Independent hip/knee leg hierarchy for locomotion
- Rifle-ready upper body
- Procedural rifle with muzzle marker
- Arms held in a weapon-ready pose
- Camera yaw drives upper-torso twist within a hard anatomical limit
- Camera pitch drives chest/rifle pitch separately from the legs
- Head follows residual yaw beyond the chest by a limited amount
- Lower body continues to follow locomotion
- Walking/running leg gait remains active while the rifle stays shouldered
- Camera calibration markers now inherit actual head/chest animation
- Debug HUD displays torso yaw, torso pitch and head residual yaw

This is intentionally a calibration rig, not final character art or final animation.

## Camera system

- Independent camera entity; it is not parented to the player
- Elevated trailing observer position
- Forward-biased tactical viewing cone
- Mouse yaw and pitch
- Screen-space head framing using `Camera3D.unproject_position()`
- World collision ray from player anchor to preferred camera position
- Upward collision escape search
- Bounded vertical, lateral and depth excursion
- Fast obstruction response and slower return
- Yaw-safe render cutaway for otherwise impossible rear-wall camera positions
- Capped movement-direction lead with smooth return
- Debug HUD with FOV, head/torso screen position, excursion and collision state

## Run

1. Install Godot 4.x.
2. Open this folder as a Godot project.
3. Run the project.
4. `WASD` move.
5. `Shift` run.
6. Mouse controls the independent camera/aim direction.
7. `R` resets the camera.
8. `C` toggles the SOCOM reference calibration overlay.
9. `[` and `]` change reference-frame opacity.
10. `T` toggles the rooftop downward-aim test.
11. `I` toggles the interior compression test.
12. `B` toggles the back-to-wall escape test.
13. `Esc` releases the mouse.

Press `T` to move between the ground lab and the roof-edge test. On the roof, aim downward over the parapet. The camera gains limited height/forward authority, the rifle converges on the screen-center world point, and both hands remain attached to their weapon grips.

## Reference calibration

Capture a representative gameplay frame from legally accessible footage, crop it to the same 16:9 viewport, and save it as `reference/reference_frame.png`. Toggle the overlay with `C`, then compare the reference body position with the live head, torso and pelvis guide lines.

The open-space target favors an upper-body tactical portrait while retaining
enough lower-body guardrail data to remain stable over uneven ground:

- aim: about 50% screen height
- head: about 72%
- torso: about 82%
- pelvis: about 99%
- feet: deliberately beyond the lower edge, with a 122% guard

In the interior test, the preselected close shot and ceiling clearance take
authority from the foot guardrail. The legs disappear first; severe confinement
can crop around the upper stomach. If no physical lens position exists because
the player is flush with a surface, only that direct blocker is culled visually;
its gameplay collision remains active.

## What to test now

Stand still and orbit the camera. The feet/pelvis remain tied to the character facing while the chest twists toward camera intent. Push far enough around the character and the torso reaches its yaw limit instead of twisting indefinitely.

Then move sideways while aiming elsewhere. The legs should continue representing locomotion while the rifle/upper body remains biased toward camera aim. This is the relationship we need before adding firing, recoil, crouch/prone, shoulder transitions or production animation.

## Important

All numerical defaults are prototype hypotheses. They are not claims about SOCOM II's original internal camera or animation constants. Use the calibration overlay to replace hypotheses with measurements from selected reference frames.

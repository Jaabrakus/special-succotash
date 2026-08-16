# SOCOM-141 Camera Philosophy

The camera is an independent observer, not a child transform of the player.

## Core composition

- The camera lives above and behind the player.
- The lens primarily looks into the battlefield, not down at the player.
- The player occupies the lower-middle portion of the frame.
- Head and torso should remain readable.
- Open traversal often reveals the legs; the boots may touch or pass the lower edge.
- Lower-body visibility decreases as the available camera volume becomes constrained.
- The center/upper-middle of the view is reserved for forward tactical information.
- Peripheral information matters; avoid a cramped over-the-shoulder composition.

## Camera invariants

The camera may change distance, height, or lateral position, but it should continuously try to preserve:

1. Useful world information in front of the player.
2. A readable head/torso silhouette.
3. Aim direction and screen-space composition.
4. A stable field of view, with controlled widening only under severe confinement.
5. Geometry authority: ordinary camera positions remain legal; exceptional cutaways affect rendering only and never remove gameplay collision.

Input authority is a separate invariant: collision may move or visually protect the camera, but it must never rewrite the player's yaw or pitch intent.

## Adaptive body crop

The player does not have one universal full-body framing target.

- Outdoor tactical framing preserves the head and torso while allowing the legs to remain visible.
- Sloped terrain may reveal a little more lower body so elevation changes remain readable.
- Buildings, ceilings and severe boom compression may deliberately crop below the upper torso.
- Steep downward aim is an exceptional state: the observer moves higher, closer and slightly sideways so the player can aim over a ledge without the body covering the crosshair.

These are camera decisions. Levels and character scripts should not fake them with hard-coded shot changes.

## Aim intent

Raw player yaw/pitch produces a world-space aim point independently of collision. The camera, upper body, rifle and muzzle all consume or display that intent without allowing camera collision to rewrite it.

1. Cast from the player aim pivot along raw yaw/pitch.
2. Project that point into the legal camera and use a bounded soft reticle only when wall parallax requires it.
3. Rotate the torso within anatomical yaw and pitch limits.
4. Aim the rifle directly at the world point.
5. Solve both hands back onto the rifle grips.
6. Trace again from the authoritative muzzle so geometry can block the shot.

The muzzle does not simply fire along an unrelated body-facing vector. Camera intent, animation and weapon convergence must agree.

## Movement follow

Movement should open information in the travel direction without feeling detached from the character.

- Lead slightly along horizontal velocity.
- Cap the lead so the player remains inside the composition band.
- Build lead smoothly during acceleration.
- Return a little faster when movement stops.
- Shift the head target slightly opposite lateral travel so the view opens in the movement direction.
- Do not reinterpret movement lead as aim input or automatic yaw.

## Excursion

Collision is allowed to move the camera away from its preferred pose, but only inside a bounded excursion envelope.

- Distance may compress.
- Height may rise more than it may fall.
- Before severe compression, the camera may search laterally around the player for a legal wall-side view.
- Small wall-side physical escapes are allowed, but they never rotate the user's viewing direction.
- If a direct rear wall makes every readable camera position impossible, cut only a small patch around the blocking surface while retaining gameplay collision; never hide the whole wall.
- Tight spaces may widen the FOV modestly to preserve context; this is relief, not a general zoom effect.
- The camera should not swing wildly around the player.
- Collision response should be quick.
- Return to the preferred pose should be slower and smooth.
- Framing correction must be collision-checked again; composition cannot move the camera back through a ceiling or wall.

## Mental model

The player supplies movement, orientation, stance, and aim intent.
The camera solves its own world transform every frame.

The preferred shot is the target. Collision and framing correction are temporary deviations from that shot.

## Deterministic state boundary

The continuous solver is reported through five stable states: preferred,
compressed, post-solved, perched and release. Obstruction entry may transition
immediately; non-safety transitions require a short dwell. Solver detail is not
gameplay authority and must never be replicated in multiplayer.

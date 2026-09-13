# Building a low-poly tactical shooter — progress update

I've been building a third-person tactical shooter inspired by the old SOCOM days, with a low-poly look and a focus on positioning, gunplay, and readable movement.

The latest work has been on jump animations, weapon handling, crouch/prone bloom, and reload reliability. The HUD floats beside the character, bringing health, ammo, and throwable information into focus when needed, then fading back.

The goal is browser-accessible, server-hosted 32-player tournaments. Before a wider test, the priorities are animation polish, consistent climbing and vaulting, and checking how matches behave over real internet connections.

These screenshots are from the current desktop development build—not a finished release or proof of a full multiplayer session. Still plenty to improve, but I wanted to share where it's at.

What would matter most to you in the next playtest: movement feel, gunplay, or map flow?

## Screenshot captions

- `01-rifle-ready.png`: Current third-person view, training environment, and floating player HUD.
- `04-crouch-detail.png`: Crouched operator, shown with a development capture camera.
- `03-reload.png`: Reload in progress, shown with a development capture camera.

## Internal next-work notes (not part of the post)

1. Visual acceptance: inspect jump launch/air/landing and reload transitions across the weapon families. Normal rendered reload tests pass, but the screenshot-capture regression previously exceeded its rifle-position-step limit; this is not a claim that every transition is polished.
2. Traversal acceptance: test actual crates, rocks, awnings and windows. The current eligibility owner rejects unsuitable geometry; `scripts/traversal/socom_mantle_motor.gd:66` checks `top_point.y - foot.y > reach + 0.001` and surface slope. Verify player expectations against these limits instead of promising every object is climbable.
3. Multiplayer validation: test two remote players first (hit registration, leaning, reload/swap, disconnect/rejoin), then increase concurrency toward 32 and measure server tick/frame time and bandwidth. Full internet/32-player validation has not been established in this session.
4. Release checkpoint: review the accumulated uncommitted work and deletions, make a verified restore point, rebuild the browser ZIP, and test that exact upload for audio, mouse capture and joining.

## Capture provenance

Captured from `res://main.tscn` on 2026-09-12 using Godot 4.7.1 with the existing saved map and assets. The temporary capture script is `/private/tmp/socom_community_capture.gd`. Rifle-ready presentation is invoked for framing; these stills do not demonstrate hit registration. Reload is started through the canonical `_request_weapon_reload` call. No gameplay configuration, lighting, textures or animation assets were changed for these images. No post has been published.

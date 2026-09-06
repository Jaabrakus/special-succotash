# Blue night vision

Player intent: blue night vision with readable dark surfaces rather than a
flat green wash and black edges. Acceptance: dark shades stay distinguishable,
highlights do not hard-clip, N toggles back to normal, HUD and aim stay unchanged.
Owner: existing SocomNightVisionOverlay. Input N -> main gameplay HUD -> overlay
-> shared config/night_vision.json -> screen-reading shader and existing local IR light.
Protected: camera transforms, weapons, animation, networking, normal lighting,
HUD layer 10. No additional per-frame processing or screen copies.
Proof: night_vision_regression.gd, rendered canonical off/on images, contract gate.

REPLACE transfer curve only, MERGE shared visual settings. Current shader adds
0.14 before multiplying by 5.2; black becomes about 0.85 intensity. Hard clipping
also erases bright-surface contrast. Edge alpha reaches 0.92.
Candidate uses a bounded rational gain curve, gamma for shadows, blue tint, and
0.22 maximum edge alpha. Scores current -> candidate: correctness 1 -> 4,
ownership 5 -> 5, parity 4 -> 5, editor usability 2 -> 4, performance 5 -> 5,
coverage 1 -> 4. Evidence: scripts/effects/socom_night_vision_overlay.gd,
scripts/runtime/main_gameplay_hud.gd:182, config/night_vision.json, focused test.
This is stylized blue night vision, not a claim of authentic SOCOM or physical NVG.

Godot screen-reading shader reference:
https://docs.godotengine.org/en/stable/tutorials/shaders/screen-reading_shaders.html

# Hybrid camera proof — 2026-09-13

Unedited native captures from actual main.tscn and the current skinned player.
The native --visual-quick run covers12 stance/pitch views, six real lean states,
entry frames, viewport resizing and actual-map idle. Running and wall/removal
fixtures are covered separately by the full24-row headless main proof.

Fixed74HFOV, constant-radius pitch orbit, existing height framing and physical
collision/trailing. Level boom remains2.8m; no3.1m distance increase was made.
Clear-space lean shifts -.50m/+.56m and returns to0, with unchanged aim input.
This is a deliberate hybrid, not original camera1:1.

main-map-rifle-idle.png is the saved-map spawn. Other captures use a controlled
platform added to the test's canonical main instance. No user map is overwritten.
Body/hand visual acceptance remains partial pending the user's latest screenshot.
Maximum upward prone view still places the character at the bottom edge; a
visible head landmark is not proof that the complete framing looks ideal.

See docs/CAMERA_SCALE_IDLE_UPDATE_20260913.md for files, excerpts, test results,
remaining issues and launch instructions. This folder is ignored by Godot.

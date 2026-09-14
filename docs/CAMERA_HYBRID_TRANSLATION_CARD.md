# Hybrid camera — translation card, 2026-09-13

User choice: “both hybrid”. This supersedes exact ordinary source camera as the
requested default; original scalar math remains available for comparison.

- Intent: keep source scale, animated level-aim framing and lens, with our
  readable pitch framing, collision, trailing and sideways lean-follow.
- Acceptance: source level framing stays unchanged; smooth signed pitch blends
  our existing height correction into the source seed; a saved minimum pivot-
  relative camera height avoids starting the preferred lens below the feet.
  Neither FOV nor aim angles change with lean or pitch. Collision still decides
  the final legal lens position. Left/right/neutral are tested via actual main
  movement commands, not manually assigned lean values.
- Owner: existing SocomCameraRig. Its existing framing solver computes the
  correction; SourceGameplayCamera is a pure saved policy, not another node.
- Protected: CharacterBody movement/collision, animation poses and timing,
  server shots/damage, user processes, original decoded scalar fixtures.
- Proof: saved-policy validation, continuous blend/bounds tests; main stance,
  signed pitch, lean, run, resized viewport and actual-map renders; aim chain
  and obstruction regressions. No claim of full original camera parity.

System delta (0–5: correctness/ownership/main parity/editor/performance/tests):
ordinary source default = 3/5/5/4/5/4, hybrid candidate = 4/5/5/4/4/5.
MERGE: keep the verified source level shot, restore the existing framing solver
only progressively with pitch. Values in `hybrid` are deliberate local tuning,
not decoded source constants. Candidate scores are targets until tests pass.
The older disabled `camera_source_hybrid.json` distance-only trial is unchanged;
it is not an additional camera owner or the new hybrid policy.

Follow-up delta after “something about looks off”: original radius shrinks
toward 14 source units as pitch changes. Fixed FOV does not prevent this physical
pull-in. MERGE a saved hybrid-only constant-radius option; the source reference
function and scalar fixtures remain untouched. Acceptance adds same boom length
around the animated pivot at signed pitch; physical collision may still shorten
it. Existing pitch framing/clearance must be rechecked, especially prone.

Constant-radius first trial exposed head cropping at maximum28degree upward
prone aim with70HFOV. Do not lower the lens through the floor or loosen viewport
assertions to pass. Test an explicitly authored, fixed74HFOV hybrid lens to
provide modest extra peripheral space; source mode retains verified70HFOV.
This is a deliberate hybrid framing change, not original-source parity. It
does not add zoom breathing or change the selected model/collision scale.

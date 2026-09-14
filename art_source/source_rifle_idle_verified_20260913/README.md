# Main source-rifle idle proof — 2026-09-13

Generated with `tools/source_rifle_default_idle_regression.gd` in `main.tscn`.
The selected character is modern_soldier_iso at its saved measured scale.
No original asset was changed or overwritten. This folder is excluded from
Godot import/export by `.gdignore`.

`rifle-idle-v2.json` contains the live main graph, source identity, accepted-shot
latch, physical palm/socket measurements and 40 rear/side image paths.
`rifle-idle-v2-transitions.json` contains per-frame readiness and fire weights.
The three return samples wait for natural latch expiry, halfway readiness and
idle, rather than assuming native render frames have a fixed duration.

`*_ready_api*` is an explicitly separate presentation-API fixture. Main supplies
zero readiness outside accepted firing; these pictures do not claim an extra
player ready input exists. Actual idle/fire/return samples use main forwarding
and real `WeaponController.request_fire()` acceptance.

This demonstrates distinct source default Stand / alert ready / Fire stand
selection on the current retargeted character, not original game mode-timing
or original skinned-mesh parity. Existing support fingers still look claw-like
in ready/fire; sub-millimetre palm-anchor error does not prove correct fingers.
The current weapon/character fitting layers were not replaced in this pass.

Reproduce in a separate native process (does not update any browser ZIP):

```sh
/Users/kiwimango/Applications/Godot-4.7.1.app/Contents/MacOS/Godot --path /Users/kiwimango/socom-141-camera-lab --log-file /private/tmp/rifle-idle-proof.log --script res://tools/source_rifle_default_idle_regression.gd -- --capture --output-prefix=/private/tmp/rifle-idle-recheck
```

See `docs/SOURCE_RIFLE_DEFAULT_IDLE.md` for source mode tags, exact changed key,
test outcomes and remaining limitations.

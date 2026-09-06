# zWeapon recoil and reticle audit — 2026-09-05

Read-only audit; no importer run, weapon values or presentation tuning changed.

## Original data

`reCOM-main/data/s1/common/zrdr/zweapon.rdr:744` (Mark 23 standing):
```
ReticuleKnock ( 20.000000 )
ReticuleKnockReturn ( 60.000000 )
ReticuleKnockMax ( 40.000000 )
```
The M4A1 standing block near line 2499 has 12 / 70 / 45; M60E3 near
line 4050 has 10 / 42 / 50. These are original data units, not a verified
pixel-for-pixel conversion to the current game.

The same file contains stance overrides, TargetDilateUponFire,
TargetDilateUponMovement, TargetConstrict, TargetMin/Max, KnockCount,
KnockEntryStrength and FireRifleKickRate/ReturnRate/BaseDist/RandomDist.
Those rifle fields describe authored kick parameters, not proof that the
current Godot runtime imports or reproduces them.

## Import defect

`tools/import_recom_weapons.py:149`:
```python
stand_match = re.search(r'STANCE_STAND\s*\((.*?)\)', body, re.DOTALL)
```
This stops at the first inner closing parenthesis. Reproduced with an actual
shaped stance string: captured body was ` ReticuleKnock ( 20.000000 `.
It lacks even the closing parenthesis needed by the first field regex; the
remaining fields are absent. Lines 164–166 then fall back to 20 / 40 / 60.
Current Mark 23, M4A1 and M60E3 JSONs all contain that triplet rather than
their distinct original values. Bloom conversion also uses this truncated
stance body. A blanket reimport would overwrite tuned values; do not run it
as a repair without a selective diff and acceptance tests.

## Current consumers

`scripts/weapons/socom_weapon_controller.gd:120` merges saved reticle data.
`scripts/runtime/main_weapon_runtime.gd:98` invokes `dynamic_reticle.notify_shot`.
`scripts/ui/socom_dynamic_reticle.gd:107` caps visual kick:
```gdscript
else minf(
    maximum_shot_kick_pixels,
    shot_kick_pixels * clampf(intensity, 0.25, 2.0)
)
```
It resets each-shot bounce age, adds a capped radial impulse and recovers it.
`_apply_fire_cadence` at line 159 derives bounce duration and return speed from
fire interval, overriding the saved return rate when cadence is supplied.
The shot is resolved before this visual impulse. This is not identical to
functional camera climb. `scripts/camera/socom_camera.gd:312` has a separate
optional functional recoil system with pitch/yaw caps and recovery.

`scripts/weapons/weapon_ballistics.gd:310` selects standing versus crouching
maximum recoil bloom; both solo controller and multiplayer ballistics adapter
load those saved spread fields.

However `scripts/network/socom_multiplayer_hud.gd:378` currently does:
```gdscript
reticle = Label.new()
reticle.text = "+"
```
The multiplayer HUD has no dynamic-reticle shot callback. Training and online
reticle presentation therefore do not currently have parity.

Next repair should separately address balanced stance parsing, reviewed
weapon-specific conversions, and reuse of the same reticle presentation in
multiplayer. Do not silently combine recoil/aim gameplay changes with this
network architecture refactor.

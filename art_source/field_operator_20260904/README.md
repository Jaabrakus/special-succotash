# Original field operator — review candidate

Original low-poly geometry with olive fatigues, fitted plate carrier, equipment,
helmet/headset, faceted face, gloves and boots. Source is reproducible using
`tools/blender/build_field_operator.py` in Blender 5.2.1.

Only the project's existing 41-bone native rest rig is reused. The static review
pose is authored in `author_ready_pose()`. No original trooper mesh vertices,
textures or logos are copied. The
new mesh is skinned and exported at meter scale. This is **not yet a drop-in
gameplay replacement**: socket contact, all stance transitions, deformation and
live animation compatibility remain to be checked before changing the operator
profile. The separate pistol-shaped review prop is nonfunctional.

The character uses one vertex-colored opaque material/surface. The three
separate review-prop pieces add three surfaces and can be removed for gameplay
integration. Gloves have an authored closed grip and are hand-weighted; they
do not have articulated fingers. The rest-height target is 1.7888 meters.

Open `field_operator.blend` to edit; render previews use an aim-ready posture.
The GLB is in `assets/characters/field_operator_20260904/`. The Godot-ready
`field_operator_aim_ready.scn` in the same directory preserves the explicit
`vertex_palette.tres` material and autoplays the static review pose. The direct
Godot 4.7.1 GLTFDocument import retained COLOR_0 but did not enable material
vertex colors; `validate_import.gd` applies the explicit saved material before
packing the Godot scene. It does not modify any gameplay scene or profile.

Verified final asset: 7,388 triangles, 3,990 Blender mesh vertices, one character
surface, 41 unchanged native bone rest matrices, 1.7888m rest-height target,
1,045,184-byte GLB. Three nonfunctional prop pieces add three surfaces.

Godot 4.7.1 import and saved-scene round trip pass: four skinned mesh nodes,
41 bones, four total surfaces, vertex colors enabled, animation present.
Run `Godot --headless --log-file /private/tmp/field-operator-import.log --path .
--script res://art_source/field_operator_20260904/validate_import.gd` to rebuild
and validate the Godot scene from the GLB. Review logs distinguish this limited
import proof from untested runtime deformation and weapon-contact behavior.

System delta: **KEEP** the live character until the candidate passes runtime
contact and deformation checks. Candidate improves editable geometry and visual
detail but has no runtime-parity claim. Protected camera, collision, aim intent,
weapon attachment, damage and networking owners are unchanged.

@tool
extends Resource
## Authored in calibrated weapon metres; edit this shared resource in Godot.
@export var enabled := true
## Experimental: keep off until the base grip passes all posture/transition views.
@export var correction_enabled := false
@export_file("*.scn", "*.tscn", "*.glb", "*.fbx") var expected_model := ""
@export var shape: CapsuleShape3D
@export var local_transform := Transform3D.IDENTITY
@export_range(0.001, 0.015, 0.001) var finger_radius_m := 0.004
@export_range(4, 24, 1) var sweep_steps := 12
@export_range(4, 12, 1) var refinement_steps := 7

func is_valid() -> bool:
	if shape == null or not local_transform.is_finite(): return false
	if not is_finite(shape.radius) or not is_finite(shape.height): return false
	if shape.radius < .001 or shape.height < shape.radius * 2.0: return false
	if shape.radius > .15 or shape.height > 1.0: return false
	if not is_finite(finger_radius_m) or finger_radius_m < .001 or finger_radius_m > .015: return false
	if sweep_steps < 4 or sweep_steps > 24 or refinement_steps < 4 or refinement_steps > 12: return false
	# Shape dimensions carry size. Reject skew/scale rather than silently making
	# a differently sized physics shape and analytic surface.
	return local_transform.basis.is_equal_approx(local_transform.basis.orthonormalized()) \
		and local_transform.basis.determinant() > .99

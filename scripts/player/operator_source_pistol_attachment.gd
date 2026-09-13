extends RefCounted

const SourceAim := preload("res://scripts/player/operator_source_attachment_aim.gd")

## Explicit target-rig adaptation. Not a reconstruction of the original engine's
## aim equation or the detached source pistol helper's unknown parent space.
static func aim_upper_body(pose: Node3D, yaw: float, pitch: float, weight: float,
		target: Vector3, body: Node3D) -> void:
	pose.source_pistol_aim_applied_degrees = SourceAim.apply(pose, yaw, pitch,
		weight, target, body, pose.source_pistol_aim_limit_degrees)

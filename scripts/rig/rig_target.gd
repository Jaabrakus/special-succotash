class_name RigTarget
extends RefCounted

var enabled: bool = false
var transform: Transform3D = Transform3D.IDENTITY
var position_only: bool = false

var weight: float = 1.0

# Body-region authority.
var influence_root: float = 0.0
var influence_pelvis: float = 0.0
var influence_spine: float = 0.0
var influence_chest: float = 0.0
var influence_clavicle: float = 0.0
var influence_arm: float = 0.0
var influence_leg: float = 0.0
var influence_head: float = 0.0


func clear() -> void:
	enabled = false
	transform = Transform3D.IDENTITY
	position_only = false
	weight = 1.0

	influence_root = 0.0
	influence_pelvis = 0.0
	influence_spine = 0.0
	influence_chest = 0.0
	influence_clavicle = 0.0
	influence_arm = 0.0
	influence_leg = 0.0
	influence_head = 0.0

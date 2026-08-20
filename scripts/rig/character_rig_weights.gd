class_name CharacterRigWeights
extends Resource

@export_range(0.0, 1.0) var pelvis_weight: float = 1.0
@export_range(0.0, 1.0) var spine_weight: float = 0.30
@export_range(0.0, 1.0) var chest_weight: float = 0.35

@export_range(0.0, 1.0) var clavicle_weight: float = 0.40

@export_range(0.0, 1.0) var right_arm_weight: float = 1.0
@export_range(0.0, 1.0) var left_arm_weight: float = 1.0

@export_range(0.0, 1.0) var right_leg_weight: float = 1.0
@export_range(0.0, 1.0) var left_leg_weight: float = 1.0

@export_range(0.0, 1.0) var head_weight: float = 0.30

@export var max_spine_yaw_deg: float = 25.0
@export var max_spine_pitch_deg: float = 20.0

@export var max_head_yaw_deg: float = 55.0
@export var max_head_pitch_deg: float = 35.0

@export var max_clavicle_raise_deg: float = 15.0

@export var relaxation_iterations: int = 2

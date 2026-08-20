class_name WeaponRigIntentAdapter
extends Node

@export var rig_solver_path: NodePath
@export var right_grip_path: NodePath
@export var left_grip_path: NodePath
@export var right_elbow_pole_path: NodePath
@export var left_elbow_pole_path: NodePath

var rig_solver: UniversalCharacterRigSolver
var right_grip: Node3D
var left_grip: Node3D
var right_elbow_pole: Node3D
var left_elbow_pole: Node3D


func _ready() -> void:
	rig_solver = get_node_or_null(rig_solver_path) as UniversalCharacterRigSolver
	right_grip = get_node_or_null(right_grip_path) as Node3D
	left_grip = get_node_or_null(left_grip_path) as Node3D
	right_elbow_pole = get_node_or_null(right_elbow_pole_path) as Node3D
	left_elbow_pole = get_node_or_null(left_elbow_pole_path) as Node3D


func submit_weapon_pose() -> void:
	if rig_solver == null:
		return

	var targets := rig_solver.targets

	if right_grip:
		targets.right_hand.enabled = true
		targets.right_hand.transform = right_grip.global_transform
		targets.right_hand.weight = 1.0
		targets.right_hand.influence_arm = 1.0
		targets.right_hand.influence_clavicle = 0.45
		targets.right_hand.influence_chest = 0.20
		targets.right_hand.influence_spine = 0.08

	if left_grip:
		targets.left_hand.enabled = true
		targets.left_hand.transform = left_grip.global_transform
		targets.left_hand.weight = 1.0
		targets.left_hand.influence_arm = 1.0
		targets.left_hand.influence_clavicle = 0.40
		targets.left_hand.influence_chest = 0.15

	if right_elbow_pole:
		targets.right_elbow.enabled = true
		targets.right_elbow.transform = right_elbow_pole.global_transform

	if left_elbow_pole:
		targets.left_elbow.enabled = true
		targets.left_elbow.transform = left_elbow_pole.global_transform

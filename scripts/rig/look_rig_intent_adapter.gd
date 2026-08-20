class_name LookRigIntentAdapter
extends Node

@export var rig_solver_path: NodePath
var rig_solver: UniversalCharacterRigSolver


func _ready() -> void:
	rig_solver = get_node_or_null(rig_solver_path) as UniversalCharacterRigSolver


func submit_look_target(world_position: Vector3) -> void:
	if rig_solver == null:
		return
	rig_solver.targets.look_enabled = true
	rig_solver.targets.look_target_world = world_position

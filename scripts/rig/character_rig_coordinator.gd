class_name CharacterRigCoordinator
extends Node

@export var rig_solver_path: NodePath
@export var weapon_adapter_path: NodePath
@export var look_adapter_path: NodePath

var rig_solver: UniversalCharacterRigSolver
var weapon_adapter: WeaponRigIntentAdapter
var look_adapter: LookRigIntentAdapter


func _ready() -> void:
	rig_solver = get_node_or_null(rig_solver_path) as UniversalCharacterRigSolver
	weapon_adapter = get_node_or_null(weapon_adapter_path) as WeaponRigIntentAdapter
	look_adapter = get_node_or_null(look_adapter_path) as LookRigIntentAdapter


func _process(delta: float) -> void:
	if rig_solver == null:
		return

	# Start fresh from current animation pose.
	rig_solver.targets.clear_frame_intent()

	# Systems submit intent.
	if weapon_adapter:
		weapon_adapter.submit_weapon_pose()

	# Single authoritative owner writes final skeleton.
	rig_solver.solve(delta)

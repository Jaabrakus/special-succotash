class_name SocomOperatorPosePipeline
extends Node3D

## Visible Godot node hierarchy for deterministic character-pose evaluation.
## Gameplay aim and shots stay outside this presentation-only pipeline.

const STAGE_ORDER: Array[StringName] = [
	&"10_BaseAnimation",
	&"20_PostureAndShoulderFrame",
	&"30_FireTorsoShoulderArms",
	&"40_WeaponMuzzleAlignment",
	&"50_HandContact",
	&"60_FootGrounding",
	&"70_PresentationEvents",
]

var stages: Dictionary = {}


func build() -> void:
	if not stages.is_empty():
		return
	for stage_name: StringName in STAGE_ORDER:
		var stage := Node3D.new()
		stage.name = stage_name
		add_child(stage)
		stages[stage_name] = stage


func attach_component(stage_name: StringName, component: Node) -> void:
	build()
	var stage := stages.get(stage_name) as Node
	if stage == null or component == null:
		return
	stage.add_child(component)


func ordered_stage_names() -> Array[StringName]:
	return STAGE_ORDER.duplicate()


func get_stage(stage_name: StringName) -> Node:
	return stages.get(stage_name) as Node


func get_debug_state(fire_active: bool) -> Dictionary:
	return {
		"node_path": get_path(),
		"ordered_stages": ordered_stage_names(),
		"active_upper_body_stage": (
			&"30_FireTorsoShoulderArms" if fire_active else &"10_BaseAnimation"
		),
		"muzzle_alignment_after_fire": (
			STAGE_ORDER.find(&"40_WeaponMuzzleAlignment")
			> STAGE_ORDER.find(&"30_FireTorsoShoulderArms")
		),
	}

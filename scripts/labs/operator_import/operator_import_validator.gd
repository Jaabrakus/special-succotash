class_name SocomOperatorImportValidator
extends RefCounted

## Read-only character preflight. It maps foreign artist bone names to stable
## operator roles without changing the imported scene or the playable operator.

const Normalizer := preload("res://scripts/characters/operator_model_normalizer.gd")

const REQUIRED_BONE_ROLES: Array[String] = [
	"hips", "spine", "chest", "neck", "head",
	"left_shoulder", "left_upper_arm", "left_lower_arm", "left_hand",
	"right_shoulder", "right_upper_arm", "right_lower_arm", "right_hand",
	"left_upper_leg", "left_lower_leg", "left_foot", "left_toe",
	"right_upper_leg", "right_lower_leg", "right_foot", "right_toe",
]

const BONE_ALIASES := {
	"hips": ["mixamorig_Hips", "mixamorig:Hips", "pelvis", "Hips"],
	"spine": ["mixamorig_Spine", "mixamorig:Spine", "spine_0", "Spine"],
	"chest": ["mixamorig_Spine2", "mixamorig:Spine2", "spine_3", "Chest"],
	"neck": ["mixamorig_Neck", "mixamorig:Neck", "neck_0", "Neck"],
	"head": ["mixamorig_Head", "mixamorig:Head", "head_0", "Head"],
	"left_shoulder": ["mixamorig_LeftShoulder", "mixamorig:LeftShoulder", "clavicle_L", "LeftShoulder"],
	"left_upper_arm": ["mixamorig_LeftArm", "mixamorig:LeftArm", "arm_upper_L", "LeftArm"],
	"left_lower_arm": ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "arm_lower_L", "LeftForeArm"],
	"left_hand": ["mixamorig_LeftHand", "mixamorig:LeftHand", "hand_L", "LeftHand"],
	"right_shoulder": ["mixamorig_RightShoulder", "mixamorig:RightShoulder", "clavicle_R", "RightShoulder"],
	"right_upper_arm": ["mixamorig_RightArm", "mixamorig:RightArm", "arm_upper_R", "RightArm"],
	"right_lower_arm": ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "arm_lower_R", "RightForeArm"],
	"right_hand": ["mixamorig_RightHand", "mixamorig:RightHand", "hand_R", "RightHand"],
	"left_upper_leg": ["mixamorig_LeftUpLeg", "mixamorig:LeftUpLeg", "leg_upper_L", "LeftUpLeg"],
	"left_lower_leg": ["mixamorig_LeftLeg", "mixamorig:LeftLeg", "leg_lower_L", "LeftLeg"],
	"left_foot": ["mixamorig_LeftFoot", "mixamorig:LeftFoot", "ankle_L", "LeftFoot"],
	"left_toe": ["mixamorig_LeftToeBase", "mixamorig:LeftToeBase", "ball_L", "LeftToeBase"],
	"right_upper_leg": ["mixamorig_RightUpLeg", "mixamorig:RightUpLeg", "leg_upper_R", "RightUpLeg"],
	"right_lower_leg": ["mixamorig_RightLeg", "mixamorig:RightLeg", "leg_lower_R", "RightLeg"],
	"right_foot": ["mixamorig_RightFoot", "mixamorig:RightFoot", "ankle_R", "RightFoot"],
	"right_toe": ["mixamorig_RightToeBase", "mixamorig:RightToeBase", "ball_R", "RightToeBase"],
}


static func validate(model_path: String) -> Dictionary:
	var report := _empty_report(model_path)
	if model_path.is_empty() or not ResourceLoader.exists(model_path):
		report.errors.append("The model is not imported or the path does not exist.")
		return report
	var packed := load(model_path) as PackedScene
	if packed == null:
		report.errors.append("Godot could not load the model as a scene.")
		return report
	var root := packed.instantiate()
	var skeletons: Array[Skeleton3D] = []
	var meshes: Array[MeshInstance3D] = []
	var animation_players: Array[AnimationPlayer] = []
	_collect_nodes(root, skeletons, meshes, animation_players)
	var skeleton := _largest_skeleton(skeletons)
	if skeleton == null:
		report.errors.append("No Skeleton3D was found.")
	else:
		report.skeleton_name = String(skeleton.name)
		report.bone_count = skeleton.get_bone_count()
		report.bone_map = _build_bone_map(skeleton)
		for role in REQUIRED_BONE_ROLES:
			if not report.bone_map.has(role):
				report.missing_bone_roles.append(role)
		if not report.missing_bone_roles.is_empty():
			report.errors.append("Missing operator bone roles: %s" % ", ".join(report.missing_bone_roles))
		report.requires_canonical_conversion = not skeleton.find_bone("mixamorig_Hips") >= 0
		if root is Node3D and report.missing_bone_roles.is_empty():
			report.normalization = Normalizer.measure(root as Node3D, report.bone_map)

	for mesh_instance in meshes:
		if mesh_instance.mesh == null:
			continue
		report.mesh_count += 1
		if mesh_instance.skin != null:
			report.skinned_mesh_count += 1
		for surface in mesh_instance.mesh.get_surface_count():
			var material := mesh_instance.get_active_material(surface)
			var slot := {
				"mesh": String(mesh_instance.name),
				"surface": surface,
				"material": material.resource_name if material != null else "",
				"albedo_texture": "",
			}
			if material is StandardMaterial3D:
				var texture := (material as StandardMaterial3D).albedo_texture
				if texture != null:
					slot.albedo_texture = texture.resource_path
			report.material_slots.append(slot)

	for player in animation_players:
		for library_name in player.get_animation_library_list():
			report.animation_count += player.get_animation_library(library_name).get_animation_list().size()
	if report.mesh_count == 0:
		report.errors.append("No MeshInstance3D was found.")
	if report.skinned_mesh_count == 0:
		report.errors.append("No mesh is skinned to a skeleton.")
	if root is Node3D:
		report.preview_height_m = Normalizer.model_bounds(root as Node3D).size.y
	if report.material_slots.is_empty():
		report.warnings.append("The model has no material slots for texture overrides.")
	elif _untextured_slot_count(report.material_slots) > 0:
		report.warnings.append("Some material slots have no albedo texture. Assign them before promotion.")
	if float(report.preview_height_m) < 0.5 or float(report.preview_height_m) > 3.0:
		report.warnings.append("Source units differ from metres; normalized operator space will correct them.")
	report.compatible = report.errors.is_empty()
	root.free()
	return report


static func _empty_report(model_path: String) -> Dictionary:
	return {
		"model_path": model_path,
		"compatible": false,
		"skeleton_name": "",
		"bone_count": 0,
		"bone_map": {},
		"missing_bone_roles": [],
		"mesh_count": 0,
		"skinned_mesh_count": 0,
		"material_slots": [],
		"animation_count": 0,
		"preview_height_m": 0.0,
		"requires_canonical_conversion": true,
		"normalization": {},
		"warnings": [],
		"errors": [],
	}


static func _collect_nodes(
	node: Node,
	skeletons: Array[Skeleton3D],
	meshes: Array[MeshInstance3D],
	animation_players: Array[AnimationPlayer]
) -> void:
	if node is Skeleton3D:
		skeletons.append(node as Skeleton3D)
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	if node is AnimationPlayer:
		animation_players.append(node as AnimationPlayer)
	for child in node.get_children():
		_collect_nodes(child, skeletons, meshes, animation_players)


static func _largest_skeleton(skeletons: Array[Skeleton3D]) -> Skeleton3D:
	var result: Skeleton3D
	for skeleton in skeletons:
		if result == null or skeleton.get_bone_count() > result.get_bone_count():
			result = skeleton
	return result


static func _build_bone_map(skeleton: Skeleton3D) -> Dictionary:
	var result := {}
	for role in REQUIRED_BONE_ROLES:
		for candidate: String in BONE_ALIASES[role]:
			if skeleton.find_bone(candidate) >= 0:
				result[role] = candidate
				break
	return result


static func _untextured_slot_count(slots: Array) -> int:
	var count := 0
	for slot: Dictionary in slots:
		if String(slot.get("albedo_texture", "")).is_empty():
			count += 1
	return count

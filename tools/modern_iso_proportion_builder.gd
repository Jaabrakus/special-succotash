extends RefCounted

const ALIASES := {
	"hips":"Hips", "spinelo":"Spine", "spinehi":"Spine2", "neck":"Neck", "head":"Head",
	"lscap":"LeftShoulder", "lbicep":"LeftArm", "lforearm":"LeftForeArm", "lhand":"LeftHand",
	"rscap":"RightShoulder", "rbicep":"RightArm", "rforearm":"RightForeArm", "rhand":"RightHand",
	"lthigh":"LeftUpLeg", "lcalf":"LeftLeg", "lfoot":"LeftFoot", "ltoe":"LeftToeBase",
	"rthigh":"RightUpLeg", "rcalf":"RightLeg", "rfoot":"RightFoot", "rtoe":"RightToeBase"
}

static func apply(rig: Skeleton3D, source_path: String) -> Dictionary:
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	var source_globals := {}
	for node: Dictionary in data.nodes:
		var m: Array = node.matrix_column_major
		var local := Transform3D(Basis(Vector3(m[0],m[1],m[2]), Vector3(m[4],m[5],m[6]), Vector3(m[8],m[9],m[10])), Vector3(m[12],m[13],m[14]))
		source_globals[node.name] = source_globals[node.parent] * local if node.parent != null else local
	var old_rests: Array[Transform3D] = []
	var old_globals: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		old_rests.append(rig.get_bone_rest(bone))
		old_globals.append(rig.global_transform * rig.get_bone_global_rest(bone))
	var old_ankle := (old_globals[rig.find_bone("mixamorig_LeftFoot")].origin + old_globals[rig.find_bone("mixamorig_RightFoot")].origin) * .5
	var source_ankle: Vector3 = (source_globals.lfoot.origin + source_globals.rfoot.origin) * .5
	# Match overall joint height, not arbitrary game-unit/metre assumptions.
	var uniform_scale: float = (old_globals[rig.find_bone("mixamorig_Head")].origin.y - old_ankle.y) / (source_globals.head.origin.y - source_ankle.y)
	var left_sign := signf(old_globals[rig.find_bone("mixamorig_LeftArm")].origin.x - old_globals[rig.find_bone("mixamorig_RightArm")].origin.x)
	var source_sign := signf(source_globals.lbicep.origin.x - source_globals.rbicep.origin.x)
	var facing := Basis(Vector3.UP, PI if left_sign != source_sign else 0.0)
	var targets := {}
	var source_points := {}
	for name: String in ALIASES:
		var canonical := "mixamorig_" + String(ALIASES[name])
		var source_point: Vector3 = source_globals[name].origin
		targets[rig.find_bone(canonical)] = old_ankle + facing * (source_point - source_ankle) * uniform_scale
		source_points[canonical] = [source_point.x, source_point.y, source_point.z]
	# ISO has two spine controls; retain the extra canonical intermediate joint.
	var low := rig.find_bone("mixamorig_Spine")
	var mid := rig.find_bone("mixamorig_Spine1")
	var high := rig.find_bone("mixamorig_Spine2")
	var fraction := old_globals[low].origin.distance_to(old_globals[mid].origin) / old_globals[low].origin.distance_to(old_globals[high].origin)
	targets[mid] = Vector3(targets[low]).lerp(targets[high], fraction)
	var resolved := {}
	for bone in rig.get_bone_count():
		_resolve(bone, rig, targets, old_globals, old_rests, resolved)
	for bone in rig.get_bone_count():
		var parent := rig.get_bone_parent(bone)
		var parent_global: Transform3D = resolved[parent] if parent >= 0 else rig.global_transform
		var rest := old_rests[bone]
		rest.origin = parent_global.affine_inverse() * resolved[bone].origin
		rig.set_bone_rest(bone, rest)
	rig.reset_bone_poses()
	rig.set_meta("canonical_rest_before_proportions", old_rests)
	var report := {"reference":"seal_A_arc", "source_sha256":FileAccess.get_sha256(source_path), "units":"source units uniformly normalized to existing head-to-ankle height", "metres_per_source_unit":uniform_scale * 62.0, "landmarks":source_points, "scope":"21 recovered body landmarks; modern head volume, fingers and surface detail retained"}
	rig.set_meta("iso_proportions", report)
	return report

static func _resolve(bone: int, rig: Skeleton3D, targets: Dictionary, old_globals: Array[Transform3D], old_rests: Array[Transform3D], resolved: Dictionary) -> Transform3D:
	if resolved.has(bone): return resolved[bone]
	var parent := rig.get_bone_parent(bone)
	var transform := old_globals[bone]
	if targets.has(bone):
		transform.origin = targets[bone]
	elif parent >= 0:
		transform.origin = _resolve(parent, rig, targets, old_globals, old_rests, resolved) * old_rests[bone].origin
	resolved[bone] = transform
	return transform

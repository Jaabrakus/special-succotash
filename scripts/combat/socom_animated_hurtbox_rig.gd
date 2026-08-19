class_name SocomAnimatedHurtboxRig
extends Node3D

## Damage geometry driven directly from the rendered Skeleton3D pose.
## Capsules overlap at joints on purpose: competitive shots must not disappear
## through single-frame seams between animated limbs.

const HurtboxAreaScript := preload("res://scripts/combat/socom_hurtbox_area.gd")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")

const HEAD_RADIUS := 0.19
const TORSO_RADIUS := 0.245
const PELVIS_RADIUS := 0.22
const UPPER_ARM_RADIUS := 0.115
const FOREARM_RADIUS := 0.10
const THIGH_RADIUS := 0.155
const CALF_RADIUS := 0.135
const FOOT_RADIUS := 0.13

var skeleton: Skeleton3D
var damage_receiver: Node
var debug_visible: bool = false
var precision_core_debug_visible: bool = false
var precision_core_scale: float = 1.0
var enabled: bool = true
var radius_scales: Dictionary = HurtboxProfile.load_scales()

var _records: Array[Dictionary] = []
var _bone_indices: Dictionary = {}
var _debug_materials: Dictionary = {}


func bind(target_skeleton: Skeleton3D, receiver: Node) -> bool:
	skeleton = target_skeleton
	damage_receiver = receiver
	radius_scales = HurtboxProfile.load_scales()
	_clear_hurtboxes()
	if skeleton == null:
		push_warning("Animated hurtbox rig could not bind: Skeleton3D missing")
		return false

	_cache_required_bones()
	if not _has_required_bones():
		push_warning("Animated hurtbox rig could not bind: required Mixamo bones missing")
		return false

	_add_sphere(&"HEAD", &"Head", &"Neck", HEAD_RADIUS, 0.42)
	_add_capsule(&"TORSO", &"Spine", &"Neck", TORSO_RADIUS)
	_add_capsule(&"PELVIS", &"Hips", &"Spine", PELVIS_RADIUS)

	_add_capsule(&"LEFT_UPPER_ARM", &"LeftArm", &"LeftForeArm", UPPER_ARM_RADIUS)
	_add_capsule(&"RIGHT_UPPER_ARM", &"RightArm", &"RightForeArm", UPPER_ARM_RADIUS)
	_add_capsule(&"LEFT_FOREARM", &"LeftForeArm", &"LeftHand", FOREARM_RADIUS)
	_add_capsule(&"RIGHT_FOREARM", &"RightForeArm", &"RightHand", FOREARM_RADIUS)
	_add_capsule(&"LEFT_THIGH", &"LeftUpLeg", &"LeftLeg", THIGH_RADIUS)
	_add_capsule(&"RIGHT_THIGH", &"RightUpLeg", &"RightLeg", THIGH_RADIUS)
	_add_capsule(&"LEFT_CALF", &"LeftLeg", &"LeftFoot", CALF_RADIUS)
	_add_capsule(&"RIGHT_CALF", &"RightLeg", &"RightFoot", CALF_RADIUS)
	_add_sphere(&"LEFT_FOOT", &"LeftFoot", &"LeftLeg", FOOT_RADIUS, -0.12)
	_add_sphere(&"RIGHT_FOOT", &"RightFoot", &"RightLeg", FOOT_RADIUS, -0.12)

	set_debug_visible(debug_visible)
	set_enabled(enabled)
	force_pose_update()
	return true


func _physics_process(_delta: float) -> void:
	force_pose_update()


func force_pose_update() -> void:
	if skeleton == null or not is_instance_valid(skeleton):
		return
	for record in _records:
		match StringName(record.kind):
			&"capsule":
				_update_capsule(record)
			&"midpoint_capsule":
				_update_midpoint_capsule(record)
			&"sphere":
				_update_sphere(record)


func set_enabled(value: bool) -> void:
	enabled = value
	for record in _records:
		var area: Area3D = record.area
		area.set_hurtbox_enabled(enabled)


func set_debug_visible(value: bool) -> void:
	debug_visible = value
	for record in _records:
		var mesh: MeshInstance3D = record.debug_mesh
		mesh.visible = debug_visible


func set_precision_core_debug(value: bool, core_scale: float = 1.0) -> void:
	precision_core_debug_visible = value
	precision_core_scale = clampf(core_scale, 0.05, 1.0)
	for record in _records:
		var mesh: MeshInstance3D = record.precision_mesh
		mesh.visible = precision_core_debug_visible
	force_pose_update()


func apply_radius_scales(settings: Dictionary) -> void:
	for key in radius_scales:
		if settings.has(key) or settings.has(String(key)):
			var raw_value: Variant = settings.get(key, settings.get(String(key), radius_scales[key]))
			radius_scales[key] = clampf(float(raw_value), 0.45, 1.25)
	force_pose_update()


func get_radius_scales() -> Dictionary:
	return radius_scales.duplicate()


func save_radius_scales() -> bool:
	return HurtboxProfile.save_scales(radius_scales)


func get_hurtbox_areas() -> Array[Area3D]:
	var result: Array[Area3D] = []
	for record in _records:
		result.append(record.area as Area3D)
	return result


func get_hurtbox_rids() -> Array[RID]:
	var result: Array[RID] = []
	for record in _records:
		var area: Area3D = record.area
		result.append(area.get_rid())
	return result


func get_region_names() -> Array[StringName]:
	var result: Array[StringName] = []
	for record in _records:
		result.append(StringName(record.region))
	return result


func get_region_area(region: StringName) -> Area3D:
	for record in _records:
		if StringName(record.region) == region:
			return record.area as Area3D
	return null


func _cache_required_bones() -> void:
	_bone_indices.clear()
	for short_name in [
		"Hips", "Spine", "Neck", "Head",
		"LeftArm", "LeftForeArm", "LeftHand",
		"RightArm", "RightForeArm", "RightHand",
		"LeftUpLeg", "LeftLeg", "LeftFoot",
		"RightUpLeg", "RightLeg", "RightFoot"
	]:
		_bone_indices[StringName(short_name)] = _find_bone_index(short_name)


func _has_required_bones() -> bool:
	for bone_name in _bone_indices:
		if int(_bone_indices[bone_name]) < 0:
			return false
	return true


func _find_bone_index(short_name: String) -> int:
	var exact := skeleton.find_bone("mixamorig_%s" % short_name)
	if exact >= 0:
		return exact
	for index in skeleton.get_bone_count():
		var candidate := skeleton.get_bone_name(index)
		if candidate.ends_with(short_name):
			return index
	return -1


func _bone_world_position(short_name: StringName) -> Vector3:
	var index := int(_bone_indices.get(short_name, -1))
	if index < 0:
		return global_position
	return skeleton.global_transform * skeleton.get_bone_global_pose(index).origin


func _add_capsule(
	region: StringName,
	from_bone: StringName,
	to_bone: StringName,
	radius: float
) -> void:
	var pair := _create_capsule_nodes(region, radius)
	_records.append({
		"kind": &"capsule",
		"region": region,
		"from_bone": from_bone,
		"to_bone": to_bone,
		"base_radius": radius,
		"area": pair.area,
		"shape": pair.shape,
		"debug_mesh": pair.debug_mesh,
		"precision_mesh": pair.precision_mesh
	})


func _add_midpoint_capsule(
	region: StringName,
	from_bone: StringName,
	left_bone: StringName,
	right_bone: StringName,
	radius: float,
	target_fraction: float
) -> void:
	var pair := _create_capsule_nodes(region, radius)
	_records.append({
		"kind": &"midpoint_capsule",
		"region": region,
		"from_bone": from_bone,
		"left_bone": left_bone,
		"right_bone": right_bone,
		"base_radius": radius,
		"target_fraction": target_fraction,
		"area": pair.area,
		"shape": pair.shape,
		"debug_mesh": pair.debug_mesh,
		"precision_mesh": pair.precision_mesh
	})


func _add_sphere(
	region: StringName,
	bone: StringName,
	reference_bone: StringName,
	radius: float,
	directional_offset: float
) -> void:
	var area := _create_area(region)
	var shape_node := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = radius
	shape_node.shape = sphere
	area.add_child(shape_node)

	var debug_mesh := MeshInstance3D.new()
	var sphere_mesh := SphereMesh.new()
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	debug_mesh.mesh = sphere_mesh
	_configure_debug_mesh(debug_mesh, region)
	area.add_child(debug_mesh)
	var precision_mesh := _create_precision_sphere(radius)
	area.add_child(precision_mesh)
	_records.append({
		"kind": &"sphere",
		"region": region,
		"bone": bone,
		"reference_bone": reference_bone,
		"base_radius": radius,
		"directional_offset": directional_offset,
		"area": area,
		"shape": sphere,
		"debug_mesh": debug_mesh,
		"precision_mesh": precision_mesh
	})


func _create_capsule_nodes(region: StringName, radius: float) -> Dictionary:
	var area := _create_area(region)
	var shape_node := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = radius
	capsule.height = radius * 2.0
	shape_node.shape = capsule
	area.add_child(shape_node)

	var debug_mesh := MeshInstance3D.new()
	var capsule_mesh := CapsuleMesh.new()
	capsule_mesh.radius = radius
	capsule_mesh.height = radius * 2.0
	debug_mesh.mesh = capsule_mesh
	_configure_debug_mesh(debug_mesh, region)
	area.add_child(debug_mesh)
	var precision_mesh := _create_precision_capsule(radius)
	area.add_child(precision_mesh)
	return {
		"area": area,
		"shape": capsule,
		"debug_mesh": debug_mesh,
		"precision_mesh": precision_mesh,
	}


func _create_area(region: StringName) -> Area3D:
	var area := HurtboxAreaScript.new() as Area3D
	area.name = "Hurtbox_%s" % String(region).to_pascal_case()
	area.configure(region, damage_receiver)
	add_child(area)
	return area


func _configure_debug_mesh(mesh: MeshInstance3D, region: StringName) -> void:
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.material_override = _debug_material(region)
	mesh.visible = debug_visible


func _create_precision_sphere(radius: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mesh.mesh = sphere
	_configure_precision_mesh(mesh)
	return mesh


func _create_precision_capsule(radius: float) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var capsule := CapsuleMesh.new()
	capsule.radius = radius
	capsule.height = radius * 2.0
	mesh.mesh = capsule
	_configure_precision_mesh(mesh)
	return mesh


func _configure_precision_mesh(mesh: MeshInstance3D) -> void:
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.albedo_color = Color(0.05, 0.95, 1.0, 0.24)
	mesh.material_override = material
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh.visible = precision_core_debug_visible


func _debug_material(region: StringName) -> StandardMaterial3D:
	var family := _region_family(region)
	if _debug_materials.has(family):
		return _debug_materials[family]
	var material := StandardMaterial3D.new()
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	match family:
		&"HEAD": material.albedo_color = Color(1.0, 0.20, 0.18, 0.34)
		&"TORSO": material.albedo_color = Color(1.0, 0.72, 0.16, 0.28)
		&"ARMS": material.albedo_color = Color(0.18, 0.82, 1.0, 0.30)
		_: material.albedo_color = Color(0.28, 1.0, 0.42, 0.30)
	_debug_materials[family] = material
	return material


func _region_family(region: StringName) -> StringName:
	var text := String(region)
	if text == "HEAD":
		return &"HEAD"
	if text in ["TORSO", "PELVIS"]:
		return &"TORSO"
	if "ARM" in text:
		return &"ARMS"
	return &"LEGS"


func _update_capsule(record: Dictionary) -> void:
	_update_capsule_between(
		record,
		_bone_world_position(StringName(record.from_bone)),
		_bone_world_position(StringName(record.to_bone))
	)


func _update_midpoint_capsule(record: Dictionary) -> void:
	var start := _bone_world_position(StringName(record.from_bone))
	var left := _bone_world_position(StringName(record.left_bone))
	var right := _bone_world_position(StringName(record.right_bone))
	var target := left.lerp(right, 0.5)
	target = start.lerp(target, float(record.target_fraction))
	_update_capsule_between(record, start, target)


func _update_capsule_between(record: Dictionary, start: Vector3, finish: Vector3) -> void:
	var delta := finish - start
	var length := delta.length()
	if length < 0.001:
		return
	var radius := _scaled_radius(record)
	var total_height := maxf(radius * 2.0, length + radius * 2.0)
	var capsule: CapsuleShape3D = record.shape
	capsule.radius = radius
	capsule.height = total_height
	var debug_mesh: MeshInstance3D = record.debug_mesh
	var capsule_mesh := debug_mesh.mesh as CapsuleMesh
	capsule_mesh.radius = radius
	capsule_mesh.height = total_height
	var precision_mesh: MeshInstance3D = record.precision_mesh
	var precision_capsule := precision_mesh.mesh as CapsuleMesh
	var core_radius := radius * precision_core_scale
	precision_capsule.radius = core_radius
	precision_capsule.height = maxf(core_radius * 2.0, length + core_radius * 2.0)

	var y_axis := delta / length
	var x_axis := y_axis.cross(Vector3.FORWARD)
	if x_axis.length_squared() < 0.0001:
		x_axis = y_axis.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(y_axis).normalized()
	var area: Area3D = record.area
	area.global_transform = Transform3D(Basis(x_axis, y_axis, z_axis), start.lerp(finish, 0.5))


func _update_sphere(record: Dictionary) -> void:
	var bone_position := _bone_world_position(StringName(record.bone))
	var reference_position := _bone_world_position(StringName(record.reference_bone))
	var direction := (bone_position - reference_position).normalized()
	var radius := _scaled_radius(record)
	var sphere: SphereShape3D = record.shape
	sphere.radius = radius
	var debug_mesh: MeshInstance3D = record.debug_mesh
	var sphere_mesh := debug_mesh.mesh as SphereMesh
	sphere_mesh.radius = radius
	sphere_mesh.height = radius * 2.0
	var precision_mesh: MeshInstance3D = record.precision_mesh
	var precision_sphere := precision_mesh.mesh as SphereMesh
	var core_radius := radius * precision_core_scale
	precision_sphere.radius = core_radius
	precision_sphere.height = core_radius * 2.0
	var offset := direction * radius * float(record.directional_offset)
	var area: Area3D = record.area
	area.global_transform = Transform3D(Basis.IDENTITY, bone_position + offset)


func _scaled_radius(record: Dictionary) -> float:
	var region := StringName(record.region)
	var group := &"legs"
	if region == &"HEAD":
		group = &"head"
	elif region in [&"TORSO", &"PELVIS"]:
		group = &"torso"
	elif "ARM" in String(region):
		group = &"arms"
	return (
		float(record.base_radius)
		* float(radius_scales.get("global", 0.88))
		* float(radius_scales.get(String(group), 1.0))
	)


func _clear_hurtboxes() -> void:
	for record in _records:
		var area: Area3D = record.area
		if is_instance_valid(area):
			area.queue_free()
	_records.clear()

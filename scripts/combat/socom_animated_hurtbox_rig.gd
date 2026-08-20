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
var geometry_tuning: Dictionary = HurtboxProfile.load_geometry()
var custom_hitboxes: Array[Dictionary] = HurtboxProfile.load_custom_hitboxes()

var _records: Array[Dictionary] = []
var _bone_indices: Dictionary = {}
var _debug_materials: Dictionary = {}


func bind(target_skeleton: Skeleton3D, receiver: Node) -> bool:
	skeleton = target_skeleton
	damage_receiver = receiver
	radius_scales = HurtboxProfile.load_scales()
	geometry_tuning = HurtboxProfile.load_geometry()
	custom_hitboxes = HurtboxProfile.load_custom_hitboxes()
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
	_rebuild_custom_hitbox_records()

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
		_ensure_record_shape(record)
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
	if settings.has(&"global") or settings.has("global"):
		radius_scales[&"global"] = clampf(
			float(settings.get(&"global", settings.get("global", radius_scales[&"global"]))),
			HurtboxProfile.MIN_SCALE,
			HurtboxProfile.MAX_SCALE
		)
	for group_key: StringName in HurtboxProfile.LEGACY_GROUP_REGIONS:
		if not (settings.has(group_key) or settings.has(String(group_key))):
			continue
		var has_exact_member := false
		for region_key: StringName in HurtboxProfile.LEGACY_GROUP_REGIONS[group_key]:
			if region_key == group_key:
				continue
			if settings.has(region_key) or settings.has(String(region_key)):
				has_exact_member = true
				break
		if not has_exact_member:
			var group_value := float(settings.get(
				group_key,
				settings.get(String(group_key), radius_scales.get(group_key, 1.0))
			))
			HurtboxProfile.set_group_scale(radius_scales, group_key, group_value)
	for region_key in HurtboxProfile.REGION_KEYS:
		if settings.has(region_key) or settings.has(String(region_key)):
			radius_scales[region_key] = clampf(
				float(settings.get(
					region_key,
					settings.get(String(region_key), radius_scales.get(region_key, 1.0))
				)),
				HurtboxProfile.MIN_SCALE,
				HurtboxProfile.MAX_SCALE
			)
	force_pose_update()


func get_radius_scales() -> Dictionary:
	return radius_scales.duplicate()


func apply_geometry_tuning(settings: Dictionary) -> void:
	geometry_tuning = HurtboxProfile.normalize_geometry(settings)
	force_pose_update()


func get_geometry_tuning() -> Dictionary:
	return geometry_tuning.duplicate(true)


func apply_custom_hitboxes(settings: Variant) -> void:
	var normalized := HurtboxProfile.normalize_custom_hitboxes(settings)
	if _custom_structure_matches(normalized):
		custom_hitboxes = normalized
		_update_custom_record_tuning()
		force_pose_update()
		return
	custom_hitboxes = normalized
	_rebuild_custom_hitbox_records()
	set_debug_visible(debug_visible)
	set_precision_core_debug(precision_core_debug_visible, precision_core_scale)
	set_enabled(enabled)
	force_pose_update()


func get_custom_hitboxes() -> Array[Dictionary]:
	return custom_hitboxes.duplicate(true)


func _custom_structure_matches(settings: Array[Dictionary]) -> bool:
	if settings.size() != custom_hitboxes.size():
		return false
	var record_count := 0
	for record in _records:
		if bool(record.get("custom", false)):
			record_count += 1
	if record_count != settings.size():
		return false
	for index in settings.size():
		for key in ["id", "source_region", "damage_region"]:
			if String(settings[index].get(key, "")) != String(custom_hitboxes[index].get(key, "")):
				return false
	return true


func _update_custom_record_tuning() -> void:
	var entries_by_id: Dictionary = {}
	for entry in custom_hitboxes:
		entries_by_id[StringName(entry.get("id", &""))] = entry
	for record in _records:
		if not bool(record.get("custom", false)):
			continue
		var editor_id := StringName(record.editor_id)
		var entry: Dictionary = entries_by_id.get(editor_id, {})
		if entry.is_empty():
			continue
		record["custom_width_scale"] = float(entry.get("width_scale", 1.0))
		record["custom_geometry"] = (entry.get("geometry", {}) as Dictionary).duplicate(true)


func save_radius_scales() -> bool:
	return HurtboxProfile.save_profile(radius_scales, geometry_tuning, custom_hitboxes)


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


func get_editor_hitbox_ids() -> Array[StringName]:
	var result: Array[StringName] = []
	for record in _records:
		result.append(StringName(record.editor_id))
	return result


func get_editor_hitbox_area(editor_id: StringName) -> Area3D:
	for record in _records:
		if StringName(record.editor_id) == editor_id:
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
		"editor_id": HurtboxProfile.region_scale_key(region),
		"custom": false,
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
		"editor_id": HurtboxProfile.region_scale_key(region),
		"custom": false,
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
	var pair := _create_sphere_nodes(region, radius)
	_records.append({
		"kind": &"sphere",
		"region": region,
		"editor_id": HurtboxProfile.region_scale_key(region),
		"custom": false,
		"bone": bone,
		"reference_bone": reference_bone,
		"base_radius": radius,
		"directional_offset": directional_offset,
		"area": pair.area,
		"shape": pair.shape,
		"debug_mesh": pair.debug_mesh,
		"precision_mesh": pair.precision_mesh
	})


func _create_capsule_nodes(
	region: StringName,
	radius: float,
	editor_id: StringName = &""
) -> Dictionary:
	var area := _create_area(region, editor_id)
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


func _create_sphere_nodes(
	region: StringName,
	radius: float,
	editor_id: StringName = &""
) -> Dictionary:
	var area := _create_area(region, editor_id)
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
	return {
		"area": area,
		"shape": sphere,
		"debug_mesh": debug_mesh,
		"precision_mesh": precision_mesh,
	}


func _create_area(region: StringName, editor_id: StringName = &"") -> Area3D:
	var area := HurtboxAreaScript.new() as Area3D
	area.name = (
		"Hurtbox_%s" % String(region).to_pascal_case()
		if editor_id == &""
		else "HurtboxExtra_%s" % String(editor_id).to_pascal_case()
	)
	area.configure(region, damage_receiver)
	add_child(area)
	return area


func _rebuild_custom_hitbox_records() -> void:
	for index in range(_records.size() - 1, -1, -1):
		var record: Dictionary = _records[index]
		if not bool(record.get("custom", false)):
			continue
		var area := record.area as Area3D
		if is_instance_valid(area):
			area.queue_free()
		_records.remove_at(index)
	for custom_entry in custom_hitboxes:
		_append_custom_hitbox_record(custom_entry)


func _append_custom_hitbox_record(custom_entry: Dictionary) -> void:
	var source_region := StringName(custom_entry.get("source_region", &""))
	var damage_region := StringName(custom_entry.get(
		"damage_region",
		HurtboxProfile.damage_type_for_source_region(source_region)
	))
	var source_record: Dictionary = {}
	for candidate in _records:
		if (
			not bool(candidate.get("custom", false))
			and StringName(candidate.editor_id) == source_region
		):
			source_record = candidate
			break
	if source_record.is_empty():
		return
	var editor_id := StringName(custom_entry.get("id", &""))
	var pair: Dictionary
	if StringName(source_record.kind) == &"sphere":
		pair = _create_sphere_nodes(
			damage_region,
			float(source_record.base_radius),
			editor_id
		)
	else:
		pair = _create_capsule_nodes(
			damage_region,
			float(source_record.base_radius),
			editor_id
		)
	var record := source_record.duplicate()
	record["region"] = damage_region
	record["source_region"] = source_region
	record["editor_id"] = editor_id
	record["custom"] = true
	record["custom_width_scale"] = float(custom_entry.get("width_scale", 1.0))
	record["custom_geometry"] = (custom_entry.get("geometry", {}) as Dictionary).duplicate(true)
	record["area"] = pair.area
	record["shape"] = pair.shape
	record["debug_mesh"] = pair.debug_mesh
	record["precision_mesh"] = pair.precision_mesh
	_records.append(record)


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
		&"NECK": material.albedo_color = Color(0.92, 0.30, 1.0, 0.32)
		&"TORSO": material.albedo_color = Color(1.0, 0.72, 0.16, 0.28)
		&"ARMS": material.albedo_color = Color(0.18, 0.82, 1.0, 0.30)
		_: material.albedo_color = Color(0.28, 1.0, 0.42, 0.30)
	_debug_materials[family] = material
	return material


func _region_family(region: StringName) -> StringName:
	var text := String(region)
	if text == "HEAD":
		return &"HEAD"
	if text == "NECK":
		return &"NECK"
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
	var bone_length := delta.length()
	if bone_length < 0.001:
		return
	var radius := _scaled_radius(record)
	var length_scale := _record_length_scale(record)
	# Capsule height includes both rounded caps. Keeping total height on the
	# authored bone span prevents the torso cap from covering the head while the
	# neighboring shapes still meet at their shared joint.
	var total_height := maxf(
		radius * 2.0 + 0.001,
		maxf(radius * 2.0 + 0.001, bone_length) * length_scale
	)
	_update_record_shape_dimensions(record, radius, total_height)

	var area_basis := _basis_for_axis(delta / bone_length)
	var offset := _record_geometry_offset(record)
	var area: Area3D = record.area
	area.global_transform = Transform3D(
		area_basis,
		start.lerp(finish, 0.5) + area_basis * offset
	)


func _update_sphere(record: Dictionary) -> void:
	var bone_position := _bone_world_position(StringName(record.bone))
	var reference_position := _bone_world_position(StringName(record.reference_bone))
	var direction := (bone_position - reference_position).normalized()
	var radius := _scaled_radius(record)
	_update_record_shape_dimensions(record, radius, radius * 2.0)
	var offset := direction * radius * float(record.directional_offset)
	var area_basis := _basis_for_axis(direction)
	offset += area_basis * _record_geometry_offset(record)
	var area: Area3D = record.area
	area.global_transform = Transform3D(area_basis, bone_position + offset)


func _record_shape_kind(record: Dictionary) -> StringName:
	var source_region := StringName(record.get(
		"source_region",
		record.get("editor_id", &"torso")
	))
	var geometry_entry: Dictionary = (
		(record.get("custom_geometry", {}) as Dictionary)
		if bool(record.get("custom", false))
		else (geometry_tuning.get(source_region, {}) as Dictionary)
	)
	return HurtboxProfile.geometry_shape(
		{source_region: geometry_entry},
		source_region
	)


func _ensure_record_shape(record: Dictionary) -> void:
	var requested := _record_shape_kind(record)
	if StringName(record.get("shape_kind", &"")) == requested:
		return
	var area := record.area as Area3D
	var shape_node: CollisionShape3D = null
	for child in area.get_children():
		if child is CollisionShape3D:
			shape_node = child as CollisionShape3D
			break
	if shape_node == null:
		return
	var collision_shape: Shape3D
	var visible_mesh: PrimitiveMesh
	var precision_shape_mesh: PrimitiveMesh
	match requested:
		&"sphere":
			collision_shape = SphereShape3D.new()
			visible_mesh = SphereMesh.new()
			precision_shape_mesh = SphereMesh.new()
		&"box":
			collision_shape = BoxShape3D.new()
			visible_mesh = BoxMesh.new()
			precision_shape_mesh = BoxMesh.new()
		_:
			collision_shape = CapsuleShape3D.new()
			visible_mesh = CapsuleMesh.new()
			precision_shape_mesh = CapsuleMesh.new()
	shape_node.shape = collision_shape
	(record.debug_mesh as MeshInstance3D).mesh = visible_mesh
	(record.precision_mesh as MeshInstance3D).mesh = precision_shape_mesh
	record["shape"] = collision_shape
	record["shape_kind"] = requested


func _update_record_shape_dimensions(
	record: Dictionary,
	radius: float,
	total_height: float
) -> void:
	var shape_kind := StringName(record.get("shape_kind", &"capsule"))
	var debug_mesh := record.debug_mesh as MeshInstance3D
	var precision_mesh := record.precision_mesh as MeshInstance3D
	var core_radius := radius * precision_core_scale
	match shape_kind:
		&"sphere":
			(record.shape as SphereShape3D).radius = radius
			var sphere_mesh := debug_mesh.mesh as SphereMesh
			sphere_mesh.radius = radius
			sphere_mesh.height = radius * 2.0
			var precision_sphere := precision_mesh.mesh as SphereMesh
			precision_sphere.radius = core_radius
			precision_sphere.height = core_radius * 2.0
		&"box":
			var box_size := Vector3(radius * 2.0, total_height, radius * 2.0)
			(record.shape as BoxShape3D).size = box_size
			(debug_mesh.mesh as BoxMesh).size = box_size
			(precision_mesh.mesh as BoxMesh).size = box_size * precision_core_scale
		_:
			var capsule := record.shape as CapsuleShape3D
			capsule.radius = radius
			capsule.height = total_height
			var capsule_mesh := debug_mesh.mesh as CapsuleMesh
			capsule_mesh.radius = radius
			capsule_mesh.height = total_height
			var precision_capsule := precision_mesh.mesh as CapsuleMesh
			precision_capsule.radius = core_radius
			var center_segment_length := maxf(0.001, total_height - radius * 2.0)
			precision_capsule.height = center_segment_length + core_radius * 2.0


func _basis_for_axis(y_axis: Vector3) -> Basis:
	var normalized_y := y_axis.normalized()
	var reference_forward := (
		skeleton.global_basis.z.normalized()
		if skeleton != null
		else Vector3.FORWARD
	)
	var x_axis := normalized_y.cross(reference_forward)
	if x_axis.length_squared() < 0.0001:
		x_axis = normalized_y.cross(Vector3.RIGHT)
	x_axis = x_axis.normalized()
	var z_axis := x_axis.cross(normalized_y).normalized()
	return Basis(x_axis, normalized_y, z_axis)


func _scaled_radius(record: Dictionary) -> float:
	var region := StringName(record.region)
	var region_key := HurtboxProfile.region_scale_key(region)
	var region_scale := (
		float(record.get("custom_width_scale", 1.0))
		if bool(record.get("custom", false))
		else float(radius_scales.get(region_key, 1.0))
	)
	return (
		float(record.base_radius)
		* float(radius_scales.get("global", 0.88))
		* region_scale
	)


func _record_geometry_offset(record: Dictionary) -> Vector3:
	if bool(record.get("custom", false)):
		var editor_id := StringName(record.editor_id)
		return HurtboxProfile.geometry_offset(
			{editor_id: record.get("custom_geometry", {})},
			editor_id
		)
	var region_key := HurtboxProfile.region_scale_key(StringName(record.region))
	return HurtboxProfile.geometry_offset(geometry_tuning, region_key)


func _record_length_scale(record: Dictionary) -> float:
	if bool(record.get("custom", false)):
		var editor_id := StringName(record.editor_id)
		return HurtboxProfile.geometry_length_scale(
			{editor_id: record.get("custom_geometry", {})},
			editor_id
		)
	var region_key := HurtboxProfile.region_scale_key(StringName(record.region))
	return HurtboxProfile.geometry_length_scale(geometry_tuning, region_key)


func _clear_hurtboxes() -> void:
	for record in _records:
		var area: Area3D = record.area
		if is_instance_valid(area):
			area.queue_free()
	_records.clear()

class_name SocomAnimationStudioRigOverlay
extends Node3D

## Gunsmith-parity visual overlay for Animation Studio. It draws editor-only
## rig markers and reference lines. It never changes camera or shot authority.

const PICK_RADIUS_PX := 22.0
const BLUE_LINE_PICK_RADIUS_PX := 28.0
const FINE_JOINT_PICK_RADIUS_PX := 13.0
const FINE_JOINT_RADIUS := 0.011
const CORRECTION_OVERLAY := preload(
	"res://scripts/labs/animation_correction_overlay.gd"
)
const JOINT_SCHEMA := preload(
	"res://scripts/player/operator_joint_control_schema.gd"
)
const WEAPON_CONTACT_SOLVER := preload(
	"res://scripts/player/operator_weapon_contact_solver.gd"
)

var markers: Dictionary = {}
var marker_base_colors: Dictionary = {}
var fine_joint_markers: Dictionary = {}
var fine_joint_skeleton_id: int = 0
var elbow_guides_visible: bool = true
var hand_guides_active: bool = true
var preview_reference_mode: bool = false
var selected_target: StringName = &""
var hovered_target: StringName = &""
var line_mesh := ImmediateMesh.new()
var line_instance: MeshInstance3D


func _ready() -> void:
	name = "AnimationStudioGunsmithRigOverlay"
	_build_marker("right_elbow_pole", "RightElbowIKPole", Color(1.0, 0.25, 0.9), 0.026)
	_build_marker("left_elbow_pole", "LeftElbowIKPole", Color(0.75, 0.35, 1.0), 0.026)
	_build_marker("right_hand", "RightHandGripTarget", Color(1.0, 0.55, 0.08), 0.024)
	_build_marker("left_hand", "LeftHandGripTarget", Color(0.0, 0.95, 1.0), 0.024)
	_build_marker("weapon_mount", "WeaponMount", Color(1.0, 0.55, 0.08), 0.026)
	_build_marker("muzzle", "Socket_Muzzle", Color(1.0, 0.2, 0.2), 0.022)
	_build_marker("barrel_base", "Socket_BarrelBase", Color(1.0, 0.4, 0.4), 0.019)
	_build_marker("ejection", "Socket_Ejection", Color(1.0, 0.85, 0.1), 0.019)
	_build_marker("optic", "Socket_Optic", Color(0.2, 1.0, 0.4), 0.020)
	_build_marker("placement_origin", "GunPlacementLineOrigin", Color(0.25, 0.55, 1.0), 0.023)
	_build_marker("placement_direction", "GunPlacementDirectionHandle", Color(0.55, 0.78, 1.0), 0.021)
	line_instance = MeshInstance3D.new()
	line_instance.name = "GunsmithRigReferenceLines"
	line_instance.mesh = line_mesh
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	line_material.render_priority = 105
	line_instance.material_override = line_material
	line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(line_instance)


func update_overlay(
	skeleton: Skeleton3D,
	weapon_pivot: Node3D,
	right_hand: Marker3D,
	left_hand: Marker3D,
	barrel_base: Marker3D,
	muzzle: Marker3D,
	ejection: Marker3D,
	optic: Marker3D,
	right_elbow_offset: Vector3,
	left_elbow_offset: Vector3,
	placement_origin: Vector3,
	placement_direction: Vector3,
	selected_bone: String = ""
) -> void:
	if skeleton == null:
		visible = false
		return
	visible = true
	_update_fine_joint_markers(skeleton, selected_bone)
	var right_hand_world := _bone_world(skeleton, ["mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001", "Bip01 R Hand"])
	var left_hand_joint_world := _bone_world(skeleton, ["mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001", "Bip01 L Hand"])
	var left_hand_contact_world := left_hand.global_position if left_hand else left_hand_joint_world
	var right_shoulder := _bone_world(skeleton, ["mixamorig_RightArm", "mixamorig:RightArm", "ArmUpper.R", "Bip01 R UpperArm"])
	var left_shoulder := _bone_world(skeleton, ["mixamorig_LeftArm", "mixamorig:LeftArm", "ArmUpper.L", "Bip01 L UpperArm"])
	var right_elbow_joint := _bone_world(skeleton, ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "ArmLower.R", "Bip01 R Forearm"])
	var left_elbow_joint := _bone_world(skeleton, ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "ArmLower.L", "Bip01 L Forearm"])
	var right_elbow_pole := _elbow_world(skeleton, right_shoulder, right_hand_world, right_elbow_offset, true)
	var left_palm_roll_degrees := 0.0
	if weapon_pivot != null:
		var active_map: Variant = weapon_pivot.get_meta(
			"active_animation_hand_map",
			{}
		)
		if active_map is Dictionary:
			left_palm_roll_degrees = float(
				(active_map as Dictionary).get("palm_roll_deg", 0.0)
			)
	var left_elbow_pole := WEAPON_CONTACT_SOLVER.support_elbow_pole(
		skeleton,
		_find_bone(skeleton, ["mixamorig_LeftArm", "mixamorig:LeftArm", "ArmUpper.L", "Bip01 L UpperArm"]),
		_find_bone(skeleton, ["mixamorig_RightArm", "mixamorig:RightArm", "ArmUpper.R", "Bip01 R UpperArm"]),
		_find_bone(skeleton, ["mixamorig_Hips", "mixamorig:Hips", "Hips", "Bip01 Pelvis"]),
		left_hand_joint_world,
		left_palm_roll_degrees,
		left_elbow_offset
	)
	# The animation owns the trigger arm and the rifle follows that hand. A
	# second right-hand IK target would form a cyclic solver, so only the
	# support-hand targets are interactive here.
	_set_marker("right_elbow_pole", right_elbow_pole, false)
	_set_marker(
		"left_elbow_pole",
		left_elbow_pole,
		elbow_guides_visible and hand_guides_active and not preview_reference_mode
	)
	_set_marker(
		"right_hand",
		right_hand.global_position if right_hand else right_hand_world,
		preview_reference_mode
	)
	_set_marker(
		"left_hand",
		left_hand_contact_world,
		(left_hand != null and hand_guides_active) or preview_reference_mode
	)
	_set_marker("weapon_mount", weapon_pivot.global_position if weapon_pivot else Vector3.ZERO, weapon_pivot != null)
	_set_node_marker("barrel_base", barrel_base)
	_set_node_marker("muzzle", muzzle)
	_set_node_marker("ejection", ejection)
	_set_node_marker("optic", optic)
	_set_marker("placement_origin", placement_origin, placement_direction.length_squared() > 0.5)
	_set_marker("placement_direction", placement_origin + placement_direction * 2.0, placement_direction.length_squared() > 0.5)
	_draw_lines(
		right_shoulder, right_elbow_joint, right_hand_world, right_elbow_pole,
		left_shoulder, left_elbow_joint, left_hand_joint_world, left_elbow_pole,
		barrel_base, muzzle, optic, placement_origin, placement_direction
	)
	_refresh_target_styles(selected_bone)


func pick(camera: Camera3D, screen_position: Vector2) -> StringName:
	if not visible or camera == null:
		return &""
	# Hand, elbow, and blue-line authoring is the primary interaction layer.
	# Small weapon sockets can overlap those controls in screen space, but must
	# never steal an arm-placement click. Within a layer, the nearest dot wins.
	var marker_layers := [
		[
			"placement_direction", "placement_origin",
			"right_hand", "left_hand",
			"right_elbow_pole", "left_elbow_pole",
		],
		["weapon_mount", "muzzle", "barrel_base", "optic", "ejection"],
	]
	for marker_layer in marker_layers:
		var closest_marker := ""
		var closest_marker_distance := INF
		for marker_id in marker_layer:
			var marker := markers.get(marker_id) as MeshInstance3D
			if marker and marker.visible and not camera.is_position_behind(marker.global_position):
				var pick_radius := (
					BLUE_LINE_PICK_RADIUS_PX
					if marker_id in ["placement_origin", "placement_direction"]
					else PICK_RADIUS_PX
				)
				var marker_distance := screen_position.distance_to(
					camera.unproject_position(marker.global_position)
				)
				if marker_distance <= pick_radius and marker_distance < closest_marker_distance:
					closest_marker_distance = marker_distance
					closest_marker = marker_id
		if not closest_marker.is_empty():
			return StringName(closest_marker)
	var closest_distance := FINE_JOINT_PICK_RADIUS_PX
	var closest_bone := ""
	for raw_bone_name in fine_joint_markers.keys():
		var bone_name := String(raw_bone_name)
		var fine_marker := fine_joint_markers[raw_bone_name] as MeshInstance3D
		if fine_marker and fine_marker.visible and not camera.is_position_behind(fine_marker.global_position):
			var distance := screen_position.distance_to(
				camera.unproject_position(fine_marker.global_position)
			)
			if distance < closest_distance:
				closest_distance = distance
				closest_bone = bone_name
	if not closest_bone.is_empty():
		return StringName("bone:%s" % closest_bone)
	return &""


func target_position(target_id: StringName) -> Vector3:
	var marker := markers.get(String(target_id)) as MeshInstance3D
	return marker.global_position if marker else global_position


func set_elbow_guides_visible(enabled: bool) -> void:
	elbow_guides_visible = enabled
	_set_marker_visibility("right_elbow_pole", false)
	_set_marker_visibility(
		"left_elbow_pole",
		enabled and hand_guides_active and not preview_reference_mode
	)


func set_hand_guides_active(enabled: bool) -> void:
	hand_guides_active = enabled
	_set_marker_visibility("right_hand", preview_reference_mode)
	_set_marker_visibility("left_hand", enabled or preview_reference_mode)
	_set_marker_visibility("right_elbow_pole", false)
	_set_marker_visibility(
		"left_elbow_pole",
		enabled and elbow_guides_visible and not preview_reference_mode
	)


func set_preview_reference_mode(enabled: bool) -> void:
	preview_reference_mode = enabled
	if enabled:
		_set_marker_visibility("right_elbow_pole", false)
		_set_marker_visibility("left_elbow_pole", false)


func set_selected_target(target_id: StringName) -> void:
	selected_target = target_id
	_refresh_target_styles("")


func set_hovered_target(target_id: StringName) -> void:
	if hovered_target == target_id:
		return
	hovered_target = target_id
	_refresh_target_styles("")


func _draw_lines(
	right_shoulder: Vector3,
	right_elbow_joint: Vector3,
	right_hand: Vector3,
	right_elbow_pole: Vector3,
	left_shoulder: Vector3,
	left_elbow_joint: Vector3,
	left_hand: Vector3,
	left_elbow_pole: Vector3,
	barrel_base: Marker3D,
	muzzle: Marker3D,
	optic: Marker3D,
	placement_origin: Vector3,
	placement_direction: Vector3
) -> void:
	line_mesh.clear_surfaces()
	line_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	if elbow_guides_visible and hand_guides_active and not preview_reference_mode:
		# Gunsmith parity: cyan follows the real arm bones. Pink/purple only
		# points from the shoulder to its bend control; it never draws a
		# misleading pole-to-hand triangle.
		_segment(left_shoulder, left_elbow_joint, Color(0.1, 0.95, 1.0))
		_segment(left_elbow_joint, left_hand, Color(0.1, 0.95, 1.0))
		_segment(left_shoulder, left_elbow_pole, Color(0.75, 0.35, 1.0))
	if barrel_base and muzzle:
		var barrel_direction := (muzzle.global_position - barrel_base.global_position).normalized()
		_segment(barrel_base.global_position, muzzle.global_position + barrel_direction * 5.0, Color(1.0, 0.12, 0.08))
		if optic:
			_segment(optic.global_position, optic.global_position + barrel_direction * 5.0, Color(0.15, 1.0, 0.18))
	if placement_direction.length_squared() > 0.5:
		_segment(placement_origin, placement_origin + placement_direction * 8.0, Color(0.25, 0.55, 1.0))
	line_mesh.surface_end()


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
	line_mesh.surface_set_color(color)
	line_mesh.surface_add_vertex(from)
	line_mesh.surface_set_color(color)
	line_mesh.surface_add_vertex(to)


func _build_marker(marker_id: String, node_name: String, color: Color, radius: float) -> void:
	var marker := MeshInstance3D.new()
	marker.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 110
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	markers[marker_id] = marker
	marker_base_colors[marker_id] = color


func _refresh_target_styles(selected_bone: String) -> void:
	for raw_marker_id in markers.keys():
		var marker_id := String(raw_marker_id)
		var marker := markers[raw_marker_id] as MeshInstance3D
		if marker == null:
			continue
		var active := String(selected_target) == marker_id
		var hovered := String(hovered_target) == marker_id
		marker.scale = Vector3.ONE * (1.65 if active else 1.35 if hovered else 1.0)
		var material := marker.material_override as StandardMaterial3D
		if material:
			material.albedo_color = (
				Color.WHITE
				if active or hovered
				else marker_base_colors.get(marker_id, Color.WHITE)
			)
	for raw_bone_name in fine_joint_markers.keys():
		var bone_name := String(raw_bone_name)
		var fine_marker := fine_joint_markers[raw_bone_name] as MeshInstance3D
		if fine_marker == null:
			continue
		var fine_active := bone_name == selected_bone
		var fine_hovered := String(hovered_target) == "bone:%s" % bone_name
		fine_marker.scale = Vector3.ONE * (
			1.65 if fine_active else 1.35 if fine_hovered else 1.0
		)
		var fine_material := fine_marker.material_override as StandardMaterial3D
		if fine_material:
			var logical_name := CORRECTION_OVERLAY.joint_name_for_bone(bone_name)
			fine_material.albedo_color = (
				Color.WHITE
				if fine_active or fine_hovered
				else _fine_joint_color(StringName(logical_name))
			)


func _update_fine_joint_markers(skeleton: Skeleton3D, selected_bone: String) -> void:
	_ensure_fine_joint_markers(skeleton)
	for raw_bone_name in fine_joint_markers.keys():
		var bone_name := String(raw_bone_name)
		var marker := fine_joint_markers[raw_bone_name] as MeshInstance3D
		var bone_index := skeleton.find_bone(bone_name)
		marker.visible = bone_index >= 0
		if bone_index < 0:
			continue
		marker.global_position = (
			skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
		).origin
		var logical_name := CORRECTION_OVERLAY.joint_name_for_bone(bone_name)
		var base_color := _fine_joint_color(StringName(logical_name))
		var material := marker.material_override as StandardMaterial3D
		if material:
			material.albedo_color = Color.WHITE if bone_name == selected_bone else base_color
		marker.scale = Vector3.ONE * (1.55 if bone_name == selected_bone else 1.0)


func _ensure_fine_joint_markers(skeleton: Skeleton3D) -> void:
	var skeleton_id := skeleton.get_instance_id()
	if fine_joint_skeleton_id == skeleton_id and not fine_joint_markers.is_empty():
		return
	for marker in fine_joint_markers.values():
		if is_instance_valid(marker):
			(marker as Node).queue_free()
	fine_joint_markers.clear()
	fine_joint_skeleton_id = skeleton_id
	var used_logical_joints: Dictionary = {}
	for bone_index in range(skeleton.get_bone_count()):
		var bone_name := String(skeleton.get_bone_name(bone_index))
		if _is_finger_bone(bone_name):
			continue
		var logical_name := StringName(
			CORRECTION_OVERLAY.joint_name_for_bone(bone_name)
		)
		if logical_name == &"" or logical_name not in JOINT_SCHEMA.SELECTABLE_JOINTS:
			continue
		if used_logical_joints.has(logical_name):
			continue
		used_logical_joints[logical_name] = true
		var marker := _build_fine_joint_marker(
			"FineJoint_%s" % String(logical_name),
			_fine_joint_color(logical_name)
		)
		fine_joint_markers[bone_name] = marker


func _build_fine_joint_marker(node_name: String, color: Color) -> MeshInstance3D:
	var marker := MeshInstance3D.new()
	marker.name = node_name
	var sphere := SphereMesh.new()
	sphere.radius = FINE_JOINT_RADIUS
	sphere.height = FINE_JOINT_RADIUS * 2.0
	sphere.radial_segments = 10
	sphere.rings = 5
	marker.mesh = sphere
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.no_depth_test = true
	material.render_priority = 112
	marker.material_override = material
	marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(marker)
	return marker


func _fine_joint_color(logical_name: StringName) -> Color:
	var name_text := String(logical_name)
	if "leg" in name_text:
		return Color(0.18, 0.62, 1.0)
	if "foot" in name_text:
		return Color(1.0, 0.48, 0.08)
	if "toe" in name_text:
		return Color(1.0, 0.2, 0.62)
	if logical_name == &"hips":
		return Color(0.95, 0.95, 1.0)
	return Color(0.15, 0.85, 1.0)


func _is_finger_bone(bone_name: String) -> bool:
	var lower := bone_name.to_lower()
	return (
		"thumb" in lower
		or "index" in lower
		or "middle" in lower
		or "ring" in lower
		or "pinky" in lower
	)


func _set_node_marker(marker_id: String, target: Node3D) -> void:
	_set_marker(marker_id, target.global_position if target else Vector3.ZERO, target != null)


func _set_marker(marker_id: String, world_position: Vector3, should_show: bool) -> void:
	var marker := markers.get(marker_id) as MeshInstance3D
	if marker:
		marker.visible = should_show
		marker.global_position = world_position


func _set_marker_visibility(marker_id: String, should_show: bool) -> void:
	var marker := markers.get(marker_id) as MeshInstance3D
	if marker:
		marker.visible = should_show


func _elbow_world(
	skeleton: Skeleton3D,
	shoulder_world: Vector3,
	hand_world: Vector3,
	offset: Vector3,
	is_right: bool,
	left_palm_roll_degrees: float = 0.0
) -> Vector3:
	var left_shoulder_world := _bone_world(skeleton, ["mixamorig_LeftArm", "mixamorig:LeftArm", "ArmUpper.L", "Bip01 L UpperArm"])
	var right_shoulder_world := _bone_world(skeleton, ["mixamorig_RightArm", "mixamorig:RightArm", "ArmUpper.R", "Bip01 R UpperArm"])
	var shoulder_midpoint := left_shoulder_world.lerp(right_shoulder_world, 0.5)
	var anatomical_right := (right_shoulder_world - left_shoulder_world).normalized()
	var hips_world := _bone_world(skeleton, ["mixamorig_Hips", "mixamorig:Hips", "Hips", "Bip01 Pelvis"])
	var anatomical_up := (shoulder_midpoint - hips_world).normalized()
	anatomical_up = (
		anatomical_up
		- anatomical_right * anatomical_up.dot(anatomical_right)
	).normalized()
	if anatomical_up.length_squared() < 0.5:
		anatomical_up = Vector3.UP
	var anatomical_forward := anatomical_up.cross(anatomical_right).normalized()
	var anatomical_outward := anatomical_right if is_right else -anatomical_right
	var outward := 0.28 if is_right else 0.38
	var downward := 0.08 if is_right else 0.10
	var forward := 0.10 if is_right else 0.08
	if not is_right:
		var upright_factor := (
			cos(deg_to_rad(left_palm_roll_degrees)) + 1.0
		) * 0.5
		outward = lerpf(0.24, outward, upright_factor)
		downward = lerpf(0.18, downward, upright_factor)
	return (
		shoulder_world.lerp(hand_world, 0.5)
		+ anatomical_outward * outward
		- anatomical_up * downward
		+ anatomical_forward * forward
		+ anatomical_outward * offset.x
		+ anatomical_up * offset.y
		+ anatomical_forward * offset.z
	)


func _bone_world(skeleton: Skeleton3D, candidates: Array[String]) -> Vector3:
	for candidate in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return (skeleton.global_transform * skeleton.get_bone_global_pose(index)).origin
	return skeleton.global_position


func _find_bone(skeleton: Skeleton3D, candidates: Array[String]) -> int:
	for candidate in candidates:
		var index := skeleton.find_bone(candidate)
		if index >= 0:
			return index
	return -1

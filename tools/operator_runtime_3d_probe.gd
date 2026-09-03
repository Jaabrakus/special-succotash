extends SceneTree

## Programmatic 3D inspection of the real playable operator runtime.
##
## This drives continuous simulation rather than evaluating authored still
## frames. It samples bone chains, skinned-mesh bounds, feet, hand/socket
## contact, muzzle alignment, and detached geometry while each state runs.

const OUTPUT_DIRECTORY := "/private/tmp/socom-operator-runtime-3d-probe"
const REPORT_PATH := OUTPUT_DIRECTORY + "/report.json"
const SAMPLE_FRAMES := 36
const SETTLE_FRAMES := 24
const MAX_HAND_ERROR_M := 0.010
const MAX_AIM_ERROR_DEG := 0.25
const MAX_CHAIN_STRETCH_M := 0.006
const MAX_FLOOR_PENETRATION_M := 0.10
const MAX_DETACHED_MESH_DISTANCE_M := 2.50
const MAX_SKIN_EDGE_STRETCH_RATIO := 2.50
const MIN_SKIN_EDGE_COMPRESSION_RATIO := 0.35

const LEGACY_LIMB_SEGMENTS := {
	"left_upper_arm": [&"mixamorig_LeftArm", &"mixamorig_LeftForeArm"],
	"left_forearm": [&"mixamorig_LeftForeArm", &"mixamorig_LeftHand"],
	"right_upper_arm": [&"mixamorig_RightArm", &"mixamorig_RightForeArm"],
	"right_forearm": [&"mixamorig_RightForeArm", &"mixamorig_RightHand"],
	"left_thigh": [&"mixamorig_LeftUpLeg", &"mixamorig_LeftLeg"],
	"left_shin": [&"mixamorig_LeftLeg", &"mixamorig_LeftFoot"],
	"right_thigh": [&"mixamorig_RightUpLeg", &"mixamorig_RightLeg"],
	"right_shin": [&"mixamorig_RightLeg", &"mixamorig_RightFoot"],
}

const NEW_IK_LIMB_SEGMENTS := {
	"left_upper_arm": [&"LeftUpperArm", &"LeftLowerArm"],
	"left_forearm": [&"LeftLowerArm", &"LeftHand"],
	"right_upper_arm": [&"RightUpperArm", &"RightLowerArm"],
	"right_forearm": [&"RightLowerArm", &"RightHand"],
	"left_thigh": [&"LeftUpperLeg", &"LeftLowerLeg"],
	"left_shin": [&"LeftLowerLeg", &"LeftFoot"],
	"right_thigh": [&"RightUpperLeg", &"RightLowerLeg"],
	"right_shin": [&"RightLowerLeg", &"RightFoot"],
}

var failures: Array[String] = []
var state_reports: Array[Dictionary] = []
var baseline_segments: Dictionary = {}
var review_camera: Camera3D
var scene: Node3D
var player: CharacterBody3D
var mannequin: Node3D
var driver: Node
var visual_bridge: Node3D
var skeleton: Skeleton3D
var limb_segments: Dictionary = LEGACY_LIMB_SEGMENTS


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(OUTPUT_DIRECTORY)
	root.size = Vector2i(1440, 900)
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "main scene loads")
	if packed == null:
		_finish()
		return
	scene = packed.instantiate() as Node3D
	root.add_child(scene)
	await _frames(75)
	player = scene.get_node_or_null("Player") as CharacterBody3D
	mannequin = player.get_node_or_null("Mannequin") as Node3D if player != null else null
	driver = mannequin.get_node_or_null("ProductionAnimation") if mannequin != null else null
	visual_bridge = mannequin.get_node_or_null("NewIkVisual") as Node3D if mannequin != null else null
	var forbidden_sample_root := (
		mannequin.find_child("AuthoredGodotIkVisual", true, false)
		if mannequin != null
		else null
	)
	var forbidden_sample_mesh := (
		mannequin.find_child("AnimMan", true, false)
		if mannequin != null
		else null
	)
	_expect(visual_bridge == null, "canonical player does not instantiate NewIkVisual")
	_expect(forbidden_sample_root == null, "canonical player excludes the purchased sample root")
	_expect(forbidden_sample_mesh == null, "canonical player excludes the AnimMan sample mesh")
	_expect(
		driver == null or (driver as Node3D).visible,
		"canonical ProductionAnimation remains the visible operator"
	)
	if visual_bridge != null and visual_bridge.has_method("get_visual_skeleton"):
		skeleton = visual_bridge.call("get_visual_skeleton") as Skeleton3D
		limb_segments = NEW_IK_LIMB_SEGMENTS
	else:
		skeleton = driver.get("skeleton") as Skeleton3D if driver != null else null
	_expect(player != null and mannequin != null and driver != null, "real playable operator runtime exists")
	_expect(skeleton != null, "production skeleton exists")
	if player == null or mannequin == null or driver == null or skeleton == null:
		_finish()
		return
	if OS.get_cmdline_user_args().has("--identity-only"):
		_finish()
		return
	# The production mannequin normally mirrors the real Player every frame.
	# Suspend only that input-copy callback so this diagnostic can feed explicit
	# states; the child production driver and full pose pipeline keep processing.
	mannequin.set_process(false)
	if mannequin.has_method("set_proxy_visuals_visible"):
		mannequin.call("set_proxy_visuals_visible", false)
	if OS.get_cmdline_user_args().has("--rest-pose"):
		# Diagnostic isolation only: prove whether the imported Skin is valid before
		# any gameplay animation or IK modifier is allowed to write a pose.
		driver.set_process(false)
		driver.set_physics_process(false)
		var runtime_player := driver.get("animation_player") as AnimationPlayer
		if runtime_player != null:
			runtime_player.stop()
		skeleton.reset_bone_poses()
		skeleton.force_update_all_bone_transforms()
	_hide_canvas(scene)
	_install_review_camera()
	baseline_segments = _segment_lengths()
	for state in _probe_states():
		await _run_state(state)
	_finish()


func _probe_states() -> Array[Dictionary]:
	var states: Array[Dictionary] = [
		{"name": "idle_carry", "direction": Vector2.ZERO, "posture": &"STANDING", "ready": 0.0, "speed": 0.0, "gait": &"WALK", "firing": false, "movement_state": &"STANDING"},
		{"name": "aim_idle", "direction": Vector2.ZERO, "posture": &"STANDING", "ready": 1.0, "speed": 0.0, "gait": &"WALK", "firing": false, "movement_state": &"STANDING"},
		{"name": "walk_forward_aim", "direction": Vector2(0.0, -1.0), "posture": &"STANDING", "ready": 1.0, "speed": 0.45, "gait": &"WALK", "firing": false},
		{"name": "sprint_forward_left", "direction": Vector2(-0.707, -0.707), "posture": &"STANDING", "ready": 0.0, "speed": 1.0, "gait": &"FULL", "firing": false},
		{"name": "moving_fire", "direction": Vector2(0.0, -1.0), "posture": &"STANDING", "ready": 1.0, "speed": 0.55, "gait": &"WALK", "firing": true, "fire_event": true},
		{"name": "jump_fire", "direction": Vector2(0.0, -1.0), "posture": &"STANDING", "ready": 1.0, "speed": 0.55, "gait": &"WALK", "firing": true, "fire_event": true, "movement_state": &"AIRBORNE", "vertical_speed": 4.0},
		{"name": "reload_standing", "direction": Vector2.ZERO, "posture": &"STANDING", "ready": 1.0, "speed": 0.0, "gait": &"WALK", "firing": false, "reload": true, "movement_state": &"STANDING"},
		{"name": "moving_reload", "direction": Vector2(0.0, -1.0), "posture": &"STANDING", "ready": 1.0, "speed": 0.55, "gait": &"WALK", "firing": false, "reload": true, "movement_state": &"LOCOMOTION"},
		{"name": "crouch_aim", "direction": Vector2.ZERO, "posture": &"CROUCHED", "ready": 1.0, "speed": 0.0, "gait": &"WALK", "firing": false, "movement_state": &"CROUCHED"},
		{"name": "prone_aim", "direction": Vector2.ZERO, "posture": &"PRONE", "ready": 1.0, "speed": 0.0, "gait": &"WALK", "firing": false, "movement_state": &"PRONE"},
	]
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--state="):
			var requested := argument.trim_prefix("--state=")
			return states.filter(func(state: Dictionary) -> bool:
				return String(state.get("name", "")) == requested
			)
	return states


func _run_state(state: Dictionary) -> void:
	# Every state begins from cleared transient presentation ownership. This is
	# part of the probe itself: a reload/fire action must not contaminate the
	# following crouch or prone sample.
	if driver.has_method("cancel_reload_action"):
		driver.call("cancel_reload_action")
	if driver.has_method("clear_fire_ready_aim"):
		driver.call("clear_fire_ready_aim")
	var state_name := String(state.name)
	var direction := Vector2(state.direction)
	var posture := StringName(state.posture)
	var ready := float(state.ready)
	var speed := float(state.speed)
	var gait := StringName(state.gait)
	var firing := bool(state.firing)
	var movement_state := StringName(state.get("movement_state", &"LOCOMOTION"))
	var vertical_speed := float(state.get("vertical_speed", 0.0))
	var target := player.global_position + Vector3(0.0, 1.35, -25.0)
	driver.call(
		"set_visual_inputs",
		direction,
		posture,
		vertical_speed,
		0.0,
		ready,
		firing,
		0.0,
		speed,
		movement_state,
		0.0,
		gait,
		speed * 5.0,
		target,
		direction,
		direction.length(),
		&"SUSTAINED" if speed > 0.0 else &"IDLE",
		0.0
	)
	if bool(state.get("fire_event", false)):
		mannequin.call("notify_operator_fired")
	if bool(state.get("reload", false)):
		mannequin.call("play_operator_semantic_action_timed", &"reload", 1.75, 0.12)
	await _frames(SETTLE_FRAMES)
	var report := {
		"state": state_name,
		"expected_posture": String(posture),
		"samples": SAMPLE_FRAMES,
		"max_trigger_hand_error_m": 0.0,
		"max_support_hand_error_m": 0.0,
		"max_weapon_aim_error_deg": 0.0,
		"max_limb_stretch_m": 0.0,
		"max_foot_lock_slip_cm": 0.0,
		"minimum_mesh_floor_offset_m": INF,
		"maximum_mesh_center_distance_m": 0.0,
		"non_finite_transforms": 0,
		"maximum_skin_edge_stretch_ratio": 1.0,
		"minimum_skin_edge_compression_ratio": 1.0,
		"worst_skin_mesh": "",
		"skin_strain_by_mesh": {},
		"logical_clip": "",
		"presentation_posture": "",
	}
	for _sample in range(SAMPLE_FRAMES):
		await physics_frame
		_sample_runtime(report)
	_sample_skin_deformation(report)
	state_reports.append(report)
	_validate_state(report)
	await _capture_state(state_name)
	print("OPERATOR_RUNTIME_3D_STATE %s" % JSON.stringify(report))


func _sample_runtime(report: Dictionary) -> void:
	var debug: Dictionary = driver.call("get_animation_debug_state")
	report.logical_clip = String(debug.get("logical_clip", ""))
	report.presentation_posture = String(debug.get("presentation_posture", ""))
	var pose: Dictionary = debug.get("weapon_pose", {})
	var authored_graph: Dictionary = debug.get("authored_ik_graph", {})
	if not authored_graph.is_empty():
		var attachment: Dictionary = authored_graph.get("weapon_attachment", {})
		var support: Dictionary = authored_graph.get("support_contact", {})
		report.max_trigger_hand_error_m = maxf(
			float(report.max_trigger_hand_error_m),
			float(attachment.get("trigger_contact_error_m", INF))
		)
		report.max_support_hand_error_m = maxf(
			float(report.max_support_hand_error_m),
			float(support.get("contact_error_m", INF))
		)
		var connected_aim_dot := clampf(
			float(authored_graph.get("connected_arm_aim_dot", -1.0)),
			-1.0,
			1.0
		)
		report.max_weapon_aim_error_deg = maxf(
			float(report.max_weapon_aim_error_deg),
			rad_to_deg(acos(connected_aim_dot))
		)
		_sample_body_runtime(report, debug)
		return
	report.max_trigger_hand_error_m = maxf(
		float(report.max_trigger_hand_error_m),
		float(pose.get("trigger_hand_error_m", 0.0))
	)
	report.max_support_hand_error_m = maxf(
		float(report.max_support_hand_error_m),
		float(pose.get("support_hand_error_m", 0.0))
	)
	report.max_weapon_aim_error_deg = maxf(
		float(report.max_weapon_aim_error_deg),
		float(pose.get("weapon_aim_error_deg", 0.0))
	)
	_sample_body_runtime(report, debug)


func _sample_body_runtime(report: Dictionary, debug: Dictionary) -> void:
	var foot_lock: Dictionary = debug.get("foot_contact_lock", {})
	if bool(foot_lock.get("active", false)):
		report.max_foot_lock_slip_cm = maxf(
			float(report.max_foot_lock_slip_cm),
			float(foot_lock.get("world_slip_cm", 0.0))
		)
	var lengths := _segment_lengths()
	for segment_name in baseline_segments:
		report.max_limb_stretch_m = maxf(
			float(report.max_limb_stretch_m),
			absf(float(lengths.get(segment_name, 0.0)) - float(baseline_segments[segment_name]))
		)
	for mesh in _production_meshes():
		var bounds := _mesh_world_bounds(mesh)
		report.minimum_mesh_floor_offset_m = minf(
			float(report.minimum_mesh_floor_offset_m),
			float(bounds.position.y - player.global_position.y)
		)
		var center := bounds.get_center()
		report.maximum_mesh_center_distance_m = maxf(
			float(report.maximum_mesh_center_distance_m),
			center.distance_to(player.global_position + Vector3.UP)
		)
		if not _finite_transform(mesh.global_transform):
			report.non_finite_transforms = int(report.non_finite_transforms) + 1


func _segment_lengths() -> Dictionary:
	var result: Dictionary = {}
	for segment_name in limb_segments:
		var bones: Array = limb_segments[segment_name]
		var first: int = skeleton.find_bone(StringName(bones[0]))
		var second: int = skeleton.find_bone(StringName(bones[1]))
		if first < 0 or second < 0:
			failures.append("missing limb segment %s" % segment_name)
			continue
		var first_position := (skeleton.global_transform * skeleton.get_bone_global_pose(first)).origin
		var second_position := (skeleton.global_transform * skeleton.get_bone_global_pose(second)).origin
		result[segment_name] = first_position.distance_to(second_position)
	return result


func _production_meshes() -> Array[MeshInstance3D]:
	var output: Array[MeshInstance3D] = []
	if visual_bridge != null:
		var visual_root := visual_bridge.get("visual_root") as Node
		if visual_root != null:
			_collect_meshes(visual_root, output)
			return output
	var model_root := driver.get("model_root") as Node
	if model_root != null:
		_collect_meshes(model_root, output)
	return output


func _collect_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D and (node as MeshInstance3D).mesh != null:
		output.append(node as MeshInstance3D)
	for child in node.get_children():
		_collect_meshes(child, output)


func _mesh_world_bounds(mesh: MeshInstance3D) -> AABB:
	var local := mesh.get_aabb()
	var points: Array[Vector3] = [
		Vector3(local.position.x, local.position.y, local.position.z),
		Vector3(local.end.x, local.position.y, local.position.z),
		Vector3(local.position.x, local.end.y, local.position.z),
		Vector3(local.position.x, local.position.y, local.end.z),
		Vector3(local.end.x, local.end.y, local.position.z),
		Vector3(local.end.x, local.position.y, local.end.z),
		Vector3(local.position.x, local.end.y, local.end.z),
		local.end,
	]
	var first: Vector3 = mesh.global_transform * points[0]
	var result := AABB(first, Vector3.ZERO)
	for point in points.slice(1):
		result = result.expand(mesh.global_transform * Vector3(point))
	return result


func _finite_transform(value: Transform3D) -> bool:
	for component in [
		value.origin.x, value.origin.y, value.origin.z,
		value.basis.x.x, value.basis.x.y, value.basis.x.z,
		value.basis.y.x, value.basis.y.y, value.basis.y.z,
		value.basis.z.x, value.basis.z.y, value.basis.z.z,
	]:
		if is_nan(float(component)) or is_inf(float(component)):
			return false
	return true


func _sample_skin_deformation(report: Dictionary) -> void:
	for mesh_instance in _production_meshes():
		var skin := mesh_instance.skin
		var mesh := mesh_instance.mesh
		if skin == null or mesh == null or skin.get_bind_count() == 0:
			continue
		var bind_transforms: Array[Transform3D] = []
		for bind_index in skin.get_bind_count():
			var bone_index := -1
			var bind_name := skin.get_bind_name(bind_index)
			if bind_name != &"":
				bone_index = skeleton.find_bone(bind_name)
			if bone_index < 0:
				bone_index = skin.get_bind_bone(bind_index)
			bind_transforms.append(
				skeleton.get_bone_global_pose(bone_index) * skin.get_bind_pose(bind_index)
				if bone_index >= 0 and bone_index < skeleton.get_bone_count()
				else Transform3D.IDENTITY
			)
		var mesh_stretch := 1.0
		var mesh_compression := 1.0
		var mesh_stretch_edge: Dictionary = {}
		var mesh_compression_edge: Dictionary = {}
		for surface_index in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_index)
			if arrays.is_empty():
				continue
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			if vertices.is_empty() or bones.is_empty() or weights.is_empty():
				continue
			var influences := bones.size() / vertices.size()
			if influences <= 0:
				continue
			var deformed := PackedVector3Array()
			deformed.resize(vertices.size())
			for vertex_index in vertices.size():
				var point := Vector3.ZERO
				var weight_sum := 0.0
				for influence in influences:
					var array_index := vertex_index * influences + influence
					var weight := float(weights[array_index])
					var bind_index := int(bones[array_index])
					if weight <= 0.000001 or bind_index < 0 or bind_index >= bind_transforms.size():
						continue
					point += (bind_transforms[bind_index] * vertices[vertex_index]) * weight
					weight_sum += weight
				deformed[vertex_index] = point / weight_sum if weight_sum > 0.000001 else vertices[vertex_index]
			var triangle_indices := indices
			if triangle_indices.is_empty():
				triangle_indices.resize(vertices.size())
				for vertex_index in vertices.size():
					triangle_indices[vertex_index] = vertex_index
			var triangle_count := triangle_indices.size() / 3
			var triangle_step := maxi(triangle_count / 2000, 1)
			for triangle in range(0, triangle_count, triangle_step):
				var base := triangle * 3
				for edge in [[0, 1], [1, 2], [2, 0]]:
					var first := int(triangle_indices[base + int(edge[0])])
					var second := int(triangle_indices[base + int(edge[1])])
					if first < 0 or second < 0 or first >= vertices.size() or second >= vertices.size():
						continue
					var rest_length := vertices[first].distance_to(vertices[second])
					if rest_length <= 0.00001:
						continue
					var deformed_length := deformed[first].distance_to(deformed[second])
					var ratio := deformed_length / rest_length
					if ratio > mesh_stretch:
						mesh_stretch = ratio
						mesh_stretch_edge = _skin_edge_report(
							surface_index, first, second, rest_length, deformed_length,
							bones, weights, influences, skin
						)
					if ratio < mesh_compression:
						mesh_compression = ratio
						mesh_compression_edge = _skin_edge_report(
							surface_index, first, second, rest_length, deformed_length,
							bones, weights, influences, skin
						)
					if ratio > float(report.maximum_skin_edge_stretch_ratio):
						report.maximum_skin_edge_stretch_ratio = ratio
						report.worst_skin_mesh = String(mesh_instance.name)
					report.minimum_skin_edge_compression_ratio = minf(
						float(report.minimum_skin_edge_compression_ratio),
						ratio
					)
		var by_mesh: Dictionary = report.skin_strain_by_mesh
		by_mesh[String(mesh_instance.name)] = {
			"maximum_stretch_ratio": mesh_stretch,
			"minimum_compression_ratio": mesh_compression,
			"worst_stretch_edge": mesh_stretch_edge,
			"worst_compression_edge": mesh_compression_edge,
		}


func _skin_edge_report(
	surface_index: int,
	first: int,
	second: int,
	rest_length: float,
	deformed_length: float,
	bones: PackedInt32Array,
	weights: PackedFloat32Array,
	influences: int,
	skin: Skin
) -> Dictionary:
	var vertices: Array[Dictionary] = []
	for vertex_index in [first, second]:
		var vertex_influences: Array[Dictionary] = []
		for influence in influences:
			var array_index: int = int(vertex_index) * influences + influence
			var weight := float(weights[array_index])
			var bind_index := int(bones[array_index])
			if weight <= 0.000001 or bind_index < 0 or bind_index >= skin.get_bind_count():
				continue
			vertex_influences.append({
				"bind": String(skin.get_bind_name(bind_index)),
				"weight": weight,
			})
		vertices.append({"index": vertex_index, "influences": vertex_influences})
	return {
		"surface": surface_index,
		"vertices": vertices,
		"rest_length_m": rest_length,
		"deformed_length_m": deformed_length,
	}


func _validate_state(report: Dictionary) -> void:
	var name := String(report.state)
	_expect(float(report.max_limb_stretch_m) <= MAX_CHAIN_STRETCH_M, "%s keeps fixed limb lengths" % name)
	_expect(float(report.minimum_mesh_floor_offset_m) >= -MAX_FLOOR_PENETRATION_M, "%s mesh stays above floor budget" % name)
	_expect(float(report.maximum_mesh_center_distance_m) <= MAX_DETACHED_MESH_DISTANCE_M, "%s has no detached mesh section" % name)
	_expect(int(report.non_finite_transforms) == 0, "%s transforms remain finite" % name)
	_expect(
		float(report.maximum_skin_edge_stretch_ratio) <= MAX_SKIN_EDGE_STRETCH_RATIO,
		"%s skin edges stay within stretch budget" % name
	)
	_expect(
		float(report.minimum_skin_edge_compression_ratio) >= MIN_SKIN_EDGE_COMPRESSION_RATIO,
		"%s skin edges stay within compression budget" % name
	)
	_expect(
		String(report.presentation_posture) == String(report.expected_posture),
		"%s reaches requested posture" % name
	)
	if name in ["aim_idle", "walk_forward_aim", "moving_fire", "jump_fire", "crouch_aim", "prone_aim"]:
		_expect(float(report.max_trigger_hand_error_m) <= MAX_HAND_ERROR_M, "%s trigger palm remains attached" % name)
		_expect(float(report.max_support_hand_error_m) <= MAX_HAND_ERROR_M, "%s support palm remains attached" % name)
		_expect(float(report.max_weapon_aim_error_deg) <= MAX_AIM_ERROR_DEG, "%s rendered bore follows aim" % name)


func _install_review_camera() -> void:
	var active := root.get_viewport().get_camera_3d()
	if active != null:
		active.current = false
	review_camera = Camera3D.new()
	review_camera.name = "Programmatic3DProbeCamera"
	review_camera.fov = 42.0
	review_camera.current = true
	review_camera.set_cull_mask_value(20, false)
	scene.add_child(review_camera)


func _capture_state(state_name: String) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var target := player.global_position + Vector3.UP * 1.15
	var views := {
		"rear": Vector3(1.30, 1.55, 2.35),
		"side": Vector3(2.55, 1.45, 0.10),
		"front": Vector3(-0.90, 1.50, -2.35),
	}
	for view_name in views:
		review_camera.global_position = player.global_position + Vector3(views[view_name])
		review_camera.look_at(target, Vector3.UP)
		await _frames(3)
		RenderingServer.force_draw()
		await process_frame
		var image := root.get_texture().get_image()
		if image == null or image.is_empty():
			failures.append("%s %s capture" % [state_name, view_name])
			continue
		var path := "%s/%s_%s.png" % [OUTPUT_DIRECTORY, state_name, view_name]
		if image.save_png(path) != OK:
			failures.append("%s %s capture save" % [state_name, view_name])


func _hide_canvas(node: Node) -> void:
	if node is CanvasLayer:
		(node as CanvasLayer).visible = false
	for child in node.get_children():
		_hide_canvas(child)


func _frames(count: int) -> void:
	for _frame in range(count):
		await process_frame


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("OPERATOR_RUNTIME_3D_PROBE PASS %s" % label)
		return
	if label not in failures:
		failures.append(label)
	push_error("OPERATOR_RUNTIME_3D_PROBE FAIL %s" % label)


func _finish() -> void:
	var report := {
		"schema": "socom_operator_runtime_3d_probe_v1",
		"continuous_simulation": true,
		"state_reports": state_reports,
		"failures": failures,
		"passed": failures.is_empty(),
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "  "))
	print("OPERATOR_RUNTIME_3D_PROBE_REPORT %s" % REPORT_PATH)
	quit(0 if failures.is_empty() else 1)

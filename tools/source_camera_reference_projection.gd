extends SceneTree
## Offline observer only. Raw-source projection is conditional on root processing.

const SOURCE := "/Users/kiwimango/Downloads/SOCOM-II-animation-extractor/output/"
const SKELETON_HASH := "26e991e38bb09147c54ce3062116466fef3225e76b5e6771da619d56e625c551"
const CAMERA = preload("res://scripts/camera/source_gameplay_camera.gd")
const METRES := 0.10000000149011612
const HFOV := 69.99999967119774
const LANDMARKS := {"Hips": "hips", "Spine": "spinelo", "Spine2": "spinehi",
	"Neck": "neck", "Head": "head", "LeftArm": "lbicep", "RightArm": "rbicep",
	"LeftHand": "lhand", "RightHand": "rhand", "LeftFoot": "lfoot", "RightFoot": "rfoot",
	"LeftToeBase": "ltoe", "RightToeBase": "rtoe"}
const FIRST_CAMERA := {"seal_stand": Vector3(2.9296875, 21.484375, 26.96875),
	"seal_stand_alert02": Vector3(-0.203125, 21.22265625, 28.44140625),
	"seal_crouch": Vector3(-0.7734375, 15.377867016675737, 35.48828125),
	"seal_prone": Vector3(1.328125, 7.66796875, 26.8359375)}
var checks := 0
var report: Dictionary = {"schema_version": 1, "errors": [], "source_poses": [],
	"scope": "Conditional raw-key joint projection; NOT original runtime motion extraction or skinned visual parity",
	"horizontal_fov_degrees": HFOV, "metres_per_source_unit": METRES}
var source_nodes: Array = []
var viewport: SubViewport
var camera: Camera3D
var current_model: Node3D
var current_skeleton: Skeleton3D
var current_asset_runtime: RefCounted
const CURRENT_SLOTS := {"seal_stand": "idle_rifle", "seal_stand_alert02": "seal_stand_alert02",
	"seal_crouch": "idle_crouch", "seal_prone": "idle_prone"}


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var output := ""
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--out="): output = argument.trim_prefix("--out=")
	if not output.begins_with("/private/tmp/") or output.contains("..") or FileAccess.file_exists(output):
		push_error("A fresh --out=/private/tmp/...json is required")
		quit(1)
		return
	var skeleton_data := _json(SOURCE + "seal-skeleton.json")
	_check(FileAccess.get_sha256(SOURCE + "seal-skeleton.json") == SKELETON_HASH, "source skeleton hash")
	_check(skeleton_data.get("position_divisor") == 256, "source position divisor")
	if not report.errors.is_empty():
		_finish(output)
		return
	source_nodes = skeleton_data.nodes
	report["source_skeleton_sha256"] = SKELETON_HASH
	report["helper_sha256"] = FileAccess.get_sha256("res://scripts/camera/source_gameplay_camera.gd")
	viewport = SubViewport.new()
	viewport.own_world_3d = true
	viewport.size = Vector2i(1280, 720)
	root.add_child(viewport)
	camera = Camera3D.new()
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	viewport.add_child(camera)
	camera.make_current()
	await process_frame
	var rest := _globals({}, 0)
	report["source_rest_landmarks_m"] = _points(rest, METRES)
	_measure_current_rest(rest)
	for clip: String in FIRST_CAMERA:
		var path := SOURCE + "motion/" + clip + ".json"
		var data := _json(path)
		if data.is_empty(): continue
		_check(int(data.frames) > 0 and int(data.samples) == int(data.frames) + 1, clip + " sample layout")
		var indices := [0, int(data.frames) / 2, int(data.frames)]
		for index: int in indices:
			var pose := _globals(data, index)
			if pose.is_empty(): continue
			var root_source: Vector3 = pose.skel_root.origin
			var row := {"clip": clip, "source_sha256": FileAccess.get_sha256(path), "sample": index,
				"time_seconds": float(index) * float(data.duration) / float(data.frames),
				"root_source": _vec(root_source), "landmarks_source": _points(pose, 1.0),
				"projections": []}
			for pitch in [0.0, deg_to_rad(-20.0), deg_to_rad(20.0)]:
				var preferred: Dictionary = CAMERA.source_preferred_pose(root_source, pitch, 0.0)
				_check(not preferred.is_empty(), clip + " preferred pose")
				if preferred.is_empty(): continue
				if index == 0 and pitch == 0.0:
					_check(preferred.position_source.distance_to(FIRST_CAMERA[clip]) < 0.00001, clip + " independent first-key camera fixture")
				var projection := {"pitch_radians": pitch, "camera_source": _vec(preferred.position_source),
					"pivot_source": _vec(preferred.pivot_source), "camera_m": _vec(preferred.position_source * METRES),
					"radius_source": preferred.radius_source, "viewports": []}
				camera.position = preferred.position_source * METRES
				camera.look_at(preferred.far_target_source * METRES, Vector3.UP)
				for dimensions in [Vector2i(1280, 720), Vector2i(1280, 960)]:
					viewport.size = dimensions
					camera.fov = CAMERA.vertical_fov(HFOV, float(dimensions.x) / dimensions.y)
					var samples := {}
					var maximum_pixel_error := 0.0
					for name in ["skel_root", "hips", "spinehi", "head", "lfoot", "rfoot"]:
						var world: Vector3 = pose[name].origin * METRES
						var pixel := camera.unproject_position(world)
						var independent := _pinhole(world, dimensions)
						var error := pixel.distance_to(independent)
						maximum_pixel_error = maxf(maximum_pixel_error, error)
						_check(pixel.is_finite() and not camera.is_position_behind(world), clip + " finite/front " + name)
						_check(error < 0.002, clip + " pinhole/Camera3D agreement " + name)
						samples[name] = {"pixel": [pixel.x, pixel.y],
							"uv": [pixel.x / dimensions.x, pixel.y / dimensions.y]}
					projection.viewports.append({"width": dimensions.x, "height": dimensions.y,
						"vertical_fov_degrees": camera.fov, "joints": samples,
						"max_independent_pixel_error": maximum_pixel_error})
				row.projections.append(projection)
			row["ordinary_root_xz_cleared_comparison"] = _processed_comparison(clip, data, index, pose)
			report.source_poses.append(row)
	if current_model != null: current_model.free()
	viewport.free()
	_finish(output)


func _globals(animation: Dictionary, sample_index: int) -> Dictionary:
	var channels := {}
	for track: Dictionary in animation.get("tracks", []): channels[track.name] = track
	var globals := {}
	for node: Dictionary in source_nodes:
		var m: Array = node.matrix_column_major
		var local := Transform3D(Basis(Vector3(m[0], m[1], m[2]), Vector3(m[4], m[5], m[6]),
			Vector3(m[8], m[9], m[10])), Vector3(m[12], m[13], m[14]))
		if channels.has(node.name):
			var channel: Dictionary = channels[node.name]
			for kind in ["positions_raw", "rotations_raw"]:
				var values: Array = channel[kind]
				if values.size() != 1 and values.size() != int(animation.samples):
					_check(false, "invalid channel length: " + str(node.name))
					return {}
				var value: Array = values[0 if values.size() == 1 else sample_index]
				if kind == "positions_raw":
					local.origin = Vector3(value[0], value[1], value[2]) / 256.0
				else:
					var rotation := Quaternion(value[0], value[1], value[2], value[3])
					if not rotation.is_finite() or rotation.length_squared() <= 0.0:
						_check(false, "invalid source quaternion: " + str(node.name))
						return {}
					local.basis = Basis(rotation.normalized())
		if node.parent != null:
			if not globals.has(node.parent):
				_check(false, "source nodes not parent ordered")
				return {}
			local = globals[node.parent] * local
		globals[node.name] = local
	return globals


func _measure_current_rest(rest: Dictionary) -> void:
	var selection := _json("res://config/operator_character.json")
	var tuning := _json("res://config/operator_movement_tuning.json")
	var path: String = selection.scene
	var model := load(path).instantiate() as Node3D
	root.add_child(model)
	# Same saved presentation convention as the current operator driver.
	model.rotation.y = PI
	var scale_value: float = tuning.animation.operator_scale_by_scene.get(path, tuning.animation.operator_scale)
	model.scale = Vector3.ONE * scale_value
	var matches := model.find_children("*", "Skeleton3D", true, false)
	_check(matches.size() == 1, "current selected scene has one canonical skeleton")
	if matches.size() != 1:
		model.free()
		return
	var skeleton := matches[0] as Skeleton3D
	var points := {}
	for canonical: String in LANDMARKS:
		var bone := skeleton.find_bone("mixamorig_" + canonical)
		_check(bone >= 0, "current rest landmark exists: " + canonical)
		if bone < 0: continue
		points[canonical] = skeleton.global_transform * skeleton.get_bone_global_rest(bone).origin
	var source_ankle: Vector3 = (rest.lfoot.origin + rest.rfoot.origin) * 0.5 * METRES
	var modern_ankle: Vector3 = (points.LeftFoot + points.RightFoot) * 0.5
	var rest_translation := modern_ankle - source_ankle
	var residuals := {}
	var maximum_residual := 0.0
	for canonical: String in LANDMARKS:
		var original: Vector3 = rest[LANDMARKS[canonical]].origin * METRES
		var residual: Vector3 = points[canonical] - original - rest_translation
		maximum_residual = maxf(maximum_residual, residual.length())
		residuals[canonical] = {"current_m": _vec(points[canonical]), "source_m": _vec(original),
			"difference_m": _vec(points[canonical] - original), "residual_after_rest_translation_m": _vec(residual)}
	var source_span: float = rest.head.origin.y * METRES - source_ankle.y
	var modern_span: float = points.Head.y - modern_ankle.y
	_check(absf(source_span - modern_span) < 0.00002, "source/modern head-to-ankle scale")
	_check(maximum_residual < 0.00003, "modern landmark translation-only rest correspondence")
	report["modern_rest_comparison"] = {"scene": path, "scene_sha256": FileAccess.get_sha256(path),
		"selection_sha256": FileAccess.get_sha256("res://config/operator_character.json"),
		"tuning_sha256": FileAccess.get_sha256("res://config/operator_movement_tuning.json"),
		"configured_scale": scale_value, "source_average_ankle_m": _vec(source_ankle),
		"modern_average_ankle_m": _vec(modern_ankle), "modern_minus_source_rest_translation_m": _vec(rest_translation),
		"source_head_to_ankle_m": source_span, "modern_head_to_ankle_m": modern_span,
		"maximum_landmark_residual_m": maximum_residual, "landmarks": residuals,
		"scope": "Fresh selected-asset REST only. Not an animated camera anchor correction or source skin comparison."}
	# Same build-time pipeline as main, on a separate temporary scene only.
	# This is not a claim that a manually sampled clone includes live pose layers.
	current_model = model
	current_skeleton = skeleton
	var profile := preload("res://scripts/player/operator_animation_profile.gd").new()
	profile.load_project_map()
	current_asset_runtime = preload("res://scripts/player/operator_asset_runtime.gd").new()
	current_asset_runtime.model_root = model
	current_asset_runtime.skeleton = skeleton
	current_asset_runtime.operator_scale = scale_value
	current_asset_runtime.profile = profile
	current_asset_runtime.animation_player = AnimationPlayer.new()
	skeleton.add_child(current_asset_runtime.animation_player)
	current_asset_runtime._build_animation_library()
	report["animation_map_sha256"] = FileAccess.get_sha256("res://config/operator_animation_map.json")


func _processed_comparison(clip: String, data: Dictionary, sample_index: int, raw_pose: Dictionary) -> Dictionary:
	var translation: Vector3 = raw_pose.skel_root.origin
	translation.y = 0.0
	var original := {}
	for name in raw_pose:
		var transform: Transform3D = raw_pose[name]
		# Every listed body landmark is below skel_root in the recovered tree.
		if name != "seal_A_arc" and name != "body": transform.origin -= translation
		original[name] = transform
	var preferred: Dictionary = CAMERA.source_preferred_pose(original.skel_root.origin, 0.0, 0.0)
	camera.position = preferred.position_source * METRES
	camera.look_at(preferred.far_target_source * METRES, Vector3.UP)
	var slot: String = CURRENT_SLOTS[clip]
	if not current_asset_runtime.animation_library.has_animation(slot):
		_check(false, "missing current clip " + slot)
		return {}
	var animation: Animation = current_asset_runtime.animation_library.get_animation(slot).duplicate()
	_check(animation.get_meta("source_name", "") == clip, "same original source clip " + slot)
	_check(animation.get_meta("source_sha256", "") == FileAccess.get_sha256(SOURCE + "motion/" + clip + ".json"), "same original source hash " + slot)
	var time := float(sample_index) / float(data.frames) * animation.length
	animation.loop_mode = Animation.LOOP_NONE
	current_skeleton.reset_bone_poses()
	for track in animation.get_track_count():
		var path := animation.track_get_path(track)
		if path.get_subname_count() != 1: continue
		var bone := current_skeleton.find_bone(path.get_subname(0))
		if bone < 0: continue
		match animation.track_get_type(track):
			Animation.TYPE_POSITION_3D:
				current_skeleton.set_bone_pose_position(bone, animation.position_track_interpolate(track, time))
			Animation.TYPE_ROTATION_3D:
				current_skeleton.set_bone_pose_rotation(bone, animation.rotation_track_interpolate(track, time))
			Animation.TYPE_SCALE_3D:
				current_skeleton.set_bone_pose_scale(bone, animation.scale_track_interpolate(track, time))
	current_skeleton.force_update_all_bone_transforms()
	var modern := {}
	for canonical in LANDMARKS:
		var bone := current_skeleton.find_bone("mixamorig_" + canonical)
		modern[LANDMARKS[canonical]] = current_skeleton.global_transform * current_skeleton.get_bone_global_pose(bone).origin
	var result := {"scope": "Ordinary source X/Z zeroing and static-stance Y preservation proven. Current saved per-clip clone excludes live blend/aim layers. Passing this observer does not mean pose parity.",
		"original_root_processing": "ZSeal57b1d0/57b1e0 XZclear;59b870 ordinary Y retained except Ladderslide",
		"current_slot": slot, "current_sample_time": time, "current_clip_length": animation.length,
		"original_clip_length": data.duration, "source_root": _vec(original.skel_root.origin),
		"source_camera_m": _vec(preferred.position_source * METRES), "landmarks": {}, "viewports": []}
	var maximum_landmark_difference := 0.0
	for name in ["head", "spinehi", "hips", "lfoot", "rfoot"]:
		var source_point: Vector3 = original[name].origin * METRES
		var target_point: Vector3 = modern[name]
		_check(source_point.is_finite() and target_point.is_finite(), "finite sampled counterpart " + name)
		maximum_landmark_difference = maxf(maximum_landmark_difference, source_point.distance_to(target_point))
		result.landmarks[name] = {"original_m": _vec(source_point), "current_m": _vec(target_point),
			"current_minus_original_m": _vec(target_point - source_point)}
	result["maximum_animated_landmark_difference_m"] = maximum_landmark_difference
	result["animated_landmark_parity_within_1mm"] = maximum_landmark_difference <= 0.001
	for dimensions in [Vector2i(1280, 720), Vector2i(1280, 800), Vector2i(1280, 960)]:
		viewport.size = dimensions
		camera.fov = CAMERA.vertical_fov(HFOV, float(dimensions.x) / dimensions.y)
		var points := {}
		for name in ["head", "spinehi", "hips", "lfoot", "rfoot"]:
			var source_pixel := camera.unproject_position(original[name].origin * METRES)
			var modern_pixel := camera.unproject_position(modern[name])
			points[name] = {"original_uv": [source_pixel.x / dimensions.x, source_pixel.y / dimensions.y],
				"current_uv": [modern_pixel.x / dimensions.x, modern_pixel.y / dimensions.y]}
		result.viewports.append({"width": dimensions.x, "height": dimensions.y, "joints": points})
	return result


func _pinhole(world: Vector3, dimensions: Vector2i) -> Vector2:
	var local := camera.global_transform.affine_inverse() * world
	var focal := float(dimensions.x) * 0.5 / tan(deg_to_rad(HFOV) * 0.5)
	return Vector2(float(dimensions.x) * 0.5 + local.x * focal / -local.z,
		float(dimensions.y) * 0.5 - local.y * focal / -local.z)


func _points(globals: Dictionary, scale_value: float) -> Dictionary:
	var result := {}
	for name in ["skel_root", "hips", "spinehi", "head", "lfoot", "rfoot", "ltoe", "rtoe"]:
		result[name] = _vec(globals[name].origin * scale_value)
	return result


func _json(path: String) -> Dictionary:
	var value: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if value is Dictionary: return value
	_check(false, "invalid JSON: " + path)
	return {}


func _vec(value: Vector3) -> Array:
	return [value.x, value.y, value.z]


func _check(success: bool, label: String) -> void:
	checks += 1
	if not success: report.errors.append(label)


func _finish(path: String) -> void:
	report["checks"] = checks
	report["passed"] = report.errors.is_empty()
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write proof report: " + path)
		quit(1)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	print("SOURCE_CAMERA_REFERENCE_PROJECTION ", "PASS" if report.passed else "FAIL",
		" checks=", checks, " poses=", report.source_poses.size(), " report=", path)
	for failure in report.errors: push_error(failure)
	quit(0 if report.passed else 1)

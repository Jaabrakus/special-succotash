extends SceneTree

## AK-only source and retarget proof. This never changes gameplay state; it
## measures the exported AGLS weapon and animation assets that the canonical
## weapon profile is allowed to reference.

const MODEL_PATH := "res://assets/external/agls_intake/imported/weapons/ak47/ak47.glb"
const CONFIG_PATH := "res://config/weapons/ak-47.json"
const ANIMATION_MAP_PATH := "res://config/operator_animation_map.json"
const OPERATOR_SCALE := 62.0
const HOLD_PATH := (
	"res://assets/external/agls_intake/imported/weapon_hold/"
	+ "ALS_Props_Rifle_AK-47_Poses.scn"
)
const RELOAD_PATH := (
	"res://assets/external/agls_intake/imported/weapon_reload/"
	+ "ALSP2_Reloading_Rifle_AK47.scn"
)
const TARGET_PATH := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const NativeRigAdapter := preload("res://scripts/player/operator_native_rig_adapter.gd")
const SkeletonContract := preload("res://scripts/player/operator_skeleton_contract.gd")
const WeaponContract := preload("res://scripts/weapons/weapon_rig_contract.gd")
const AssetRegistry := preload("res://scripts/weapons/agls_weapon_asset_registry.gd")

const REQUIRED_WEAPON_BONES: Array[String] = [
	"Root", "body", "bolt", "magazine", "bullet", "magrelease", "selector", "muzzle",
]
const CANONICAL_ARM_BONES: Array[String] = [
	"mixamorig_LeftShoulder", "mixamorig_LeftArm", "mixamorig_LeftForeArm",
	"mixamorig_LeftHand", "mixamorig_RightShoulder", "mixamorig_RightArm",
	"mixamorig_RightForeArm", "mixamorig_RightHand",
]

var failures: Array[String] = []


func _initialize() -> void:
	_inspect_saved_contract()
	_inspect_weapon_model()
	_inspect_action(HOLD_PATH, "hold", true)
	_inspect_action(RELOAD_PATH, "reload", false)
	_finish()


func _inspect_saved_contract() -> void:
	var raw := _read_json(CONFIG_PATH)
	var config := WeaponContract.load_config(CONFIG_PATH)
	_expect(not raw.is_empty(), "AK-47 canonical config is valid JSON")
	_expect(int(raw.get("schema_version", 0)) == 3, "AK-47 saves the current weapon schema")
	_expect(bool(config.get("socket_contract_authored", false)), "AK-47 physical sockets are authored")
	_expect(String(config.get("model_fbx", "")) == MODEL_PATH, "AK-47 config selects the measured AGLS GLB")
	_expect(AssetRegistry.preferred_model_path(config) == MODEL_PATH, "AGLS registry resolves the same AK-47 GLB")
	_expect(is_equal_approx(float(config.get("normalized_scale", 0.0)), 1.0), "AK-47 preserves the metre-scale export")
	_expect(
		_vector(config.get("model_rotation_degrees", {})).is_zero_approx(),
		"AK-47 mesh and physical sockets keep the exported axis frame"
	)
	var grip: Dictionary = config.get("grip_offset", {})
	_expect(
		Vector3(
			float(grip.get("rot_x", 0.0)),
			float(grip.get("rot_y", 0.0)),
			float(grip.get("rot_z", 0.0))
		).distance_to(Vector3(-32.82586, -176.2812, 70.73891)) <= 0.0001,
		"AK-47 one master mount rotates mesh and sockets into canonical aim space"
	)
	var expected_sockets := {
		"right_hand_grip_target": Vector3(0.0, 0.049863, 0.058773),
		"left_hand_ik_target": Vector3(0.045742, 0.058888, 0.247412),
		"barrel_base_socket": Vector3(0.0, 0.084590, 0.301776),
		"muzzle_socket": Vector3(0.0, 0.089968, 0.622505),
		"buttstock_socket": Vector3(0.0, 0.036564, -0.306726),
		"optic_rail": Vector3(0.0, 0.118641, 0.087364),
		"ejection_port": Vector3(0.020296, 0.102640, 0.140029),
	}
	var sockets: Dictionary = config.get("weapon_sockets", {})
	for socket_name in expected_sockets:
		_expect(
			_vector(sockets.get(socket_name, {})).distance_to(expected_sockets[socket_name])
				<= 0.000001,
			"AK-47 %s matches its measured or surface-calibrated export point" % socket_name
		)
	var support_socket := _vector(sockets.get("left_hand_ik_target", {}))
	_expect(
		support_socket.x >= 0.023 and support_socket.x <= 0.050
		and support_socket.y >= 0.050 and support_socket.y <= 0.064
		and support_socket.z >= 0.245 and support_socket.z <= 0.255,
		"AK-47 support palm sits immediately below the measured handguard surface"
	)
	var handling: Dictionary = config.get("handling_profile", {})
	var slots: Dictionary = handling.get("animation_slots", {})
	_expect(
		String(slots.get("idle_standing", "")) == "aim_idle"
		and String(slots.get("idle_crouched", "")) == "idle_crouch"
		and String(slots.get("idle_prone", "")) == "idle_prone"
		and String(slots.get("ready_crouched", "")) == "aim_idle_crouch",
		"AK-47 keeps the accepted shared idle and recovery poses"
	)
	_expect(
		String(slots.get("fire_standing", "")) == "combat_fire"
		and String(slots.get("fire_crouched", "")) == "crouch_fire"
		and String(slots.get("fire_prone", "")) == "prone_fire",
		"AK-47 keeps the shared posture-specific fire routes"
	)
	_expect(
		String(slots.get("reload_standing", "")) == "reload_ak47"
		and String(slots.get("reload_crouched", "")) == "reload_ak47"
		and String(slots.get("reload_prone", "")) == "prone_reload",
		"AK-47 uses its verified upper-body reload without forcing it onto prone"
	)
	var ready_aim: Dictionary = handling.get("ready_aim", {})
	_expect(
		is_equal_approx(float(ready_aim.get("fire_hold_seconds", 0.0)), 1.2),
		"AK-47 preserves the 1.2 second fire-recovery latch"
	)
	var dynamic_hold: Dictionary = handling.get("dynamic_hold", {})
	_expect(
		not bool(dynamic_hold.get("hand_socket_ik_enabled", true))
		and bool(dynamic_hold.get("support_hand_socket_ik_enabled", false))
		and bool(dynamic_hold.get("right_hand_owns_weapon", false))
		and not bool(dynamic_hold.get("fire_spine_ccdik_enabled", true))
		and not bool(dynamic_hold.get("fire_saved_joint_rotations_enabled", true)),
		"AK-47 uses the accepted single-owner hand and shoulder presentation"
	)
	var animation_map := _read_json(ANIMATION_MAP_PATH)
	var clips: Dictionary = animation_map.get("clips", {})
	var rules: Dictionary = animation_map.get("state_rules", {})
	_expect(String(clips.get("reload_ak47", "")) == RELOAD_PATH, "AK-47 reload map uses the measured AGLS source")
	_expect(
		String((rules.get("reload_ak47", {}) as Dictionary).get("layer", ""))
			== "UPPER_BODY",
		"AK-47 reload preserves the current locomotion base"
	)
	_expect(
		not clips.has("aim_idle_ak47") and HOLD_PATH not in clips.values(),
		"multi-pose AK hold strip is rejected from continuous runtime routes"
	)
	var ballistics: Dictionary = raw.get("ballistics", {})
	var reticle: Dictionary = raw.get("reticle", {})
	_expect(
		int(ballistics.get("damage", 0)) == 37
		and int(ballistics.get("fire_rate_rpm", 0)) == 375
		and is_equal_approx(float(ballistics.get("muzzle_velocity_mps", 0.0)), 710.0)
		and int(ballistics.get("magazine_capacity", 0)) == 30
		and int(ballistics.get("reserve_ammo", 0)) == 90,
		"AK-47 presentation pass preserves RECOM ballistics and ammunition"
	)
	_expect(
		is_equal_approx(float(reticle.get("base_gap_px", 0.0)), 5.1)
		and is_equal_approx(float(reticle.get("max_gap_px", 0.0)), 41.6)
		and is_equal_approx(float(reticle.get("shot_kick_px", 0.0)), 20.0),
		"AK-47 presentation pass leaves the reticle contract unchanged"
	)


func _inspect_weapon_model() -> void:
	var packed := load(MODEL_PATH) as PackedScene
	_expect(packed != null, "AK-47 AGLS GLB loads")
	if packed == null:
		return
	var instance := packed.instantiate()
	root.add_child(instance)
	var skeleton := _find_skeleton(instance)
	_expect(skeleton != null, "AK-47 AGLS GLB contains a weapon skeleton")
	if skeleton != null:
		for bone_name in REQUIRED_WEAPON_BONES:
			_expect(skeleton.find_bone(bone_name) >= 0, "AK-47 export preserves %s" % bone_name)
		for bone_index in skeleton.get_bone_count():
			var global_rest := _bone_global_rest(skeleton, bone_index)
			print("AGLS_AK47_WEAPON_BONE name=%s parent=%d origin=%s" % [
				skeleton.get_bone_name(bone_index),
				skeleton.get_bone_parent(bone_index),
				global_rest.origin,
			])
		var config := WeaponContract.load_config(CONFIG_PATH)
		var sockets: Dictionary = config.get("weapon_sockets", {})
		var body_origin := _bone_global_rest(skeleton, skeleton.find_bone("body")).origin
		var muzzle_origin := _bone_global_rest(skeleton, skeleton.find_bone("muzzle")).origin
		_expect(
			body_origin.distance_to(_vector(sockets.get("barrel_base_socket", {})))
				<= 0.000001,
			"AK-47 barrel-base socket is the exported body bone"
		)
		_expect(
			muzzle_origin.distance_to(_vector(sockets.get("muzzle_socket", {})))
				<= 0.000001,
			"AK-47 muzzle socket is the exported muzzle bone"
		)
	var bounds := _combined_local_bounds(instance)
	print("AGLS_AK47_WEAPON_BOUNDS position=%s size=%s end=%s" % [
		bounds.position, bounds.size, bounds.end,
	])
	_print_vertex_region("buttstock", instance, func(point: Vector3) -> bool:
		return point.z <= bounds.position.z + 0.025
	)
	_print_vertex_region("trigger_grip", instance, func(point: Vector3) -> bool:
		return point.z >= 0.02 and point.z <= 0.10 and point.y <= 0.075
	)
	_print_vertex_region("support_handguard", instance, func(point: Vector3) -> bool:
		return point.z >= 0.25 and point.z <= 0.40 and point.y >= 0.06
	)
	_print_vertex_region("optic_receiver", instance, func(point: Vector3) -> bool:
		return point.z >= -0.02 and point.z <= 0.20 and point.y >= 0.10
	)
	_print_vertex_region("ejection_receiver_right", instance, func(point: Vector3) -> bool:
		return point.z >= 0.10 and point.z <= 0.22 and point.y >= 0.08 and point.x >= 0.0
	)
	_expect(
		bounds.size.z >= 0.95 and bounds.size.z <= 1.05,
		"AK-47 export is human rifle scale (%.4f m long)" % bounds.size.z
	)
	instance.free()


func _print_vertex_region(
	label: String,
	model_root: Node3D,
	includes: Callable
) -> void:
	var points: Array[Vector3] = []
	for mesh_instance in _mesh_instances(model_root):
		var relative := _descendant_transform(model_root, mesh_instance)
		var mesh := mesh_instance.mesh
		if mesh == null:
			continue
		for surface_index in mesh.get_surface_count():
			var arrays := mesh.surface_get_arrays(surface_index)
			var vertices := arrays[Mesh.ARRAY_VERTEX] as PackedVector3Array
			for vertex in vertices:
				var point := relative * vertex
				if includes.call(point):
					points.append(point)
	if points.is_empty():
		print("AGLS_AK47_VERTEX_REGION label=%s count=0" % label)
		return
	var region := AABB(points[0], Vector3.ZERO)
	var centroid := Vector3.ZERO
	for point in points:
		region = region.expand(point)
		centroid += point
	centroid /= float(points.size())
	print("AGLS_AK47_VERTEX_REGION label=%s count=%d centroid=%s bounds=%s" % [
		label, points.size(), centroid, region,
	])


func _inspect_action(path: String, label: String, require_gun_helper: bool) -> void:
	var packed := load(path) as PackedScene
	_expect(packed != null, "AK-47 %s scene loads" % label)
	if packed == null:
		return
	var source_root := packed.instantiate()
	var target_root := (load(TARGET_PATH) as PackedScene).instantiate()
	root.add_child(source_root)
	root.add_child(target_root)
	var source_skeleton := _find_skeleton(source_root)
	var target_skeleton := _find_skeleton(target_root)
	var source_player := _find_animation_player(source_root)
	_expect(source_skeleton != null, "AK-47 %s has a source skeleton" % label)
	_expect(source_player != null, "AK-47 %s has an AnimationPlayer" % label)
	_expect(target_skeleton != null, "canonical operator target skeleton loads")
	if source_skeleton == null or source_player == null or target_skeleton == null:
		source_root.free()
		target_root.free()
		return
	SkeletonContract.ensure_65_bones(target_skeleton)
	_expect(SkeletonContract.is_complete(target_skeleton), "AK-47 %s uses the production 65-bone target" % label)
	_expect(NativeRigAdapter.is_native_agls_skeleton(source_skeleton), "AK-47 %s uses native AGLS bones" % label)
	_expect(source_skeleton.find_bone("hand_l") >= 0, "AK-47 %s preserves left hand" % label)
	_expect(source_skeleton.find_bone("hand_r") >= 0, "AK-47 %s preserves right hand" % label)
	if require_gun_helper:
		_expect(source_skeleton.find_bone("ik_hand_gun") >= 0, "AK-47 hold preserves ik_hand_gun")
	var animation_name := _first_authored_animation(source_player)
	_expect(animation_name != &"", "AK-47 %s has an authored animation" % label)
	if animation_name == &"":
		source_root.free()
		target_root.free()
		return
	var source_animation := source_player.get_animation(animation_name)
	var maximum_keys := 0
	for track_index in source_animation.get_track_count():
		maximum_keys = maxi(maximum_keys, source_animation.track_get_key_count(track_index))
	print("AGLS_AK47_ACTION label=%s name=%s length=%.6f tracks=%d max_keys=%d" % [
		label, animation_name, source_animation.length,
		source_animation.get_track_count(), maximum_keys,
	])
	_expect(source_animation.length > 0.0, "AK-47 %s has a sample range" % label)
	_expect(source_animation.get_track_count() >= 50, "AK-47 %s preserves authored body tracks" % label)
	if require_gun_helper:
		_measure_source_weapon_contacts(source_animation, source_skeleton)
	var retargeted := NativeRigAdapter.adapt_animation_rest_aware(
		source_animation,
		source_skeleton,
		target_skeleton,
		NodePath(".")
	)
	print("AGLS_AK47_RETARGET_TRACKS label=%s tracks=%d" % [
		label, retargeted.get_track_count() if retargeted != null else 0,
	])
	_expect(retargeted != null and retargeted.get_track_count() == 53, "AK-47 %s rest-aware retarget keeps all compatible production tracks" % label)
	if retargeted != null:
		_measure_retarget(label, retargeted, target_skeleton)
	source_root.free()
	target_root.free()


func _measure_source_weapon_contacts(animation: Animation, skeleton: Skeleton3D) -> void:
	var left_index := skeleton.find_bone("hand_l")
	var right_index := skeleton.find_bone("hand_r")
	var gun_index := skeleton.find_bone("ik_hand_gun")
	for sample_time in [0.0, animation.length * 0.5, animation.length]:
		var globals := _sample_animation_globals(animation, skeleton, sample_time)
		var gun: Transform3D = globals[gun_index]
		var right_contact := gun.affine_inverse() * (globals[right_index] as Transform3D)
		var left_contact := gun.affine_inverse() * (globals[left_index] as Transform3D)
		print("AGLS_AK47_SOURCE_CONTACT time=%.6f right=%s left=%s hand_distance=%.6f" % [
			sample_time,
			right_contact.origin,
			left_contact.origin,
			right_contact.origin.distance_to(left_contact.origin),
		])


func _measure_retarget(label: String, animation: Animation, skeleton: Skeleton3D) -> void:
	var samples := maxi(1, ceili(animation.length * 30.0))
	var finite := true
	var minimum_height := INF
	var maximum_height := 0.0
	var minimum_shoulder_span := INF
	var maximum_shoulder_span := 0.0
	var minimum_hand_span := INF
	var maximum_hand_span := 0.0
	var maximum_shoulder_level := 0.0
	var maximum_shoulder_yaw := 0.0
	var maximum_hip_travel := 0.0
	var first_hips := Vector3.ZERO
	var terminal_metrics: Dictionary = {}
	for sample_index in range(samples + 1):
		var sample_time := minf(float(sample_index) / 30.0, animation.length)
		var globals := _sample_animation_globals(animation, skeleton, sample_time)
		var metrics := _body_metrics(skeleton, globals)
		if sample_index == 0:
			first_hips = metrics.get("hips", Vector3.ZERO)
		if sample_index == samples:
			terminal_metrics = metrics
		finite = finite and bool(metrics.get("finite", false))
		minimum_height = minf(minimum_height, float(metrics.get("body_height", 0.0)))
		maximum_height = maxf(maximum_height, float(metrics.get("body_height", 0.0)))
		minimum_shoulder_span = minf(minimum_shoulder_span, float(metrics.get("shoulder_span", 0.0)))
		maximum_shoulder_span = maxf(maximum_shoulder_span, float(metrics.get("shoulder_span", 0.0)))
		minimum_hand_span = minf(minimum_hand_span, float(metrics.get("hand_span", 0.0)))
		maximum_hand_span = maxf(maximum_hand_span, float(metrics.get("hand_span", 0.0)))
		maximum_shoulder_level = maxf(maximum_shoulder_level, float(metrics.get("shoulder_level", 0.0)))
		maximum_shoulder_yaw = maxf(maximum_shoulder_yaw, float(metrics.get("shoulder_yaw_degrees", 0.0)))
		maximum_hip_travel = maxf(
			maximum_hip_travel,
			first_hips.distance_to(metrics.get("hips", Vector3.ZERO))
		)
	var terminal_hip_delta := first_hips.distance_to(
		terminal_metrics.get("hips", Vector3.ZERO)
	)
	print(
		"AGLS_AK47_RETARGET_SWEEP label=%s samples=%d finite=%s height=%.6f..%.6f shoulder_span=%.6f..%.6f shoulder_level_max=%.6f shoulder_yaw_max=%.6f hand_span=%.6f..%.6f hip_travel_max=%.6f hip_terminal_delta=%.6f" % [
			label, samples + 1, finite, minimum_height, maximum_height,
			minimum_shoulder_span, maximum_shoulder_span, maximum_shoulder_level,
			maximum_shoulder_yaw, minimum_hand_span, maximum_hand_span,
			maximum_hip_travel, terminal_hip_delta,
		]
	)
	_expect(finite, "AK-47 %s retarget remains finite through every 30 Hz sample" % label)
	if label == "hold":
		_expect(maximum_hip_travel >= 0.25, "AK-47 hold source is proven to be a varying pose strip")
		_expect(
			float(terminal_metrics.get("body_height", 0.0)) >= 1.80
			and float(terminal_metrics.get("body_height", 0.0)) <= 2.15
			and float(terminal_metrics.get("shoulder_span", 0.0)) >= 0.35
			and float(terminal_metrics.get("shoulder_span", 0.0)) <= 0.50
			and float(terminal_metrics.get("shoulder_level", INF)) <= 0.02
			and float(terminal_metrics.get("shoulder_yaw_degrees", INF)) <= 10.0,
			"AK-47 hold terminal sample is human and square, but is not routed as a loop"
		)
	else:
		_expect(
			minimum_height >= 1.75 and maximum_height <= 2.10
			and minimum_shoulder_span >= 0.38 and maximum_shoulder_span <= 0.46
			and minimum_hand_span >= 0.12 and maximum_hand_span <= 0.78,
			"AK-47 reload keeps human body and arm proportions throughout"
		)
		_expect(
			maximum_shoulder_level <= 0.18 and maximum_shoulder_yaw <= 60.0,
			"AK-47 reload asymmetry stays inside the verified human action envelope"
		)
		_expect(
			maximum_hip_travel <= 0.05 and terminal_hip_delta <= 0.005,
			"AK-47 reload root motion is bounded and closes at the terminal pose"
		)
		for bone_name in [
			"mixamorig_LeftShoulder", "mixamorig_RightShoulder",
			"mixamorig_LeftHand", "mixamorig_RightHand",
		]:
			var maximum_step := _maximum_rotation_step_degrees(animation, bone_name)
			print("AGLS_AK47_ROTATION_CONTINUITY bone=%s maximum_step_degrees=%.6f" % [bone_name, maximum_step])
			_expect(maximum_step <= 60.0, "AK-47 reload %s has no one-frame inversion" % bone_name)


func _sample_animation_globals(
	animation: Animation,
	skeleton: Skeleton3D,
	time: float
) -> Dictionary:
	var channels: Dictionary = {}
	for track_index in animation.get_track_count():
		var raw_bone := String(animation.track_get_path(track_index)).split(":")[-1]
		var bone_index := skeleton.find_bone(raw_bone)
		if bone_index < 0:
			continue
		if not channels.has(bone_index):
			channels[bone_index] = {}
		var channel: Dictionary = channels[bone_index]
		match animation.track_get_type(track_index):
			Animation.TYPE_POSITION_3D:
				channel["position"] = track_index
			Animation.TYPE_ROTATION_3D:
				channel["rotation"] = track_index
	var globals: Dictionary = {}
	for bone_index in skeleton.get_bone_count():
		var local := skeleton.get_bone_rest(bone_index)
		var channel: Dictionary = channels.get(bone_index, {})
		if channel.has("position"):
			local.origin = animation.position_track_interpolate(int(channel["position"]), time)
		if channel.has("rotation"):
			local.basis = Basis(animation.rotation_track_interpolate(int(channel["rotation"]), time))
		var parent_index := skeleton.get_bone_parent(bone_index)
		globals[bone_index] = (
			(globals[parent_index] as Transform3D) * local
			if parent_index >= 0 and globals.has(parent_index)
			else local
		)
	return globals


func _body_metrics(skeleton: Skeleton3D, globals: Dictionary) -> Dictionary:
	var poses: Dictionary = {}
	for bone_name in CANONICAL_ARM_BONES:
		var bone_index := skeleton.find_bone(bone_name)
		if bone_index < 0:
			return {"finite": false}
		poses[bone_name] = (globals[bone_index] as Transform3D).origin
	var left_shoulder: Vector3 = poses["mixamorig_LeftArm"] * OPERATOR_SCALE
	var right_shoulder: Vector3 = poses["mixamorig_RightArm"] * OPERATOR_SCALE
	var left_hand: Vector3 = poses["mixamorig_LeftHand"] * OPERATOR_SCALE
	var right_hand: Vector3 = poses["mixamorig_RightHand"] * OPERATOR_SCALE
	var shoulder_span := left_shoulder.distance_to(right_shoulder)
	var finite := true
	var minimum_y := INF
	var maximum_y := -INF
	for transform_value in globals.values():
		var position := (transform_value as Transform3D).origin * OPERATOR_SCALE
		finite = finite and position.is_finite()
		minimum_y = minf(minimum_y, position.y)
		maximum_y = maxf(maximum_y, position.y)
	var shoulder_line := left_shoulder - right_shoulder
	var hips_index := skeleton.find_bone("mixamorig_Hips")
	return {
		"finite": finite,
		"body_height": maximum_y - minimum_y,
		"shoulder_level": absf(left_shoulder.y - right_shoulder.y),
		"shoulder_span": shoulder_span,
		"shoulder_yaw_degrees": absf(rad_to_deg(atan2(
			absf(shoulder_line.z), maxf(absf(shoulder_line.x), 0.000001)
		))),
		"hand_span": left_hand.distance_to(right_hand),
		"left_hand": left_hand,
		"right_hand": right_hand,
		"hips": (globals[hips_index] as Transform3D).origin * OPERATOR_SCALE,
	}


func _maximum_rotation_step_degrees(animation: Animation, bone_name: String) -> float:
	var maximum_step := 0.0
	for track_index in animation.get_track_count():
		if animation.track_get_type(track_index) != Animation.TYPE_ROTATION_3D:
			continue
		if not String(animation.track_get_path(track_index)).ends_with(":" + bone_name):
			continue
		for key_index in range(1, animation.track_get_key_count(track_index)):
			var previous: Quaternion = animation.track_get_key_value(track_index, key_index - 1)
			var current: Quaternion = animation.track_get_key_value(track_index, key_index)
			maximum_step = maxf(
				maximum_step,
				rad_to_deg(previous.angle_to(current))
			)
	return maximum_step


func _bone_global_rest(skeleton: Skeleton3D, bone_index: int) -> Transform3D:
	var result := skeleton.get_bone_rest(bone_index)
	var parent := skeleton.get_bone_parent(bone_index)
	while parent >= 0:
		result = skeleton.get_bone_rest(parent) * result
		parent = skeleton.get_bone_parent(parent)
	return result


func _combined_local_bounds(node: Node) -> AABB:
	var bounds := AABB()
	var initialized := false
	for mesh_instance in _mesh_instances(node):
		var mesh_bounds := (mesh_instance as MeshInstance3D).get_aabb()
		var relative := _descendant_transform(node as Node3D, mesh_instance as Node3D)
		mesh_bounds = relative * mesh_bounds
		if initialized:
			bounds = bounds.merge(mesh_bounds)
		else:
			bounds = mesh_bounds
			initialized = true
	return bounds


func _descendant_transform(ancestor: Node3D, descendant: Node3D) -> Transform3D:
	var chain: Array[Transform3D] = []
	var cursor: Node = descendant
	while cursor != null and cursor != ancestor:
		if cursor is Node3D:
			chain.push_front((cursor as Node3D).transform)
		cursor = cursor.get_parent()
	var result := Transform3D.IDENTITY
	for local_transform in chain:
		result *= local_transform
	return result


func _mesh_instances(node: Node) -> Array[MeshInstance3D]:
	var result: Array[MeshInstance3D] = []
	if node is MeshInstance3D:
		result.append(node as MeshInstance3D)
	for child in node.get_children():
		result.append_array(_mesh_instances(child))
	return result


func _first_authored_animation(player: AnimationPlayer) -> StringName:
	for animation_name in player.get_animation_list():
		if animation_name != &"RESET":
			return animation_name
	return &""


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for child in node.get_children():
		var found := _find_animation_player(child)
		if found != null:
			return found
	return null


func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	return parsed as Dictionary if parsed is Dictionary else {}


func _vector(value: Variant) -> Vector3:
	if not value is Dictionary:
		return Vector3.ZERO
	var data := value as Dictionary
	return Vector3(
		float(data.get("x", 0.0)),
		float(data.get("y", 0.0)),
		float(data.get("z", 0.0))
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("AGLS_AK47_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("AGLS_AK47_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("AGLS_AK47_ASSET_REGRESSION PASS")
		quit(0)
	else:
		print("AGLS_AK47_ASSET_REGRESSION FAIL %s" % [failures])
		quit(1)

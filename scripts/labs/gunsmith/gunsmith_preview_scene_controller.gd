extends RefCounted

const PS1_GAS_MASK_RIGGED_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const OperatorPostureLayer := preload("res://scripts/player/operator_posture_layer.gd")

static func _setup_studio_environment(lab: Node) -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	lab.add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 75, 0)
	key.light_color = Color(1.0, 0.98, 0.92)
	key.light_energy = 1.6
	key.shadow_enabled = true
	lab.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 0, 0)
	fill.light_color = Color(0.6, 0.7, 0.85)
	fill.light_energy = 0.9
	lab.add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(20, -160, 0)
	rim.light_color = Color(0.3, 0.9, 1.0)
	rim.light_energy = 1.0
	lab.add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.20)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	lab.add_child(floor_mesh)

	lab.cam_pivot = Node3D.new()
	lab.add_child(lab.cam_pivot)
	lab.cam = Camera3D.new()
	lab.cam_pivot.add_child(lab.cam)
	lab.cam.current = true
	lab._update_camera()

	lab.bullet_tracers = Node3D.new()
	lab.add_child(lab.bullet_tracers)

	lab.fire_debug_material = StandardMaterial3D.new()
	lab.fire_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	lab.fire_debug_material.vertex_color_use_as_albedo = true
	lab.fire_debug_material.no_depth_test = true
	lab.fire_debug_instance = MeshInstance3D.new()
	lab.fire_debug_instance.name = "WeaponFireDebugLayers"
	lab.fire_debug_instance.mesh = lab.fire_debug_mesh
	lab.fire_debug_instance.material_override = lab.fire_debug_material
	lab.fire_debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	lab.add_child(lab.fire_debug_instance)

static func _update_camera(lab: Node) -> void:
	if not lab.cam_pivot or not lab.cam: return
	lab.cam_pivot.position = lab.cam_target
	lab.cam_pivot.rotation_degrees = Vector3(lab.cam_pitch, lab.cam_yaw, 0)
	lab.cam.position = Vector3(0, 0, lab.cam_distance)

static func _set_camera_preset(lab: Node,preset_name: String) -> void:
	match preset_name:
		"hands":
			lab.cam_target = Vector3(0.08, 1.22, 0.05)
			lab.cam_distance = 0.80
			lab.cam_yaw = 60.0
			lab.cam_pitch = -8.0
		"ots":
			lab.cam_target = Vector3(0.12, 1.28, 0.0)
			lab.cam_distance = 1.2
			lab.cam_yaw = 15.0
			lab.cam_pitch = -6.0
		"side":
			lab.cam_target = Vector3(0.0, 1.22, 0.0)
			lab.cam_distance = 1.1
			lab.cam_yaw = 90.0
			lab.cam_pitch = 0.0
		"full":
			lab.cam_target = Vector3(0.0, 0.95, 0.0)
			lab.cam_distance = 2.2
			lab.cam_yaw = 35.0
			lab.cam_pitch = -12.0
	lab._update_camera()

static func _setup_trooper_and_rig(lab: Node) -> void:
	lab.trooper_node = PS1_GAS_MASK_RIGGED_SCENE.instantiate() as Node3D
	lab.trooper_node.scale = Vector3.ONE * lab.trooper_scale
	lab.add_child(lab.trooper_node)

	lab.skeleton = lab._find_skeleton(lab.trooper_node)
	lab._ensure_65_bone_contract()
	lab._apply_pixel_texture(lab.trooper_node)

	lab.left_arm_idx = lab.skeleton.find_bone("mixamorig_LeftArm")
	lab.left_forearm_idx = lab.skeleton.find_bone("mixamorig_LeftForeArm")
	lab.left_hand_idx = lab.skeleton.find_bone("mixamorig_LeftHand")
	lab.right_arm_idx = lab.skeleton.find_bone("mixamorig_RightArm")
	lab.right_forearm_idx = lab.skeleton.find_bone("mixamorig_RightForeArm")
	lab.right_hand_idx = lab.skeleton.find_bone("mixamorig_RightHand")
	lab.head_idx = lab.skeleton.find_bone("mixamorig_Head")
	for anchor_name in ["mixamorig_Spine2", "mixamorig_Spine1", "mixamorig_Spine"]:
		lab.weapon_anchor_bone_idx = lab.skeleton.find_bone(anchor_name)
		if lab.weapon_anchor_bone_idx >= 0:
			break
	lab.left_palm_anchor_local = lab._calculate_palm_anchor("Left", lab.left_hand_idx)
	lab.right_palm_anchor_local = lab._calculate_palm_anchor("Right", lab.right_hand_idx)

	lab.animation_player = AnimationPlayer.new()
	lab.animation_player.name = "AnimationPlayer"
	lab.animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	lab.skeleton.add_child(lab.animation_player)
	lab.animation_player.root_node = lab.animation_player.get_path_to(lab.skeleton)

	var aim_fbx_path := "res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx"
	var packed_anim := load(aim_fbx_path) as PackedScene
	if packed_anim:
		var temp := packed_anim.instantiate()
		var temp_ap: AnimationPlayer = lab._find_animation_player(temp)
		if temp_ap and not temp_ap.get_animation_list().is_empty():
			var anim_name: StringName = temp_ap.get_animation_list()[0]
			for a in temp_ap.get_animation_list():
				if a != &"RESET": anim_name = a; break
			var src_anim: Animation = temp_ap.get_animation(anim_name)
			var lib := AnimationLibrary.new()
			var retargeted: Animation = lab._retarget_aim_anim(src_anim)
			retargeted.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation("aim_idle", retargeted)

			var reload_path := "res://assets/animations/mixamo/Shooter Pack/reloading.fbx"
			if FileAccess.file_exists(reload_path):
				var r_scene := load(reload_path) as PackedScene
				if r_scene:
					var r_temp := r_scene.instantiate()
					var r_ap: AnimationPlayer = lab._find_animation_player(r_temp)
					if r_ap and not r_ap.get_animation_list().is_empty():
						var r_src: Animation = r_ap.get_animation(r_ap.get_animation_list()[0])
						var r_ret: Animation = lab._retarget_aim_anim(r_src)
						lib.add_animation("reload", r_ret)
					r_temp.queue_free()

			lab.animation_player.add_animation_library("", lib)
			lab.animation_player.play("aim_idle")
		temp.queue_free()

	lab.runtime_posture_layer = OperatorPostureLayer.new()
	lab.runtime_posture_layer.bind(lab.skeleton, lab._neutral_preview_hip_rotation())

	if lab.left_arm_idx >= 0 and lab.left_hand_idx >= 0:
		lab.left_hand_ik = SkeletonIK3D.new()
		lab.left_hand_ik.name = "LeftHandIK"
		lab.left_hand_ik.root_bone = "mixamorig_LeftArm"
		lab.left_hand_ik.tip_bone = "mixamorig_LeftHand"
		lab.left_hand_ik.use_magnet = true
		lab.left_hand_ik.interpolation = 1.0
		lab.left_hand_ik.override_tip_basis = true
		lab.left_hand_ik.max_iterations = 40
		lab.left_hand_ik.min_distance = 0.00002
		lab.left_hand_ik.magnet = Vector3(-0.35, -0.75, 0.15)
		lab.skeleton.add_child(lab.left_hand_ik)
		# Keep IK stopped until two-stage bootstrap completes.
		lab.left_hand_ik.stop()

	var inv_scale: float = 1.0 / lab.trooper_scale

	if lab.right_hand_idx >= 0:
		lab.ba_right_hand = BoneAttachment3D.new()
		lab.ba_right_hand.name = "BA_RightHand"
		lab.ba_right_hand.bone_name = "mixamorig_RightHand"
		lab.skeleton.add_child(lab.ba_right_hand)
		lab.right_hand_dot = lab._create_marker(Color(1.0, 0.6, 0.1), "RightHand_Bone_Dot", 0.028 * inv_scale)
		lab.ba_right_hand.add_child(lab.right_hand_dot)

		var mount_basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(180.0), 0.0)).scaled(Vector3.ONE * inv_scale)
		lab.weapon_mount_local = Transform3D(mount_basis, Vector3(-0.02, 0.08, 0.05) * inv_scale)

		lab.weapon_root = Node3D.new()
		lab.weapon_root.name = "WeaponRoot"
		lab.skeleton.add_child(lab.weapon_root)

		lab.weapon_pivot = Node3D.new()
		lab.weapon_pivot.name = "WeaponPivot"
		lab.weapon_root.add_child(lab.weapon_pivot)

		lab.geometry_root = Node3D.new()
		lab.geometry_root.name = "GeometryRoot"
		lab.weapon_pivot.add_child(lab.geometry_root)

		lab.socket_root = Node3D.new()
		lab.socket_root.name = "SocketRoot"
		lab.weapon_pivot.add_child(lab.socket_root)

		lab.right_hand_ik = SkeletonIK3D.new()
		lab.right_hand_ik.name = "RightHandIK"
		lab.right_hand_ik.root_bone = "mixamorig_RightArm"
		lab.right_hand_ik.tip_bone = "mixamorig_RightHand"
		lab.right_hand_ik.use_magnet = true
		lab.right_hand_ik.interpolation = 1.0
		lab.right_hand_ik.override_tip_basis = true
		lab.right_hand_ik.max_iterations = 40
		lab.right_hand_ik.min_distance = 0.00002
		lab.skeleton.add_child(lab.right_hand_ik)
		# Keep IK stopped until two-stage bootstrap completes.
		lab.right_hand_ik.stop()

	lab.eye_sight_marker = Marker3D.new()
	lab.eye_sight_marker.name = "GunPlacementLineOrigin"
	lab.add_child(lab.eye_sight_marker)
	lab.eye_sight_dot = lab._create_marker(Color(0.25, 0.55, 1.0), "GunPlacementLineDot", 0.014)
	lab.eye_sight_marker.add_child(lab.eye_sight_dot)
	lab.eye_sight_direction_marker = Marker3D.new()
	lab.eye_sight_direction_marker.name = "GunPlacementDirectionHandle"
	lab.add_child(lab.eye_sight_direction_marker)
	lab.eye_sight_direction_dot = lab._create_marker(
		Color(0.55, 0.78, 1.0),
		"GunPlacementDirectionDot",
		0.012
	)
	lab.eye_sight_direction_marker.add_child(lab.eye_sight_direction_dot)
	lab._update_eye_sight_marker()


static func _neutral_preview_hip_rotation(lab: Node) -> Quaternion:
	if lab.animation_player == null or not lab.animation_player.has_animation(&"aim_idle"):
		return Quaternion.IDENTITY
	var animation: Animation = lab.animation_player.get_animation(&"aim_idle")
	if animation == null:
		return Quaternion.IDENTITY
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		if not str(animation.track_get_path(track)).ends_with(":mixamorig_Hips"):
			continue
		if animation.track_get_key_count(track) > 0:
			return (animation.track_get_key_value(track, 0) as Quaternion).normalized()
	return Quaternion.IDENTITY


static func _get_gunsmith_fixed_aim_target(lab: Node) -> Vector3:
	if lab.skeleton == null:
		return Vector3(0.0, 1.25, -50.0)
	var forward: Vector3 = -lab.skeleton.global_basis.z.normalized()
	return lab.skeleton.global_position + Vector3.UP * 1.25 + forward * 50.0


static func _apply_runtime_posture_preview(lab: Node) -> void:
	if lab.runtime_posture_layer == null or lab.skeleton == null:
		return

	var aim_target: Vector3 = lab._get_gunsmith_fixed_aim_target()

	# Optional debugging mode only
	if lab.gunsmith_camera_tracking_enabled and lab.cam != null:
		aim_target = lab._camera_aim_sample().position

	lab.runtime_posture_layer.apply(
		0.0,
		0.0,
		1.0,
		0.0,
		0.0,
		deg_to_rad(78.0),
		deg_to_rad(48.0),
		deg_to_rad(42.0),
		deg_to_rad(32.0),
		0.0,
		0.18,
		0.0,
		deg_to_rad(90.0),
		0.0,
		lab.preview_posture,
		0.0,
		aim_target,
		lab.preview_hip_level_trim_deg
	)


static func _initialize_weapon_master_pose(lab: Node) -> void:
	if lab.weapon_master_pose_initialized or not lab.weapon_root or not lab._right_hand_pose_is_ready():
		return
	var hand_world: Transform3D = lab._get_right_hand_world_transform()
	lab.weapon_root.global_transform = hand_world * lab.weapon_mount_local
	lab._capture_weapon_anchor()
	lab.weapon_master_pose_initialized = true
	lab._sync_weapon_transform(false)
	lab._sync_markers()
	lab._register_interactive_dots()
	lab._set_weapon_ik_enabled(true)
	lab._set_save_enabled(true)


static func _set_weapon_ik_enabled(lab: Node,enabled: bool) -> void:
	if lab.right_hand_ik:
		if enabled:
			if not lab.right_hand_ik.is_running():
				lab.right_hand_ik.start(true)
		else:
			if lab.right_hand_ik.is_running():
				lab.right_hand_ik.stop()
	if lab.left_hand_ik:
		if enabled:
			if not lab.left_hand_ik.is_running():
				lab.left_hand_ik.start(true)
		else:
			if lab.left_hand_ik.is_running():
				lab.left_hand_ik.stop()


static func _set_save_enabled(lab: Node,enabled: bool) -> void:
	if lab.save_rig_button:
		lab.save_rig_button.disabled = not enabled
	if lab.equip_weapon_button:
		lab.equip_weapon_button.disabled = not enabled
	if lab.play_latest_button:
		lab.play_latest_button.disabled = not enabled


static func _get_right_hand_bone_index(lab: Node) -> int:
	if lab.right_hand_idx >= 0:
		return lab.right_hand_idx
	if lab.ba_right_hand != null and lab.ba_right_hand.bone_idx >= 0:
		return lab.ba_right_hand.bone_idx
	if lab.skeleton != null:
		return lab.skeleton.find_bone("mixamorig_RightHand")
	return -1

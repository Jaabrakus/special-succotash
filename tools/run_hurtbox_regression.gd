extends SceneTree

const TargetDummyScript := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const ShotAuthorityScript := preload("res://scripts/network/socom_shot_authority.gd")
const AnatomicalHitResolver := preload("res://scripts/combat/socom_anatomical_hit_resolver.gd")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")
const REQUIRED_REGIONS: Array[StringName] = [
	&"HEAD", &"TORSO", &"PELVIS",
	&"LEFT_UPPER_ARM", &"RIGHT_UPPER_ARM",
	&"LEFT_FOREARM", &"RIGHT_FOREARM",
	&"LEFT_THIGH", &"RIGHT_THIGH",
	&"LEFT_CALF", &"RIGHT_CALF",
	&"LEFT_FOOT", &"RIGHT_FOOT"
]

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_root := Node3D.new()
	world_root.name = "HurtboxRegressionWorld"
	root.add_child(world_root)
	var dummy := TargetDummyScript.new()
	dummy.name = "AnimatedTarget"
	world_root.add_child(dummy)

	await process_frame
	await physics_frame

	var rig: Node3D = dummy.get_hurtbox_rig()
	_assert(rig != null, "animated hurtbox rig was not created")
	if rig == null:
		_finish()
		return

	var regions: Array[StringName] = rig.get_region_names()
	for required in REQUIRED_REGIONS:
		_assert(regions.has(required), "missing region %s" % required)

	# Core anatomy wins only when a limb is almost coplanar due to overlap.
	var overlap_choice: Dictionary = AnatomicalHitResolver.choose_hit([
		{"hit_region": &"RIGHT_FOREARM", "distance": 4.00},
		{"hit_region": &"TORSO", "distance": 4.08},
	])
	_assert(
		StringName(overlap_choice.get("hit_region", &"")) == &"TORSO",
		"near-coplanar limb overlap was not resolved to torso"
	)
	_assert(
		bool(overlap_choice.get("anatomical_override", false)),
		"resolved overlap did not expose diagnostic metadata"
	)
	var exposed_limb_choice: Dictionary = AnatomicalHitResolver.choose_hit([
		{"hit_region": &"RIGHT_FOREARM", "distance": 4.00},
		{"hit_region": &"TORSO", "distance": 4.30},
	])
	_assert(
		StringName(exposed_limb_choice.get("hit_region", &"")) == &"RIGHT_FOREARM",
		"genuinely exposed limb was incorrectly converted to torso"
	)

	# The original defect: shoulder-to-elbow had no reliable collision shape.
	for upper_arm in [&"LEFT_UPPER_ARM", &"RIGHT_UPPER_ARM"]:
		var arm_area: Area3D = rig.get_region_area(upper_arm)
		_assert(arm_area != null, "%s area missing" % upper_arm)
		if arm_area:
			var hits := _point_hits(arm_area.global_position)
			_assert(
				_has_region(hits, upper_arm),
				"physics point at %s center did not resolve its upper-arm area" % upper_arm
			)

	# The live tuner must change physics geometry, not only the debug mesh.
	var tuned_arm: Area3D = rig.get_region_area(&"RIGHT_UPPER_ARM")
	if tuned_arm:
		var tuned_shape_node := tuned_arm.get_child(0) as CollisionShape3D
		var tuned_shape := tuned_shape_node.shape as CapsuleShape3D
		var radius_before := tuned_shape.radius
		rig.apply_radius_scales({&"global": 0.70})
		var radius_after := tuned_shape.radius
		_assert(
			radius_after < radius_before - 0.01,
			"global tuning slider did not shrink physics hurtboxes"
		)
		rig.apply_radius_scales({&"global": 0.88})

	# Every exact region has an independent canonical scale. Tuning the right arm
	# must not resize the mirrored left arm or depend on lab-only geometry.
	var left_tuned_arm: Area3D = rig.get_region_area(&"LEFT_UPPER_ARM")
	if tuned_arm and left_tuned_arm:
		var right_shape := (tuned_arm.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		var left_shape := (left_tuned_arm.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		var initial_scales: Dictionary = rig.get_radius_scales()
		var exact_scales := initial_scales.duplicate(true)
		exact_scales[&"right_upper_arm"] = 0.55
		exact_scales[&"left_upper_arm"] = 1.0
		rig.apply_radius_scales(exact_scales)
		var expected_right := (
			SocomAnimatedHurtboxRig.UPPER_ARM_RADIUS
			* float(exact_scales.get(&"global", 0.88))
			* 0.55
		)
		var expected_left := (
			SocomAnimatedHurtboxRig.UPPER_ARM_RADIUS
			* float(exact_scales.get(&"global", 0.88))
		)
		_assert(
			is_equal_approx(right_shape.radius, expected_right),
			"right upper-arm exact scale did not reach physics geometry"
		)
		_assert(
			is_equal_approx(left_shape.radius, expected_left),
			"right upper-arm tuning changed the left upper arm"
		)
		rig.apply_radius_scales(initial_scales)

	var migrated := HurtboxProfile.normalize_scales({
		&"global": 0.9,
		&"head": 0.8,
		&"torso": 0.75,
		&"arms": 0.7,
		&"legs": 0.65,
	})
	_assert(
		is_equal_approx(float(migrated[&"pelvis"]), 0.75),
		"legacy torso scale did not migrate to the exact pelvis region"
	)
	_assert(
		is_equal_approx(float(migrated[&"right_forearm"]), 0.7),
		"legacy arm scale did not migrate to exact arm regions"
	)
	_assert(
		is_equal_approx(float(migrated[&"left_foot"]), 0.65),
		"legacy leg scale did not migrate to exact foot regions"
	)

	# Center and length authoring must change the same live physics objects and
	# remain independent per region.
	var torso_for_layout: Area3D = rig.get_region_area(&"TORSO")
	var pelvis_for_layout: Area3D = rig.get_region_area(&"PELVIS")
	if torso_for_layout and pelvis_for_layout:
		var initial_geometry: Dictionary = rig.get_geometry_tuning()
		var layout_edit := initial_geometry.duplicate(true)
		var initial_torso_offset := HurtboxProfile.geometry_offset(
			layout_edit,
			&"torso"
		)
		var torso_position_before := torso_for_layout.global_position
		var pelvis_position_before := pelvis_for_layout.global_position
		var torso_shape := (torso_for_layout.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		var torso_height_before := torso_shape.height
		HurtboxProfile.set_geometry_offset(
			layout_edit,
			&"torso",
			initial_torso_offset + Vector3(0.05, -0.04, 0.02)
		)
		HurtboxProfile.set_geometry_length_scale(layout_edit, &"torso", 1.40)
		rig.apply_geometry_tuning(layout_edit)
		_assert(
			torso_for_layout.global_position.distance_to(torso_position_before) > 0.05,
			"torso center edit did not move its physics area"
		)
		_assert(
			torso_shape.height > torso_height_before + 0.05,
			"torso length edit did not stretch its physics capsule"
		)
		_assert(
			pelvis_for_layout.global_position.distance_to(pelvis_position_before) < 0.001,
			"torso layout edit moved the pelvis hitbox"
		)
		rig.apply_geometry_tuning(initial_geometry)

	var default_geometry := HurtboxProfile.default_geometry()
	_assert(
		HurtboxProfile.geometry_offset(default_geometry, &"torso").y < -0.05,
		"default torso center was not lowered away from the head"
	)

	# There must be no invisible center capsule. A shot through visible air
	# between independently animated legs is a legitimate miss.
	_assert(
		rig.get_region_area(&"LEG_BRIDGE") == null,
		"an invisible hitbox still occupies the center-leg gap"
	)

	# Region classification comes from the struck shape, never from world Y.
	var left_arm: Area3D = rig.get_region_area(&"LEFT_UPPER_ARM")
	if left_arm:
		var result: Dictionary = left_arm.take_bullet_damage(
			10.0,
			left_arm.global_position,
			Vector3.RIGHT,
			Vector3(0.0, 1.4, 4.0)
		)
		_assert(
			StringName(result.get("hit_region", &"")) == &"LEFT_UPPER_ARM",
			"upper-arm damage lost its exact region identity"
		)
		_assert(not bool(result.get("headshot", true)), "upper arm was mislabeled as headshot")

		var outward := left_arm.global_position - dummy.global_position
		outward.y = 0.0
		if outward.length_squared() < 0.001:
			outward = Vector3.LEFT
		outward = outward.normalized()
		var authority_origin := left_arm.global_position + outward * 1.5
		var authority_direction := (left_arm.global_position - authority_origin).normalized()
		var authority_yaw := atan2(-authority_direction.x, -authority_direction.z)
		var authority_pitch := asin(clampf(authority_direction.y, -1.0, 1.0))
		var authoritative_hit: Dictionary = ShotAuthorityScript.validate_and_trace(
			world_root.get_world_3d(),
			{
				"sequence": 1,
				"simulation_tick": 100,
				"yaw": authority_yaw,
				"pitch": authority_pitch,
				"reported_muzzle_origin": authority_origin,
				"direction": authority_direction
			},
			authority_origin,
			[],
			4.0,
			0,
			100
		)
		_assert(bool(authoritative_hit.get("accepted", false)), "server-style shot was rejected")
		_assert(bool(authoritative_hit.get("hit", false)), "server-style upper-arm shot missed")
		_assert(
			StringName(authoritative_hit.get("hit_region", &"")) == &"LEFT_UPPER_ARM",
			"server authority did not preserve the exact upper-arm region"
		)

	# A per-bone pose change must propagate too; following only the actor root is
	# not sufficient once locomotion, recoil, prone, and hit reactions are active.
	var skeleton := _find_skeleton(dummy.model_root)
	if skeleton and left_arm:
		var arm_bone := skeleton.find_bone("mixamorig_LeftArm")
		_assert(arm_bone >= 0, "left upper-arm bone missing from test skeleton")
		if arm_bone >= 0:
			var arm_before := left_arm.global_position
			var original_rotation := skeleton.get_bone_pose_rotation(arm_bone)
			skeleton.set_bone_pose_rotation(
				arm_bone,
				Quaternion(Vector3.FORWARD, deg_to_rad(32.0)) * original_rotation
			)
			rig.force_pose_update()
			_assert(
				left_arm.global_position.distance_to(arm_before) > 0.025,
				"upper-arm hurtbox did not follow an animated bone pose"
			)
			skeleton.set_bone_pose_rotation(arm_bone, original_rotation)

	# Moving the rendered skeleton root must move every damage shape with it.
	var torso: Area3D = rig.get_region_area(&"TORSO")
	if torso:
		# Composure classification is shooter-relative metadata over a stable
		# physical capsule. A central ray is full damage; the same capsule's edge
		# is a graze when the shooter's precision core has contracted.
		var torso_shape_node := torso.get_child(0) as CollisionShape3D
		var torso_capsule := torso_shape_node.shape as CapsuleShape3D
		var physical_radius_before := torso_capsule.radius
		var local_forward := torso.global_transform.basis.z.normalized()
		var local_right := torso.global_transform.basis.x.normalized()
		var center_origin := torso.global_position + local_forward * 4.0
		var center_classification: Dictionary = torso.classify_shot_path(
			center_origin,
			-local_forward,
			0.60
		)
		_assert(
			bool(center_classification.get("precision", false)),
			"central torso ray was not classified as precision"
		)
		var edge_origin := center_origin + local_right * torso_capsule.radius * 0.86
		var edge_classification: Dictionary = torso.classify_shot_path(
			edge_origin,
			-local_forward,
			0.60
		)
		_assert(
			bool(edge_classification.get("graze", false)),
			"edge torso ray was not classified as a composure graze: %s" % edge_classification
		)
		_assert(
			is_equal_approx(torso_capsule.radius, physical_radius_before),
			"precision classification mutated the physical hurtbox"
		)

		var before := torso.global_position
		dummy.model_root.position += Vector3(0.31, 0.17, -0.23)
		rig.force_pose_update()
		var actual_delta := torso.global_position - before
		_assert(
			actual_delta.distance_to(Vector3(0.31, 0.17, -0.23)) < 0.015,
			"hurtboxes did not follow the moved rendered skeleton"
		)

	_finish()


func _point_hits(position: Vector3) -> Array[Dictionary]:
	var query := PhysicsPointQueryParameters3D.new()
	query.position = position
	query.collision_mask = 1 << 2
	query.collide_with_areas = true
	query.collide_with_bodies = false
	return root.get_world_3d().direct_space_state.intersect_point(query, 32)


func _has_region(hits: Array[Dictionary], region: StringName) -> bool:
	for hit in hits:
		var collider: Object = hit.get("collider")
		if collider != null and collider.has_method("get_hit_region"):
			if StringName(collider.call("get_hit_region")) == region:
				return true
	return false


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found:
			return found
	return null


func _assert(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("HURTBOX_REGRESSION PASS: animated regions, upper arms, and open center-leg gap")
		quit(0)
		return
	for failure in failures:
		push_error("HURTBOX_REGRESSION: %s" % failure)
	quit(1)

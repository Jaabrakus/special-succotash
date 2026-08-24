extends SceneTree

const TargetDummyScript := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const ShotAuthorityScript := preload("res://scripts/network/socom_shot_authority.gd")
const AnatomicalHitResolver := preload("res://scripts/combat/socom_anatomical_hit_resolver.gd")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")
const HurtboxAreaScript := preload("res://scripts/combat/socom_hurtbox_area.gd")
const REQUIRED_REGIONS: Array[StringName] = [
	&"HEAD", &"NECK", &"TORSO", &"PELVIS",
	&"LEFT_UPPER_ARM", &"RIGHT_UPPER_ARM",
	&"LEFT_FOREARM", &"RIGHT_FOREARM",
	&"LEFT_THIGH", &"RIGHT_THIGH",
	&"LEFT_CALF", &"RIGHT_CALF",
	&"LEFT_FOOT", &"RIGHT_FOOT"
]

var failures: Array[String] = []


class DamageMovementProxy extends CharacterBody3D:
	func take_bullet_damage_region() -> Dictionary:
		return {"accepted": true}


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var world_root := Node3D.new()
	world_root.name = "HurtboxRegressionWorld"
	root.add_child(world_root)
	var dummy := TargetDummyScript.new()
	dummy.name = "AnimatedTarget"
	world_root.add_child(dummy)
	var movement_proxy := DamageMovementProxy.new()
	movement_proxy.name = "MovementCapsuleInFrontOfAnatomy"
	movement_proxy.collision_layer = 1
	movement_proxy.position = Vector3(10.0, 1.0, 0.0)
	var movement_shape_node := CollisionShape3D.new()
	var movement_shape := SphereShape3D.new()
	movement_shape.radius = 0.40
	movement_shape_node.shape = movement_shape
	movement_proxy.add_child(movement_shape_node)
	world_root.add_child(movement_proxy)
	var anatomy_area := HurtboxAreaScript.new() as Area3D
	anatomy_area.name = "TorsoBehindMovementCapsule"
	anatomy_area.position = Vector3(10.0, 1.0, -0.70)
	anatomy_area.configure(&"TORSO", movement_proxy)
	var anatomy_shape_node := CollisionShape3D.new()
	var anatomy_shape := SphereShape3D.new()
	anatomy_shape.radius = 0.25
	anatomy_shape_node.shape = anatomy_shape
	anatomy_area.add_child(anatomy_shape_node)
	world_root.add_child(anatomy_area)

	await process_frame
	await physics_frame

	var proxy_trace := AnatomicalHitResolver.trace(
		world_root.get_world_3d().direct_space_state,
		Vector3(10.0, 1.0, 1.0),
		Vector3(10.0, 1.0, -2.0),
		[]
	)
	_assert(
		StringName(proxy_trace.get("hit_region", &"")) == &"TORSO",
		"movement capsule blocked the animated anatomical hurtbox behind it"
	)

	var rig: Node3D = dummy.get_hurtbox_rig()
	_assert(rig != null, "animated hurtbox rig was not created")
	if rig == null:
		_finish()
		return

	var regions: Array[StringName] = rig.get_region_names()
	for required in REQUIRED_REGIONS:
		_assert(regions.has(required), "missing region %s" % required)
	_assert(
		HurtboxProfile.CURRENT_SCHEMA_VERSION >= 6
		and HurtboxProfile.damage_type_for_source_region(&"neck") == &"NECK",
		"neck anatomy is not part of the versioned shared profile"
	)
	var profile_document: Variant = JSON.parse_string(
		FileAccess.get_file_as_string(HurtboxProfile.CONFIG_PATH)
	)
	_assert(
		profile_document is Dictionary
		and int((profile_document as Dictionary).get("schema_version", 0))
			== HurtboxProfile.CURRENT_SCHEMA_VERSION,
		"saved hurtbox profile version does not match the runtime contract"
	)
	var neck_area: Area3D = rig.get_region_area(&"NECK")
	var head_area: Area3D = rig.get_region_area(&"HEAD")
	var torso_area: Area3D = rig.get_region_area(&"TORSO")
	_assert(
		neck_area != null and head_area != null and torso_area != null,
		"head, neck, and torso areas do not form a complete core stack"
	)
	if neck_area != null and head_area != null and torso_area != null:
		var neck_shape := (neck_area.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		_assert(
			neck_area.global_position.y < head_area.global_position.y
			and neck_area.global_position.y > torso_area.global_position.y,
			"neck hurtbox is outside the visible head-to-torso span"
		)
		_assert(
			neck_shape.radius <= 0.08 and neck_shape.height <= 0.16,
			"neck hurtbox exceeds the calibrated production-character silhouette"
		)
		_assert(
			_has_region(_point_hits(neck_area.global_position), &"NECK"),
			"physics point at neck center did not resolve the neck area"
		)
		var neck_damage: Dictionary = neck_area.take_bullet_damage(
			5.0,
			neck_area.global_position,
			Vector3.BACK,
			neck_area.global_position + Vector3.BACK
		)
		_assert(
			bool(neck_damage.get("accepted", false))
			and StringName(neck_damage.get("hit_region", &"")) == &"NECK"
			and not bool(neck_damage.get("headshot", true)),
			"neck damage did not preserve its non-headshot anatomical identity"
		)

	# Core anatomy wins at a joint overlap and when a bullet continues through
	# an arm into the same operator's torso.
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
	var arm_through_core_choice: Dictionary = AnatomicalHitResolver.choose_hit([
		{"hit_region": &"RIGHT_FOREARM", "distance": 4.00},
		{"hit_region": &"TORSO", "distance": 4.30},
	])
	_assert(
		StringName(arm_through_core_choice.get("hit_region", &"")) == &"TORSO",
		"arm penetration into the same operator core was not resolved to torso"
	)
	var exposed_limb_choice: Dictionary = AnatomicalHitResolver.choose_hit([
		{"hit_region": &"RIGHT_FOREARM", "distance": 4.00},
	])
	_assert(
		StringName(exposed_limb_choice.get("hit_region", &"")) == &"RIGHT_FOREARM",
		"an arm outside the body silhouette remains limb damage"
	)
	var distant_core_choice: Dictionary = AnatomicalHitResolver.choose_hit([
		{"hit_region": &"RIGHT_FOREARM", "distance": 4.00},
		{"hit_region": &"TORSO", "distance": 4.80},
	])
	_assert(
		StringName(distant_core_choice.get("hit_region", &"")) == &"RIGHT_FOREARM",
		"an implausibly distant core does not absorb an exposed arm hit"
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
		HurtboxProfile.set_geometry_length_scale(layout_edit, &"torso", 0.60)
		rig.apply_geometry_tuning(layout_edit)
		_assert(
			torso_for_layout.global_position.distance_to(torso_position_before) > 0.05,
			"torso center edit did not move its physics area"
		)
		_assert(
			torso_shape.height <= torso_height_before + 0.001,
			"torso length edit grew beyond its calibrated physics capsule"
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

	# Extra authored shapes are real physics areas. Their anchor follows the
	# original bone span, while damage paint is an independent identity.
	rig.apply_custom_hitboxes([{
		"id": "left_upper_arm_extra_test",
		"source_region": "left_upper_arm",
		"damage_region": "NECK",
		"display_name": "Neck fill test",
		"width_scale": 5.0,
		"geometry": {
			"offset": {"x": 9.0, "y": 0.0, "z": 0.0},
			"length_scale": 5.0,
		},
	}])
	var custom_area: Area3D = rig.get_editor_hitbox_area(&"left_upper_arm_extra_test")
	_assert(custom_area != null, "custom hitbox did not create a physics area")
	_assert(
		rig.get_hurtbox_areas().size() == REQUIRED_REGIONS.size() + 1,
		"custom hitbox did not increase the physical hurtbox count"
	)
	if custom_area:
		_assert(custom_area.get_hit_region() == &"NECK", "custom hitbox paint was not applied")
		var custom_shape := (custom_area.get_child(0) as CollisionShape3D).shape as CapsuleShape3D
		_assert(
			custom_shape.radius <= SocomAnimatedHurtboxRig.UPPER_ARM_RADIUS * float(rig.get_radius_scales().get("global", 0.88)) + 0.001,
			"custom hitbox width exceeded its calibrated rig anchor"
		)
	var normalized_custom: Array[Dictionary] = rig.get_custom_hitboxes()
	_assert(
		is_equal_approx(float(normalized_custom[0].get("width_scale", 0.0)), HurtboxProfile.MAX_SCALE),
		"custom hitbox width was not bounded by the rig"
	)
	_assert(
		is_equal_approx(float((normalized_custom[0].get("geometry", {}) as Dictionary).get("length_scale", 0.0)), HurtboxProfile.MAX_LENGTH_SCALE),
		"custom hitbox length was not bounded by the rig"
	)
	if custom_area:
		var custom_area_id := custom_area.get_instance_id()
		var fluid_edit := normalized_custom.duplicate(true)
		fluid_edit[0]["width_scale"] = 0.55
		(fluid_edit[0]["geometry"] as Dictionary)["shape"] = "box"
		rig.apply_custom_hitboxes(fluid_edit)
		var fluid_area: Area3D = rig.get_editor_hitbox_area(&"left_upper_arm_extra_test")
		_assert(
			fluid_area != null and fluid_area.get_instance_id() == custom_area_id,
			"fluid custom hitbox shape change rebuilt the physics area"
		)
		_assert(
			fluid_area != null
			and (fluid_area.get_child(0) as CollisionShape3D).shape is BoxShape3D,
			"custom hitbox did not switch to real box collision geometry"
		)
	rig.apply_custom_hitboxes([])

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

		# Shoot the exposed arm from the front so this path does not continue
		# through the torso. A lateral path through arm + torso is intentionally
		# resolved as core anatomy by the production resolver.
		var authority_origin := left_arm.global_position + Vector3.BACK * 1.5
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

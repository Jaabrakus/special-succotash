extends SceneTree

## Direct proof of the live render-mesh -> Skeleton3D -> modifier hierarchy.
## This does not trust configuration files or construction comments. It inspects
## the instantiated canonical main scene after the production player is ready.

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(75):
		await process_frame

	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(driver != null, "production animation owner exists")
	if driver == null:
		_finish()
		return
	var skeleton := driver.get("skeleton") as Skeleton3D
	_expect(skeleton != null, "production owner exposes a live Skeleton3D")
	if skeleton == null:
		_finish()
		return
	print("SKELETON_PROOF path=%s class=%s bones=%d" % [
		skeleton.get_path(), skeleton.get_class(), skeleton.get_bone_count(),
	])
	_expect(skeleton.get_bone_count() == 65, "live Skeleton3D has canonical 65 bones")

	var skinned_meshes: Array[MeshInstance3D] = []
	_collect_skinned_meshes(driver, skinned_meshes)
	_expect(not skinned_meshes.is_empty(), "production player has rendered skinned meshes")
	var mesh_resolves_live_skeleton := false
	for mesh_instance in skinned_meshes:
		var skeleton_path := mesh_instance.skeleton
		var resolved := mesh_instance.get_node_or_null(skeleton_path)
		var skin_bound := mesh_instance.skin != null
		print("SKELETON_PROOF mesh=%s skeleton_path=%s resolved=%s skin=%s" % [
			mesh_instance.get_path(),
			skeleton_path,
			resolved.get_path() if resolved != null else NodePath(""),
			skin_bound,
		])
		if resolved == skeleton and skin_bound:
			mesh_resolves_live_skeleton = true
	_expect(
		mesh_resolves_live_skeleton,
		"a rendered mesh Skin resolves directly to the production Skeleton3D"
	)

	var modifier_names: Array[String] = []
	var modifiers_by_name: Dictionary = {}
	for child in skeleton.get_children():
		if child is SkeletonModifier3D:
			modifier_names.append(String(child.name))
			modifiers_by_name[String(child.name)] = child
			var running: Variant = (
				child.call("is_running") if child.has_method("is_running") else "n/a"
			)
			print("SKELETON_PROOF modifier=%s class=%s parent=%s active=%s running=%s influence=%.3f" % [
				child.name,
				child.get_class(),
				child.get_parent().get_path(),
				child.active,
				running,
				float(child.influence),
			])
	for required_name in [
		"SpineCCDIK3D",
		"TargetPivotArmAimModifier",
		"WeaponHandAttachmentModifier",
		"LHTwoBoneIK3D",
		"LHCopyTransformModifier3D2",
		"LeftHandContactObserver",
	]:
		_expect(required_name in modifier_names, "live Skeleton3D owns %s" % required_name)

	var hierarchy := [
		["IKModifier3D", "SkeletonModifier3D"],
		["ChainIK3D", "IKModifier3D"],
		["IterateIK3D", "ChainIK3D"],
		["CCDIK3D", "IterateIK3D"],
		["FABRIK3D", "IterateIK3D"],
		["JacobianIK3D", "IterateIK3D"],
		["TwoBoneIK3D", "IKModifier3D"],
	]
	for relation in hierarchy:
		var child_class: String = relation[0]
		var parent_class: String = relation[1]
		var actual_parent := ClassDB.get_parent_class(child_class)
		print("SKELETON_PROOF class=%s parent=%s" % [child_class, actual_parent])
		_expect(
			actual_parent == parent_class,
			"ClassDB confirms %s is directly under %s" % [child_class, parent_class]
		)

	var mannequin := scene.get_node_or_null("Player/Mannequin")
	if mannequin != null and mannequin.has_method("notify_operator_fired"):
		mannequin.call("notify_operator_fired")
	for _frame in range(20):
		await process_frame
	var authored_left := modifiers_by_name.get("LHTwoBoneIK3D") as SkeletonModifier3D
	var legacy_right := modifiers_by_name.get("RuntimeRightHandIK") as SkeletonIK3D
	var legacy_left := modifiers_by_name.get("RuntimeLeftHandIK") as SkeletonIK3D
	var old_native_left := modifiers_by_name.get("NativePresentationLeftHandIK") as SkeletonModifier3D
	_expect(
		authored_left != null
		and authored_left.active
		and authored_left.influence > 0.90,
		"combat mode activates TargetPivot support-hand IK"
	)
	var authored_spine := modifiers_by_name.get("SpineCCDIK3D") as SkeletonModifier3D
	_expect(
		authored_spine != null and authored_spine.influence > 0.90,
		"combat mode activates constrained TargetPivot spine CCD"
	)
	var authored_mount := modifiers_by_name.get("WeaponHandAttachmentModifier") as SkeletonModifier3D
	_expect(
		authored_mount != null and authored_mount.active and authored_mount.influence > 0.9,
		"right-hand weapon mount remains active while animation owns the arms"
	)
	_expect(
		legacy_right != null and not legacy_right.is_running(),
		"legacy right-hand SkeletonIK3D is stopped"
	)
	_expect(
		legacy_left != null and not legacy_left.is_running(),
		"legacy left-hand SkeletonIK3D is stopped"
	)
	_expect(
		old_native_left != null and not old_native_left.active,
		"previous native support-hand modifier is inactive"
	)
	var graph_runtime = driver.get("godot_ik_aim_runtime")
	var debug: Dictionary = (
		graph_runtime.get_debug_state()
		if graph_runtime != null and graph_runtime.has_method("get_debug_state")
		else {}
	)
	print("SKELETON_PROOF runtime=%s" % JSON.stringify(debug))
	_expect(
		StringName(debug.get("owner", &"")) == &"PLAYER_TARGET_PIVOT_GRIP",
		"live modifier graph reports player-owned grip authority"
	)
	_expect(
		int((debug.get("weapon_attachment", {}) as Dictionary).get("process_count", 0)) > 0,
		"weapon attachment modifier processed rendered frames"
	)
	_expect(
		int((debug.get("support_contact", {}) as Dictionary).get("process_count", 0)) > 0,
		"support-hand contact observer processed rendered frames"
	)

	scene.queue_free()
	_finish()


func _collect_skinned_meshes(node: Node, output: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if not mesh_instance.skeleton.is_empty():
			output.append(mesh_instance)
	for child in node.get_children():
		_collect_skinned_meshes(child, output)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("SKELETON_PROOF PASS ", label)
	else:
		failures.append(label)
		push_error("SKELETON_PROOF FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("RUNTIME_SKELETON_MODIFIER_PROOF PASS")
		quit(0)
	else:
		print("RUNTIME_SKELETON_MODIFIER_PROOF FAIL %s" % [failures])
		quit(1)

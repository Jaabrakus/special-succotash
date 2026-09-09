extends SceneTree

const BASE := "res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx"
const GLB := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.glb"
const SCENE := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
const Adapter := preload("res://scripts/player/operator_native_rig_adapter.gd")
const Contract := preload("res://scripts/player/operator_skeleton_contract.gd")
const Runtime := preload("res://scripts/player/operator_asset_runtime.gd")
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _find(node: Node, type: String) -> Node:
	if node.is_class(type):
		return node
	for child in node.get_children():
		var result := _find(child, type)
		if result != null:
			return result
	return null

func _expect(ok: bool, label: String) -> void:
	if not ok:
		print("DUAL_RIG FAIL ", label)
	if not ok:
		failures.append(label)

func _run() -> void:
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	_expect(doc.append_from_file(GLB, state) == OK, "GLB loads")
	var candidate := doc.generate_scene(state)
	root.add_child(candidate)
	var source := (load(BASE) as PackedScene).instantiate()
	root.add_child(source)
	var old := _find(source, "Skeleton3D") as Skeleton3D
	var rig := _find(candidate, "Skeleton3D") as Skeleton3D
	_normalize_runtime_space(candidate, rig, old)
	_expect(FileAccess.get_file_as_string("res://scenes/player/operator_player.tscn").contains(SCENE), "canonical scene selects shared rig")
	_expect(FileAccess.get_file_as_string("res://scripts/player/operator_asset_runtime.gd").contains(SCENE), "fallback runtime selects shared rig")
	_expect(rig.get_bone_count() == 65, "65 authored bones")
	var rest_error := 0.0
	var angle_error := 0.0
	for bone in old.get_bone_count():
		var name := old.get_bone_name(bone)
		var target := rig.find_bone(name)
		_expect(target >= 0, "original bone " + name)
		_expect(target == bone, "native bone index " + name)
		if target < 0:
			continue
		var a := old.global_transform * old.get_bone_global_rest(bone)
		var b := rig.global_transform * rig.get_bone_global_rest(target)
		rest_error = maxf(rest_error, a.origin.distance_to(b.origin)*62.0)
		angle_error = maxf(angle_error, rad_to_deg(a.basis.orthonormalized().get_rotation_quaternion().angle_to(b.basis.orthonormalized().get_rotation_quaternion())))
	_expect(rest_error < .001 and angle_error < .1, "native rests and wrist anchors preserved")
	var rests: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		rests.append(rig.get_bone_rest(bone))
	Contract.ensure_65_bones(rig)
	for bone in rig.get_bone_count():
		_expect(rests[bone].is_equal_approx(rig.get_bone_rest(bone)), "runtime preserves authored rest %d" % bone)
	var mesh := _find(candidate, "MeshInstance3D") as MeshInstance3D
	var weighted := {}
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		for i in bones.size():
			if weights[i] > .1:
				var name := String(mesh.skin.get_bind_name(bones[i]))
				if name.is_empty():
					name = rig.get_bone_name(mesh.skin.get_bind_bone(bones[i]))
				weighted[name] = true
	for side in ["Left", "Right"]:
		for finger in ["Middle", "Ring", "Pinky"]:
			for segment in range(1,4):
				_expect(weighted.has("mixamorig_%sHand%s%d" % [side,finger,segment]), "weighted %s %s %d" % [side,finger,segment])
	var player := AnimationPlayer.new()
	rig.add_child(player)
	player.root_node = NodePath("..")
	var runtime := Runtime.new()
	runtime.skeleton = rig
	runtime.animation_player = player
	for path in ["res://assets/animations/mixamo/Reload.fbx", "res://assets/external/agls_intake/imported/weapon_reload/ALSP2_Reloading_Rifle_AK47.scn"]:
		var animated := (load(path) as PackedScene).instantiate()
		root.add_child(animated)
		var source_player := _find(animated, "AnimationPlayer") as AnimationPlayer
		var source_rig := _find(animated, "Skeleton3D") as Skeleton3D
		var clip: Animation
		for name in source_player.get_animation_list():
			if name != &"RESET":
				clip = source_player.get_animation(name)
				break
		var baked := runtime._retarget_animation(clip, source_rig)
		_expect(baked.get_track_count() > 20, "retarget tracks " + path.get_file())
		for track in baked.get_track_count():
			_expect(rig.find_bone(String(baked.track_get_path(track)).get_slice(":",1)) >= 0, "resolved track")
		var library := AnimationLibrary.new()
		library.add_animation("trial", baked)
		player.add_animation_library("", library)
		player.play("trial")
		player.seek(0, true)
		rig.force_update_all_bone_transforms()
		var hand := rig.find_bone("mixamorig_LeftHand")
		var first := rig.get_bone_global_pose(hand)
		var first_points := _points(mesh, rig)
		player.seek(baked.length*.5, true)
		rig.force_update_all_bone_transforms()
		_expect(not first.is_equal_approx(rig.get_bone_global_pose(hand)), "hand changes across " + path.get_file())
		var second_points := _points(mesh, rig)
		var surface_motion := 0.0
		for i in first_points.size():
			surface_motion = maxf(surface_motion, first_points[i].distance_to(second_points[i])*62.0)
		_expect(surface_motion > .01, "visible mesh deforms for " + path.get_file())
		var baseline_player := AnimationPlayer.new()
		old.add_child(baseline_player)
		baseline_player.root_node = NodePath("..")
		var baseline_runtime := Runtime.new()
		baseline_runtime.skeleton = old
		baseline_runtime.animation_player = baseline_player
		var baseline_clip := baseline_runtime._retarget_animation(clip, source_rig)
		var baseline_library := AnimationLibrary.new()
		baseline_library.add_animation("trial", baseline_clip)
		baseline_player.add_animation_library("", baseline_library)
		baseline_player.play("trial")
		baseline_player.seek(baked.length*.5, true)
		old.force_update_all_bone_transforms()
		for name in ["mixamorig_Hips", "mixamorig_Head", "mixamorig_LeftHand", "mixamorig_RightHand", "mixamorig_LeftFoot", "mixamorig_RightFoot"]:
			var a := rig.global_transform * rig.get_bone_global_pose(rig.find_bone(name))
			var b := old.global_transform * old.get_bone_global_pose(old.find_bone(name))
			_expect(a.origin.distance_to(b.origin)*62.0 < .001, "animated native placement " + name + " " + path.get_file())
		baseline_player.free()
		old.reset_bone_poses()
		player.stop()
		player.remove_animation_library("")
		animated.free()
	player.free()
	rig.reset_bone_poses()
	if failures.is_empty() and OS.get_cmdline_user_args().has("--publish"):
		var packed := PackedScene.new()
		_expect(packed.pack(candidate) == OK, "pack runtime asset")
		_expect(ResourceSaver.save(packed, SCENE) == OK, "publish runtime asset")
	source.free()
	candidate.free()
	print("DUAL_SOURCE_RIG_RESULT ", "PASS" if failures.is_empty() else failures)
	quit(0 if failures.is_empty() else 1)

func _normalize_runtime_space(candidate: Node3D, rig: Skeleton3D, native: Skeleton3D) -> void:
	# Blender GLB retains an object-level .01 axis conversion, whereas Godot's
	# canonical FBX bakes it into the rest skeleton. Existing Mixamo keys and IK
	# expect the FBX space. Normalize rests AND inverse binds, preserving shape.
	var mesh := _find(candidate, "MeshInstance3D") as MeshInstance3D
	rig.reset_bone_poses()
	rig.force_update_all_bone_transforms()
	var before := _points(mesh, rig)
	var conversion := native.global_transform.affine_inverse() * rig.global_transform
	var previous: Array[Transform3D] = []
	var desired: Array[Transform3D] = []
	for bone in rig.get_bone_count():
		previous.append(rig.get_bone_global_rest(bone))
		var native_index := native.find_bone(rig.get_bone_name(bone))
		var rest := conversion * previous[bone]
		rest.basis = rest.basis.orthonormalized()
		if native_index >= 0:
			rest = native.get_bone_global_rest(native_index)
		desired.append(rest)
	for bone in rig.get_bone_count():
		var parent := rig.get_bone_parent(bone)
		rig.set_bone_rest(bone, desired[parent].affine_inverse() * desired[bone] if parent >= 0 else desired[bone])
	mesh.skin = mesh.skin.duplicate() as Skin
	for bind in mesh.skin.get_bind_count():
		var bone := rig.find_bone(mesh.skin.get_bind_name(bind))
		if bone < 0:
			bone = mesh.skin.get_bind_bone(bind)
		mesh.skin.set_bind_pose(bind, desired[bone].affine_inverse() * conversion * previous[bone] * mesh.skin.get_bind_pose(bind))
		mesh.skin.set_bind_name(bind, rig.get_bone_name(bone))
	# Keep the native 41 indices too; gameplay readers may cache bone indices.
	var names: Array[String] = []
	var local_rests := {}
	var parents := {}
	for bone in rig.get_bone_count():
		var name := String(rig.get_bone_name(bone))
		local_rests[name] = rig.get_bone_rest(bone)
		var parent := rig.get_bone_parent(bone)
		parents[name] = String(rig.get_bone_name(parent)) if parent >= 0 else ""
	for bone in native.get_bone_count():
		names.append(String(native.get_bone_name(bone)))
	for side in ["Left", "Right"]:
		for finger in ["Middle", "Ring", "Pinky"]:
			for segment in range(1,5):
				names.append("mixamorig_%sHand%s%d" % [side,finger,segment])
	rig.clear_bones()
	for name in names:
		rig.add_bone(name)
	for name in names:
		var bone := rig.find_bone(name)
		rig.set_bone_parent(bone, rig.find_bone(parents[name]))
		rig.set_bone_rest(bone, local_rests[name])
	for bind in mesh.skin.get_bind_count():
		mesh.skin.set_bind_bone(bind, rig.find_bone(mesh.skin.get_bind_name(bind)))
	rig.global_transform = native.global_transform
	rig.reset_bone_poses()
	rig.force_update_all_bone_transforms()
	var after := _points(mesh, rig)
	var error := 0.0
	for i in before.size():
		error = maxf(error, before[i].distance_to(after[i])*62.0)
	_expect(error < .001, "space normalization preserves skinned surface within 1mm")
	_expect(rig.global_transform.is_equal_approx(native.global_transform), "native runtime skeleton coordinate space")

func _points(mesh: MeshInstance3D, rig: Skeleton3D) -> PackedVector3Array:
	var result := PackedVector3Array()
	for surface in mesh.mesh.get_surface_count():
		var arrays := mesh.mesh.surface_get_arrays(surface)
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
		var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
		var stride := weights.size() / vertices.size()
		for vertex in vertices.size():
			var point := Vector3.ZERO
			for slot in stride:
				var offset := vertex*stride+slot
				if weights[offset] <= .000001:
					continue
				var bind := bones[offset]
				var bone := rig.find_bone(mesh.skin.get_bind_name(bind))
				if bone < 0:
					bone = mesh.skin.get_bind_bone(bind)
				point += (rig.global_transform * rig.get_bone_global_pose(bone) * mesh.skin.get_bind_pose(bind) * vertices[vertex]) * weights[offset]
			result.append(point)
	return result

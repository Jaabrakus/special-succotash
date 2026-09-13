extends SceneTree

const Appearance := preload("res://scripts/player/character_appearance_profile.gd")
const Team := preload("res://scripts/player/operator_team_appearance.gd")
const BASE := "res://assets/characters/ps1_dual_source_rig/ps1_dual_source_rig.scn"
var MODERN: String = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_character.json")).scene
var failures: Array[String] = []
var checked_vertices := 0
var checked_pose_samples := 0

func _initialize() -> void:
	_run.call_deferred()

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("MODERN_FAIL ", label)

func _run() -> void:
	var model := (load(MODERN) as PackedScene).instantiate() as Node3D
	var original := (load(BASE) as PackedScene).instantiate() as Node3D
	root.add_child(model)
	root.add_child(original)
	var skeleton := model.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var previous := original.find_children("*", "Skeleton3D", true, false)[0] as Skeleton3D
	var proportional := skeleton.has_meta("iso_proportions")
	check(skeleton.get_bone_count() == 65, "65-bone animation contract")
	for bone in previous.get_bone_count():
		check(skeleton.get_bone_name(bone) == previous.get_bone_name(bone), "stable bone index")
		check(skeleton.get_bone_parent(bone) == previous.get_bone_parent(bone), "unchanged bone parent")
		if proportional:
			check(skeleton.get_bone_rest(bone).basis.is_equal_approx(previous.get_bone_rest(bone).basis), "unchanged animation rest orientation")
			check(skeleton.get_meta("canonical_rest_before_proportions")[bone].is_equal_approx(previous.get_bone_rest(bone)), "preserved canonical animation baseline")
		else:
			check(skeleton.get_bone_rest(bone).is_equal_approx(previous.get_bone_rest(bone)), "unchanged bone rest")
			check(skeleton.get_bone_global_rest(bone).is_equal_approx(previous.get_bone_global_rest(bone)), "unchanged accumulated rest")
	if proportional:
		_check_iso_proportions(skeleton)
	check(model.transform.is_equal_approx(original.transform), "unchanged model transform")
	check(model.get_global_transform().affine_inverse() * skeleton.global_transform == original.get_global_transform().affine_inverse() * previous.global_transform, "unchanged skeleton node transform")
	var meshes := model.find_children("*", "MeshInstance3D", true, false)
	check(meshes.size() == 14, "14 runtime mesh sections; unmasked eyelash card excluded")
	var weighted := {}
	for mesh: MeshInstance3D in meshes:
		check(mesh.skin != null and mesh.get_node(mesh.skeleton) == skeleton, "one skin owner " + mesh.name)
		check(mesh.transform.is_equal_approx(Transform3D.IDENTITY), "no double mesh transform " + mesh.name)
		check(mesh.skin.get_bind_count() == 65, "complete skin binds " + mesh.name)
		for bind in mesh.skin.get_bind_count():
			var bone := skeleton.find_bone(mesh.skin.get_bind_name(bind))
			check(bone >= 0, "resolved skin bind " + mesh.name)
			if bone >= 0:
				check((skeleton.get_bone_global_rest(bone) * mesh.skin.get_bind_pose(bind)).is_equal_approx(Transform3D.IDENTITY), "inverse bind cancels rest " + mesh.name)
		for surface in mesh.mesh.get_surface_count():
			var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
			check(mat != null and mat.albedo_texture != null, "textured " + mesh.name)
			check(mat.albedo_texture is PortableCompressedTexture2D, "portable compressed textures")
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var indices: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			var stride := weights.size() / vertices.size()
			check(stride == 4 and indices.size() == weights.size(), "four valid influences per vertex")
			checked_vertices += vertices.size()
			for v in vertices.size():
				var total := 0.0
				for slot in stride:
					var index := v * stride + slot
					check(is_finite(weights[index]) and weights[index] >= 0.0, "nonnegative finite weight")
					check(indices[index] >= 0 and indices[index] < mesh.skin.get_bind_count(), "skin index in range")
					total += weights[index]
					if weights[index] > .01:
						weighted[String(mesh.skin.get_bind_name(indices[index]))] = true
				check(absf(total - 1.0) < .002 and vertices[v].is_finite(), "finite normalized skin weights")
	for side in ["Left", "Right"]:
		for finger in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
			for segment in range(1, 4):
				check(weighted.has("mixamorig_%sHand%s%d" % [side, finger, segment]), "weighted finger " + side + finger + str(segment))
	var choices := Appearance.defaults()
	choices.cap = false
	choices.patches = true
	choices.shirt = "green"
	check(Appearance.save_profile(choices, "/private/tmp/modern-appearance-test.json") == OK, "save profile")
	check(Appearance.load_profile("/private/tmp/modern-appearance-test.json") == choices, "load exact saved profile")
	Team.apply(model, 0, "black", choices)
	check(not (model.find_child("Cap", true, false) as Node3D).visible, "cap toggle")
	check(not (model.find_child("SKM_Patch_Flag_Cap", true, false) as Node3D).visible, "cap patch follows cap")
	Team.apply(model, 1, "")
	check((model.find_child("Cap", true, false) as Node3D).visible, "remote default unaffected by local customization")
	var actor := (load("res://scenes/player/operator_player.tscn") as PackedScene).instantiate() as CharacterBody3D
	root.add_child(actor)
	actor.set_physics_process(false)
	var driver := actor.get_node("Mannequin/ProductionAnimation")
	check(driver.model_root.get_meta("socom_modern_character", false), "canonical player uses selected character")
	check(is_equal_approx(actor.get_node("CollisionShape3D").shape.height, 1.85), "collision height preserved")
	driver.set_process(false)
	driver.animation_tree.active = false
	var pose_meshes: Array[Node] = driver.model_root.find_children("*", "MeshInstance3D", true, false)
	var character_meshes: Array[MeshInstance3D] = []
	for mesh: MeshInstance3D in pose_meshes:
		if mesh.get_meta("socom_modern_character", false):
			character_meshes.append(mesh)
	var animation_root: Node = driver.animation_player.get_node(driver.animation_player.root_node)
	for name in driver.animation_player.get_animation_list():
		var animation: Animation = driver.animation_player.get_animation(name)
		if proportional:
			check(animation.get_meta("iso_proportion_adapted", false), "runtime animation proportion adapted " + name)
		for track in animation.get_track_count():
			if animation.track_get_type(track) not in [Animation.TYPE_POSITION_3D, Animation.TYPE_ROTATION_3D, Animation.TYPE_SCALE_3D]:
				continue
			var path := animation.track_get_path(track)
			var target := animation_root.get_node_or_null(NodePath(path.get_concatenated_names()))
			check(target != null, "animation node resolves " + String(path))
			if target is Skeleton3D and path.get_subname_count() > 0:
				check(target.find_bone(path.get_subname(0)) >= 0, "animation bone resolves " + String(path))
	for clip in ["aim_idle", "aim_idle_crouch", "idle_prone", "run_forward", "jump_dive_right", "crouch_dive_left", "reload", "death_right"]:
		var found := false
		for animation_name in driver.animation_player.get_animation_list():
			if String(animation_name).get_slice("/", 1) != clip:
				continue
			found = true
			var animation := driver.animation_player.get_animation(animation_name) as Animation
			for fraction in [.1, .5, .9]:
				driver.skeleton.clear_bones_global_pose_override()
				driver.skeleton.reset_bone_poses()
				driver.animation_player.play(animation_name)
				driver.animation_player.seek(animation.length * fraction, true)
				driver.animation_player.advance(0.0)
				for bone in driver.skeleton.get_bone_count():
					check(driver.skeleton.get_bone_global_pose(bone).is_finite(), "finite pose " + clip)
				_check_deformed_vertices(driver.skeleton, character_meshes, clip + ":" + str(fraction))
		check(found, "clip exists " + clip)
	# Both network combatants and solo construct the same production driver.
	var remote := load("res://scripts/network/socom_network_operator.gd").new() as CharacterBody3D
	remote.name = "ModernRemoteProof"
	root.add_child(remote)
	remote.set_physics_process(false)
	# The network actor binds hurtboxes after its own deferred process-frame wait.
	await process_frame
	await process_frame
	check(remote.get_node("Mannequin/ProductionAnimation/TrooperModel").get_meta("socom_modern_character", false), "network operator uses modern rig")
	var remote_skeleton: Skeleton3D = remote.get_node("Mannequin/ProductionAnimation").skeleton
	for bone in skeleton.get_bone_count():
		check(remote_skeleton.get_bone_global_rest(bone).is_equal_approx(skeleton.get_bone_global_rest(bone)), "remote rest parity")
	remote.free()
	actor.free()
	model.free()
	original.free()
	print("MODERN_SOLDIER_REGRESSION ", "PASS" if failures.is_empty() else failures)
	print("RIG_AUDIT vertices=", checked_vertices, " deformation_samples=", checked_pose_samples)
	quit(0 if failures.is_empty() else 1)

func _check_deformed_vertices(skeleton: Skeleton3D, meshes: Array[MeshInstance3D], label: String) -> void:
	# CPU evaluation of every character vertex, independent of renderer culling.
	# This is a coarse explosion/invalid-bind check, not an anatomical quality score.
	var hips := skeleton.get_bone_global_pose(skeleton.find_bone("mixamorig_Hips")).origin
	var maximum_radius := 0.0
	for mesh in meshes:
		var palette: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			palette.append(skeleton.get_bone_global_pose(skeleton.find_bone(mesh.skin.get_bind_name(bind))) * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var arrays := mesh.mesh.surface_get_arrays(surface)
			var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
			for v in vertices.size():
				var point := Vector3.ZERO
				for slot in 4:
					var index := v * 4 + slot
					point += (palette[bones[index]] * vertices[v]) * weights[index]
				check(point.is_finite(), "finite deformed vertex " + label)
				maximum_radius = maxf(maximum_radius, (skeleton.global_basis * (point - hips)).length())
	check(maximum_radius < 2.5, "bounded deformed character " + label)
	checked_pose_samples += 1
	print("RIG_DEFORMATION ", label, " hip_radius_m=", maximum_radius)

func _check_iso_proportions(skeleton: Skeleton3D) -> void:
	var profile: Dictionary = skeleton.get_meta("iso_proportions")
	var points: Dictionary = profile.landmarks
	var scale: float = profile.metres_per_source_unit
	var maximum_error := 0.0
	# Every pair tests relative proportion, including shoulder/hip width and
	# torso/neck lengths, independent of native source units or facing direction.
	for a: String in points:
		for b: String in points:
			var expected := Vector3(points[a][0],points[a][1],points[a][2]).distance_to(Vector3(points[b][0],points[b][1],points[b][2])) * scale
			var actual := skeleton.get_bone_global_rest(skeleton.find_bone(a)).origin.distance_to(skeleton.get_bone_global_rest(skeleton.find_bone(b)).origin) * 62.0
			maximum_error = maxf(maximum_error, absf(actual - expected))
	check(maximum_error < .0001, "ISO body landmark proportions within 0.1 mm")
	print("ISO_PROPORTIONS landmarks=", points.size(), " maximum_distance_error_m=", maximum_error)

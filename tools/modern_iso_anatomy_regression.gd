extends SceneTree

## Measures actual rest-mesh edges, not just metadata or skeleton coordinates.
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var selected: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/operator_character.json"))
	var args := OS.get_cmdline_user_args()
	if args.has("--candidate"):
		selected.scene = args[args.find("--candidate") + 1]
	var target := (load(selected.scene) as PackedScene).instantiate() as Node3D
	root.add_child(target)
	var rig: Skeleton3D = target.find_children("*", "Skeleton3D", true, false)[0]
	var profile: Dictionary = rig.get_meta("iso_proportions", {})
	check(not profile.is_empty(), "selected asset has ISO proportions")
	if profile.is_empty():
		quit(1)
		return
	check(profile.get("skin_fit", {}).get("revision", 0) >= 2, "coherent anatomical fit revision")
	check(float(profile.skin_fit.neck_anchor_error_m) < .0001, "continuous neck anchor")
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	assert(doc.append_from_file("res://art_source/modern_soldier/modern_soldier_native.glb", state) == OK)
	var source := doc.generate_scene(state)
	root.add_child(source)
	var source_rig: Skeleton3D = source.find_children("*", "Skeleton3D", true, false)[0]
	var checked := 0
	var maximum := 0.0
	for mesh: MeshInstance3D in source.find_children("*", "MeshInstance3D", true, false):
		if String(mesh.name) not in ["Head", "Shirt"] and not "Shirt" in String(mesh.name):
			continue
		var fitted := target.find_child(String(mesh.name), true, false) as MeshInstance3D
		check(fitted != null, "corresponding modern mesh " + String(mesh.name))
		if fitted == null: continue
		var palette: Array[Transform3D] = []
		for bind in mesh.skin.get_bind_count():
			var index := source_rig.find_bone(mesh.skin.get_bind_name(bind))
			if index < 0:
				index = mesh.skin.get_bind_bone(bind)
			assert(index >= 0 and index < source_rig.get_bone_count(), "Valid source skin bind")
			palette.append(source_rig.global_transform * source_rig.get_bone_global_rest(index) * mesh.skin.get_bind_pose(bind))
		for surface in mesh.mesh.get_surface_count():
			var a := mesh.mesh.surface_get_arrays(surface)
			var b := fitted.mesh.surface_get_arrays(surface)
			var original: PackedVector3Array = a[Mesh.ARRAY_VERTEX]
			var converted: PackedVector3Array = b[Mesh.ARRAY_VERTEX]
			var uv_a: PackedVector2Array = a[Mesh.ARRAY_TEX_UV]
			var uv_b: PackedVector2Array = b[Mesh.ARRAY_TEX_UV]
			check(original.size() == converted.size() and uv_a == uv_b, "unchanged vertex correspondence " + String(mesh.name))
			if original.size() != converted.size() or uv_a != uv_b: continue
			var weights: PackedFloat32Array = a[Mesh.ARRAY_WEIGHTS]
			var bones: PackedInt32Array = a[Mesh.ARRAY_BONES]
			var stride := weights.size() / original.size()
			var points := PackedVector3Array()
			for v in original.size():
				var point := Vector3.ZERO
				for slot in stride:
					var offset := v * stride + slot
					point += (palette[bones[offset]] * original[v]) * weights[offset]
				points.append(point)
			var indices: PackedInt32Array = a[Mesh.ARRAY_INDEX]
			for tri in range(0, indices.size(), 3):
				for side in 3:
					var i := indices[tri + side]
					var j := indices[tri + (side + 1) % 3]
					var p := points[i]
					var q := points[j]
					# Center collar, lower head and neck: excludes limb articulation.
					if absf(p.x) > .12 or p.y < 1.38 or p.y > 1.66: continue
					var length := p.distance_to(q)
					if length < .002: continue
					var mapped_length := (fitted.global_basis * (converted[i] - converted[j]) * 62.0).length()
					var stretch := mapped_length / length
					maximum = maxf(maximum, stretch)
					checked += 1
	check(checked > 100, "neck/collar surface actually sampled")
	check(maximum < 2.0, "neck/collar edges not stretched to more than twice source length")
	print("ISO_ANATOMY edges=", checked, " maximum_neck_edge_ratio=", maximum)
	print("MODERN_ISO_ANATOMY ", "PASS" if failures.is_empty() else failures)
	source.free()
	target.free()
	quit(0 if failures.is_empty() else 1)

func check(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		print("ISO_ANATOMY_FAIL ", label)

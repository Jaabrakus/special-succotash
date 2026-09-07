extends SceneTree
## Inspection-only candidate proof. GLTFDocument reads only the two artifacts;
## no whole-project import, gameplay scene, profile assignment or bone solver.
## --capture writes independent Godot previews under /private/tmp/retro1212-preview.

const DIRECTORY := "res://assets/weapons/retro_1212/"
var failures: Array[String] = []
var capture := false

func _initialize() -> void:
	capture = "--capture" in OS.get_cmdline_user_args()
	_run.call_deferred()

func _run() -> void:
	root.size = Vector2i(1080, 480)
	for id: String in ["uzi_candidate", "pump_candidate"]:
		var metadata: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + id + ".intake.json"))
		var asset: Node3D
		if "--runtime-models" in OS.get_cmdline_user_args():
			var path := DIRECTORY + id + ".scn"
			asset = (load(path) as PackedScene).instantiate() as Node3D
			_expect(ResourceLoader.get_dependencies(path).is_empty(), id + " bundled runtime artifact has no external dependencies")
		else:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			var error := document.append_from_file(DIRECTORY + id + ".glb", state)
			_expect(error == OK, id + " GLB imports with embedded images")
			if error != OK:
				continue
			asset = document.generate_scene(state) as Node3D
		_expect(asset != null, id + " generates a Godot scene")
		if asset == null:
			continue
		root.add_child(asset)
		var meshes: Array[Node] = asset.find_children("*", "MeshInstance3D", true, false)
		var skeletons := asset.find_children("*", "Skeleton3D", true, false)
		_expect(meshes.size() == int(metadata.glb_checks.meshes), id + " all assembled meshes present")
		_expect(skeletons.size() == 1, id + " one original part skeleton")
		_expect(asset.find_children("*", "Camera3D", true, false).is_empty(), id + " no imported cameras")
		_expect(asset.find_children("*", "Light3D", true, false).is_empty(), id + " no imported lights")
		_expect(asset.find_children("*", "AnimationPlayer", true, false).is_empty(), id + " no imported gameplay/camera animation")
		_expect(asset.find_child("FPS_Arms_Mesh", true, false) == null, id + " no first person arms")
		if id == "uzi_candidate":
			_expect(asset.find_child("Magazine_Mesh", true, false) != null, id + " assembled magazine included")
			_expect(asset.find_child("Silencer_Mesh", true, false) == null, id + " unsuppressed variant")
		var bounds := AABB()
		var have_bounds := false
		var triangles := 0
		for item: Node in meshes:
			var mesh := item as MeshInstance3D
			var transformed := mesh.global_transform * mesh.get_aabb()
			bounds = bounds.merge(transformed) if have_bounds else transformed
			have_bounds = true
			_expect(mesh.skin != null, id + " part skin retained: " + mesh.name)
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				triangles += indices.size() / 3
				var mat := mesh.mesh.surface_get_material(surface) as BaseMaterial3D
				_expect(mat != null, id + " material imported")
				if mat != null:
					_expect(mat.albedo_texture != null and mat.albedo_texture.get_width() > 0, id + " embedded albedo loaded")
					_expect(mat.roughness > 0.99, id + " rough material preserved")
		_expect(triangles == int(metadata.glb_checks.triangles), id + " triangle count preserved")
		var expected_low := INF
		var expected_high := -INF
		for row: Dictionary in metadata.source_meshes:
			expected_low = minf(expected_low, float(row.bounds_min_blender_m[0]))
			expected_high = maxf(expected_high, float(row.bounds_max_blender_m[0]))
		_expect(absf(bounds.size.x - (expected_high - expected_low)) < 0.002, id + " source-to-Godot world length preserved")
		_expect(bounds.size.x > 0.50 and bounds.size.x < 1.1, id + " meter scale, not centimeters")
		var bones: Array[String] = []
		for node: Node in skeletons:
			var sk := node as Skeleton3D
			for index in sk.get_bone_count():
				bones.append(sk.get_bone_name(index))
		for row: Dictionary in metadata.source_bone_landmarks:
			_expect(bones.has(String(row.name)), id + " original part bone " + String(row.name))
		print("RETRO1212_ASSET ", id, " ", JSON.stringify({"meshes":meshes.size(),"triangles":triangles,"world_bounds":str(bounds),"bones":bones}))
		if capture:
			await _capture(asset, bounds, id)
		asset.queue_free()
		await process_frame
	print("RETRO1212_ASSETS ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _capture(asset: Node3D, bounds: AABB, id: String) -> void:
	_expect(DisplayServer.get_name() != "headless", "capture requires native display")
	if DisplayServer.get_name() == "headless":
		return
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(0.15,0.17,0.20)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color.WHITE
	environment.environment.ambient_light_energy = 0.6
	asset.add_child(environment)
	var center := bounds.get_center()
	var length := bounds.size.x
	var light := DirectionalLight3D.new()
	asset.add_child(light)
	light.position = center + Vector3(-0.3,1,1)
	light.look_at(center)
	var cam := Camera3D.new()
	asset.add_child(cam)
	cam.position = center + Vector3(length * 0.16, length * 0.48, length * 2.4)
	cam.look_at(center)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	# DisplayRuntime can restore the user's viewport/aspect after this fixture
	# starts. A conservative full-length size keeps both ends visible either way.
	cam.size = maxf(length * 1.3, bounds.size.y * 1.3)
	cam.current = true
	for frame in 8:
		await process_frame
	RenderingServer.force_draw(false)
	var image := root.get_texture().get_image()
	DirAccess.make_dir_recursive_absolute("/private/tmp/retro1212-preview")
	_expect(image.save_png("/private/tmp/retro1212-preview/" + id + "-godot.png") == OK, id + " preview saved")

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

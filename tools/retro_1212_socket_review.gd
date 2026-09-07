extends SceneTree
## Offline only: inspect the draft documents, never publish or bind them.
## Native --capture writes independent marker views from the exact saved draft.

const Rig := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const DIRECTORY := "res://art_source/retro1212_calibration/"
const OUTPUT := "/private/tmp/retro1212-calibration"
const LABELS := ["R palm", "L palm", "Muzzle", "Barrel root", "Butt", "Sight up", "Ejection"]
const KEYS := ["right_hand_grip_target", "left_hand_ik_target", "muzzle_socket", "barrel_base_socket", "buttstock_socket", "optic_rail", "ejection_port"]
const COLORS := [Color(1,.25,.22),Color(.1,1,.55),Color(1,.86,.08),Color(.2,.7,1),Color(1,.25,.9),Color(.85,.65,1),Color(1,.55,.12)]
var failures: Array[String] = []
var schema_blockers: Dictionary = {}
var runtime_candidate := false
var output_directory := OUTPUT

func _initialize() -> void:
	runtime_candidate = "--runtime-candidate" in OS.get_cmdline_user_args()
	if runtime_candidate:
		output_directory = "/private/tmp/retro1212-runtime-calibration"
	_run.call_deferred()

func _run() -> void:
	DirAccess.make_dir_recursive_absolute(output_directory)
	for id: String in ["9mm_sub", "870"]:
		var suffix := ".runtime_candidate.json" if runtime_candidate else ".visual_rig.draft.json"
		var draft: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(DIRECTORY + id + suffix))
		var visual: Dictionary = draft.visual
		_expect(draft.status == "draft", id + " remains draft")
		_expect(float(visual.normalized_scale) == 1.0 and float(visual.user_scale_multiplier) == 1.0, id + " meters already baked")
		_expect(_v(visual.model_rotation_degrees).length() == 0, id + " source +X barrel retained")
		var baseline: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapon_visual_rigs/" + String(draft.calibration.baseline_visual_rig_id) + ".json"))
		for field: String in draft.calibration.preserved_provisional_fields:
			if not runtime_candidate:
				_expect(visual[field] == baseline.visual[field], id + " preserves provisional " + field)
		var schema := Rig.validate(draft)
		if not bool(schema.ok):
			schema_blockers[id] = schema.errors
		print("RETRO1212_DRAFT_SCHEMA ", id, " ", JSON.stringify(schema))
		var asset: Node3D
		if runtime_candidate:
			asset = (load(String(visual.model_fbx)) as PackedScene).instantiate() as Node3D
		else:
			var document := GLTFDocument.new()
			var state := GLTFState.new()
			_expect(document.append_from_file(String(visual.model_fbx), state) == OK, id + " direct GLB load")
			asset = document.generate_scene(state) as Node3D
		if asset == null:
			_expect(false, id + " generated model")
			continue
		# Validate the actual generated PackedScene in this inspection process.
		# No editor import or resource file is written; the on-disk import status
		# above remains reported separately and is still required for publication.
		var inspection_scene := PackedScene.new()
		_expect(inspection_scene.pack(asset) == OK, id + " packs actual direct-loaded model")
		if not runtime_candidate:
			inspection_scene.take_over_path(String(visual.model_fbx))
		var materialized_schema := Rig.validate(draft)
		print("RETRO1212_MATERIALIZED_DRAFT_SCHEMA ", id, " ", JSON.stringify(materialized_schema))
		var viewport := SubViewport.new()
		viewport.size = Vector2i(1600,900)
		viewport.own_world_3d = true
		viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(viewport)
		viewport.add_child(asset)
		var surfaces: Dictionary = {}
		var bounds := AABB()
		var first := true
		for node: Node in asset.find_children("*", "MeshInstance3D", true, false):
			var mesh := node as MeshInstance3D
			# Mesh.get_faces() passes through a welded/rounded TriangleMesh cache.
			# Surface arrays preserve the original exported vertex coordinates.
			var faces := PackedVector3Array()
			for surface in mesh.mesh.get_surface_count():
				var arrays := mesh.mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
				for vertex_index in indices:
					faces.append(mesh.global_transform * vertices[vertex_index])
			surfaces[String(mesh.name)] = faces
			var box := mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var results: Array[Dictionary] = []
		for witness: Dictionary in draft.calibration.surface_witnesses:
			var from := _a(witness.ray_from)
			var direction := _a(witness.ray_direction)
			var to := from + direction * 2.0
			var triangles: PackedVector3Array = surfaces[witness.mesh]
			var closest := Vector3(INF, INF, INF)
			var closest_distance := INF
			for index in range(0, triangles.size(), 3):
				var hit: Variant = Geometry3D.segment_intersects_triangle(from, to, triangles[index], triangles[index+1], triangles[index+2])
				if hit != null and from.distance_to(hit as Vector3) < closest_distance:
					closest = hit as Vector3
					closest_distance = from.distance_to(closest)
			var wanted := _v(visual.weapon_sockets[witness.socket])
			var error := wanted.distance_to(closest)
			_expect(error < 0.00002, id + " actual surface " + String(witness.socket))
			results.append({"socket":witness.socket,"mesh":witness.mesh,"error_m":error,"hit":str(closest)})
		var muzzle := _v(visual.weapon_sockets.muzzle_socket)
		var base := _v(visual.weapon_sockets.barrel_base_socket)
		var bore := (muzzle-base).normalized()
		_expect(bore.dot(Vector3.RIGHT) > .99999, id + " +X bore direction")
		var up := _v(visual.weapon_sockets.optic_rail)-base
		up = (up-bore*up.dot(bore)).normalized()
		_expect(up.dot(Vector3.UP) > .99999, id + " projected sight-up is +Y")
		var landmarks: Dictionary = draft.calibration.bore_landmarks
		for end: String in ["root", "muzzle"]:
			var x := float(landmarks[end+"_ring_x"])
			var radius := float(landmarks[end+"_ring_radius"])
			var socket := base if end == "root" else muzzle
			var unique: Array[Vector3] = []
			for vertex: Vector3 in surfaces[landmarks.mesh]:
				if absf(vertex.x-x) > .000002 or absf(Vector2(vertex.y-socket.y,vertex.z-socket.z).length()-radius) > .000005:
					continue
				var duplicate := false
				for found: Vector3 in unique:
					if found.distance_to(vertex)<.000001:
						duplicate=true
				if not duplicate:
					unique.append(vertex)
			_expect(unique.size() >= 8, id + " modeled eight-sided " + end + " bore ring")
			var mean := Vector3.ZERO
			for vertex: Vector3 in unique:
				mean += vertex
			mean /= maxf(unique.size(),1)
			_expect(mean.distance_to(socket) < .000005, id + " center of " + end + " bore ring")
			results.append({"socket":end,"ring_vertices":unique.size(),"ring_center":str(mean),"error_m":mean.distance_to(socket)})
		print("RETRO1212_SOCKET_GEOMETRY ", id, " ", JSON.stringify(results))
		var file := FileAccess.open(output_directory + "/" + id + "-geometry-proof.json", FileAccess.WRITE)
		file.store_string(JSON.stringify({"draft":DIRECTORY+id+suffix,"on_disk_schema":schema,"materialized_scene_schema":materialized_schema,"surface_and_bore_results":results,"character_fit_verified":false},"  "))
		if "--capture" in OS.get_cmdline_user_args():
			await _capture(viewport,asset,bounds,id,visual.weapon_sockets)
		viewport.queue_free()
		await process_frame
	print("RETRO1212_SOCKET_GEOMETRY ", "PASS" if failures.is_empty() else "FAIL", " ", JSON.stringify(failures))
	print("RETRO1212_PUBLICATION NOT PERFORMED; schema blockers=", JSON.stringify(schema_blockers), "; character contact pending")
	quit(0 if failures.is_empty() else 1)

func _capture(viewport: SubViewport, asset: Node3D, bounds: AABB, id: String, sockets: Dictionary) -> void:
	_expect(DisplayServer.get_name() != "headless", "native display required for capture")
	if DisplayServer.get_name() == "headless":
		return
	var env := WorldEnvironment.new()
	env.environment = Environment.new()
	env.environment.background_mode = Environment.BG_COLOR
	env.environment.background_color = Color(.12,.14,.18)
	env.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.environment.ambient_light_color = Color.WHITE
	env.environment.ambient_light_energy = .85
	asset.add_child(env)
	var light := DirectionalLight3D.new()
	asset.add_child(light)
	light.rotation_degrees = Vector3(-40,-30,0)
	var cam := Camera3D.new()
	asset.add_child(cam)
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.current = true
	for index in KEYS.size():
		var point := _v(sockets[KEYS[index]])
		var marker := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = .0035
		sphere.height = .007
		marker.mesh = sphere
		marker.material_override = _material(COLORS[index])
		asset.add_child(marker)
		marker.position = point
	_line(asset,_v(sockets.barrel_base_socket),_v(sockets.muzzle_socket),Color(1,.9,.2))
	var sight := _v(sockets.optic_rail)
	_line(asset,sight,sight+Vector3.UP*.055,Color(.85,.65,1))
	var center := bounds.get_center()
	var length := bounds.size.x
	var shots := [
		{"name":"right","center":center,"offset":Vector3(0,0,2),"size":length*.8,"up":Vector3.UP},
		{"name":"left","center":center,"offset":Vector3(0,0,-2),"size":length*.8,"up":Vector3.UP},
		{"name":"top","center":center,"offset":Vector3(0,2,.001),"size":length*.8,"up":Vector3(0,0,-1)},
		{"name":"grip","center":(_v(sockets.right_hand_grip_target)+_v(sockets.left_hand_ik_target))*.5,"offset":Vector3(.03,.13,1),"size":.30,"up":Vector3.UP}
	]
	for shot: Dictionary in shots:
		cam.position = shot.center + shot.offset
		cam.look_at(shot.center,shot.up)
		cam.size = shot.size
		var annotations := Node3D.new()
		asset.add_child(annotations)
		# Camera-plane leaders stay readable in side and top views. These offsets
		# affect annotation placement only, never the saved contact coordinates.
		var offsets := [Vector2(-.035,-.055),Vector2(0,-.065),Vector2(0,.055),Vector2(.015,-.09),Vector2(0,-.06),Vector2(-.065,.075),Vector2(.01,.1)]
		for index in KEYS.size():
			var point := _v(sockets[KEYS[index]])
			var label := Label3D.new()
			label.text = "%d %s" % [index+1,LABELS[index]]
			label.font_size = 36
			label.pixel_size = .00033
			label.modulate = COLORS[index]
			label.outline_size = 10
			label.no_depth_test = true
			label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
			annotations.add_child(label)
			label.position = point+cam.basis.x*offsets[index].x+cam.basis.y*offsets[index].y
			_line(annotations,point,label.position,COLORS[index])
		for frame in 8:
			await process_frame
		RenderingServer.force_draw(false)
		var image := viewport.get_texture().get_image()
		_expect(image.save_png(output_directory+"/"+id+"-"+String(shot.name)+".png") == OK, id + " marker capture " + String(shot.name))
		annotations.queue_free()
		await process_frame

func _line(parent: Node3D, from: Vector3, to: Vector3, color: Color) -> void:
	var mesh := ImmediateMesh.new()
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	mesh.surface_add_vertex(from)
	mesh.surface_add_vertex(to)
	mesh.surface_end()
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = _material(color)
	parent.add_child(node)

func _material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.no_depth_test = true
	mat.albedo_color = color
	return mat

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

func _a(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _v(value: Dictionary) -> Vector3:
	return Vector3(float(value.x),float(value.y),float(value.z))

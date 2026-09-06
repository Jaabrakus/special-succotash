extends SceneTree

const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const Document := preload("res://scripts/maps/socom_map_document.gd")
const PROP := "res://assets/environment/tactical_courtyard_kit/wood_supply_crate_1m.glb"
var failures: Array[String] = []
var fingerprints: Array = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var runtime_source := FileAccess.get_file_as_string("res://scripts/maps/socom_map_runtime.gd")
	_expect(runtime_source.contains("return ImportedAssetBuilder.build(object, editor_preview)"), "canonical dispatch uses extracted component")
	_expect(not runtime_source.contains("static func _build_imported_asset"), "no duplicate imported builder in coordinator")
	var builder_source := FileAccess.get_file_as_string("res://scripts/maps/socom_imported_map_asset_builder.gd")
	_expect(builder_source.count("\n") <= 160, "imported component stays bounded")
	var world := Node3D.new()
	root.add_child(world)
	for preview in [false, true]:
		for mode in ["none", "box", "detailed_mesh"]:
			var object := _object(mode)
			var body := Runtime.build_object(object, preview)
			world.add_child(body)
			_expect(body is StaticBody3D, "static prop owner")
			_expect(body.position.is_equal_approx(Vector3(2, 0, -3)), "position preserved")
			_expect(body.rotation_degrees.is_equal_approx(Vector3(0, 35, 0)), "rotation preserved")
			_expect(body.get_meta("map_object_id") == "contributor_crate", "stable object identity")
			_expect(body.get_meta("map_object_type") == &"imported_asset", "stable type")
			var content := body.get_node_or_null("ImportedContent") as Node3D
			_expect(content != null, "GLB content is built by the shared runtime")
			if content != null:
				_expect(content.scale.is_equal_approx(Vector3(1.5, 2, 0.75)), "saved asset scale preserved")
			var shapes := body.find_children("*", "CollisionShape3D", true, false)
			_expect(shapes.size() > 0 if preview or mode != "none" else shapes.is_empty(), "collision mode " + mode)
			_expect(body.has_node("EditorSelectionCollision") == preview, "editor selection is separate from play collision")
			fingerprints.append({"mode": mode, "preview": preview, "tree": _fingerprint(body)})
			body.free()
		var missing := _object("none")
		missing.properties.asset_path = "res://assets/no_such_contributor_asset.glb"
		var placeholder := Runtime.build_object(missing, preview)
		_expect(placeholder.has_node("MissingAssetVisual") == preview, "missing content has editor-only placeholder")
		fingerprints.append({"missing": true, "preview": preview, "tree": _fingerprint(placeholder)})
		placeholder.free()
	var document := Document.new_document("Contributor boundary probe")
	document.objects = [_object("box")]
	var built := Runtime.build_into(world, document, false)
	_expect(built != null and built.find_child("ImportedContent", true, false) != null, "saved document reaches runtime consumer")
	var tag := "after"
	for arg: String in OS.get_cmdline_user_args():
		if arg.begins_with("--proof-tag="):
			tag = arg.trim_prefix("--proof-tag=").validate_filename()
	var proof_path := "/private/tmp/imported-map-boundary-%s.json" % tag
	var output := FileAccess.open(proof_path, FileAccess.WRITE)
	output.store_string(JSON.stringify(fingerprints, "  "))
	output.close()
	if "--render" in OS.get_cmdline_user_args():
		var camera := Camera3D.new()
		world.add_child(camera)
		camera.position = Vector3(6, 4, 4)
		camera.look_at(Vector3(2, 1, -3))
		camera.current = true
		var light := DirectionalLight3D.new()
		world.add_child(light)
		light.rotation_degrees = Vector3(-35, -30, 0)
		light.light_energy = 2.0
		for _frame in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("/private/tmp/imported-map-boundary-%s.png" % tag)
	world.free()
	print("IMPORTED_MAP_ASSET_BOUNDARY_REGRESSION ", "PASS" if failures.is_empty() else "FAIL", " cases=", fingerprints.size(), " proof=", proof_path)
	quit(0 if failures.is_empty() else 1)

func _object(mode: String) -> Dictionary:
	return {"id": "contributor_crate", "name": "Contributor Crate", "type": "imported_asset",
		"position": {"x": 2.0, "y": 0.0, "z": -3.0}, "rotation_degrees": {"x": 0.0, "y": 35.0, "z": 0.0},
		"size": {"x": 1.5, "y": 2.0, "z": 0.75}, "properties": {"asset_path": PROP, "collision_mode": mode}}

func _fingerprint(node: Node) -> Dictionary:
	var result := {"name": String(node.name), "type": node.get_class(), "children": []}
	if node is Node3D:
		result["transform"] = str(node.transform)
	if node is MeshInstance3D and node.mesh != null:
		result["aabb"] = str(node.get_aabb())
		result["faces"] = str(node.mesh.get_faces())
	if node is CollisionShape3D:
		result["shape"] = node.shape.get_class()
		if node.shape is BoxShape3D:
			result["size"] = str(node.shape.size)
		elif node.shape is ConcavePolygonShape3D:
			result["faces"] = str(node.shape.get_faces())
	for child in node.get_children():
		result.children.append(_fingerprint(child))
	return result

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error("IMPORTED_MAP_BOUNDARY: " + label)

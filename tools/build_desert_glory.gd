extends SceneTree
## Imports one local map into the existing map library, never changes active_map.
const Assets := preload("res://scripts/maps/socom_map_asset_library.gd")
const Maps := preload("res://scripts/maps/socom_map_document.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const SPEC := "res://config/maps/desert_glory_rebuild_spec.json"
var document: Dictionary
var replacements := 0
var source_prop_count := 0
var omitted_models: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var args := OS.get_cmdline_user_args()
	var source := ""
	var replace_hash := ""
	for arg in args:
		if arg.begins_with("--source="): source = arg.trim_prefix("--source=")
		if arg.begins_with("--replace-generated="): replace_hash = arg.trim_prefix("--replace-generated=")
	if source.is_empty():
		_fail("Pass --source=<fresh desert_glory.cjs output directory>")
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(source.path_join("desert_glory.json")))
	if not parsed is Dictionary:
		_fail("Missing conversion report")
		return
	var report: Dictionary = parsed
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(SPEC))
	var source_variant := String(report.get("texture_mode", "")) == "source_enhanced"
	if source_variant:
		spec.library_path = "user://maps/desert_glory_source_enhanced.json"
		spec.map_id = "desert_glory_source_enhanced"
		spec.name = "Desert Glory — source assets + enhanced wall"
	if report.get("source", {}).get("sha256", "") != spec.expected_source_archive_sha256 or int(report.get("validated_packets", 0)) != int(spec.expected_packets) or int(report.get("matched_draw_keys", 0)) != int(spec.expected_draw_keys) or int(report.get("triangles", 0)) != int(spec.expected_triangles):
		_fail("Source archive / full draw-key and bounds validation does not match this map")
		return
	var target := String(spec.library_path)
	if FileAccess.file_exists(target) and (replace_hash.is_empty() or FileAccess.get_sha256(target) != replace_hash):
		_fail("Existing map preserved: " + ProjectSettings.globalize_path(target))
		return
	document = Maps.new_document(spec.name)
	document.map_id = spec.map_id
	document.objects = []
	document.environment = Maps.normalize_environment(spec.environment)
	document.gameplay.primary_mode = "team_deathmatch"
	document.gameplay.supported_modes = ["team_deathmatch"]
	for chunk: Dictionary in report.chunks:
		var from := source.path_join(String(chunk.file))
		var existing := Assets.USER_ASSET_DIRECTORY.path_join(String(chunk.file))
		var asset_path := existing
		if not FileAccess.file_exists(existing) or FileAccess.get_sha256(existing) != FileAccess.get_sha256(from):
			var imported := Assets.import_glb(from)
			if not imported.get("ok", false):
				_fail(str(imported))
				return
			asset_path = imported.path
		var object := Maps.make_object(&"imported_asset", _v(chunk.origin), Vector3.ONE)
		object.id = "dg_sector_" + String(chunk.key)
		object.name = chunk.node
		object.properties = {"asset_path": asset_path, "collision_mode": "detailed_mesh", "collision_enabled": true, "local_research_only": true}
		document.objects.append(object)
	if source_variant:
		if not _add_source_props(report, source):
			return
	else:
		_add_replacement_props(report)
	var host := Node3D.new()
	root.add_child(host)
	Runtime.build_into(host, document, false)
	await physics_frame
	await physics_frame
	for column: Dictionary in spec.preview_spawn_columns_m:
		var start := Vector3(float(column.x), 30.0, float(column.z))
		var hit := _clear_spawn_near(host, start)
		if hit.is_empty():
			host.free()
			_fail("No walkable preview spawn at " + str(start))
			return
		var object := Maps.make_object(StringName(column.type), (hit.position as Vector3) + Vector3.UP * 0.12)
		object.id = "dg_" + String(column.type)
		object.rotation_degrees = Maps.vector_to_data(Vector3(0, float(column.yaw), 0))
		document.objects.append(object)
		print("DESERT_GLORY_SPAWN ", column.type, " ", object.position)
	host.free()
	if FileAccess.file_exists(target):
		# Explicit compare-and-replace only; retain the previous generated map.
		if FileAccess.get_sha256(target) != replace_hash:
			_fail("Map changed during rebuild; preserving it")
			return
		var backup := target + "." + replace_hash.left(12) + ".previous.txt"
		if not FileAccess.file_exists(backup):
			var backup_error := DirAccess.copy_absolute(ProjectSettings.globalize_path(target), ProjectSettings.globalize_path(backup))
			if backup_error != OK:
				_fail("Cannot preserve previous generated map")
				return
	if not Maps.save_path(document, target):
		_fail("Map save failed")
		return
	var provenance := target.get_basename() + ".provenance.txt"
	var file := FileAccess.open(provenance, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify({"source": report.source, "replacement_props": replacements, "source_props": source_prop_count, "omitted_models": omitted_models, "enhancements": report.get("enhancements", []), "scope": report.get("scope", ""), "deferred_props": report.get("deferred_props", []), "limitations": spec.asset_gaps if not source_variant else ["One AI-enhanced wall texture; other recovered textures remain original", "Unsupported source effects/dynamic assets remain omitted", "Original mission, lighting and camera parity not implemented"]}, "  "))
	print("DESERT_GLORY_BUILD PASS: %d architecture sectors, %d replacement props, %d source props; %s" % [report.chunks.size(), replacements, source_prop_count, ProjectSettings.globalize_path(target)])
	quit()

func _clear_spawn_near(host: Node3D, start: Vector3) -> Dictionary:
	# Scenic camera positions are references, not original gameplay spawn points.
	# Find a nearby walkable floor with full standing clearance; never save blindly.
	var offsets: Array[Vector3] = [Vector3.ZERO]
	for radius in range(1, 6):
		for direction in [Vector3.RIGHT, Vector3.LEFT, Vector3.FORWARD, Vector3.BACK]:
			offsets.append(direction * float(radius))
	var space := host.get_world_3d().direct_space_state
	for offset in offsets:
		var point := start + offset
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(point, point - Vector3.UP * 50.0, 1))
		if hit.is_empty() or (hit.normal as Vector3).y < 0.85:
			continue
		var shape := CapsuleShape3D.new()
		shape.radius = 0.4
		shape.height = 1.85
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = shape
		query.collision_mask = 1
		query.transform = Transform3D(Basis.IDENTITY, (hit.position as Vector3) + Vector3.UP * 1.07)
		if space.intersect_shape(query, 1).is_empty():
			return hit
	return {}

func _add_source_props(report: Dictionary, source: String) -> bool:
	var paths := {}
	for model: Dictionary in report.get("source_props", []):
		var imported := Assets.import_glb(source.path_join("props").path_join(String(model.file)))
		if not imported.get("ok", false):
			_fail("Source prop import failed: " + str(imported))
			return false
		paths[String(model.name)] = imported.path
	for instance: Dictionary in report.instances:
		var model := String(instance.model)
		if not paths.has(model):
			omitted_models[model] = int(omitted_models.get(model, 0)) + 1
			continue
		var matrix: Array = instance.matrix
		var basis := Basis(_v(matrix.slice(0,3)), _v(matrix.slice(4,7)), _v(matrix.slice(8,11)))
		var scale := basis.get_scale()
		var rotation := basis.orthonormalized().get_euler()
		# Saved map TRS cannot represent shear. Never silently distort a source instance.
		var rebuilt := Basis.from_euler(rotation).scaled_local(scale)
		if not rebuilt.is_equal_approx(basis):
			omitted_models[model + " (non-TRS)"] = int(omitted_models.get(model + " (non-TRS)", 0)) + 1
			continue
		var object := Maps.make_object(&"imported_asset", _v(matrix.slice(12,15)) * float(report.meters_per_unit), scale)
		object.id = "dg_source_prop_%03d" % source_prop_count
		object.name = "Source " + String(instance.name)
		object.rotation_degrees = Maps.vector_to_data(rotation * (180.0 / PI))
		object.properties = {"asset_path": paths[model], "collision_mode": "detailed_mesh", "collision_enabled": not (model.contains("grass") or model.contains("fly") or model.contains("rubble_burning")), "local_research_only": true}
		document.objects.append(object)
		source_prop_count += 1
	return true

func _add_replacement_props(report: Dictionary) -> void:
	var assets: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://assets/environment/relic_depot/asset_manifest.json"))
	for instance: Dictionary in report.instances:
		var model := String(instance.model)
		var asset := ""
		var stack := 1
		if model.contains("crate") or model.contains("box"):
			asset = "crate_wood"
		elif model in ["barrel", "mp6_barrel_fuel"]:
			asset = "barrel_oil"
		elif model.contains("tire_pile"):
			asset = "tires"
		elif model.contains("palette"):
			asset = "pallet"
			stack = 10 if model.contains("10high") else (5 if model.contains("5high") else 3)
		elif model.contains("rubble_burning"):
			asset = "mediun_rock_2"
		elif model.contains("dry_grass"):
			asset = "grass"
		if asset.is_empty() or not assets.has(asset) or not instance.source_bounds is Dictionary:
			omitted_models[model] = int(omitted_models.get(model, 0)) + 1
			continue
		var matrix: Array = instance.matrix
		var basis := Basis(_v(matrix.slice(0,3)), _v(matrix.slice(4,7)), _v(matrix.slice(8,11)))
		var scale := float(report.meters_per_unit)
		var lo := _v(instance.source_bounds.min) * scale
		var hi := _v(instance.source_bounds.max) * scale
		var size := (hi - lo) * basis.get_scale().abs()
		if size.x < 0.05 or size.y < 0.05 or size.z < 0.05:
			continue
		var bottom := Vector3((lo.x+hi.x)*0.5, lo.y, (lo.z+hi.z)*0.5)
		var position := _v(matrix.slice(12,15)) * scale + basis * bottom
		var native_size := _v(assets[asset].size_m)
		var object_scale := size / native_size
		object_scale.y /= float(stack)
		for level in stack:
			var object := Maps.make_object(&"imported_asset", position + basis.orthonormalized().y * (size.y * float(level) / float(stack)), object_scale)
			object.id = "dg_prop_%03d" % replacements
			object.name = "Replacement " + asset + " / " + String(instance.name)
			object.rotation_degrees = Maps.vector_to_data(basis.orthonormalized().get_euler() * (180.0 / PI))
			object.properties = {"asset_path": assets[asset].path, "collision_mode": "detailed_mesh", "collision_enabled": asset != "grass", "yard_finish": true}
			document.objects.append(object)
			replacements += 1

func _v(value: Array) -> Vector3:
	return Vector3(float(value[0]),float(value[1]),float(value[2]))

func _fail(message: String) -> void:
	push_error("DESERT_GLORY_BUILD FAIL: " + message)
	quit(1)

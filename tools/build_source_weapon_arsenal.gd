extends SceneTree
## Offline import/calibration only. Runtime consumes saved native scenes/profiles.
const RECIPE := "res://config/source_weapon_arsenal.json"
const OUTPUT := "res://assets/weapons/socom2_arsenal/"
const Resolver := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_resolver.gd")
const VisualContract := preload("res://scripts/labs/gunsmith2/weapon_visual_rig_contract.gd")
const Contract := preload("res://scripts/weapons/weapon_rig_contract.gd")
var failures: Array[String] = []
var models: Dictionary = {}
var settings: Dictionary = {}
var manifest: Dictionary
var alignment_defaults: Dictionary = {}

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var recipe := _json(RECIPE)
	alignment_defaults = recipe.get("alignment_defaults", {})
	manifest = _json(recipe.manifest)
	for model: Dictionary in manifest.models: models[model.name] = model
	for item: Dictionary in _json("res://config/reference/socom2_weapon_settings.json").weapons:
		settings[item.name] = item
	DirAccess.make_dir_recursive_absolute(OUTPUT)
	var built := 0
	for entry: Dictionary in recipe.entries:
		if not _build(entry): break
		built += 1
	if built != recipe.entries.size(): _fail("Incomplete build: " + str(built))
	print("SOURCE_WEAPON_ARSENAL_BUILD ", "PASS" if failures.is_empty() else "FAIL", " entries=", recipe.entries.size(), " ", failures)
	quit(0 if failures.is_empty() else 1)

func _build(entry: Dictionary) -> bool:
	var id := String(entry.id)
	if not id.begins_with("s2_") or id.get_file() != id or not models.has(entry.model) or not settings.has(entry.source):
		return _fail("Invalid explicit source recipe " + id)
	var profile_path := "res://config/weapons/" + id + ".json"
	var model_path := OUTPUT + id + ".scn"
	if FileAccess.file_exists(profile_path) and not "--replace-generated" in OS.get_cmdline_user_args():
		return _fail("Existing generated profile; review diff and use --replace-generated: " + profile_path)
	var model: Dictionary = models[entry.model]
	var body_part: Dictionary = model.parts[0]
	var stage := Node3D.new()
	stage.name = id
	var source := Node3D.new()
	source.name = "SourceGeometry"
	stage.add_child(source)
	var selected: Array[String] = []
	for part: Dictionary in model.parts:
		var is_body := part == body_part
		var is_scope: bool = bool(entry.get("scope", false)) and part.source_node == "scope" and int(part.visual_word) == 256
		var is_silencer: bool = bool(entry.get("silencer", false)) and part.source_node == "silencer"
		if not (is_body or is_scope or is_silencer): continue
		var file := "res://assets/weapons/socom2_source/v2/models/" + String(part.file)
		if FileAccess.get_sha256(file) != String(part.sha256):
			stage.free()
			return _fail("Extracted source checksum changed: " + file)
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		state.create_animations = false
		state.handle_binary_image_mode = GLTFState.HANDLE_BINARY_IMAGE_MODE_EMBED_AS_UNCOMPRESSED
		if document.append_from_file(file, state, GLTFDocument.IMPORT_FLAG_FORCE_DISABLE_MESH_COMPRESSION) != OK:
			stage.free()
			return _fail("Cannot decode " + file)
		var instance := document.generate_scene(state)
		instance.name = "Body" if is_body else String(part.source_node)
		source.add_child(instance)
		selected.append(part.file)
	var base := Contract.load_config("res://config/weapons/" + String(entry.base) + ".json")
	var category := String(entry.get("category", base.get("category", "")))
	var pistol := category == "Pistols"
	var faces := _faces(source.get_child(0))
	var bounds := _bounds(faces)
	var right_seed := Vector3(float(entry.get("right_x", -0.07 if pistol else -0.04)), float(entry.get("right_y", -0.035)), 0.0)
	var right := _contact(faces, right_seed, 1.0)
	var support_seed := right_seed + Vector3(0.025, -0.005, 0.0) if pistol else Vector3(float(entry.get("support_x", 0.20)), 0.035, 0.0)
	var left := _contact(faces, support_seed, -1.0)
	# Two-handed pistols cup the trigger hand, not the same occupied grip
	# volume. Allow 1 cm for that hand's skin on the opposing grip surface.
	if pistol: left.z -= 0.01
	if not right.is_finite() or not left.is_finite():
		stage.free()
		return _fail(id + " has no surface contact near authored seeds")
	# Source vertices already use metres. Only rigid axes/origin conversion.
	var axis := Basis(Vector3.UP, -PI * 0.5)
	source.transform = Transform3D(axis, -(axis * right))
	var source_markers := Node3D.new()
	source_markers.name = "SourceMarkers"
	source.add_child(source_markers)
	var marker_points := {}
	for marker: Dictionary in model.markers:
		var point := _v(marker.position_model_meters)
		marker_points[marker.name] = point
		var node := Marker3D.new()
		node.name = marker.name
		node.position = point
		source_markers.add_child(node)
	var fire: Vector3 = marker_points.get("firepoint", Vector3(bounds.end.x, bounds.end.y * 0.65, 0))
	# A few source firepoints are inside suppressors. Use the actual mesh end;
	# keep original marker untouched for inspection. Never aim using aimpoint.
	var muzzle := Vector3(bounds.end.x, fire.y, fire.z)
	if bool(entry.get("silencer", false)):
		var all_faces := _faces(source)
		muzzle.x = _bounds(all_faces).end.x
	var sockets := {
		"right_hand_grip_target": Vector3.ZERO,
		"left_hand_ik_target": axis * (left - right),
		"muzzle_socket": axis * (muzzle - right),
		"barrel_base_socket": axis * (muzzle - Vector3(0.1, 0, 0) - right),
		"buttstock_socket": axis * (Vector3(bounds.position.x, fire.y - 0.045, 0) - right),
		"ejection_port": axis * ((marker_points.get("firepoint_shell", fire) as Vector3) - right),
		"optic_rail": axis * (Vector3(0, bounds.end.y, 0) - right)
	}
	stage.set_meta("source_model", entry.model)
	stage.set_meta("source_parts", selected)
	stage.set_meta("meters_per_unit", 1.0)
	_own(stage, stage)
	var packed := PackedScene.new()
	if packed.pack(stage) != OK or ResourceSaver.save(packed, model_path) != OK:
		stage.free()
		return _fail("Cannot save native source weapon " + id)
	stage.free()
	# Use established +Z family frames, not AGLS's model-specific coordinates.
	var template_id := "family_pistol_4_v3" if pistol else "m16a2_directional_v1"
	if category == "Shotguns": template_id = "family_shotgun_1_directional_v1"
	if category == "Sniper Rifles": template_id = "family_sniper_1_directional_v1"
	var template := Resolver.load_published(template_id)
	if not template.has("visual"): return _fail("Missing presentation template " + template_id)
	var visual: Dictionary = template.visual.duplicate(true)
	visual.model_fbx = model_path
	visual.normalized_scale = 1.0
	visual.user_scale_multiplier = 1.0
	visual.model_rotation_degrees = _map(Vector3.ZERO)
	visual.weapon_sockets = {}
	for name: String in sockets: visual.weapon_sockets[name] = _map(sockets[name])
	# Old clip-specific contacts are for other meshes. Do not transplant them.
	visual.stances = {}
	visual.animation_hand_maps = {}
	visual.animation_frame_pose_keys = {}
	for key: String in alignment_defaults:
		visual.support_hand_pose[key] = alignment_defaults[key]
	if pistol:
		visual.support_hand_pose.finger_curl = 1.0
		# Native left palm +Z faces the grip from its left surface; fingers +Y
		# extend toward the front, then the existing finger stage curls them.
		var wrist_angles := Basis(Vector3.DOWN, Vector3.BACK, Vector3.LEFT).get_euler(EULER_ORDER_YXZ) * (180.0 / PI)
		visual.support_hand_pose.palm_pitch_deg = wrist_angles.x
		visual.support_hand_pose.palm_yaw_deg = wrist_angles.y
		visual.support_hand_pose.palm_roll_deg = wrist_angles.z
	visual.gun_placement_line = {"runtime_enabled": false}
	var output := _json("res://config/weapons/" + String(entry.base) + ".json")
	output.erase("visual_rig_id")
	output.erase("weapon_contact_graph")
	output.erase("provenance")
	output.erase("recom_assets")
	for field: String in VisualContract.VISUAL_FIELDS:
		output.erase(field)
	for key: String in visual: output[key] = visual[key]
	output.schema_version = 3
	output.weapon_id = id
	output.catalog_weapon_id = id
	output.display_name = "SOCOM II · " + String(entry.get("label", entry.source))
	output.category = category
	output.catalog_source = "SOCOM II MP1 WEAP extraction / SOCOM-141 family gameplay adaptation"
	output.socket_contract_authored = true
	output.coordinate_space = {"grip_offset":"weapon_root_local_meters", "weapon_sockets":"weapon_pivot_local_meters"}
	output.armory_eligible = true
	output.competitive_eligible = false
	output.training_only = false
	output.presentation_status = "Extracted mesh and textures; source markers retained; adapted surface contacts and family animation."
	var ref: Dictionary = settings[entry.source]
	var numeric: Dictionary = ref.numeric
	output.ballistics.fire_rate_rpm = 60.0 / float(numeric.FireWait)
	output.ballistics.magazine_capacity = int(numeric.Ammo_Capacity)
	output.ballistics.reserve_ammo = int(numeric.Ammo_Capacity) * int(numeric.get("NumMags", 3))
	output.ballistics.muzzle_velocity_mps = float(numeric.Muzzle_Velocity)
	output.ballistics.effective_range_m = float(numeric.Effective_Range)
	output.ballistics.max_range_m = float(numeric.Maximum_Range)
	output.ballistics.is_silenced = "SD" in String(entry.source) or id == "s2_9mm_pistol"
	output.fire_modes = []
	for mode: String in ref.mode_flags:
		output.fire_modes.append({"SingleMode":"semi", "BurstMode":"burst", "AutoMode":"auto"}[mode])
	if output.fire_modes.is_empty(): output.fire_modes = base.fire_modes.duplicate()
	if not output.default_fire_mode in output.fire_modes: output.default_fire_mode = output.fire_modes[0]
	# Do not silently opt new equipment into the concurrently developed damage
	# policy. Original settings stay provenance, distinct from verified runtime IDs.
	output.reticle.erase("socom2_source_name")
	output.reticle.erase("socom2_stances")
	output.source_asset = {"manifest": RECIPE, "source_manifest_sha256": FileAccess.get_sha256("res://assets/weapons/socom2_source/v2/manifest.json"),
		"source_name":entry.source, "model":entry.model, "parts":selected, "base_profile":entry.base,
		"notes":entry.get("note", ""), "right_contact_source_m":_map(right), "left_contact_source_m":_map(left),
		"gameplay_status":"project family tuning with source cadence/ammo/range; not original damage parity", "source_settings":ref}
	var file := FileAccess.open(profile_path, FileAccess.WRITE)
	if file == null: return _fail("Cannot save " + profile_path)
	file.store_string(JSON.stringify(output, "\t") + "\n")
	print("SOURCE_WEAPON_BUILT ", id, " parts=", selected.size(), " length_m=", bounds.size.x)
	return true

func _faces(node: Node, parent: Transform3D = Transform3D.IDENTITY) -> PackedVector3Array:
	# Root transform intentionally excluded: inputs are source model-space metres.
	var result := PackedVector3Array()
	if node is MeshInstance3D and node.mesh != null:
		for vertex: Vector3 in node.mesh.get_faces(): result.append(parent * vertex)
	for child: Node in node.get_children():
		var frame := parent * ((child as Node3D).transform if child is Node3D else Transform3D.IDENTITY)
		result.append_array(_faces(child, frame))
	return result

func _contact(faces: PackedVector3Array, seed: Vector3, side: float) -> Vector3:
	for radius in [0.0, 0.015, 0.03, 0.045, 0.06]:
		for offset: Vector2 in [Vector2.ZERO, Vector2(0, radius), Vector2(radius, 0), Vector2(-radius, 0), Vector2(0, -radius)]:
			var start := seed + Vector3(offset.x, offset.y, side * 0.3)
			var end := start - Vector3(0, 0, side * 0.6)
			var hit := Vector3(INF, INF, INF)
			var nearest := INF
			for index in range(0, faces.size(), 3):
				var point: Variant = Geometry3D.segment_intersects_triangle(start, end, faces[index], faces[index+1], faces[index+2])
				if point is Vector3 and start.distance_squared_to(point) < nearest:
					hit = point
					nearest = start.distance_squared_to(point)
			if hit.is_finite(): return hit
	return Vector3(INF, INF, INF)

func _bounds(faces: PackedVector3Array) -> AABB:
	var result := AABB(faces[0], Vector3.ZERO)
	for point: Vector3 in faces: result = result.expand(point)
	return result

func _own(node: Node, owner_node: Node) -> void:
	for child: Node in node.get_children():
		child.owner = owner_node
		_own(child, owner_node)

func _json(path: String) -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(path))

func _v(values: Array) -> Vector3:
	return Vector3(values[0], values[1], values[2])

func _map(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}

func _fail(message: String) -> bool:
	failures.append(message)
	push_error(message)
	return false

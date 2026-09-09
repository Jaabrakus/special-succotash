extends SceneTree
const Maps := preload("res://scripts/maps/socom_map_document.gd")
const Runtime := preload("res://scripts/maps/socom_map_runtime.gd")
const Commands := preload("res://scripts/maps/socom_map_command_service.gd")
const Assets := preload("res://scripts/maps/socom_map_asset_library.gd")
var failures := 0
func _initialize() -> void: _run.call_deferred()
func _run() -> void:
	var spec: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/maps/mp51_geometry_kit_spec.json"))
	var document := Maps.load_path(spec["library_path"])
	_expect(not document.is_empty(), "installed study loads")
	_expect(Commands.validate_document(document).get("ok", false), "editor validation")
	var roundtrip := Maps.normalize(JSON.parse_string(JSON.stringify(document)))
	_expect(roundtrip == document, "saved contract roundtrip")
	var count := 0
	for object: Dictionary in document.get("objects", []):
		if object["type"] != "imported_asset": continue
		count += 1
		_expect(object["properties"]["collision_mode"] == "detailed_mesh", "geometry collision")
		_expect(Assets.asset_exists(object["properties"]["asset_path"]), "installed GLB")
	_expect(count == int(spec["expected_world_chunks"]), "82 source world chunks")
	var host := Node3D.new()
	root.add_child(host)
	var built := Runtime.build_into(host, document, false)
	_expect(built != null, "canonical runtime constructs map")
	await physics_frame
	await physics_frame
	for object: Dictionary in document.get("objects", []):
		if object["type"] not in ["player_spawn", "team_alpha_spawn", "team_bravo_spawn"]: continue
		var p := Maps.data_to_vector(object["position"])
		var hit := host.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(p+Vector3.UP*.1,p-Vector3.UP*.4,1))
		_expect(not hit.is_empty(), "preview spawn has actual mesh support")
	host.free()
	if failures == 0: print("SOCOM_GEOMETRY_REGRESSION PASS: 82 chunks, save parity, canonical collision and preview spawns")
	quit(0 if failures == 0 else 1)
func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("SOCOM_GEOMETRY_REGRESSION FAIL: " + message)

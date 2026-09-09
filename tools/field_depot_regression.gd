extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")
const DOCUMENT := "res://config/maps/field_depot_research.json"
var failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var document := MapDocument.load_path(DOCUMENT)
	_expect(not document.is_empty(), "saved map loads")
	var health := MapCommands.validate_document(document)
	_expect(bool(health.get("ok", false)), "editor accepts save: " + str(health))
	var textures: Dictionary = {}
	var ids: Dictionary = {}
	var alpha := 0
	var bravo := 0
	for object: Dictionary in document.get("objects", []):
		_expect(not ids.has(object["id"]), "stable unique object id")
		ids[object["id"]] = true
		alpha += int(object["type"] == "team_alpha_spawn")
		bravo += int(object["type"] == "team_bravo_spawn")
		var path := String(object.get("properties", {}).get("texture_path", ""))
		if not path.is_empty() and not textures.has(path):
			textures[path] = true
			_expect(path.begins_with("user://map_assets/field_depot/"), "textures stay local")
			_expect(FileAccess.file_exists(path), "installed texture exists: " + path)
			var material := MapRuntime._material_for_object(object)
			_expect(material.albedo_texture != null, "canonical material loads " + path)
	_expect(textures.size() == 6, "six source textures are used")
	_expect(alpha == 16 and bravo == 16, "both teams have 16 authored spawn markers")
	var validation := MapRuntime.validate_build(document)
	_expect(bool(validation.get("ok", false)), "all map objects build with collision: " + str(validation))
	var edited := MapCommands.apply(document, {"command": "transform_object", "id": "fd_000", "size": {"x": 62, "y": 0.4, "z": 48}})
	_expect(bool(edited.get("ok", false)), "existing editor commands edit imported map")
	var roundtrip := MapDocument.normalize(JSON.parse_string(JSON.stringify(document)))
	_expect(roundtrip == document, "save/reload preserves geometry and textures")
	var world := Node3D.new()
	root.add_child(world)
	var runtime := MapRuntime.build_into(world, document, false)
	_expect(runtime != null and runtime.has_node("SafetyPerimeter"), "canonical play builds safety perimeter")
	await physics_frame
	await physics_frame
	for object: Dictionary in document["objects"]:
		if object["type"] not in ["player_spawn", "team_alpha_spawn", "team_bravo_spawn"]:
			continue
		var p := MapDocument.data_to_vector(object["position"])
		var query := PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.0, p - Vector3.UP, 1)
		var hit := world.get_world_3d().direct_space_state.intersect_ray(query)
		_expect(not hit.is_empty() and absf(hit.get("position", Vector3.INF).y) < 0.06, "spawn rests on courtyard: " + object["id"])
	world.queue_free()
	await process_frame
	if failures == 0:
		print("FIELD_DEPOT_REGRESSION PASS: editable map, 6 textures, 32 team spawns, runtime collision")
	quit(0 if failures == 0 else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error("FIELD_DEPOT_REGRESSION FAIL: " + message)

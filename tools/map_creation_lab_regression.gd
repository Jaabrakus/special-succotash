extends SceneTree

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const MapCommands := preload("res://scripts/maps/socom_map_command_service.gd")
const MapRuntime := preload("res://scripts/maps/socom_map_runtime.gd")
const MapAmbience := preload("res://scripts/maps/socom_map_ambience_engine.gd")
const MapGameplay := preload("res://scripts/maps/socom_map_gameplay_contract.gd")
const MovingTrainingDummy := preload("res://scripts/combat/socom_moving_training_dummy.gd")
const ControlsGuide := preload("res://scripts/ui/socom_controls_guide.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var document := MapDocument.new_document("Regression Map")
	_expect(document.has("environment"), "new maps contain authored atmosphere")
	_expect(document.get("objects", []).size() >= 7, "new maps start with a SOCOM demolition/TDM layout")
	var demolition := MapGameplay.demolition_layout(document)
	_expect(not (demolition.get("alpha_spawns", []) as Array).is_empty(), "new maps include Alpha team spawns")
	_expect(not (demolition.get("bravo_spawns", []) as Array).is_empty(), "new maps include Bravo team spawns")
	_expect(not (demolition.get("bomb_pickups", []) as Array).is_empty(), "new maps include a neutral bomb pickup")
	var capabilities := MapCommands.describe_capabilities()
	_expect((capabilities.get("commands", {}) as Dictionary).has("place_object"), "human and LLM editors share place_object")
	_expect((capabilities.get("commands", {}) as Dictionary).has("set_environment"), "atmosphere has a safe command interface")

	var placed := MapCommands.apply(document, {
		"command": "place_object",
		"type": "wall",
		"id": "regression_wall",
		"position": {"x": 1.0, "y": 1.5, "z": -3.0},
	})
	_expect(bool(placed.get("ok", false)), "place command succeeds with a stable object id")
	document = placed.get("document", {})
	var moved := MapCommands.apply(document, {
		"command": "transform_object",
		"id": "regression_wall",
		"size": {"x": 6.0, "y": 3.0, "z": 0.4},
	})
	_expect(bool(moved.get("ok", false)), "transform command resizes an existing object by id")
	document = moved.get("document", {})
	for shape_type in ["curved_wall", "jagged_wall", "ramp"]:
		var shaped := MapCommands.apply(document, {
			"command": "place_object", "type": shape_type,
			"position": {"x": 0.0, "y": 1.5, "z": -5.0},
		})
		_expect(bool(shaped.get("ok", false)), "%s is available as authored tactical geometry" % shape_type)
		document = shaped.get("document", {})
	for dummy_type in ["training_dummy", "moving_training_dummy"]:
		var target := MapCommands.apply(document, {
			"command": "place_object", "type": dummy_type,
			"position": {"x": 2.0, "y": 0.05, "z": -2.0},
		})
		_expect(bool(target.get("ok", false)), "%s is available in the map document" % dummy_type)
		document = target.get("document", {})
	var atmosphere := MapCommands.apply(document, {"command": "apply_environment_preset", "preset": "moonlit_night"})
	_expect(bool(atmosphere.get("ok", false)), "atmosphere preset command succeeds")
	document = atmosphere.get("document", {})
	_expect(String((document.get("environment", {}) as Dictionary).get("preset", "")) == "moonlit_night", "atmosphere preset remains in the document")
	var validation := MapCommands.validate_document(document)
	_expect(bool(validation.get("ok", false)), "authored map validates for play")
	var save_path := "/private/tmp/socom_map_creation_regression.json"
	_expect(MapDocument.save_path(document, save_path), "map document saves to JSON")
	var reloaded := MapDocument.load_path(save_path)
	_expect(String(reloaded.get("name", "")) == "Regression Map", "saved map document loads without losing identity")
	DirAccess.remove_absolute(save_path)

	var test_world := Node3D.new()
	root.add_child(test_world)
	var atmosphere_root := MapAmbience.build_into(test_world, document)
	var runtime_root := MapRuntime.build_into(test_world, document, true)
	_expect(atmosphere_root != null and atmosphere_root.get_node_or_null("MapWorldEnvironment") != null, "runtime builds the saved sky and lighting")
	_expect(runtime_root != null and runtime_root.get_child_count() == document.get("objects", []).size(), "runtime builds every authored object")
	var moving_dummy := MovingTrainingDummy.new()
	moving_dummy.position = Vector3.ZERO
	test_world.add_child(moving_dummy)
	moving_dummy.configure_patrol({"patrol_distance": 6.0, "patrol_speed": 2.0, "turn_pause": 0.0})
	var dummy_start := moving_dummy.global_position
	moving_dummy._physics_process(0.5)
	_expect(not moving_dummy.global_position.is_equal_approx(dummy_start), "moving training dummy follows its authored patrol")
	test_world.free()

	var controls := ControlsGuide.new()
	root.add_child(controls)
	await process_frame
	_expect(controls.find_child("ControlsGuideButton", true, false) != null, "gameplay exposes the F3 Controls Guide button")
	controls.toggle()
	var controls_text := controls.find_child("CompleteControlsText", true, false) as RichTextLabel
	_expect(controls_text != null and "F10" in controls_text.text and "MAP LAB" in controls_text.text, "Controls Guide lists function keys and Map Lab controls")
	controls.free()

	var packed := load("res://map_creation_lab.tscn") as PackedScene
	_expect(packed != null, "Map Lab scene loads")
	if packed != null:
		var lab := packed.instantiate()
		root.add_child(lab)
		await process_frame
		await process_frame
		_expect(lab.find_child("MapEditorViewport", true, false) != null, "Map Lab exposes the visual editor viewport")
		_expect(lab.find_child("Palette_wall", true, false) != null, "Map Lab exposes a wall placement tool")
		_expect(lab.find_child("Palette_point_light", true, false) != null, "Map Lab exposes practical lighting")
		_expect(lab.find_child("Palette_ambience_zone", true, false) != null, "Map Lab exposes ambience zones")
		_expect(lab.find_child("Palette_curved_wall", true, false) != null, "Map Lab exposes curved wall shaping")
		_expect(lab.find_child("Palette_jagged_wall", true, false) != null, "Map Lab exposes broken tactical walls")
		_expect(lab.find_child("Palette_bomb_pickup", true, false) != null, "Map Lab exposes the neutral demolition bomb")
		_expect(lab.find_child("Palette_training_dummy", true, false) != null, "Map Lab exposes stationary training dummies")
		_expect(lab.find_child("Palette_moving_training_dummy", true, false) != null, "Map Lab exposes moving training dummies")
		_expect(lab.find_child("MapTransformMode", true, false) != null, "Map Lab exposes mouse transform-mode cycling")
		_expect(lab.find_child("BrowseMapTextureButton", true, false) != null, "Map Lab exposes texture selection")
		_expect(lab.find_child("RepairSocomMissionButton", true, false) != null, "older maps can add missing SOCOM mission markers in one click")
		_expect(lab.find_child("MapCommandJSON", true, false) != null, "Map Lab exposes the optional safe command surface")
		_expect(lab.find_child("SaveMapButton", true, false) != null, "Map Lab exposes save")
		_expect(lab.find_child("PlayAuthoredMapButton", true, false) != null, "Map Lab exposes save-and-play")
		lab.free()

	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("MAP_CREATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("MAP_CREATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("MAP_CREATION_LAB_REGRESSION PASS")
		quit(0)
	else:
		print("MAP_CREATION_LAB_REGRESSION FAIL ", failures)
		quit(1)

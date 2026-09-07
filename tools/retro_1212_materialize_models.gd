extends SceneTree
## Build only the selected meter-scale models as bundled runtime PackedScenes.
## Source GLBs and raw 1212 source assets remain unchanged.
const DIRECTORY := "res://assets/weapons/retro_1212/"
var failures: Array[String] = []

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	for id: String in ["uzi_candidate", "pump_candidate"]:
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		_expect(document.append_from_file(DIRECTORY + id + ".glb", state) == OK, id + " source load")
		var model := document.generate_scene(state) as Node3D
		if model == null:
			_expect(false, id + " generated scene")
			continue
		_expect(model.find_children("*", "Camera3D", true, false).is_empty(), id + " no camera")
		_expect(model.find_children("*", "AnimationPlayer", true, false).is_empty(), id + " no source action ownership")
		_expect(model.find_child("FPS_Arms_Mesh", true, false) == null, id + " no first-person arms")
		for node: Node in model.find_children("*", "", true, false):
			_expect(node.get_script() == null, id + " no imported script")
		var packed := PackedScene.new()
		_expect(packed.pack(model) == OK, id + " packed scene")
		var path := DIRECTORY + id + ".scn"
		_expect(ResourceSaver.save(packed, path, ResourceSaver.FLAG_BUNDLE_RESOURCES) == OK, id + " bundled scene saved")
		var loaded := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
		_expect(loaded != null, id + " canonical ResourceLoader ready")
		var dependencies := ResourceLoader.get_dependencies(path)
		_expect(dependencies.is_empty(), id + " self-contained, no raw pack/export dependency")
		print("RETRO1212_RUNTIME_MODEL ", path, " dependencies=", dependencies)
		model.free()
	print("RETRO1212_MATERIALIZE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)

func _expect(ok: bool, label: String) -> void:
	if not ok:
		failures.append(label)
		push_error(label)

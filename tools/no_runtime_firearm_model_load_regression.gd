extends SceneTree

## Firearm source assets remain catalog metadata, but no playable or Gunsmith
## presentation path may instantiate an FBX/GLB firearm model while the
## universal-stick policy is active.

const STICK_SCENE := "res://assets/weapons/placeholders/universal_weapon_stick.tscn"
const SOURCE_ROOTS: Array[String] = [
	"res://scripts/player",
	"res://scripts/runtime",
	"res://scripts/labs",
]
const DIRECT_SCENE_ROOT := "res://scenes/weapons"

var failures: Array[String] = []


func _initialize() -> void:
	var direct_load := RegEx.new()
	direct_load.compile(
		"(?:preload|load)\\s*\\(\\s*[\\\"']res://assets/weapons/[^\\\"']+\\.(?:fbx|glb)"
	)
	for root_path in SOURCE_ROOTS:
		for path in _files_recursive(root_path, "gd"):
			var source := _read(path)
			_expect(
				direct_load.search(source) == null,
				"%s has no direct firearm FBX/GLB render load" % path
			)
	for path in _files_recursive(DIRECT_SCENE_ROOT, "tscn"):
		var source := _read(path)
		_expect(
			"assets/weapons/" not in source or (
				".fbx\"" not in source.to_lower()
				and ".glb\"" not in source.to_lower()
			),
			"%s has no firearm FBX/GLB visual resource" % path
		)

	var operator_source := _read("res://scripts/player/operator_asset_runtime.gd")
	_expect("AK47_SCENE" not in operator_source, "operator has no AK FBX fallback")
	_expect(
		"resolve_for_presentation" in operator_source,
		"operator visual passes through universal resolver"
	)
	_expect(
		"var presentation_config := VISUAL_RIG_RESOLVER.resolve_for_presentation(config)"
		in operator_source,
		"weapon switching cannot bypass the stick resolver"
	)
	var warmup_source := _read("res://scripts/runtime/playable_resource_warmup.gd")
	_expect(
		"VisualRigResolver.resolve_for_presentation" in warmup_source,
		"startup warms the resolved stick instead of source FBX"
	)
	var preview_source := _read(
		"res://scripts/labs/gunsmith/gunsmith_weapon_preview_loader.gd"
	)
	_expect(
		"VisualRigResolver.resolve_for_presentation" in preview_source,
		"Gunsmith preview resolves the universal stick"
	)
	_expect(
		"source_model_fbx" in preview_source,
		"Gunsmith preview retains source-model metadata"
	)
	var loader_source := _read("res://scripts/labs/gunsmith/gunsmith_weapon_loader.gd")
	_expect(
		"get_source_weapon_file_path" in loader_source,
		"Gunsmith loader retains recoverable source-model metadata"
	)
	_expect(
		"var path := UNIVERSAL_WEAPON_STICK_PATH" in loader_source,
		"Gunsmith loader instantiates only the stick"
	)
	var studio_loader_source := _read("res://scripts/labs/weapon_rig_preview_loader.gd")
	_expect(
		"GunsLab2VisualRigResolver.resolve_for_presentation(config)" in studio_loader_source,
		"Animation Studio saved-profile preview resolves the universal stick"
	)
	_expect(
		"var sockets: Dictionary = config.get(\"weapon_sockets\", {})" in studio_loader_source
		and "\"config\": config" in studio_loader_source,
		"Animation Studio preserves authored sockets and canonical config"
	)

	var stick_profile := _read_json(
		"res://config/weapon_visual_rigs/universal_starter_stick_v1.json"
	)
	var visual: Dictionary = stick_profile.get("visual", {})
	_expect(String(visual.get("model_fbx", "")) == STICK_SCENE, "stick scene is canonical")
	_expect(is_equal_approx(float(visual.get("normalized_scale", 0.0)), 1.0), "stick uses meter scale")
	var rotation: Dictionary = visual.get("model_rotation_degrees", {})
	_expect(
		is_zero_approx(float(rotation.get("x", 999.0)))
		and is_zero_approx(float(rotation.get("y", 999.0)))
		and is_zero_approx(float(rotation.get("z", 999.0))),
		"stick mesh and sockets share one axis frame"
	)
	_finish()


func _files_recursive(root_path: String, extension: String) -> Array[String]:
	var result: Array[String] = []
	var directory := DirAccess.open(root_path)
	if directory == null:
		failures.append("directory opens: %s" % root_path)
		return result
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		if entry not in [".", ".."]:
			var path := root_path.path_join(entry)
			if directory.current_is_dir():
				result.append_array(_files_recursive(path, extension))
			elif entry.get_extension().to_lower() == extension:
				result.append(path)
		entry = directory.get_next()
	directory.list_dir_end()
	return result


func _read(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	return file.get_as_text() if file != null else ""


func _read_json(path: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(_read(path))
	return parsed as Dictionary if parsed is Dictionary else {}


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("NO_RUNTIME_FIREARM_MODEL_LOAD PASS ", label)
	else:
		failures.append(label)
		push_error("NO_RUNTIME_FIREARM_MODEL_LOAD FAIL " + label)


func _finish() -> void:
	if failures.is_empty():
		print("NO_RUNTIME_FIREARM_MODEL_LOAD_REGRESSION PASS")
		quit(0)
	else:
		print("NO_RUNTIME_FIREARM_MODEL_LOAD_REGRESSION FAIL ", failures)
		quit(1)

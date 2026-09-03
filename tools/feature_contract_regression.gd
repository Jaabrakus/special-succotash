extends SceneTree

const FeatureContract := preload("res://scripts/core/socom_feature_contract.gd")
const CONTRACT_DIRECTORY := "res://config/feature_contracts"

var failures := 0


func _init() -> void:
	var directory := DirAccess.open(CONTRACT_DIRECTORY)
	if directory == null:
		_fail("missing contract directory: %s" % CONTRACT_DIRECTORY)
		quit(1)
		return
	var files := PackedStringArray()
	for file_name in directory.get_files():
		if file_name.ends_with(".json"):
			files.append(file_name)
	files.sort()
	if files.is_empty():
		_fail("no feature contracts found")
	for file_name in files:
		_validate_file("%s/%s" % [CONTRACT_DIRECTORY, file_name])
	if failures == 0:
		print("[FEATURE CONTRACT] PASS: %d contract(s) form complete Godot integration graphs" % files.size())
	quit(1 if failures > 0 else 0)


func _validate_file(path: String) -> void:
	var contract := FeatureContract.load_json(path)
	if contract.is_empty():
		_fail("%s could not be loaded as a JSON dictionary" % path)
		return
	var errors := FeatureContract.validate(contract)
	if errors.is_empty():
		print("[FEATURE CONTRACT] PASS %s (%s)" % [String(contract.get("feature_id", "")), path])
		return
	for error in errors:
		_fail("%s: %s" % [path, error])


func _fail(message: String) -> void:
	failures += 1
	push_error("[FEATURE CONTRACT] FAIL: %s" % message)

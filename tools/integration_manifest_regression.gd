extends SceneTree

const MANIFEST_PATH := "res://config/integration_manifest.json"

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var manifest := _load_manifest()
	if manifest.is_empty():
		_finish()
		return

	_expect(int(manifest.get("schema_version", 0)) == 1, "manifest schema is supported")
	_expect(String(manifest.get("project_id", "")) == "socom-141", "project identity is canonical")
	_expect(String(manifest.get("authoritative_branch", "")) == "main", "main is the authoritative branch")
	_expect(String(manifest.get("canonical_path_alias", "")) == "/Users/kiwimango/Documents/SOCOM-141", "canonical path alias is stable and outside dated worktrees")
	_expect(_path_exists(String(manifest.get("studio_entry_scene", ""))), "Studio entry scene exists")
	var runtime_entry := String(manifest.get("runtime_entry_scene", ""))
	_expect(runtime_entry == String(ProjectSettings.get_setting("application/run/main_scene", "")), "manifest and project share one runtime entry")

	var lab_ids: Dictionary = {}
	for raw_lab in manifest.get("labs", []):
		if not (raw_lab is Dictionary):
			_expect(false, "lab entries are dictionaries")
			continue
		var lab := raw_lab as Dictionary
		var lab_id := String(lab.get("id", ""))
		_expect(not lab_id.is_empty() and not lab_ids.has(lab_id), "lab id is unique: %s" % lab_id)
		lab_ids[lab_id] = true
		_validate_lab(lab)

	var authority_names: Dictionary = {}
	for raw_contract in manifest.get("authority_contracts", []):
		if not (raw_contract is Dictionary):
			_expect(false, "authority entries are dictionaries")
			continue
		var contract := raw_contract as Dictionary
		var contract_name := String(contract.get("name", ""))
		var owner := String(contract.get("owner", ""))
		_expect(not contract_name.is_empty() and not authority_names.has(contract_name), "authority has one owner: %s" % contract_name)
		authority_names[contract_name] = owner
		_expect(_path_exists(owner), "authority owner exists: %s" % owner)

	var gates: Dictionary = manifest.get("gates", {})
	for gate_name in ["quick", "full"]:
		var tests: Array = gates.get(gate_name, [])
		_expect(not tests.is_empty(), "%s integration gate is registered" % gate_name)
		for raw_test in tests:
			var test_path := String(raw_test)
			_expect(_path_exists(test_path), "%s gate test exists: %s" % [gate_name, test_path])

	_finish()


func _load_manifest() -> Dictionary:
	_expect(FileAccess.file_exists(MANIFEST_PATH), "integration manifest exists")
	if not FileAccess.file_exists(MANIFEST_PATH):
		return {}
	var file := FileAccess.open(MANIFEST_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
	_expect(parsed is Dictionary, "integration manifest is valid JSON")
	return parsed as Dictionary if parsed is Dictionary else {}


func _validate_lab(lab: Dictionary) -> void:
	var lab_id := String(lab.get("id", "unnamed"))
	var scene_path := String(lab.get("scene", ""))
	var controller_path := String(lab.get("controller", ""))
	_expect(_path_exists(scene_path), "%s scene exists" % lab_id)
	_expect(_path_exists(controller_path), "%s controller exists" % lab_id)
	if not _path_exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	_expect(packed != null, "%s scene loads" % lab_id)
	if packed == null:
		return
	var instance := packed.instantiate()
	var root_script := instance.get_script() as Script
	_expect(root_script != null, "%s root has a controller" % lab_id)
	if root_script != null:
		_expect(root_script.resource_path == controller_path, "%s uses the registered controller" % lab_id)
	instance.free()

	var contracts: Array = lab.get("shared_contracts", [])
	_expect(not contracts.is_empty(), "%s declares shared runtime contracts" % lab_id)
	for raw_path in contracts:
		var contract_path := String(raw_path)
		_expect(not contract_path.begins_with("res://scripts/labs/"), "%s contract is shared runtime code: %s" % [lab_id, contract_path])
		_expect(_path_exists(contract_path), "%s contract exists: %s" % [lab_id, contract_path])
		if contract_path.ends_with(".gd") and _path_exists(contract_path):
			_expect(load(contract_path) != null, "%s contract parses: %s" % [lab_id, contract_path])


func _path_exists(resource_path: String) -> bool:
	if resource_path.is_empty():
		return false
	return FileAccess.file_exists(resource_path) or DirAccess.dir_exists_absolute(
		ProjectSettings.globalize_path(resource_path)
	)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("INTEGRATION_MANIFEST_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("INTEGRATION_MANIFEST_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("INTEGRATION_MANIFEST_REGRESSION PASS")
		quit(0)
	else:
		print("INTEGRATION_MANIFEST_REGRESSION FAIL ", failures)
		quit(1)

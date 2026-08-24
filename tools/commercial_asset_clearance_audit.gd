extends SceneTree

const REGISTER_PATH := "res://config/commercial_asset_register.json"


func _initialize() -> void:
	var failures: Array[String] = []
	var blockers: Array[String] = []
	var file := FileAccess.open(REGISTER_PATH, FileAccess.READ)
	if file == null:
		failures.append("asset register is missing")
		_finish(failures, blockers)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		failures.append("asset register is not valid JSON")
		_finish(failures, blockers)
		return
	var document := parsed as Dictionary
	if int(document.get("schema_version", 0)) != 1:
		failures.append("asset register schema is unsupported")
	var policy: Dictionary = document.get("release_policy", {})
	var approved := PackedStringArray(policy.get("approved_statuses", []))
	var packages: Array = document.get("packages", [])
	if packages.is_empty():
		failures.append("asset register has no packages")
	var ids: Dictionary = {}
	for raw_package: Variant in packages:
		if not raw_package is Dictionary:
			failures.append("asset package entry is not an object")
			continue
		var package := raw_package as Dictionary
		var package_id := String(package.get("id", ""))
		var path := String(package.get("path", ""))
		var status := String(package.get("status", ""))
		if package_id.is_empty() or ids.has(package_id):
			failures.append("asset package id is missing or duplicated: %s" % package_id)
		ids[package_id] = true
		if not path.begins_with("res://"):
			failures.append("asset package path is invalid: %s" % path)
		if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(path)):
			failures.append("asset package path does not exist: %s" % path)
		if String(package.get("required_action", "")).is_empty():
			failures.append("asset package lacks a required action: %s" % package_id)
		if bool(package.get("included_in_customer_build", false)) and not approved.has(status):
			blockers.append("%s [%s] — %s" % [package_id, status, package.get("required_action", "")])

	print("COMMERCIAL_ASSET_AUDIT packages=%d blockers=%d" % [packages.size(), blockers.size()])
	for blocker in blockers:
		print("COMMERCIAL_ASSET_BLOCKER ", blocker)
	_finish(failures, blockers)


func _finish(failures: Array[String], blockers: Array[String]) -> void:
	for failure in failures:
		push_error("COMMERCIAL_ASSET_AUDIT ERROR: %s" % failure)
	if not failures.is_empty():
		quit(1)
		return
	if OS.get_cmdline_user_args().has("--enforce-clearance") and not blockers.is_empty():
		push_error("COMMERCIAL_ASSET_AUDIT BLOCKED: customer build contains uncleared packages")
		quit(2)
		return
	print("COMMERCIAL_ASSET_AUDIT PASS (register valid; blockers reported above)")
	quit(0)

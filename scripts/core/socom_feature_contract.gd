class_name SocomFeatureContract
extends RefCounted

## Executable schema for a SOCOM feature's Godot node/data/ownership graph.
## Documentation alone cannot pass this contract: referenced files, scene
## nodes, code-created node symbols, profile writers/readers, and proof scripts
## must all exist.

const SCHEMA_VERSION := 1
const REQUIRED_TEXT_FIELDS := [
	"feature_id",
	"player_intent",
	"acceptance_rule",
	"canonical_scene",
	"visual_check",
]


static func load_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


static func validate(contract: Dictionary) -> PackedStringArray:
	var errors := PackedStringArray()
	if int(contract.get("schema_version", -1)) != SCHEMA_VERSION:
		errors.append("schema_version must be %d" % SCHEMA_VERSION)
	for field in REQUIRED_TEXT_FIELDS:
		if String(contract.get(field, "")).strip_edges().is_empty():
			errors.append("%s must be non-empty" % field)

	_validate_res_file(String(contract.get("canonical_scene", "")), "canonical_scene", errors)
	var editor_scene := String(contract.get("editor_scene", ""))
	if not editor_scene.is_empty():
		_validate_res_file(editor_scene, "editor_scene", errors)

	var ownership_value: Variant = contract.get("ownership", {})
	if not ownership_value is Dictionary or (ownership_value as Dictionary).is_empty():
		errors.append("ownership must name at least one domain and sole owner")
	else:
		for domain_value in (ownership_value as Dictionary).keys():
			var domain := String(domain_value).strip_edges()
			var owner := String((ownership_value as Dictionary).get(domain_value, "")).strip_edges()
			if domain.is_empty() or owner.is_empty():
				errors.append("ownership entries require non-empty domain and owner")

	_validate_nodes(contract.get("nodes", []), errors)
	_validate_data_contracts(contract.get("data_contracts", []), errors)
	_validate_system_delta(contract.get("system_delta", {}), errors)
	_validate_res_file_list(contract.get("proof_scripts", []), "proof_scripts", errors)

	var unchanged_value: Variant = contract.get("must_not_change", [])
	if not unchanged_value is Array or (unchanged_value as Array).is_empty():
		errors.append("must_not_change must declare at least one protected system")
	return errors


static func _validate_system_delta(value: Variant, errors: PackedStringArray) -> void:
	if not value is Dictionary:
		errors.append("system_delta must compare current and candidate systems")
		return
	var delta := value as Dictionary
	var decision := String(delta.get("decision", ""))
	if decision not in ["KEEP", "MERGE", "REPLACE", "REJECT"]:
		errors.append("system_delta.decision must be KEEP, MERGE, REPLACE, or REJECT")
	if String(delta.get("reason", "")).strip_edges().is_empty():
		errors.append("system_delta.reason must explain the evidence-based decision")
	for side in ["current", "candidate"]:
		var side_value: Variant = delta.get(side, {})
		if not side_value is Dictionary:
			errors.append("system_delta.%s must be a dictionary" % side)
			continue
		var assessment := side_value as Dictionary
		if String(assessment.get("system", "")).strip_edges().is_empty():
			errors.append("system_delta.%s.system must be named" % side)
		for criterion in [
			"correctness",
			"ownership_clarity",
			"runtime_parity",
			"editor_usability",
			"performance",
			"regression_coverage",
		]:
			if not assessment.has(criterion):
				errors.append("system_delta.%s.%s score is required" % [side, criterion])
				continue
			var score := int(assessment.get(criterion, -1))
			if score < 0 or score > 5:
				errors.append("system_delta.%s.%s must be 0..5" % [side, criterion])
		_validate_res_file_list(
			assessment.get("evidence_paths", []),
			"system_delta.%s.evidence_paths" % side,
			errors
		)


static func _validate_nodes(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array or (value as Array).is_empty():
		errors.append("nodes must declare at least one Godot node")
		return
	var ids := {}
	for index in (value as Array).size():
		var entry_value: Variant = (value as Array)[index]
		if not entry_value is Dictionary:
			errors.append("nodes[%d] must be a dictionary" % index)
			continue
		var entry := entry_value as Dictionary
		var prefix := "nodes[%d]" % index
		for field in ["id", "type", "role", "owner"]:
			if String(entry.get(field, "")).strip_edges().is_empty():
				errors.append("%s.%s must be non-empty" % [prefix, field])
		var node_id := String(entry.get("id", ""))
		if ids.has(node_id):
			errors.append("duplicate node id: %s" % node_id)
		ids[node_id] = true

		var scene_path := String(entry.get("scene_path", ""))
		var node_path := String(entry.get("node_path", ""))
		var source_script := String(entry.get("source_script", ""))
		if not scene_path.is_empty() or not node_path.is_empty():
			_validate_scene_node(scene_path, node_path, String(entry.get("type", "")), prefix, errors)
		elif not source_script.is_empty():
			_validate_code_created_node(source_script, entry.get("code_symbols", []), prefix, errors)
		else:
			errors.append("%s needs scene_path/node_path or source_script/code_symbols" % prefix)


static func _validate_scene_node(
	scene_path: String,
	node_path: String,
	expected_type: String,
	prefix: String,
	errors: PackedStringArray
) -> void:
	_validate_res_file(scene_path, "%s.scene_path" % prefix, errors)
	if node_path.is_empty():
		errors.append("%s.node_path must be non-empty" % prefix)
		return
	if not ResourceLoader.exists(scene_path):
		return
	var packed := load(scene_path) as PackedScene
	if packed == null:
		errors.append("%s could not load PackedScene %s" % [prefix, scene_path])
		return
	var root := packed.instantiate()
	var node: Node = root if node_path == "." else root.get_node_or_null(NodePath(node_path))
	if node == null:
		errors.append("%s missing node %s in %s" % [prefix, node_path, scene_path])
	elif not expected_type.is_empty() and not node.is_class(expected_type):
		errors.append("%s node %s is %s, expected %s" % [prefix, node_path, node.get_class(), expected_type])
	root.free()


static func _validate_code_created_node(
	source_script: String,
	symbols_value: Variant,
	prefix: String,
	errors: PackedStringArray
) -> void:
	_validate_res_file(source_script, "%s.source_script" % prefix, errors)
	if not FileAccess.file_exists(source_script):
		return
	if not symbols_value is Array or (symbols_value as Array).is_empty():
		errors.append("%s.code_symbols must prove the node construction" % prefix)
		return
	var source := FileAccess.get_file_as_string(source_script)
	for symbol_value in symbols_value as Array:
		var symbol := String(symbol_value)
		if symbol.is_empty() or source.find(symbol) < 0:
			errors.append("%s source is missing code symbol: %s" % [prefix, symbol])


static func _validate_data_contracts(value: Variant, errors: PackedStringArray) -> void:
	if not value is Array or (value as Array).is_empty():
		errors.append("data_contracts must connect authored data to runtime")
		return
	for index in (value as Array).size():
		var entry_value: Variant = (value as Array)[index]
		if not entry_value is Dictionary:
			errors.append("data_contracts[%d] must be a dictionary" % index)
			continue
		var entry := entry_value as Dictionary
		var prefix := "data_contracts[%d]" % index
		_validate_res_file(String(entry.get("path", "")), "%s.path" % prefix, errors)
		_validate_res_file(String(entry.get("writer", "")), "%s.writer" % prefix, errors)
		_validate_res_file_list(entry.get("readers", []), "%s.readers" % prefix, errors)


static func _validate_res_file_list(value: Variant, label: String, errors: PackedStringArray) -> void:
	if not value is Array or (value as Array).is_empty():
		errors.append("%s must contain at least one res:// file" % label)
		return
	for path_value in value as Array:
		_validate_res_file(String(path_value), label, errors)


static func _validate_res_file(path: String, label: String, errors: PackedStringArray) -> void:
	if not path.begins_with("res://"):
		errors.append("%s must be a res:// path: %s" % [label, path])
	elif not FileAccess.file_exists(path) and not ResourceLoader.exists(path):
		errors.append("%s does not exist: %s" % [label, path])

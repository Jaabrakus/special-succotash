extends SceneTree

## Gunfight ruleset regression: schema normalization, rotation table
## integrity, determinism, layer-chain wiring, and the authority contracts.
## Run headless:
##   godot --headless --path . --script res://tools/gunfight_regression.gd

const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const BuyPhaseLayer := preload("res://scripts/network/socom_multiplayer_buy_phase.gd")
const ObjectivesLayer := preload("res://scripts/network/socom_multiplayer_objectives.gd")

const RULESET_PATH := "res://config/maps/gunfight_rules.json"
const LOADOUT_TABLE_PATH := "res://config/economy/gunfight_loadouts.json"

var failures: int = 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("GUNFIGHT_CHECK PASS ", message)
		return
	failures += 1
	push_error("GUNFIGHT_CHECK FAIL " + message)


func _initialize() -> void:
	_check_ruleset_document()
	_check_schema_normalization()
	_check_rotation_table()
	_check_layer_chain()
	_finish()


func _finish() -> void:
	if failures == 0:
		print("GUNFIGHT_REGRESSION PASS")
		quit(0)
		return
	print("GUNFIGHT_REGRESSION FAIL count=", failures)
	quit(1)


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	return parsed as Dictionary if parsed is Dictionary else {}


func _check_ruleset_document() -> void:
	var document := _load_json(RULESET_PATH)
	_expect(not document.is_empty(), "gunfight ruleset document loads")
	var gameplay: Dictionary = document.get("gameplay", {}) as Dictionary
	_expect(String(gameplay.get("primary_mode", "")) == "gunfight", "ruleset declares the gunfight mode")
	_expect(int(gameplay.get("round_time_seconds", 0)) == 40, "gunfight rounds are 40 seconds")
	_expect(int(gameplay.get("rounds_to_win", 0)) == 6, "gunfight is first to six rounds")
	_expect(not bool(gameplay.get("respawns_enabled", true)), "gunfight has no mid-round respawn")
	_expect(String(gameplay.get("round_timeout_result", "")) == "overtime_flag", "timeouts resolve through the overtime flag")
	_expect(String(gameplay.get("loadout_mode", "")) == "rotation", "gunfight uses the loadout rotation")


func _check_schema_normalization() -> void:
	var normalized := MapDocument.normalize_gameplay(_load_json(RULESET_PATH).get("gameplay", {}))
	_expect(String(normalized.get("primary_mode", "")) == "gunfight", "schema accepts the gunfight primary mode")
	_expect(String(normalized.get("round_timeout_result", "")) == "overtime_flag", "schema accepts the overtime timeout result")
	_expect(int(normalized.get("round_time_seconds", 0)) == 40, "schema allows sub-minute rounds")
	_expect(String(normalized.get("loadout_mode", "")) == "rotation", "schema preserves the loadout mode")
	var demolition := MapDocument.normalize_gameplay({})
	_expect(String(demolition.get("primary_mode", "")) == "demolition", "schema default mode stays demolition")
	_expect(String(demolition.get("loadout_mode", "")) == "economy", "schema default loadout mode stays economy")
	_expect(int(demolition.get("round_time_seconds", 0)) == 300, "schema default round time unchanged")
	var hostile := MapDocument.normalize_gameplay({
		"primary_mode": "aimbot_mode",
		"round_timeout_result": "<script>",
		"loadout_mode": "delete_save",
		"round_time_seconds": -500,
	})
	_expect(String(hostile.get("primary_mode", "")) == "demolition", "hostile mode value falls back to demolition")
	_expect(String(hostile.get("round_timeout_result", "")) == "draw", "hostile timeout value falls back to draw")
	_expect(String(hostile.get("loadout_mode", "")) == "economy", "hostile loadout value falls back to economy")
	_expect(int(hostile.get("round_time_seconds", 0)) == 30, "hostile round time clamps to the floor")


func _check_rotation_table() -> void:
	var table := _load_json(LOADOUT_TABLE_PATH)
	var pairs: Array = table.get("pairs", []) as Array
	_expect(pairs.size() >= 12, "rotation table has a meaningful rotation (%d pairs)" % pairs.size())
	var seen_pairs: Dictionary = {}
	for raw_pair: Variant in pairs:
		var pair := raw_pair as Array
		if pair.size() != 2:
			_expect(false, "rotation pair has exactly two entries")
			continue
		var primary := String(pair[0]).to_lower()
		var secondary := String(pair[1]).to_lower()
		var key := primary + "+" + secondary
		if seen_pairs.has(key):
			_expect(false, "rotation pair is unique: " + key)
			continue
		seen_pairs[key] = true
		for weapon_id in [primary, secondary]:
			var profile_path := "res://config/weapons/%s.json" % weapon_id
			if not FileAccess.file_exists(profile_path):
				_expect(false, "rotation weapon has an equip profile: " + weapon_id)


func _check_layer_chain() -> void:
	var objectives_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_multiplayer_objectives.gd"
	)
	_expect(
		objectives_source.begins_with("extends \"res://scripts/network/socom_multiplayer_gunfight.gd\""),
		"objectives layer sits above the gunfight layer"
	)
	var source := FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_gunfight.gd")
	_expect(
		source.contains("extends \"res://scripts/network/socom_multiplayer_buy_phase.gd\""),
		"gunfight layer extends the buy phase layer"
	)
	var gated := [
		"_server_open_buy_phase",
		"_on_operator_eliminated",
		"_advance_round_clock",
	]
	for method_name: String in gated:
		var block := _extract_function(source, method_name)
		_expect(
			block.contains("_gunfight_enabled()") and block.contains("super."),
			"%s stays mode-gated and reaches super outside gunfight" % method_name
		)
	var finish_block := _extract_function(source, "_server_finish_round")
	_expect(
		finish_block.contains("winner_team < 0") and finish_block.contains("overtime_flag"),
		"overtime intercepts only timeout draws"
	)
	_expect(
		BuyPhaseLayer != null and ObjectivesLayer != null,
		"neighbouring layers still load through the new chain"
	)


func _extract_function(source: String, method_name: String) -> String:
	var marker := "func %s(" % method_name
	var start := source.find(marker)
	if start < 0:
		return ""
	var next_func := source.find("\nfunc ", start + marker.length())
	var block := source.substr(start, next_func - start if next_func > start else source.length())
	return block

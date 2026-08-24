extends SceneTree

const WRAPPER_PATH := "res://scripts/network/socom_multiplayer_slice.gd"
const LAYER_PATHS := [
	"res://scripts/network/socom_multiplayer_state.gd",
	"res://scripts/network/socom_multiplayer_session.gd",
	"res://scripts/network/socom_multiplayer_replication.gd",
	"res://scripts/network/socom_multiplayer_combat.gd",
	"res://scripts/network/socom_multiplayer_rounds.gd",
	"res://scripts/network/socom_multiplayer_objectives.gd",
	"res://scripts/network/socom_multiplayer_world_ui.gd",
]
const EXPECTED_RPC_METHODS := [
	"spawn_operator",
	"despawn_operator",
	"receive_server_map",
	"receive_lobby_state",
	"request_lobby_team",
	"request_lobby_ready",
	"receive_match_started",
	"receive_round_state",
	"receive_return_to_lobby",
	"submit_movement",
	"receive_time_sync_probe",
	"submit_time_sync_echo",
	"receive_time_sync_result",
	"submit_shot",
	"submit_reload",
	"submit_objective_interaction",
	"receive_world_state",
	"receive_shot_effect",
	"receive_damage_feedback",
	"receive_match_event",
	"receive_ammo_state",
	"receive_objective_state",
]

var failures := 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("MULTIPLAYER_ARCHITECTURE_CHECK PASS ", message)
		return
	failures += 1
	push_error("MULTIPLAYER_ARCHITECTURE_CHECK FAIL " + message)


func _line_count(path: String) -> int:
	return FileAccess.get_file_as_string(path).split("\n").size() - 1


func _init() -> void:
	var wrapper_source := FileAccess.get_file_as_string(WRAPPER_PATH)
	_expect(wrapper_source.contains("class_name SocomMultiplayerSlice"), "public multiplayer type remains stable")
	_expect(_line_count(WRAPPER_PATH) <= 300, "RPC compatibility boundary stays below 300 lines")

	var function_count := 0
	var rpc_annotation_count := 0
	for path in LAYER_PATHS:
		_expect(FileAccess.file_exists(path), "authority layer exists: " + path.get_file())
		var layer_script := load(path) as Script
		_expect(
			layer_script != null and layer_script.can_instantiate(),
			"authority layer parses and can instantiate: " + path.get_file()
		)
		var source := FileAccess.get_file_as_string(path)
		_expect(_line_count(path) <= 500, "authority layer stays below 500 lines: " + path.get_file())
		if path.ends_with("socom_multiplayer_state.gd"):
			source = source.split("# BEGIN GENERATED MULTIPLAYER CROSS-LAYER CONTRACT")[0]
		function_count += source.count("\nfunc ")
		rpc_annotation_count += source.count("\n@rpc(")

	_expect(function_count == 118, "all 118 authority functions remain in one layer")
	_expect(rpc_annotation_count == 22, "all 22 RPC annotations remain present")

	var scene := load("res://multiplayer_slice.tscn") as PackedScene
	var slice := scene.instantiate() if scene != null else null
	_expect(slice != null, "multiplayer scene instantiates through the compatibility type")
	if slice != null:
		var concrete_script := slice.get_script() as Script
		_expect(
			concrete_script != null and concrete_script.has_method("get_rpc_config"),
			"concrete multiplayer script exposes RPC metadata"
		)
		var rpc_config_value: Variant = (
			concrete_script.call("get_rpc_config")
			if concrete_script != null and concrete_script.has_method("get_rpc_config")
			else null
		)
		_expect(rpc_config_value is Dictionary, "runtime exposes a live RPC configuration")
		if rpc_config_value is Dictionary:
			var rpc_config := rpc_config_value as Dictionary
			_expect(rpc_config.size() == EXPECTED_RPC_METHODS.size(), "runtime exposes exactly 22 RPC methods")
			for method_name in EXPECTED_RPC_METHODS:
				_expect(rpc_config.has(method_name), "runtime RPC remains registered: " + method_name)
		slice.free()

	if failures == 0:
		print("MULTIPLAYER_SLICE_ARCHITECTURE_REGRESSION PASS")
		quit(0)
		return
	print("MULTIPLAYER_SLICE_ARCHITECTURE_REGRESSION FAIL count=", failures)
	quit(1)

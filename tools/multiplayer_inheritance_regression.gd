extends SceneTree

const LAYERS := [
	"res://scripts/network/socom_multiplayer_state.gd",
	"res://scripts/network/socom_multiplayer_admission.gd",
	"res://scripts/network/socom_multiplayer_directory_presence.gd",
	"res://scripts/network/socom_multiplayer_webrtc.gd",
	"res://scripts/network/socom_multiplayer_session.gd",
	"res://scripts/network/socom_multiplayer_lobby_pairing.gd",
	"res://scripts/network/socom_multiplayer_replication.gd",
	"res://scripts/network/socom_multiplayer_combat.gd",
	"res://scripts/network/socom_multiplayer_rounds.gd",
	"res://scripts/network/socom_multiplayer_round_loadout.gd",
	"res://scripts/network/socom_multiplayer_objectives.gd",
	"res://scripts/network/socom_multiplayer_world_ui.gd",
	"res://scripts/network/socom_multiplayer_tournament_runtime.gd",
	"res://scripts/network/socom_multiplayer_warmup.gd",
	"res://scripts/network/socom_multiplayer_slice.gd",
]


func _initialize() -> void:
	print("--- Running Multiplayer Inheritance Regression ---")
	for path in LAYERS:
		var script: Script = load(path)
		assert(script != null and script.can_instantiate(), "Failed to compile multiplayer layer: %s" % path)
		print("✓ %s" % path)
	print("MULTIPLAYER_INHERITANCE_REGRESSION PASS")
	quit(0)

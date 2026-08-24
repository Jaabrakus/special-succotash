extends Node

## Routes a dedicated-server export (or an explicit --dedicated-server run)
## directly into the authoritative multiplayer scene. Client exports keep the
## normal launcher and never receive a server credential from this script.

const MULTIPLAYER_SCENE := "res://multiplayer_slice.tscn"


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if not OS.has_feature("dedicated_server") and not args.has("--dedicated-server"):
		return
	ProjectSettings.set_setting("socom/session/launch_mode", "dedicated")
	call_deferred("_open_authoritative_server")


func _open_authoritative_server() -> void:
	if get_tree().current_scene != null and get_tree().current_scene.scene_file_path == MULTIPLAYER_SCENE:
		return
	var error := get_tree().change_scene_to_file(MULTIPLAYER_SCENE)
	if error != OK:
		push_error("DEDICATED_SERVER_BOOT_FAILED %s" % error_string(error))

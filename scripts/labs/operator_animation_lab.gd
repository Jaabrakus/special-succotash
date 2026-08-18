extends "res://scripts/labs/animation_studio/animation_studio_routes.gd"

# Stable scene entry point. Feature behavior lives in focused Studio modules;
# this coordinator owns only lifecycle order and deferred startup intent.

func _ready() -> void:
    _prepare_workshop_window()
    _scan_all_mixamo_fbx()
    _load_state_slots()
    _load_layer_recipe()
    _build_stage()
    _build_ui()
    _load_skin(current_skin)
    if OS.get_cmdline_user_args().has("--pose-editor"):
        call_deferred("_show_editor_page", "Pose")

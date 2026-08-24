extends "res://scripts/labs/animation_studio/animation_studio_routes.gd"

# Stable scene entry point. Feature behavior lives in focused Studio modules;
# this coordinator owns only lifecycle order and deferred startup intent.

func _ready() -> void:
    # Match the playable operator's presentation order. Imported animation is
    # sampled first; Studio corrections, weapon placement, and hand IK run as
    # the final visual pass so the skinned mesh receives the same bone pose as
    # the colored rig overlay. Without this priority the AnimationPlayer can
    # overwrite the solved arms later in the same frame.
    process_priority = 100
    _prepare_workshop_window()
    _scan_all_mixamo_fbx()
    _load_state_slots()
    _load_animation_casting_board()
    _load_layer_recipe()
    _build_stage()
    _build_ui()
    if (
        OS.get_cmdline_user_args().has("--urban-skin")
        or OS.get_cmdline_user_args().has("--capture-urban-skin")
    ):
        current_skin = SkinType.COUNTER_STRIKE_URBAN
    _load_skin(current_skin)
    if OS.get_cmdline_user_args().has("--capture-urban-skin"):
        call_deferred(
            "_capture_skin_preview",
            "/private/tmp/socom-urban-animation-studio.png"
        )
    elif OS.get_cmdline_user_args().has("--capture-ps1-skin"):
        call_deferred(
            "_capture_skin_preview",
            "/private/tmp/socom-ps1-animation-studio.png"
        )
    elif OS.get_cmdline_user_args().has("--animation-states-demo"):
        call_deferred("_run_animation_state_demo")
    elif OS.get_cmdline_user_args().has("--animation-states"):
        call_deferred("_show_editor_page", "States")
    elif OS.get_cmdline_user_args().has("--pose-editor"):
        call_deferred("_show_editor_page", "Pose")
    elif OS.get_cmdline_user_args().has("--animation-casting"):
        call_deferred("_show_editor_page", "Casting")

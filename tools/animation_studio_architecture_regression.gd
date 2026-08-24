extends SceneTree

const COORDINATOR_PATH := "res://scripts/labs/operator_animation_lab.gd"
const PHASE_MODULES := [
    "res://scripts/labs/animation_studio/animation_studio_state.gd",
    "res://scripts/labs/animation_studio/animation_studio_workspace.gd",
    "res://scripts/labs/animation_studio/animation_studio_model.gd",
    "res://scripts/labs/animation_studio/animation_studio_stage.gd",
    "res://scripts/labs/animation_studio/animation_studio_playback.gd",
    "res://scripts/labs/animation_studio/animation_studio_pose_runtime.gd",
    "res://scripts/labs/animation_studio/animation_studio_pose_input.gd",
    "res://scripts/labs/animation_studio/animation_studio_pose_strip.gd",
    "res://scripts/labs/animation_studio/animation_studio_pose_corrections.gd",
    "res://scripts/labs/animation_studio/animation_studio_pose_authoring.gd",
    "res://scripts/labs/animation_studio/animation_studio_rig_authoring.gd",
    "res://scripts/labs/animation_studio/animation_studio_sequence.gd",
    "res://scripts/labs/animation_studio/animation_studio_weapon.gd",
    "res://scripts/labs/animation_studio/animation_studio_view_workspace.gd",
    "res://scripts/labs/animation_studio/animation_studio_view_timeline.gd",
    "res://scripts/labs/animation_studio/animation_studio_view.gd",
    "res://scripts/labs/animation_studio/animation_studio_view_controls.gd",
    "res://scripts/labs/animation_studio/animation_studio_casting.gd",
    "res://scripts/labs/animation_studio/animation_studio_routes.gd",
    "res://scripts/labs/animation_studio_rig_overlay.gd",
    "res://scripts/labs/animation_rig_quick_controls.gd",
]

var failures: int = 0


func _expect(condition: bool, message: String) -> void:
    if condition:
        print("ANIMATION_STUDIO_ARCHITECTURE_CHECK PASS ", message)
        return
    failures += 1
    push_error("ANIMATION_STUDIO_ARCHITECTURE_CHECK FAIL " + message)


func _init() -> void:
    _expect(FileAccess.file_exists(COORDINATOR_PATH), "stable Studio coordinator exists")
    var coordinator := FileAccess.get_file_as_string(COORDINATOR_PATH)
    var coordinator_lines := coordinator.split("\n").size()
    _expect(coordinator_lines <= 500, "Studio coordinator stays below 500 lines (%d)" % coordinator_lines)
    _expect(coordinator.count("func ") == 1, "coordinator owns lifecycle only")
    _expect(coordinator.contains("func _ready()"), "coordinator exposes the scene startup lifecycle")

    for module_path in PHASE_MODULES:
        _expect(FileAccess.file_exists(module_path), "named phase module exists: " + module_path.get_file())
        var module_script := load(module_path) as Script
        _expect(
            module_script != null and module_script.can_instantiate(),
            "named phase module parses and can instantiate: " + module_path.get_file()
        )

    if failures == 0:
        print("ANIMATION_STUDIO_ARCHITECTURE_REGRESSION PASS")
        quit(0)
        return
    print("ANIMATION_STUDIO_ARCHITECTURE_REGRESSION FAIL count=", failures)
    quit(1)

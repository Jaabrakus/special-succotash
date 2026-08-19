extends SceneTree

const POSE_PROFILE := preload("res://scripts/player/operator_procedural_pose_profile.gd")

const LAB_SCRIPT := preload("res://scripts/labs/operator_animation_lab.gd")
const DRAG_BUTTON_SCRIPT := preload("res://scripts/labs/animation_clip_drag_button.gd")
const DROP_TARGET_SCRIPT := preload("res://scripts/labs/animation_slot_drop_target.gd")
const ROUTE_GRAPH_SCRIPT := preload("res://scripts/labs/animation_route_graph.gd")

var failures: Array[String] = []


func _init() -> void:
    _run.call_deferred()


func _run() -> void:
    _expect(
        &"left_shoulder" in POSE_PROFILE.SUPPORTED_BONES
        and &"right_upper_arm" in POSE_PROFILE.SUPPORTED_BONES,
        "pose tuner exposes shoulder and upper-arm joints without translating bones"
    )
    var lab = LAB_SCRIPT.new()
    var skeleton := Skeleton3D.new()
    skeleton.add_bone("TestBone")
    var initial_pose := Transform3D(
        Basis.from_euler(Vector3(0.08, -0.12, 0.03)),
        Vector3(0.04, 0.18, -0.02)
    )
    skeleton.set_bone_pose(0, initial_pose)
    lab.skeleton = skeleton
    lab.is_playing = false

    lab.call("_capture_bone_edit_base", "TestBone")
    lab.bone_rot_offsets["TestBone"] = Vector3(12.0, -18.0, 4.0)
    lab.bone_pos_offsets["TestBone"] = Vector3(0.08, -0.03, 0.05)
    lab.call("_apply_bone_rot_overrides")
    var first_pose := skeleton.get_bone_pose(0)
    for frame in range(240):
        lab.call("_apply_bone_rot_overrides")
    var final_pose := skeleton.get_bone_pose(0)

    _expect(
        first_pose.is_equal_approx(final_pose),
        "paused pose edits do not accumulate across rendered frames"
    )
    _expect(
        final_pose.origin.is_equal_approx(initial_pose.origin + Vector3(0.08, -0.03, 0.05)),
        "move mode applies the requested local translation once"
    )
    var expected_basis := initial_pose.basis * Basis.from_euler(Vector3(
        deg_to_rad(12.0), deg_to_rad(-18.0), deg_to_rad(4.0)
    ))
    _expect(
        final_pose.basis.is_equal_approx(expected_basis),
        "rotate mode applies the requested local rotation once"
    )
    _expect(
        lab.rotation_degrees_per_pixel <= 0.20,
        "default rotation sensitivity stays in the fine-control range"
    )

    lab.state_slots = {"run_left": "res://replacement.fbx"}
    var merged_config: Dictionary = lab.call(
        "_merge_state_slots_into_config",
        {
            "clips": {"run_left": "res://old.fbx"},
            "clip_aliases": {"run_left": "run_forward_left"},
            "pose_yaw_offsets_degrees": {"run_left": 6.0},
            "locomotion": {"full_nominal_speed_mps": 5.7},
        }
    )
    _expect(
        merged_config["clips"]["run_left"] == "res://replacement.fbx",
        "studio save replaces the edited runtime clip slot"
    )
    _expect(
        merged_config.has("clip_aliases")
        and merged_config.has("pose_yaw_offsets_degrees")
        and merged_config.has("locomotion"),
        "studio save preserves aliases, pose angles, and locomotion tuning"
    )
    _expect(
        lab.call("_suggest_slot_for_entry", {
            "type": "FBX",
            "path": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run forward right.fbx",
        }) == "run_forward_right",
        "studio suggests the specific forward-right runtime state"
    )
    _expect(
        lab.call("_suggest_slot_for_entry", {
            "type": "FBX",
            "path": "res://assets/animations/mixamo/Unknown Acrobatics.fbx",
        }).is_empty(),
        "unknown clips stay unassigned instead of inventing an unsafe gameplay state"
    )

    var test_entry := {
        "type": "FBX",
        "display": "Run Forward Right",
        "path": "res://assets/animations/mixamo/Rifle 8-Way Locomotion Pack/run forward right.fbx",
    }
    var drag_button = DRAG_BUTTON_SCRIPT.new()
    drag_button.clip_entry = test_entry
    var payload: Dictionary = drag_button.call("_drag_payload")
    _expect(
        payload.get("kind", "") == "operator_animation_clip"
        and (payload.get("entry", {}) as Dictionary).get("path", "") == test_entry["path"],
        "clip row produces the complete animation drag payload"
    )

    var assembly_drop_target = DROP_TARGET_SCRIPT.new()
    var assembly_drop := {"entry": {}}
    var drop_visual_states: Array[String] = []
    assembly_drop_target.clip_dropped.connect(func(entry: Dictionary):
        assembly_drop["entry"] = entry
    )
    assembly_drop_target.drop_visual_state_changed.connect(func(state: String):
        drop_visual_states.append(state)
    )
    root.add_child(assembly_drop_target)
    assembly_drop_target.call("_notification", Control.NOTIFICATION_DRAG_BEGIN)
    _expect(
        assembly_drop_target.call("_can_drop_data", Vector2.ZERO, payload),
        "assembly dock accepts the same reliable clip drag payload"
    )
    _expect(
        "ready" in drop_visual_states and "hover" in drop_visual_states,
        "assembly dock visibly announces a valid drag and hovered release target"
    )
    assembly_drop_target.call("_drop_data", Vector2.ZERO, payload)
    _expect(
        (assembly_drop.get("entry", {}) as Dictionary).get("path", "") == test_entry["path"],
        "assembly dock receives the complete dragged clip"
    )

    var route_graph = ROUTE_GRAPH_SCRIPT.new()
    route_graph.call("set_state_data", {
        "run_forward": "res://old-forward.fbx",
        "run_forward_right": "res://old-forward-right.fbx",
        "idle_crouch": "res://old-crouch.fbx",
    }, "run_forward")
    var target_rect: Rect2 = route_graph.node_rects["run_forward_right"]
    var received_drop: Dictionary = {}
    route_graph.clip_dropped_on_state.connect(func(entry: Dictionary, slot_name: String):
        received_drop["entry"] = entry
        received_drop["slot"] = slot_name
    )
    _expect(
        route_graph.call("_can_drop_data", target_rect.get_center(), payload),
        "visual route card accepts an animation clip drag"
    )
    route_graph.call("_drop_data", target_rect.get_center(), payload)
    _expect(
        received_drop.get("slot", "") == "run_forward_right"
        and (received_drop.get("entry", {}) as Dictionary).get("path", "") == test_entry["path"],
        "dropping a clip identifies the exact connected runtime state"
    )

    var candidate_entry := test_entry.duplicate(true)
    candidate_entry["suggested_slot"] = "run_forward_right"
    route_graph.call("set_state_data", {
        "run_forward": "res://old-forward.fbx",
        "run_forward_right": "res://old-forward-right.fbx",
    }, "run_forward", [candidate_entry])
    _expect(
        route_graph.candidate_entries.size() == 1
        and route_graph.candidate_rects.size() == 1,
        "highlighted clip appears as a candidate card in the visual route graph"
    )
    var candidate_rect: Rect2 = route_graph.candidate_rects[0]
    _expect(
        route_graph.call("_candidate_at", candidate_rect.get_center()) == 0,
        "highlighted candidate card can be selected without drag-and-drop"
    )
    lab.highlighted_clip_entries.clear()
    lab.highlighted_clip_entries.append(candidate_entry)
    var shortlist: Dictionary = lab.call("_highlight_shortlist_payload")
    var saved_candidates: Array = shortlist.get("selected_clips", [])
    _expect(
        saved_candidates.size() == 1
        and (saved_candidates[0] as Dictionary).get("path", "") == test_entry["path"]
        and (saved_candidates[0] as Dictionary).get("suggested_slot", "") == "run_forward_right",
        "highlight shortlist preserves the user's clip and its proposed graph route for Codex"
    )

    lab.call("_build_ui")
    var clip_panel := lab.find_child("ClipLibraryPanel", true, false) as Control
    var runtime_panel := lab.find_child("RuntimeMapPanel", true, false) as Control
    var editor_dock := lab.find_child("FrameEditorDock", true, false) as Control
    _expect(
        clip_panel != null and editor_dock != null
        and clip_panel.anchor_bottom == editor_dock.anchor_top
        and clip_panel.offset_bottom <= editor_dock.offset_top,
        "frame editor is docked below the clip library instead of covering it"
    )
    _expect(
        runtime_panel != null and editor_dock != null
        and runtime_panel.anchor_bottom == editor_dock.anchor_top
        and runtime_panel.offset_bottom <= editor_dock.offset_top,
        "frame editor is docked below the route graph instead of covering it"
    )
    _expect(
        lab.find_child("AssemblyClipDropTarget", true, false) != null
        and _find_button_with_text(lab, "Save Cut Alone") != null
        and _find_button_with_text(lab, "Add Highlighted Cut →") != null,
        "frame editor exposes direct drag, trim-save, and range-assembly controls"
    )
    _expect(
        _find_button_with_text(lab, "+ Add Whole Clip") != null,
        "assembly dock provides a no-drag fallback for the selected clip"
    )

    lab.call("_clear_bone_rot_offsets")
    _expect(
        skeleton.get_bone_pose(0).is_equal_approx(initial_pose),
        "reset restores the sampled animation pose"
    )

    skeleton.free()
    drag_button.free()
    assembly_drop_target.free()
    route_graph.free()
    lab.free()

    if failures.is_empty():
        print("OPERATOR_POSE_TOOL_REGRESSION PASS")
        quit(0)
    else:
        for failure in failures:
            push_error(failure)
        print("OPERATOR_POSE_TOOL_REGRESSION FAIL ", failures)
        quit(1)


func _expect(condition: bool, description: String) -> void:
    if condition:
        print("POSE_TOOL_CHECK PASS ", description)
    else:
        failures.append(description)
        push_error("POSE_TOOL_CHECK FAIL %s" % description)


func _find_button_with_text(root: Node, value: String) -> Button:
    for node in root.find_children("*", "Button", true, false):
        var button := node as Button
        if button != null and button.text == value:
            return button
    return null

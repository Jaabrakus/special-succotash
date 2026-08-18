extends Node3D

const PS1_GAS_MASK_RIGGED_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const MILITARY_TACTICAL_SCENE := preload("res://assets/characters/military_tactical_operator/Anim_Idle_MIL_R5.fbx")
const OPERATOR_SCENE := preload("res://assets/characters/operator3d/socom_141_operator_animated.glb")
const MIXAMO_SKIN_SCENE := preload("res://assets/characters/operator3d/mixamo_beta_skin.glb")
const PS1_NV_SCENE := preload("res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb")
const PS1_GAS_MASK_OBJ := preload("res://assets/characters/ps1_gas_mask_soldier/sasman5.obj")
const PS1_GAS_MASK_TEX := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const AK47_FBX_SCENE := preload("res://assets/weapons/ps1_ak47/source/ak-47.fbx")
const AK47_TEXTURE := preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
const ANIMATION_MAP_PATH := "res://config/operator_animation_map.json"
const HIGHLIGHT_SHORTLIST_PATH := "res://config/highlighted_animation_candidates.json"
const LAYER_RECIPE_PATH := "res://config/operator_animation_layer_recipe.json"
const WEAPON_LOADOUT_PATH := "res://config/weapons/operator_loadout.json"
const AUTHORED_ANIMATION_DIR := "res://assets/animations/authored"
const CLIP_DRAG_BUTTON := preload("res://scripts/labs/animation_clip_drag_button.gd")
const SLOT_DROP_TARGET := preload("res://scripts/labs/animation_slot_drop_target.gd")
const STATE_TREE_DROP := preload("res://scripts/labs/animation_state_tree_drop.gd")
const ROUTE_GRAPH := preload("res://scripts/labs/animation_route_graph.gd")
const CLIP_EDITOR_SCRIPT := preload("res://scripts/labs/animation_clip_editor.gd")
const RANGE_SELECTOR_SCRIPT := preload("res://scripts/labs/animation_range_selector.gd")
const SEQUENCE_TIMELINE_SCRIPT := preload("res://scripts/labs/animation_sequence_timeline.gd")
const LAYER_COMPOSER_SCRIPT := preload("res://scripts/labs/animation_layer_composer.gd")
const POSE_EDITOR_SCRIPT := preload("res://scripts/labs/animation_pose_editor.gd")
const EDITOR_UI_SCALE := 0.84
const ROOT_SANITIZER := preload("res://scripts/player/operator_animation_root_sanitizer.gd")
const EDITOR_FPS := 30.0

enum SkinType {
    PS1_GAS_MASK_SOLDIER,
    MILITARY_TACTICAL_OPERATOR,
    SOCOM_OPERATOR,
    MIXAMO_MANNEQUIN,
    PS1_NIGHT_VISION_SEAL
}

enum WeaponType {
    M4A1_SOPMOD,
    MP5_SD,
    COMBAT_PISTOL,
    AK_47,
    NONE
}

var current_skin: SkinType = SkinType.PS1_GAS_MASK_SOLDIER
var current_weapon: WeaponType = WeaponType.AK_47
var model_root: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D

# Animation lists
var baked_clips: Array[StringName] = []
var fbx_files: Dictionary = {}
var authored_animation_files: Dictionary = {}
var all_clip_entries: Array[Dictionary] = []
var filtered_entries: Array[Dictionary] = []
var highlighted_clip_entries: Array[Dictionary] = []
var highlight_shortlist_loaded: bool = false
var clip_index: int = 0
var current_category: String = "ALL"
var dynamic_anim_lib: AnimationLibrary

# Playback controls
var is_playing: bool = true
var playback_speed: float = 0.5
var trim_in_seconds: float = 0.0
var trim_out_seconds: float = 0.0
var trim_preview_active: bool = false
var trim_preview_last_position: float = 0.0
var assembly_segments: Array[Dictionary] = []
var selected_sequence_regions: Dictionary = {"full_body": true}
var assembly_preview_active: bool = false
var assembly_card_panels: Dictionary = {}
var clip_editor = CLIP_EDITOR_SCRIPT.new()
var weapon_socket_visible: bool = true
var weapon_node: Node3D
var socket_attachment: BoneAttachment3D
var left_hand_marker: Marker3D

# Two-Hand Gun Engine Offsets
var right_grip_pos := Vector3(-0.02, 0.08, 0.05)
var right_grip_rot := Vector3(-90.0, 180.0, 0.0)
var left_handguard_pos := Vector3(0.0, 0.02, 0.28)
var two_hand_ik_enabled: bool = true
var two_hand_ik_weight: float = 1.0
var weapon_scale_factor: float = 1.0
var gun_sliders: Dictionary = {}

# 3D Draggable Limb Bubbles System
var bubbles_enabled: bool = true
var bubble_nodes: Dictionary = {} # BoneName -> {mesh: MeshInstance3D, bone_idx: int, color: Color}
var skeleton_chain_mesh := ImmediateMesh.new()
var skeleton_chain_instance: MeshInstance3D
var skeleton_chain_material: StandardMaterial3D
var active_dragged_bone: String = ""
var drag_start_mouse: Vector2 = Vector2.ZERO
var drag_origin_mouse: Vector2 = Vector2.ZERO
var drag_start_rotations: Dictionary = {}
var drag_rotation_chain: Array[String] = []
var drag_start_local_offset: Vector3 = Vector3.ZERO
var bone_rot_offsets: Dictionary = {} # BoneName -> Vector3 (euler angles in degrees)
var bone_pos_offsets: Dictionary = {} # BoneName -> local translation in meters
var bone_edit_base_poses: Dictionary = {} # Stable paused-frame pose; prevents cumulative edits
var pose_edit_mode: StringName = &"MOVE"
var rotation_degrees_per_pixel: float = 0.18
var translation_meters_per_pixel: float = 0.0015

# Camera Orbit
var camera: Camera3D
var orbit_yaw: float = -0.48
var orbit_pitch: float = -0.10
var orbit_distance: float = 3.6
var target_height: float = 0.95
var dragging: bool = false
var panning: bool = false

# UI Elements
var overlay: CanvasLayer
var editor_ui_root: Control
var status_label: Label
var category_container: HBoxContainer
var clip_scroll: ScrollContainer
var clip_list_vbox: VBoxContainer
var timeline_slider: HSlider
var time_label: Label
var trim_label: Label
var assembly_label: Label
var assembly_cards_vbox: VBoxContainer
var assembly_drop_label: Label
var assembly_drop_target: PanelContainer
var authored_name_input: LineEdit
var speed_button: Button
var range_selector: Control
var sequence_timeline: Control
var sequence_action_controls: Control
var sequence_transition_controls: Control
var sequence_selection_name_input: LineEdit
var sequence_drawer_button: Button
var persistent_action_controls: Control
var sequence_drawer_expanded: bool = false
var build_waiting_for_clip: bool = false
var selected_sequence_segment_index: int = -1
var sequence_selection_start: float = 0.0
var sequence_selection_end: float = 0.0
var assembly_preview_window_start: float = 0.0
var assembly_preview_window_end: float = -1.0
var frame_editor_dock: PanelContainer
var clip_library_panel: PanelContainer
var runtime_map_panel: PanelContainer
var trim_preview_button: Button
var sequence_region_buttons: Dictionary = {}
var sequence_region_summary_label: Label
var weapon_selector_button: Button
var skin_button: Button
var bubbles_toggle_btn: Button
var pose_tool_button: Button
var slot_panel_label: Label
var slot_suggestion_label: Label
var slot_drop_label: Label
var runtime_route_graph: Control
var state_slot_selector: OptionButton
var gun_lab_panel: PanelContainer
var gun_lab_visible: bool = false
var limb_hud_label: Label
var editor_pages: Dictionary = {}
var editor_mode_buttons: Dictionary = {}
var active_editor_page: String = ""
var layer_drop_labels: Dictionary = {}
var layer_recipe_summary: Label
var layer_recipe_name_input: LineEdit
var layer_recipe_family: String = "CUSTOM_BODY"
var selected_layer_key: String = "lower_body"
var layer_recipe: Dictionary = {
    "lower_body": "",
    "torso": "",
    "left_arm": "",
    "right_arm": "",
    "head": "",
}
var layer_composer = LAYER_COMPOSER_SCRIPT.new()
var pose_editor = POSE_EDITOR_SCRIPT.new()
var selected_pose_bone: String = ""
var pose_slider_controls: Dictionary = {}
var pose_slider_syncing: bool = false
var pose_selected_bone_label: Label
var pose_keyframe_label: Label
var pose_name_input: LineEdit
var pose_smooth_interpolation: bool = true
var pose_interpolation_button: Button
var pose_contact_summary_label: Label
var pose_contacts: Dictionary = {}
var pose_contact_wall_visual: MeshInstance3D

# Gameplay Slot Mappings. Values are FBX resource paths shared with the runtime
# animation driver, so a workbench assignment is immediately authoritative.
var state_slots: Dictionary = {}
var state_slot_keys: Array[String] = []
var selected_state_slot: String = "idle_rifle"

const MIXAMO_TO_PS1_MAP := {
    "mixamorig_Hips": "Spinelower",
    "mixamorig_Spine": "Spinelower",
    "mixamorig_Spine1": "Spineupper",
    "mixamorig_Spine2": "Spineupper",
    "mixamorig_Neck": "Neck",
    "mixamorig_Head": "head",
    "mixamorig_LeftShoulder": "Spineupper",
    "mixamorig_LeftArm": "ArmUpper.L",
    "mixamorig_LeftForeArm": "ArmLower.L",
    "mixamorig_LeftHand": "Hand.L.001",
    "mixamorig_RightShoulder": "Spineupper",
    "mixamorig_RightArm": "ArmUpper.R",
    "mixamorig_RightForeArm": "ArmLower.R",
    "mixamorig_RightHand": "Hand.R.001",
    "mixamorig_LeftUpLeg": "LegThigh.L",
    "mixamorig_LeftLeg": "LegShin.L",
    "mixamorig_LeftFoot": "Foot.L",
    "mixamorig_LeftToeBase": "FootToe.L",
    "mixamorig_RightUpLeg": "LegThigh.R",
    "mixamorig_RightLeg": "LegShin.R",
    "mixamorig_RightFoot": "Foot.R",
    "mixamorig_RightToeBase": "FootToe.R"
}

func _ready() -> void:
    _prepare_workshop_window()
    _scan_all_mixamo_fbx()
    _load_state_slots()
    _load_layer_recipe()
    _build_stage()
    _build_ui()
    _load_skin(current_skin)

func _prepare_workshop_window() -> void:
    if DisplayServer.get_name() == "headless":
        return
    var usable_rect := DisplayServer.screen_get_usable_rect()
    var target_size := Vector2i(
        mini(1600, usable_rect.size.x),
        mini(900, usable_rect.size.y)
    )
    target_size.x = maxi(target_size.x, mini(1280, usable_rect.size.x))
    target_size.y = maxi(target_size.y, mini(720, usable_rect.size.y))
    DisplayServer.window_set_min_size(Vector2i(
        mini(1100, usable_rect.size.x),
        mini(680, usable_rect.size.y)
    ))
    DisplayServer.window_set_size(target_size)
    DisplayServer.window_set_position(usable_rect.position + (usable_rect.size - target_size) / 2)

func _load_layer_recipe() -> void:
    if not FileAccess.file_exists(LAYER_RECIPE_PATH):
        return
    var file := FileAccess.open(LAYER_RECIPE_PATH, FileAccess.READ)
    var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
    if not parsed is Dictionary:
        return
    var saved := parsed as Dictionary
    # Older recipes were incorrectly presented as pistol families. Keep their
    # useful body-part assignments, but migrate the editor to a neutral body
    # composition recipe.
    layer_recipe_family = "CUSTOM_BODY"
    var saved_layers: Variant = saved.get("layers", {})
    if saved_layers is Dictionary:
        for layer_key in layer_recipe.keys():
            layer_recipe[layer_key] = String((saved_layers as Dictionary).get(layer_key, ""))

func _save_layer_recipe() -> void:
    var file := FileAccess.open(LAYER_RECIPE_PATH, FileAccess.WRITE)
    if file == null:
        if status_label:
            status_label.text = "Could not save the body-layer recipe."
        return
    file.store_string(JSON.stringify({
        "version": 1,
        "weapon_family": layer_recipe_family,
        "layers": layer_recipe,
        "note": "Bone-masked animation sources. Gameplay aim remains authoritative over the final head and weapon pose.",
    }, "  "))

func _assign_selected_clip_to_layer() -> void:
    if filtered_entries.is_empty():
        return
    var entry: Dictionary = filtered_entries[clip_index]
    _assign_entry_to_layer(entry, selected_layer_key)

func _assign_entry_to_layer(entry: Dictionary, layer_key: String) -> void:
    var path := String(entry.get("path", ""))
    if path.is_empty():
        status_label.text = "Choose an FBX or authored clip before assigning a body layer."
        return
    if not layer_recipe.has(layer_key):
        status_label.text = "That body part is not available in this recipe."
        return
    selected_layer_key = layer_key
    layer_recipe[layer_key] = path
    _save_layer_recipe()
    _refresh_layer_recipe_summary()
    status_label.text = "%s now drives %s in the saved layer recipe." % [
        String(entry.get("display", path.get_file())),
        layer_key.replace("_", " ").capitalize(),
    ]

func _build_layer_composite() -> void:
    var sources: Dictionary = {}
    for layer_key in layer_recipe.keys():
        var path := String(layer_recipe[layer_key])
        if path.is_empty():
            continue
        var entry := _entry_for_resource_path(path)
        if entry.is_empty():
            status_label.text = "The %s source is no longer in the animation library." % String(layer_key).replace("_", " ")
            return
        match String(entry.get("type", "")):
            "FBX":
                _load_and_retarget_fbx(entry)
            "AUTHORED":
                _load_authored_animation(entry)
        var animation := _get_current_animation(entry)
        if animation == null:
            status_label.text = "Could not load the %s layer." % String(layer_key).replace("_", " ")
            return
        sources[layer_key] = animation.duplicate(true)
    var composite: Animation = layer_composer.compose(sources, EDITOR_FPS)
    if composite == null or composite.get_track_count() == 0:
        status_label.text = "Assign at least one compatible body-layer clip first."
        return
    var requested_name := (
        layer_recipe_name_input.text.strip_edges()
        if layer_recipe_name_input
        else ""
    )
    if requested_name.is_empty():
        requested_name = "custom body animation"
    if authored_name_input:
        authored_name_input.text = requested_name
    var composite_segment: Array[Dictionary] = [{
        "animation": composite,
        "start": 0.0,
        "end": composite.length,
        "display": requested_name,
        "path": LAYER_RECIPE_PATH,
    }]
    _save_authored_segments(composite_segment, requested_name.to_snake_case(), false)

func _entry_for_resource_path(resource_path: String) -> Dictionary:
    for entry in all_clip_entries:
        if String(entry.get("path", "")) == resource_path:
            return entry
    return {}

func _refresh_layer_recipe_summary() -> void:
    if layer_recipe_summary == null:
        return
    var assigned_count := 0
    for layer_key in layer_recipe.keys():
        var path := String(layer_recipe[layer_key])
        if not path.is_empty():
            assigned_count += 1
        if layer_drop_labels.has(layer_key):
            var drop_label: Label = layer_drop_labels[layer_key]
            drop_label.text = "%s\n%s" % [
                String(layer_key).replace("lower_body", "legs").replace("_", " ").capitalize(),
                "Drop a clip" if path.is_empty() else path.get_file().get_basename(),
            ]
    layer_recipe_summary.text = "%d / %d body parts assigned" % [assigned_count, layer_recipe.size()]

func _show_editor_page(page_name: String) -> void:
    var previous_page := active_editor_page
    active_editor_page = page_name
    trim_preview_active = false
    if page_name == "Build" and previous_page != "Build":
        sequence_drawer_expanded = false
    for key in editor_pages.keys():
        var page: Control = editor_pages[key]
        page.visible = String(key) == page_name
    for key in editor_mode_buttons.keys():
        var button: Button = editor_mode_buttons[key]
        button.button_pressed = String(key) == page_name
    if pose_contact_wall_visual:
        pose_contact_wall_visual.visible = page_name == "Pose"
    if timeline_slider:
        timeline_slider.visible = page_name != "Build"
    if range_selector:
        range_selector.visible = page_name == "Build"
    _refresh_sequence_drawer_visibility()
    _apply_editor_workspace_layout()
    if page_name != "Build":
        trim_preview_active = false
        _refresh_trim_preview_button()
    if page_name == "Build" and previous_page != "Build":
        _show_body_composer_rest_pose()
    elif previous_page == "Build":
        if weapon_node:
            weapon_node.visible = current_weapon != WeaponType.NONE
        _play_selected()
    if page_name == "Pose":
        _prepare_pose_mode()

func _apply_editor_workspace_layout() -> void:
    if frame_editor_dock == null or clip_library_panel == null or runtime_map_panel == null:
        return
    var build_mode := active_editor_page == "Build"
    # Build needs room for both the source-range and destination timelines.
    # Preview and Routes keep only a compact transport strip, returning the
    # otherwise empty lower third to the model viewport and side panels.
    var expanded_build := build_mode and sequence_drawer_expanded
    frame_editor_dock.offset_top = -316.0 if expanded_build else (-112.0 if build_mode else -108.0)
    var workspace_bottom := -330.0 if expanded_build else (-126.0 if build_mode else -122.0)
    clip_library_panel.offset_bottom = workspace_bottom
    runtime_map_panel.offset_bottom = workspace_bottom

func _toggle_sequence_drawer() -> void:
    sequence_drawer_expanded = not sequence_drawer_expanded
    _refresh_sequence_drawer_visibility()
    _apply_editor_workspace_layout()

func _refresh_sequence_drawer_visibility() -> void:
    var build_mode := active_editor_page == "Build"
    if sequence_drawer_button:
        sequence_drawer_button.visible = build_mode
        sequence_drawer_button.text = "%s OUTPUT EDITOR  •  %d CUTS" % [
            "▼ CLOSE" if sequence_drawer_expanded else "▲ OPEN",
            assembly_segments.size(),
        ]
    if sequence_timeline:
        sequence_timeline.visible = build_mode and sequence_drawer_expanded
    if sequence_action_controls:
        sequence_action_controls.visible = build_mode and sequence_drawer_expanded
    if sequence_transition_controls:
        sequence_transition_controls.visible = build_mode and sequence_drawer_expanded
    if persistent_action_controls:
        persistent_action_controls.visible = not build_mode

func _fit_editor_ui_to_window() -> void:
    if editor_ui_root == null:
        return
    var viewport_size := get_viewport().get_visible_rect().size
    editor_ui_root.position = Vector2.ZERO
    editor_ui_root.scale = Vector2.ONE * EDITOR_UI_SCALE
    editor_ui_root.size = viewport_size / EDITOR_UI_SCALE

func _show_body_composer_rest_pose() -> void:
    trim_preview_active = false
    is_playing = false
    build_waiting_for_clip = true
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    if animation_player:
        animation_player.stop()
    if skeleton:
        skeleton.clear_bones_global_pose_override()
        skeleton.reset_bone_poses()
    if weapon_node:
        weapon_node.visible = false

func _preview_trim_range() -> void:
    var animation := _selected_animation()
    if animation_player == null or animation == null:
        return
    assembly_preview_active = false
    if trim_preview_active:
        trim_preview_active = false
        animation_player.pause()
        is_playing = false
        _refresh_trim_preview_button()
        status_label.text = "Kept-frame preview paused."
        return
    trim_in_seconds = clampf(trim_in_seconds, 0.0, animation.length)
    trim_out_seconds = clampf(trim_out_seconds, trim_in_seconds + (1.0 / EDITOR_FPS), animation.length)
    var source_segment := _current_trim_segment()
    var masked_segments: Array[Dictionary] = []
    for region in _selected_sequence_region_keys():
        var region_segment := source_segment.duplicate(true)
        region_segment["layer"] = region
        masked_segments.append(region_segment)
    var kept_preview := _build_assembly_animation(masked_segments)
    if kept_preview == null or kept_preview.get_track_count() == 0:
        status_label.text = "The highlighted body regions have no compatible tracks in these frames."
        return
    kept_preview.loop_mode = Animation.LOOP_LINEAR
    var preview_key := StringName("kept_frames_preview")
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    dynamic_anim_lib.add_animation(preview_key, kept_preview)
    animation_player.stop()
    if skeleton:
        skeleton.clear_bones_global_pose_override()
        skeleton.reset_bone_poses()
    animation_player.speed_scale = playback_speed
    animation_player.play(StringName("dyn/%s" % preview_key))
    is_playing = true
    trim_preview_active = true
    trim_preview_last_position = 0.0
    _refresh_trim_preview_button()
    status_label.text = "Looping frames %d–%d on: %s. Press again to stop." % [
        roundi(trim_in_seconds * EDITOR_FPS),
        roundi(trim_out_seconds * EDITOR_FPS),
        ", ".join(_selected_sequence_region_keys()).replace("lower_body", "legs").replace("_", " "),
    ]

func _refresh_trim_preview_button() -> void:
    if trim_preview_button:
        trim_preview_button.text = "■ Stop Kept Frames" if trim_preview_active else "▶ Play Frames To Keep"

func _touch_button(text_value: String, minimum_width: float = 0.0) -> Button:
    var button := Button.new()
    button.text = text_value
    button.custom_minimum_size = Vector2(minimum_width, 44.0)
    return button

func _create_body_layer_target(layer_key: String, title: String, minimum_size: Vector2) -> PanelContainer:
    var target: PanelContainer = SLOT_DROP_TARGET.new()
    target.name = "%sBodyDropTarget" % layer_key.to_pascal_case()
    target.custom_minimum_size = minimum_size
    target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    target.tooltip_text = "Drag any animation clip here to use its %s motion." % title.to_lower()
    target.clip_dropped.connect(_assign_entry_to_layer.bind(layer_key))
    var label := Label.new()
    label.text = "%s\nDrop a clip" % title
    label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
    label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    label.add_theme_font_size_override("font_size", 11)
    target.add_child(label)
    layer_drop_labels[layer_key] = label
    return target

func _scan_all_mixamo_fbx() -> void:
    fbx_files.clear()
    _scan_dir_recursive("res://assets/animations/mixamo")
    _scan_authored_animations()

func _scan_authored_animations() -> void:
    authored_animation_files.clear()
    var directory := DirAccess.open(AUTHORED_ANIMATION_DIR)
    if directory == null:
        return
    directory.list_dir_begin()
    var file_name := directory.get_next()
    while not file_name.is_empty():
        if not directory.current_is_dir() and file_name.ends_with(".tres"):
            authored_animation_files[file_name.get_basename().capitalize()] = "%s/%s" % [AUTHORED_ANIMATION_DIR, file_name]
        file_name = directory.get_next()

func _scan_dir_recursive(dir_path: String) -> void:
    var dir := DirAccess.open(dir_path)
    if dir:
        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
            if dir.current_is_dir() and not file_name.begins_with("."):
                _scan_dir_recursive(dir_path + "/" + file_name)
            elif file_name.ends_with(".fbx") and not file_name.begins_with("."):
                var full_path := dir_path + "/" + file_name
                var clean_name := file_name.get_basename().capitalize()
                var folder := dir_path.get_file()
                var tag := ""
                if "Pistol" in folder: tag = "[Pistol] "
                elif "Locomotion" in folder or "Lite" in folder: tag = "[Rifle] "
                elif "Shooter" in folder: tag = "[Shooter] "
                clean_name = tag + clean_name
                fbx_files[clean_name] = full_path
            file_name = dir.get_next()

func _load_skin(skin: SkinType) -> void:
    if model_root:
        model_root.queue_free()
        model_root = null
    
    current_skin = skin
    
    match skin:
        SkinType.PS1_GAS_MASK_SOLDIER:
            model_root = PS1_GAS_MASK_RIGGED_SCENE.instantiate() as Node3D
            model_root.scale = Vector3.ONE * 55.0  # Mixamo exported at ~3cm tall, scale to ~1.8m
            _apply_trooper_texture(model_root)

        SkinType.MILITARY_TACTICAL_OPERATOR:
            model_root = MILITARY_TACTICAL_SCENE.instantiate() as Node3D

        SkinType.SOCOM_OPERATOR:
            model_root = OPERATOR_SCENE.instantiate() as Node3D

        SkinType.MIXAMO_MANNEQUIN:
            model_root = MIXAMO_SKIN_SCENE.instantiate() as Node3D

        SkinType.PS1_NIGHT_VISION_SEAL:
            model_root = PS1_NV_SCENE.instantiate() as Node3D
    
    model_root.name = "PreviewOperator"
    model_root.rotation.y = PI
    add_child(model_root)

    if skin == SkinType.SOCOM_OPERATOR:
        _hide_baked_rifle_parts(model_root)

    animation_player = _find_animation_player(model_root)
    skeleton = _find_skeleton(model_root)

    # If model has a skeleton but no AnimationPlayer (e.g. trooper_rigged.fbx),
    # create one so we can load and play Mixamo clips dynamically
    if animation_player == null and skeleton != null:
        animation_player = AnimationPlayer.new()
        animation_player.name = "AnimationPlayer"
        skeleton.add_child(animation_player)
        animation_player.owner = model_root
        # Point the animation player root at the skeleton so bone tracks resolve
        animation_player.root_node = animation_player.get_path_to(skeleton)

    if animation_player:
        dynamic_anim_lib = AnimationLibrary.new()
        if not animation_player.has_animation_library("dyn"):
            animation_player.add_animation_library("dyn", dynamic_anim_lib)

    _rebuild_weapon_socket()
    _rebuild_limb_bubbles()

    baked_clips.clear()
    if animation_player:
        for anim_name in animation_player.get_animation_list():
            if not str(anim_name).begins_with("dyn/"):
                baked_clips.append(StringName(anim_name))
        baked_clips.sort()

    all_clip_entries.clear()
    for baked in baked_clips:
        all_clip_entries.append({"name": baked, "key": str(baked), "display": str(baked), "type": "BAKED", "path": ""})
    for fbx_name in fbx_files.keys():
        var clean_key: String = str(fbx_name).replace("[", "").replace("]", "").replace(" ", "_").replace("-", "_").replace("(", "").replace(")", "").replace(".", "_").to_lower()
        all_clip_entries.append({"name": StringName("dyn/" + clean_key), "key": clean_key, "display": fbx_name, "type": "FBX", "path": fbx_files[fbx_name]})
    for authored_name in authored_animation_files.keys():
        var authored_key := "authored_" + str(authored_name).to_snake_case()
        all_clip_entries.append({
            "name": StringName("dyn/" + authored_key),
            "key": authored_key,
            "display": "[Authored] " + str(authored_name),
            "type": "AUTHORED",
            "path": authored_animation_files[authored_name],
        })

    if not highlight_shortlist_loaded:
        _load_highlighted_shortlist()
        highlight_shortlist_loaded = true

    _filter_category(current_category)
    clip_index = 0
    if active_editor_page == "Build":
        _show_body_composer_rest_pose()
    else:
        _play_selected()
    _refresh_clip_list_ui()

func _hide_mannequin_mesh(node: Node) -> void:
    if node is MeshInstance3D:
        node.visible = false
    for c in node.get_children():
        _hide_mannequin_mesh(c)

func _apply_trooper_texture(node: Node) -> void:
    if node is MeshInstance3D:
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = PS1_GAS_MASK_TEX
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        mat.roughness = 0.9
        (node as MeshInstance3D).material_override = mat
    for c in node.get_children():
        _apply_trooper_texture(c)

func _generate_auto_skinned_mesh(src_mesh: ArrayMesh, skel: Skeleton3D) -> ArrayMesh:
    var src_arrays := src_mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
    var uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
    
    var bones: PackedInt32Array = PackedInt32Array()
    var weights: PackedFloat32Array = PackedFloat32Array()
    var new_vertices: PackedVector3Array = PackedVector3Array()
    
    # Scale from 3.34m to 1.85m standard height
    var scale_factor := 1.85 / 3.344682
    
    var head_idx := skel.find_bone("mixamorig_Head")
    if head_idx == -1: head_idx = skel.find_bone("mixamorig:Head")
    var spine_idx := skel.find_bone("mixamorig_Spine2")
    if spine_idx == -1: spine_idx = skel.find_bone("mixamorig:Spine2")
    var hips_idx := skel.find_bone("mixamorig_Hips")
    if hips_idx == -1: hips_idx = skel.find_bone("mixamorig:Hips")
    var r_arm_idx := skel.find_bone("mixamorig_RightArm")
    if r_arm_idx == -1: r_arm_idx = skel.find_bone("mixamorig:RightArm")
    var r_forearm_idx := skel.find_bone("mixamorig_RightForeArm")
    if r_forearm_idx == -1: r_forearm_idx = skel.find_bone("mixamorig:RightForeArm")
    var l_arm_idx := skel.find_bone("mixamorig_LeftArm")
    if l_arm_idx == -1: l_arm_idx = skel.find_bone("mixamorig:LeftArm")
    var l_forearm_idx := skel.find_bone("mixamorig_LeftForeArm")
    if l_forearm_idx == -1: l_forearm_idx = skel.find_bone("mixamorig:LeftForeArm")
    var r_thigh_idx := skel.find_bone("mixamorig_RightUpLeg")
    if r_thigh_idx == -1: r_thigh_idx = skel.find_bone("mixamorig:RightUpLeg")
    var r_leg_idx := skel.find_bone("mixamorig_RightLeg")
    if r_leg_idx == -1: r_leg_idx = skel.find_bone("mixamorig:RightLeg")
    var r_foot_idx := skel.find_bone("mixamorig_RightFoot")
    if r_foot_idx == -1: r_foot_idx = skel.find_bone("mixamorig:RightFoot")
    var l_thigh_idx := skel.find_bone("mixamorig_LeftUpLeg")
    if l_thigh_idx == -1: l_thigh_idx = skel.find_bone("mixamorig:LeftUpLeg")
    var l_leg_idx := skel.find_bone("mixamorig_LeftLeg")
    if l_leg_idx == -1: l_leg_idx = skel.find_bone("mixamorig:LeftLeg")
    var l_foot_idx := skel.find_bone("mixamorig_LeftFoot")
    if l_foot_idx == -1: l_foot_idx = skel.find_bone("mixamorig:LeftFoot")
    
    for v in vertices:
        var scaled_v := v * scale_factor
        new_vertices.append(scaled_v)
        
        var chosen_bone := hips_idx
        var y := scaled_v.y
        var x := scaled_v.x
        
        if y > 1.48:
            chosen_bone = head_idx
        elif y > 0.95:
            if x > 0.28:
                chosen_bone = r_forearm_idx if y < 1.30 else r_arm_idx
            elif x < -0.28:
                chosen_bone = l_forearm_idx if y < 1.30 else l_arm_idx
            else:
                chosen_bone = spine_idx
        else:
            if x >= 0:
                if y < 0.18: chosen_bone = r_foot_idx
                elif y < 0.55: chosen_bone = r_leg_idx
                else: chosen_bone = r_thigh_idx
            else:
                if y < 0.18: chosen_bone = l_foot_idx
                elif y < 0.55: chosen_bone = l_leg_idx
                else: chosen_bone = l_thigh_idx
                
        bones.append(chosen_bone if chosen_bone != -1 else 0)
        bones.append(0)
        bones.append(0)
        bones.append(0)
        
        weights.append(1.0)
        weights.append(0.0)
        weights.append(0.0)
        weights.append(0.0)
        
    var new_arrays := []
    new_arrays.resize(Mesh.ARRAY_MAX)
    new_arrays[Mesh.ARRAY_VERTEX] = new_vertices
    new_arrays[Mesh.ARRAY_NORMAL] = normals
    new_arrays[Mesh.ARRAY_TEX_UV] = uvs
    new_arrays[Mesh.ARRAY_BONES] = bones
    new_arrays[Mesh.ARRAY_WEIGHTS] = weights
    
    var out_mesh := ArrayMesh.new()
    out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
    return out_mesh

func _build_segmented_meshes(src_mesh: ArrayMesh, skel: Skeleton3D, bone_map: Dictionary) -> Dictionary:
    var src_arrays := src_mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
    var uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
    var indices: PackedInt32Array = src_arrays[Mesh.ARRAY_INDEX]
    
    var seg_verts := {"head": PackedVector3Array(), "torso": PackedVector3Array(), "left_arm": PackedVector3Array(), "right_arm": PackedVector3Array(), "left_leg": PackedVector3Array(), "right_leg": PackedVector3Array()}
    var seg_norms := {"head": PackedVector3Array(), "torso": PackedVector3Array(), "left_arm": PackedVector3Array(), "right_arm": PackedVector3Array(), "left_leg": PackedVector3Array(), "right_leg": PackedVector3Array()}
    var seg_uvs := {"head": PackedVector2Array(), "torso": PackedVector2Array(), "left_arm": PackedVector2Array(), "right_arm": PackedVector2Array(), "left_leg": PackedVector2Array(), "right_leg": PackedVector2Array()}
    
    var scale_factor := 1.85 / 3.344682
    
    for i in range(0, indices.size(), 3):
        var idx0 := indices[i]
        var idx1 := indices[i+1]
        var idx2 := indices[i+2]
        
        var v0 := vertices[idx0] * scale_factor
        var v1 := vertices[idx1] * scale_factor
        var v2 := vertices[idx2] * scale_factor
        var center := (v0 + v1 + v2) / 3.0
        
        var target := "torso"
        if center.y > 1.45:
            target = "head"
        elif center.y > 0.95:
            if center.x > 0.22: target = "right_arm"
            elif center.x < -0.22: target = "left_arm"
            else: target = "torso"
        else:
            if center.x >= 0: target = "right_leg"
            else: target = "left_leg"
            
        var bone_name: String = bone_map.get(target, "mixamorig_Hips")
        var b_idx := skel.find_bone(bone_name)
        var bone_rest: Transform3D = skel.get_bone_global_rest(b_idx) if b_idx != -1 else Transform3D.IDENTITY
        var inv_rest := bone_rest.affine_inverse()
        
        for v_idx in [idx0, idx1, idx2]:
            var world_v := vertices[v_idx] * scale_factor
            var local_v := inv_rest * world_v
            var local_norm := inv_rest.basis * normals[v_idx]
            
            seg_verts[target].append(local_v)
            seg_norms[target].append(local_norm)
            seg_uvs[target].append(uvs[v_idx])
            
    var result := {}
    for key in seg_verts.keys():
        if seg_verts[key].size() > 0:
            var arrs := []
            arrs.resize(Mesh.ARRAY_MAX)
            arrs[Mesh.ARRAY_VERTEX] = seg_verts[key]
            arrs[Mesh.ARRAY_NORMAL] = seg_norms[key]
            arrs[Mesh.ARRAY_TEX_UV] = seg_uvs[key]
            var m := ArrayMesh.new()
            m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
            result[key] = m
    return result

func _process(delta: float) -> void:
    if active_editor_page != "Pose" and not dragging and not panning and active_dragged_bone == "":
        orbit_yaw += delta * 0.04
    _update_camera()
    _update_ui_state()
    _update_assembly_playhead()
    if active_editor_page == "Build" and build_waiting_for_clip:
        if animation_player and animation_player.is_playing():
            animation_player.stop()
        if skeleton:
            skeleton.clear_bones_global_pose_override()
            skeleton.reset_bone_poses()
    elif active_editor_page != "Build":
        _apply_two_hand_ik()
        _apply_bone_rot_overrides()
    _update_skeleton_chain_visual()
    _update_bubble_positions()

func _rebuild_limb_bubbles() -> void:
    for b in bubble_nodes.values():
        if is_instance_valid(b["node"]):
            b["node"].queue_free()
    bubble_nodes.clear()

    if skeleton == null:
        return

    _ensure_skeleton_chain_visual()

    # Direct-manipulation landmarks. The small rendered node is separate from
    # its generous screen-space picking radius, so joints remain easy to grab
    # without covering the operator.
    var landmarks := {
        "HEAD": {"names": ["mixamorig_Head", "mixamorig:Head", "head"], "color": Color(1.0, 0.85, 0.2, 0.95), "radius": 0.040},
        "NECK": {"names": ["mixamorig_Neck", "mixamorig:Neck", "neck"], "color": Color(0.45, 1.0, 0.55, 0.95), "radius": 0.032},
        "CHEST": {"names": ["mixamorig_Spine2", "mixamorig:Spine2", "Spineupper"], "color": Color(0.45, 1.0, 0.55, 0.95), "radius": 0.040},
        "SPINE": {"names": ["mixamorig_Spine1", "mixamorig:Spine1", "Spine"], "color": Color(0.45, 1.0, 0.55, 0.95), "radius": 0.037},
        "HIPS": {"names": ["mixamorig_Hips", "mixamorig:Hips", "Spinelower"], "color": Color(1.0, 1.0, 1.0, 0.95), "radius": 0.043},
        "RIGHT_SHOULDER": {"names": ["mixamorig_RightShoulder", "mixamorig:RightShoulder", "Shoulder.R"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "LEFT_SHOULDER": {"names": ["mixamorig_LeftShoulder", "mixamorig:LeftShoulder", "Shoulder.L"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "RIGHT_ELBOW": {"names": ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "ArmLower.R"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "LEFT_ELBOW": {"names": ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "ArmLower.L"], "color": Color(0.12, 0.9, 1.0, 0.95), "radius": 0.034},
        "RIGHT_HAND": {"names": ["mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001"], "color": Color(0.1, 0.95, 0.85, 0.98), "radius": 0.037},
        "LEFT_HAND": {"names": ["mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001"], "color": Color(0.2, 1.0, 0.35, 0.98), "radius": 0.037},
        "RIGHT_KNEE": {"names": ["mixamorig_RightLeg", "mixamorig:RightLeg", "LegLower.R"], "color": Color(0.2, 0.58, 1.0, 0.95), "radius": 0.035},
        "LEFT_KNEE": {"names": ["mixamorig_LeftLeg", "mixamorig:LeftLeg", "LegLower.L"], "color": Color(0.2, 0.58, 1.0, 0.95), "radius": 0.035},
        "RIGHT_FOOT": {"names": ["mixamorig_RightFoot", "mixamorig:RightFoot", "Foot.R"], "color": Color(1.0, 0.5, 0.1, 0.98), "radius": 0.037},
        "LEFT_FOOT": {"names": ["mixamorig_LeftFoot", "mixamorig:LeftFoot", "Foot.L"], "color": Color(1.0, 0.2, 0.6, 0.98), "radius": 0.037},
    }

    for landmark_id in landmarks.keys():
        var cfg: Dictionary = landmarks[landmark_id]
        var target_bone := ""
        var bone_idx := -1
        for cand in cfg["names"]:
            bone_idx = skeleton.find_bone(cand)
            if bone_idx != -1:
                target_bone = cand
                break
        
        if bone_idx != -1:
            var bubble_root := Node3D.new()
            bubble_root.name = "Bubble_" + landmark_id
            var bubble_mesh := MeshInstance3D.new()
            var sphere := SphereMesh.new()
            sphere.radius = float(cfg["radius"])
            sphere.height = float(cfg["radius"]) * 2.0
            sphere.radial_segments = 12
            sphere.rings = 6
            bubble_mesh.mesh = sphere
            var material := StandardMaterial3D.new()
            material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
            material.albedo_color = cfg["color"]
            material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            material.no_depth_test = true
            bubble_mesh.material_override = material
            bubble_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
            bubble_root.add_child(bubble_mesh)
            add_child(bubble_root)
            bubble_nodes[landmark_id] = {
                "node": bubble_root,
                "material": material,
                "bone_name": target_bone,
                "bone_idx": bone_idx,
                "color": cfg["color"],
                "radius": cfg["radius"]
            }

func _ensure_skeleton_chain_visual() -> void:
    if skeleton_chain_instance != null:
        return
    skeleton_chain_material = StandardMaterial3D.new()
    skeleton_chain_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    skeleton_chain_material.vertex_color_use_as_albedo = true
    skeleton_chain_material.no_depth_test = true
    skeleton_chain_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    skeleton_chain_instance = MeshInstance3D.new()
    skeleton_chain_instance.name = "SkeletonBodyChain"
    skeleton_chain_instance.mesh = skeleton_chain_mesh
    skeleton_chain_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(skeleton_chain_instance)

func _update_skeleton_chain_visual() -> void:
    if skeleton_chain_instance == null:
        return
    skeleton_chain_instance.visible = bubbles_enabled and skeleton != null
    skeleton_chain_mesh.clear_surfaces()
    if not skeleton_chain_instance.visible:
        return
    skeleton_chain_mesh.surface_begin(Mesh.PRIMITIVE_LINES, skeleton_chain_material)
    for bone_index in range(skeleton.get_bone_count()):
        var parent_index := skeleton.get_bone_parent(bone_index)
        if parent_index < 0:
            continue
        var child_global := skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)
        var parent_global := skeleton.global_transform * skeleton.get_bone_global_pose(parent_index)
        var segment_length := child_global.origin.distance_to(parent_global.origin)
        if segment_length < 0.002 or segment_length > 1.5:
            continue
        var bone_name := skeleton.get_bone_name(bone_index).to_lower()
        var color := Color(0.12, 0.9, 1.0, 0.92)
        if "spine" in bone_name or "hips" in bone_name or "neck" in bone_name:
            color = Color(0.35, 1.0, 0.45, 0.95)
        elif "leg" in bone_name or "foot" in bone_name or "toe" in bone_name:
            color = Color(0.2, 0.58, 1.0, 0.92)
        elif "head" in bone_name:
            color = Color(1.0, 0.82, 0.2, 0.95)
        if active_editor_page == "Build" and not selected_sequence_regions.has("full_body"):
            var sequence_region := _sequence_region_for_bone_name(bone_name)
            if sequence_region.is_empty() or not selected_sequence_regions.has(sequence_region):
                color = Color(0.22, 0.25, 0.3, 0.32)
            else:
                color = color.lightened(0.18)
        if skeleton.get_bone_name(bone_index) in [active_dragged_bone, selected_pose_bone]:
            color = Color.WHITE
        skeleton_chain_mesh.surface_set_color(color)
        skeleton_chain_mesh.surface_add_vertex(skeleton_chain_instance.to_local(parent_global.origin))
        skeleton_chain_mesh.surface_set_color(color)
        skeleton_chain_mesh.surface_add_vertex(skeleton_chain_instance.to_local(child_global.origin))
    skeleton_chain_mesh.surface_end()

func _sequence_region_for_bone_name(bone_name: String) -> String:
    if "leftshoulder" in bone_name or "leftarm" in bone_name or "lefthand" in bone_name or "armupper.l" in bone_name or "armlower.l" in bone_name or "hand.l" in bone_name:
        return "left_arm"
    if "rightshoulder" in bone_name or "rightarm" in bone_name or "righthand" in bone_name or "armupper.r" in bone_name or "armlower.r" in bone_name or "hand.r" in bone_name:
        return "right_arm"
    if "neck" in bone_name or "head" in bone_name or "eye" in bone_name:
        return "head"
    if "spine" in bone_name and not "spinelower" in bone_name:
        return "torso"
    if "hips" in bone_name or "spinelower" in bone_name or "leg" in bone_name or "foot" in bone_name or "toe" in bone_name:
        return "lower_body"
    return ""

func _update_bubble_positions() -> void:
    if not bubbles_enabled or skeleton == null:
        for b in bubble_nodes.values():
            if is_instance_valid(b["node"]):
                b["node"].visible = false
        return

    for landmark_id in bubble_nodes.keys():
        var b: Dictionary = bubble_nodes[landmark_id]
        var node: Node3D = b["node"]
        if is_instance_valid(node):
            node.visible = bubbles_enabled
            var bone_global_trans := skeleton.global_transform * skeleton.get_bone_global_pose(b["bone_idx"])
            node.global_position = bone_global_trans.origin
            var is_selected: bool = b["bone_name"] in [selected_pose_bone, active_dragged_bone]
            node.scale = Vector3.ONE * (1.55 if is_selected else 1.0)
            var material: StandardMaterial3D = b.get("material")
            if material:
                material.albedo_color = Color.WHITE if is_selected else b["color"]

func _apply_bone_rot_overrides() -> void:
    if skeleton == null:
        return
    var edited_bones: Dictionary = {}
    for bone_name in bone_rot_offsets.keys():
        edited_bones[bone_name] = true
    for bone_name in bone_pos_offsets.keys():
        edited_bones[bone_name] = true
    for bone_name in edited_bones.keys():
        var b_idx := skeleton.find_bone(bone_name)
        if b_idx != -1:
            if not bone_edit_base_poses.has(bone_name):
                _capture_bone_edit_base(bone_name)
            var pose: Transform3D = (
                skeleton.get_bone_pose(b_idx)
                if is_playing
                else bone_edit_base_poses[bone_name]
            )
            var deg: Vector3 = bone_rot_offsets.get(bone_name, Vector3.ZERO)
            var position: Vector3 = bone_pos_offsets.get(bone_name, Vector3.ZERO)
            var rad := Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
            var add_basis := Basis.from_euler(rad)
            pose.basis = pose.basis * add_basis
            pose.origin += position
            skeleton.set_bone_pose(b_idx, pose)

func _capture_bone_edit_base(bone_name: String, replace_existing: bool = false) -> void:
    if skeleton == null or bone_name.is_empty():
        return
    if bone_edit_base_poses.has(bone_name) and not replace_existing:
        return
    var bone_idx := skeleton.find_bone(bone_name)
    if bone_idx < 0:
        return
    bone_edit_base_poses[bone_name] = skeleton.get_bone_pose(bone_idx)
    if not bone_rot_offsets.has(bone_name):
        bone_rot_offsets[bone_name] = Vector3.ZERO
    if not bone_pos_offsets.has(bone_name):
        bone_pos_offsets[bone_name] = Vector3.ZERO

func _capture_all_edit_bases_after_seek() -> void:
    if skeleton == null:
        return
    for bone_name in bone_edit_base_poses.keys():
        var bone_idx := skeleton.find_bone(bone_name)
        if bone_idx >= 0:
            bone_edit_base_poses[bone_name] = skeleton.get_bone_pose(bone_idx)

func _pause_for_pose_edit() -> void:
    if animation_player == null:
        return
    if animation_player.is_playing():
        var current_time := animation_player.current_animation_position
        animation_player.pause()
        animation_player.seek(current_time, true)
    is_playing = false
    _capture_all_edit_bases_after_seek()

func _toggle_pose_edit_mode() -> void:
    _set_pose_edit_mode(&"MOVE" if pose_edit_mode == &"ROTATE" else &"ROTATE")

func _set_pose_edit_mode(next_mode: StringName) -> void:
    pose_edit_mode = next_mode
    if pose_tool_button != null:
        pose_tool_button.text = "Bone Tool (M): %s" % pose_edit_mode

func _human_rotation_limits(bone_name: String) -> Vector3:
    var lower := bone_name.to_lower()
    if "forearm" in lower or "armlower" in lower:
        return Vector3(145.0, 32.0, 40.0)
    if "arm" in lower or "shoulder" in lower:
        return Vector3(105.0, 100.0, 95.0)
    if "leglower" in lower or lower.ends_with("rightleg") or lower.ends_with("leftleg"):
        return Vector3(145.0, 24.0, 28.0)
    if "upleg" in lower or "upperleg" in lower:
        return Vector3(115.0, 55.0, 55.0)
    if "foot" in lower or "toe" in lower:
        return Vector3(55.0, 30.0, 25.0)
    if "head" in lower or "neck" in lower:
        return Vector3(55.0, 75.0, 45.0)
    if "spine" in lower or "chest" in lower:
        return Vector3(45.0, 60.0, 40.0)
    if "hand" in lower:
        return Vector3(70.0, 45.0, 80.0)
    if "hips" in lower:
        return Vector3(35.0, 55.0, 35.0)
    return Vector3(75.0, 75.0, 75.0)

func _clamp_human_rotation(bone_name: String, rotation_degrees: Vector3) -> Vector3:
    var limits := _human_rotation_limits(bone_name)
    return Vector3(
        clampf(rotation_degrees.x, -limits.x, limits.x),
        clampf(rotation_degrees.y, -limits.y, limits.y),
        clampf(rotation_degrees.z, -limits.z, limits.z)
    )

func _anatomical_drag_chain(bone_name: String) -> Array[String]:
    var result: Array[String] = []
    if skeleton == null:
        return result
    var selected_index := skeleton.find_bone(bone_name)
    if selected_index < 0:
        return result
    var lower := bone_name.to_lower()
    var driver_index := selected_index
    # End effectors move through their upstream joints. This preserves the
    # authored bone lengths instead of stretching a hand or foot away from its
    # arm/leg.
    if "hand" in lower or "foot" in lower or "head" in lower or "neck" in lower:
        driver_index = skeleton.get_bone_parent(selected_index)
    elif (
        "forearm" in lower
        or "armlower" in lower
        or "leglower" in lower
        or lower.ends_with("rightleg")
        or lower.ends_with("leftleg")
    ):
        driver_index = skeleton.get_bone_parent(selected_index)
    if driver_index >= 0:
        result.append(skeleton.get_bone_name(driver_index))
        var parent_index := skeleton.get_bone_parent(driver_index)
        if parent_index >= 0 and ("hand" in lower or "foot" in lower):
            result.append(skeleton.get_bone_name(parent_index))
    return result

func _begin_anatomical_drag(bone_name: String) -> void:
    drag_rotation_chain = _anatomical_drag_chain(bone_name)
    drag_start_rotations.clear()
    drag_start_local_offset = bone_pos_offsets.get(bone_name, Vector3.ZERO)
    for driver_bone in drag_rotation_chain:
        _capture_bone_edit_base(driver_bone)
        drag_start_rotations[driver_bone] = bone_rot_offsets.get(driver_bone, Vector3.ZERO)

func _drag_anatomical_chain(mouse_delta_from_start: Vector2) -> void:
    for chain_index in range(drag_rotation_chain.size()):
        var driver_bone := drag_rotation_chain[chain_index]
        var start_rotation: Vector3 = drag_start_rotations.get(driver_bone, Vector3.ZERO)
        var influence := 1.0 if chain_index == 0 else 0.55
        var requested := start_rotation + Vector3(
            -mouse_delta_from_start.y * 0.32 * influence,
            mouse_delta_from_start.x * 0.30 * influence,
            mouse_delta_from_start.x * 0.10 * influence
        )
        bone_rot_offsets[driver_bone] = _clamp_human_rotation(driver_bone, requested)

func _apply_two_hand_ik() -> void:
    if not two_hand_ik_enabled or skeleton == null or left_hand_marker == null or current_weapon == WeaponType.NONE:
        return
    # Skip IK on scaled models — the target positions don't match
    if model_root and model_root.scale.x > 1.5:
        return
    
    var left_hand_idx := skeleton.find_bone("mixamorig_LeftHand")
    if left_hand_idx == -1: left_hand_idx = skeleton.find_bone("mixamorig:LeftHand")
    if left_hand_idx == -1: left_hand_idx = skeleton.find_bone("Hand.L.001")
    if left_hand_idx == -1: return

    var target_global_pos := left_hand_marker.global_position
    var target_in_skel := skeleton.global_transform.affine_inverse() * target_global_pos
    var current_hand_pose := skeleton.get_bone_global_pose(left_hand_idx)
    
    var blend_pos := current_hand_pose.origin.lerp(target_in_skel, 0.85 * two_hand_ik_weight)
    current_hand_pose.origin = blend_pos
    skeleton.set_bone_global_pose_override(left_hand_idx, current_hand_pose, 0.85 * two_hand_ik_weight, true)

func _update_ui_state() -> void:
    if animation_player == null or filtered_entries.is_empty():
        return
    
    var entry: Dictionary = filtered_entries[clip_index]
    var anim: Animation = _get_current_animation(entry)
    var length: float = anim.length if anim else 1.0
    var current_pos: float = (
        animation_player.current_animation_position
        if not animation_player.current_animation.is_empty()
        else 0.0
    )
    var displayed_source_pos := trim_in_seconds + current_pos if trim_preview_active else current_pos
    
    if not timeline_slider.has_focus():
        timeline_slider.max_value = length
        timeline_slider.set_value_no_signal(displayed_source_pos)
    
    var current_frame := clampi(roundi(displayed_source_pos * EDITOR_FPS), 0, maxi(1, roundi(length * EDITOR_FPS)))
    var total_frames := maxi(1, roundi(length * EDITOR_FPS))
    timeline_slider.step = 1.0 / EDITOR_FPS
    timeline_slider.tick_count = total_frames + 1
    timeline_slider.ticks_on_borders = true
    if range_selector:
        range_selector.set_playhead(displayed_source_pos)
    time_label.text = "Frame %d / %d  •  %.2fs / %.2fs" % [current_frame, total_frames, displayed_source_pos, length]
    _refresh_frame_editor_labels()
    
    var skin_name := _skin_name(current_skin)
    var wep_name := _weapon_name(current_weapon)
    status_label.text = (
        "[ REST POSE ]  •  Drag clips from the library onto the T-pose body map"
        if active_editor_page == "Body"
        else "[ %s ]  •  Weapon: %s  •  Clip %d/%d: %s (%.2fs)" % [
            skin_name,
            wep_name,
            clip_index + 1,
            filtered_entries.size(),
            entry["display"],
            length
        ]
    )

    if active_dragged_bone != "":
        limb_hud_label.visible = true
        var deg: Vector3 = bone_rot_offsets.get(active_dragged_bone, Vector3.ZERO)
        var pos: Vector3 = bone_pos_offsets.get(active_dragged_bone, Vector3.ZERO)
        limb_hud_label.text = (
            "%s [%s]  ROT %.1f°, %.1f°, %.1f°  POS %.3f, %.3f, %.3f m"
            % [pose_edit_mode, active_dragged_bone, deg.x, deg.y, deg.z, pos.x, pos.y, pos.z]
        )
    else:
        limb_hud_label.visible = false

func _get_current_animation(entry: Dictionary) -> Animation:
    if entry["type"] == "BAKED":
        return animation_player.get_animation(entry["name"]) if animation_player else null
    elif dynamic_anim_lib and entry.has("key"):
        var anim_key: StringName = StringName(entry["key"])
        if dynamic_anim_lib.has_animation(anim_key):
            return dynamic_anim_lib.get_animation(anim_key)
    return null

func _unhandled_input(event: InputEvent) -> void:
    # Some full-window 3D controls can claim an otherwise valid drawer click.
    # Treat the visible handle as authoritative before orbit input begins.
    if (
        event is InputEventMouseButton
        and event.button_index == MOUSE_BUTTON_LEFT
        and event.pressed
        and sequence_drawer_button != null
        and sequence_drawer_button.visible
        and sequence_drawer_button.get_global_rect().has_point(event.position)
    ):
        _toggle_sequence_drawer()
        get_viewport().set_input_as_handled()
        return
    if event is InputEventKey and event.pressed and not event.echo:
        match event.physical_keycode:
            KEY_LEFT:
                _select_relative(-1)
            KEY_RIGHT:
                _select_relative(1)
            KEY_SPACE:
                _toggle_play_pause()
            KEY_TAB:
                _toggle_skin()
            KEY_G:
                _cycle_weapon()
            KEY_B:
                _toggle_bubbles()
            KEY_M:
                _toggle_pose_edit_mode()
            KEY_L:
                _toggle_gun_lab()
            KEY_R:
                _reset_camera()
            KEY_C:
                _clear_bone_rot_offsets()
            KEY_1:
                _assign_to_slot("idle_rifle")
            KEY_2:
                _assign_to_slot("run_forward")
            KEY_3:
                _assign_to_slot("run_backward")
            KEY_4:
                _assign_to_slot("jump_loop")
            KEY_5:
                _assign_to_slot("dive_roll")
            KEY_6:
                _assign_to_slot("prone_backward")
            KEY_ESCAPE:
                get_tree().quit()

    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                # Raycast to find clicked limb bubble
                var clicked_bone := _find_bubble_at_mouse(event.position)
                if clicked_bone != "":
                    _pause_for_pose_edit()
                    active_dragged_bone = clicked_bone
                    _select_pose_bone(clicked_bone)
                    drag_start_mouse = event.position
                    drag_origin_mouse = event.position
                    _capture_bone_edit_base(clicked_bone)
                    _begin_anatomical_drag(clicked_bone)
                else:
                    dragging = true
            else:
                dragging = false
                active_dragged_bone = ""
                _sync_pose_sliders_from_selection()

        elif event.button_index == MOUSE_BUTTON_RIGHT:
            panning = event.pressed
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            orbit_distance = maxf(1.4, orbit_distance - 0.25)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            orbit_distance = minf(7.5, orbit_distance + 0.25)

    elif event is InputEventMouseMotion:
        if active_dragged_bone != "":
            var delta_drag: Vector2 = event.position - drag_start_mouse
            var total_drag: Vector2 = event.position - drag_origin_mouse
            drag_start_mouse = event.position
            if pose_edit_mode == &"ROTATE":
                var current_rot: Vector3 = bone_rot_offsets.get(active_dragged_bone, Vector3.ZERO)
                current_rot = _clamp_human_rotation(
                    active_dragged_bone,
                    current_rot + Vector3(
                        -delta_drag.y * rotation_degrees_per_pixel,
                        delta_drag.x * rotation_degrees_per_pixel,
                        0.0
                    )
                )
                bone_rot_offsets[active_dragged_bone] = current_rot
            else:
                var lower_name := active_dragged_bone.to_lower()
                if "hips" in lower_name or "root" in lower_name:
                    var current_pos: Vector3 = bone_pos_offsets.get(active_dragged_bone, Vector3.ZERO)
                    if event.shift_pressed:
                        current_pos.z = clampf(
                            current_pos.z - delta_drag.y * translation_meters_per_pixel,
                            -0.35,
                            0.35
                        )
                    else:
                        current_pos.x = clampf(
                            current_pos.x + delta_drag.x * translation_meters_per_pixel,
                            -0.35,
                            0.35
                        )
                        current_pos.y = clampf(
                            current_pos.y - delta_drag.y * translation_meters_per_pixel,
                            -0.35,
                            0.35
                        )
                    bone_pos_offsets[active_dragged_bone] = current_pos
                else:
                    _drag_anatomical_chain(total_drag)
        elif dragging:
            orbit_yaw -= event.relative.x * 0.007
            orbit_pitch = clampf(orbit_pitch - event.relative.y * 0.005, -0.65, 0.45)
        elif panning:
            target_height = clampf(target_height + event.relative.y * 0.004, 0.2, 1.8)

func _find_bubble_at_mouse(m_pos: Vector2) -> String:
    if not bubbles_enabled or camera == null:
        return ""
    var closest_dist := 36.0 # pixel hit radius
    var selected_bone := ""
    
    for landmark_id in bubble_nodes.keys():
        var b: Dictionary = bubble_nodes[landmark_id]
        var node: Node3D = b["node"]
        if is_instance_valid(node) and not camera.is_position_behind(node.global_position):
            var screen_pos := camera.unproject_position(node.global_position)
            var d := screen_pos.distance_to(m_pos)
            if d < closest_dist:
                closest_dist = d
                selected_bone = b["bone_name"]
    return selected_bone

func _toggle_bubbles() -> void:
    bubbles_enabled = not bubbles_enabled
    bubbles_toggle_btn.text = "Skeleton Chain (B): " + ("ON" if bubbles_enabled else "OFF")

func _clear_bone_rot_offsets() -> void:
    if skeleton != null:
        for bone_name in bone_edit_base_poses.keys():
            var bone_idx := skeleton.find_bone(bone_name)
            if bone_idx >= 0:
                skeleton.set_bone_pose(bone_idx, bone_edit_base_poses[bone_name])
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    _sync_pose_sliders_from_selection()

func _prepare_pose_mode() -> void:
    if animation_player == null or skeleton == null:
        return
    build_waiting_for_clip = false
    _set_pose_edit_mode(&"MOVE")
    if animation_player.current_animation.is_empty() and not filtered_entries.is_empty():
        _play_selected()
    _pause_for_pose_edit()
    if weapon_node:
        weapon_node.visible = current_weapon != WeaponType.NONE
    if selected_pose_bone.is_empty() and not bubble_nodes.is_empty():
        var first_landmark := String(bubble_nodes.keys()[0])
        selected_pose_bone = String((bubble_nodes[first_landmark] as Dictionary).get("bone_name", ""))
    if not selected_pose_bone.is_empty():
        _capture_bone_edit_base(selected_pose_bone)
    _sync_pose_sliders_from_selection()
    _refresh_pose_keyframe_label()

func _select_pose_bone(bone_name: String) -> void:
    if bone_name.is_empty():
        return
    selected_pose_bone = bone_name
    _capture_bone_edit_base(bone_name)
    _sync_pose_sliders_from_selection()
    _update_skeleton_chain_visual()

func _sync_pose_sliders_from_selection() -> void:
    if pose_selected_bone_label:
        pose_selected_bone_label.text = (
            "SELECTED JOINT: %s" % selected_pose_bone.replace("mixamorig_", "").replace("mixamorig:", "")
            if not selected_pose_bone.is_empty()
            else "SELECTED JOINT: click a cyan skeleton node"
        )
    if pose_slider_controls.is_empty():
        return
    pose_slider_syncing = true
    var position: Vector3 = bone_pos_offsets.get(selected_pose_bone, Vector3.ZERO)
    var rotation: Vector3 = bone_rot_offsets.get(selected_pose_bone, Vector3.ZERO)
    var selected_lower := selected_pose_bone.to_lower()
    var root_can_translate := "hips" in selected_lower or "root" in selected_lower
    var values := {
        "move_x": position.x,
        "move_y": position.y,
        "move_z": position.z,
        "rot_x": rotation.x,
        "rot_y": rotation.y,
        "rot_z": rotation.z,
    }
    for key in values.keys():
        if pose_slider_controls.has(key):
            var slider: HSlider = pose_slider_controls[key]["slider"]
            var value_label: Label = pose_slider_controls[key]["label"]
            slider.editable = root_can_translate if String(key).begins_with("move_") else true
            slider.value = float(values[key])
            value_label.text = (
                _pose_slider_value_text(String(key), float(values[key]))
                if slider.editable
                else "chain locked"
            )
    pose_slider_syncing = false

func _pose_slider_value_text(key: String, value: float) -> String:
    return "%.1f°" % value if key.begins_with("rot_") else "%.1f cm" % (value * 100.0)

func _set_pose_slider_value(key: String, value: float) -> void:
    if pose_slider_syncing or selected_pose_bone.is_empty():
        return
    _pause_for_pose_edit()
    _capture_bone_edit_base(selected_pose_bone)
    if key.begins_with("move_"):
        var selected_lower := selected_pose_bone.to_lower()
        if not ("hips" in selected_lower or "root" in selected_lower):
            status_label.text = "Limb length protected: drag this node to rotate its anatomical chain instead of stretching the bone."
            _sync_pose_sliders_from_selection()
            return
        var position: Vector3 = bone_pos_offsets.get(selected_pose_bone, Vector3.ZERO)
        match key:
            "move_x": position.x = value
            "move_y": position.y = value
            "move_z": position.z = value
        bone_pos_offsets[selected_pose_bone] = position
    else:
        var rotation: Vector3 = bone_rot_offsets.get(selected_pose_bone, Vector3.ZERO)
        match key:
            "rot_x": rotation.x = value
            "rot_y": rotation.y = value
            "rot_z": rotation.z = value
        bone_rot_offsets[selected_pose_bone] = _clamp_human_rotation(selected_pose_bone, rotation)
    if pose_slider_controls.has(key):
        var value_label: Label = pose_slider_controls[key]["label"]
        value_label.text = _pose_slider_value_text(key, value)
    _apply_bone_rot_overrides()
    if skeleton:
        skeleton.force_update_all_bone_transforms()

func _current_pose_frame() -> int:
    if animation_player == null or animation_player.current_animation.is_empty():
        return 0
    return maxi(0, roundi(animation_player.current_animation_position * EDITOR_FPS))

func _capture_pose_keyframe() -> void:
    if skeleton == null:
        return
    _pause_for_pose_edit()
    _apply_bone_rot_overrides()
    skeleton.force_update_all_bone_transforms()
    var frame := _current_pose_frame()
    pose_editor.capture_pose(skeleton, frame, pose_contacts)
    _refresh_pose_keyframe_label()
    status_label.text = "Captured the complete edited skeleton at frame %d. The source animation is unchanged." % frame

func _duplicate_latest_pose() -> void:
    if skeleton == null:
        return
    if pose_editor.keyframes.is_empty():
        _capture_pose_keyframe()
        return
    var source_index: int = pose_editor.keyframes.size() - 1
    var target_frame := int(pose_editor.keyframes[source_index].get("frame", 0)) + 1
    var selected_animation := _selected_animation()
    if animation_player and selected_animation:
        animation_player.seek(minf(float(target_frame) / EDITOR_FPS, selected_animation.length), true)
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    pose_editor.apply_keyframe(skeleton, source_index)
    pose_editor.capture_pose(skeleton, target_frame, pose_contacts)
    _capture_all_edit_bases_after_seek()
    _sync_pose_sliders_from_selection()
    _refresh_pose_keyframe_label()
    status_label.text = "Duplicated the previous pose to frame %d. Adjust a joint, then capture again." % target_frame

func _copy_latest_pose() -> void:
    if pose_editor.copy_latest_pose():
        status_label.text = "Copied the latest complete body pose."
    else:
        status_label.text = "Capture a pose before copying it."

func _paste_pose_to_current_frame() -> void:
    if skeleton == null or not pose_editor.paste_pose(skeleton):
        status_label.text = "Copy a captured pose before pasting it."
        return
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    _capture_all_edit_bases_after_seek()
    _sync_pose_sliders_from_selection()
    status_label.text = "Pasted the copied pose. Press Capture Pose to keep it at this frame."

func _pose_skeleton_path() -> NodePath:
    if animation_player == null or skeleton == null:
        return NodePath("")
    var animation_root := animation_player.get_node_or_null(animation_player.root_node)
    if animation_root == null:
        return NodePath("")
    return animation_root.get_path_to(skeleton)

func _build_pose_animation() -> Animation:
    return pose_editor.build_animation(_pose_skeleton_path(), EDITOR_FPS, pose_smooth_interpolation)

func _preview_pose_strip() -> void:
    var animation := _build_pose_animation()
    if animation == null or animation_player == null:
        status_label.text = "Capture at least one pose before previewing."
        return
    var preview_key := StringName("pose_strip_preview")
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    dynamic_anim_lib.add_animation(preview_key, animation)
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()
    skeleton.reset_bone_poses()
    animation_player.play(StringName("dyn/" + String(preview_key)))
    animation_player.speed_scale = playback_speed
    is_playing = true
    status_label.text = "Playing %d captured key poses with %s interpolation." % [
        pose_editor.keyframes.size(),
        "smooth" if pose_smooth_interpolation else "held stop-motion",
    ]

func _save_pose_strip() -> void:
    var animation := _build_pose_animation()
    if animation == null:
        status_label.text = "Capture at least one pose before saving."
        return
    var requested_name := pose_name_input.text.strip_edges() if pose_name_input else ""
    if requested_name.is_empty():
        requested_name = "stop_motion_pose"
    if authored_name_input:
        authored_name_input.text = requested_name
    var baked_pose: Array[Dictionary] = [{
        "animation": animation,
        "start": 0.0,
        "end": animation.length,
        "display": requested_name,
        "path": "",
    }]
    _save_authored_segments(baked_pose, requested_name.to_snake_case(), false)

func _clear_pose_strip() -> void:
    pose_editor.clear()
    pose_contacts.clear()
    _refresh_pose_keyframe_label()
    status_label.text = "Cleared captured key poses. Imported source animations were not changed."

func _toggle_pose_interpolation() -> void:
    pose_smooth_interpolation = not pose_smooth_interpolation
    if pose_interpolation_button:
        pose_interpolation_button.text = "Between Poses: %s" % (
            "SMOOTH" if pose_smooth_interpolation else "HOLD"
        )

func _refresh_pose_keyframe_label() -> void:
    if pose_keyframe_label:
        pose_keyframe_label.text = pose_editor.summary()
    if pose_contact_summary_label:
        pose_contact_summary_label.text = "CONTACTS: %s" % (
            "none" if pose_contacts.is_empty() else ", ".join(pose_contacts.keys())
        )

func _snap_selected_bone_to_collision(contact_type: String) -> void:
    if skeleton == null or selected_pose_bone.is_empty():
        status_label.text = "Select a skeleton joint before snapping it to a surface."
        return
    var bone_index := skeleton.find_bone(selected_pose_bone)
    if bone_index < 0:
        return
    _pause_for_pose_edit()
    _apply_bone_rot_overrides()
    skeleton.force_update_all_bone_transforms()
    var bone_skeleton_position := skeleton.get_bone_global_pose(bone_index).origin
    var bone_world_position := skeleton.global_transform * bone_skeleton_position
    var directions: Array[Vector3] = [Vector3.DOWN]
    if contact_type == "wall":
        directions = [Vector3.LEFT, Vector3.RIGHT, Vector3.FORWARD, Vector3.BACK]
    var closest_hit: Dictionary = {}
    var closest_distance := INF
    var world := get_world_3d()
    if world == null:
        return
    for direction in directions:
        var query := PhysicsRayQueryParameters3D.create(
            bone_world_position - direction * 0.05,
            bone_world_position + direction * 1.5
        )
        var hit := world.direct_space_state.intersect_ray(query)
        if not hit.is_empty():
            var distance := bone_world_position.distance_to(hit.get("position", bone_world_position))
            if distance < closest_distance:
                closest_distance = distance
                closest_hit = hit
    if closest_hit.is_empty():
        status_label.text = "No %s collision is close enough to this joint." % contact_type
        return
    var target_world: Vector3 = closest_hit.get("position", bone_world_position)
    var target_skeleton := skeleton.global_transform.affine_inverse() * target_world
    var skeleton_delta := target_skeleton - bone_skeleton_position
    var parent_index := skeleton.get_bone_parent(bone_index)
    var local_delta := skeleton_delta
    if parent_index >= 0:
        local_delta = skeleton.get_bone_global_pose(parent_index).basis.inverse() * skeleton_delta
    var current_offset: Vector3 = bone_pos_offsets.get(selected_pose_bone, Vector3.ZERO)
    bone_pos_offsets[selected_pose_bone] = current_offset + local_delta
    pose_contacts[contact_type] = {
        "bone": selected_pose_bone,
        "position": target_world,
        "normal": closest_hit.get("normal", Vector3.UP),
    }
    _apply_bone_rot_overrides()
    _sync_pose_sliders_from_selection()
    _refresh_pose_keyframe_label()
    status_label.text = "Snapped %s to the nearest %s collision. Capture Pose to store the contact." % [selected_pose_bone, contact_type]

func _select_relative(amount: int) -> void:
    if filtered_entries.is_empty():
        return
    clip_index = wrapi(clip_index + amount, 0, filtered_entries.size())
    _play_selected()
    _refresh_clip_list_ui()

func _play_selected() -> void:
    if animation_player == null or filtered_entries.is_empty():
        return
    trim_preview_active = false
    assembly_preview_active = false
    if active_editor_page == "Build":
        build_waiting_for_clip = false
    _refresh_trim_preview_button()
    if weapon_node:
        weapon_node.visible = current_weapon != WeaponType.NONE
    var entry: Dictionary = filtered_entries[clip_index]
    var clip_name: StringName = entry["name"]
    
    if entry["type"] == "FBX":
        _load_and_retarget_fbx(entry)
    elif entry["type"] == "AUTHORED":
        _load_authored_animation(entry)
    
    var anim := _get_current_animation(entry)
    if anim:
        anim.loop_mode = Animation.LOOP_LINEAR if _should_loop(entry["display"]) else Animation.LOOP_NONE
    
    animation_player.speed_scale = playback_speed
    if animation_player.has_animation(clip_name):
        animation_player.play(clip_name, 0.1)
        is_playing = true
        trim_in_seconds = 0.0
        trim_out_seconds = anim.length if anim else 0.0
        if range_selector and anim:
            range_selector.set_clip_length(anim.length, true)
        _refresh_frame_editor_labels()
        if active_editor_page == "Pose":
            animation_player.seek(0.0, true)
            _pause_for_pose_edit()
            bone_rot_offsets.clear()
            bone_pos_offsets.clear()
            bone_edit_base_poses.clear()
            _sync_pose_sliders_from_selection()

func _load_authored_animation(entry: Dictionary) -> void:
    var anim_key: StringName = StringName(entry.get("key", ""))
    if anim_key == &"" or dynamic_anim_lib.has_animation(anim_key):
        return
    var source_authored := load(str(entry.get("path", ""))) as Animation
    if source_authored != null:
        var authored := source_authored.duplicate(true) as Animation
        ROOT_SANITIZER.sanitize(authored, _should_loop(str(entry.get("display", ""))))
        dynamic_anim_lib.add_animation(anim_key, authored)

func _load_and_retarget_fbx(entry: Dictionary) -> void:
    var anim_key: StringName = StringName(entry["key"])
    if dynamic_anim_lib.has_animation(anim_key):
        return
    
    var fbx_path: String = entry["path"]
    var packed: PackedScene = load(fbx_path) as PackedScene
    if not packed:
        return
    
    var temp_instance := packed.instantiate()
    var temp_player := _find_animation_player(temp_instance)
    if not temp_player or temp_player.get_animation_list().is_empty():
        temp_instance.queue_free()
        return
    
    var src_anim_name := _select_source_animation_name(temp_player)
    if src_anim_name == &"":
        temp_instance.queue_free()
        return
    var src_anim: Animation = temp_player.get_animation(src_anim_name)
    if not src_anim:
        temp_instance.queue_free()
        return

    # Universal 65-Bone Retargeter with Full Finger & Spine Tracks
    var retargeted: Animation = src_anim.duplicate()
    var skel_path: NodePath = NodePath("GeneralSkeleton")
    if skeleton:
        skel_path = animation_player.get_node(animation_player.root_node).get_path_to(skeleton)

    var track_idx := retargeted.get_track_count() - 1
    while track_idx >= 0:
        var old_path_str := str(retargeted.track_get_path(track_idx))
        var raw_bone := old_path_str.split(":")[-1]
        var normalized_mixamo := raw_bone.replace("mixamorig:", "mixamorig_")
        if not normalized_mixamo.begins_with("mixamorig_"):
            normalized_mixamo = "mixamorig_" + normalized_mixamo

        var target_bone := ""
        if skeleton:
            if current_skin == SkinType.PS1_NIGHT_VISION_SEAL and MIXAMO_TO_PS1_MAP.has(normalized_mixamo):
                target_bone = MIXAMO_TO_PS1_MAP[normalized_mixamo]
            elif skeleton.find_bone(raw_bone) != -1:
                target_bone = raw_bone
            elif skeleton.find_bone(normalized_mixamo) != -1:
                target_bone = normalized_mixamo
            elif skeleton.find_bone(normalized_mixamo.replace("mixamorig_", "mixamorig:")) != -1:
                target_bone = normalized_mixamo.replace("mixamorig_", "mixamorig:")
            else:
                var lower_raw := raw_bone.to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
                for b_i in range(skeleton.get_bone_count()):
                    var b_name := skeleton.get_bone_name(b_i)
                    if b_name.to_lower() == lower_raw or b_name.to_lower().begins_with(lower_raw):
                        target_bone = b_name
                        break

        if target_bone != "":
            var new_path := NodePath(str(skel_path) + ":" + target_bone)
            retargeted.track_set_path(track_idx, new_path)

            if ("Hips" in raw_bone or "Spinelower" in target_bone or "root" in raw_bone.to_lower()) and retargeted.track_get_type(track_idx) == Animation.TYPE_POSITION_3D:
                var bone_idx := skeleton.find_bone(target_bone) if skeleton else -1
                var rest_y := skeleton.get_bone_rest(bone_idx).origin.y if bone_idx != -1 else 0.92
                var base_y := 0.0
                if retargeted.track_get_key_count(track_idx) > 0:
                    base_y = retargeted.track_get_key_value(track_idx, 0).y
                    
                # Scale factor: ratio of target skeleton hips to source animation hips
                # This keeps the bobbing proportional instead of adding raw meter offsets
                var scale_factor := (rest_y / base_y) if base_y != 0.0 else 1.0
                    
                for key_idx in range(retargeted.track_get_key_count(track_idx)):
                    var pos: Vector3 = retargeted.track_get_key_value(track_idx, key_idx)
                    pos.x = 0.0
                    pos.z = 0.0
                    pos.y = pos.y * scale_factor
                    retargeted.track_set_key_value(track_idx, key_idx, pos)
        else:
            retargeted.remove_track(track_idx)
            
        track_idx -= 1

    ROOT_SANITIZER.sanitize(retargeted, _should_loop(str(entry.get("display", ""))))
    dynamic_anim_lib.add_animation(anim_key, retargeted)
    temp_instance.queue_free()

func _select_source_animation_name(player: AnimationPlayer) -> StringName:
    var names := player.get_animation_list()
    if names.has(&"mixamo_com"):
        return &"mixamo_com"
    for animation_name in names:
        if animation_name != &"RESET":
            return animation_name
    return &""

func _toggle_play_pause() -> void:
    if animation_player == null:
        return
    if active_editor_page == "Build":
        _preview_trim_range()
        return
    if animation_player.is_playing():
        _pause_for_pose_edit()
    else:
        animation_player.play()
        is_playing = true

func _step_animation_frame(direction: int) -> void:
    var animation := _selected_animation()
    if animation_player == null or animation == null:
        return
    _pause_for_pose_edit()
    var current_frame := roundi(animation_player.current_animation_position * EDITOR_FPS)
    var total_frames := maxi(1, roundi(animation.length * EDITOR_FPS))
    var target_frame := clampi(current_frame + direction, 0, total_frames)
    animation_player.seek(float(target_frame) / EDITOR_FPS, true)
    _capture_all_edit_bases_after_seek()

func _set_trim_in() -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    trim_in_seconds = minf(_snapped_current_time(), trim_out_seconds - (1.0 / EDITOR_FPS))
    trim_in_seconds = clampf(trim_in_seconds, 0.0, animation.length)
    _refresh_frame_editor_labels()

func _set_trim_out() -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    trim_out_seconds = maxf(_snapped_current_time(), trim_in_seconds + (1.0 / EDITOR_FPS))
    trim_out_seconds = clampf(trim_out_seconds, 0.0, animation.length)
    _refresh_frame_editor_labels()

func _on_range_selector_changed(start_seconds: float, end_seconds: float) -> void:
    trim_in_seconds = start_seconds
    trim_out_seconds = end_seconds
    _refresh_frame_editor_labels()

func _on_range_playhead_requested(seconds: float) -> void:
    if animation_player == null or animation_player.current_animation.is_empty():
        return
    animation_player.seek(seconds, true)
    if animation_player.is_playing():
        animation_player.pause()
    is_playing = false

func _preview_assembly() -> void:
    if animation_player == null or assembly_segments.is_empty():
        if status_label:
            status_label.text = "Add at least one cut before previewing the sequence."
        return
    var combined: Animation = _build_assembly_animation(assembly_segments)
    if combined == null or combined.get_track_count() == 0:
        status_label.text = "The sequence has no compatible animation tracks."
        return
    var preview_key := StringName("sequence_preview")
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    dynamic_anim_lib.add_animation(preview_key, combined)
    combined.loop_mode = Animation.LOOP_LINEAR
    animation_player.speed_scale = playback_speed
    animation_player.play(StringName("dyn/%s" % preview_key), 0.08)
    is_playing = true
    trim_preview_active = false
    assembly_preview_active = true
    assembly_preview_window_start = 0.0
    assembly_preview_window_end = combined.length
    status_label.text = "Previewing all %d sequence cuts together." % assembly_segments.size()

func _on_sequence_selection_changed(start_seconds: float, end_seconds: float) -> void:
    sequence_selection_start = start_seconds
    sequence_selection_end = end_seconds
    if status_label and end_seconds > start_seconds:
        status_label.text = "Selected output frames %d–%d. Play or save this range below." % [
            roundi(start_seconds * EDITOR_FPS),
            roundi(end_seconds * EDITOR_FPS),
        ]

func _on_sequence_segment_selected(index: int) -> void:
    selected_sequence_segment_index = index
    if index < 0 or index >= assembly_segments.size():
        return
    var segment: Dictionary = assembly_segments[index]
    status_label.text = "Selected cut: %s (%s). Choose a transition clip on the left, then attach it before or after." % [
        str(segment.get("display", "animation")),
        str(segment.get("layer", "full_body")).replace("lower_body", "legs").replace("_", " "),
    ]

func _current_sequence_selection() -> Vector2:
    if sequence_timeline and sequence_timeline.has_method("get_selection"):
        var selection: Vector2 = sequence_timeline.get_selection()
        sequence_selection_start = selection.x
        sequence_selection_end = selection.y
    return Vector2(sequence_selection_start, sequence_selection_end)

func _play_sequence_animation(animation: Animation, key_text: String, message: String, window: Vector2) -> void:
    if animation_player == null or animation == null or animation.get_track_count() == 0:
        status_label.text = "That sequence selection has no compatible animation tracks."
        return
    var preview_key := StringName(key_text)
    if dynamic_anim_lib.has_animation(preview_key):
        dynamic_anim_lib.remove_animation(preview_key)
    animation.loop_mode = Animation.LOOP_LINEAR
    dynamic_anim_lib.add_animation(preview_key, animation)
    animation_player.speed_scale = playback_speed
    animation_player.play(StringName("dyn/%s" % preview_key), 0.06)
    is_playing = true
    trim_preview_active = false
    assembly_preview_active = true
    assembly_preview_window_start = window.x
    assembly_preview_window_end = window.y
    status_label.text = message

func _preview_sequence_selection() -> void:
    var combined := _build_assembly_animation(assembly_segments)
    if combined == null:
        status_label.text = "Add at least one cut before playing an output selection."
        return
    var selection := _current_sequence_selection()
    var start_time := clampf(selection.x, 0.0, combined.length)
    var end_time := clampf(selection.y, start_time, combined.length)
    if end_time - start_time < 1.0 / EDITOR_FPS:
        status_label.text = "Drag across at least one output frame first."
        return
    var selected_animation: Animation = clip_editor.trim(combined, start_time, end_time, EDITOR_FPS)
    _play_sequence_animation(selected_animation, "sequence_range_preview", "Playing only output frames %d–%d." % [roundi(start_time * EDITOR_FPS), roundi(end_time * EDITOR_FPS)], Vector2(start_time, end_time))

func _preview_selected_sequence_cut() -> void:
    if selected_sequence_segment_index < 0 or selected_sequence_segment_index >= assembly_segments.size():
        status_label.text = "Click one cut on the output timeline first."
        return
    var segment: Dictionary = assembly_segments[selected_sequence_segment_index]
    var one_cut: Array[Dictionary] = [segment.duplicate(true)]
    var cut_animation := _build_assembly_animation(one_cut)
    var output_range := Vector2.ZERO
    if sequence_timeline and sequence_timeline.has_method("get_segment_output_range"):
        output_range = sequence_timeline.get_segment_output_range(selected_sequence_segment_index)
    _play_sequence_animation(cut_animation, "sequence_cut_preview", "Playing selected cut: %s." % str(segment.get("display", "animation")), output_range)

func _save_sequence_selection() -> void:
    var combined := _build_assembly_animation(assembly_segments)
    if combined == null:
        status_label.text = "Add at least one cut before saving a selection."
        return
    var selection := _current_sequence_selection()
    var start_time := clampf(selection.x, 0.0, combined.length)
    var end_time := clampf(selection.y, start_time, combined.length)
    if end_time - start_time < 1.0 / EDITOR_FPS:
        status_label.text = "Drag across at least one output frame before saving."
        return
    var selected_animation: Animation = clip_editor.trim(combined, start_time, end_time, EDITOR_FPS)
    if sequence_selection_name_input and authored_name_input:
        authored_name_input.text = sequence_selection_name_input.text.strip_edges()
    var baked_selection: Array[Dictionary] = [{
        "animation": selected_animation,
        "start": 0.0,
        "end": selected_animation.length,
        "display": "sequence selection",
        "path": "",
    }]
    _save_authored_segments(baked_selection, "sequence_selection", false)

func _insert_current_clip_as_transition(before_selected: bool) -> void:
    if selected_sequence_segment_index < 0 or selected_sequence_segment_index >= assembly_segments.size():
        status_label.text = "Click the cut that needs a transition first."
        return
    var transition := _current_trim_segment()
    if transition.is_empty():
        status_label.text = "Choose and trim the transition animation on the source timeline first."
        return
    var target_index := selected_sequence_segment_index
    var target_layer := str(assembly_segments[target_index].get("layer", "full_body"))
    transition["layer"] = target_layer
    if before_selected:
        transition["transition_frames"] = 6 if _lane_has_segment_before(target_index, target_layer) else 0
        assembly_segments.insert(target_index, transition)
        assembly_segments[target_index + 1]["transition_frames"] = 6
        selected_sequence_segment_index = target_index
    else:
        transition["transition_frames"] = 6
        assembly_segments.insert(target_index + 1, transition)
        selected_sequence_segment_index = target_index + 1
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()
    status_label.text = "Attached %s %s the selected cut with a 6-frame crossfade." % [
        str(transition.get("display", "transition")),
        "before" if before_selected else "after",
    ]

func _lane_has_segment_before(index: int, layer: String) -> bool:
    for candidate in range(index):
        if str(assembly_segments[candidate].get("layer", "full_body")) == layer:
            return true
    return false

func _cycle_selected_sequence_blend() -> void:
    if selected_sequence_segment_index < 0 or selected_sequence_segment_index >= assembly_segments.size():
        status_label.text = "Click a cut before changing its connector blend."
        return
    _cycle_segment_blend(selected_sequence_segment_index)
    status_label.text = "Selected connector now blends for %d frames." % int(assembly_segments[selected_sequence_segment_index].get("transition_frames", 0))

func _build_assembly_animation(segments: Array[Dictionary]) -> Animation:
    var region_segments: Dictionary = {}
    for region in ["full_body", "lower_body", "torso", "left_arm", "right_arm", "head"]:
        region_segments[region] = []
    for segment in segments:
        var region := str(segment.get("layer", "full_body"))
        if not region_segments.has(region):
            region = "full_body"
        (region_segments[region] as Array).append(segment)
    var region_sources: Dictionary = {}
    for region in region_segments.keys():
        var lane: Array = region_segments[region]
        if lane.is_empty():
            continue
        var typed_lane: Array[Dictionary] = []
        for lane_segment in lane:
            typed_lane.append(lane_segment)
        var lane_animation: Animation = clip_editor.combine(typed_lane, EDITOR_FPS)
        if lane_animation != null and lane_animation.get_track_count() > 0:
            region_sources[region] = lane_animation
    if region_sources.is_empty():
        return null
    if region_sources.size() == 1 and region_sources.has("full_body"):
        return region_sources["full_body"] as Animation
    return layer_composer.compose(region_sources, EDITOR_FPS)

func _snapped_current_time() -> float:
    if animation_player == null:
        return 0.0
    return roundf(animation_player.current_animation_position * EDITOR_FPS) / EDITOR_FPS

func _selected_animation() -> Animation:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return null
    return _get_current_animation(filtered_entries[clip_index])

func _toggle_sequence_region(region: String) -> void:
    if region == "full_body":
        selected_sequence_regions.clear()
        selected_sequence_regions["full_body"] = true
    else:
        selected_sequence_regions.erase("full_body")
        if selected_sequence_regions.has(region):
            selected_sequence_regions.erase(region)
        else:
            selected_sequence_regions[region] = true
        if selected_sequence_regions.is_empty():
            selected_sequence_regions["full_body"] = true
    _refresh_sequence_region_buttons()

func _refresh_sequence_region_buttons() -> void:
    for region_key in sequence_region_buttons.keys():
        var region_button: Button = sequence_region_buttons[region_key]
        var selected := selected_sequence_regions.has(region_key)
        region_button.button_pressed = selected
        region_button.add_theme_color_override(
            "font_color",
            Color(0.3, 1.0, 0.55) if selected else Color(0.7, 0.74, 0.8)
        )
    if sequence_region_summary_label:
        var names: String = " + ".join(_selected_sequence_region_keys())
        sequence_region_summary_label.text = "CARRYING: %s" % names.replace("full_body", "full body").replace("lower_body", "legs").replace("_", " ").to_upper()

func _selected_sequence_region_keys() -> Array[String]:
    var selected: Array[String] = []
    for region in ["full_body", "lower_body", "torso", "left_arm", "right_arm", "head"]:
        if selected_sequence_regions.has(region):
            selected.append(region)
    if selected.is_empty():
        selected.append("full_body")
    return selected

func _add_current_trim_segment() -> void:
    var segment := _current_trim_segment()
    if segment.is_empty():
        status_label.text = "A trim segment must contain at least one frame."
        return
    var selected_regions := _selected_sequence_region_keys()
    for region in selected_regions:
        var region_segment := segment.duplicate(true)
        region_segment["layer"] = region
        region_segment["transition_frames"] = 3 if _lane_has_segments(region) else 0
        assembly_segments.append(region_segment)
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()
    status_label.text = "Added %s frames %d–%d to %s." % [
        str(segment.get("display", "Animation clip")),
        roundi(float(segment.get("start", 0.0)) * EDITOR_FPS),
        roundi(float(segment.get("end", 0.0)) * EDITOR_FPS),
        ", ".join(selected_regions).replace("lower_body", "legs").replace("_", " "),
    ]

func _current_trim_segment() -> Dictionary:
    var animation := _selected_animation()
    if animation == null or filtered_entries.is_empty():
        return {}
    var safe_in := clampf(trim_in_seconds, 0.0, animation.length)
    var safe_out := clampf(trim_out_seconds, safe_in, animation.length)
    if safe_out - safe_in < 1.0 / EDITOR_FPS:
        return {}
    var entry: Dictionary = filtered_entries[clip_index]
    return {
        "animation": animation.duplicate(true),
        "start": safe_in,
        "end": safe_out,
        "display": str(entry.get("display", "Animation clip")),
        "path": str(entry.get("path", "")),
    }

func _lane_has_segments(layer: String) -> bool:
    for segment in assembly_segments:
        if str(segment.get("layer", "full_body")) == layer:
            return true
    return false

func _on_clip_dropped_to_assembly(entry: Dictionary) -> void:
    _append_entry_full_range(entry)

func _on_clip_dropped_to_sequence(entry: Dictionary) -> void:
    # Dragging the clip currently being trimmed respects its cyan source
    # range. A different clip has no source selection yet, so append its full
    # range. Both routes honor the highlighted destination body regions.
    if not filtered_entries.is_empty() and clip_index >= 0 and clip_index < filtered_entries.size():
        var current_entry: Dictionary = filtered_entries[clip_index]
        if _entry_identity(current_entry) == _entry_identity(entry):
            _add_current_trim_segment()
            return
    _append_entry_full_range(entry)

func _add_selected_full_clip() -> void:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return
    _append_entry_full_range(filtered_entries[clip_index])

func _append_entry_full_range(entry: Dictionary) -> void:
    match str(entry.get("type", "")):
        "FBX":
            _load_and_retarget_fbx(entry)
        "AUTHORED":
            _load_authored_animation(entry)
    var animation := _get_current_animation(entry)
    if animation == null:
        status_label.text = "That clip could not be loaded into the assembly."
        return
    var full_segment := {
        "animation": animation.duplicate(true),
        "start": 0.0,
        "end": animation.length,
        "display": str(entry.get("display", "Animation clip")),
        "path": str(entry.get("path", "")),
    }
    for region in _selected_sequence_region_keys():
        var region_segment := full_segment.duplicate(true)
        region_segment["layer"] = region
        region_segment["transition_frames"] = 3 if _lane_has_segments(region) else 0
        assembly_segments.append(region_segment)
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()
    if assembly_drop_label:
        assembly_drop_label.text = "✓ ADDED: %s" % str(entry.get("display", "Animation clip"))
        assembly_drop_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
    status_label.text = "Appended the complete %s clip to the assembly." % str(entry.get("display", "Animation clip"))

func _on_assembly_drop_visual_state_changed(state: String) -> void:
    if assembly_drop_label == null:
        return
    match state:
        "hover":
            assembly_drop_label.text = "RELEASE NOW → add this clip"
            assembly_drop_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
        "ready":
            assembly_drop_label.text = "VALID DESTINATION → drag clip here"
            assembly_drop_label.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
        _:
            assembly_drop_label.text = "DROP CLIP HERE → append full clip"
            assembly_drop_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.84))

func _undo_assembly_segment() -> void:
    if not assembly_segments.is_empty():
        assembly_segments.pop_back()
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()

func _clear_assembly_segments() -> void:
    assembly_segments.clear()
    selected_sequence_segment_index = -1
    sequence_selection_start = 0.0
    sequence_selection_end = 0.0
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()

func _remove_assembly_segment(index: int) -> void:
    if index < 0 or index >= assembly_segments.size():
        return
    assembly_segments.remove_at(index)
    if selected_sequence_segment_index == index:
        selected_sequence_segment_index = -1
    elif selected_sequence_segment_index > index:
        selected_sequence_segment_index -= 1
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()

func _move_assembly_segment(index: int, direction: int) -> void:
    var target := index + direction
    if index < 0 or index >= assembly_segments.size() or target < 0 or target >= assembly_segments.size():
        return
    var segment := assembly_segments[index]
    assembly_segments[index] = assembly_segments[target]
    assembly_segments[target] = segment
    _refresh_assembly_cards()

func _move_assembly_segment_in_lane(index: int, direction: int) -> void:
    if index < 0 or index >= assembly_segments.size():
        return
    var layer := str(assembly_segments[index].get("layer", "full_body"))
    var lane_indices: Array[int] = []
    for candidate in range(assembly_segments.size()):
        if str(assembly_segments[candidate].get("layer", "full_body")) == layer:
            lane_indices.append(candidate)
    var lane_position := lane_indices.find(index)
    var target_position := lane_position + direction
    if lane_position < 0 or target_position < 0 or target_position >= lane_indices.size():
        return
    var target_index := lane_indices[target_position]
    var segment := assembly_segments[index]
    assembly_segments[index] = assembly_segments[target_index]
    assembly_segments[target_index] = segment
    _refresh_assembly_cards()

func _cycle_segment_blend(index: int) -> void:
    if index < 0 or index >= assembly_segments.size():
        return
    var current := int(assembly_segments[index].get("transition_frames", 0))
    assembly_segments[index]["transition_frames"] = 3 if current == 0 else (6 if current == 3 else 0)
    _refresh_assembly_cards()
    _refresh_frame_editor_labels()

func _refresh_assembly_cards() -> void:
    if assembly_cards_vbox == null:
        return
    if sequence_timeline:
        sequence_timeline.set_segments(assembly_segments)
    _refresh_sequence_drawer_visibility()
    assembly_card_panels.clear()
    for child in assembly_cards_vbox.get_children():
        child.queue_free()
    if assembly_segments.is_empty():
        var empty_label := Label.new()
        empty_label.text = "No cuts yet — make your first selection above."
        empty_label.add_theme_color_override("font_color", Color(0.62, 0.69, 0.76))
        assembly_cards_vbox.add_child(empty_label)
        return
    var lane_labels := {
        "full_body": "FULL",
        "lower_body": "LEGS",
        "torso": "TORSO",
        "left_arm": "L ARM",
        "right_arm": "R ARM",
        "head": "HEAD",
    }
    for layer in lane_labels.keys():
        var lane_indices: Array[int] = []
        for index in range(assembly_segments.size()):
            if str(assembly_segments[index].get("layer", "full_body")) == layer:
                lane_indices.append(index)
        if lane_indices.is_empty():
            continue
        var lane_row := HBoxContainer.new()
        lane_row.name = "%sSequenceLane" % String(layer).to_pascal_case()
        lane_row.custom_minimum_size.y = 92.0
        var lane_name := Label.new()
        lane_name.text = lane_labels[layer]
        lane_name.custom_minimum_size.x = 58.0
        lane_name.add_theme_color_override("font_color", Color(0.4, 1.0, 0.65))
        lane_row.add_child(lane_name)
        var lane_scroll := ScrollContainer.new()
        lane_scroll.custom_minimum_size = Vector2(300.0, 90.0)
        lane_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        lane_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
        lane_row.add_child(lane_scroll)
        var lane_strip := HBoxContainer.new()
        lane_strip.add_theme_constant_override("separation", 4)
        lane_scroll.add_child(lane_strip)
        for lane_position in range(lane_indices.size()):
            var index := lane_indices[lane_position]
            var segment: Dictionary = assembly_segments[index]
            var start_frame := roundi(float(segment.get("start", 0.0)) * EDITOR_FPS)
            var end_frame := roundi(float(segment.get("end", 0.0)) * EDITOR_FPS)
            var frame_count := maxi(1, end_frame - start_frame)
            var card_panel := PanelContainer.new()
            card_panel.name = "SequenceCut%d" % (index + 1)
            card_panel.custom_minimum_size = Vector2(clampf(float(frame_count) * 5.0, 126.0, 230.0), 82.0)
            var card_style := StyleBoxFlat.new()
            card_style.bg_color = Color(0.08, 0.24, 0.31, 0.96)
            card_style.border_color = Color(0.18, 0.85, 1.0, 0.9)
            card_style.set_border_width_all(2)
            card_style.set_corner_radius_all(5)
            card_panel.add_theme_stylebox_override("panel", card_style)
            assembly_card_panels[index] = card_panel
            var card_box := VBoxContainer.new()
            card_panel.add_child(card_box)
            var card := Label.new()
            card.text = "%s\nframes %d → %d  •  %.2fs" % [
                str(segment.get("display", "Animation clip")),
                start_frame,
                end_frame,
                float(frame_count) / EDITOR_FPS,
            ]
            card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
            card.add_theme_color_override("font_color", Color(0.75, 0.93, 1.0))
            card_box.add_child(card)
            var card_actions := HBoxContainer.new()
            card_box.add_child(card_actions)
            var earlier_button := Button.new()
            earlier_button.text = "←"
            earlier_button.disabled = lane_position == 0
            earlier_button.pressed.connect(_move_assembly_segment_in_lane.bind(index, -1))
            card_actions.add_child(earlier_button)
            var later_button := Button.new()
            later_button.text = "→"
            later_button.disabled = lane_position == lane_indices.size() - 1
            later_button.pressed.connect(_move_assembly_segment_in_lane.bind(index, 1))
            card_actions.add_child(later_button)
            var blend_button := Button.new()
            var transition_frames := int(segment.get("transition_frames", 0))
            blend_button.text = "Blend %df" % transition_frames
            blend_button.tooltip_text = "Cycle this connector: cut, quick 3-frame blend, or smooth 6-frame blend."
            blend_button.disabled = lane_position == 0
            blend_button.pressed.connect(_cycle_segment_blend.bind(index))
            card_actions.add_child(blend_button)
            var remove_button := Button.new()
            remove_button.text = "×"
            remove_button.tooltip_text = "Remove this cut from the sequence."
            remove_button.pressed.connect(_remove_assembly_segment.bind(index))
            card_actions.add_child(remove_button)
            lane_strip.add_child(card_panel)
        assembly_cards_vbox.add_child(lane_row)

func _update_assembly_playhead() -> void:
    var has_current_animation := (
        animation_player != null
        and not String(animation_player.current_animation).is_empty()
        and animation_player.has_animation(animation_player.current_animation)
    )
    var current_position := animation_player.current_animation_position if has_current_animation else 0.0
    var current_length := animation_player.current_animation_length if has_current_animation else 1.0
    if sequence_timeline:
        sequence_timeline.set_playback(
            current_position,
            current_length,
            assembly_preview_active and has_current_animation and animation_player.is_playing(),
            assembly_preview_window_start,
            assembly_preview_window_end
        )
    for index in assembly_card_panels.keys():
        var panel: PanelContainer = assembly_card_panels[index]
        if not is_instance_valid(panel):
            continue
        var style := panel.get_theme_stylebox("panel") as StyleBoxFlat
        if style:
            style.bg_color = Color(0.08, 0.24, 0.31, 0.96)
            style.border_color = Color(0.18, 0.85, 1.0, 0.9)
    if not assembly_preview_active or not has_current_animation or not animation_player.is_playing():
        return
    var preview_length := maxf(animation_player.current_animation_length, 1.0 / EDITOR_FPS)
    var normalized_playhead := clampf(animation_player.current_animation_position / preview_length, 0.0, 1.0)
    for layer in ["full_body", "lower_body", "torso", "left_arm", "right_arm", "head"]:
        var lane_indices: Array[int] = []
        var lane_duration := 0.0
        for index in range(assembly_segments.size()):
            var segment: Dictionary = assembly_segments[index]
            if str(segment.get("layer", "full_body")) != layer:
                continue
            lane_indices.append(index)
            lane_duration += maxf(0.0, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
        if lane_indices.is_empty() or lane_duration <= 0.0:
            continue
        var lane_playhead := normalized_playhead * lane_duration
        var cursor := 0.0
        for lane_position in range(lane_indices.size()):
            var index := lane_indices[lane_position]
            var segment: Dictionary = assembly_segments[index]
            var segment_duration := maxf(0.0, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
            var is_active := lane_playhead >= cursor and (
                lane_playhead < cursor + segment_duration
                or lane_position == lane_indices.size() - 1
            )
            if is_active and assembly_card_panels.has(index):
                var panel: PanelContainer = assembly_card_panels[index]
                if is_instance_valid(panel):
                    var active_style := panel.get_theme_stylebox("panel") as StyleBoxFlat
                    if active_style:
                        active_style.bg_color = Color(0.18, 0.45, 0.25, 0.98)
                        active_style.border_color = Color(0.55, 1.0, 0.35, 1.0)
                break
            cursor += segment_duration

func _nudge_trim_in(frame_delta: int) -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    var step := 1.0 / EDITOR_FPS
    trim_in_seconds = clampf(trim_in_seconds + float(frame_delta) * step, 0.0, trim_out_seconds - step)
    trim_in_seconds = roundf(trim_in_seconds * EDITOR_FPS) / EDITOR_FPS
    animation_player.seek(trim_in_seconds, true)
    _refresh_frame_editor_labels()

func _nudge_trim_out(frame_delta: int) -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    var step := 1.0 / EDITOR_FPS
    trim_out_seconds = clampf(trim_out_seconds + float(frame_delta) * step, trim_in_seconds + step, animation.length)
    trim_out_seconds = roundf(trim_out_seconds * EDITOR_FPS) / EDITOR_FPS
    animation_player.seek(trim_out_seconds, true)
    _refresh_frame_editor_labels()

func _refresh_frame_editor_labels() -> void:
    if trim_label:
        trim_label.text = "KEEP FRAMES %d → %d  •  %d frames total" % [
            roundi(trim_in_seconds * EDITOR_FPS),
            roundi(trim_out_seconds * EDITOR_FPS),
            maxi(0, roundi((trim_out_seconds - trim_in_seconds) * EDITOR_FPS)),
        ]
    if assembly_label:
        var lane_durations: Dictionary = {}
        for segment in assembly_segments:
            var lane := str(segment.get("layer", "full_body"))
            lane_durations[lane] = float(lane_durations.get(lane, 0.0)) + maxf(
                0.0,
                float(segment.get("end", 0.0)) - float(segment.get("start", 0.0))
            )
        var duration := 0.0
        for lane_duration in lane_durations.values():
            duration = maxf(duration, float(lane_duration))
        assembly_label.text = "SEQUENCE: %d cut%s • %d lane%s • %d frames" % [
            assembly_segments.size(),
            "" if assembly_segments.size() == 1 else "s",
            lane_durations.size(),
            "" if lane_durations.size() == 1 else "s",
            roundi(duration * EDITOR_FPS),
        ]

func _save_authored_assembly() -> void:
    var segments: Array[Dictionary] = []
    for queued_segment in assembly_segments:
        segments.append(queued_segment.duplicate(true))
    if segments.is_empty():
        var current_segment := _current_trim_segment()
        if not current_segment.is_empty():
            segments.append(current_segment)
    if segments.is_empty():
        return
    var layered_sequence := _build_assembly_animation(segments)
    if layered_sequence == null or layered_sequence.get_track_count() == 0:
        status_label.text = "The stacked sequence did not contain compatible bone tracks."
        return
    var baked_sequence: Array[Dictionary] = [{
        "animation": layered_sequence,
        "start": 0.0,
        "end": layered_sequence.length,
        "display": "layered sequence",
        "path": "",
    }]
    _save_authored_segments(baked_sequence, "combined_clip", true)

func _save_current_trim() -> void:
    var segment := _current_trim_segment()
    if segment.is_empty():
        status_label.text = "Choose a trim range of at least one frame before saving."
        return
    var fallback_name := _safe_authored_name(str(segment.get("display", "animation"))) + "_trim"
    var selected_segments: Array[Dictionary] = []
    for region in _selected_sequence_region_keys():
        var region_segment := segment.duplicate(true)
        region_segment["layer"] = region
        selected_segments.append(region_segment)
    var masked_cut := _build_assembly_animation(selected_segments)
    if masked_cut == null or masked_cut.get_track_count() == 0:
        status_label.text = "The selected body regions did not contain compatible tracks."
        return
    var baked_cut: Array[Dictionary] = [{
        "animation": masked_cut,
        "start": 0.0,
        "end": masked_cut.length,
        "display": str(segment.get("display", "animation")),
        "path": str(segment.get("path", "")),
    }]
    _save_authored_segments(baked_cut, fallback_name, false)

func _save_authored_segments(segments: Array[Dictionary], fallback_name: String, clear_assembly: bool) -> void:
    var combined: Animation = clip_editor.combine(segments, EDITOR_FPS)
    if combined == null or combined.get_track_count() == 0:
        status_label.text = "The selected segments did not contain compatible animation tracks."
        return
    var requested_name := authored_name_input.text.strip_edges() if authored_name_input else ""
    if requested_name.is_empty():
        requested_name = fallback_name
    var safe_name := _safe_authored_name(requested_name)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUTHORED_ANIMATION_DIR))
    var resource_path := "%s/%s.tres" % [AUTHORED_ANIMATION_DIR, safe_name]
    var suffix := 2
    while FileAccess.file_exists(resource_path):
        resource_path = "%s/%s_%d.tres" % [AUTHORED_ANIMATION_DIR, safe_name, suffix]
        suffix += 1
    combined.resource_name = resource_path.get_file().get_basename()
    combined.loop_mode = Animation.LOOP_NONE
    var save_error := ResourceSaver.save(combined, resource_path)
    if save_error != OK:
        status_label.text = "Could not save authored clip (%s)." % error_string(save_error)
        return
    var authored_key := "authored_" + resource_path.get_file().get_basename().to_snake_case()
    if dynamic_anim_lib.has_animation(authored_key):
        dynamic_anim_lib.remove_animation(authored_key)
    dynamic_anim_lib.add_animation(authored_key, combined)
    var new_entry := {
        "name": StringName("dyn/" + authored_key),
        "key": authored_key,
        "display": "[Authored] " + combined.resource_name.capitalize(),
        "type": "AUTHORED",
        "path": resource_path,
    }
    all_clip_entries.append(new_entry)
    authored_animation_files[combined.resource_name.capitalize()] = resource_path
    if clear_assembly:
        assembly_segments.clear()
        _refresh_assembly_cards()
    _filter_category("AUTHORED")
    for index in range(filtered_entries.size()):
        if str(filtered_entries[index].get("path", "")) == resource_path:
            clip_index = index
            break
    _play_selected()
    _refresh_clip_list_ui()
    _refresh_frame_editor_labels()
    status_label.text = "Saved %s (%d frames). It is now available under AUTHORED." % [
        resource_path,
        roundi(combined.length * EDITOR_FPS),
    ]

func _safe_authored_name(value: String) -> String:
    var safe := value.to_snake_case().validate_filename().strip_edges()
    if safe.is_empty():
        return "authored_clip"
    return safe

func _toggle_skin() -> void:
    var next_idx := (int(current_skin) + 1) % 5
    _load_skin(next_idx as SkinType)

func _skin_name(skin: SkinType) -> String:
    match skin:
        SkinType.PS1_GAS_MASK_SOLDIER: return "PS1 Gas Mask Trooper (Rigged & Skinned)"
        SkinType.MILITARY_TACTICAL_OPERATOR: return "Military Tactical Suit (Game-Ready 87-Bone)"
        SkinType.SOCOM_OPERATOR: return "SOCOM Operator (Authored Rig)"
        SkinType.MIXAMO_MANNEQUIN: return "Mixamo Beta Skin"
        SkinType.PS1_NIGHT_VISION_SEAL: return "PS1 Night Vision SEAL"
    return "Unknown"

func _cycle_weapon() -> void:
    var next_idx := (int(current_weapon) + 1) % 5
    current_weapon = next_idx as WeaponType
    _rebuild_weapon_socket()
    weapon_selector_button.text = "Weapon (G): " + _weapon_name(current_weapon)

func _toggle_gun_lab() -> void:
    gun_lab_visible = not gun_lab_visible
    gun_lab_panel.visible = gun_lab_visible

func _reset_camera() -> void:
    orbit_yaw = -0.48
    orbit_pitch = -0.10
    orbit_distance = 3.6
    target_height = 0.95

func _should_loop(clip_name: String) -> bool:
    var s := clip_name.to_lower()
    if "jump loop" in s:
        return true
    for one_shot_word in [
        "start", "stop", "turn", "transition", "death", "hit", "reload",
        "throw", "fire", "shoot", "dive", "roll", "jump", "land", "climb",
        "idle to", "to walk", "kneel to", "to kneel", "to prone", "to standing", "to crouch",
    ]:
        if one_shot_word in s:
            return false
    return (
        "idle" in s
        or "walk" in s
        or "run" in s
        or "strafe" in s
        or "crawl" in s
        or "prone forward" in s
        or "backward in prone" in s
    )

func _filter_category(cat: String) -> void:
    current_category = cat
    filtered_entries.clear()
    for entry in all_clip_entries:
        var name_str: String = str(entry["display"]).to_lower()
        match cat:
            "ALL":
                filtered_entries.append(entry)
            "RIFLE LOCO":
                if ("walk" in name_str or "run" in name_str or "sprint" in name_str or "strafe" in name_str) and not "crouch" in name_str and not "pistol" in name_str:
                    filtered_entries.append(entry)
            "PISTOL":
                if "pistol" in name_str:
                    filtered_entries.append(entry)
            "CROUCH & PRONE":
                if "crouch" in name_str or "prone" in name_str or "kneel" in name_str or "crawl" in name_str:
                    filtered_entries.append(entry)
            "COMBAT & FIRE":
                if "fire" in name_str or "aim" in name_str or "reload" in name_str or "shoot" in name_str or "throw" in name_str:
                    filtered_entries.append(entry)
            "AGILITY & DIVE":
                if "dive" in name_str or "roll" in name_str or "jump" in name_str or "land" in name_str:
                    filtered_entries.append(entry)
            "DEATH & HIT":
                if "death" in name_str or "hit" in name_str or "die" in name_str:
                    filtered_entries.append(entry)
            "AUTHORED":
                if entry["type"] in ["BAKED", "AUTHORED"]:
                    filtered_entries.append(entry)

    if filtered_entries.is_empty():
        filtered_entries = all_clip_entries.duplicate()
    clip_index = 0
    _play_selected()
    _refresh_clip_list_ui()

func _assign_to_slot(slot_name: String) -> void:
    if filtered_entries.is_empty():
        return
    _assign_entry_to_slot(filtered_entries[clip_index], slot_name)

func _assign_entry_to_slot(entry: Dictionary, slot_name: String) -> void:
    var resource_path := str(entry.get("path", ""))
    if resource_path.is_empty():
        status_label.text = "This baked preview cannot be assigned; choose an FBX clip."
        return
    if not state_slots.has(slot_name):
        status_label.text = "Unknown gameplay slot: %s" % slot_name
        return
    state_slots[slot_name] = resource_path
    _save_state_slots()
    _refresh_slot_ui()
    status_label.text = "%s is now bound to %s." % [str(entry.get("display", resource_path.get_file())), slot_name]

func _refresh_slot_ui() -> void:
    if slot_panel_label == null:
        return
    var mapped := 0
    for path in state_slots.values():
        if not str(path).is_empty():
            mapped += 1
    var selected_path := str(state_slots.get(selected_state_slot, ""))
    var clip_label := "UNASSIGNED" if selected_path.is_empty() else selected_path.get_file()
    slot_panel_label.text = (
        "GAMEPLAY STATE: %s\n↓ logical slot\nCLIP: %s\n%d/%d basic slots mapped"
        % [selected_state_slot, clip_label, mapped, state_slots.size()]
    )
    if slot_drop_label:
        slot_drop_label.text = "DROP CLIP HERE\n→ %s" % selected_state_slot
    _refresh_runtime_state_tree()
    _refresh_slot_suggestion()

func _load_state_slots() -> void:
    state_slots.clear()
    if FileAccess.file_exists(ANIMATION_MAP_PATH):
        var file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.READ)
        var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
        if parsed is Dictionary:
            var clips: Variant = (parsed as Dictionary).get("clips", {})
            if clips is Dictionary:
                for slot_name in (clips as Dictionary).keys():
                    state_slots[str(slot_name)] = str((clips as Dictionary)[slot_name])
    state_slot_keys.clear()
    for slot_name in state_slots.keys():
        state_slot_keys.append(str(slot_name))
    state_slot_keys.sort()
    if not state_slot_keys.is_empty():
        selected_state_slot = state_slot_keys[0]

func _save_state_slots() -> void:
    var config: Dictionary = {}
    if FileAccess.file_exists(ANIMATION_MAP_PATH):
        var existing_file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.READ)
        var parsed: Variant = JSON.parse_string(existing_file.get_as_text()) if existing_file else null
        if parsed is Dictionary:
            config = (parsed as Dictionary).duplicate(true)
    if config.is_empty():
        config = {
            "version": 1,
            "description": "Gameplay state -> editable Mixamo FBX mapping.",
        }
    config = _merge_state_slots_into_config(config)
    var file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.WRITE)
    if file == null:
        status_label.text = "Could not save the runtime animation map."
        return
    file.store_string(JSON.stringify(config, "  "))

func _save_animation_work_and_play_latest() -> void:
    # One project-level commit: animation routes, authored body recipe, review
    # shortlist, and the authoritative Gunsmith rig selection all survive the
    # scene change into the integration playground.
    _save_state_slots()
    _save_highlighted_shortlist()
    _save_layer_recipe()
    var weapon_rig_path := _save_linked_gunsmith_profile()
    if status_label:
        status_label.text = (
            "Project saved with weapon rig %s. Opening the latest playground…" % weapon_rig_path.get_file()
            if not weapon_rig_path.is_empty()
            else "Animation work saved. No compatible Gunsmith profile is available for this preview weapon."
        )
    if weapon_rig_path.is_empty():
        return
    call_deferred("_open_latest_playground")

func _save_linked_gunsmith_profile() -> String:
    var rig_config_path := ""
    var weapon_id := ""
    if FileAccess.file_exists(WEAPON_LOADOUT_PATH):
        var existing_file := FileAccess.open(WEAPON_LOADOUT_PATH, FileAccess.READ)
        var existing_value: Variant = JSON.parse_string(existing_file.get_as_text()) if existing_file else null
        if existing_value is Dictionary:
            rig_config_path = String((existing_value as Dictionary).get("rig_config", ""))
            weapon_id = String((existing_value as Dictionary).get("primary_weapon_id", ""))
    if rig_config_path.is_empty() or not FileAccess.file_exists(rig_config_path):
        var fallback_ids := {
            WeaponType.M4A1_SOPMOD: "assaultrifle_1",
            WeaponType.MP5_SD: "submachinegun_1",
            WeaponType.AK_47: "ak-47",
        }
        weapon_id = String(fallback_ids.get(current_weapon, ""))
        rig_config_path = "res://config/weapons/%s.json" % weapon_id if not weapon_id.is_empty() else ""
    if rig_config_path.is_empty() or not FileAccess.file_exists(rig_config_path):
        return ""
    var config_file := FileAccess.open(rig_config_path, FileAccess.READ)
    var config_value: Variant = JSON.parse_string(config_file.get_as_text()) if config_file else null
    if not config_value is Dictionary:
        return ""
    var config: Dictionary = config_value as Dictionary
    weapon_id = String(config.get("weapon_id", weapon_id))
    var loadout_file := FileAccess.open(WEAPON_LOADOUT_PATH, FileAccess.WRITE)
    if loadout_file == null:
        return ""
    loadout_file.store_string(JSON.stringify({
        "schema_version": 1,
        "primary_weapon_id": weapon_id,
        "rig_config": rig_config_path,
        "saved_by": "animation_workshop",
    }, "  "))
    return rig_config_path

func _open_latest_playground() -> void:
    var change_error := get_tree().change_scene_to_file("res://main.tscn")
    if change_error != OK and status_label:
        status_label.text = "Could not open the latest playground (%s)." % error_string(change_error)

func _merge_state_slots_into_config(existing_config: Dictionary) -> Dictionary:
    var merged := existing_config.duplicate(true)
    merged["clips"] = state_slots.duplicate(true)
    return merged

func _weapon_name(wep: WeaponType) -> String:
    match wep:
        WeaponType.M4A1_SOPMOD: return "M4A1 SOPMOD Rifle"
        WeaponType.MP5_SD: return "MP5-SD Submachine Gun"
        WeaponType.COMBAT_PISTOL: return "9mm Combat Pistol"
        WeaponType.AK_47: return "AK-47 Assault Rifle"
        WeaponType.NONE: return "Holstered (None)"
    return "Unknown"

func _rebuild_weapon_socket() -> void:
    if socket_attachment:
        socket_attachment.queue_free()
        socket_attachment = null
        weapon_node = null
        left_hand_marker = null

    if current_weapon == WeaponType.NONE:
        return

    if skeleton == null:
        if model_root:
            weapon_node = Node3D.new()
            weapon_node.name = "AttachedWeapon"
            weapon_node.position = Vector3(-0.20, 0.95, 0.22)
            weapon_node.rotation_degrees = Vector3(0, 0, 0)
            var weapon_mesh := _create_weapon_mesh(current_weapon)
            weapon_node.add_child(weapon_mesh)
            model_root.add_child(weapon_node)
        return

    # Attach weapon directly to the active Right Hand bone
    var target_bone := "mixamorig_RightHand"
    if skeleton.find_bone("mixamorig_RightHand") != -1:
        target_bone = "mixamorig_RightHand"
    elif skeleton.find_bone("mixamorig:RightHand") != -1:
        target_bone = "mixamorig:RightHand"
    elif skeleton.find_bone("Hand.R.001") != -1:
        target_bone = "Hand.R.001"
    elif skeleton.find_bone("HandWrist.R") != -1:
        target_bone = "HandWrist.R"

    socket_attachment = BoneAttachment3D.new()
    socket_attachment.name = "WeaponSocketAttachment"
    socket_attachment.bone_name = target_bone
    skeleton.add_child(socket_attachment)

    weapon_node = Node3D.new()
    weapon_node.name = "AttachedWeapon"
    _sync_weapon_node_transform()

    # Build the 3D Weapon Mesh
    var weapon_mesh := _create_weapon_mesh(current_weapon)
    weapon_node.add_child(weapon_mesh)

    # Left Hand Handguard Target Socket
    left_hand_marker = Marker3D.new()
    left_hand_marker.name = "LeftHandGripTarget"
    left_hand_marker.position = left_handguard_pos
    weapon_node.add_child(left_hand_marker)

    socket_attachment.add_child(weapon_node)

func _sync_weapon_node_transform() -> void:
    if weapon_node == null:
        return
    var factor := (1.0 / model_root.scale.x) if (model_root and model_root.scale.x > 1.5) else 1.0
    weapon_node.position = right_grip_pos * factor
    weapon_node.rotation_degrees = right_grip_rot
    weapon_node.scale = Vector3.ONE * factor * weapon_scale_factor

func _hide_baked_rifle_parts(node: Node) -> void:
    if node is MeshInstance3D and ("Rifle" in node.name or "weapon" in node.name.to_lower()):
        node.visible = false
    for child in node.get_children():
        _hide_baked_rifle_parts(child)

func _create_weapon_mesh(wep: WeaponType) -> Node3D:
    var root := Node3D.new()
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color(0.12, 0.13, 0.15)
    metal.metallic = 0.85
    metal.roughness = 0.35

    var dark_plastic := StandardMaterial3D.new()
    dark_plastic.albedo_color = Color(0.08, 0.09, 0.10)
    dark_plastic.roughness = 0.8

    var wood := StandardMaterial3D.new()
    wood.albedo_color = Color(0.40, 0.22, 0.12)
    wood.roughness = 0.65

    match wep:
        WeaponType.M4A1_SOPMOD:
            left_handguard_pos = Vector3(0.0, 0.02, 0.28)
            _add_box(root, Vector3(0.045, 0.09, 0.28), Vector3(0, 0.02, 0.05), dark_plastic)
            _add_box(root, Vector3(0.038, 0.08, 0.18), Vector3(0, 0.04, -0.16), dark_plastic)
            _add_box(root, Vector3(0.042, 0.055, 0.24), Vector3(0, 0.035, 0.28), dark_plastic)
            _add_cylinder(root, 0.012, 0.20, Vector3(0, 0.035, 0.46), metal)
            _add_cylinder(root, 0.018, 0.12, Vector3(0, 0.035, 0.58), metal)
            _add_box(root, Vector3(0.026, 0.16, 0.075), Vector3(0, -0.08, 0.12), metal, Vector3(14, 0, 0))
            _add_box(root, Vector3(0.034, 0.045, 0.08), Vector3(0, 0.095, 0.10), dark_plastic)
            _add_box(root, Vector3(0.032, 0.11, 0.045), Vector3(0, -0.06, 0.0), dark_plastic, Vector3(-20, 0, 0))

        WeaponType.MP5_SD:
            left_handguard_pos = Vector3(0.0, 0.015, 0.22)
            _add_box(root, Vector3(0.04, 0.07, 0.24), Vector3(0, 0.02, 0.06), metal)
            _add_cylinder(root, 0.026, 0.28, Vector3(0, 0.025, 0.28), dark_plastic)
            _add_box(root, Vector3(0.022, 0.15, 0.045), Vector3(0, -0.07, 0.12), metal, Vector3(18, 0, 0))
            _add_box(root, Vector3(0.03, 0.10, 0.04), Vector3(0, -0.05, 0.0), dark_plastic, Vector3(-22, 0, 0))
            _add_box(root, Vector3(0.035, 0.06, 0.14), Vector3(0, 0.03, -0.12), metal)

        WeaponType.COMBAT_PISTOL:
            left_handguard_pos = Vector3(-0.025, -0.01, 0.02)
            _add_box(root, Vector3(0.03, 0.038, 0.19), Vector3(0, 0.04, 0.06), metal)
            _add_box(root, Vector3(0.028, 0.11, 0.048), Vector3(0, -0.03, 0.02), dark_plastic, Vector3(-16, 0, 0))
            _add_box(root, Vector3(0.015, 0.035, 0.04), Vector3(0, -0.01, 0.07), dark_plastic)

        WeaponType.AK_47:
            left_handguard_pos = Vector3(0.0, 0.05, 0.32)
            var ak_pivot := Node3D.new()
            ak_pivot.name = "AK47_Pivot"
            
            var ak_inst := AK47_FBX_SCENE.instantiate() as Node3D
            # Scale from FBX units (29.2 units long) to real rifle length (0.88m)
            ak_inst.scale = Vector3.ONE * 0.030
            # Offset so the pistol grip / trigger is right at (0,0,0)
            ak_inst.position = Vector3(0.0, 0.02, -0.05)
            ak_inst.rotation_degrees = Vector3(0, 180, 0)
            
            # Apply texture
            var ak_mat := StandardMaterial3D.new()
            ak_mat.albedo_texture = AK47_TEXTURE
            for child in ak_inst.get_children():
                if child is MeshInstance3D:
                    child.material_override = ak_mat
                for grandchild in child.get_children():
                    if grandchild is MeshInstance3D:
                        grandchild.material_override = ak_mat
            ak_pivot.add_child(ak_inst)
            root.add_child(ak_pivot)

    return root

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
    var mi := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mi.mesh = box
    mi.position = pos
    mi.rotation_degrees = rot_deg
    mi.material_override = mat
    parent.add_child(mi)

func _add_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
    var mi := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = radius
    cyl.bottom_radius = radius
    cyl.height = height
    mi.mesh = cyl
    mi.position = pos
    mi.rotation_degrees = Vector3(90, 0, 0)
    mi.material_override = mat
    parent.add_child(mi)

func _build_stage() -> void:
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color(0.035, 0.045, 0.06)
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color(0.55, 0.60, 0.68)
    settings.ambient_light_energy = 0.95
    environment.environment = settings
    add_child(environment)

    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(24.0, 24.0)
    floor_mesh.mesh = plane
    var floor_mat := StandardMaterial3D.new()
    floor_mat.albedo_color = Color(0.11, 0.13, 0.15)
    floor_mat.roughness = 0.85
    floor_mesh.material_override = floor_mat
    add_child(floor_mesh)

    # Pose contacts use the same physics query path as gameplay IK. The mesh
    # remains visual-only; this thin collider makes floor snapping measurable.
    var floor_body := StaticBody3D.new()
    floor_body.name = "PoseContactFloor"
    var floor_shape_node := CollisionShape3D.new()
    var floor_shape := BoxShape3D.new()
    floor_shape.size = Vector3(24.0, 0.1, 24.0)
    floor_shape_node.shape = floor_shape
    floor_shape_node.position.y = -0.05
    floor_body.add_child(floor_shape_node)
    add_child(floor_body)

    var wall_body := StaticBody3D.new()
    wall_body.name = "PoseContactWall"
    wall_body.position = Vector3(1.35, 1.25, 0.0)
    var wall_shape_node := CollisionShape3D.new()
    var wall_shape := BoxShape3D.new()
    wall_shape.size = Vector3(0.1, 2.5, 3.0)
    wall_shape_node.shape = wall_shape
    wall_body.add_child(wall_shape_node)
    add_child(wall_body)
    pose_contact_wall_visual = MeshInstance3D.new()
    pose_contact_wall_visual.name = "PoseContactWallGuide"
    var wall_mesh := BoxMesh.new()
    wall_mesh.size = wall_shape.size
    pose_contact_wall_visual.mesh = wall_mesh
    var wall_material := StandardMaterial3D.new()
    wall_material.albedo_color = Color(0.15, 0.75, 0.9, 0.16)
    wall_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    pose_contact_wall_visual.material_override = wall_material
    pose_contact_wall_visual.visible = false
    wall_body.add_child(pose_contact_wall_visual)

    var key_light := DirectionalLight3D.new()
    key_light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
    key_light.light_energy = 1.8
    key_light.shadow_enabled = true
    add_child(key_light)

    var rim_light := DirectionalLight3D.new()
    rim_light.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
    rim_light.light_energy = 1.2
    rim_light.light_color = Color(0.65, 0.75, 0.95)
    add_child(rim_light)

    camera = Camera3D.new()
    camera.fov = 48.0
    add_child(camera)
    _update_camera()

func _update_camera() -> void:
    if camera == null:
        return
    var target_pos := Vector3(0.0, target_height, 0.0)
    var horizontal := cos(orbit_pitch) * orbit_distance
    camera.position = target_pos + Vector3(
        sin(orbit_yaw) * horizontal,
        sin(orbit_pitch) * orbit_distance + 0.4,
        cos(orbit_yaw) * horizontal
    )
    camera.look_at(target_pos, Vector3.UP)

func _build_ui() -> void:
    overlay = CanvasLayer.new()
    add_child(overlay)

    # All editor docks live under a full-viewport Control so their anchors
    # follow the game window. The old fixed pixel layout was easy to clip at
    # laptop resolutions and made the bottom tools unreachable.
    editor_ui_root = Control.new()
    editor_ui_root.name = "AnimationEditorWorkspace"
    editor_ui_root.set_anchors_preset(Control.PRESET_TOP_LEFT)
    editor_ui_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
    overlay.add_child(editor_ui_root)
    _fit_editor_ui_to_window()
    get_viewport().size_changed.connect(_fit_editor_ui_to_window)
    var ui_root := editor_ui_root

    # Keep the studio in three non-overlapping bands: header, workspace, and
    # timeline. The old right dock started at the top edge and rendered its
    # instructions underneath the clip header.
    var workspace_margin := 14.0
    var header_bottom := 112.0
    var workspace_top := 124.0
    var timeline_top := -292.0
    var workspace_bottom := -306.0
    var left_dock_width := 344.0
    var right_dock_width := 446.0

    # Top Header Panel
    var top_panel := PanelContainer.new()
    top_panel.name = "StudioHeaderPanel"
    top_panel.set_anchor(SIDE_RIGHT, 1.0)
    top_panel.offset_left = workspace_margin
    top_panel.offset_top = workspace_margin
    top_panel.offset_right = -workspace_margin
    top_panel.offset_bottom = header_bottom
    ui_root.add_child(top_panel)

    var top_vbox := VBoxContainer.new()
    top_panel.add_child(top_vbox)

    status_label = Label.new()
    status_label.add_theme_font_size_override("font_size", 16)
    status_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
    status_label.tooltip_text = "Current skin, weapon, and animation clip"
    top_vbox.add_child(status_label)

    # One category picker replaces eight wide tabs. Filtering remains just as
    # powerful, but the first screen now reads like a simple clip browser.
    category_container = HBoxContainer.new()
    top_vbox.add_child(category_container)
    var categories := ["ALL", "RIFLE LOCO", "PISTOL", "CROUCH & PRONE", "COMBAT & FIRE", "AGILITY & DIVE", "DEATH & HIT", "AUTHORED"]
    var category_label := Label.new()
    category_label.text = "Show"
    category_label.custom_minimum_size.x = 48.0
    category_container.add_child(category_label)
    var category_picker := OptionButton.new()
    category_picker.custom_minimum_size = Vector2(260.0, 42.0)
    category_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    for category_name in categories:
        category_picker.add_item(category_name)
    category_picker.item_selected.connect(func(index: int):
        _filter_category(category_picker.get_item_text(index))
    )
    category_container.add_child(category_picker)

    # Left Sidebar: Clips Scroll List with Real-time Search
    clip_library_panel = PanelContainer.new()
    clip_library_panel.name = "ClipLibraryPanel"
    clip_library_panel.set_anchor(SIDE_BOTTOM, 1.0)
    clip_library_panel.offset_left = workspace_margin
    clip_library_panel.offset_top = workspace_top
    clip_library_panel.offset_right = left_dock_width
    clip_library_panel.offset_bottom = workspace_bottom
    ui_root.add_child(clip_library_panel)

    var left_vbox := VBoxContainer.new()
    clip_library_panel.add_child(left_vbox)

    var search_bar := LineEdit.new()
    search_bar.placeholder_text = "🔍 Search 341 Mixamo animations..."
    search_bar.text_changed.connect(_on_search_changed)
    left_vbox.add_child(search_bar)

    clip_scroll = ScrollContainer.new()
    clip_scroll.custom_minimum_size = Vector2(300, 240)
    clip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left_vbox.add_child(clip_scroll)

    clip_list_vbox = VBoxContainer.new()
    clip_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    clip_scroll.add_child(clip_list_vbox)

    # Right Sidebar: persistent gameplay state -> clip mapping.
    runtime_map_panel = PanelContainer.new()
    runtime_map_panel.name = "RuntimeMapPanel"
    runtime_map_panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
    runtime_map_panel.offset_left = -right_dock_width
    runtime_map_panel.offset_top = workspace_top
    runtime_map_panel.offset_right = -workspace_margin
    runtime_map_panel.offset_bottom = workspace_bottom
    ui_root.add_child(runtime_map_panel)

    var right_scroll := ScrollContainer.new()
    right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    runtime_map_panel.add_child(right_scroll)

    var slot_vbox := VBoxContainer.new()
    slot_vbox.custom_minimum_size = Vector2(386, 0)
    slot_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_scroll.add_child(slot_vbox)

    var slot_title := Label.new()
    slot_title.text = "ANIMATION WORKSHOP"
    slot_title.add_theme_font_size_override("font_size", 14)
    slot_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    slot_vbox.add_child(slot_title)

    var mode_help := Label.new()
    mode_help.text = "Choose one job. Everything else stays out of the way."
    mode_help.add_theme_font_size_override("font_size", 12)
    mode_help.add_theme_color_override("font_color", Color(0.72, 0.78, 0.86))
    slot_vbox.add_child(mode_help)

    var mode_grid := GridContainer.new()
    mode_grid.columns = 4
    slot_vbox.add_child(mode_grid)
    for mode_name in ["Preview", "Pose", "Build", "Routes"]:
        var mode_button := Button.new()
        mode_button.name = "%sModeButton" % mode_name
        mode_button.text = mode_name
        mode_button.toggle_mode = true
        mode_button.custom_minimum_size = Vector2(90.0, 42.0)
        mode_button.pressed.connect(_show_editor_page.bind(mode_name))
        mode_grid.add_child(mode_button)
        editor_mode_buttons[mode_name] = mode_button

    var preview_page := VBoxContainer.new()
    var pose_page := VBoxContainer.new()
    var trim_page := VBoxContainer.new()
    var layers_page := VBoxContainer.new()
    var routes_page := VBoxContainer.new()
    editor_pages = {
        "Preview": preview_page,
        "Pose": pose_page,
        "Build": trim_page,
        "Routes": routes_page,
    }
    for page_name in editor_pages.keys():
        var editor_page: Control = editor_pages[page_name]
        editor_page.name = "%sPage" % page_name
        editor_page.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        slot_vbox.add_child(editor_page)

    var preview_title := Label.new()
    preview_title.text = "1. Pick a clip  →  2. Press play  →  3. Inspect the body"
    preview_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    preview_title.add_theme_font_size_override("font_size", 15)
    preview_page.add_child(preview_title)
    var preview_help := Label.new()
    preview_help.text = "Use Build to select exact frames, highlight body regions, and assemble them on stacked timeline lanes."
    preview_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    preview_help.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    preview_page.add_child(preview_help)

    var pose_title := Label.new()
    pose_title.text = "POSE AN IMPORTED FRAME"
    pose_title.add_theme_font_size_override("font_size", 17)
    pose_title.add_theme_color_override("font_color", Color(0.35, 1.0, 0.62))
    pose_page.add_child(pose_title)
    var pose_help := Label.new()
    pose_help.text = "Click and drag a colored body node like the Gunsmith control point. Limbs move through their shoulder/elbow or hip/knee chain, so bones cannot stretch. Use Rotate Joint for local bend/turn; sliders are only fine tuning."
    pose_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    pose_help.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    pose_page.add_child(pose_help)

    pose_selected_bone_label = Label.new()
    pose_selected_bone_label.text = "SELECTED JOINT: click a cyan skeleton node"
    pose_selected_bone_label.add_theme_color_override("font_color", Color.WHITE)
    pose_page.add_child(pose_selected_bone_label)

    var direct_tool_row := HBoxContainer.new()
    pose_page.add_child(direct_tool_row)
    var move_joint_button := _touch_button("MOVE NODE")
    move_joint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    move_joint_button.tooltip_text = "Drag a node. Limbs solve through upstream joints; only the hips translate."
    move_joint_button.pressed.connect(_set_pose_edit_mode.bind(&"MOVE"))
    direct_tool_row.add_child(move_joint_button)
    var rotate_joint_button := _touch_button("ROTATE JOINT")
    rotate_joint_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    rotate_joint_button.tooltip_text = "Drag left/right to turn and up/down to bend within human joint limits."
    rotate_joint_button.pressed.connect(_set_pose_edit_mode.bind(&"ROTATE"))
    direct_tool_row.add_child(rotate_joint_button)

    var move_title := Label.new()
    move_title.text = "ROOT POSITION (hips only)"
    move_title.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
    pose_page.add_child(move_title)
    _add_pose_slider(pose_page, "Left / Right", "move_x", -0.25, 0.25, 0.005)
    _add_pose_slider(pose_page, "Up / Down", "move_y", -0.25, 0.25, 0.005)
    _add_pose_slider(pose_page, "Forward / Back", "move_z", -0.25, 0.25, 0.005)

    var rotate_title := Label.new()
    rotate_title.text = "FINE ROTATION"
    rotate_title.add_theme_color_override("font_color", Color(1.0, 0.78, 0.3))
    pose_page.add_child(rotate_title)
    _add_pose_slider(pose_page, "Bend", "rot_x", -90.0, 90.0, 1.0)
    _add_pose_slider(pose_page, "Turn", "rot_y", -120.0, 120.0, 1.0)
    _add_pose_slider(pose_page, "Twist", "rot_z", -90.0, 90.0, 1.0)

    var contact_row := HBoxContainer.new()
    pose_page.add_child(contact_row)
    var floor_contact_button := Button.new()
    floor_contact_button.text = "Snap Joint to Floor"
    floor_contact_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    floor_contact_button.pressed.connect(_snap_selected_bone_to_collision.bind("floor"))
    contact_row.add_child(floor_contact_button)
    var wall_contact_button := Button.new()
    wall_contact_button.text = "Snap Joint to Wall"
    wall_contact_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    wall_contact_button.pressed.connect(_snap_selected_bone_to_collision.bind("wall"))
    contact_row.add_child(wall_contact_button)
    pose_contact_summary_label = Label.new()
    pose_contact_summary_label.text = "CONTACTS: none"
    pose_contact_summary_label.add_theme_font_size_override("font_size", 11)
    pose_page.add_child(pose_contact_summary_label)

    pose_keyframe_label = Label.new()
    pose_keyframe_label.text = "KEY POSES: none yet"
    pose_keyframe_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    pose_keyframe_label.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    pose_page.add_child(pose_keyframe_label)
    var pose_capture_row := GridContainer.new()
    pose_capture_row.columns = 2
    pose_page.add_child(pose_capture_row)
    var capture_pose_button := _touch_button("Capture Pose at This Frame")
    capture_pose_button.pressed.connect(_capture_pose_keyframe)
    pose_capture_row.add_child(capture_pose_button)
    var duplicate_pose_button := _touch_button("Duplicate to Next Frame")
    duplicate_pose_button.pressed.connect(_duplicate_latest_pose)
    pose_capture_row.add_child(duplicate_pose_button)
    var copy_pose_button := _touch_button("Copy Latest Pose")
    copy_pose_button.pressed.connect(_copy_latest_pose)
    pose_capture_row.add_child(copy_pose_button)
    var paste_pose_button := _touch_button("Paste at Current Frame")
    paste_pose_button.pressed.connect(_paste_pose_to_current_frame)
    pose_capture_row.add_child(paste_pose_button)

    pose_interpolation_button = _touch_button("Between Poses: SMOOTH")
    pose_interpolation_button.pressed.connect(_toggle_pose_interpolation)
    pose_page.add_child(pose_interpolation_button)
    var pose_preview_button := _touch_button("▶ Play Captured Poses")
    pose_preview_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    pose_preview_button.pressed.connect(_preview_pose_strip)
    pose_page.add_child(pose_preview_button)
    pose_name_input = LineEdit.new()
    pose_name_input.placeholder_text = "Name the new stop-motion animation"
    pose_name_input.custom_minimum_size.y = 42.0
    pose_page.add_child(pose_name_input)
    var pose_save_row := HBoxContainer.new()
    pose_page.add_child(pose_save_row)
    var save_pose_button := _touch_button("Save as New Animation")
    save_pose_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_pose_button.pressed.connect(_save_pose_strip)
    pose_save_row.add_child(save_pose_button)
    var clear_pose_button := _touch_button("Clear Key Poses")
    clear_pose_button.pressed.connect(_clear_pose_strip)
    pose_save_row.add_child(clear_pose_button)

    # Touch-first, weapon-neutral body composer. The five targets form a
    # simple T-pose diagram and accept clips directly from the left library.
    var simple_title := Label.new()
    simple_title.text = "MIX BODY PARTS"
    simple_title.add_theme_font_size_override("font_size", 15)
    simple_title.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    layers_page.add_child(simple_title)
    var layers_help := Label.new()
    layers_help.text = "Combine the legs from one clip with the torso, arms, or head from others."
    layers_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layers_help.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    layers_page.add_child(layers_help)

    var t_pose_map := VBoxContainer.new()
    t_pose_map.add_theme_constant_override("separation", 4)
    layers_page.add_child(t_pose_map)

    var head_center := CenterContainer.new()
    head_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    head_center.add_child(_create_body_layer_target("head", "HEAD", Vector2(116.0, 58.0)))
    t_pose_map.add_child(head_center)

    var upper_body_row := HBoxContainer.new()
    upper_body_row.add_theme_constant_override("separation", 4)
    upper_body_row.add_child(_create_body_layer_target("left_arm", "LEFT ARM", Vector2(112.0, 82.0)))
    upper_body_row.add_child(_create_body_layer_target("torso", "TORSO", Vector2(130.0, 92.0)))
    upper_body_row.add_child(_create_body_layer_target("right_arm", "RIGHT ARM", Vector2(112.0, 82.0)))
    t_pose_map.add_child(upper_body_row)

    var legs_center := CenterContainer.new()
    legs_center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    legs_center.add_child(_create_body_layer_target("lower_body", "LEGS", Vector2(150.0, 72.0)))
    t_pose_map.add_child(legs_center)

    var tap_fallback_help := Label.new()
    tap_fallback_help.text = "No drag? Pick a part, then use the selected clip:"
    tap_fallback_help.add_theme_font_size_override("font_size", 11)
    tap_fallback_help.add_theme_color_override("font_color", Color(0.68, 0.74, 0.82))
    layers_page.add_child(tap_fallback_help)
    var layer_row := HBoxContainer.new()
    layers_page.add_child(layer_row)
    var layer_selector := OptionButton.new()
    layer_selector.custom_minimum_size = Vector2(190.0, 44.0)
    var layer_keys := ["lower_body", "torso", "left_arm", "right_arm", "head"]
    for layer_key in layer_keys:
        layer_selector.add_item(String(layer_key).replace("_", " ").capitalize())
        layer_selector.set_item_metadata(layer_selector.item_count - 1, layer_key)
    layer_selector.item_selected.connect(func(index: int):
        selected_layer_key = String(layer_selector.get_item_metadata(index))
    )
    layer_row.add_child(layer_selector)
    var use_clip_button := Button.new()
    use_clip_button.text = "Use Clip for Part"
    use_clip_button.custom_minimum_size.y = 44.0
    use_clip_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    use_clip_button.pressed.connect(_assign_selected_clip_to_layer)
    layer_row.add_child(use_clip_button)

    layer_recipe_summary = Label.new()
    layer_recipe_summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    layer_recipe_summary.add_theme_font_size_override("font_size", 11)
    layer_recipe_summary.add_theme_color_override("font_color", Color(0.72, 0.93, 1.0))
    layers_page.add_child(layer_recipe_summary)
    _refresh_layer_recipe_summary()

    var bake_row := HBoxContainer.new()
    layers_page.add_child(bake_row)
    layer_recipe_name_input = LineEdit.new()
    layer_recipe_name_input.placeholder_text = "Name this animation"
    layer_recipe_name_input.text = "custom_body_animation"
    layer_recipe_name_input.custom_minimum_size = Vector2(180.0, 44.0)
    layer_recipe_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bake_row.add_child(layer_recipe_name_input)
    var bake_button := Button.new()
    bake_button.text = "Build New Animation"
    bake_button.custom_minimum_size.y = 44.0
    bake_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bake_button.tooltip_text = "Bake the five selected bone regions into one reusable authored animation."
    bake_button.pressed.connect(_build_layer_composite)
    bake_row.add_child(bake_button)

    var simple_play_button := Button.new()
    simple_play_button.text = "▶ Save Everything + Play Latest"
    simple_play_button.custom_minimum_size.y = 48.0
    simple_play_button.add_theme_font_size_override("font_size", 15)
    simple_play_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    simple_play_button.pressed.connect(_save_animation_work_and_play_latest)
    layers_page.add_child(simple_play_button)

    var routes_help := Label.new()
    routes_help.text = "ADVANCED ROUTES\nConnect clips to gameplay states. Beginners can ignore this page."
    routes_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    routes_help.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    routes_page.add_child(routes_help)

    var graph_scroll := ScrollContainer.new()
    graph_scroll.custom_minimum_size = Vector2(0, 250)
    graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    routes_page.add_child(graph_scroll)

    runtime_route_graph = ROUTE_GRAPH.new()
    runtime_route_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    runtime_route_graph.state_selected.connect(_on_route_state_selected)
    runtime_route_graph.clip_dropped_on_state.connect(_on_clip_dropped_on_tree_state)
    runtime_route_graph.candidate_selected.connect(_on_graph_candidate_selected)
    graph_scroll.add_child(runtime_route_graph)

    state_slot_selector = OptionButton.new()
    for slot_name in state_slot_keys:
        state_slot_selector.add_item(slot_name)
    state_slot_selector.item_selected.connect(func(index: int):
        selected_state_slot = state_slot_keys[index]
        _refresh_slot_ui()
    )
    routes_page.add_child(state_slot_selector)

    var btn_row := HBoxContainer.new()
    routes_page.add_child(btn_row)

    var assign_button := Button.new()
    assign_button.text = "Bind Selected Clip ➔"
    assign_button.pressed.connect(func(): _assign_to_slot(selected_state_slot))
    btn_row.add_child(assign_button)

    var auto_map_button := Button.new()
    auto_map_button.text = "⚡ Auto-Build Known States"
    auto_map_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
    auto_map_button.pressed.connect(_auto_map_all_slots)
    btn_row.add_child(auto_map_button)

    var highlight_help := Label.new()
    highlight_help.text = "★ Highlight clips on the left. Your shortlist is saved for Codex; purple proposals appear here."
    highlight_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    highlight_help.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    routes_page.add_child(highlight_help)

    slot_suggestion_label = Label.new()
    slot_suggestion_label.add_theme_font_size_override("font_size", 11)
    slot_suggestion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    routes_page.add_child(slot_suggestion_label)

    var use_suggestion_button := Button.new()
    use_suggestion_button.text = "Approve Selected Suggestion"
    use_suggestion_button.pressed.connect(_assign_selected_to_suggested_slot)
    routes_page.add_child(use_suggestion_button)

    var clear_highlights_button := Button.new()
    clear_highlights_button.text = "Clear Highlighted Clips"
    clear_highlights_button.pressed.connect(_clear_highlighted_clips)
    routes_page.add_child(clear_highlights_button)

    slot_panel_label = Label.new()
    slot_panel_label.add_theme_font_size_override("font_size", 11)
    routes_page.add_child(slot_panel_label)
    _refresh_slot_ui()

    # Active Limb Drag HUD Label
    limb_hud_label = Label.new()
    limb_hud_label.position = Vector2(330, 120)
    limb_hud_label.add_theme_font_size_override("font_size", 15)
    limb_hud_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    limb_hud_label.visible = false
    overlay.add_child(limb_hud_label)

    # Gun Lab Calibration Panel (Interactive Weapon Studio)
    gun_lab_panel = PanelContainer.new()
    gun_lab_panel.position = Vector2(880, 232)
    gun_lab_panel.size = Vector2(384, 368)
    gun_lab_panel.visible = false # Animation tree owns the default workspace; L opens weapon tools.
    overlay.add_child(gun_lab_panel)

    var gun_vbox := VBoxContainer.new()
    gun_lab_panel.add_child(gun_vbox)
    
    var gun_title := Label.new()
    gun_title.text = "[ WEAPON ALIGNMENT STUDIO (L) ]"
    gun_title.add_theme_font_size_override("font_size", 14)
    gun_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
    gun_vbox.add_child(gun_title)

    # Quick Rotation Presets
    var quick_rot_hbox := HBoxContainer.new()
    gun_vbox.add_child(quick_rot_hbox)
    
    var btn_roll90 := Button.new()
    btn_roll90.text = "↻ Roll 90°"
    btn_roll90.pressed.connect(func():
        right_grip_rot.z = wrapf(right_grip_rot.z + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_roll90)

    var btn_pitch90 := Button.new()
    btn_pitch90.text = "↻ Pitch 90°"
    btn_pitch90.pressed.connect(func():
        right_grip_rot.x = wrapf(right_grip_rot.x + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_pitch90)

    var btn_yaw90 := Button.new()
    btn_yaw90.text = "↻ Yaw 90°"
    btn_yaw90.pressed.connect(func():
        right_grip_rot.y = wrapf(right_grip_rot.y + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_yaw90)

    # Sliders for Position & Rotation & Scale
    _add_gun_slider(gun_vbox, "Pos X (Left/Right)", "pos_x", -0.3, 0.3, right_grip_pos.x, 0.005, func(val):
        right_grip_pos.x = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pos Y (Up/Down)", "pos_y", -0.3, 0.3, right_grip_pos.y, 0.005, func(val):
        right_grip_pos.y = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pos Z (Fwd/Back)", "pos_z", -0.3, 0.3, right_grip_pos.z, 0.005, func(val):
        right_grip_pos.z = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pitch X (Up/Down)", "rot_x", -180.0, 180.0, right_grip_rot.x, 1.0, func(val):
        right_grip_rot.x = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Yaw Y (Turn)", "rot_y", -180.0, 180.0, right_grip_rot.y, 1.0, func(val):
        right_grip_rot.y = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Roll Z (Tilt)", "rot_z", -180.0, 180.0, right_grip_rot.z, 1.0, func(val):
        right_grip_rot.z = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Gun Scale", "scale", 0.2, 3.0, weapon_scale_factor, 0.05, func(val):
        weapon_scale_factor = val
        _sync_weapon_node_transform()
    )

    # Action Buttons: Print Config & Reset
    var action_hbox := HBoxContainer.new()
    gun_vbox.add_child(action_hbox)
    
    var print_btn := Button.new()
    print_btn.text = "📋 Print Transform Config"
    print_btn.pressed.connect(_print_weapon_config)
    action_hbox.add_child(print_btn)

    var reset_btn := Button.new()
    reset_btn.text = "↺ Reset"
    reset_btn.pressed.connect(func():
        right_grip_pos = Vector3(-0.02, 0.08, 0.05)
        right_grip_rot = Vector3(-90.0, 180.0, 0.0)
        weapon_scale_factor = 1.0
        _update_gun_sliders_and_mesh()
    )
    action_hbox.add_child(reset_btn)

    # Bottom Toolbar / Timeline
    frame_editor_dock = PanelContainer.new()
    frame_editor_dock.name = "FrameEditorDock"
    frame_editor_dock.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
    frame_editor_dock.offset_left = workspace_margin
    frame_editor_dock.offset_top = timeline_top
    frame_editor_dock.offset_right = -workspace_margin
    frame_editor_dock.offset_bottom = -workspace_margin
    ui_root.add_child(frame_editor_dock)

    var bot_vbox := VBoxContainer.new()
    frame_editor_dock.add_child(bot_vbox)

    var slider_hbox := HBoxContainer.new()
    bot_vbox.add_child(slider_hbox)

    var play_btn := Button.new()
    play_btn.text = " ▶ / ❚❚ "
    play_btn.pressed.connect(_toggle_play_pause)
    slider_hbox.add_child(play_btn)

    var previous_frame_button := Button.new()
    previous_frame_button.text = "◀ Frame"
    previous_frame_button.pressed.connect(func(): _step_animation_frame(-1))
    slider_hbox.add_child(previous_frame_button)

    var next_frame_button := Button.new()
    next_frame_button.text = "Frame ▶"
    next_frame_button.pressed.connect(func(): _step_animation_frame(1))
    slider_hbox.add_child(next_frame_button)

    var timeline_stack := VBoxContainer.new()
    timeline_stack.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider_hbox.add_child(timeline_stack)

    timeline_slider = HSlider.new()
    timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    timeline_slider.value_changed.connect(func(val): 
        if animation_player and filtered_entries.size() > 0:
            animation_player.seek(val, true)
            if range_selector:
                range_selector.set_playhead(val)
            if not animation_player.is_playing():
                _capture_all_edit_bases_after_seek()
    )
    timeline_stack.add_child(timeline_slider)

    # Cut and joining happens on this large, persistent timeline. It replaces
    # the ordinary seek slider in that workspace so there is only one place to
    # look: drag the cyan range, then add it to the sequence.
    range_selector = RANGE_SELECTOR_SCRIPT.new()
    range_selector.name = "CutRangeTimeline"
    range_selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    range_selector.range_changed.connect(_on_range_selector_changed)
    range_selector.playhead_requested.connect(_on_range_playhead_requested)
    range_selector.visible = false
    timeline_stack.add_child(range_selector)

    time_label = Label.new()
    time_label.text = "Frame 0 / 0 • 0.0s / 0.0s"
    slider_hbox.add_child(time_label)

    sequence_timeline = SEQUENCE_TIMELINE_SCRIPT.new()
    sequence_timeline.name = "DestinationSequenceTimeline"
    sequence_timeline.visible = false
    sequence_timeline.tooltip_text = "Drag across output frames to select them, or click a cut to select it."
    sequence_timeline.clip_dropped.connect(_on_clip_dropped_to_sequence)
    sequence_timeline.selection_changed.connect(_on_sequence_selection_changed)
    sequence_timeline.segment_selected.connect(_on_sequence_segment_selected)
    sequence_timeline.set_segments(assembly_segments)
    bot_vbox.add_child(sequence_timeline)

    sequence_drawer_button = Button.new()
    sequence_drawer_button.text = "▲ OPEN OUTPUT EDITOR  •  0 CUTS"
    sequence_drawer_button.custom_minimum_size.y = 32.0
    sequence_drawer_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
    sequence_drawer_button.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
    sequence_drawer_button.pressed.connect(_toggle_sequence_drawer)
    bot_vbox.add_child(sequence_drawer_button)
    bot_vbox.move_child(sequence_drawer_button, sequence_timeline.get_index())

    sequence_action_controls = HBoxContainer.new()
    sequence_action_controls.visible = false
    bot_vbox.add_child(sequence_action_controls)
    var play_selected_range_button := Button.new()
    play_selected_range_button.text = "▶ PLAY DRAGGED FRAMES"
    play_selected_range_button.custom_minimum_size = Vector2(210.0, 38.0)
    play_selected_range_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    play_selected_range_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    play_selected_range_button.pressed.connect(_preview_sequence_selection)
    sequence_action_controls.add_child(play_selected_range_button)
    var play_selected_cut_button := Button.new()
    play_selected_cut_button.text = "▶ Play Selected Cut"
    play_selected_cut_button.pressed.connect(_preview_selected_sequence_cut)
    sequence_action_controls.add_child(play_selected_cut_button)
    var play_whole_sequence_button := Button.new()
    play_whole_sequence_button.text = "▶ Play Whole Sequence"
    play_whole_sequence_button.pressed.connect(_preview_assembly)
    sequence_action_controls.add_child(play_whole_sequence_button)
    sequence_selection_name_input = LineEdit.new()
    sequence_selection_name_input.placeholder_text = "name selected frames"
    sequence_selection_name_input.custom_minimum_size.x = 170.0
    sequence_action_controls.add_child(sequence_selection_name_input)
    var save_sequence_selection_button := Button.new()
    save_sequence_selection_button.text = "Save Dragged Frames as New"
    save_sequence_selection_button.pressed.connect(_save_sequence_selection)
    sequence_action_controls.add_child(save_sequence_selection_button)

    sequence_transition_controls = HBoxContainer.new()
    sequence_transition_controls.visible = false
    bot_vbox.add_child(sequence_transition_controls)
    var transition_help := Label.new()
    transition_help.text = "CONNECT SELECTED CUT USING CURRENT CYAN CLIP:"
    transition_help.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    transition_help.add_theme_color_override("font_color", Color(1.0, 0.82, 0.32))
    sequence_transition_controls.add_child(transition_help)
    var transition_before_button := Button.new()
    transition_before_button.text = "+ Transition Before"
    transition_before_button.pressed.connect(_insert_current_clip_as_transition.bind(true))
    sequence_transition_controls.add_child(transition_before_button)
    var transition_after_button := Button.new()
    transition_after_button.text = "+ Transition After"
    transition_after_button.pressed.connect(_insert_current_clip_as_transition.bind(false))
    sequence_transition_controls.add_child(transition_after_button)
    var cycle_selected_blend_button := Button.new()
    cycle_selected_blend_button.text = "Blend Selected: 0 / 3 / 6 frames"
    cycle_selected_blend_button.pressed.connect(_cycle_selected_sequence_blend)
    sequence_transition_controls.add_child(cycle_selected_blend_button)

    var trim_intro := Label.new()
    trim_intro.text = "BUILD A LAYERED SEQUENCE"
    trim_intro.add_theme_font_size_override("font_size", 17)
    trim_intro.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
    trim_page.add_child(trim_intro)
    var trim_instructions := Label.new()
    trim_instructions.text = "1. Pick an animation on the left.\n2. Drag across the frames to keep.\n3. Add that cut to the sequence below."
    trim_instructions.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    trim_page.add_child(trim_instructions)

    var body_mask_title := Label.new()
    body_mask_title.text = "HIGHLIGHT BODY PARTS TO KEEP"
    body_mask_title.add_theme_font_size_override("font_size", 14)
    body_mask_title.add_theme_color_override("font_color", Color(0.55, 1.0, 0.72))
    trim_page.add_child(body_mask_title)
    var body_mask_grid := GridContainer.new()
    body_mask_grid.columns = 3
    trim_page.add_child(body_mask_grid)
    var region_labels := {
        "full_body": "FULL BODY",
        "lower_body": "LEGS",
        "torso": "TORSO",
        "left_arm": "LEFT ARM",
        "right_arm": "RIGHT ARM",
        "head": "HEAD",
    }
    for region_key in region_labels.keys():
        var region_button := Button.new()
        region_button.name = "%sMaskButton" % String(region_key).to_pascal_case()
        region_button.text = region_labels[region_key]
        region_button.toggle_mode = true
        region_button.custom_minimum_size = Vector2(118.0, 40.0)
        region_button.tooltip_text = "Carry only this bone region from the selected frames."
        region_button.pressed.connect(_toggle_sequence_region.bind(String(region_key)))
        body_mask_grid.add_child(region_button)
        sequence_region_buttons[region_key] = region_button
    sequence_region_summary_label = Label.new()
    sequence_region_summary_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    sequence_region_summary_label.add_theme_color_override("font_color", Color(0.72, 0.95, 1.0))
    trim_page.add_child(sequence_region_summary_label)
    _refresh_sequence_region_buttons()

    trim_label = Label.new()
    trim_label.custom_minimum_size = Vector2(190, 30)
    trim_label.add_theme_font_size_override("font_size", 15)
    trim_label.add_theme_color_override("font_color", Color(1.0, 0.88, 0.35))
    trim_page.add_child(trim_label)

    var trim_action_row := HBoxContainer.new()
    trim_page.add_child(trim_action_row)

    trim_preview_button = Button.new()
    trim_preview_button.text = "▶ Play Frames To Keep"
    trim_preview_button.custom_minimum_size.y = 48.0
    trim_preview_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    trim_preview_button.tooltip_text = "Loop only the cyan range selected on the large timeline below."
    trim_preview_button.pressed.connect(_preview_trim_range)
    trim_action_row.add_child(trim_preview_button)

    var add_segment_button := Button.new()
    add_segment_button.text = "Add Highlighted Cut →"
    add_segment_button.custom_minimum_size.y = 46.0
    add_segment_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    add_segment_button.tooltip_text = "Append the selected frame range to the combined clip queue."
    add_segment_button.pressed.connect(_add_current_trim_segment)
    trim_action_row.add_child(add_segment_button)

    var save_trim_button := Button.new()
    save_trim_button.text = "Save Cut Alone"
    save_trim_button.custom_minimum_size.y = 46.0
    save_trim_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    save_trim_button.tooltip_text = "Save only this selected frame range as a new authored clip."
    save_trim_button.pressed.connect(_save_current_trim)
    trim_page.add_child(save_trim_button)

    var combine_intro := Label.new()
    combine_intro.text = "YOUR SEQUENCE"
    combine_intro.add_theme_font_size_override("font_size", 17)
    combine_intro.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    trim_page.add_child(combine_intro)
    var combine_help := Label.new()
    combine_help.text = "Each cut appears here in playback order. Choose another source clip and repeat to continue building."
    combine_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    trim_page.add_child(combine_help)

    var assembly_box := VBoxContainer.new()
    trim_page.add_child(assembly_box)

    assembly_cards_vbox = VBoxContainer.new()
    assembly_cards_vbox.name = "SequenceClipCards"
    assembly_box.add_child(assembly_cards_vbox)
    _refresh_assembly_cards()

    var play_sequence_button := Button.new()
    play_sequence_button.text = "▶ Play Stacked Sequence"
    play_sequence_button.custom_minimum_size.y = 48.0
    play_sequence_button.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    play_sequence_button.pressed.connect(_preview_assembly)
    assembly_box.add_child(play_sequence_button)

    var full_clip_help := Label.new()
    full_clip_help.text = "Optional: add a whole clip without cutting it"
    full_clip_help.add_theme_font_size_override("font_size", 11)
    full_clip_help.add_theme_color_override("font_color", Color(0.62, 0.69, 0.76))
    assembly_box.add_child(full_clip_help)

    assembly_drop_target = SLOT_DROP_TARGET.new()
    assembly_drop_target.name = "AssemblyClipDropTarget"
    assembly_drop_target.custom_minimum_size = Vector2(305, 28)
    assembly_drop_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    assembly_drop_target.tooltip_text = "Drag a clip from the left library here to append its complete frame range."
    assembly_drop_target.clip_dropped.connect(_on_clip_dropped_to_assembly)
    assembly_drop_target.drop_visual_state_changed.connect(_on_assembly_drop_visual_state_changed)
    assembly_box.add_child(assembly_drop_target)

    assembly_drop_label = Label.new()
    assembly_drop_label.text = "DROP CLIP HERE → append full clip"
    assembly_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    assembly_drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    assembly_drop_target.add_child(assembly_drop_label)

    var assembly_action_grid := GridContainer.new()
    assembly_action_grid.columns = 3
    assembly_box.add_child(assembly_action_grid)

    var add_full_clip_button := Button.new()
    add_full_clip_button.text = "+ Add Whole Clip"
    add_full_clip_button.custom_minimum_size.y = 44.0
    add_full_clip_button.tooltip_text = "No dragging required: append the selected library clip's complete frame range."
    add_full_clip_button.pressed.connect(_add_selected_full_clip)
    assembly_action_grid.add_child(add_full_clip_button)

    var undo_segment_button := Button.new()
    undo_segment_button.text = "Undo Last"
    undo_segment_button.custom_minimum_size.y = 44.0
    undo_segment_button.pressed.connect(_undo_assembly_segment)
    assembly_action_grid.add_child(undo_segment_button)

    var clear_segments_button := Button.new()
    clear_segments_button.text = "Clear"
    clear_segments_button.custom_minimum_size.y = 44.0
    clear_segments_button.pressed.connect(_clear_assembly_segments)
    assembly_action_grid.add_child(clear_segments_button)

    assembly_label = Label.new()
    assembly_label.custom_minimum_size = Vector2(190, 30)
    assembly_label.add_theme_font_size_override("font_size", 15)
    assembly_box.add_child(assembly_label)

    var assembly_save_row := HBoxContainer.new()
    assembly_box.add_child(assembly_save_row)

    authored_name_input = LineEdit.new()
    authored_name_input.placeholder_text = "Name your new animation"
    authored_name_input.custom_minimum_size = Vector2(180, 46)
    authored_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    assembly_save_row.add_child(authored_name_input)

    var save_assembly_button := Button.new()
    save_assembly_button.text = "Save Combined"
    save_assembly_button.custom_minimum_size.y = 46.0
    save_assembly_button.pressed.connect(_save_authored_assembly)
    assembly_save_row.add_child(save_assembly_button)

    var tools_title := Label.new()
    tools_title.text = "OPTIONAL PREVIEW TOOLS"
    tools_title.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    preview_page.add_child(tools_title)
    var btn_hbox := GridContainer.new()
    btn_hbox.columns = 2
    preview_page.add_child(btn_hbox)

    skin_button = Button.new()
    skin_button.text = "Switch Skin (Tab)"
    skin_button.custom_minimum_size.y = 44.0
    skin_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    skin_button.pressed.connect(_toggle_skin)
    btn_hbox.add_child(skin_button)

    weapon_selector_button = Button.new()
    weapon_selector_button.text = "Weapon (G): " + _weapon_name(current_weapon)
    weapon_selector_button.custom_minimum_size.y = 44.0
    weapon_selector_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    weapon_selector_button.pressed.connect(_cycle_weapon)
    btn_hbox.add_child(weapon_selector_button)

    bubbles_toggle_btn = Button.new()
    bubbles_toggle_btn.text = "Skeleton Chain (B): ON"
    bubbles_toggle_btn.custom_minimum_size.y = 44.0
    bubbles_toggle_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    bubbles_toggle_btn.pressed.connect(_toggle_bubbles)
    btn_hbox.add_child(bubbles_toggle_btn)

    pose_tool_button = Button.new()
    pose_tool_button.text = "Bone Tool (M): ROTATE"
    pose_tool_button.custom_minimum_size.y = 44.0
    pose_tool_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    pose_tool_button.tooltip_text = "Rotate: drag. Move: drag X/Y; hold Shift and drag vertically for depth."
    pose_tool_button.pressed.connect(_toggle_pose_edit_mode)
    btn_hbox.add_child(pose_tool_button)

    var reset_pose_btn := Button.new()
    reset_pose_btn.text = "Reset Pose (C)"
    reset_pose_btn.custom_minimum_size.y = 44.0
    reset_pose_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    reset_pose_btn.pressed.connect(_clear_bone_rot_offsets)
    btn_hbox.add_child(reset_pose_btn)

    var gun_lab_btn := Button.new()
    gun_lab_btn.text = "Two-Hand Engine (L)"
    gun_lab_btn.custom_minimum_size.y = 44.0
    gun_lab_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    gun_lab_btn.pressed.connect(_toggle_gun_lab)
    btn_hbox.add_child(gun_lab_btn)

    persistent_action_controls = HBoxContainer.new()
    bot_vbox.add_child(persistent_action_controls)

    var play_latest_btn := Button.new()
    play_latest_btn.text = "▶ Save + Play Latest"
    play_latest_btn.custom_minimum_size = Vector2(250.0, 42.0)
    play_latest_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    play_latest_btn.tooltip_text = "Save animation assignments and launch the canonical current gameplay scene."
    play_latest_btn.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
    play_latest_btn.pressed.connect(_save_animation_work_and_play_latest)
    persistent_action_controls.add_child(play_latest_btn)

    speed_button = Button.new()
    speed_button.text = "Speed: %.2fx" % playback_speed
    speed_button.custom_minimum_size = Vector2(115.0, 42.0)
    speed_button.pressed.connect(func():
        if is_equal_approx(playback_speed, 0.25): playback_speed = 0.5
        elif is_equal_approx(playback_speed, 0.5): playback_speed = 0.75
        elif is_equal_approx(playback_speed, 0.75): playback_speed = 1.0
        else: playback_speed = 0.25
        speed_button.text = "Speed: %.2fx" % playback_speed
        if animation_player:
            animation_player.speed_scale = playback_speed
    )
    persistent_action_controls.add_child(speed_button)

    var reset_cam_btn := Button.new()
    reset_cam_btn.text = "Reset View (R)"
    reset_cam_btn.custom_minimum_size = Vector2(130.0, 42.0)
    reset_cam_btn.pressed.connect(_reset_camera)
    persistent_action_controls.add_child(reset_cam_btn)

    _show_editor_page("Preview")

func _add_slider_control(parent: Control, label_text: String, min_val: float, max_val: float, default_val: float, callback: Callable) -> void:
    var hbox := HBoxContainer.new()
    parent.add_child(hbox)
    var lbl := Label.new()
    lbl.text = "%-12s" % label_text
    lbl.custom_minimum_size = Vector2(95, 0)
    hbox.add_child(lbl)
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = (max_val - min_val) / 200.0
    slider.value = default_val
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(callback)
    hbox.add_child(slider)

func _add_pose_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, step_val: float) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size.x = 108.0
    label.add_theme_font_size_override("font_size", 11)
    row.add_child(label)
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = step_val
    slider.value = 0.0
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    var value_label := Label.new()
    value_label.text = _pose_slider_value_text(key, 0.0)
    value_label.custom_minimum_size.x = 64.0
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value_label.add_theme_font_size_override("font_size", 11)
    row.add_child(value_label)
    pose_slider_controls[key] = {"slider": slider, "label": value_label}
    slider.value_changed.connect(func(value: float): _set_pose_slider_value(key, value))

func _add_gun_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, default_val: float, step_val: float, callback: Callable) -> void:
    var hbox := HBoxContainer.new()
    parent.add_child(hbox)
    var lbl := Label.new()
    lbl.text = "%-16s" % label_text
    lbl.custom_minimum_size = Vector2(130, 0)
    lbl.add_theme_font_size_override("font_size", 11)
    hbox.add_child(lbl)
    
    var val_lbl := Label.new()
    val_lbl.text = "%.2f" % default_val
    val_lbl.custom_minimum_size = Vector2(45, 0)
    val_lbl.add_theme_font_size_override("font_size", 11)
    val_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = step_val
    slider.value = default_val
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(func(v):
        val_lbl.text = ("%.1f°" % v) if "rot" in key else ("%.3f" % v if "pos" in key else "%.2fx" % v)
        callback.call(v)
    )
    hbox.add_child(slider)
    hbox.add_child(val_lbl)
    gun_sliders[key] = {"slider": slider, "label": val_lbl}

func _update_gun_sliders_and_mesh() -> void:
    if gun_sliders.has("pos_x"): gun_sliders["pos_x"]["slider"].value = right_grip_pos.x
    if gun_sliders.has("pos_y"): gun_sliders["pos_y"]["slider"].value = right_grip_pos.y
    if gun_sliders.has("pos_z"): gun_sliders["pos_z"]["slider"].value = right_grip_pos.z
    if gun_sliders.has("rot_x"): gun_sliders["rot_x"]["slider"].value = right_grip_rot.x
    if gun_sliders.has("rot_y"): gun_sliders["rot_y"]["slider"].value = right_grip_rot.y
    if gun_sliders.has("rot_z"): gun_sliders["rot_z"]["slider"].value = right_grip_rot.z
    if gun_sliders.has("scale"): gun_sliders["scale"]["slider"].value = weapon_scale_factor
    _sync_weapon_node_transform()

func _print_weapon_config() -> void:
    print("=" .repeat(60))
    print("  WEAPON TRANSFORM CONFIG")
    print("=" .repeat(60))
    print("var right_grip_pos := Vector3(%.4f, %.4f, %.4f)" % [right_grip_pos.x, right_grip_pos.y, right_grip_pos.z])
    print("var right_grip_rot := Vector3(%.1f, %.1f, %.1f)" % [right_grip_rot.x, right_grip_rot.y, right_grip_rot.z])
    print("var weapon_scale_factor: float = %.2f" % weapon_scale_factor)
    print("=" .repeat(60))
    if limb_hud_label:
        limb_hud_label.visible = true
        limb_hud_label.text = "Config printed to Godot Output!"
        get_tree().create_timer(3.0).timeout.connect(func(): limb_hud_label.visible = false)

func _refresh_clip_list_ui() -> void:
    for child in clip_list_vbox.get_children():
        child.queue_free()

    for i in range(filtered_entries.size()):
        var entry: Dictionary = filtered_entries[i]
        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        row.custom_minimum_size.y = 42.0
        var highlight_button := Button.new()
        highlight_button.toggle_mode = true
        highlight_button.button_pressed = _is_entry_highlighted(entry)
        highlight_button.text = "★" if highlight_button.button_pressed else "☆"
        highlight_button.custom_minimum_size = Vector2(44, 42)
        highlight_button.tooltip_text = "Highlight this clip and add it to the purple proposal branch."
        var row_entry := entry.duplicate(true)
        highlight_button.toggled.connect(func(enabled: bool):
            _set_entry_highlighted(row_entry, enabled)
        )
        row.add_child(highlight_button)

        var btn := CLIP_DRAG_BUTTON.new()
        btn.clip_entry = entry.duplicate(true)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.custom_minimum_size.y = 42.0
        btn.clip_text = true
        btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        var prefix := "▶ " if i == clip_index else "  "
        btn.text = prefix + entry["display"]
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
        if highlight_button.button_pressed:
            btn.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
        var idx := i
        btn.pressed.connect(func():
            clip_index = idx
            _play_selected()
            _refresh_clip_list_ui()
        )
        row.add_child(btn)
        clip_list_vbox.add_child(row)
    _refresh_slot_suggestion()

func _entry_identity(entry: Dictionary) -> String:
    var path := str(entry.get("path", ""))
    return path if not path.is_empty() else "%s:%s" % [str(entry.get("type", "")), str(entry.get("key", entry.get("name", "")))]

func _highlighted_entry_index(entry: Dictionary) -> int:
    var identity := _entry_identity(entry)
    for index in range(highlighted_clip_entries.size()):
        if _entry_identity(highlighted_clip_entries[index]) == identity:
            return index
    return -1

func _is_entry_highlighted(entry: Dictionary) -> bool:
    return _highlighted_entry_index(entry) >= 0

func _set_entry_highlighted(entry: Dictionary, enabled: bool) -> void:
    var existing_index := _highlighted_entry_index(entry)
    if enabled and existing_index < 0:
        highlighted_clip_entries.append(entry.duplicate(true))
    elif not enabled and existing_index >= 0:
        highlighted_clip_entries.remove_at(existing_index)
    _save_highlighted_shortlist()
    _select_entry_for_preview(entry)
    _refresh_runtime_state_tree()
    _refresh_clip_list_ui()
    status_label.text = "%d highlighted clip%s saved for Codex and shown as purple graph proposals." % [
        highlighted_clip_entries.size(),
        "" if highlighted_clip_entries.size() == 1 else "s",
    ]

func _clear_highlighted_clips() -> void:
    highlighted_clip_entries.clear()
    _save_highlighted_shortlist()
    _refresh_runtime_state_tree()
    _refresh_clip_list_ui()
    status_label.text = "Highlighted animation proposals cleared."

func _highlight_shortlist_payload() -> Dictionary:
    var selected_clips: Array[Dictionary] = []
    for raw_entry in highlighted_clip_entries:
        var entry := raw_entry.duplicate(true)
        entry["suggested_slot"] = _suggest_slot_for_entry(entry)
        selected_clips.append({
            "display": str(entry.get("display", "Animation clip")),
            "type": str(entry.get("type", "")),
            "key": str(entry.get("key", entry.get("name", ""))),
            "path": str(entry.get("path", "")),
            "suggested_slot": str(entry.get("suggested_slot", "")),
        })
    return {
        "version": 1,
        "purpose": "User-selected animation candidates for Codex review and route assembly.",
        "selected_clips": selected_clips,
    }

func _save_highlighted_shortlist() -> void:
    var file := FileAccess.open(HIGHLIGHT_SHORTLIST_PATH, FileAccess.WRITE)
    if file == null:
        if status_label:
            status_label.text = "Could not save the highlighted animation shortlist."
        return
    file.store_string(JSON.stringify(_highlight_shortlist_payload(), "  "))

func _load_highlighted_shortlist() -> void:
    highlighted_clip_entries.clear()
    if not FileAccess.file_exists(HIGHLIGHT_SHORTLIST_PATH):
        return
    var file := FileAccess.open(HIGHLIGHT_SHORTLIST_PATH, FileAccess.READ)
    var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
    if not parsed is Dictionary:
        return
    var saved_clips: Variant = (parsed as Dictionary).get("selected_clips", [])
    if not saved_clips is Array:
        return
    for raw_saved in saved_clips:
        if not raw_saved is Dictionary:
            continue
        var saved: Dictionary = raw_saved
        var saved_identity := _entry_identity(saved)
        for entry in all_clip_entries:
            if _entry_identity(entry) == saved_identity:
                highlighted_clip_entries.append(entry.duplicate(true))
                break

func _select_entry_for_preview(entry: Dictionary) -> void:
    var identity := _entry_identity(entry)
    for index in range(filtered_entries.size()):
        if _entry_identity(filtered_entries[index]) == identity:
            clip_index = index
            _play_selected()
            return

func _on_graph_candidate_selected(entry: Dictionary) -> void:
    var identity := _entry_identity(entry)
    for index in range(filtered_entries.size()):
        if _entry_identity(filtered_entries[index]) == identity:
            clip_index = index
            _play_selected()
            _refresh_clip_list_ui()
            status_label.text = "Selected highlighted proposal: %s" % str(entry.get("display", "Animation clip"))
            return

func _on_clip_dropped(entry: Dictionary) -> void:
    _assign_entry_to_slot(entry, selected_state_slot)

func _on_clip_dropped_on_tree_state(entry: Dictionary, slot_name: String) -> void:
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _assign_entry_to_slot(entry, slot_name)

func _on_route_state_selected(slot_name: String) -> void:
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _refresh_slot_ui()

func _select_state_slot_in_selector(slot_name: String) -> void:
    var selector_index := state_slot_keys.find(slot_name)
    if selector_index >= 0 and state_slot_selector:
        state_slot_selector.select(selector_index)

func _refresh_runtime_state_tree() -> void:
    if runtime_route_graph == null:
        return
    var graph_candidates: Array[Dictionary] = []
    for highlighted_entry in highlighted_clip_entries:
        var candidate := highlighted_entry.duplicate(true)
        candidate["suggested_slot"] = _suggest_slot_for_entry(candidate)
        graph_candidates.append(candidate)
    runtime_route_graph.call("set_state_data", state_slots, selected_state_slot, graph_candidates)

func _state_group_for_slot(slot_name: String) -> String:
    if slot_name == "idle_crouch" or slot_name.begins_with("crouch_"):
        return "CROUCH"
    if slot_name == "idle_prone" or slot_name.begins_with("prone_"):
        return "PRONE"
    if slot_name.begins_with("jump_") or slot_name in ["dive_roll", "roll"]:
        return "MOBILITY"
    if slot_name in ["combat_fire", "reload", "aim_idle"]:
        return "COMBAT"
    if (
        slot_name.begins_with("start_")
        or slot_name.begins_with("stop_")
        or slot_name.begins_with("turn_")
        or slot_name == "run_to_stop"
    ):
        return "TRANSITIONS"
    return "STANDING LOCOMOTION"

func _assign_selected_to_suggested_slot() -> void:
    if filtered_entries.is_empty():
        return
    var entry: Dictionary = filtered_entries[clip_index]
    var suggestion := _suggest_slot_for_entry(entry)
    if suggestion.is_empty():
        status_label.text = "No safe runtime-state suggestion was found for this clip."
        return
    selected_state_slot = suggestion
    _select_state_slot_in_selector(suggestion)
    _assign_entry_to_slot(entry, suggestion)

func _refresh_slot_suggestion() -> void:
    if slot_suggestion_label == null:
        return
    if filtered_entries.is_empty():
        slot_suggestion_label.text = "BEST MATCH: none"
        return
    var suggestion := _suggest_slot_for_entry(filtered_entries[clip_index])
    if suggestion.is_empty():
        slot_suggestion_label.text = "BEST MATCH: preview only — drag manually or propose a new route"
    else:
        slot_suggestion_label.text = "BEST MATCH: %s (review before applying)" % suggestion

func _suggest_slot_for_entry(entry: Dictionary) -> String:
    if str(entry.get("type", "")) != "FBX":
        return ""
    var path := str(entry.get("path", "")).to_lower()
    var best_slot := ""
    var best_score := -1
    var targets := _slot_targets()
    for slot_key in targets.keys():
        for candidate in targets[slot_key]:
            var candidate_text := str(candidate).to_lower()
            if candidate_text in path and candidate_text.length() > best_score:
                best_slot = str(slot_key)
                best_score = candidate_text.length()
    return best_slot

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found:
            return found
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found:
            return found
    return null

func _on_search_changed(query: String) -> void:
    filtered_entries.clear()
    var q := query.strip_edges().to_lower()
    for entry in all_clip_entries:
        var name_str: String = str(entry["display"]).to_lower()
        if q == "" or q in name_str:
            filtered_entries.append(entry)
    clip_index = 0
    if not filtered_entries.is_empty():
        _play_selected()
    _refresh_clip_list_ui()

func _auto_map_all_slots() -> void:
    # Conservative mapping into known states. It does not invent gameplay logic.
    var slot_targets: Dictionary = {
        "idle_rifle": ["Lite Rifle Pack/idle", "Rifle 8-Way Locomotion Pack/idle", "idle"],
        "aim_idle": ["Shooter Pack/rifle aiming idle", "aiming idle", "idle"],
        "run_forward": ["Lite Rifle Pack/run forward", "run forward", "walk forward"],
        "run_backward": ["Lite Rifle Pack/run backward", "run backward", "walk backward"],
        "run_left": ["Lite Rifle Pack/run left", "run left", "walk left"],
        "run_right": ["Lite Rifle Pack/run right", "run right", "walk right"],
        "run_forward_left": ["Lite Rifle Pack/run forward left", "run forward left"],
        "run_forward_right": ["Lite Rifle Pack/run forward right", "run forward right"],
        "run_back_left": ["Lite Rifle Pack/run backward left", "run backward left"],
        "run_back_right": ["Lite Rifle Pack/run backward right", "run backward right"],
        "idle_crouch": ["Rifle 8-Way Locomotion Pack/idle crouching", "idle crouching", "crouch idle"],
        "crouch_forward": ["Rifle 8-Way Locomotion Pack/walk crouching forward", "walk crouching forward"],
        "crouch_backward": ["Rifle 8-Way Locomotion Pack/walk crouching backward", "walk crouching backward"],
        "crouch_left": ["Rifle 8-Way Locomotion Pack/walk crouching left", "walk crouching left"],
        "crouch_right": ["Rifle 8-Way Locomotion Pack/walk crouching right", "walk crouching right"],
        "crouch_forward_left": ["Rifle 8-Way Locomotion Pack/walk crouching forward left"],
        "crouch_forward_right": ["Rifle 8-Way Locomotion Pack/walk crouching forward right"],
        "crouch_back_left": ["Rifle 8-Way Locomotion Pack/walk crouching backward left"],
        "crouch_back_right": ["Rifle 8-Way Locomotion Pack/walk crouching backward right"],
        "idle_prone": ["Prone Firing Rifle", "Prone Idle", "Prone Forward Stop"],
        "prone_forward": ["Prone Forward", "Crawl Forward"],
        "prone_backward": ["Moving Backward In Prone Position", "Prone Backward"],
        "prone_turn_left": ["Prone Left Turn", "Prone Turn Left"],
        "prone_turn_right": ["Prone Right Turn", "Prone Turn Right", "Prone Left Turn"],
        "prone_fire": ["Prone Firing Rifle", "Prone Fire"],
        "prone_reload": ["Prone Reloading", "Prone Reload"],
        "dive_roll": ["Running Dive Roll", "Dive Roll"],
        "roll": ["Run To Rolling", "Roll"],
        "jump_up": ["Rifle 8-Way Locomotion Pack/jump up", "jump up"],
        "jump_loop": ["Rifle 8-Way Locomotion Pack/jump loop", "jump loop"],
        "jump_down": ["Rifle 8-Way Locomotion Pack/jump down", "jump down"],
        "combat_fire": ["Shooter Pack/firing rifle", "firing rifle"],
        "reload": ["Reloading", "Reload"]
    }

    var mapped_count := 0
    for slot_key in slot_targets.keys():
        var candidates: Array = slot_targets[slot_key]
        var found_path := ""
        for cand in candidates:
            var cand_str: String = str(cand).to_lower()
            for entry in all_clip_entries:
                if entry["type"] != "FBX": continue
                var full_path: String = entry["path"].to_lower()
                if cand_str in full_path:
                    found_path = entry["path"]
                    break
            if found_path != "":
                break
        
        if found_path != "":
            state_slots[slot_key] = found_path
            mapped_count += 1

    _save_state_slots()
    _refresh_slot_ui()
    if limb_hud_label:
        limb_hud_label.visible = true
        limb_hud_label.text = "⚡ Auto-built %d / %d known runtime states. Review before playtesting." % [mapped_count, slot_targets.size()]
        get_tree().create_timer(4.0).timeout.connect(func(): limb_hud_label.visible = false)

func _slot_targets() -> Dictionary:
    return {
        "idle_rifle": ["Lite Rifle Pack/idle", "Rifle 8-Way Locomotion Pack/idle", "idle"],
        "aim_idle": ["Shooter Pack/rifle aiming idle", "aiming idle"],
        "run_forward": ["Lite Rifle Pack/run forward", "run forward"],
        "run_backward": ["Lite Rifle Pack/run backward", "run backward"],
        "run_left": ["Lite Rifle Pack/run left", "run left"],
        "run_right": ["Lite Rifle Pack/run right", "run right"],
        "run_forward_left": ["Lite Rifle Pack/run forward left", "run forward left"],
        "run_forward_right": ["Lite Rifle Pack/run forward right", "run forward right"],
        "run_back_left": ["Lite Rifle Pack/run backward left", "run backward left"],
        "run_back_right": ["Lite Rifle Pack/run backward right", "run backward right"],
        "idle_crouch": ["idle crouching", "crouch idle"],
        "crouch_forward": ["walk crouching forward"],
        "crouch_backward": ["walk crouching backward"],
        "crouch_left": ["walk crouching left"],
        "crouch_right": ["walk crouching right"],
        "crouch_forward_left": ["walk crouching forward left"],
        "crouch_forward_right": ["walk crouching forward right"],
        "crouch_back_left": ["walk crouching backward left"],
        "crouch_back_right": ["walk crouching backward right"],
        "idle_prone": ["Prone Firing Rifle", "Prone Idle"],
        "prone_forward": ["Prone Forward", "Crawl Forward"],
        "prone_backward": ["Moving Backward In Prone Position", "Prone Backward"],
        "prone_turn_left": ["Prone Left Turn", "Prone Turn Left"],
        "prone_turn_right": ["Prone Right Turn", "Prone Turn Right"],
        "prone_fire": ["Prone Firing Rifle", "Prone Fire"],
        "prone_reload": ["Prone Reloading", "Prone Reload"],
        "dive_roll": ["Running Dive Roll", "Dive Roll"],
        "roll": ["Run To Rolling", "Roll"],
        "jump_up": ["jump up"],
        "jump_loop": ["jump loop"],
        "jump_down": ["jump down"],
        "combat_fire": ["firing rifle"],
        "reload": ["Reloading", "Reload"],
        "start_forward": ["Start Walking"],
        "start_backward": ["start walking backwards"],
        "stop_forward": ["stop walking"],
        "stop_backward": ["walk backwards stop"],
        "run_to_stop": ["Run To Stop"],
        "crouch_start": ["Rifle Crouch Idle To Walk"],
        "crouch_stop": ["Crouch Stop Walking"],
        "turn_90_left": ["turn 90 left"],
        "turn_90_right": ["turn 90 right"],
    }

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
const TRANSFORM_GIZMO_SCRIPT := preload("res://scripts/labs/transform_gizmo_3d.gd")
const WEAPON_RIG_PREVIEW := preload("res://scripts/labs/weapon_rig_preview_loader.gd")
const WORKSHOP_REPOSITORY_SCRIPT := preload("res://scripts/labs/animation_workshop_repository.gd")
const RETARGET_SERVICE_SCRIPT := preload("res://scripts/labs/animation_retarget_service.gd")
const SEQUENCE_SERVICE_SCRIPT := preload("res://scripts/labs/animation_sequence_service.gd")
const EDITOR_UI_SCALE := 0.84
const ROOT_SANITIZER := preload("res://scripts/player/operator_animation_root_sanitizer.gd")
const PROCEDURAL_POSE_PROFILE := preload(
    "res://scripts/player/operator_procedural_pose_profile.gd"
)
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
var workshop_repository = WORKSHOP_REPOSITORY_SCRIPT.new()
var retarget_service = RETARGET_SERVICE_SCRIPT.new()
var sequence_service = SEQUENCE_SERVICE_SCRIPT.new()
var weapon_socket_visible: bool = true
var weapon_node: Node3D
var socket_attachment: BoneAttachment3D
var left_hand_marker: Marker3D
var right_hand_marker: Marker3D
var weapon_muzzle_marker: Marker3D
var weapon_calibrated_pivot: Node3D
var gunsmith_weapon_config: Dictionary = {}
var loaded_gunsmith_config_path: String = ""

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
var pose_transform_gizmo: SocomTransformGizmo3D
var active_pose_gizmo_handle: StringName = &""
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
var pose_follow_chain: bool = false
var pose_follow_chain_button: Button
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

# BEGIN GENERATED CROSS-LAYER CONTRACT
# Parsing contract only. Every method is overridden by a named feature layer.
func _add_gun_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, default_val: float, step_val: float, callback: Callable) -> void:
    pass

func _add_pose_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, step_val: float) -> void:
    pass

func _assign_selected_to_suggested_slot() -> void:
    pass

func _assign_to_slot(slot_name: String) -> void:
    pass

func _auto_map_all_slots() -> void:
    pass

func _build_assembly_animation(segments: Array[Dictionary]) -> Animation:
    return null

func _clear_highlighted_clips() -> void:
    pass

func _current_trim_segment() -> Dictionary:
    return {}

func _cycle_segment_blend(index: int) -> void:
    pass

func _cycle_weapon() -> void:
    pass

func _entry_identity(entry: Dictionary) -> String:
    return ""

func _filter_category(cat: String) -> void:
    pass

func _find_animation_player(node: Node) -> AnimationPlayer:
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    return null

func _get_current_animation(entry: Dictionary) -> Animation:
    return null

func _hide_baked_rifle_parts(node: Node) -> void:
    pass

func _load_and_retarget_fbx(entry: Dictionary) -> void:
    pass

func _load_authored_animation(entry: Dictionary) -> void:
    pass

func _load_highlighted_shortlist() -> void:
    pass

func _on_clip_dropped_on_tree_state(entry: Dictionary, slot_name: String) -> void:
    pass

func _on_graph_candidate_selected(entry: Dictionary) -> void:
    pass

func _on_route_state_selected(slot_name: String) -> void:
    pass

func _on_search_changed(query: String) -> void:
    pass

func _play_selected() -> void:
    pass

func _prepare_pose_mode() -> void:
    pass

func _print_weapon_config() -> void:
    pass

func _rebuild_limb_bubbles() -> void:
    pass

func _rebuild_weapon_socket() -> void:
    pass

func _refresh_assembly_cards() -> void:
    pass

func _refresh_clip_list_ui() -> void:
    pass

func _refresh_frame_editor_labels() -> void:
    pass

func _refresh_runtime_state_tree() -> void:
    pass

func _refresh_slot_suggestion() -> void:
    pass

func _reset_camera() -> void:
    pass

func _save_authored_segments(segments: Array[Dictionary], fallback_name: String, clear_assembly: bool) -> void:
    pass

func _save_highlighted_shortlist() -> void:
    pass

func _select_relative(amount: int) -> void:
    pass

func _selected_animation() -> Animation:
    return null

func _selected_sequence_region_keys() -> Array[String]:
    return []

func _should_loop(clip_name: String) -> bool:
    return false

func _skin_name(skin: SkinType) -> String:
    return ""

func _toggle_gun_lab() -> void:
    pass

func _toggle_play_pause() -> void:
    pass

func _toggle_skin() -> void:
    pass

func _update_assembly_playhead() -> void:
    pass

func _update_camera() -> void:
    pass

func _update_gun_sliders_and_mesh() -> void:
    pass

func _weapon_name(wep: WeaponType) -> String:
    return ""

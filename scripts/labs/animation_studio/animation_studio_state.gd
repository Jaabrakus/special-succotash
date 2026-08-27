extends Node3D

const PS1_GAS_MASK_RIGGED_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const MILITARY_TACTICAL_SCENE := preload("res://assets/characters/military_tactical_operator/Anim_Idle_MIL_R5.fbx")
const OPERATOR_SCENE := preload("res://assets/characters/operator3d/socom_141_operator_animated.glb")
const MIXAMO_SKIN_SCENE := preload("res://assets/characters/operator3d/mixamo_beta_skin.glb")
const PS1_NV_SCENE := preload("res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb")
const COUNTER_STRIKE_URBAN_SCENE_PATH := (
    "res://counter-strike-urban/source/Counter Strike Urban.fbx"
)
const COUNTER_STRIKE_URBAN_BODY_TEXTURE_PATH := (
    "res://counter-strike-urban/textures/SEAL_Working1.png"
)
const COUNTER_STRIKE_URBAN_BACKPACK_TEXTURE_PATH := (
    "res://counter-strike-urban/textures/Backpack2.png"
)
const PS1_GAS_MASK_OBJ := preload("res://assets/characters/ps1_gas_mask_soldier/sasman5.obj")
const PS1_GAS_MASK_TEX := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const AK47_FBX_SCENE := preload("res://assets/weapons/ps1_ak47/source/ak-47.fbx")
const AK47_TEXTURE := preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
const ANIMATION_MAP_PATH := "res://config/operator_animation_map.json"
const HIGHLIGHT_SHORTLIST_PATH := "res://config/highlighted_animation_candidates.json"
const LAYER_RECIPE_PATH := "res://config/operator_animation_layer_recipe.json"
const ANIMATION_CASTING_BOARD_PATH := "res://config/animation_casting_board.json"
const WEAPON_LOADOUT_PATH := "res://config/weapons/operator_loadout.json"
const AUTHORED_ANIMATION_DIR := "res://assets/animations/authored"
const APPLE_MOCAP_REVIEW_DIR := "user://apple_mocap/review"
const CLIP_DRAG_BUTTON := preload("res://scripts/labs/animation_clip_drag_button.gd")
const SLOT_DROP_TARGET := preload("res://scripts/labs/animation_slot_drop_target.gd")
const STATE_TREE_DROP := preload("res://scripts/labs/animation_state_tree_drop.gd")
const ROUTE_GRAPH := preload("res://scripts/labs/animation_route_graph.gd")
const ROUTE_SEQUENCE_EDITOR := preload(
    "res://scripts/labs/animation_route_sequence_editor.gd"
)
const CLIP_EDITOR_SCRIPT := preload("res://scripts/labs/animation_clip_editor.gd")
const RANGE_SELECTOR_SCRIPT := preload("res://scripts/labs/animation_range_selector.gd")
const SEQUENCE_TIMELINE_SCRIPT := preload("res://scripts/labs/animation_sequence_timeline.gd")
const LAYER_COMPOSER_SCRIPT := preload("res://scripts/player/animation_layer_composer.gd")
const POSE_EDITOR_SCRIPT := preload("res://scripts/labs/animation_pose_editor.gd")
const ANIMATION_CORRECTION_OVERLAY_SCRIPT := preload(
    "res://scripts/labs/animation_correction_overlay.gd"
)
const JOINT_CONTROL_SCHEMA := preload(
    "res://scripts/player/operator_joint_control_schema.gd"
)
const ANIMATION_RIG_IK_PREVIEW_SCRIPT := preload(
    "res://scripts/labs/animation_studio_arm_ik_preview.gd"
)
const ANIMATION_RIG_OVERLAY_SCRIPT := preload(
    "res://scripts/labs/animation_studio_rig_overlay.gd"
)
const GUN_PLACEMENT_PROFILE := preload(
    "res://scripts/player/weapon_gun_placement_profile.gd"
)
const TRANSFORM_GIZMO_SCRIPT := preload("res://scripts/labs/transform_gizmo_3d.gd")
const WEAPON_RIG_PREVIEW := preload("res://scripts/labs/weapon_rig_preview_loader.gd")
const WEAPON_OWNERSHIP_CONTRACT := preload(
    "res://scripts/player/weapon_ownership_contract.gd"
)
const ANIMATION_WEAPON_OWNERSHIP_PREVIEW_SCRIPT := preload(
    "res://scripts/labs/animation_studio_weapon_ownership_preview.gd"
)
const WORKSHOP_REPOSITORY_SCRIPT := preload("res://scripts/labs/animation_workshop_repository.gd")
const CLIP_CATALOG_SCRIPT := preload("res://scripts/labs/animation_clip_catalog.gd")
const RETARGET_SERVICE_SCRIPT := preload("res://scripts/labs/animation_retarget_service.gd")
const SEQUENCE_SERVICE_SCRIPT := preload("res://scripts/labs/animation_sequence_service.gd")
const ANIMATION_STATE_CONTRACT := preload(
    "res://scripts/player/operator_animation_state_contract.gd"
)
const PRESENTATION_ROUTER_SCRIPT := preload(
    "res://scripts/player/operator_presentation_router.gd"
)
const OPERATOR_WEAPON_POSE_SOLVER_SCRIPT := preload(
    "res://scripts/player/operator_weapon_pose_solver.gd"
)
const OPERATOR_POSTURE_LAYER_SCRIPT := preload(
    "res://scripts/player/operator_posture_layer.gd"
)
const SOCOM_DYNAMIC_RETICLE_SCRIPT := preload(
    "res://scripts/ui/socom_dynamic_reticle.gd"
)
const GAMEPLAY_DICTIONARY := preload(
    "res://scripts/runtime/gameplay_event_dictionary.gd"
)
const ANIMATION_STATE_LANGUAGE_PARSER := preload(
    "res://scripts/labs/animation_state_language_parser.gd"
)
const ANIMATION_EVENT_DRAG_BUTTON := preload(
    "res://scripts/labs/animation_event_drag_button.gd"
)
const ANIMATION_CASTING_REPOSITORY_SCRIPT := preload(
    "res://scripts/labs/animation_casting_repository.gd"
)
const EDITOR_UI_SCALE := 0.84
const ROOT_SANITIZER := preload("res://scripts/player/operator_animation_root_sanitizer.gd")
const PROCEDURAL_POSE_PROFILE := preload(
    "res://scripts/player/operator_procedural_pose_profile.gd"
)
const EDITOR_FPS := 30.0
const STATE_EVENT_RETURN_SECONDS := 0.45
const STATE_EVENT_RETURN_BONE_CANDIDATES := [
    ["mixamorig_Spine2", "mixamorig:Spine2", "Spineupper", "Bip01 Spine3"],
    ["mixamorig_Neck", "mixamorig:Neck", "neck", "Bip01 Neck"],
    ["mixamorig_Head", "mixamorig:Head", "head", "Bip01 Head"],
    ["mixamorig_LeftShoulder", "mixamorig:LeftShoulder", "Shoulder.L", "Bip01 L Clavicle"],
    ["mixamorig_LeftArm", "mixamorig:LeftArm", "ArmUpper.L", "Bip01 L UpperArm"],
    ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "ArmLower.L", "Bip01 L Forearm"],
    ["mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001", "Bip01 L Hand"],
    ["mixamorig_RightShoulder", "mixamorig:RightShoulder", "Shoulder.R", "Bip01 R Clavicle"],
    ["mixamorig_RightArm", "mixamorig:RightArm", "ArmUpper.R", "Bip01 R UpperArm"],
    ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "ArmLower.R", "Bip01 R Forearm"],
    ["mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001", "Bip01 R Hand"],
]

enum SkinType {
    PS1_GAS_MASK_SOLDIER,
    MILITARY_TACTICAL_OPERATOR,
    SOCOM_OPERATOR,
    MIXAMO_MANNEQUIN,
    PS1_NIGHT_VISION_SEAL,
    COUNTER_STRIKE_URBAN
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
## Open on the approved playable set. The complete library contains raw and
## unclassified clips that are useful for review, but they must not be the
## first pose a user sees or receive gameplay rifle corrections by accident.
var current_category: String = "LIVE IN GAME"
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
var clip_catalog = CLIP_CATALOG_SCRIPT.new()
var retarget_service = RETARGET_SERVICE_SCRIPT.new()
var sequence_service = SEQUENCE_SERVICE_SCRIPT.new()
var animation_weapon_ownership_preview = ANIMATION_WEAPON_OWNERSHIP_PREVIEW_SCRIPT.new()
var weapon_socket_visible: bool = true
var weapon_node: Node3D
var socket_attachment: BoneAttachment3D
var left_hand_marker: Marker3D
var right_hand_marker: Marker3D
var weapon_muzzle_marker: Marker3D
var weapon_barrel_base_marker: Marker3D
var weapon_ejection_marker: Marker3D
var weapon_optic_marker: Marker3D
var weapon_calibrated_pivot: Node3D
var gunsmith_weapon_config: Dictionary = {}
var loaded_gunsmith_config_path: String = ""
var state_event_weapon_solver: Node3D
var state_event_head_look_layer
var state_event_effect_posture: StringName = &"STANDING"
var state_event_effect_active_seconds: float = 0.0
var state_event_effect_release_seconds: float = 0.0
var state_event_effect_forward_direction := Vector3.ZERO
var state_event_head_look_radians := Vector2.ZERO
var state_event_return_bone_poses: Dictionary = {}
var state_event_return_weapon_transform := Transform3D.IDENTITY
var state_event_return_blend_weight: float = 0.0
var state_event_return_pose_captured: bool = false
var state_event_return_animation_path: String = ""
var state_event_return_animation_blend_seconds: float = 0.12

# Two-Hand Gun Engine Offsets
var right_grip_pos := Vector3(-0.02, 0.08, 0.05)
var right_grip_rot := Vector3(-90.0, 180.0, 0.0)
var left_handguard_pos := Vector3(0.0, 0.02, 0.28)
var two_hand_ik_enabled: bool = true
var two_hand_ik_weight: float = 1.0
var animation_preview_weapon_owner: StringName = WEAPON_OWNERSHIP_CONTRACT.READY_SOLVER
var animation_preview_support_hand_owner: StringName = WEAPON_OWNERSHIP_CONTRACT.SUPPORT_IK_TO_WEAPON
var animation_preview_ownership_label: Label
var animation_elbow_guides_requested: bool = true
var weapon_scale_factor: float = 1.0
var gun_sliders: Dictionary = {}


func _animation_preview_uses_ready_hand_solver() -> bool:
    return (
        (
            WEAPON_OWNERSHIP_CONTRACT.ready_solver_owns_weapon(
                animation_preview_weapon_owner
            )
            or animation_preview_weapon_owner
            == WEAPON_OWNERSHIP_CONTRACT.RELAXED_RIFLE_LOCOMOTION
        )
        and animation_preview_support_hand_owner
        == WEAPON_OWNERSHIP_CONTRACT.SUPPORT_IK_TO_WEAPON
    )


func _animation_preview_is_full_body_mobility() -> bool:
    return animation_preview_weapon_owner == WEAPON_OWNERSHIP_CONTRACT.MOBILITY_RIGHT_HAND


func _sync_animation_preview_weapon_parent() -> void:
    animation_weapon_ownership_preview.bind(
        skeleton,
        socket_attachment,
        weapon_node
    )
    animation_weapon_ownership_preview.restore_hand_mount()


func _prepare_state_event_return_frame() -> void:
    if (
        active_editor_page == "States"
        and state_event_return_pose_captured
        and state_event_effect_active_seconds <= 0.0
        and state_event_effect_release_seconds > 0.0
        and skeleton != null
    ):
        # Remove last frame's crossfade before the AnimationPlayer and authored
        # corrections establish this frame's live movement pose.
        skeleton.clear_bones_global_pose_override()
        skeleton.force_update_all_bone_transforms()

# 3D Draggable Limb Bubbles System
var bubbles_enabled: bool = true
var bubble_nodes: Dictionary = {} # BoneName -> {mesh: MeshInstance3D, bone_idx: int, color: Color}
var skeleton_chain_mesh := ImmediateMesh.new()
var skeleton_chain_instance: MeshInstance3D
var skeleton_chain_material: StandardMaterial3D
var active_dragged_bone: String = ""
var pose_transform_gizmo: Node3D
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
var stage_input_surface: Control
var editor_ui_root: Control
var animation_studio_aim_reticle: Control
var status_label: Label
var category_container: HBoxContainer
var clip_scroll: ScrollContainer
var clip_list_vbox: VBoxContainer
var timeline_slider: HSlider
var time_label: Label
var timeline_context_label: Label
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
var animation_casting_repository = ANIMATION_CASTING_REPOSITORY_SCRIPT.new()
var animation_casting_board_path: String = ANIMATION_CASTING_BOARD_PATH
var animation_casting_board: Dictionary = {}
var animation_casting_region_buttons: Dictionary = {}
var animation_casting_decision_buttons: Dictionary = {}
var animation_casting_clip_label: Label
var animation_casting_progress_label: Label
var animation_casting_range_label: Label
var animation_casting_saved_label: Label
var animation_casting_regions: Dictionary = {}
var animation_casting_syncing: bool = false
var animation_casting_show_grip_guides: bool = true
var animation_casting_guides_button: Button
var animation_casting_weapon_button: Button
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


func _animation_workbench_center_screen() -> Vector2:
    var rect := get_viewport().get_visible_rect()
    var left := rect.position.x
    var right := rect.end.x
    var top := rect.position.y
    var bottom := rect.end.y
    if clip_library_panel and clip_library_panel.visible:
        left = maxf(left, clip_library_panel.get_global_rect().end.x)
    if runtime_map_panel and runtime_map_panel.visible:
        right = minf(right, runtime_map_panel.get_global_rect().position.x)
    var header := find_child("StudioHeaderPanel", true, false) as Control
    if header and header.visible:
        top = maxf(top, header.get_global_rect().end.y)
    if frame_editor_dock and frame_editor_dock.visible:
        bottom = minf(bottom, frame_editor_dock.get_global_rect().position.y)
    return Vector2((left + right) * 0.5, (top + bottom) * 0.5)


func _update_animation_studio_aim_reticle() -> void:
    if animation_studio_aim_reticle == null:
        return
    var should_show := active_editor_page in ["Pose", "States", "Casting"]
    animation_studio_aim_reticle.visible = should_show
    if not should_show:
        return
    animation_studio_aim_reticle.update_reticle_state(
        0.0,
        false,
        _animation_workbench_center_screen(),
        false,
        0.0
    )
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
var animation_correction_overlay = ANIMATION_CORRECTION_OVERLAY_SCRIPT.new()
var animation_correction_enabled: bool = false
var animation_correction_syncing: bool = false
var animation_correction_toggle: CheckButton
var animation_correction_label: Label
var animation_correction_panel: VBoxContainer
var animation_correction_controls: Dictionary = {}
var animation_rig_joint_picker: OptionButton
var correction_right_hand := Vector3.ZERO
var correction_left_hand := Vector3.ZERO
var correction_right_hand_rotation := Vector3.ZERO
var correction_left_hand_rotation := Vector3.ZERO
var correction_right_elbow := Vector3.ZERO
var correction_left_elbow := Vector3.ZERO
var correction_weapon_position := Vector3.ZERO
var correction_weapon_rotation := Vector3.ZERO
var correction_weapon_base_transform := Transform3D.IDENTITY
var correction_right_hand_base := Vector3.ZERO
var correction_left_hand_base := Vector3.ZERO
var correction_right_hand_rotation_base := Vector3.ZERO
var correction_left_hand_rotation_base := Vector3.ZERO
var animation_correction_last_frame: int = -1
var animation_rig_ik_preview = ANIMATION_RIG_IK_PREVIEW_SCRIPT.new()
var animation_rig_overlay: Node3D
var animation_rig_selected_target: StringName = &""
var animation_rig_active_drag_target: StringName = &""
var animation_rig_drag_start_values: Dictionary = {}
var correction_placement_position := Vector3.ZERO
var correction_placement_rotation := Vector3.ZERO
var animation_rig_placement_clip_key := ""
var animation_placement_anchor_local_by_posture: Dictionary = {}


func _update_animation_correction_overlay() -> void:
    # Overridden by the pose-authoring phase. This hook lets the earlier runtime
    # phase apply the optional editor overlay without knowing its UI details.
    pass

func _update_animation_rig_visual_overlay() -> void:
    # Overridden by the pose-authoring phase.
    pass

func _update_state_event_effect_preview(_delta: float) -> bool:
    return false

func _begin_animation_rig_target_drag(_target_id: StringName) -> void:
    pass

func _end_animation_rig_target_drag(_target_id: StringName) -> void:
    pass

func _select_animation_rig_target(_target_id: StringName) -> void:
    pass

func _toggle_animation_elbow_guides(_enabled: bool) -> void:
    pass

func _drag_animation_rig_target(_target_id: StringName, _axis: String, _total_drag: Vector2, _is_rotation: bool) -> void:
    pass

func _drag_animation_rig_target_screen(_target_id: StringName, _total_drag: Vector2) -> void:
    pass

func _refresh_animation_rig_selection_status() -> void:
    pass

func _load_animation_placement_reference(_clip_key: String) -> void:
    pass

func _store_animation_placement_reference(_clip_key: String) -> void:
    pass

func _store_animation_socket_reference() -> void:
    pass

func _animation_placement_origin_world() -> Vector3:
    return Vector3.ZERO

func _animation_placement_direction_world() -> Vector3:
    return Vector3.FORWARD

# Gameplay Slot Mappings. Values are FBX resource paths shared with the runtime
# animation driver, so a workbench assignment is immediately authoritative.
var state_slots: Dictionary = {}
var state_slot_keys: Array[String] = []
var selected_state_slot: String = "idle_rifle"
var state_rules: Dictionary = {}
var state_rule_syncing: bool = false
var state_condition_label: Label
var state_layer_selector: OptionButton
var state_blend_in_control: SpinBox
var state_blend_out_control: SpinBox
var state_return_selector: OptionButton
var state_rule_summary_label: Label
var state_workflow_step_labels: Array[Label] = []
var state_workflow_current_label: Label
var state_workflow_primary_button: Button
var state_preview_serial: int = 0
var event_routes: Dictionary = {}
var selected_animation_event: String = "FIRE_ACCEPTED"
var animation_event_selector: OptionButton
var animation_event_posture_selector: OptionButton
var animation_event_family_selector: OptionButton
var animation_event_route_label: Label
var presentation_plan_label: Label
var route_sequence_editor: Control
var gameplay_dictionary_label: Label
var natural_language_state_input: LineEdit
var natural_language_proposal_label: Label
var natural_language_apply_button: Button
var pending_state_proposal: Dictionary = {}
var state_language_parser = ANIMATION_STATE_LANGUAGE_PARSER.new()
var presentation_router = PRESENTATION_ROUTER_SCRIPT.new()

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

const MIXAMO_TO_URBAN_MAP := {
    "mixamorig_Hips": "Bip01 Pelvis",
    "mixamorig_Spine": "Bip01 Spine",
    "mixamorig_Spine1": "Bip01 Spine1",
    "mixamorig_Spine2": "Bip01 Spine3",
    "mixamorig_Neck": "Bip01 Neck",
    "mixamorig_Head": "Bip01 Head",
    "mixamorig_LeftShoulder": "Bip01 L Clavicle",
    "mixamorig_LeftArm": "Bip01 L UpperArm",
    "mixamorig_LeftForeArm": "Bip01 L Forearm",
    "mixamorig_LeftHand": "Bip01 L Hand",
    "mixamorig_RightShoulder": "Bip01 R Clavicle",
    "mixamorig_RightArm": "Bip01 R UpperArm",
    "mixamorig_RightForeArm": "Bip01 R Forearm",
    "mixamorig_RightHand": "Bip01 R Hand",
    "mixamorig_LeftUpLeg": "Bip01 L Thigh",
    "mixamorig_LeftLeg": "Bip01 L Calf",
    "mixamorig_LeftFoot": "Bip01 L Foot",
    "mixamorig_LeftToeBase": "Bip01 L Toe0",
    "mixamorig_RightUpLeg": "Bip01 R Thigh",
    "mixamorig_RightLeg": "Bip01 R Calf",
    "mixamorig_RightFoot": "Bip01 R Foot",
    "mixamorig_RightToeBase": "Bip01 R Toe0",
}

# BEGIN GENERATED CROSS-LAYER CONTRACT
# Parsing contract only. Every method is overridden by a named feature layer.
func _add_gun_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, default_val: float, step_val: float, callback: Callable) -> void:
    pass

func _add_pose_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, step_val: float) -> void:
    pass

func _apply_natural_language_state_proposal() -> void:
    pass

func _assign_selected_to_suggested_slot() -> void:
    pass

func _assign_to_slot(slot_name: String) -> void:
    pass

func _auto_map_all_slots() -> void:
    pass

func _build_animation_casting_page(page: VBoxContainer) -> void:
    pass

func _build_assembly_animation(segments: Array[Dictionary]) -> Animation:
    return null

func _clear_highlighted_clips() -> void:
    pass

func _connect_selected_event_to_state() -> void:
    pass

func _current_trim_segment() -> Dictionary:
    return {}

func _cycle_segment_blend(index: int) -> void:
    pass

func _cycle_weapon() -> void:
    pass

func _disconnect_selected_event() -> void:
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

func _on_animation_event_dropped_on_tree_state(event_name: String, slot_name: String) -> void:
    pass

func _on_animation_event_selected(index: int) -> void:
    pass

func _on_clip_dropped_on_tree_state(entry: Dictionary, slot_name: String) -> void:
    pass

func _on_graph_candidate_selected(entry: Dictionary) -> void:
    pass

func _on_route_event_selected(event_name: String) -> void:
    pass

func _on_route_state_selected(slot_name: String) -> void:
    pass

func _on_visual_sequence_changed(patch: Dictionary) -> void:
    pass

func _on_search_changed(query: String) -> void:
    pass

func _on_state_workflow_primary_pressed() -> void:
    pass

func _play_selected() -> void:
    pass

func _prepare_pose_mode() -> void:
    pass

func _preview_selected_animation_event() -> void:
    pass

func _print_weapon_config() -> void:
    pass

func _propose_natural_language_state() -> void:
    pass

func _rebuild_limb_bubbles() -> void:
    pass

func _rebuild_weapon_socket() -> void:
    pass

func _refresh_animation_casting_ui() -> void:
    pass

func _refresh_animation_correction_label() -> void:
    pass

func _refresh_assembly_cards() -> void:
    pass

func _refresh_clip_list_ui() -> void:
    pass

func _refresh_event_routing_ui() -> void:
    pass

func _refresh_frame_editor_labels() -> void:
    pass

func _refresh_pose_keyframe_label() -> void:
    pass

func _refresh_runtime_state_tree() -> void:
    pass

func _refresh_slot_suggestion() -> void:
    pass

func _refresh_state_workflow_cues() -> void:
    pass

func _reset_camera() -> void:
    pass

func _reset_state_event_weapon_solver() -> void:
    pass

func _restore_raw_animation_frame() -> void:
    pass

func _save_authored_segments(segments: Array[Dictionary], fallback_name: String, clear_assembly: bool) -> void:
    pass

func _save_highlighted_shortlist() -> void:
    pass

func _select_and_preview_animation_event(event_name: String) -> void:
    pass

func _select_animation_event(event_name: String) -> void:
    pass

func _select_relative(amount: int) -> void:
    pass

func _select_state_slot_in_selector(slot_name: String) -> void:
    pass

func _selected_animation() -> Animation:
    return null

func _selected_sequence_region_keys() -> Array[String]:
    return []

func _should_loop(clip_name: String) -> bool:
    return false

func _skin_name(skin: SkinType) -> String:
    return ""

func _toggle_animation_correction_overlay(enabled: bool) -> void:
    pass

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

func _verify_selected_event_route() -> void:
    pass

func _weapon_name(wep: WeaponType) -> String:
    return ""

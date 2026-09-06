class_name GunsmithLabState
extends "res://scripts/labs/gunsmith/gunsmith_lab_dependencies.gd"

var cam_pivot: Node3D
var cam: Camera3D
var cam_target := Vector3(0.08, 1.24, 0.05)
var cam_distance := 0.95
var cam_pitch := -8.0
var cam_yaw := 55.0
var is_orbiting := false
var is_panning := false
var last_mouse_pos := Vector2.ZERO

var trooper_scale := 62.0
var trooper_node: Node3D
var composure_preview_dummy: Node3D
var composure_preview_active := false
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var runtime_posture_layer: SocomOperatorPostureLayer
var preview_posture: StringName = &"STANDING"
var preview_hip_level_trim_deg := 4.5
var stance_buttons: Dictionary = {}

var left_arm_idx := -1
var left_forearm_idx := -1
var left_hand_idx := -1
var right_arm_idx := -1
var right_forearm_idx := -1
var right_hand_idx := -1
var head_idx := -1
var weapon_anchor_bone_idx := -1
var right_hand_ik: SkeletonIK3D
var left_hand_ik: SkeletonIK3D

var upper_arm_len := 0.315
var forearm_len := 0.312
var max_reach := 0.620
var left_palm_anchor_local := Vector3.ZERO
var right_palm_anchor_local := Vector3.ZERO
var support_hand_attached := true
var right_elbow_pole_offset := Vector3.ZERO
var left_elbow_pole_offset := Vector3.ZERO
var elbow_poles_by_stance: Dictionary = {
	&"STANDING": {"right": Vector3.ZERO, "left": Vector3.ZERO},
	&"CROUCHED": {"right": Vector3.ZERO, "left": Vector3.ZERO},
	&"PRONE": {"right": Vector3.ZERO, "left": Vector3.ZERO},
}
var hand_poses_by_stance: Dictionary = {
	&"STANDING": {}, &"CROUCHED": {}, &"PRONE": {},
}
var stance_rebase_remaining := 0.0
var right_elbow_pole_marker: MeshInstance3D
var left_elbow_pole_marker: MeshInstance3D
var joint_debug_mesh := ImmediateMesh.new()
var joint_debug_instance: MeshInstance3D
var body_joint_markers: Dictionary = {}
var selected_body_joint: StringName = &"left_upper_arm"
var selected_joint_title: Label
var selected_joint_help: Label

var weapon_contact_target_pivot: Marker3D
var weapon_contact_targets: Dictionary = {}
var weapon_contact_base_transforms: Dictionary = {}
var weapon_contact_graph_profile: Dictionary = WeaponContactGraphContract.default_profile()
var selected_weapon_contact_target := "trigger_hand"

enum GripStyle { CLASSIC_CRADLE, C_CLAMP_TACTICAL, MAGWELL_GRIP, VERTICAL_FOREGRIP, ANGLED_AFG }
var current_grip_style: GripStyle = GripStyle.CLASSIC_CRADLE
var palm_roll := 0.0
var palm_pitch := 0.0
var palm_yaw := 0.0
var finger_curl := 0.65
var thumb_wrap := 0.50

var ba_right_hand: BoneAttachment3D
var right_hand_dot: MeshInstance3D
var weapon_root: Node3D
var weapon_pivot: Node3D
var geometry_root: Node3D
var socket_root: Node3D
var weapon_mount_local := Transform3D.IDENTITY
var weapon_anchor_local := Transform3D.IDENTITY
var weapon_anchor_bone_origin := Vector3.ZERO
var weapon_anchor_ready := false
var weapon_master_pose_initialized := false
var _loaded_weapon_profile: Dictionary = {}
var current_weapon_mesh: Node3D
var current_silencer_mesh: Node3D
var current_scope_mesh: Node3D
var save_rig_button: Button
var equip_weapon_button: Button
var play_latest_button: Button

var hand_gizmo_world: Node3D
var hand_gizmo_center: MeshInstance3D
var gizmo_arrow_x: Node3D
var gizmo_arrow_y: Node3D
var gizmo_arrow_z: Node3D
var gizmo_ring_roll: MeshInstance3D
var gizmo_ring_pitch: MeshInstance3D
var gizmo_ring_yaw: MeshInstance3D
var weapon_gizmo_world: Node3D
var weapon_gizmo_center: MeshInstance3D
var weapon_gizmo_arrow_x: Node3D
var weapon_gizmo_arrow_y: Node3D
var weapon_gizmo_arrow_z: Node3D
var weapon_gizmo_ring_roll: MeshInstance3D
var weapon_gizmo_ring_pitch: MeshInstance3D
var weapon_gizmo_ring_yaw: MeshInstance3D

var left_grip_marker: MeshInstance3D
var right_grip_marker: MeshInstance3D
var muzzle_marker: MeshInstance3D
var barrel_base_marker: MeshInstance3D
var ejection_marker: MeshInstance3D
var optic_marker: MeshInstance3D
var eye_sight_marker: Marker3D
var eye_sight_dot: MeshInstance3D
var eye_sight_direction_marker: Marker3D
var eye_sight_direction_dot: MeshInstance3D
var gun_placement_anchor_local_by_posture: Dictionary = {}
var grip_offset_pos := Vector3.ZERO
var grip_offset_rot := Vector3.ZERO
var user_scale_multiplier := 1.0
var auto_normalized_scale := 1.0
var auto_grip_center_offset := Vector3.ZERO
var left_grip_local_pos := Vector3(-0.04, -0.04, -0.30)
var right_grip_local_pos := Vector3.ZERO
var muzzle_local_pos := Vector3(0.0, 0.0, -0.68)
var barrel_base_local_pos := Vector3(0.0, 0.0, -0.12)
var ejection_local_pos := Vector3(0.05, 0.03, -0.10)
var optic_local_pos := Vector3(0.0, 0.08, -0.18)
var right_grip_profile_loaded := false
var right_grip_needs_initialization := false

var interactive_dots: Array[Dictionary] = []
var hovered_dot_id := ""
var dragged_dot_id := ""
var authoring_pointer_down := false
var mouse_fire_armed := false
var drag_plane := Plane()
var drag_initial_world := Vector3.ZERO
var drag_offset_vector := Vector3.ZERO
var active_gizmo_id := "hand"
var gunsmith_camera_tracking_enabled := false
var live_weapon_aim_enabled := true
var live_weapon_yaw_deg := 0.0
var live_weapon_pitch_deg := 0.0
var live_aim_preview_toggle: CheckButton
var gunsmith_live_aim_rotation := Quaternion.IDENTITY
var match_weapon_rail_to_blue_line := true
var show_joint_bubbles := true
var isolate_selected_node := false

var weapon_name := "m16a2"
var weapon_display_name := "M16A2"
var selected_category := "Assault Rifles"
var selected_catalog_weapon_id := "m16a2"
var selected_visual_profile_id := "assaultrifle_1"
var selected_model_path := "res://assets/weapons/modular_pack/AssaultRifle_1.fbx"
var catalog_fire_modes: Array[String] = ["semi", "burst"]
var catalog_default_fire_mode := "semi"
var catalog_burst_size := 3
var fire_rate_rpm := 650
var damage_per_shot := 34
var headshot_multiplier := 3.5
var muzzle_velocity_mps := 715.0
var is_silenced := false
var base_spread_deg := 0.28
var moving_spread_deg := 0.95
var full_gait_spread_deg := 1.55
var opening_burst_motion_multiplier := 0.35
var bloom_per_shot_deg := 0.32
var bloom_recovery_speed := 10.0
var bloom_recovery_delay_seconds := 0.30
var max_recoil_bloom_deg := 2.4
var functional_aim_climb_enabled := false
var aim_climb_pitch_per_shot_deg := 0.35
var aim_climb_yaw_per_shot_deg := 0.0
var aim_climb_max_pitch_deg := 3.5
var aim_climb_max_yaw_deg := 0.75
var aim_climb_recovery_delay_seconds := 0.10
var aim_climb_recovery_speed_deg_per_second := 6.0
var crouch_spread_multiplier := 0.72
var crouch_bloom_per_shot_deg := 1.35
var crouch_max_recoil_bloom_deg := 1.70
var crouch_bloom_recovery_speed := 18.0
var magazine_capacity := 30
var reserve_ammo := 90
var reticle_base_gap_px := 10.0
var reticle_max_gap_px := 46.0
var reticle_response_speed := 24.0
var reticle_shot_kick_px := 10.5
var reticle_shot_kick_return := 18.0
var reticle_cadence_driven_return := true
var reticle_vrc_enabled := true
var reticle_vrc_toggle: CheckButton
var reticle_vrc_delay := 0.18
var reticle_vrc_return_speed := 180.0
var reticle_maximum_shot_kick_px := 12.5
var reticle_maximum_movement_tick_extension_px := 16.0
var current_bloom := 0.0
var fire_cooldown := 0.0
var burst_shot_count := 0
var composure := OperatorComposureScript.new()
var composure_preview_movement := 0.0
var composure_preview_turning := 0.0
var composure_opening_stress_multiplier := 0.28
var composure_graze_damage_scale := 0.38
var composure_readout: Label
var composure_profile_title: Label
var shared_hurtbox_scales: Dictionary = HurtboxProfile.load_scales()
var shared_hurtbox_geometry: Dictionary = HurtboxProfile.load_geometry()
var shared_custom_hitboxes: Array[Dictionary] = HurtboxProfile.load_custom_hitboxes()
var hitbox_model: GunsmithHitboxModel
var selected_hurtbox_region: StringName = &"torso"
var hurtbox_region_picker: OptionButton
var hurtbox_shape_picker: OptionButton
var hurtbox_damage_type_picker: OptionButton
var delete_hitbox_button: Button
var hurtbox_edit_markers: Dictionary = {}
var hitbox_drag_offset_start := Vector3.ZERO
var fire_input_held := false
var active_lab_tab_name := "Weapon Rig"
var current_aim_target := Vector3.ZERO
var is_reloading := false
var weapon_owner_state: StringName = WeaponOwnershipContract.OWNER_WEAPON_MASTER
var support_hand_policy: StringName = WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
var pose_ownership_snapshot: Dictionary = {}
var pose_ownership_conflicts: Array[String] = []
var action_weapon_follow_active := false
var action_weapon_hand_offset := Transform3D.IDENTITY
var animation_frame_weapon_position_correction := Vector3.ZERO
var animation_frame_weapon_rotation_correction_deg := Vector3.ZERO
var frame_weapon_drag_position_start := Vector3.ZERO
var action_return_transform := Transform3D.IDENTITY
var action_recovery_start := Transform3D.IDENTITY
var action_recovery_duration := 0.14
var action_recovery_elapsed := action_recovery_duration
var active_reload_visual_slot := ""
var reload_magazine_proxy: MeshInstance3D
var reload_visual_state := WeaponReloadVisualTimeline.STATE_IN_WEAPON

var camo_skins: Array[String] = [
	"Factory Classic (Wood & Steel)", "SOCOM Desert Tan (Crossroads)",
	"SOCOM Woodland OD (Frostfire)", "Midnight Spec-Ops (All Black)",
	"Arctic Whiteout (Winter Camo)", "Titanium & Carbon (Silver Steel)",
]
var selected_camo_idx := 0
var target_board: Node3D
var bullet_tracers: Node3D
var weapon_categories: Dictionary = {
	"Assault Rifles": ["AssaultRifle_1", "AssaultRifle_2", "AssaultRifle_3", "AssaultRifle_4", "AssaultRifle_5", "AssaultRifle2_1", "AssaultRifle2_2", "AssaultRifle2_3", "AssaultRifle2_4"],
	"Classic SOCOM": ["ak-47"],
	"Bullpups": ["Bullpup_1", "Bullpup_2", "Bullpup_3"],
	"SMGs": ["SubmachineGun_1", "SubmachineGun_2", "SubmachineGun_3", "SubmachineGun_4", "SubmachineGun_5"],
	"Sniper Rifles": ["SniperRifle_1", "SniperRifle_2", "SniperRifle_3", "SniperRifle_4", "SniperRifle_5", "SniperRifle_6"],
	"Shotguns": ["Shotgun_1", "Shotgun_2", "Shotgun_3", "Shotgun_4", "Shotgun_SawedOff", "Shotgun_ShortStock"],
	"Pistols": ["Pistol_1", "Pistol_2", "Pistol_3", "Pistol_4", "Pistol_5", "Pistol_6"],
	"Revolvers": ["Revolver_1", "Revolver_2", "Revolver_3", "Revolver_4", "Revolver_5"],
}
var silencer_options: Array[String] = ["None", "Silencer_1", "Silencer_2", "Silencer_3", "Silencer_long", "Silencer_Short"]
var scope_options: Array[String] = ["None", "Scope_1", "Scope_2", "Scope_3"]
var selected_weapon_file := "m16a2"
var selected_silencer := "None"
var selected_scope := "None"

var animation_catalog
var presentation_router = PresentationRouterScript.new()
var animation_asset_catalog := GunsmithAnimationAssetCatalogScript.new()
var all_animation_entries: Array[Dictionary] = []
var all_animation_paths: Dictionary = {}
var handling_profile: Dictionary = {}
var handling_family_select: OptionButton
var animation_mapping_status: Label
var support_hand_toggle: CheckButton
var animation_slot_labels: Dictionary = {}
var animation_slot_selectors: Dictionary = {}
var animation_preview_token := 0
var animation_frame_editor := GunsmithAnimationFrameEditorScript.new()
var animation_frame_scrubber: HSlider
var animation_frame_panel: PanelContainer
var animation_frame_timeline: Control
var animation_frame_readout: Label
var animation_frame_play_button: Button
var animation_frame_edit_button: Button
var animation_frame_edit_controls: Array[BaseButton] = []
var animation_frame_editor_title: Label
var reload_event_controls_row: HBoxContainer
var reload_event_status: Label
var reload_event_buttons: Dictionary = {}
var animation_frame_base_pose: Dictionary = {}
var animation_frame_last_applied := -1
var animation_edit_candidate_slot := ""
var animation_edit_candidate_clip: StringName = &""
var all_animation_select: OptionButton
var selected_animation_key: StringName = &""
var animation_hand_maps: Dictionary = {}
var animation_quality_status: Label
var animation_quality_results: RichTextLabel
var animation_quality_sample_elapsed := 0.0
var animation_autofix_undo_button: Button
var animation_quality_auditor := GunsmithAnimationQualityAuditorScript.new()

var sliders_map: Dictionary = {}
var overlay: Control
var sidebar_panel: PanelContainer
var hud_status: Label
var fire_profile_title: Label
var reticle_canvas: Control
var dynamic_reticle: SocomDynamicReticle
var fire_debug_mesh := ImmediateMesh.new()
var fire_debug_instance: MeshInstance3D
var fire_debug_material: StandardMaterial3D
var show_bullet_velocity := true
var show_barrel_axis := false
var show_camera_aim := false
var show_eye_sight := true
var show_last_shot := false
var last_shot_origin := Vector3.ZERO
var last_shot_end := Vector3.ZERO
var rotation_panel: PanelContainer
var rotation_title_label: Label
var rotation_orbit_control: Control
var rotation_value_labels: Dictionary = {}
var reticle_bloom_radius := 12.0

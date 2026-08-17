class_name SocomCameraProfile
extends Resource

@export_group("Preferred Shot")
@export var distance: float = 2.20
@export var height: float = 2.05
@export var shoulder_offset: float = 0.0
@export var vertical_fov: float = 74.0
@export var close_level_fov: float = 80.0
@export_range(0.0, 1.0, 0.01) var close_fov_start_compression: float = 0.48
@export_range(0.0, 1.0, 0.01) var close_fov_full_compression: float = 0.78
@export var close_fov_response: float = 12.0
@export var look_ahead_distance: float = 14.0
@export var look_height: float = 1.45

@export_group("Orbit")
@export var mouse_sensitivity: float = 0.0024
@export var pitch_min_deg: float = -60.0
@export var pitch_max_deg: float = 28.0
@export var orbit_trail_enabled: bool = true
@export var orbit_yaw_response: float = 22.0
@export var orbit_pitch_response: float = 24.0
@export var scoped_orbit_yaw_response: float = 30.0
@export var scoped_orbit_pitch_response: float = 32.0

@export_group("Mouse Aim String")
@export var mouse_aim_string_enabled: bool = true
@export_range(0.5, 8.0, 0.1) var mouse_string_yaw_limit_deg: float = 5.0
@export_range(0.5, 6.0, 0.1) var mouse_string_pitch_limit_deg: float = 3.25
@export_range(0.5, 3.0, 0.05) var mouse_string_tension_curve: float = 1.35
@export var mouse_string_debug_dot_visible: bool = true
@export_range(6.0, 20.0, 1.0) var mouse_string_deadzone_radius_px: float = 10.0
@export_range(3.0, 8.0, 0.5) var mouse_string_blue_radius_px: float = 5.0
@export_range(24.0, 72.0, 1.0) var mouse_string_max_lead_px: float = 40.0
@export_range(8.0, 40.0, 0.5) var mouse_string_aim_yaw_response: float = 28.0
@export_range(8.0, 40.0, 0.5) var mouse_string_aim_pitch_response: float = 30.0
@export_range(0.0, 1.0, 0.05) var mouse_string_debug_opacity: float = 0.90

@export_group("Mouse Cursor Cage")
@export var mouse_cursor_cage_enabled: bool = false
@export_range(0.25, 0.495, 0.001) var mouse_cage_half_width: float = 0.48
@export_range(0.25, 0.495, 0.001) var mouse_cage_half_height: float = 0.46
@export_range(0.50, 0.98, 0.01) var mouse_edge_turn_start: float = 0.88
@export var mouse_edge_yaw_speed_deg: float = 210.0
@export var mouse_edge_pitch_speed_deg: float = 135.0
@export_range(0.5, 3.0, 0.05) var mouse_edge_turn_curve: float = 1.35
@export_range(0.0, 1.0, 0.01) var mouse_cage_guide_opacity: float = 0.14

@export_group("Downward Aim Authority")
@export var downward_aim_start_deg: float = -18.0
@export var downward_aim_full_deg: float = -52.0
@export var downward_distance: float = 2.95
@export var downward_height: float = 1.45
@export var downward_shoulder_offset: float = 0.0
@export var downward_fov: float = 60.0
@export var steep_downward_fov: float = 42.0
@export var downward_fov_response: float = 12.0
@export var max_downward_camera_raise: float = 1.90
@export var mid_downward_ledge_raise: float = 0.90
@export var max_downward_camera_forward: float = 2.90
@export var max_downward_camera_side: float = 0.0
@export_range(0.0, 1.0, 0.001) var downward_aim_head_y: float = 0.85
@export_range(0.0, 1.0, 0.001) var steep_downward_head_y: float = 0.98
@export_range(0.0, 1.2, 0.001) var downward_aim_pelvis_y: float = 1.08
@export var downward_max_framing_height_correction: float = 1.50
@export var aim_distance: float = 250.0

@export_group("Screen-space Framing")
@export_range(0.0, 1.0, 0.001) var desired_head_x: float = 0.50
@export_range(0.0, 1.0, 0.001) var desired_head_y: float = 0.66
@export_range(0.0, 1.0, 0.001) var desired_torso_y: float = 0.82
@export_range(0.0, 1.2, 0.001) var desired_pelvis_y: float = 0.99
@export_range(0.0, 1.3, 0.001) var desired_feet_y: float = 1.22
@export_range(0.0, 0.1, 0.001) var pelvis_crop_tolerance_above: float = 0.025
@export_range(0.0, 0.1, 0.001) var pelvis_crop_tolerance_below: float = 0.035
@export_range(0.0, 0.15, 0.001) var feet_crop_tolerance_above: float = 0.040
@export_range(0.0, 0.2, 0.001) var feet_crop_tolerance_below: float = 0.085
@export_range(0.0, 1.0, 0.01) var head_framing_weight: float = 0.72
@export_range(0.0, 1.0, 0.01) var torso_framing_weight: float = 0.18
@export_range(0.0, 1.0, 0.01) var pelvis_framing_weight: float = 0.28
@export_range(0.0, 1.0, 0.01) var feet_framing_weight: float = 0.24
@export var framing_gain: float = 1.45
@export var max_framing_height_correction: float = 1.00
@export var wall_escape_max_framing_height_correction: float = 0.70
@export var framing_deadzone: float = 0.003
@export var framing_probe_height: float = 0.10
@export var framing_probe_side: float = 0.10
@export var max_framing_side_correction: float = 0.0
@export var wall_escape_max_framing_side_correction: float = 0.0

@export_group("Terrain Crop Relaxation")
@export var terrain_full_relaxation_deg: float = 28.0
@export_range(0.0, 0.15, 0.001) var max_terrain_pelvis_reveal: float = 0.055

@export_group("Tight-space Framing")
@export var interior_distance: float = 2.30
@export var interior_height: float = 0.75
@export var interior_shoulder_offset: float = 0.0
@export_range(0.0, 1.0, 0.001) var interior_head_y: float = 0.68
@export_range(0.0, 1.0, 0.001) var interior_torso_y: float = 0.86
@export_range(0.0, 1.3, 0.001) var interior_pelvis_y: float = 1.15
@export var interior_state_response: float = 12.0
@export var interior_max_framing_height_correction: float = 0.55
@export var interior_view_pitch_bias_deg: float = 12.0
@export_range(0.0, 0.8, 0.01) var tight_space_compression_start: float = 0.10
@export_range(0.1, 0.95, 0.01) var tight_space_full_compression: float = 0.55
@export_range(0.0, 0.35, 0.001) var max_tight_space_pelvis_crop: float = 0.15
@export_range(0.0, 0.8, 0.01) var max_tight_space_extra_drop: float = 0.45
@export_range(0.0, 1.0, 0.01) var tight_space_pelvis_weight_scale: float = 0.25
@export_range(0.0, 1.0, 0.01) var tight_space_feet_weight_scale: float = 0.0
@export var ceiling_probe_distance: float = 2.25
@export var tight_space_response: float = 10.0
@export_range(0.0, 1.0, 0.001) var tight_space_head_y: float = 0.86
@export_range(0.0, 1.0, 0.01) var wall_escape_min_tightness: float = 0.35
@export_range(0.0, 1.0, 0.001) var wall_escape_head_x: float = 0.50
@export_range(0.0, 1.0, 0.001) var wall_escape_head_y: float = 0.84
@export_group("Collision / Excursion")
@export var collision_anchor_height: float = 1.95
# Sized to the 60-degree camera's near-plane diagonal plus margin. The former
# 0.24 m gameplay capsule was twice as conservative as the rendered lens and
# removed the close orbit needed to glide past a wall behind the operator.
@export var camera_collision_radius: float = 0.12
@export var collision_margin: float = 0.025
@export var min_distance: float = 2.20
@export var collision_close_distance: float = 1.35
@export var min_subject_camera_distance: float = 1.00
@export var min_camera_target_distance: float = 1.20
@export var max_rendered_target_distance: float = 5.50
@export var max_raise: float = 0.70
@export var max_collision_drop: float = 1.25
@export var max_drop: float = 0.35
@export var max_side_excursion: float = 0.0
@export var max_wall_escape_side_excursion: float = 0.0
@export var collision_max_radial_speed: float = 12.0
@export var collision_release_radial_response: float = 5.0
@export var collision_release_max_radial_speed: float = 4.5
@export var wall_context_enter_response: float = 12.0
@export var wall_context_exit_response: float = 4.5
@export var close_wall_crane_max_height: float = 3.75
@export var close_wall_crane_default_look_ahead: float = 3.0
@export var close_wall_crane_trigger_head_distance: float = 0.85
@export var close_wall_crane_enter_response: float = 9.0
@export var close_wall_crane_exit_response: float = 12.0
@export_range(0.0, 0.35, 0.001) var close_wall_reticle_max_x: float = 0.20
@export_range(0.0, 0.25, 0.001) var close_wall_reticle_max_y: float = 0.14
@export var close_wall_reticle_response: float = 16.0
@export var wall_branch_max_angular_speed_deg: float = 110.0
@export var wall_branch_max_linear_speed: float = 8.8
@export var wall_branch_transition_distance: float = 0.35
@export var post_solve_position_continuity_weight: float = 0.55
@export_range(0.05, 0.35, 0.01) var rendered_head_soft_limit_x: float = 0.05
@export_range(0.10, 0.48, 0.01) var rendered_head_hard_limit_x: float = 0.38
@export var composition_recovery_speed: float = 12.0

@export_group("Stance Framing")
@export var low_stance_head_height_start: float = 1.85
@export var low_stance_head_height_full: float = 0.75
@export var max_low_stance_camera_drop: float = 1.45
@export_range(0.0, 1.0, 0.01) var low_stance_pelvis_weight_scale: float = 0.08
@export_range(0.0, 1.0, 0.01) var low_stance_feet_weight_scale: float = 0.0

@export_group("Movement Follow")
@export var movement_lead_time: float = 0.0
@export var max_movement_lead: float = 0.0
@export var movement_lead_response: float = 5.0
@export var movement_return_response: float = 8.0
@export var movement_full_speed: float = 6.5
@export var movement_camera_response: float = 16.0
@export_range(0.0, 0.15, 0.001) var movement_head_x_shift: float = 0.0

@export_group("Response")
@export var obstruction_response: float = 24.0
@export var normal_return_response: float = 7.0

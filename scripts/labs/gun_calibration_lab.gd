class_name GunCalibrationLab
extends Node3D

## SOCOM-141 AAA Tactical Gunsmith & Biomechanical Arm Engine
## Full Anatomical Human Arm Biomechanics (Anatomical Hinge Elbow, Shoulder Ball-Socket, Palm Alignment)
## Left hand automatically finds and biomechanically grips Socket_LeftHand on any firearm.

const PS1_GAS_MASK_RIGGED_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const PS1_GAS_MASK_TEX := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const OperatorAnimationProfile := preload("res://scripts/player/operator_animation_profile.gd")
const WeaponAnimationProfile := preload("res://scripts/weapons/weapon_animation_profile.gd")
const WeaponReloadVisualTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")
const WeaponOwnershipContract := preload("res://scripts/player/weapon_ownership_contract.gd")
const OperatorPostureLayer := preload("res://scripts/player/operator_posture_layer.gd")
const ProceduralPoseProfile := preload("res://scripts/player/operator_procedural_pose_profile.gd")
const JointControlSchema := preload("res://scripts/player/operator_joint_control_schema.gd")
const GunsmithAnimationFrameEditorScript := preload("res://scripts/labs/gunsmith/gunsmith_animation_frame_editor.gd")
const GunsmithFrameTimelineScript := preload("res://scripts/labs/gunsmith/gunsmith_frame_timeline.gd")
const GunsmithBallisticsView := preload("res://scripts/labs/gunsmith/gunsmith_ballistics_view.gd")
const OperatorComposureScript := preload("res://scripts/weapons/operator_composure.gd")
const DynamicReticleScript := preload("res://scripts/ui/socom_dynamic_reticle.gd")
const TargetDummyScript := preload("res://scripts/combat/lab_leak_target_dummy.gd")
const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")
const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"
const HAND_GIZMO_ARROW_LENGTH := 0.12
const HAND_GIZMO_RING_RADIUS := 0.09
const WEAPON_GIZMO_ARROW_LENGTH := 0.10
const WEAPON_GIZMO_RING_RADIUS := 0.075
const GIZMO_CENTER_RADIUS := 0.018
const GIZMO_PICK_DISTANCE_PX := 28.0
const MUZZLE_RETICLE_LEAD_PX := 64.0
const BULLET_VELOCITY_PREVIEW_SECONDS := 0.004
const MIN_BARREL_AXIS_LENGTH_METERS := 0.02
const EYE_ORIGIN_FORWARD_METERS := 0.13
const EYE_ORIGIN_HEIGHT_METERS := 0.09
const EYE_SIGHT_PICK_LENGTH_METERS := 0.5
const TUNABLE_BODY_JOINTS := JointControlSchema.SELECTABLE_JOINTS

# A selected joint keeps full control. Small linked rotations continue through
# its anatomical parent so a correction does not form a hard hinge.
const JOINT_CHAIN_LINKS: Dictionary = {
	# Head lean forms a continuous arc. The head remains the primary control;
	# smaller corrections travel through the neck and upper spine.
	&"head": {&"neck": 0.55, &"spine2": 0.25, &"spine1": 0.10},
	&"neck": {&"spine2": 0.18},
	&"spine2": {&"spine1": 0.35, &"spine": 0.15},
	&"spine1": {&"spine": 0.25},
	&"left_upper_arm": {&"left_shoulder": 0.20},
	&"right_upper_arm": {&"right_shoulder": 0.20},
}

# Camera Rig
var cam_pivot: Node3D
var cam: Camera3D
var cam_target := Vector3(0.08, 1.24, 0.05)
var cam_distance: float = 0.95
var cam_pitch: float = -8.0
var cam_yaw: float = 55.0
var is_orbiting: bool = false
var is_panning: bool = false
var last_mouse_pos := Vector2.ZERO

# Trooper & Skeleton
var trooper_scale: float = 62.0
var trooper_node: Node3D
var composure_preview_dummy: Node3D
var composure_preview_active: bool = false
var skeleton: Skeleton3D
var animation_player: AnimationPlayer
var runtime_posture_layer: SocomOperatorPostureLayer
var preview_posture: StringName = &"STANDING"
var preview_hip_level_trim_deg: float = 4.5
var stance_buttons: Dictionary = {}

# Bone Indices
var left_arm_idx: int = -1
var left_forearm_idx: int = -1
var left_hand_idx: int = -1
var right_arm_idx: int = -1
var right_forearm_idx: int = -1
var right_hand_idx: int = -1
var head_idx: int = -1
var weapon_anchor_bone_idx: int = -1
var right_hand_ik: SkeletonIK3D

# Biomechanical Engine Parameters
var upper_arm_len: float = 0.315
var forearm_len: float = 0.312
var max_reach: float = 0.620
var left_palm_anchor_local := Vector3.ZERO
var right_palm_anchor_local := Vector3.ZERO
var support_hand_attached: bool = true
var right_elbow_pole_offset := Vector3.ZERO
var left_elbow_pole_offset := Vector3.ZERO
var elbow_poles_by_stance: Dictionary = {
	&"STANDING": {"right": Vector3.ZERO, "left": Vector3.ZERO},
	&"CROUCHED": {"right": Vector3.ZERO, "left": Vector3.ZERO},
	&"PRONE": {"right": Vector3.ZERO, "left": Vector3.ZERO},
}
var hand_poses_by_stance: Dictionary = {
	&"STANDING": {},
	&"CROUCHED": {},
	&"PRONE": {},
}
var stance_rebase_remaining: float = 0.0
var right_elbow_pole_marker: MeshInstance3D
var left_elbow_pole_marker: MeshInstance3D
var joint_debug_mesh := ImmediateMesh.new()
var joint_debug_instance: MeshInstance3D
var body_joint_markers: Dictionary = {}
var selected_body_joint: StringName = &"left_upper_arm"
var selected_joint_title: Label
var selected_joint_help: Label

# Tactical Grip Style Presets
enum GripStyle { CLASSIC_CRADLE, C_CLAMP_TACTICAL, MAGWELL_GRIP, VERTICAL_FOREGRIP, ANGLED_AFG }
var current_grip_style: GripStyle = GripStyle.CLASSIC_CRADLE

# Palm & Finger Posing (Underneath cradle vs C-Clamp vs Fist wrap)
var palm_roll: float = 0.0      # Underneath barrel vs Side vs Top C-clamp
var palm_pitch: float = 0.0     # Forward / backward hand tilt
var palm_yaw: float = 0.0       # Barrel alignment
var finger_curl: float = 0.65   # Grip wrap tightness around barrel
var thumb_wrap: float = 0.50    # Thumb wrap over rail

# Bone Attachments for Visual Gizmos
var ba_right_hand: BoneAttachment3D
var right_hand_dot: MeshInstance3D
var weapon_root: Node3D
var weapon_pivot: Node3D
var geometry_root: Node3D
var socket_root: Node3D
var weapon_mount_local := Transform3D.IDENTITY
var weapon_anchor_local := Transform3D.IDENTITY
var weapon_anchor_bone_origin := Vector3.ZERO
var weapon_anchor_ready: bool = false
var weapon_master_pose_initialized: bool = false
var _loaded_weapon_profile: Dictionary = {}
var current_weapon_mesh: Node3D
var current_silencer_mesh: Node3D
var current_scope_mesh: Node3D
var save_rig_button: Button
var play_latest_button: Button

const MAX_GRIP_OFFSET_RADIUS_METERS: float = 0.75
const MAX_HAND_TO_GRIP_ERROR_METERS: float = 0.40

# Unscaled World 3D Transform Gizmo for Hand
var hand_gizmo_world: Node3D
var hand_gizmo_center: MeshInstance3D
var gizmo_arrow_x: Node3D
var gizmo_arrow_y: Node3D
var gizmo_arrow_z: Node3D
var gizmo_ring_roll: MeshInstance3D
var gizmo_ring_pitch: MeshInstance3D
var gizmo_ring_yaw: MeshInstance3D

# Unscaled World 3D Transform Gizmo for Weapon Mount
var weapon_gizmo_world: Node3D
var weapon_gizmo_center: MeshInstance3D
var weapon_gizmo_arrow_x: Node3D
var weapon_gizmo_arrow_y: Node3D
var weapon_gizmo_arrow_z: Node3D
var weapon_gizmo_ring_roll: MeshInstance3D
var weapon_gizmo_ring_pitch: MeshInstance3D
var weapon_gizmo_ring_yaw: MeshInstance3D

# Weapon Sockets
var left_grip_marker: MeshInstance3D
var right_grip_marker: MeshInstance3D
var muzzle_marker: MeshInstance3D
var barrel_base_marker: MeshInstance3D
var ejection_marker: MeshInstance3D
var optic_marker: MeshInstance3D
var eye_sight_marker: Marker3D
var eye_sight_dot: MeshInstance3D

# Transform Calibration
var grip_offset_pos := Vector3.ZERO
var grip_offset_rot := Vector3.ZERO
var user_scale_multiplier: float = 1.0
var auto_normalized_scale: float = 1.0
var auto_grip_center_offset := Vector3.ZERO

# Socket Local Coordinates on Weapon Mesh
var left_grip_local_pos := Vector3(-0.04, -0.04, -0.30)
var right_grip_local_pos := Vector3.ZERO
var muzzle_local_pos := Vector3(0.0, 0.0, -0.68)
var barrel_base_local_pos := Vector3(0.0, 0.0, -0.12)
var ejection_local_pos := Vector3(0.05, 0.03, -0.10)
var optic_local_pos := Vector3(0.0, 0.08, -0.18)
var right_grip_profile_loaded := false
var right_grip_needs_initialization := false

# Interactive 3D Dragging
var interactive_dots: Array[Dictionary] = []
var hovered_dot_id: String = ""
var dragged_dot_id: String = ""
var authoring_pointer_down: bool = false
var mouse_fire_armed: bool = false
var drag_plane := Plane()
var drag_initial_world := Vector3.ZERO
var drag_offset_vector := Vector3.ZERO
var active_gizmo_id := "hand"
var gunsmith_camera_tracking_enabled: bool = false
var live_weapon_aim_enabled: bool = true
var live_weapon_yaw_deg: float = 0.0
var live_weapon_pitch_deg: float = 0.0
var live_aim_preview_toggle: CheckButton
var gunsmith_live_aim_rotation := Quaternion.IDENTITY
var show_joint_bubbles: bool = true
var isolate_selected_node: bool = false

# Ballistics & Firing
var weapon_name: String = "AssaultRifle_1"
var selected_category: String = "Assault Rifles"
var fire_rate_rpm: int = 650
var damage_per_shot: int = 34
var muzzle_velocity_mps: float = 715.0
var is_silenced: bool = false
var base_spread_deg: float = 0.28
var bloom_per_shot_deg: float = 0.32
var bloom_recovery_speed: float = 10.0
var max_recoil_bloom_deg: float = 2.4
var visual_recoil_pitch_deg: float = 0.0
var visual_recoil_back_m: float = 0.0
const VISUAL_RECOIL_PITCH_PER_SHOT_DEG := 1.15
const VISUAL_RECOIL_BACK_PER_SHOT_M := 0.010
const VISUAL_RECOIL_MAX_PITCH_DEG := 5.0
const VISUAL_RECOIL_MAX_BACK_M := 0.040
const VISUAL_RECOIL_RECOVERY := 17.0
var reticle_base_gap_px: float = 10.0
var reticle_max_gap_px: float = 46.0
var reticle_response_speed: float = 24.0
var reticle_shot_kick_px: float = 6.0
var reticle_shot_kick_return: float = 18.0
var reticle_maximum_shot_kick_px: float = 18.0
var current_bloom: float = 0.0
var fire_cooldown: float = 0.0
var burst_shot_count: int = 0
var composure := OperatorComposureScript.new()
var composure_preview_movement: float = 0.0
var composure_preview_turning: float = 0.0
var composure_opening_stress_multiplier: float = 0.28
var composure_graze_damage_scale: float = 0.38
var composure_readout: Label
var composure_profile_title: Label
var shared_hurtbox_scales: Dictionary = HurtboxProfile.load_scales()
var shared_hurtbox_geometry: Dictionary = HurtboxProfile.load_geometry()
var shared_custom_hitboxes: Array[Dictionary] = HurtboxProfile.load_custom_hitboxes()
var selected_hurtbox_region: StringName = &"torso"
var hurtbox_region_picker: OptionButton
var hurtbox_damage_type_picker: OptionButton
var delete_hitbox_button: Button
var hurtbox_edit_markers: Dictionary = {}
var hitbox_drag_offset_start := Vector3.ZERO
var fire_input_held: bool = false
var active_lab_tab_name := "Rig & Hands"
var current_aim_target := Vector3.ZERO
var is_reloading: bool = false
var weapon_owner_state: StringName = WeaponOwnershipContract.OWNER_WEAPON_MASTER
var support_hand_policy: StringName = WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
var action_weapon_follow_active: bool = false
var action_weapon_hand_offset := Transform3D.IDENTITY
var animation_frame_weapon_position_correction := Vector3.ZERO
var animation_frame_weapon_rotation_correction_deg := Vector3.ZERO
var frame_weapon_drag_position_start := Vector3.ZERO
var action_return_transform := Transform3D.IDENTITY
var action_recovery_start := Transform3D.IDENTITY
var action_recovery_duration: float = 0.14
var action_recovery_elapsed: float = action_recovery_duration
var active_reload_visual_slot: String = ""
var reload_magazine_proxy: MeshInstance3D
var reload_visual_state: String = WeaponReloadVisualTimeline.STATE_IN_WEAPON

# Weapon Skins
var camo_skins: Array[String] = [
	"Factory Classic (Wood & Steel)",
	"SOCOM Desert Tan (Crossroads)",
	"SOCOM Woodland OD (Frostfire)",
	"Midnight Spec-Ops (All Black)",
	"Arctic Whiteout (Winter Camo)",
	"Titanium & Carbon (Silver Steel)"
]
var selected_camo_idx: int = 0

# Target Range & Visuals
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
	"Revolvers": ["Revolver_1", "Revolver_2", "Revolver_3", "Revolver_4", "Revolver_5"]
}

var silencer_options: Array[String] = ["None", "Silencer_1", "Silencer_2", "Silencer_3", "Silencer_long", "Silencer_Short"]
var scope_options: Array[String] = ["None", "Scope_1", "Scope_2", "Scope_3"]

var selected_weapon_file: String = "AssaultRifle_1"
var selected_silencer: String = "None"
var selected_scope: String = "None"
var animation_catalog
var all_animation_entries: Array[Dictionary] = []
var all_animation_paths: Dictionary = {}
var handling_profile: Dictionary = {}
var handling_family_select: OptionButton
var animation_mapping_status: Label
var support_hand_toggle: CheckButton
var animation_slot_labels: Dictionary = {}
var animation_slot_selectors: Dictionary = {}
var animation_preview_token: int = 0
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
var animation_frame_last_applied: int = -1
var animation_edit_candidate_slot: String = ""
var animation_edit_candidate_clip: StringName = &""
var all_animation_select: OptionButton
var selected_animation_key: StringName = &""
var animation_hand_maps: Dictionary = {}
var animation_quality_status: Label
var animation_quality_results: RichTextLabel
var animation_quality_audit_running: bool = false
var animation_quality_sample_elapsed: float = 0.0
var last_animation_quality_audit: Dictionary = {}
var last_animation_autofix_previous_slots: Dictionary = {}
var animation_autofix_running: bool = false
var animation_autofix_undo_button: Button

# UI Sliders Map
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
var show_bullet_velocity: bool = true
var show_barrel_axis: bool = false
var show_camera_aim: bool = false
var show_eye_sight: bool = true
var show_last_shot: bool = false
var last_shot_origin := Vector3.ZERO
var last_shot_end := Vector3.ZERO
var rotation_panel: PanelContainer
var rotation_title_label: Label
var rotation_orbit_control: Control
var rotation_value_labels: Dictionary = {}
var rotation_pad_drag_axis := ""
var rotation_pad_hover_axis := ""
var reticle_bloom_radius: float = 12.0

func _ready() -> void:
	animation_catalog = OperatorAnimationProfile.new()
	animation_catalog.load_project_map()
	_scan_all_animation_assets()
	handling_profile = WeaponAnimationProfile.build_default(
		WeaponAnimationProfile.infer_family(weapon_name, selected_category),
		animation_catalog.clip_paths
	)
	_setup_studio_environment()
	_setup_trooper_and_rig()
	_setup_elbow_pole_visuals()
	_setup_body_joint_visuals()
	_setup_target_range()
	_setup_composure_target_preview()
	_load_weapon(selected_weapon_file)
	_build_studio_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var ek := event as InputEventKey
		if ek.keycode == KEY_S and (ek.ctrl_pressed or ek.meta_pressed):
			_request_save_everything()
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_R and not (ek.ctrl_pressed or ek.meta_pressed):
			_trigger_reload_animation()
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_1:
			_set_preview_posture(&"STANDING")
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_2:
			_set_preview_posture(&"CROUCHED")
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_3:
			_set_preview_posture(&"PRONE")
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_B:
			show_joint_bubbles = not show_joint_bubbles
			_update_body_joint_visuals()
			if hud_status:
				hud_status.text = "👁 Joint Bubbles: %s" % ("VISIBLE" if show_joint_bubbles else "HIDDEN")
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_I:
			isolate_selected_node = not isolate_selected_node
			_update_body_joint_visuals()
			if hud_status:
				hud_status.text = "🎯 Isolate Active Node: %s" % ("ON (Showing %s only)" % String(selected_body_joint) if isolate_selected_node else "OFF")
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (
			mb.button_index == MOUSE_BUTTON_LEFT
			and mb.pressed
			and save_rig_button != null
			and not save_rig_button.disabled
			and save_rig_button.get_global_rect().has_point(mb.position)
		):
			_cancel_3d_authoring_pointer()
			_request_save_everything()
			get_viewport().set_input_as_handled()
			return
		if _pointer_over_editor_ui(mb.position):
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				_cancel_3d_authoring_pointer()
			return
		var target_dot := dragged_dot_id if dragged_dot_id != "" else hovered_dot_id

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if target_dot.begins_with("body_joint:"):
				_select_body_joint(StringName(target_dot.trim_prefix("body_joint:")))
				_adjust_selected_joint_rotation(Vector3(0.0, 0.0, 2.0))
				get_viewport().set_input_as_handled()
				return
			elif target_dot == "left_ik":
				left_grip_local_pos.x = clampf(left_grip_local_pos.x + 0.015, -0.40, 1.20)
				_sync_markers()
				_update_slider_value("ik_x", left_grip_local_pos.x)
				get_viewport().set_input_as_handled()
				return
			elif target_dot == "right_grip":
				_adjust_weapon_rotation("yaw", 3.0)
				get_viewport().set_input_as_handled()
				return
			else:
				cam_distance = clampf(cam_distance - 0.08, 0.20, 3.5)
				_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if target_dot.begins_with("body_joint:"):
				_select_body_joint(StringName(target_dot.trim_prefix("body_joint:")))
				_adjust_selected_joint_rotation(Vector3(0.0, 0.0, -2.0))
				get_viewport().set_input_as_handled()
				return
			elif target_dot == "left_ik":
				left_grip_local_pos.x = clampf(left_grip_local_pos.x - 0.015, -0.40, 1.20)
				_sync_markers()
				_update_slider_value("ik_x", left_grip_local_pos.x)
				get_viewport().set_input_as_handled()
				return
			elif target_dot == "right_grip":
				_adjust_weapon_rotation("yaw", -3.0)
				get_viewport().set_input_as_handled()
				return
			else:
				cam_distance = clampf(cam_distance + 0.08, 0.20, 3.5)
				_update_camera()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			is_orbiting = mb.pressed
			last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			is_panning = mb.pressed
			last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# A mouse shot must start on empty range space. Never derive fire from
				# the global button state because Godot can sample that state before a
				# socket drag has claimed the press.
				mouse_fire_armed = false
				var hit_dot := _find_dot_under_mouse(mb.position)
				if hit_dot != "":
					authoring_pointer_down = true
					fire_input_held = false
					_pause_animation_frame_editor_for_authoring()
					if hit_dot.begins_with("body_joint:"):
						_select_body_joint(StringName(hit_dot.trim_prefix("body_joint:")))
					elif hit_dot.begins_with("hurtbox:"):
						_select_hurtbox_region(StringName(hit_dot.trim_prefix("hurtbox:")))
						hitbox_drag_offset_start = _hitbox_offset(selected_hurtbox_region)
					elif hit_dot == "left_ik":
						_set_active_gizmo("hand")
					elif hit_dot == "right_grip" or hit_dot == "weapon_mount":
						_set_active_gizmo("weapon")
						if hit_dot == "weapon_mount" and _editing_action_weapon_frame():
							frame_weapon_drag_position_start = animation_frame_weapon_position_correction
					dragged_dot_id = hit_dot
					var dot_mesh := _get_dot_mesh_by_id(hit_dot)
					if dot_mesh:
						drag_initial_world = dot_mesh.global_position
						var cam_norm := -cam.global_transform.basis.z.normalized()
						drag_plane = Plane(cam_norm, cam_norm.dot(drag_initial_world))
						var ray_orig := cam.project_ray_origin(mb.position)
						var ray_dir := cam.project_ray_normal(mb.position)
						var hit_pos = drag_plane.intersects_ray(ray_orig, ray_dir)
						if hit_pos != null:
							drag_offset_vector = drag_initial_world - hit_pos
						else:
							drag_offset_vector = Vector3.ZERO
						if hud_status:
							hud_status.text = (
								"👁 Drag eye sight: horizontal = yaw, vertical = pitch"
								if hit_dot == "eye_sight"
								else "🎯 Positioning %s (Left arm biomechanically auto-grips!)" % hit_dot
							)
					get_viewport().set_input_as_handled()
					return
				mouse_fire_armed = (
					active_lab_tab_name == "Reticle & Fire"
					and not animation_frame_editor.active
					and _preview_screen_rect().has_point(mb.position)
				)
			else:
				mouse_fire_armed = false
				authoring_pointer_down = false
				if dragged_dot_id != "":
					if hud_status:
						hud_status.text = "✅ %s locked!" % dragged_dot_id
					dragged_dot_id = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _pointer_over_editor_ui(mm.position) and dragged_dot_id == "":
			if hovered_dot_id != "":
				hovered_dot_id = ""
				_highlight_dot("")
			return
		if is_orbiting:
			cam_yaw -= mm.relative.x * 0.4
			cam_pitch = clampf(cam_pitch - mm.relative.y * 0.4, -85.0, 85.0)
			_update_camera()
		elif is_panning:
			var right := cam.global_transform.basis.x
			var up := cam.global_transform.basis.y
			cam_target -= (right * mm.relative.x - up * mm.relative.y) * 0.002
			_update_camera()
		elif dragged_dot_id != "":
			if dragged_dot_id.begins_with("body_joint:"):
				_adjust_selected_joint_rotation(Vector3(-mm.relative.y * 0.25, mm.relative.x * 0.25, 0.0))
			elif dragged_dot_id == "eye_sight":
				var eye_correction := _eye_sight_correction()
				_set_eye_sight_component(
					clampf(eye_correction.y + mm.relative.x * 0.25, -38.0, 38.0),
					&"yaw"
				)
				eye_correction = _eye_sight_correction()
				_set_eye_sight_component(
					clampf(eye_correction.x - mm.relative.y * 0.25, -24.0, 24.0),
					&"pitch"
				)
				_sync_eye_sight_controls()
				if hud_status:
					eye_correction = _eye_sight_correction()
					hud_status.text = "👁 Eye Pitch %.1f° • Yaw %.1f°" % [
						eye_correction.x,
						eye_correction.y,
					]
			elif dragged_dot_id == "left_ik_ring_roll":
				palm_roll = wrapf(palm_roll + mm.relative.x * 0.85, -180.0, 180.0)
				_update_slider_value("p_roll", palm_roll)
				if hud_status: hud_status.text = "🟡 Spinning Palm Roll: %.1f° (Underneath / C-Clamp)" % palm_roll
			elif dragged_dot_id == "left_ik_ring_pitch":
				palm_pitch = clampf(palm_pitch - mm.relative.y * 0.65, -90.0, 90.0)
				_update_slider_value("p_pitch", palm_pitch)
				if hud_status: hud_status.text = "🟣 Tilting Wrist Pitch: %.1f°" % palm_pitch
			elif dragged_dot_id == "left_ik_ring_yaw":
				palm_yaw = clampf(palm_yaw + mm.relative.x * 0.75, -90.0, 90.0)
				_update_slider_value("p_yaw", palm_yaw)
				if hud_status: hud_status.text = "🔷 Turning Palm Yaw: %.1f°" % palm_yaw
			elif dragged_dot_id == "left_ik_arrow_x":
				left_grip_local_pos.x = clampf(left_grip_local_pos.x + mm.relative.x * 0.003, -0.40, 1.20)
				_sync_markers()
				_update_slider_value("ik_x", left_grip_local_pos.x)
				if hud_status: hud_status.text = "🔴 Sliding Foregrip along Barrel (X): %.3f" % left_grip_local_pos.x
			elif dragged_dot_id == "left_ik_arrow_y":
				left_grip_local_pos.y = clampf(left_grip_local_pos.y - mm.relative.y * 0.003, -0.20, 0.20)
				_sync_markers()
				_update_slider_value("ik_y", left_grip_local_pos.y)
				if hud_status: hud_status.text = "🟢 Adjusting Hand Height (Y): %.3f" % left_grip_local_pos.y
			elif dragged_dot_id == "left_ik_arrow_z":
				left_grip_local_pos.z = clampf(left_grip_local_pos.z + mm.relative.x * 0.003, -0.20, 0.20)
				_sync_markers()
				_update_slider_value("ik_z", left_grip_local_pos.z)
				if hud_status: hud_status.text = "🔵 Adjusting Hand Side (Z): %.3f" % left_grip_local_pos.z
			elif dragged_dot_id == "weapon_ring_pitch":
				var pitch_value := _adjust_weapon_rotation("pitch", -mm.relative.y * 0.65)
				if hud_status: hud_status.text = "🟣 %s Pitch: %.1f°" % ["Frame Weapon" if _editing_action_weapon_frame() else "Weapon", pitch_value]
			elif dragged_dot_id == "weapon_ring_yaw":
				var yaw_value := _adjust_weapon_rotation("yaw", mm.relative.x * 0.75)
				if hud_status: hud_status.text = "🔷 %s Yaw: %.1f°" % ["Frame Weapon" if _editing_action_weapon_frame() else "Weapon", yaw_value]
			elif dragged_dot_id == "weapon_ring_roll":
				var roll_value := _adjust_weapon_rotation("roll", mm.relative.x * 0.85)
				if hud_status: hud_status.text = "🟡 %s Roll: %.1f°" % ["Frame Weapon" if _editing_action_weapon_frame() else "Weapon", roll_value]
			elif dragged_dot_id == "weapon_arrow_x":
				_adjust_weapon_translation("x", mm.relative.x * 0.0025)
			elif dragged_dot_id == "weapon_arrow_y":
				_adjust_weapon_translation("y", -mm.relative.y * 0.0025)
			elif dragged_dot_id == "weapon_arrow_z":
				_adjust_weapon_translation("z", mm.relative.x * 0.0025)
			else:
				var ray_orig := cam.project_ray_origin(mm.position)
				var ray_dir := cam.project_ray_normal(mm.position)
				var hit_pos = drag_plane.intersects_ray(ray_orig, ray_dir)
				if hit_pos != null:
					var new_world_pos: Vector3 = hit_pos + drag_offset_vector
					_apply_dot_world_drag(dragged_dot_id, new_world_pos)
		else:
			var hovered := _find_dot_under_mouse(mm.position)
			if hovered != hovered_dot_id:
				hovered_dot_id = hovered
				_highlight_dot(hovered_dot_id)

func _process(delta: float) -> void:
	if fire_cooldown > 0.0:
		fire_cooldown = maxf(0.0, fire_cooldown - delta)

	fire_input_held = (
		Input.is_key_pressed(KEY_SPACE)
		or (
			mouse_fire_armed
			and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
		)
	) and (
		not is_orbiting
		and not is_panning
		and not is_reloading
		and not authoring_pointer_down
		and dragged_dot_id == ""
	)
	_update_bloom_recovery(delta, fire_input_held)
	composure.advance(
		delta,
		composure_preview_movement,
		composure_preview_turning,
		_composure_stance()
	)
	if composure_preview_dummy != null and composure_preview_dummy.has_method("set_precision_core_debug"):
		composure_preview_dummy.call(
			"set_precision_core_debug",
			composure_preview_active,
			composure.get_precision_core_scale()
		)
	_update_composure_readout()

	if fire_input_held:
		if fire_cooldown <= 0.0:
			_fire_shot()

	if animation_player:
		if not animation_frame_editor.active or animation_frame_editor.playing:
			animation_player.advance(delta)
		if animation_frame_editor.active:
			_update_animation_frame_editor()
	if not weapon_master_pose_initialized:
		_initialize_weapon_master_pose()
	# Build the final authored + procedural hand pose before either weapon owner
	# consumes it. Reload/action follow must never trail the visible hand by one
	# update, and the ready anchor must use the same final posture sample.
	_apply_runtime_posture_preview()
	_update_action_weapon_ownership(delta)
	_update_reload_support_handoff()
	_update_weapon_master_anchor()
	_update_live_aim_weapon_pose()
	_update_visual_weapon_recoil(delta)

	_solve_trigger_hand_engine()
	_solve_biomechanical_arm_engine()
	_apply_hand_and_finger_posing()
	if skeleton:
		skeleton.force_update_all_bone_transforms()
	_update_reload_magazine_visual()
	_update_elbow_pole_visuals()
	_update_body_joint_visuals()
	_update_hurtbox_edit_markers()
	_update_eye_sight_marker()
	_update_animation_quality_readout(delta)

	if hand_gizmo_world and left_grip_marker and is_instance_valid(left_grip_marker):
		hand_gizmo_world.global_position = left_grip_marker.global_position
		if current_weapon_mesh:
			hand_gizmo_world.global_basis = current_weapon_mesh.global_basis.orthonormalized()

	if weapon_gizmo_world and weapon_pivot and is_instance_valid(weapon_pivot):
		weapon_gizmo_world.global_position = weapon_pivot.global_position
		if weapon_root:
			weapon_gizmo_world.global_basis = weapon_root.global_basis.orthonormalized()

	if dynamic_reticle and cam:
		current_aim_target = _camera_aim_sample().position
		var aim_sample := _muzzle_axis_sample()
		var total_spread := _current_total_spread_deg()
		dynamic_reticle.update_reticle_state(
			clampf(total_spread / maxf(max_recoil_bloom_deg, 0.001), 0.0, 1.0),
			bool(aim_sample.target_locked),
			_reticle_screen_position()
		)
	_update_fire_debug_lines()
	if reticle_canvas:
		reticle_canvas.queue_redraw()


func _update_bloom_recovery(delta: float, trigger_held: bool) -> void:
	if trigger_held:
		return
	if current_bloom > 0.0:
		current_bloom = maxf(0.0, current_bloom - bloom_recovery_speed * delta)
	if fire_cooldown <= 0.0:
		burst_shot_count = 0

var left_hand_ik: SkeletonIK3D

func _solve_trigger_hand_engine() -> void:
	if not skeleton or not right_hand_ik or not right_grip_marker or not is_instance_valid(right_grip_marker):
		return
	if not weapon_master_pose_initialized:
		return
	# Reload animation temporarily owns the firing hand and carries the weapon.
	# Solving the hand back to the ready-position gun here would freeze both.
	if weapon_owner_state == WeaponOwnershipContract.OWNER_ANIMATED_RIGHT_HAND:
		if right_hand_ik.is_running():
			right_hand_ik.stop()
		return
	# Weapon-driven contract: the orange trigger socket is authoritative and
	# the arm reaches it. Preserve the animation's natural wrist orientation;
	# copying the rifle's raw basis into the wrist caused the hand to corkscrew.
	var hand_pose := skeleton.get_bone_global_pose(right_hand_idx)
	var desired_basis := (skeleton.global_transform.basis * hand_pose.basis).orthonormalized()
	if _gunsmith_live_aim_active():
		# Apply the exact same world yaw/pitch delta to the animation-sampled wrist
		# and the weapon. Their authored relative grip stays intact in every stance.
		desired_basis = (
			Basis(gunsmith_live_aim_rotation) * desired_basis
		).orthonormalized()
	var skeleton_scale := skeleton.global_transform.basis.get_scale()
	var scaled_palm_anchor := Vector3(
		right_palm_anchor_local.x * skeleton_scale.x,
		right_palm_anchor_local.y * skeleton_scale.y,
		right_palm_anchor_local.z * skeleton_scale.z
	)
	var wrist_position := right_grip_marker.global_position - desired_basis * scaled_palm_anchor
	# Lock to the animation-sampled basis, not the rifle basis. This retains the
	# authored wrist pose while keeping the palm contact point exact.
	right_hand_ik.override_tip_basis = true
	# Imported Mixamo scales leave a small deterministic residual after one IK
	# pass, especially in prone. Correct the internal wrist target a few times;
	# the authored weapon socket never moves. This mirrors the gameplay solver
	# and keeps the editor preview continuous with the live character.
	var internal_wrist_position := wrist_position
	for _correction in range(4):
		right_hand_ik.target = Transform3D(desired_basis, internal_wrist_position)
		# Build the elbow bend plane from the sampled shoulder and current grip.
		# SkeletonIK3D expects this point in skeleton space, not a world direction.
		right_hand_ik.magnet = _right_elbow_magnet_for(internal_wrist_position)
		# AnimationPlayer is advanced manually in this lab. Solve immediately after
		# that animation sample so the next frame cannot overwrite the IK result.
		right_hand_ik.stop()
		right_hand_ik.start(true)
		skeleton.force_update_all_bone_transforms()
		var residual := right_grip_marker.global_position - _right_palm_contact_world()
		if residual.length() <= 0.001:
			break
		internal_wrist_position += residual
	if _gunsmith_live_aim_active():
		# SkeletonIK can keep the wrist position but reject a large prone tip-basis
		# turn. Apply the already bounded live-preview wrist transform for this frame
		# after the arm chain is solved, so the palm contact stays exact.
		var desired_hand_world := Transform3D(desired_basis, wrist_position)
		var desired_hand_local := skeleton.global_transform.affine_inverse() * desired_hand_world
		var current_hand_pose := skeleton.get_bone_global_pose(right_hand_idx)
		desired_hand_local.basis = desired_hand_local.basis.orthonormalized().scaled(
			current_hand_pose.basis.get_scale()
		)
		skeleton.set_bone_global_pose_override(
			right_hand_idx,
			desired_hand_local,
			1.0,
			false
		)
		skeleton.force_update_all_bone_transforms()

func _right_hand_world_transform() -> Transform3D:
	if not skeleton or right_hand_idx < 0:
		return Transform3D.IDENTITY
	return skeleton.global_transform * skeleton.get_bone_global_pose(right_hand_idx)


func _right_hand_grip_world_transform() -> Transform3D:
	var hand_world := _right_hand_world_transform()
	if skeleton == null:
		return hand_world
	var hand_basis := hand_world.basis.orthonormalized()
	return Transform3D(hand_basis, _right_palm_contact_world())


func _left_hand_world_transform() -> Transform3D:
	if not skeleton or left_hand_idx < 0:
		return Transform3D.IDENTITY
	return skeleton.global_transform * skeleton.get_bone_global_pose(left_hand_idx)

func _begin_action_weapon_follow() -> void:
	if not weapon_root or not skeleton or right_hand_idx < 0:
		return
	var hand_world := _right_hand_grip_world_transform()
	if right_grip_marker != null:
		# Start every authored action from exact trigger contact. Socket edits and a
		# newly selected clip can otherwise leave a stale ready-hand solve in the
		# frame where ownership changes.
		weapon_root.global_position += hand_world.origin - right_grip_marker.global_position
	action_return_transform = weapon_root.global_transform
	action_weapon_hand_offset = hand_world.affine_inverse() * weapon_root.global_transform
	action_weapon_follow_active = true
	action_recovery_elapsed = action_recovery_duration
	if right_hand_ik and right_hand_ik.is_running():
		right_hand_ik.stop()

func _finish_action_weapon_follow() -> void:
	if not action_weapon_follow_active:
		return
	action_weapon_follow_active = false
	action_recovery_start = weapon_root.global_transform if weapon_root else Transform3D.IDENTITY
	action_recovery_elapsed = 0.0

func _update_action_weapon_ownership(delta: float) -> void:
	if not weapon_root:
		return
	if action_weapon_follow_active:
		# A full-body authored action drives the right hand; this invariant offset
		# makes the rifle travel with that hand. The support-hand policy separately
		# decides whether the left arm stays animated or is deliberately free.
		weapon_root.global_transform = (
			_right_hand_grip_world_transform()
			* _animation_frame_weapon_correction_transform()
			* action_weapon_hand_offset
		)
		if right_grip_marker != null:
			weapon_root.global_position += (
				_right_palm_contact_world() - right_grip_marker.global_position
			)
		return
	if action_recovery_elapsed < action_recovery_duration:
		action_recovery_elapsed = minf(action_recovery_elapsed + delta, action_recovery_duration)
		var amount := action_recovery_elapsed / maxf(action_recovery_duration, 0.001)
		amount = amount * amount * (3.0 - 2.0 * amount)
		weapon_root.global_transform = action_recovery_start.interpolate_with(
			_weapon_anchor_target_transform(),
			amount
		)


func _editing_action_weapon_frame() -> bool:
	return (
		animation_frame_editor != null
		and animation_frame_editor.active
		and weapon_owner_state == WeaponOwnershipContract.OWNER_ANIMATED_RIGHT_HAND
	)


func _animation_frame_weapon_correction_transform() -> Transform3D:
	if not _editing_action_weapon_frame():
		return Transform3D.IDENTITY
	return Transform3D(
		Basis.from_euler(
			_degrees_to_radians_vector(animation_frame_weapon_rotation_correction_deg),
			EULER_ORDER_YXZ
		),
		animation_frame_weapon_position_correction
	)


func _adjust_weapon_rotation(axis_name: String, delta_degrees: float) -> float:
	var value := 0.0
	if _editing_action_weapon_frame():
		if axis_name == "pitch":
			animation_frame_weapon_rotation_correction_deg.x = wrapf(
				animation_frame_weapon_rotation_correction_deg.x + delta_degrees,
				-180.0,
				180.0
			)
			value = animation_frame_weapon_rotation_correction_deg.x
		elif axis_name == "yaw":
			animation_frame_weapon_rotation_correction_deg.y = wrapf(
				animation_frame_weapon_rotation_correction_deg.y + delta_degrees,
				-180.0,
				180.0
			)
			value = animation_frame_weapon_rotation_correction_deg.y
		else:
			animation_frame_weapon_rotation_correction_deg.z = wrapf(
				animation_frame_weapon_rotation_correction_deg.z + delta_degrees,
				-180.0,
				180.0
			)
			value = animation_frame_weapon_rotation_correction_deg.z
	else:
		if axis_name == "pitch":
			grip_offset_rot.x = wrapf(grip_offset_rot.x + delta_degrees, -180.0, 180.0)
			value = grip_offset_rot.x
		elif axis_name == "yaw":
			grip_offset_rot.y = wrapf(grip_offset_rot.y + delta_degrees, -180.0, 180.0)
			value = grip_offset_rot.y
		else:
			grip_offset_rot.z = wrapf(grip_offset_rot.z + delta_degrees, -180.0, 180.0)
			value = grip_offset_rot.z
		_sync_weapon_transform()
		_update_slider_value("rot_" + axis_name, value)
	_refresh_rotation_dials()
	return value


func _adjust_weapon_translation(axis_name: String, delta_meters: float) -> float:
	var value := 0.0
	if _editing_action_weapon_frame():
		if axis_name == "x":
			animation_frame_weapon_position_correction.x = clampf(
				animation_frame_weapon_position_correction.x + delta_meters, -0.25, 0.25
			)
			value = animation_frame_weapon_position_correction.x
		elif axis_name == "y":
			animation_frame_weapon_position_correction.y = clampf(
				animation_frame_weapon_position_correction.y + delta_meters, -0.25, 0.25
			)
			value = animation_frame_weapon_position_correction.y
		else:
			animation_frame_weapon_position_correction.z = clampf(
				animation_frame_weapon_position_correction.z + delta_meters, -0.25, 0.25
			)
			value = animation_frame_weapon_position_correction.z
	else:
		if axis_name == "x":
			grip_offset_pos.x = clampf(grip_offset_pos.x + delta_meters, -0.25, 0.25)
			value = grip_offset_pos.x
		elif axis_name == "y":
			grip_offset_pos.y = clampf(grip_offset_pos.y + delta_meters, -0.25, 0.25)
			value = grip_offset_pos.y
		else:
			grip_offset_pos.z = clampf(grip_offset_pos.z + delta_meters, -0.25, 0.25)
			value = grip_offset_pos.z
		_sync_weapon_translation()
		_update_slider_value("grip_" + axis_name, value)
	return value


func _active_reload_timeline() -> Dictionary:
	if active_reload_visual_slot.is_empty():
		return {}
	return WeaponReloadVisualTimeline.ensure_profile_timeline(
		handling_profile,
		active_reload_visual_slot,
		_active_reload_frame_count()
	)


func _active_reload_frame_count() -> int:
	if animation_frame_editor.active:
		return animation_frame_editor.frame_count()
	if animation_player and animation_player.current_animation != &"":
		var animation := animation_player.get_animation(animation_player.current_animation)
		if animation:
			return maxi(1, int(round(animation.length * GunsmithAnimationFrameEditorScript.DEFAULT_FPS)))
	return 1


func _active_reload_frame_index() -> int:
	if animation_frame_editor.active:
		return animation_frame_editor.frame_index()
	if animation_player:
		return maxi(0, int(round(
			animation_player.current_animation_position
			* GunsmithAnimationFrameEditorScript.DEFAULT_FPS
		)))
	return 0


func _update_reload_support_handoff() -> void:
	if not is_reloading or active_reload_visual_slot.is_empty():
		return
	var timeline := _active_reload_timeline()
	var events: Dictionary = timeline.get("events", {})
	support_hand_policy = (
		WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
		if WeaponReloadVisualTimeline.support_hand_should_regrip(
			events,
			_active_reload_frame_index()
		)
		else WeaponOwnershipContract.SUPPORT_FREE
	)


func _update_reload_magazine_visual() -> void:
	if reload_magazine_proxy == null:
		return
	if not is_reloading or active_reload_visual_slot.is_empty() or skeleton == null:
		reload_magazine_proxy.visible = false
		return
	var timeline := _active_reload_timeline()
	var events: Dictionary = timeline.get("events", {})
	reload_visual_state = WeaponReloadVisualTimeline.state_at_frame(
		events,
		_active_reload_frame_index()
	)
	reload_magazine_proxy.visible = WeaponReloadVisualTimeline.magazine_is_in_left_hand(
		reload_visual_state
	)
	if not reload_magazine_proxy.visible:
		return
	var offset: Dictionary = timeline.get("magazine_hand_offset", {})
	var position := _vector_from_data(
		offset.get("position", {}),
		Vector3(0.0, -0.075, 0.018)
	)
	var rotation_degrees := _vector_from_data(
		offset.get("rotation_degrees", {}),
		Vector3(8.0, 0.0, 90.0)
	)
	var hand_world := _left_hand_world_transform()
	var hand_clean := Transform3D(hand_world.basis.orthonormalized(), hand_world.origin)
	reload_magazine_proxy.global_transform = hand_clean * Transform3D(
		Basis.from_euler(Vector3(
			deg_to_rad(rotation_degrees.x),
			deg_to_rad(rotation_degrees.y),
			deg_to_rad(rotation_degrees.z)
		)),
		position
	)

func _right_elbow_magnet_for(wrist_world: Vector3) -> Vector3:
	if not skeleton or right_arm_idx < 0:
		return Vector3.ZERO
	var desired_world := _right_elbow_pole_world(wrist_world)
	return skeleton.global_transform.affine_inverse() * desired_world


func _right_elbow_pole_base_world(wrist_world: Vector3) -> Vector3:
	var shoulder_world := (skeleton.global_transform * skeleton.get_bone_global_pose(right_arm_idx)).origin
	var midpoint := (shoulder_world + wrist_world) * 0.5
	var body_right := skeleton.global_transform.basis.x.normalized()
	var body_up := skeleton.global_transform.basis.y.normalized()
	var body_forward := skeleton.global_transform.basis.z.normalized()
	return midpoint - body_right * 0.28 - body_up * 0.08 + body_forward * 0.10


func _right_elbow_pole_world(wrist_world: Vector3) -> Vector3:
	var body_basis := skeleton.global_transform.basis.orthonormalized()
	return _right_elbow_pole_base_world(wrist_world) + body_basis * right_elbow_pole_offset

func _solve_biomechanical_arm_engine() -> void:
	if not skeleton or not left_grip_marker or not is_instance_valid(left_grip_marker): return
	if not left_hand_ik: return
	if not weapon_master_pose_initialized: return
	if support_hand_policy != WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON or not support_hand_attached:
		if left_hand_ik.is_running():
			left_hand_ik.stop()
		return

	# Pin the visible center of the palm to the grip socket. The IK tip is the
	# wrist bone, so rotating that bone without this offset makes the hand orbit
	# away from the gun even though the mathematical wrist target is correct.
	var palm_rot := Basis.from_euler(Vector3(deg_to_rad(palm_pitch), deg_to_rad(palm_yaw), deg_to_rad(palm_roll)))
	var desired_global_basis := (left_grip_marker.global_transform.basis.orthonormalized() * palm_rot).orthonormalized()
	var skeleton_scale := skeleton.global_transform.basis.get_scale()
	var scaled_palm_anchor := Vector3(
		left_palm_anchor_local.x * skeleton_scale.x,
		left_palm_anchor_local.y * skeleton_scale.y,
		left_palm_anchor_local.z * skeleton_scale.z
	)
	var wrist_global_position := left_grip_marker.global_position - desired_global_basis * scaled_palm_anchor

	# SkeletonIK3D.target is a world transform. The solver performs its own
	# conversion into skeleton space; pre-converting here displaced the wrist.
	left_hand_ik.target = Transform3D(desired_global_basis, wrist_global_position)
	left_hand_ik.override_tip_basis = true

	# Maintain an anatomical support-arm triangle from the sampled shoulder to
	# the live foregrip. Grip styles only adjust the size/height of that triangle.
	left_hand_ik.magnet = _left_elbow_magnet_for(wrist_global_position)

	# Solve against the same animation sample immediately. Leaving this solver
	# running asynchronously let the next clip frame overwrite the palm first,
	# which caused visible grip lag and ignored the intended elbow plane.
	left_hand_ik.stop()
	left_hand_ik.start(true)
	skeleton.force_update_all_bone_transforms()

func _left_elbow_magnet_for(wrist_world: Vector3) -> Vector3:
	if not skeleton or left_arm_idx < 0:
		return Vector3.ZERO
	var desired_world := _left_elbow_pole_world(wrist_world)
	return skeleton.global_transform.affine_inverse() * desired_world


func _left_elbow_pole_base_world(wrist_world: Vector3) -> Vector3:
	var shoulder_world := (skeleton.global_transform * skeleton.get_bone_global_pose(left_arm_idx)).origin
	var midpoint := (shoulder_world + wrist_world) * 0.5
	var body_right := skeleton.global_transform.basis.x.normalized()
	var body_up := skeleton.global_transform.basis.y.normalized()
	var body_forward := skeleton.global_transform.basis.z.normalized()
	var outward := 0.38
	var downward := 0.08
	var forward := 0.10
	match current_grip_style:
		GripStyle.CLASSIC_CRADLE:
			outward = 0.38; downward = 0.10; forward = 0.08
		GripStyle.C_CLAMP_TACTICAL:
			outward = 0.46; downward = 0.03; forward = 0.14
		GripStyle.MAGWELL_GRIP:
			outward = 0.30; downward = 0.12; forward = 0.06
		GripStyle.VERTICAL_FOREGRIP:
			outward = 0.34; downward = 0.11; forward = 0.08
		GripStyle.ANGLED_AFG:
			outward = 0.40; downward = 0.08; forward = 0.12

	# Dynamic anatomical stabilization: when palm is rolled upside-down / cradle, drop elbow downward
	var roll_rad := deg_to_rad(palm_roll)
	var palm_upright_factor := (cos(roll_rad) + 1.0) * 0.5
	outward = lerpf(0.24, outward, palm_upright_factor)
	downward = lerpf(0.18, downward, palm_upright_factor)

	return midpoint + body_right * outward - body_up * downward + body_forward * forward


func _left_elbow_pole_world(wrist_world: Vector3) -> Vector3:
	var body_basis := skeleton.global_transform.basis.orthonormalized()
	return _left_elbow_pole_base_world(wrist_world) + body_basis * left_elbow_pole_offset


func _update_stance_weapon_rebase(delta: float) -> void:
	# Compatibility seam for old callers. Never add an unsaved world-space
	# offset after a stance profile restores the calibrated local transform.
	stance_rebase_remaining = maxf(0.0, stance_rebase_remaining - delta)

func _apply_hand_and_finger_posing() -> void:
	if not skeleton or support_hand_policy != WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON or not support_hand_attached: return

	# Wrist orientation is owned exclusively by the IK target basis. Applying the
	# same palm rotation here again makes the hand twist twice and break its grip.
	# Fingers remain a visual layer below the IK-controlled wrist.
	var idx1 := skeleton.find_bone("mixamorig_LeftHandIndex1")
	var idx2 := skeleton.find_bone("mixamorig_LeftHandIndex2")
	var idx3 := skeleton.find_bone("mixamorig_LeftHandIndex3")
	var curl_rad := deg_to_rad(finger_curl * 80.0)

	if idx1 >= 0: skeleton.set_bone_pose_rotation(idx1, Quaternion(Vector3.RIGHT, curl_rad * 0.45))
	if idx2 >= 0: skeleton.set_bone_pose_rotation(idx2, Quaternion(Vector3.RIGHT, curl_rad * 0.35))
	if idx3 >= 0: skeleton.set_bone_pose_rotation(idx3, Quaternion(Vector3.RIGHT, curl_rad * 0.20))

	# Thumb Wrap
	var th1 := skeleton.find_bone("mixamorig_LeftHandThumb1")
	var th2 := skeleton.find_bone("mixamorig_LeftHandThumb2")
	var th3 := skeleton.find_bone("mixamorig_LeftHandThumb3")
	var thumb_rad := deg_to_rad(thumb_wrap * 65.0)

	if th1 >= 0: skeleton.set_bone_pose_rotation(th1, Quaternion(Vector3.FORWARD, thumb_rad * 0.5) * Quaternion(Vector3.UP, thumb_rad * 0.3))
	if th2 >= 0: skeleton.set_bone_pose_rotation(th2, Quaternion(Vector3.FORWARD, thumb_rad * 0.5))

func _trigger_reload_animation() -> void:
	_preview_animation_slot("reload_standing")


func _posture_fire_slot() -> String:
	match preview_posture:
		&"CROUCHED":
			return "fire_crouched"
		&"PRONE":
			return "fire_prone"
		_:
			return "fire_standing"


func _preview_fire_animation() -> void:
	# A Gunsmith shot opens the same posture-specific clip that gameplay uses.
	# Repeated shots restart that clip while keeping its frame editor attached.
	var slot_name := _posture_fire_slot()
	var slots: Dictionary = handling_profile.get("animation_slots", {})
	var clip_name := StringName(slots.get(slot_name, ""))
	if clip_name == &"" or not _ensure_preview_clip(clip_name):
		if hud_status:
			hud_status.text = "⚠ Map an animation to %s before firing." % slot_name
		return
	_set_animation_edit_candidate(slot_name, clip_name)
	if not animation_frame_editor.active or animation_frame_editor.clip_name != clip_name:
		_enter_animation_frame_editor(slot_name, clip_name)
	if not animation_frame_editor.active or animation_player == null:
		return
	selected_animation_key = clip_name
	animation_frame_editor.playing = true
	animation_frame_editor.set_time(0.0)
	animation_frame_last_applied = -1
	animation_player.play(clip_name, 0.0)
	animation_player.seek(0.0, true)
	_apply_animation_frame_pose_for_current_time()
	_refresh_animation_frame_editor_ui()
	if hud_status:
		hud_status.text = "💥 %s fired. Its editable reaction clip is open on the frame ruler." % clip_name

func _set_support_hand_attached(attached: bool, announce: bool = true) -> void:
	support_hand_attached = attached
	if left_hand_ik:
		if attached and support_hand_policy == WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON:
			if not left_hand_ik.is_running():
				left_hand_ik.start()
		elif left_hand_ik.is_running():
			left_hand_ik.stop()
	if support_hand_toggle and support_hand_toggle.button_pressed != attached:
		support_hand_toggle.set_pressed_no_signal(attached)
	if announce and hud_status:
		hud_status.text = "🤲 Support hand attached to foregrip" if attached else "✋ Support hand released; firing hand keeps the weapon anchored"


func _build_handling_animation_ui(parent: VBoxContainer) -> void:
	parent.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "3. Handling & Animations"
	title.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	parent.add_child(title)

	var family_row := HBoxContainer.new()
	parent.add_child(family_row)
	var family_label := Label.new()
	family_label.text = "Handling:"
	family_label.custom_minimum_size.x = 90
	family_row.add_child(family_label)
	handling_family_select = OptionButton.new()
	for family_name in WeaponAnimationProfile.FAMILIES:
		handling_family_select.add_item(family_name.replace("_", " ").capitalize())
		handling_family_select.set_item_metadata(handling_family_select.item_count - 1, family_name)
	handling_family_select.item_selected.connect(_on_handling_family_selected)
	family_row.add_child(handling_family_select)

	var auto_button := Button.new()
	auto_button.text = "⚡ Auto-Build Animation Set"
	auto_button.tooltip_text = "Choose the safest imported clips for this weapon family."
	auto_button.pressed.connect(_auto_build_animation_set)
	parent.add_child(auto_button)

	_add_slider(
		parent,
		"preview_hip_level",
		"Preview Hip Level",
		0.0,
		10.0,
		preview_hip_level_trim_deg,
		func(value: float): preview_hip_level_trim_deg = value
	)
	var hip_help := Label.new()
	hip_help.text = "Additive preview correction only — source animation clips are never rewritten."
	hip_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hip_help.add_theme_font_size_override("font_size", 10)
	parent.add_child(hip_help)

	var clip_names: Array = animation_catalog.clip_paths.keys() if animation_catalog else []
	clip_names.sort_custom(func(a, b): return String(a).naturalnocasecmp_to(String(b)) < 0)
	for slot_name in WeaponAnimationProfile.SLOT_ORDER:
		var row := HBoxContainer.new()
		parent.add_child(row)
		var slot_label := Label.new()
		slot_label.text = String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name))
		slot_label.custom_minimum_size.x = 112
		slot_label.tooltip_text = slot_name
		row.add_child(slot_label)
		animation_slot_labels[slot_name] = slot_label

		var selector := OptionButton.new()
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.add_item("— missing —")
		selector.set_item_metadata(0, "")
		for raw_clip_name in clip_names:
			var clip_name := String(raw_clip_name)
			selector.add_item(clip_name)
			selector.set_item_metadata(selector.item_count - 1, clip_name)
		selector.item_selected.connect(_on_animation_slot_selected.bind(slot_name, selector))
		row.add_child(selector)
		animation_slot_selectors[slot_name] = selector

		var frames_button := Button.new()
		frames_button.name = "AnimationFrames_%s" % slot_name
		frames_button.text = "✎ Frames"
		frames_button.tooltip_text = "Open this exact action at frame 0, then step, play, and save additive rig corrections"
		frames_button.pressed.connect(_edit_animation_slot.bind(slot_name))
		row.add_child(frames_button)

	animation_mapping_status = Label.new()
	animation_mapping_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_mapping_status.add_theme_font_size_override("font_size", 10)
	parent.add_child(animation_mapping_status)

	var audit_title := Label.new()
	audit_title.text = "Animation Compatibility Audit"
	audit_title.tooltip_text = "Preview any imported clip and measure how much the weapon/hand rig loses quality."
	audit_title.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	parent.add_child(audit_title)
	var all_clips_row := HBoxContainer.new()
	parent.add_child(all_clips_row)
	all_animation_select = OptionButton.new()
	all_animation_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in all_animation_entries:
		all_animation_select.add_item(String(entry.get("display", entry.get("key", "animation"))))
		all_animation_select.set_item_metadata(
			all_animation_select.item_count - 1,
			String(entry.get("key", ""))
		)
	all_clips_row.add_child(all_animation_select)
	var open_frames_button := Button.new()
	open_frames_button.name = "OpenCatalogAnimationFrames"
	open_frames_button.text = "✎ Open Frames"
	open_frames_button.tooltip_text = "Open this raw clip at frame 0 in the frame pose editor"
	open_frames_button.pressed.connect(_edit_selected_catalog_animation)
	all_clips_row.add_child(open_frames_button)
	var save_clip_hands_button := Button.new()
	save_clip_hands_button.text = "💾 Map Both Hands to This Clip"
	save_clip_hands_button.tooltip_text = "Store the trigger-hand grip, support-hand grip, weapon mount, wrist pose, and finger pose for this exact imported animation. Ctrl/Cmd+S writes every map into the weapon profile."
	save_clip_hands_button.pressed.connect(_save_selected_animation_hand_map)
	parent.add_child(save_clip_hands_button)
	_build_animation_frame_editor_ui(parent)

	var audit_button := Button.new()
	audit_button.text = "🔎 Audit All Equipped States"
	audit_button.tooltip_text = "Automatically play every mapped weapon state and grade hand drift and gun travel."
	audit_button.pressed.connect(_audit_all_equipped_animation_states)
	var repair_row := HBoxContainer.new()
	parent.add_child(repair_row)
	repair_row.add_child(audit_button)
	var autofix_button := Button.new()
	autofix_button.text = "✨ Auto-Fix Failed States"
	autofix_button.tooltip_text = "Test compatible runtime clips and replace a failing slot only when the measured score clearly improves."
	autofix_button.pressed.connect(_auto_fix_failed_animation_states)
	repair_row.add_child(autofix_button)
	animation_autofix_undo_button = Button.new()
	animation_autofix_undo_button.text = "↶ Undo Fix"
	animation_autofix_undo_button.disabled = true
	animation_autofix_undo_button.pressed.connect(_undo_animation_autofix)
	repair_row.add_child(animation_autofix_undo_button)
	animation_quality_status = Label.new()
	animation_quality_status.text = "Quality: waiting for an animation sample"
	animation_quality_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_quality_status.add_theme_font_size_override("font_size", 10)
	parent.add_child(animation_quality_status)
	animation_quality_results = RichTextLabel.new()
	animation_quality_results.custom_minimum_size.y = 132
	animation_quality_results.fit_content = false
	animation_quality_results.scroll_active = true
	animation_quality_results.text = "Run the equipped-state audit to compare every firing, reload, and stance clip."
	parent.add_child(animation_quality_results)
	_refresh_handling_ui()


func _build_animation_frame_editor_ui(parent: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "FRAME POSE EDITOR"
	title.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	parent.add_child(title)
	animation_frame_editor_title = Label.new()
	animation_frame_editor_title.text = "Select Frames beside an animation state."
	animation_frame_editor_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	animation_frame_editor_title.add_theme_font_size_override("font_size", 10)
	parent.add_child(animation_frame_editor_title)
	var help := Label.new()
	help.text = "Click Frames for an action to open its lifecycle at frame 0. The green barrel-base → muzzle line is the weapon axis. Orange weapon edits become clip-local frame keys; they do not change the shared gun mount."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	help.add_theme_font_size_override("font_size", 10)
	parent.add_child(help)
	_build_animation_frame_timeline_overlay()


func _build_animation_frame_timeline_overlay() -> void:
	if animation_frame_panel != null or overlay == null:
		return
	animation_frame_panel = PanelContainer.new()
	animation_frame_panel.name = "GunsmithFrameTimelinePanel"
	animation_frame_panel.anchor_left = 0.37
	animation_frame_panel.anchor_top = 1.0
	animation_frame_panel.anchor_right = 1.0
	animation_frame_panel.anchor_bottom = 1.0
	animation_frame_panel.offset_left = 0.0
	animation_frame_panel.offset_top = -184.0
	animation_frame_panel.offset_right = -16.0
	animation_frame_panel.offset_bottom = -16.0
	# Keep the frame ruler visible. Editing must be discoverable without finding
	# a small per-slot pencil button in the scrolling sidebar.
	animation_frame_panel.visible = true
	overlay.add_child(animation_frame_panel)

	var container := VBoxContainer.new()
	animation_frame_panel.add_child(container)
	animation_frame_readout = Label.new()
	animation_frame_readout.text = "Frame —"
	animation_frame_readout.add_theme_font_size_override("font_size", 11)
	container.add_child(animation_frame_readout)
	animation_frame_timeline = GunsmithFrameTimelineScript.new()
	animation_frame_timeline.name = "AnimationFrameLifecycle"
	animation_frame_timeline.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	animation_frame_timeline.frame_scrubbed.connect(_seek_animation_frame_index)
	container.add_child(animation_frame_timeline)

	var controls := HBoxContainer.new()
	container.add_child(controls)
	animation_frame_edit_button = Button.new()
	animation_frame_edit_button.text = "✎ Edit Current Animation"
	animation_frame_edit_button.tooltip_text = "Pause and edit the explicitly selected reaction clip. This does not close the frame editor."
	animation_frame_edit_button.pressed.connect(_toggle_current_animation_frame_editor)
	controls.add_child(animation_frame_edit_button)
	var previous_button := Button.new()
	previous_button.text = "◀ Frame"
	previous_button.pressed.connect(_step_animation_frame_editor.bind(-1))
	controls.add_child(previous_button)
	animation_frame_edit_controls.append(previous_button)
	animation_frame_play_button = Button.new()
	animation_frame_play_button.text = "▶ Play"
	animation_frame_play_button.pressed.connect(_toggle_animation_frame_editor_playback)
	controls.add_child(animation_frame_play_button)
	animation_frame_edit_controls.append(animation_frame_play_button)
	var next_button := Button.new()
	next_button.text = "Frame ▶"
	next_button.pressed.connect(_step_animation_frame_editor.bind(1))
	controls.add_child(next_button)
	animation_frame_edit_controls.append(next_button)
	var capture_button := Button.new()
	capture_button.name = "SetAnimationCorrectionKey"
	capture_button.text = "◆ Set Correction Key"
	capture_button.tooltip_text = "Save the current correction here. It holds forward and blends toward the next key."
	capture_button.pressed.connect(_capture_animation_frame_pose_key)
	controls.add_child(capture_button)
	animation_frame_edit_controls.append(capture_button)
	var save_apply_button := Button.new()
	save_apply_button.name = "SaveApplyAnimationRig"
	save_apply_button.text = "💾 Save + Apply Rig"
	save_apply_button.tooltip_text = "Capture this frame key, save the weapon profile, and equip the corrections on the gameplay rig"
	save_apply_button.pressed.connect(_save_weapon_config)
	controls.add_child(save_apply_button)
	animation_frame_edit_controls.append(save_apply_button)

	reload_event_controls_row = HBoxContainer.new()
	reload_event_controls_row.name = "ReloadLifecycleControls"
	container.add_child(reload_event_controls_row)
	reload_event_status = Label.new()
	reload_event_status.text = "RELOAD VISUALS"
	reload_event_status.custom_minimum_size.x = 178.0
	reload_event_status.add_theme_font_size_override("font_size", 10)
	reload_event_controls_row.add_child(reload_event_status)
	for event_name in WeaponReloadVisualTimeline.EVENT_ORDER:
		var event_button := Button.new()
		event_button.name = "SetReloadEvent_" + event_name
		event_button.text = "Set " + String(
			WeaponReloadVisualTimeline.EVENT_LABELS.get(event_name, event_name)
		)
		event_button.tooltip_text = "Set this reload handoff at the current frame. This changes visuals only."
		event_button.pressed.connect(_set_reload_event_at_current_frame.bind(event_name))
		reload_event_controls_row.add_child(event_button)
		reload_event_buttons[event_name] = event_button
		animation_frame_edit_controls.append(event_button)
	_refresh_animation_frame_editor_ui()


func _on_handling_family_selected(index: int) -> void:
	if handling_family_select == null:
		return
	var family := String(handling_family_select.get_item_metadata(index))
	handling_profile = WeaponAnimationProfile.build_default(
		family,
		animation_catalog.clip_paths if animation_catalog else {}
	)
	_refresh_handling_ui()


func _auto_build_animation_set() -> void:
	var family := String(handling_profile.get(
		"family",
		WeaponAnimationProfile.infer_family(weapon_name, selected_category)
	))
	handling_profile = WeaponAnimationProfile.build_default(
		family,
		animation_catalog.clip_paths if animation_catalog else {}
	)
	_refresh_handling_ui()
	if hud_status:
		hud_status.text = "⚡ Animation set built for %s. Preview it, then save the weapon profile." % family.replace("_", " ")


func _on_animation_slot_selected(index: int, slot_name: String, selector: OptionButton) -> void:
	var slots: Dictionary = handling_profile.get("animation_slots", {}).duplicate(true)
	slots[slot_name] = String(selector.get_item_metadata(index))
	handling_profile["animation_slots"] = slots
	_refresh_handling_ui(false)


func _refresh_handling_ui(sync_selectors: bool = true) -> void:
	if handling_family_select == null:
		return
	var family := String(handling_profile.get(
		"family",
		WeaponAnimationProfile.infer_family(weapon_name, selected_category)
	))
	for index in handling_family_select.item_count:
		if String(handling_family_select.get_item_metadata(index)) == family:
			handling_family_select.select(index)
			break
	var slots: Dictionary = handling_profile.get("animation_slots", {})
	if sync_selectors:
		for slot_name in animation_slot_selectors:
			var selector: OptionButton = animation_slot_selectors[slot_name]
			var wanted := String(slots.get(slot_name, ""))
			selector.select(0)
			for item_index in selector.item_count:
				if String(selector.get_item_metadata(item_index)) == wanted:
					selector.select(item_index)
					break
	var audit := WeaponAnimationProfile.validate(
		handling_profile,
		animation_catalog.clip_paths if animation_catalog else {}
	)
	if animation_mapping_status:
		var missing: Array = audit.get("missing", [])
		animation_mapping_status.text = "%d/%d combat slots mapped%s\nMovement pack: %d/%d directional and posture clips ready" % [
			int(audit.get("mapped", 0)),
			int(audit.get("total", 0)),
			"" if missing.is_empty() else " • Missing: " + ", ".join(missing),
			int(audit.get("locomotion_mapped", 0)),
			int(audit.get("locomotion_total", 0)),
		]
		animation_mapping_status.add_theme_color_override(
			"font_color",
			Color(0.45, 1.0, 0.55) if bool(audit.get("complete", false)) else Color(1.0, 0.72, 0.25)
		)


func _preview_animation_slot(slot_name: String) -> void:
	_leave_animation_frame_editor()
	if animation_player == null or animation_catalog == null:
		return
	var slots: Dictionary = handling_profile.get("animation_slots", {})
	var clip_name := StringName(slots.get(slot_name, ""))
	if clip_name == &"":
		if hud_status:
			hud_status.text = "⚠ No clip mapped to %s yet." % String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name))
		return
	if not _ensure_preview_clip(clip_name):
		if hud_status:
			hud_status.text = "⚠ Could not load animation clip: %s" % clip_name
		return
	_set_animation_edit_candidate(slot_name, clip_name)
	selected_animation_key = clip_name
	animation_frame_weapon_position_correction = Vector3.ZERO
	animation_frame_weapon_rotation_correction_deg = Vector3.ZERO
	_apply_animation_hand_map(clip_name)
	animation_preview_token += 1
	var token := animation_preview_token
	var is_idle := slot_name.begins_with("idle_")
	active_reload_visual_slot = slot_name if slot_name.begins_with("reload_") else ""
	_apply_weapon_ownership_policy(
		WeaponOwnershipContract.preview_policy(slot_name, clip_name),
		slot_name.begins_with("reload_")
	)
	animation_player.play(clip_name, 0.10)
	if hud_status:
		hud_status.text = "▶ Previewing %s → %s" % [String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name)), clip_name]
	if is_idle:
		return
	var animation := animation_player.get_animation(clip_name)
	var duration := maxf(animation.length if animation else 1.0, 0.10)
	get_tree().create_timer(duration).timeout.connect(func():
		if token != animation_preview_token:
			return
		var idle_slot := _posture_idle_slot()
		active_reload_visual_slot = ""
		_apply_weapon_ownership_policy(WeaponOwnershipContract.preview_policy(idle_slot), false)
		var idle_clip := _posture_idle_clip()
		if idle_clip != &"" and _ensure_preview_clip(idle_clip):
			animation_player.play(idle_clip, 0.10)
		if hud_status:
			hud_status.text = "✅ Preview complete. Choose another slot or save this weapon profile."
	)


func _preview_selected_catalog_animation() -> void:
	_leave_animation_frame_editor()
	if all_animation_select == null or all_animation_select.item_count == 0:
		return
	var clip_name := StringName(all_animation_select.get_item_metadata(all_animation_select.selected))
	if clip_name == &"" or not _ensure_preview_clip(clip_name):
		if hud_status:
			hud_status.text = "⚠ Could not load animation clip: %s" % clip_name
		return
	_set_animation_edit_candidate("raw_clip", clip_name)
	selected_animation_key = clip_name
	_apply_animation_hand_map(clip_name)
	animation_preview_token += 1
	var token := animation_preview_token
	_apply_weapon_ownership_policy(
		WeaponOwnershipContract.preview_policy("", clip_name),
		"reload" in String(clip_name).to_lower()
	)
	active_reload_visual_slot = (
		"reload_standing" if "reload" in String(clip_name).to_lower() else ""
	)
	animation_player.play(clip_name, 0.08)
	if hud_status:
		hud_status.text = "▶ Inspecting raw clip %s. Watch the quality meter for hand drift." % clip_name
	var animation := animation_player.get_animation(clip_name)
	var duration := minf(maxf(animation.length if animation else 1.0, 0.20), 2.5)
	get_tree().create_timer(duration).timeout.connect(func():
		if token != animation_preview_token:
			return
		_finish_preview_to_idle()
	)


func _edit_animation_slot(slot_name: String) -> void:
	var slots: Dictionary = handling_profile.get("animation_slots", {})
	var clip_name := StringName(slots.get(slot_name, ""))
	_enter_animation_frame_editor(slot_name, clip_name)


func _edit_selected_catalog_animation() -> void:
	if all_animation_select == null or all_animation_select.item_count == 0:
		return
	var clip_name := StringName(all_animation_select.get_item_metadata(all_animation_select.selected))
	_enter_animation_frame_editor("raw_clip", clip_name)


func _toggle_current_animation_frame_editor() -> void:
	if animation_frame_editor.active:
		# This button is an edit command, not a close command. A shot can attach
		# its fire reaction while it plays. Pressing Edit must pause that exact
		# reaction at the visible frame and keep its context intact.
		_pause_animation_frame_editor_for_authoring()
		if hud_status:
			hud_status.text = "✎ Editing %s at frame %d." % [
				animation_frame_editor.clip_name,
				animation_frame_editor.frame_index(),
			]
		return
	if animation_player == null:
		return
	var slot_name := animation_edit_candidate_slot
	var clip_name := animation_edit_candidate_clip
	if clip_name == &"":
		clip_name = selected_animation_key
	if clip_name == &"" or clip_name == &"RESET":
		clip_name = animation_player.current_animation
	if clip_name == &"" or clip_name == &"RESET":
		clip_name = _posture_idle_clip()
	if slot_name.is_empty():
		slot_name = "current_preview"
	_enter_animation_frame_editor(slot_name, clip_name)


func _pause_animation_frame_editor_for_authoring() -> void:
	if not animation_frame_editor.active or not animation_frame_editor.playing:
		return
	animation_frame_editor.playing = false
	if animation_player:
		animation_player.pause()
		animation_frame_editor.set_time(animation_player.current_animation_position)
	animation_frame_last_applied = -1
	_apply_animation_frame_pose_for_current_time()
	_refresh_animation_frame_editor_ui()


func _set_animation_edit_candidate(slot_name: String, clip_name: StringName) -> void:
	if clip_name == &"" or clip_name == &"RESET":
		return
	animation_edit_candidate_slot = slot_name
	animation_edit_candidate_clip = clip_name


func _enter_animation_frame_editor(slot_name: String, clip_name: StringName) -> void:
	_leave_animation_frame_editor()
	if clip_name == &"" or not _ensure_preview_clip(clip_name):
		if hud_status:
			hud_status.text = "⚠ Map an animation before opening its frame editor."
		return
	animation_preview_token += 1
	mouse_fire_armed = false
	fire_input_held = false
	authoring_pointer_down = false
	_set_animation_edit_candidate(slot_name, clip_name)
	selected_animation_key = clip_name
	_apply_animation_hand_map(clip_name)
	_apply_weapon_ownership_policy(
		WeaponOwnershipContract.preview_policy(slot_name, clip_name),
		slot_name.begins_with("reload_") or "reload" in String(clip_name).to_lower()
	)
	var animation := animation_player.get_animation(clip_name)
	animation_frame_editor.begin(slot_name, clip_name, animation.length if animation else 0.0)
	active_reload_visual_slot = (
		slot_name
		if slot_name.begins_with("reload_")
		else ("reload_standing" if "reload" in String(clip_name).to_lower() else "")
	)
	if not active_reload_visual_slot.is_empty():
		WeaponReloadVisualTimeline.ensure_profile_timeline(
			handling_profile,
			active_reload_visual_slot,
			animation_frame_editor.frame_count()
		)
	animation_frame_base_pose = _snapshot_animation_frame_pose()
	if _is_reload_frame_editor() and not animation_frame_editor.saved_frame_indices().is_empty():
		# Profiles saved before the frame-local weapon split did not have an
		# explicit return key. Add one in memory when that reload is opened.
		animation_frame_editor.ensure_terminal_weapon_neutral_pose(
			animation_frame_base_pose
		)
	animation_frame_last_applied = -1
	animation_player.play(clip_name, 0.0)
	animation_player.pause()
	animation_player.seek(0.0, true)
	_apply_animation_frame_pose_for_current_time()
	_refresh_animation_frame_editor_ui()
	if hud_status:
		hud_status.text = "✎ Frame editor: %s. Step, adjust joints, then save a pose key." % clip_name


func _leave_animation_frame_editor() -> void:
	if not animation_frame_editor.active:
		return
	_restore_animation_frame_pose(animation_frame_base_pose)
	animation_frame_editor.stop()
	active_reload_visual_slot = ""
	if reload_magazine_proxy:
		reload_magazine_proxy.visible = false
	animation_frame_base_pose.clear()
	animation_frame_last_applied = -1
	_refresh_animation_frame_editor_ui()


func _toggle_animation_frame_editor_playback() -> void:
	if not animation_frame_editor.active or animation_player == null:
		return
	animation_frame_editor.playing = not animation_frame_editor.playing
	if animation_frame_editor.playing:
		if (
			animation_frame_editor.duration_seconds > 0.0
			and animation_frame_editor.time_seconds
			>= animation_frame_editor.duration_seconds - (0.5 / animation_frame_editor.fps)
		):
			animation_frame_editor.set_time(0.0)
		animation_player.play(animation_frame_editor.clip_name, 0.0)
		animation_player.seek(animation_frame_editor.time_seconds, true)
	else:
		animation_player.pause()
	_refresh_animation_frame_editor_ui()


func _step_animation_frame_editor(frame_delta: int) -> void:
	if not animation_frame_editor.active or animation_player == null:
		return
	animation_frame_editor.playing = false
	animation_player.pause()
	animation_frame_editor.step_frames(frame_delta)
	animation_player.seek(animation_frame_editor.time_seconds, true)
	animation_frame_last_applied = -1
	_apply_animation_frame_pose_for_current_time()
	_refresh_animation_frame_editor_ui()


func _seek_animation_frame_editor(normalized_time: float) -> void:
	if not animation_frame_editor.active or animation_player == null:
		return
	animation_frame_editor.playing = false
	animation_player.pause()
	animation_frame_editor.set_time(normalized_time * animation_frame_editor.duration_seconds)
	animation_player.seek(animation_frame_editor.time_seconds, true)
	animation_frame_last_applied = -1
	_apply_animation_frame_pose_for_current_time()
	_refresh_animation_frame_editor_ui()


func _seek_animation_frame_index(frame_index: int) -> void:
	if not animation_frame_editor.active or animation_player == null:
		return
	animation_frame_editor.playing = false
	animation_player.pause()
	animation_frame_editor.set_time(
		float(clampi(frame_index, 0, animation_frame_editor.frame_count()))
		/ animation_frame_editor.fps
	)
	animation_player.seek(animation_frame_editor.time_seconds, true)
	animation_frame_last_applied = -1
	_apply_animation_frame_pose_for_current_time()
	_refresh_animation_frame_editor_ui()


func _update_animation_frame_editor() -> void:
	if not animation_frame_editor.active or animation_player == null:
		return
	if animation_frame_editor.playing:
		if animation_player.is_playing():
			animation_frame_editor.set_time(animation_player.current_animation_position)
		else:
			animation_frame_editor.playing = false
			animation_frame_editor.set_time(animation_frame_editor.duration_seconds)
	else:
		# Rebuild the authored pose before procedural posture and IK run below.
		# Without this sample, those additive layers accumulate on the paused pose.
		animation_player.seek(animation_frame_editor.time_seconds, true)
	_apply_animation_frame_pose_for_current_time()
	_refresh_animation_frame_editor_ui()


func _refresh_animation_frame_editor_ui() -> void:
	if animation_frame_panel:
		animation_frame_panel.visible = true
	if animation_frame_editor_title:
		animation_frame_editor_title.text = (
			(
				"Editing %s → %s • orange weapon edits are frame-local"
				% [animation_frame_editor.slot_name, animation_frame_editor.clip_name]
			)
			if animation_frame_editor.active
			else "Select Frames beside an animation state."
		)
	var frame_weapon_editing := _editing_action_weapon_frame()
	for slider_key in ["grip_x", "grip_y", "grip_z", "rot_pitch", "rot_yaw", "rot_roll"]:
		var slider_data: Variant = sliders_map.get(slider_key, {})
		if slider_data is Dictionary:
			var mount_slider := (slider_data as Dictionary).get("slider") as HSlider
			var mount_row := (slider_data as Dictionary).get("row") as Control
			if mount_slider:
				mount_slider.editable = not frame_weapon_editing
			if mount_row:
				mount_row.tooltip_text = (
					"Shared mount is locked in Frames. Use the orange 3D weapon control for this frame only."
					if frame_weapon_editing
					else "Calibrates the shared weapon mount for every animation."
				)
	if animation_frame_play_button:
		animation_frame_play_button.text = "⏸ Pause" if animation_frame_editor.playing else "▶ Play"
	if animation_frame_edit_button:
		if animation_frame_editor.active:
			animation_frame_edit_button.text = (
				"✎ Pause & Edit %s" % animation_frame_editor.clip_name
				if animation_frame_editor.playing
				else "✎ Editing %s" % animation_frame_editor.clip_name
			)
		elif animation_edit_candidate_clip != &"":
			animation_frame_edit_button.text = "✎ Edit %s" % animation_edit_candidate_clip
		else:
			animation_frame_edit_button.text = "✎ Edit Current Animation"
	for control in animation_frame_edit_controls:
		if control:
			control.disabled = not animation_frame_editor.active
	var editing_reload := _is_reload_frame_editor()
	if reload_event_controls_row:
		reload_event_controls_row.visible = editing_reload
	for event_name in reload_event_buttons:
		var reload_button := reload_event_buttons[event_name] as Button
		if reload_button:
			reload_button.disabled = not editing_reload
	if animation_frame_scrubber:
		var normalized := 0.0
		if animation_frame_editor.duration_seconds > 0.0:
			normalized = animation_frame_editor.time_seconds / animation_frame_editor.duration_seconds
		animation_frame_scrubber.set_value_no_signal(normalized)
	if animation_frame_readout:
		if animation_frame_editor.active:
			animation_frame_readout.text = "Frame %d / %d • %.3f s%s" % [
				animation_frame_editor.frame_index(),
				animation_frame_editor.frame_count(),
				animation_frame_editor.time_seconds,
				" • SAVED POSE KEY" if animation_frame_editor.has_current_pose() else "",
			]
		else:
			animation_frame_readout.text = "FRAME EDITOR READY • Click Edit Current Animation"
	if animation_frame_timeline:
		var reload_events := _current_reload_events() if editing_reload else {}
		animation_frame_timeline.configure(
			animation_frame_editor.frame_count(),
			animation_frame_editor.frame_index(),
			animation_frame_editor.saved_frame_indices(),
			reload_events
		)
	if reload_event_status and editing_reload:
		var lifecycle_state := WeaponReloadVisualTimeline.state_at_frame(
			_current_reload_events(),
			animation_frame_editor.frame_index()
		)
		reload_event_status.text = "RELOAD • " + lifecycle_state


func _is_reload_frame_editor() -> bool:
	return (
		animation_frame_editor.active
		and (
			animation_frame_editor.slot_name.begins_with("reload_")
			or "reload" in String(animation_frame_editor.clip_name).to_lower()
		)
	)


func _current_reload_events() -> Dictionary:
	if active_reload_visual_slot.is_empty():
		return {}
	var timeline := WeaponReloadVisualTimeline.ensure_profile_timeline(
		handling_profile,
		active_reload_visual_slot,
		animation_frame_editor.frame_count()
	)
	return (timeline.get("events", {}) as Dictionary).duplicate(true)


func _set_reload_event_at_current_frame(event_name: String) -> void:
	if not _is_reload_frame_editor() or active_reload_visual_slot.is_empty():
		return
	WeaponReloadVisualTimeline.set_event_frame(
		handling_profile,
		active_reload_visual_slot,
		event_name,
		animation_frame_editor.frame_index(),
		animation_frame_editor.frame_count()
	)
	_refresh_animation_frame_editor_ui()
	if hud_status:
		hud_status.text = "◆ %s set at frame %d. Save + Apply Rig to keep it." % [
			WeaponReloadVisualTimeline.EVENT_LABELS.get(event_name, event_name),
			animation_frame_editor.frame_index(),
		]


func _capture_animation_frame_pose_key() -> void:
	if not animation_frame_editor.active:
		if hud_status:
			hud_status.text = "⚠ Open an animation with ✎ before saving a pose key."
		return
	var captured_pose := _snapshot_animation_frame_pose()
	animation_frame_editor.store_current_pose(captured_pose)
	if _is_reload_frame_editor():
		animation_frame_editor.ensure_terminal_weapon_neutral_pose(captured_pose)
	_refresh_animation_frame_editor_ui()
	if hud_status:
		hud_status.text = "◆ Saved correction key for %s at frame %d.%s Save the weapon profile to keep it." % [
			animation_frame_editor.clip_name,
			animation_frame_editor.frame_index(),
			" Weapon pitch/yaw return to aim idle at the final frame." if _is_reload_frame_editor() else " It holds until the next key;",
		]


func _apply_animation_frame_pose_for_current_time() -> void:
	var current_frame := animation_frame_editor.frame_index()
	if current_frame == animation_frame_last_applied:
		return
	_restore_animation_frame_pose(animation_frame_base_pose)
	var saved_pose := animation_frame_editor.sampled_pose()
	if not saved_pose.is_empty():
		_restore_animation_frame_pose(saved_pose)
	animation_frame_last_applied = current_frame


func _snapshot_animation_frame_pose() -> Dictionary:
	var joint_rotations: Dictionary = {}
	if runtime_posture_layer:
		for joint_name: StringName in TUNABLE_BODY_JOINTS:
			if JointControlSchema.control_mode(joint_name) == &"rotation":
				joint_rotations[String(joint_name)] = _vector3_to_dictionary(
					runtime_posture_layer.get_procedural_rotation_degrees(preview_posture, joint_name)
				)
	return {
		"posture": String(preview_posture),
		"joint_rotations": joint_rotations,
		"right_elbow_pole": _vector3_to_dictionary(right_elbow_pole_offset),
		"left_elbow_pole": _vector3_to_dictionary(left_elbow_pole_offset),
		"right_hand_target": _vector3_to_dictionary(right_grip_local_pos),
		"left_hand_target": _vector3_to_dictionary(left_grip_local_pos),
		"weapon_hand_position_correction": _vector3_to_dictionary(
			animation_frame_weapon_position_correction
		),
		"weapon_hand_rotation_correction_deg": _vector3_to_dictionary(
			animation_frame_weapon_rotation_correction_deg
		),
	}


func _restore_animation_frame_pose(pose_data: Dictionary) -> void:
	if pose_data.is_empty():
		return
	var rotations: Dictionary = pose_data.get("joint_rotations", {})
	if runtime_posture_layer:
		for joint_key in rotations:
			var joint_name := StringName(joint_key)
			if joint_name in TUNABLE_BODY_JOINTS:
				runtime_posture_layer.set_procedural_rotation_degrees(
					preview_posture,
					joint_name,
					_dictionary_to_vector3(rotations[joint_key], Vector3.ZERO)
				)
	right_elbow_pole_offset = _dictionary_to_vector3(pose_data.get("right_elbow_pole", {}), right_elbow_pole_offset)
	left_elbow_pole_offset = _dictionary_to_vector3(pose_data.get("left_elbow_pole", {}), left_elbow_pole_offset)
	right_grip_local_pos = _dictionary_to_vector3(pose_data.get("right_hand_target", {}), right_grip_local_pos)
	left_grip_local_pos = _dictionary_to_vector3(pose_data.get("left_hand_target", {}), left_grip_local_pos)
	animation_frame_weapon_position_correction = _dictionary_to_vector3(
		pose_data.get("weapon_hand_position_correction", {}),
		Vector3.ZERO
	)
	animation_frame_weapon_rotation_correction_deg = _dictionary_to_vector3(
		pose_data.get("weapon_hand_rotation_correction_deg", {}),
		Vector3.ZERO
	)
	_sync_markers()
	_sync_body_joint_controls()
	_refresh_rotation_dials()


func _finish_preview_to_idle() -> void:
	var idle_slot := _posture_idle_slot()
	active_reload_visual_slot = ""
	if reload_magazine_proxy:
		reload_magazine_proxy.visible = false
	_apply_weapon_ownership_policy(WeaponOwnershipContract.preview_policy(idle_slot), false)
	var idle_clip := _posture_idle_clip()
	if idle_clip != &"" and _ensure_preview_clip(idle_clip):
		selected_animation_key = idle_clip
		animation_player.play(idle_clip, 0.10)


func _posture_idle_slot() -> String:
	match preview_posture:
		&"CROUCHED": return "idle_crouched"
		&"PRONE": return "idle_prone"
		_: return "idle_standing"


func _posture_idle_clip() -> StringName:
	var defaults := {
		"idle_standing": &"aim_idle",
		"idle_crouched": &"idle_crouch",
		"idle_prone": &"idle_prone",
	}
	var slot := _posture_idle_slot()
	return StringName(
		(handling_profile.get("animation_slots", {}) as Dictionary).get(
			slot,
			defaults[slot]
		)
	)


func _set_preview_posture(posture_name: StringName) -> void:
	if posture_name not in [&"STANDING", &"CROUCHED", &"PRONE"]:
		return
	# A stance owns hand and joint fitting only. The calibrated weapon mount is
	# one weapon-level anchor and must not jump when the stance changes.
	var current_snapshot := _current_hand_pose_snapshot()
	hand_poses_by_stance[preview_posture] = current_snapshot
	var prev_clip := selected_animation_key
	if prev_clip == &"":
		prev_clip = _posture_idle_clip()
	if prev_clip != &"":
		var prev_path := String(all_animation_paths.get(prev_clip, prev_clip))
		animation_hand_maps[prev_path] = current_snapshot
		animation_hand_maps[String(prev_clip)] = current_snapshot

	_store_current_stance_elbow_poles()
	preview_posture = posture_name
	_restore_current_stance_elbow_poles()
	_restore_current_stance_hands()
	_sync_body_joint_controls()
	_sync_eye_sight_controls()
	for key: StringName in stance_buttons:
		var button := stance_buttons[key] as Button
		if button:
			button.set_pressed_no_signal(key == preview_posture)
	animation_preview_token += 1
	# The weapon-level mount stays fixed. The new stance re-solves both arms
	# toward the same physical weapon sockets.
	stance_rebase_remaining = 0.0
	_finish_preview_to_idle()
	if hud_status:
		hud_status.text = "%s weapon-ready stance — the bore reticle remains tied to the red muzzle socket." % String(preview_posture).capitalize()


func _restore_current_stance_hands() -> void:
	var raw_map: Variant = hand_poses_by_stance.get(preview_posture, {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		return
	var hand_map := raw_map as Dictionary
	left_grip_local_pos = _vector_from_data(hand_map.get("left_grip", {}), left_grip_local_pos)
	right_grip_local_pos = _vector_from_data(hand_map.get("right_grip", {}), right_grip_local_pos)
	palm_pitch = float(hand_map.get("palm_pitch_deg", palm_pitch))
	palm_yaw = float(hand_map.get("palm_yaw_deg", palm_yaw))
	palm_roll = float(hand_map.get("palm_roll_deg", palm_roll))
	finger_curl = float(hand_map.get("finger_curl", finger_curl))
	thumb_wrap = float(hand_map.get("thumb_wrap", thumb_wrap))
	_sync_weapon_transform()
	_sync_markers()
	for value_pair in [
		["ik_x", left_grip_local_pos.x], ["ik_y", left_grip_local_pos.y],
		["ik_z", left_grip_local_pos.z], ["rh_x", right_grip_local_pos.x],
		["rh_y", right_grip_local_pos.y], ["rh_z", right_grip_local_pos.z],
		["grip_x", grip_offset_pos.x], ["grip_y", grip_offset_pos.y],
		["grip_z", grip_offset_pos.z], ["rot_pitch", grip_offset_rot.x],
		["rot_yaw", grip_offset_rot.y], ["rot_roll", grip_offset_rot.z],
		["p_pitch", palm_pitch], ["p_yaw", palm_yaw], ["p_roll", palm_roll],
		["f_curl", finger_curl], ["t_wrap", thumb_wrap],
	]:
		_update_slider_value(value_pair[0], value_pair[1])


func _save_selected_animation_hand_map() -> void:
	var clip_key := selected_animation_key
	if clip_key == &"":
		if all_animation_select != null and all_animation_select.item_count > 0:
			clip_key = StringName(all_animation_select.get_item_metadata(all_animation_select.selected))
		if clip_key == &"":
			clip_key = _posture_idle_clip()
	var resource_path := String(all_animation_paths.get(clip_key, ""))
	if resource_path.is_empty():
		resource_path = String(clip_key)
	if resource_path.is_empty():
		return
	var data := _current_hand_pose_snapshot()
	hand_poses_by_stance[preview_posture] = data.duplicate(true)
	animation_hand_maps[resource_path] = data
	animation_hand_maps[String(clip_key)] = data
	if hud_status:
		hud_status.text = "💾 Both-hand map staged for this clip. Ctrl/Cmd+S saves it with the weapon."


func _apply_animation_hand_map(clip_key: StringName) -> void:
	var raw_map: Variant = hand_poses_by_stance.get(preview_posture, {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		var resource_path := String(all_animation_paths.get(clip_key, ""))
		raw_map = animation_hand_maps.get(resource_path, {})
		if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
			raw_map = animation_hand_maps.get(String(clip_key), {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		return
	var hand_map := raw_map as Dictionary
	left_grip_local_pos = _vector_from_data(hand_map.get("left_grip", {}), left_grip_local_pos)
	right_grip_local_pos = _vector_from_data(hand_map.get("right_grip", {}), right_grip_local_pos)
	palm_pitch = float(hand_map.get("palm_pitch_deg", palm_pitch))
	palm_yaw = float(hand_map.get("palm_yaw_deg", palm_yaw))
	palm_roll = float(hand_map.get("palm_roll_deg", palm_roll))
	finger_curl = float(hand_map.get("finger_curl", finger_curl))
	thumb_wrap = float(hand_map.get("thumb_wrap", thumb_wrap))
	_sync_weapon_transform()
	_sync_markers()
	for value_pair in [
		["ik_x", left_grip_local_pos.x], ["ik_y", left_grip_local_pos.y],
		["ik_z", left_grip_local_pos.z], ["rh_x", right_grip_local_pos.x],
		["rh_y", right_grip_local_pos.y], ["rh_z", right_grip_local_pos.z],
		["grip_x", grip_offset_pos.x], ["grip_y", grip_offset_pos.y],
		["grip_z", grip_offset_pos.z], ["rot_pitch", grip_offset_rot.x],
		["rot_yaw", grip_offset_rot.y], ["rot_roll", grip_offset_rot.z],
		["p_pitch", palm_pitch], ["p_yaw", palm_yaw], ["p_roll", palm_roll],
		["f_curl", finger_curl], ["t_wrap", thumb_wrap],
	]:
		_update_slider_value(String(value_pair[0]), float(value_pair[1]))


func _vector_to_data(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}


func _current_hand_pose_snapshot() -> Dictionary:
	return {
		"left_grip": _vector_to_data(left_grip_local_pos),
		"right_grip": _vector_to_data(right_grip_local_pos),
		"palm_pitch_deg": palm_pitch,
		"palm_yaw_deg": palm_yaw,
		"palm_roll_deg": palm_roll,
		"finger_curl": finger_curl,
		"thumb_wrap": thumb_wrap,
	}


func _hand_maps_without_legacy_mounts(raw_maps: Dictionary) -> Dictionary:
	var sanitized := raw_maps.duplicate(true)
	for map_key in sanitized.keys():
		var raw_pose: Variant = sanitized[map_key]
		if raw_pose is Dictionary:
			var pose := raw_pose as Dictionary
			pose.erase("weapon_mount_position")
			pose.erase("weapon_mount_rotation_deg")
	return sanitized


func _vector_from_data(raw_value: Variant, fallback: Vector3) -> Vector3:
	if not (raw_value is Dictionary):
		return fallback
	var data := raw_value as Dictionary
	return Vector3(
		float(data.get("x", fallback.x)),
		float(data.get("y", fallback.y)),
		float(data.get("z", fallback.z))
	)


func _apply_weapon_ownership_policy(policy: Dictionary, reload_action: bool) -> void:
	if not reload_action:
		active_reload_visual_slot = ""
		reload_visual_state = WeaponReloadVisualTimeline.STATE_IN_WEAPON
		if reload_magazine_proxy:
			reload_magazine_proxy.visible = false
	weapon_owner_state = StringName(
		policy.get("weapon_owner", WeaponOwnershipContract.OWNER_WEAPON_MASTER)
	)
	support_hand_policy = StringName(
		policy.get("support_hand", WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON)
	)
	is_reloading = reload_action
	if weapon_owner_state == WeaponOwnershipContract.OWNER_ANIMATED_RIGHT_HAND:
		if not action_weapon_follow_active:
			_begin_action_weapon_follow()
	elif action_weapon_follow_active:
		_finish_action_weapon_follow()
	_set_support_hand_attached(support_hand_attached, false)


func _update_animation_quality_readout(delta: float) -> void:
	if animation_quality_status == null or skeleton == null or weapon_root == null:
		return
	animation_quality_sample_elapsed += delta
	if animation_quality_sample_elapsed < 0.08:
		return
	animation_quality_sample_elapsed = 0.0
	var trigger_error_cm := (
		right_grip_marker.global_position.distance_to(_right_palm_contact_world()) * 100.0
		if right_grip_marker and is_instance_valid(right_grip_marker)
		else INF
	)
	var support_error_cm := (
		left_grip_marker.global_position.distance_to(_left_palm_contact_world()) * 100.0
		if left_grip_marker and is_instance_valid(left_grip_marker)
		else INF
	)
	var support_is_free := support_hand_policy != WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
	var score := _animation_quality_score(trigger_error_cm, support_error_cm, support_is_free)
	var grade := _animation_quality_grade(score)
	animation_quality_status.text = (
		"Quality %s  %.0f/100  • trigger %.2f cm  • support %s  • owner %s"
		% [
			grade,
			score,
			trigger_error_cm,
			String(support_hand_policy) if support_is_free else "%.2f cm" % support_error_cm,
			String(weapon_owner_state),
		]
	)
	animation_quality_status.add_theme_color_override(
		"font_color",
		Color(0.35, 1.0, 0.5) if score >= 85.0 else (Color(1.0, 0.8, 0.25) if score >= 65.0 else Color(1.0, 0.35, 0.3))
	)


func _animation_quality_score(trigger_error_cm: float, support_error_cm: float, support_free: bool) -> float:
	var penalty := minf(trigger_error_cm, 20.0) * 10.0
	if not support_free:
		penalty += minf(support_error_cm, 20.0) * 6.0
	return clampf(100.0 - penalty, 0.0, 100.0)


func _animation_quality_grade(score: float) -> String:
	if score >= 92.0:
		return "A"
	if score >= 82.0:
		return "B"
	if score >= 68.0:
		return "C"
	if score >= 50.0:
		return "D"
	return "F"


func _audit_all_equipped_animation_states() -> void:
	if animation_quality_audit_running or animation_player == null:
		return
	animation_quality_audit_running = true
	animation_preview_token += 1
	var audit_token := animation_preview_token
	var lines: Array[String] = []
	last_animation_quality_audit.clear()
	if animation_quality_results:
		animation_quality_results.text = "Auditing equipped animation states…"
	var slots: Dictionary = handling_profile.get("animation_slots", {})
	for slot_name in WeaponAnimationProfile.SLOT_ORDER:
		if audit_token != animation_preview_token:
			break
		var clip_name := StringName(slots.get(slot_name, ""))
		if clip_name == &"":
			lines.append("— %s: missing" % String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name)))
			continue
		var result: Dictionary = await _measure_animation_quality(String(slot_name), clip_name)
		last_animation_quality_audit[String(slot_name)] = result.duplicate(true)
		lines.append(
			"%s %s — %s  trigger %.2f cm  support %s  travel %.1f cm"
			% [
				String(result.get("grade", "?")),
				String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name)),
				clip_name,
				float(result.get("trigger_error_cm", INF)),
				"FREE" if bool(result.get("support_free", false)) else "%.2f cm" % float(result.get("support_error_cm", INF)),
				float(result.get("weapon_travel_cm", 0.0)),
			]
		)
		if animation_quality_results:
			animation_quality_results.text = "\n".join(lines)
	_finish_preview_to_idle()
	animation_quality_audit_running = false
	if hud_status:
		hud_status.text = "✅ Animation compatibility audit complete. D/F rows need a different clip or grip tune."


func _auto_fix_failed_animation_states() -> void:
	if animation_autofix_running or animation_quality_audit_running:
		return
	animation_autofix_running = true
	if last_animation_quality_audit.is_empty():
		await _audit_all_equipped_animation_states()
	var slots: Dictionary = handling_profile.get("animation_slots", {}).duplicate(true)
	last_animation_autofix_previous_slots = slots.duplicate(true)
	var changes: Array[String] = []
	var unresolved: Array[String] = []
	for raw_slot_name in WeaponAnimationProfile.SLOT_ORDER:
		var slot_name := String(raw_slot_name)
		var baseline: Dictionary = last_animation_quality_audit.get(slot_name, {})
		var baseline_score := float(baseline.get("score", 0.0))
		if baseline_score >= 82.0:
			continue
		var current_clip := StringName(slots.get(slot_name, ""))
		var best_clip := current_clip
		var best_score := baseline_score
		for candidate in _compatible_runtime_candidates(slot_name):
			if StringName(candidate) == current_clip:
				continue
			var candidate_result: Dictionary = await _measure_animation_quality(slot_name, StringName(candidate))
			var candidate_score := float(candidate_result.get("score", 0.0))
			if candidate_score > best_score:
				best_score = candidate_score
				best_clip = StringName(candidate)
		# Do not churn mappings for noise. A replacement must improve the
		# measured compatibility score by at least eight points.
		if best_clip != current_clip and best_score >= baseline_score + 8.0:
			slots[slot_name] = String(best_clip)
			changes.append("%s: %s → %s (%.0f → %.0f)" % [
				String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name)),
				current_clip,
				best_clip,
				baseline_score,
				best_score,
			])
		else:
			unresolved.append(String(WeaponAnimationProfile.SLOT_LABELS.get(slot_name, slot_name)))
	handling_profile["animation_slots"] = slots
	_refresh_handling_ui()
	if animation_autofix_undo_button:
		animation_autofix_undo_button.disabled = changes.is_empty()
	# If nothing changed, keep the already valid baseline audit visible. Starting
	# a second asynchronous audit after UI refresh could be cancelled by a
	# selector signal and leave an empty report even though no mapping changed.
	if changes.is_empty():
		_finish_preview_to_idle()
	else:
		await _audit_all_equipped_animation_states()
	var summary := (
		"AUTO-FIX\n%s"
		% ("No safe clip replacements found." if changes.is_empty() else "\n".join(changes))
	)
	if not unresolved.is_empty():
		summary += "\nNeeds human rig/socket review: %s" % ", ".join(unresolved)
	if animation_quality_results:
		animation_quality_results.text = "%s\n\n%s" % [summary, animation_quality_results.text]
	if hud_status:
		hud_status.text = (
			"✨ Auto-fix completed with %d safe replacement(s). Save only after reviewing; Undo Fix is available."
			% changes.size()
		)
	animation_autofix_running = false


func _undo_animation_autofix() -> void:
	if last_animation_autofix_previous_slots.is_empty():
		return
	handling_profile["animation_slots"] = last_animation_autofix_previous_slots.duplicate(true)
	last_animation_autofix_previous_slots.clear()
	last_animation_quality_audit.clear()
	_refresh_handling_ui()
	if animation_autofix_undo_button:
		animation_autofix_undo_button.disabled = true
	if animation_quality_results:
		animation_quality_results.text = "Auto-fix reverted. Run Audit All Equipped States to measure the restored mapping."
	if hud_status:
		hud_status.text = "↶ Auto-fix reverted; animation mappings are restored."


func _compatible_runtime_candidates(slot_name: String) -> Array[StringName]:
	var result: Array[StringName] = []
	var intent := "idle" if slot_name.begins_with("idle_") else ("reload" if slot_name.begins_with("reload_") else "fire")
	var posture := "prone" if slot_name.ends_with("prone") else ("crouch" if slot_name.ends_with("crouched") else "standing")
	for raw_clip_name in animation_catalog.clip_paths.keys():
		var clip_name := String(raw_clip_name).to_lower()
		var intent_match := (
			("idle" in clip_name or "aim" in clip_name) if intent == "idle"
			else (("reload" in clip_name) if intent == "reload" else ("fire" in clip_name or "shoot" in clip_name))
		)
		if not intent_match:
			continue
		var has_prone := "prone" in clip_name
		var has_crouch := "crouch" in clip_name or "kneel" in clip_name
		var posture_match := (
			has_prone if posture == "prone"
			else (has_crouch and not has_prone if posture == "crouch" else not has_prone and not has_crouch)
		)
		if posture_match:
			result.append(StringName(raw_clip_name))
	result.sort_custom(func(a: StringName, b: StringName): return String(a).naturalnocasecmp_to(String(b)) < 0)
	# Keep the automatic pass quick and reviewable even if the catalog grows.
	if result.size() > 8:
		result.resize(8)
	return result


func _measure_animation_quality(slot_name: String, clip_name: StringName) -> Dictionary:
	if not _ensure_preview_clip(clip_name):
		return {"grade": "F", "trigger_error_cm": INF, "support_error_cm": INF, "weapon_travel_cm": 0.0}
	var policy := WeaponOwnershipContract.preview_policy(slot_name, clip_name)
	var support_free := (
		StringName(policy.get("support_hand", WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON))
		!= WeaponOwnershipContract.SUPPORT_IK_TO_WEAPON
	)
	_apply_weapon_ownership_policy(policy, slot_name.begins_with("reload_"))
	animation_player.play(clip_name, 0.04)
	await get_tree().process_frame
	var start_weapon := weapon_root.global_position
	var max_trigger_error_cm := 0.0
	var max_support_error_cm := 0.0
	var max_weapon_travel_cm := 0.0
	var animation := animation_player.get_animation(clip_name)
	var sample_seconds := clampf(animation.length if animation else 0.5, 0.25, 0.75)
	var sample_frames := maxi(12, int(ceil(sample_seconds * 60.0)))
	for _frame in range(sample_frames):
		await get_tree().process_frame
		max_trigger_error_cm = maxf(
			max_trigger_error_cm,
			right_grip_marker.global_position.distance_to(_right_palm_contact_world()) * 100.0
		)
		max_support_error_cm = maxf(
			max_support_error_cm,
			left_grip_marker.global_position.distance_to(_left_palm_contact_world()) * 100.0
		)
		max_weapon_travel_cm = maxf(
			max_weapon_travel_cm,
			weapon_root.global_position.distance_to(start_weapon) * 100.0
		)
	var score := _animation_quality_score(max_trigger_error_cm, max_support_error_cm, support_free)
	_apply_weapon_ownership_policy(WeaponOwnershipContract.preview_policy("idle_standing"), false)
	return {
		"grade": _animation_quality_grade(score),
		"score": score,
		"trigger_error_cm": max_trigger_error_cm,
		"support_error_cm": max_support_error_cm,
		"support_free": support_free,
		"weapon_travel_cm": max_weapon_travel_cm,
	}


func _ensure_preview_clip(clip_name: StringName) -> bool:
	if animation_player.has_animation(clip_name):
		return true
	var clip_path := String(animation_catalog.clip_paths.get(
		clip_name,
		all_animation_paths.get(clip_name, "")
	))
	if clip_path == "" or not FileAccess.file_exists(clip_path):
		return false
	var packed_scene := load(clip_path) as PackedScene
	if packed_scene == null:
		return false
	var source_root := packed_scene.instantiate()
	var source_player := _find_animation_player(source_root)
	if source_player == null:
		source_root.queue_free()
		return false
	var source_name: StringName = &""
	for candidate in source_player.get_animation_list():
		if candidate != &"RESET":
			source_name = candidate
			break
	if source_name == &"":
		source_root.queue_free()
		return false
	var retargeted := _retarget_aim_anim(source_player.get_animation(source_name))
	if slot_name_is_looping(clip_name):
		retargeted.loop_mode = Animation.LOOP_LINEAR
	var library := animation_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		animation_player.add_animation_library(&"", library)
	library.add_animation(clip_name, retargeted)
	source_root.queue_free()
	return true


func slot_name_is_looping(clip_name: StringName) -> bool:
	return animation_catalog.LOOPING_CLIPS.has(clip_name) or String(clip_name).begins_with("pistol_idle")


func _scan_all_animation_assets() -> void:
	all_animation_entries.clear()
	all_animation_paths.clear()
	_scan_animation_directory("res://assets/animations/mixamo")
	all_animation_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		return String(a.get("display", "")).naturalnocasecmp_to(String(b.get("display", ""))) < 0
	)


func _scan_animation_directory(directory_path: String) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var file_name := directory.get_next()
	while file_name != "":
		if directory.current_is_dir() and not file_name.begins_with("."):
			_scan_animation_directory("%s/%s" % [directory_path, file_name])
		elif file_name.ends_with(".fbx") and not file_name.begins_with("."):
			var full_path := "%s/%s" % [directory_path, file_name]
			var folder := directory_path.get_file()
			var tag := ""
			if "Pistol" in folder:
				tag = "[Pistol] "
			elif "Locomotion" in folder or "Lite" in folder:
				tag = "[Rifle] "
			elif "Shooter" in folder:
				tag = "[Shooter] "
			var display_name := tag + file_name.get_basename().capitalize()
			var key := StringName("gunsmith_catalog_%s" % abs(full_path.hash()))
			all_animation_paths[key] = full_path
			all_animation_entries.append({
				"key": key,
				"display": display_name,
				"path": full_path,
			})
		file_name = directory.get_next()
	directory.list_dir_end()

func _setup_unscaled_hand_gizmo() -> void:
	if hand_gizmo_world and is_instance_valid(hand_gizmo_world):
		hand_gizmo_world.queue_free()
		hand_gizmo_world = null

	hand_gizmo_world = Node3D.new()
	hand_gizmo_world.name = "HandGizmoWorld"
	add_child(hand_gizmo_world)

	# Large, unscaled controls stay readable even when the imported weapon is tiny.
	hand_gizmo_center = _create_marker(Color(0.0, 0.95, 1.0), "left_ik", GIZMO_CENTER_RADIUS)
	gizmo_arrow_x = _create_axis_arrow(Color(1.0, 0.25, 0.25), Vector3.RIGHT, "left_ik_arrow_x", HAND_GIZMO_ARROW_LENGTH)
	gizmo_arrow_y = _create_axis_arrow(Color(0.25, 1.0, 0.25), Vector3.UP, "left_ik_arrow_y", HAND_GIZMO_ARROW_LENGTH)
	gizmo_arrow_z = _create_axis_arrow(Color(0.35, 0.65, 1.0), Vector3.BACK, "left_ik_arrow_z", HAND_GIZMO_ARROW_LENGTH)
	gizmo_ring_roll = _create_rotation_ring(Color(1.0, 0.9, 0.2), Vector3.RIGHT, HAND_GIZMO_RING_RADIUS, "left_ik_ring_roll")
	gizmo_ring_pitch = _create_rotation_ring(Color(1.0, 0.3, 0.9), Vector3.BACK, HAND_GIZMO_RING_RADIUS, "left_ik_ring_pitch")
	gizmo_ring_yaw = _create_rotation_ring(Color(0.2, 0.85, 1.0), Vector3.UP, HAND_GIZMO_RING_RADIUS, "left_ik_ring_yaw")

	hand_gizmo_world.add_child(hand_gizmo_center)
	hand_gizmo_world.add_child(gizmo_arrow_x)
	hand_gizmo_world.add_child(gizmo_arrow_y)
	hand_gizmo_world.add_child(gizmo_arrow_z)
	hand_gizmo_world.add_child(gizmo_ring_roll)
	hand_gizmo_world.add_child(gizmo_ring_pitch)
	hand_gizmo_world.add_child(gizmo_ring_yaw)

func _setup_unscaled_weapon_gizmo() -> void:
	if weapon_gizmo_world and is_instance_valid(weapon_gizmo_world):
		weapon_gizmo_world.queue_free()
		weapon_gizmo_world = null

	weapon_gizmo_world = Node3D.new()
	weapon_gizmo_world.name = "WeaponMountGizmoWorld"
	add_child(weapon_gizmo_world)

	weapon_gizmo_center = _create_selection_box(Color(1.0, 0.55, 0.08), "weapon_mount", GIZMO_CENTER_RADIUS * 1.15)
	weapon_gizmo_arrow_x = _create_axis_arrow(Color(1.0, 0.25, 0.25), Vector3.RIGHT, "weapon_arrow_x", WEAPON_GIZMO_ARROW_LENGTH)
	weapon_gizmo_arrow_y = _create_axis_arrow(Color(0.25, 1.0, 0.25), Vector3.UP, "weapon_arrow_y", WEAPON_GIZMO_ARROW_LENGTH)
	weapon_gizmo_arrow_z = _create_axis_arrow(Color(0.35, 0.65, 1.0), Vector3.BACK, "weapon_arrow_z", WEAPON_GIZMO_ARROW_LENGTH)
	weapon_gizmo_ring_roll = _create_rotation_ring(Color(1.0, 0.9, 0.2), Vector3.RIGHT, WEAPON_GIZMO_RING_RADIUS, "weapon_ring_roll")
	weapon_gizmo_ring_pitch = _create_rotation_ring(Color(1.0, 0.3, 0.9), Vector3.BACK, WEAPON_GIZMO_RING_RADIUS, "weapon_ring_pitch")
	weapon_gizmo_ring_yaw = _create_rotation_ring(Color(0.2, 0.85, 1.0), Vector3.UP, WEAPON_GIZMO_RING_RADIUS, "weapon_ring_yaw")

	weapon_gizmo_world.add_child(weapon_gizmo_center)
	weapon_gizmo_world.add_child(weapon_gizmo_arrow_x)
	weapon_gizmo_world.add_child(weapon_gizmo_arrow_y)
	weapon_gizmo_world.add_child(weapon_gizmo_arrow_z)
	weapon_gizmo_world.add_child(weapon_gizmo_ring_roll)
	weapon_gizmo_world.add_child(weapon_gizmo_ring_pitch)
	weapon_gizmo_world.add_child(weapon_gizmo_ring_yaw)

func _set_active_gizmo(gizmo_id: String) -> void:
	active_gizmo_id = gizmo_id
	var show_hand := active_gizmo_id == "hand"
	var hand_arrows: Array[Node3D] = [gizmo_arrow_x, gizmo_arrow_y, gizmo_arrow_z]
	var weapon_arrows: Array[Node3D] = [weapon_gizmo_arrow_x, weapon_gizmo_arrow_y, weapon_gizmo_arrow_z]
	var world_rings: Array[Node3D] = [gizmo_ring_roll, gizmo_ring_pitch, gizmo_ring_yaw, weapon_gizmo_ring_roll, weapon_gizmo_ring_pitch, weapon_gizmo_ring_yaw]
	for control in hand_arrows:
		if control and is_instance_valid(control): control.visible = false
	for control in weapon_arrows:
		if control and is_instance_valid(control): control.visible = false
	for ring in world_rings:
		if ring and is_instance_valid(ring): ring.visible = false
	# The support-hand point stays uncluttered. Keep one compact orange box on the
	# rifle so the weapon itself can always be selected and freely repositioned.
	if hand_gizmo_center: hand_gizmo_center.visible = false
	if weapon_gizmo_center: weapon_gizmo_center.visible = true
	_refresh_rotation_dials()
	if hud_status:
		hud_status.text = "🔵 Support-hand controls active" if show_hand else "🟠 Weapon-mount controls active"

func _register_interactive_dots() -> void:
	interactive_dots.clear()
	for joint_name: StringName in body_joint_markers:
		interactive_dots.append({
			"id": "body_joint:%s" % String(joint_name),
			"mesh": body_joint_markers[joint_name],
			"label": "🔷 %s procedural joint" % String(joint_name).replace("_", " ").capitalize(),
			"color": Color(0.15, 0.85, 1.0),
		})
	for region_key: StringName in hurtbox_edit_markers:
		interactive_dots.append({
			"id": "hurtbox:%s" % String(region_key),
			"mesh": hurtbox_edit_markers[region_key],
			"label": "🟠 %s hitbox" % HurtboxProfile.region_label(region_key),
			"color": Color(1.0, 0.52, 0.12),
		})
	if right_elbow_pole_marker:
		interactive_dots.append({"id": "right_elbow_pole", "mesh": right_elbow_pole_marker, "label": "🟣 Right Elbow IK Pole", "color": Color(1.0, 0.25, 0.9)})
	if left_elbow_pole_marker:
		interactive_dots.append({"id": "left_elbow_pole", "mesh": left_elbow_pole_marker, "label": "🟣 Left Elbow IK Pole", "color": Color(0.75, 0.35, 1.0)})
	if hand_gizmo_center:
		interactive_dots.append({"id": "left_ik", "mesh": hand_gizmo_center, "label": "🔵 Hand Rig (Free 3D Translate)", "color": Color(0.0, 0.95, 1.0)})
	if gizmo_arrow_x and gizmo_arrow_x.get_child_count() > 1:
		interactive_dots.append({"id": "left_ik_arrow_x", "mesh": gizmo_arrow_x.get_child(1), "label": "🔴 Drag Along Barrel (X)", "color": Color(1.0, 0.25, 0.25)})
	if gizmo_arrow_y and gizmo_arrow_y.get_child_count() > 1:
		interactive_dots.append({"id": "left_ik_arrow_y", "mesh": gizmo_arrow_y.get_child(1), "label": "🟢 Drag Height (Y)", "color": Color(0.25, 1.0, 0.25)})
	if gizmo_arrow_z and gizmo_arrow_z.get_child_count() > 1:
		interactive_dots.append({"id": "left_ik_arrow_z", "mesh": gizmo_arrow_z.get_child(1), "label": "🔵 Drag Side (Z)", "color": Color(0.35, 0.65, 1.0)})
	if gizmo_ring_roll:
		interactive_dots.append({"id": "left_ik_ring_roll", "mesh": gizmo_ring_roll, "label": "🟡 Spin Palm Around Gun (Roll)", "color": Color(1.0, 0.9, 0.2)})
	if gizmo_ring_pitch:
		interactive_dots.append({"id": "left_ik_ring_pitch", "mesh": gizmo_ring_pitch, "label": "🟣 Tilt Wrist Pitch", "color": Color(1.0, 0.3, 0.9)})
	if gizmo_ring_yaw:
		interactive_dots.append({"id": "left_ik_ring_yaw", "mesh": gizmo_ring_yaw, "label": "🔷 Turn Wrist Yaw", "color": Color(0.2, 0.85, 1.0)})

	if weapon_gizmo_center:
		interactive_dots.append({"id": "weapon_mount", "mesh": weapon_gizmo_center, "label": "🟠 Grab and Move Weapon", "color": Color(1.0, 0.55, 0.08)})
	if weapon_gizmo_arrow_x and weapon_gizmo_arrow_x.get_child_count() > 1:
		interactive_dots.append({"id": "weapon_arrow_x", "mesh": weapon_gizmo_arrow_x.get_child(1), "label": "🔴 Move Weapon X", "color": Color(1.0, 0.25, 0.25)})
	if weapon_gizmo_arrow_y and weapon_gizmo_arrow_y.get_child_count() > 1:
		interactive_dots.append({"id": "weapon_arrow_y", "mesh": weapon_gizmo_arrow_y.get_child(1), "label": "🟢 Move Weapon Y", "color": Color(0.25, 1.0, 0.25)})
	if weapon_gizmo_arrow_z and weapon_gizmo_arrow_z.get_child_count() > 1:
		interactive_dots.append({"id": "weapon_arrow_z", "mesh": weapon_gizmo_arrow_z.get_child(1), "label": "🔵 Move Weapon Z", "color": Color(0.35, 0.65, 1.0)})
	if weapon_gizmo_ring_roll:
		interactive_dots.append({"id": "weapon_ring_roll", "mesh": weapon_gizmo_ring_roll, "label": "🟡 Rotate Weapon Roll", "color": Color(1.0, 0.9, 0.2)})
	if weapon_gizmo_ring_pitch:
		interactive_dots.append({"id": "weapon_ring_pitch", "mesh": weapon_gizmo_ring_pitch, "label": "🟣 Rotate Weapon Pitch", "color": Color(1.0, 0.3, 0.9)})
	if weapon_gizmo_ring_yaw:
		interactive_dots.append({"id": "weapon_ring_yaw", "mesh": weapon_gizmo_ring_yaw, "label": "🔷 Rotate Weapon Yaw", "color": Color(0.2, 0.85, 1.0)})

	if muzzle_marker: interactive_dots.append({"id": "muzzle", "mesh": muzzle_marker, "label": "🔴 Muzzle Tip Socket", "color": Color(1.0, 0.2, 0.2)})
	if barrel_base_marker: interactive_dots.append({"id": "barrel_base", "mesh": barrel_base_marker, "label": "🔴 Barrel Base Socket", "color": Color(1.0, 0.4, 0.4)})
	if ejection_marker: interactive_dots.append({"id": "ejection", "mesh": ejection_marker, "label": "🟡 Shell Ejection Port", "color": Color(1.0, 0.85, 0.1)})
	if optic_marker: interactive_dots.append({"id": "optic", "mesh": optic_marker, "label": "🟢 Optic Scope Rail", "color": Color(0.2, 1.0, 0.4)})
	if right_grip_marker: interactive_dots.append({"id": "right_grip", "mesh": right_grip_marker, "label": "🟠 Trigger-Hand Grip (moves gun in right hand)", "color": Color(1.0, 0.55, 0.08)})
	if eye_sight_dot: interactive_dots.append({"id": "eye_sight", "mesh": eye_sight_dot, "label": "🔵 Eye Sight — drag yaw/pitch", "color": Color(0.25, 0.55, 1.0)})

func _find_dot_under_mouse(screen_pos: Vector2) -> String:
	if not cam: return ""
	var closest_id := ""
	var closest_dist := GIZMO_PICK_DISTANCE_PX
	# Weapon sockets are precise authoring points. Give them priority over the
	# larger body-joint pick radius so the red muzzle dot can never select a bone.
	for socket_pick in [
		["muzzle", muzzle_marker],
		["barrel_base", barrel_base_marker],
		["ejection", ejection_marker],
		["optic", optic_marker],
	]:
		var socket_mesh := socket_pick[1] as MeshInstance3D
		if socket_mesh != null and socket_mesh.is_visible_in_tree() and not cam.is_position_behind(socket_mesh.global_position):
			if screen_pos.distance_to(cam.unproject_position(socket_mesh.global_position)) <= 18.0:
				return String(socket_pick[0])

	# The head origin is a small dot, so make the visible blue sight segment a
	# direct authoring handle too. Keep this after weapon sockets so an eye line
	# crossing the rifle can never steal a muzzle or optic selection.
	if eye_sight_marker != null and eye_sight_marker.is_visible_in_tree():
		var eye_origin := eye_sight_marker.global_position
		# Keep the pick segment close to the face. The sight direction can point
		# toward the editor camera, so a long endpoint can cross behind the camera
		# and make the otherwise-visible blue handle impossible to select.
		var eye_pick_end := (
			eye_origin
			+ _eye_sight_direction_world() * EYE_SIGHT_PICK_LENGTH_METERS
		)
		if not cam.is_position_behind(eye_origin) and not cam.is_position_behind(eye_pick_end):
			var eye_line_distance := _screen_point_segment_distance(
				screen_pos,
				cam.unproject_position(eye_origin),
				cam.unproject_position(eye_pick_end)
			)
			if eye_line_distance <= 14.0:
				return "eye_sight"

	# Select the real support-hand area instead of requiring a visible sphere.
	if left_grip_marker and not cam.is_position_behind(left_grip_marker.global_position):
		var hand_screen := cam.unproject_position(left_grip_marker.global_position)
		var hand_dist := screen_pos.distance_to(hand_screen)
		if hand_dist < closest_dist:
			closest_dist = hand_dist
			closest_id = "left_ik"

	for item in interactive_dots:
		var id: String = item["id"]
		var mi: MeshInstance3D = item["mesh"]
		if not mi or not is_instance_valid(mi) or not mi.is_visible_in_tree(): continue

		var pick_dist := INF
		var is_hand_control := id.begins_with("left_ik_")
		var is_weapon_control := id.begins_with("weapon_")
		var control_root: Node3D = hand_gizmo_world if is_hand_control else weapon_gizmo_world
		var ring_radius := HAND_GIZMO_RING_RADIUS if is_hand_control else WEAPON_GIZMO_RING_RADIUS
		var arrow_length := HAND_GIZMO_ARROW_LENGTH if is_hand_control else WEAPON_GIZMO_ARROW_LENGTH

		if (is_hand_control or is_weapon_control) and id.contains("ring_") and control_root:
			var ring_axis := id.get_slice("ring_", 1)
			pick_dist = _ring_pick_distance(screen_pos, control_root.global_position, control_root.global_basis, ring_axis, ring_radius)
		elif (is_hand_control or is_weapon_control) and id.contains("arrow_") and control_root:
			var arrow_axis := id.get_slice("arrow_", 1)
			var direction := control_root.global_basis.x
			if arrow_axis == "y": direction = control_root.global_basis.y
			elif arrow_axis == "z": direction = -control_root.global_basis.z
			var tip := control_root.global_position + direction.normalized() * (arrow_length + 0.025)
			if not cam.is_position_behind(tip):
				pick_dist = screen_pos.distance_to(cam.unproject_position(tip))
		elif not cam.is_position_behind(mi.global_position):
			pick_dist = screen_pos.distance_to(cam.unproject_position(mi.global_position))

		if pick_dist < closest_dist:
			closest_dist = pick_dist
			closest_id = id
	return closest_id

func _screen_point_segment_distance(point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(segment_start)
	var amount := clampf((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * amount)

func _ring_pick_distance(screen_pos: Vector2, center: Vector3, basis: Basis, axis_name: String, radius: float) -> float:
	var axis_a := basis.y
	var axis_b := basis.z
	if axis_name == "pitch":
		axis_a = basis.x
		axis_b = basis.y
	elif axis_name == "yaw":
		axis_a = basis.x
		axis_b = basis.z

	var best := INF
	for i in range(48):
		var angle := (TAU / 48.0) * float(i)
		var ring_pt := center + (axis_a * cos(angle) + axis_b * sin(angle)) * radius
		if not cam.is_position_behind(ring_pt):
			best = minf(best, screen_pos.distance_to(cam.unproject_position(ring_pt)))
	return best

func _get_dot_mesh_by_id(dot_id: String) -> MeshInstance3D:
	for item in interactive_dots:
		if item["id"] == dot_id: return item["mesh"]
	return null

func _highlight_dot(dot_id: String) -> void:
	for item in interactive_dots:
		var mi: MeshInstance3D = item["mesh"]
		if mi and is_instance_valid(mi):
			var is_target: bool = (item["id"] == dot_id)
			var hover_scale := 1.55 if String(item["id"]).contains("ring_") else 1.70
			mi.scale = Vector3.ONE * (hover_scale if is_target else 1.0)
			var mat = mi.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color.WHITE if is_target else (item["color"] as Color)

func _apply_dot_world_drag(dot_id: String, world_pos: Vector3) -> void:
	if dot_id.begins_with("hurtbox:"):
		var region_key := StringName(dot_id.trim_prefix("hurtbox:"))
		var area := _hurtbox_region_area(region_key)
		if area != null:
			var world_delta := world_pos - drag_initial_world
			var local_delta := area.global_basis.orthonormalized().inverse() * world_delta
			_set_hitbox_offset(region_key, hitbox_drag_offset_start + local_delta)
			_apply_shared_hurtbox_preview()
			_sync_selected_hurtbox_controls()
		return
	match dot_id:
		"right_elbow_pole":
			_set_elbow_pole_from_world(&"right", world_pos)
		"left_elbow_pole":
			_set_elbow_pole_from_world(&"left", world_pos)
		"weapon_mount":
			if _editing_action_weapon_frame():
				var grip_world := _right_hand_grip_world_transform()
				var world_delta := world_pos - drag_initial_world
				animation_frame_weapon_position_correction = (
					frame_weapon_drag_position_start
					+ grip_world.basis.inverse() * world_delta
				)
				animation_frame_weapon_position_correction.x = clampf(animation_frame_weapon_position_correction.x, -0.25, 0.25)
				animation_frame_weapon_position_correction.y = clampf(animation_frame_weapon_position_correction.y, -0.25, 0.25)
				animation_frame_weapon_position_correction.z = clampf(animation_frame_weapon_position_correction.z, -0.25, 0.25)
			elif weapon_pivot:
				var parent_node := weapon_pivot.get_parent_node_3d()
				var local_pos := parent_node.global_transform.affine_inverse() * world_pos if parent_node else world_pos
				grip_offset_pos = local_pos - auto_grip_center_offset
				_sync_weapon_transform(false)
				_update_slider_value("grip_x", grip_offset_pos.x)
				_update_slider_value("grip_y", grip_offset_pos.y)
				_update_slider_value("grip_z", grip_offset_pos.z)
		"left_ik":
			if socket_root:
				left_grip_local_pos = socket_root.to_local(world_pos)
				_sync_hand_markers()
				_update_slider_value("ik_x", left_grip_local_pos.x)
				_update_slider_value("ik_y", left_grip_local_pos.y)
				_update_slider_value("ik_z", left_grip_local_pos.z)
		"muzzle":
			if socket_root:
				muzzle_local_pos = socket_root.to_local(world_pos)
				_sync_ballistic_markers()
				_update_slider_value("mz_x", muzzle_local_pos.x)
				_update_slider_value("mz_y", muzzle_local_pos.y)
				_update_slider_value("mz_z", muzzle_local_pos.z)
		"barrel_base":
			if socket_root:
				barrel_base_local_pos = socket_root.to_local(world_pos)
				_sync_ballistic_markers()
				_update_slider_value("bb_x", barrel_base_local_pos.x)
				_update_slider_value("bb_y", barrel_base_local_pos.y)
				_update_slider_value("bb_z", barrel_base_local_pos.z)
		"ejection":
			if socket_root:
				ejection_local_pos = socket_root.to_local(world_pos)
				_sync_markers()
				_update_slider_value("ej_x", ejection_local_pos.x)
				_update_slider_value("ej_y", ejection_local_pos.y)
				_update_slider_value("ej_z", ejection_local_pos.z)
		"optic":
			if socket_root:
				optic_local_pos = socket_root.to_local(world_pos)
				_sync_markers()
				_update_slider_value("op_x", optic_local_pos.x)
				_update_slider_value("op_y", optic_local_pos.y)
				_update_slider_value("op_z", optic_local_pos.z)
		"right_grip":
			if socket_root:
				right_grip_local_pos = socket_root.to_local(world_pos)
				_sync_hand_markers()
				_update_slider_value("rh_x", right_grip_local_pos.x)
				_update_slider_value("rh_y", right_grip_local_pos.y)
				_update_slider_value("rh_z", right_grip_local_pos.z)


func _pointer_over_editor_ui(screen_position: Vector2) -> bool:
	for control in [sidebar_panel, animation_frame_panel, rotation_panel]:
		if (
			control != null
			and (control as Control).visible
			and (control as Control).get_global_rect().has_point(screen_position)
		):
			return true
	return false


func _cancel_3d_authoring_pointer() -> void:
	mouse_fire_armed = false
	authoring_pointer_down = false
	dragged_dot_id = ""
	hovered_dot_id = ""
	_highlight_dot("")


func _set_elbow_pole_from_world(side: StringName, world_pos: Vector3) -> void:
	if not skeleton:
		return
	var body_basis := skeleton.global_transform.basis.orthonormalized()
	var wrist_world := _right_palm_contact_world() if side == &"right" else _left_palm_contact_world()
	var base_world := (
		_right_elbow_pole_base_world(wrist_world)
		if side == &"right"
		else _left_elbow_pole_base_world(wrist_world)
	)
	var local_offset := body_basis.inverse() * (world_pos - base_world)
	local_offset.x = clampf(local_offset.x, -0.30, 0.30)
	local_offset.y = clampf(local_offset.y, -0.30, 0.30)
	local_offset.z = clampf(local_offset.z, -0.30, 0.30)
	if side == &"right":
		right_elbow_pole_offset = local_offset
	else:
		left_elbow_pole_offset = local_offset
	_store_current_stance_elbow_poles()
	_update_elbow_slider_controls()


func _store_current_stance_elbow_poles() -> void:
	elbow_poles_by_stance[preview_posture] = {
		"right": right_elbow_pole_offset,
		"left": left_elbow_pole_offset,
	}


func _restore_current_stance_elbow_poles() -> void:
	var stance_value: Variant = elbow_poles_by_stance.get(preview_posture, {})
	var stance_poles: Dictionary = stance_value if stance_value is Dictionary else {}
	right_elbow_pole_offset = stance_poles.get("right", Vector3.ZERO)
	left_elbow_pole_offset = stance_poles.get("left", Vector3.ZERO)
	_update_elbow_slider_controls()


func _update_elbow_slider_controls() -> void:
	for entry in [
		["right_elbow_x", right_elbow_pole_offset.x],
		["right_elbow_y", right_elbow_pole_offset.y],
		["right_elbow_z", right_elbow_pole_offset.z],
		["left_elbow_x", left_elbow_pole_offset.x],
		["left_elbow_y", left_elbow_pole_offset.y],
		["left_elbow_z", left_elbow_pole_offset.z],
	]:
		_update_slider_value(entry[0], entry[1])


func _set_elbow_component(value: float, side: StringName, axis: StringName) -> void:
	var offset := right_elbow_pole_offset if side == &"right" else left_elbow_pole_offset
	match axis:
		&"x": offset.x = value
		&"y": offset.y = value
		&"z": offset.z = value
	if side == &"right":
		right_elbow_pole_offset = offset
	else:
		left_elbow_pole_offset = offset
	_store_current_stance_elbow_poles()


func _elbow_poles_save_data() -> Dictionary:
	_store_current_stance_elbow_poles()
	var saved: Dictionary = {}
	for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var stance_poles: Dictionary = elbow_poles_by_stance.get(posture, {})
		saved[String(posture)] = {
			"right": _vector_to_data(stance_poles.get("right", Vector3.ZERO)),
			"left": _vector_to_data(stance_poles.get("left", Vector3.ZERO)),
		}
	return saved

func _update_slider_value(slider_key: String, val: float) -> void:
	if sliders_map.has(slider_key):
		var s: HSlider = sliders_map[slider_key]["slider"]
		var lbl: Label = sliders_map[slider_key]["label"]
		if s:
			s.set_value_no_signal(val)
			if lbl: lbl.text = "%.2f" % val if absf(val) >= 5.0 else ("%.3f" % val)


func _setup_elbow_pole_visuals() -> void:
	right_elbow_pole_marker = _create_marker(Color(1.0, 0.25, 0.9), "RightElbowIKPole", 0.016)
	left_elbow_pole_marker = _create_marker(Color(0.75, 0.35, 1.0), "LeftElbowIKPole", 0.016)
	add_child(right_elbow_pole_marker)
	add_child(left_elbow_pole_marker)
	joint_debug_instance = MeshInstance3D.new()
	joint_debug_instance.name = "ElbowSkeletonFrame"
	joint_debug_instance.mesh = joint_debug_mesh
	var line_material := StandardMaterial3D.new()
	line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	line_material.vertex_color_use_as_albedo = true
	line_material.no_depth_test = true
	joint_debug_instance.material_override = line_material
	add_child(joint_debug_instance)
	_register_interactive_dots()


func _setup_body_joint_visuals() -> void:
	for joint_name: StringName in TUNABLE_BODY_JOINTS:
		var marker := _create_marker(Color(0.15, 0.85, 1.0), "BodyJoint_%s" % String(joint_name), 0.012)
		add_child(marker)
		body_joint_markers[joint_name] = marker
	_register_interactive_dots()


func _update_body_joint_visuals() -> void:
	if runtime_posture_layer == null:
		return
	for joint_name: StringName in body_joint_markers:
		var bone_index := int(runtime_posture_layer.bone_indices.get(joint_name, -1))
		var marker := body_joint_markers[joint_name] as MeshInstance3D
		if active_lab_tab_name == "Composure" or not show_joint_bubbles:
			marker.visible = false
		elif isolate_selected_node:
			marker.visible = (joint_name == selected_body_joint) and (bone_index >= 0)
		else:
			marker.visible = bone_index >= 0
		if bone_index >= 0:
			marker.global_position = _bone_world_origin(bone_index)


func _select_body_joint(joint_name: StringName) -> void:
	if joint_name not in TUNABLE_BODY_JOINTS:
		return
	selected_body_joint = joint_name
	_sync_body_joint_controls()
	if hud_status:
		hud_status.text = "🔷 Editing %s for %s. Drag for pitch/yaw; wheel for roll." % [
			String(joint_name).replace("_", " "),
			String(preview_posture).capitalize(),
		]


func _adjust_selected_joint_rotation(delta_degrees: Vector3) -> void:
	if runtime_posture_layer == null:
		return
	match JointControlSchema.control_mode(selected_body_joint):
		&"elbow_pole":
			var side: StringName = &"right" if selected_body_joint == &"right_forearm" else &"left"
			var offset := right_elbow_pole_offset if side == &"right" else left_elbow_pole_offset
			offset += delta_degrees * 0.0025
			if side == &"right":
				right_elbow_pole_offset = offset
			else:
				left_elbow_pole_offset = offset
			_store_current_stance_elbow_poles()
		&"hand_target":
			var delta := delta_degrees * 0.0015
			if selected_body_joint == &"left_hand":
				left_grip_local_pos += delta
				left_grip_local_pos = left_grip_local_pos.clamp(Vector3(-0.40, -0.20, -0.20), Vector3(1.20, 0.20, 0.20))
			else:
				right_grip_local_pos += delta
				right_grip_local_pos = right_grip_local_pos.clamp(Vector3(-1.50, -1.50, -1.50), Vector3(1.50, 1.50, 1.50))
			_sync_markers()
		_:
			_apply_joint_chain_delta(selected_body_joint, delta_degrees)
	_sync_body_joint_controls()


func _set_body_joint_component(value: float, axis: StringName) -> void:
	if runtime_posture_layer == null:
		return
	var mode: StringName = JointControlSchema.control_mode(selected_body_joint)
	if mode == &"elbow_pole":
		var side: StringName = &"right" if selected_body_joint == &"right_forearm" else &"left"
		_set_elbow_component(value, side, axis)
		_sync_body_joint_controls()
		return
	if mode == &"hand_target":
		var target := left_grip_local_pos if selected_body_joint == &"left_hand" else right_grip_local_pos
		match axis:
			&"x": target.x = value
			&"y": target.y = value
			&"z": target.z = value
		if selected_body_joint == &"left_hand":
			left_grip_local_pos = target
		else:
			right_grip_local_pos = target
		_sync_markers()
		_sync_body_joint_controls()
		return
	var rotation := runtime_posture_layer.get_procedural_rotation_degrees(preview_posture, selected_body_joint)
	match axis:
		&"x":
			_apply_joint_chain_delta(selected_body_joint, Vector3(value - rotation.x, 0.0, 0.0))
		&"y":
			_apply_joint_chain_delta(selected_body_joint, Vector3(0.0, value - rotation.y, 0.0))
		&"z":
			_apply_joint_chain_delta(selected_body_joint, Vector3(0.0, 0.0, value - rotation.z))
	_sync_body_joint_controls()


func _apply_joint_chain_delta(joint_name: StringName, delta_degrees: Vector3) -> void:
	var rotation := runtime_posture_layer.get_procedural_rotation_degrees(preview_posture, joint_name)
	runtime_posture_layer.set_procedural_rotation_degrees(
		preview_posture,
		joint_name,
		rotation + delta_degrees
	)
	var links: Dictionary = JOINT_CHAIN_LINKS.get(joint_name, {})
	for linked_joint: StringName in links:
		var linked_rotation := runtime_posture_layer.get_procedural_rotation_degrees(
			preview_posture,
			linked_joint
		)
		runtime_posture_layer.set_procedural_rotation_degrees(
			preview_posture,
			linked_joint,
			linked_rotation + delta_degrees * float(links[linked_joint])
		)


func _sync_body_joint_controls() -> void:
	if runtime_posture_layer == null:
		return
	var mode: StringName = JointControlSchema.control_mode(selected_body_joint)
	var values := Vector3.ZERO
	var maximums := Vector3(55.0, 55.0, 55.0)
	if mode == &"elbow_pole":
		values = right_elbow_pole_offset if selected_body_joint == &"right_forearm" else left_elbow_pole_offset
		maximums = Vector3(0.30, 0.30, 0.30)
	elif mode == &"hand_target":
		values = left_grip_local_pos if selected_body_joint == &"left_hand" else right_grip_local_pos
		maximums = Vector3(1.20, 0.20, 0.20) if selected_body_joint == &"left_hand" else Vector3(1.50, 1.50, 1.50)
	else:
		values = runtime_posture_layer.get_procedural_rotation_degrees(preview_posture, selected_body_joint)
		maximums = runtime_posture_layer.get_procedural_axis_limits_degrees(selected_body_joint)
	var keys := ["body_joint_pitch", "body_joint_yaw", "body_joint_roll"]
	var labels: PackedStringArray = JointControlSchema.axis_labels(selected_body_joint)
	for index in range(3):
		var entry: Dictionary = sliders_map.get(keys[index], {})
		var slider := entry.get("slider") as HSlider
		var name_label := entry.get("name_label") as Label
		if slider:
			slider.min_value = -maximums[index]
			slider.max_value = maximums[index]
			slider.step = 0.005 if maximums[index] <= 2.0 else 0.5
			slider.set_value_no_signal(values[index])
		if name_label:
			name_label.text = labels[index] + ":"
		_update_slider_value(keys[index], values[index])
	if selected_joint_title:
		selected_joint_title.text = "SELECTED JOINT — %s" % JointControlSchema.display_name(selected_body_joint).to_upper()
	if selected_joint_help:
		selected_joint_help.text = JointControlSchema.help_text(selected_body_joint)
	if hud_status:
		hud_status.text = "%s — %s" % [JointControlSchema.display_name(selected_body_joint), JointControlSchema.help_text(selected_body_joint)]


func _bone_world_origin(bone_index: int) -> Vector3:
	if not skeleton or bone_index < 0:
		return Vector3.ZERO
	return (skeleton.global_transform * skeleton.get_bone_global_pose(bone_index)).origin


func _update_elbow_pole_visuals() -> void:
	if not skeleton or not right_elbow_pole_marker or not left_elbow_pole_marker:
		return
	var right_pole := _right_elbow_pole_world(_right_palm_contact_world())
	var left_pole := _left_elbow_pole_world(_left_palm_contact_world())
	right_elbow_pole_marker.global_position = right_pole
	left_elbow_pole_marker.global_position = left_pole
	joint_debug_mesh.clear_surfaces()
	joint_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	_add_debug_segment(_bone_world_origin(right_arm_idx), _bone_world_origin(right_forearm_idx), Color(0.1, 0.95, 1.0))
	_add_debug_segment(_bone_world_origin(right_forearm_idx), _bone_world_origin(right_hand_idx), Color(0.1, 0.95, 1.0))
	_add_debug_segment(_bone_world_origin(right_arm_idx), right_pole, Color(1.0, 0.25, 0.9))
	_add_debug_segment(_bone_world_origin(left_arm_idx), _bone_world_origin(left_forearm_idx), Color(0.1, 0.95, 1.0))
	_add_debug_segment(_bone_world_origin(left_forearm_idx), _bone_world_origin(left_hand_idx), Color(0.1, 0.95, 1.0))
	_add_debug_segment(_bone_world_origin(left_arm_idx), left_pole, Color(0.75, 0.35, 1.0))
	joint_debug_mesh.surface_end()


func _add_debug_segment(from: Vector3, to: Vector3, color: Color) -> void:
	joint_debug_mesh.surface_set_color(color)
	joint_debug_mesh.surface_add_vertex(from)
	joint_debug_mesh.surface_set_color(color)
	joint_debug_mesh.surface_add_vertex(to)

func _setup_studio_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.12, 0.14, 0.17)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.85, 0.88, 0.95)

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 75, 0)
	key.light_color = Color(1.0, 0.98, 0.92)
	key.light_energy = 1.6
	key.shadow_enabled = true
	add_child(key)

	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, 0, 0)
	fill.light_color = Color(0.6, 0.7, 0.85)
	fill.light_energy = 0.9
	add_child(fill)

	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(20, -160, 0)
	rim.light_color = Color(0.3, 0.9, 1.0)
	rim.light_energy = 1.0
	add_child(rim)

	var floor_mesh := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(30.0, 30.0)
	floor_mesh.mesh = plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color(0.16, 0.17, 0.20)
	floor_mat.roughness = 0.9
	floor_mesh.material_override = floor_mat
	add_child(floor_mesh)

	cam_pivot = Node3D.new()
	add_child(cam_pivot)
	cam = Camera3D.new()
	cam_pivot.add_child(cam)
	cam.current = true
	_update_camera()

	bullet_tracers = Node3D.new()
	add_child(bullet_tracers)

	fire_debug_material = StandardMaterial3D.new()
	fire_debug_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fire_debug_material.vertex_color_use_as_albedo = true
	fire_debug_material.no_depth_test = true
	fire_debug_instance = MeshInstance3D.new()
	fire_debug_instance.name = "WeaponFireDebugLayers"
	fire_debug_instance.mesh = fire_debug_mesh
	fire_debug_instance.material_override = fire_debug_material
	fire_debug_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fire_debug_instance)

func _update_camera() -> void:
	if not cam_pivot or not cam: return
	cam_pivot.position = cam_target
	cam_pivot.rotation_degrees = Vector3(cam_pitch, cam_yaw, 0)
	cam.position = Vector3(0, 0, cam_distance)

func _set_camera_preset(preset_name: String) -> void:
	match preset_name:
		"hands":
			cam_target = Vector3(0.08, 1.22, 0.05)
			cam_distance = 0.80
			cam_yaw = 60.0
			cam_pitch = -8.0
		"ots":
			cam_target = Vector3(0.12, 1.28, 0.0)
			cam_distance = 1.2
			cam_yaw = 15.0
			cam_pitch = -6.0
		"side":
			cam_target = Vector3(0.0, 1.22, 0.0)
			cam_distance = 1.1
			cam_yaw = 90.0
			cam_pitch = 0.0
		"full":
			cam_target = Vector3(0.0, 0.95, 0.0)
			cam_distance = 2.2
			cam_yaw = 35.0
			cam_pitch = -12.0
	_update_camera()

func _setup_trooper_and_rig() -> void:
	trooper_node = PS1_GAS_MASK_RIGGED_SCENE.instantiate() as Node3D
	trooper_node.scale = Vector3.ONE * trooper_scale
	add_child(trooper_node)

	skeleton = _find_skeleton(trooper_node)
	_ensure_65_bone_contract()
	_apply_pixel_texture(trooper_node)

	left_arm_idx = skeleton.find_bone("mixamorig_LeftArm")
	left_forearm_idx = skeleton.find_bone("mixamorig_LeftForeArm")
	left_hand_idx = skeleton.find_bone("mixamorig_LeftHand")
	right_arm_idx = skeleton.find_bone("mixamorig_RightArm")
	right_forearm_idx = skeleton.find_bone("mixamorig_RightForeArm")
	right_hand_idx = skeleton.find_bone("mixamorig_RightHand")
	head_idx = skeleton.find_bone("mixamorig_Head")
	for anchor_name in ["mixamorig_Spine2", "mixamorig_Spine1", "mixamorig_Spine"]:
		weapon_anchor_bone_idx = skeleton.find_bone(anchor_name)
		if weapon_anchor_bone_idx >= 0:
			break
	left_palm_anchor_local = _calculate_palm_anchor("Left", left_hand_idx)
	right_palm_anchor_local = _calculate_palm_anchor("Right", right_hand_idx)

	animation_player = AnimationPlayer.new()
	animation_player.name = "AnimationPlayer"
	animation_player.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	skeleton.add_child(animation_player)
	animation_player.root_node = animation_player.get_path_to(skeleton)

	var aim_fbx_path := "res://assets/animations/mixamo/Shooter Pack/rifle aiming idle.fbx"
	var packed_anim := load(aim_fbx_path) as PackedScene
	if packed_anim:
		var temp := packed_anim.instantiate()
		var temp_ap := _find_animation_player(temp)
		if temp_ap and not temp_ap.get_animation_list().is_empty():
			var anim_name: StringName = temp_ap.get_animation_list()[0]
			for a in temp_ap.get_animation_list():
				if a != &"RESET": anim_name = a; break
			var src_anim := temp_ap.get_animation(anim_name)
			var lib := AnimationLibrary.new()
			var retargeted := _retarget_aim_anim(src_anim)
			retargeted.loop_mode = Animation.LOOP_LINEAR
			lib.add_animation("aim_idle", retargeted)

			var reload_path := "res://assets/animations/mixamo/Shooter Pack/reloading.fbx"
			if FileAccess.file_exists(reload_path):
				var r_scene := load(reload_path) as PackedScene
				if r_scene:
					var r_temp := r_scene.instantiate()
					var r_ap := _find_animation_player(r_temp)
					if r_ap and not r_ap.get_animation_list().is_empty():
						var r_src := r_ap.get_animation(r_ap.get_animation_list()[0])
						var r_ret := _retarget_aim_anim(r_src)
						lib.add_animation("reload", r_ret)
					r_temp.queue_free()

			animation_player.add_animation_library("", lib)
			animation_player.play("aim_idle")
		temp.queue_free()

	runtime_posture_layer = OperatorPostureLayer.new()
	runtime_posture_layer.bind(skeleton, _neutral_preview_hip_rotation())

	if left_arm_idx >= 0 and left_hand_idx >= 0:
		left_hand_ik = SkeletonIK3D.new()
		left_hand_ik.name = "LeftHandIK"
		left_hand_ik.root_bone = "mixamorig_LeftArm"
		left_hand_ik.tip_bone = "mixamorig_LeftHand"
		left_hand_ik.use_magnet = true
		left_hand_ik.interpolation = 1.0
		left_hand_ik.override_tip_basis = true
		left_hand_ik.max_iterations = 40
		left_hand_ik.min_distance = 0.00002
		left_hand_ik.magnet = Vector3(-0.35, -0.75, 0.15)
		skeleton.add_child(left_hand_ik)
		# Keep IK stopped until two-stage bootstrap completes.
		left_hand_ik.stop()

	var inv_scale := 1.0 / trooper_scale

	if right_hand_idx >= 0:
		ba_right_hand = BoneAttachment3D.new()
		ba_right_hand.name = "BA_RightHand"
		ba_right_hand.bone_name = "mixamorig_RightHand"
		skeleton.add_child(ba_right_hand)
		right_hand_dot = _create_marker(Color(1.0, 0.6, 0.1), "RightHand_Bone_Dot", 0.028 * inv_scale)
		ba_right_hand.add_child(right_hand_dot)

		var mount_basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(180.0), 0.0)).scaled(Vector3.ONE * inv_scale)
		weapon_mount_local = Transform3D(mount_basis, Vector3(-0.02, 0.08, 0.05) * inv_scale)

		weapon_root = Node3D.new()
		weapon_root.name = "WeaponRoot"
		skeleton.add_child(weapon_root)

		weapon_pivot = Node3D.new()
		weapon_pivot.name = "WeaponPivot"
		weapon_root.add_child(weapon_pivot)

		geometry_root = Node3D.new()
		geometry_root.name = "GeometryRoot"
		weapon_pivot.add_child(geometry_root)

		socket_root = Node3D.new()
		socket_root.name = "SocketRoot"
		weapon_pivot.add_child(socket_root)

		right_hand_ik = SkeletonIK3D.new()
		right_hand_ik.name = "RightHandIK"
		right_hand_ik.root_bone = "mixamorig_RightArm"
		right_hand_ik.tip_bone = "mixamorig_RightHand"
		right_hand_ik.use_magnet = true
		right_hand_ik.interpolation = 1.0
		right_hand_ik.override_tip_basis = true
		right_hand_ik.max_iterations = 40
		right_hand_ik.min_distance = 0.00002
		skeleton.add_child(right_hand_ik)
		# Keep IK stopped until two-stage bootstrap completes.
		right_hand_ik.stop()

	eye_sight_marker = Marker3D.new()
	eye_sight_marker.name = "EyeSightOrigin"
	add_child(eye_sight_marker)
	eye_sight_dot = _create_marker(Color(0.25, 0.55, 1.0), "EyeSightDot", 0.014)
	eye_sight_marker.add_child(eye_sight_dot)
	_update_eye_sight_marker()


func _neutral_preview_hip_rotation() -> Quaternion:
	if animation_player == null or not animation_player.has_animation(&"aim_idle"):
		return Quaternion.IDENTITY
	var animation := animation_player.get_animation(&"aim_idle")
	if animation == null:
		return Quaternion.IDENTITY
	for track in range(animation.get_track_count()):
		if animation.track_get_type(track) != Animation.TYPE_ROTATION_3D:
			continue
		if not str(animation.track_get_path(track)).ends_with(":mixamorig_Hips"):
			continue
		if animation.track_get_key_count(track) > 0:
			return (animation.track_get_key_value(track, 0) as Quaternion).normalized()
	return Quaternion.IDENTITY


func _get_gunsmith_fixed_aim_target() -> Vector3:
	if skeleton == null:
		return Vector3(0.0, 1.25, -50.0)
	var forward: Vector3 = -skeleton.global_basis.z.normalized()
	return skeleton.global_position + Vector3.UP * 1.25 + forward * 50.0


func _apply_runtime_posture_preview() -> void:
	if runtime_posture_layer == null or skeleton == null:
		return

	var aim_target: Vector3 = _get_gunsmith_fixed_aim_target()

	# Optional debugging mode only
	if gunsmith_camera_tracking_enabled and cam != null:
		aim_target = _camera_aim_sample().position

	runtime_posture_layer.apply(
		0.0,
		0.0,
		1.0,
		0.0,
		0.0,
		deg_to_rad(78.0),
		deg_to_rad(48.0),
		deg_to_rad(42.0),
		deg_to_rad(32.0),
		0.0,
		0.18,
		0.0,
		deg_to_rad(90.0),
		0.0,
		preview_posture,
		0.0,
		aim_target,
		preview_hip_level_trim_deg
	)


func _initialize_weapon_master_pose() -> void:
	if weapon_master_pose_initialized or not weapon_root or not _right_hand_pose_is_ready():
		return
	var hand_world := _get_right_hand_world_transform()
	weapon_root.global_transform = hand_world * weapon_mount_local
	_capture_weapon_anchor()
	weapon_master_pose_initialized = true
	_sync_weapon_transform(false)
	_sync_markers()
	_register_interactive_dots()
	_set_weapon_ik_enabled(true)
	_set_save_enabled(true)


func _set_weapon_ik_enabled(enabled: bool) -> void:
	if right_hand_ik:
		if enabled:
			if not right_hand_ik.is_running():
				right_hand_ik.start(true)
		else:
			if right_hand_ik.is_running():
				right_hand_ik.stop()
	if left_hand_ik:
		if enabled:
			if not left_hand_ik.is_running():
				left_hand_ik.start(true)
		else:
			if left_hand_ik.is_running():
				left_hand_ik.stop()


func _set_save_enabled(enabled: bool) -> void:
	if save_rig_button:
		save_rig_button.disabled = not enabled
	if play_latest_button:
		play_latest_button.disabled = not enabled


func _get_right_hand_bone_index() -> int:
	if right_hand_idx >= 0:
		return right_hand_idx
	if ba_right_hand != null and ba_right_hand.bone_idx >= 0:
		return ba_right_hand.bone_idx
	if skeleton != null:
		return skeleton.find_bone("mixamorig_RightHand")
	return -1


func _get_right_hand_world_transform() -> Transform3D:
	var bone_index: int = _get_right_hand_bone_index()
	if bone_index < 0 or skeleton == null:
		return ba_right_hand.global_transform if ba_right_hand else Transform3D.IDENTITY
	var skeleton_local_pose: Transform3D = skeleton.get_bone_global_pose(bone_index)
	return skeleton.global_transform * skeleton_local_pose


func _weapon_anchor_world_transform() -> Transform3D:
	if skeleton == null or weapon_anchor_bone_idx < 0:
		return skeleton.global_transform if skeleton else Transform3D.IDENTITY
	return (
		skeleton.global_transform
		* skeleton.get_bone_global_pose(weapon_anchor_bone_idx)
	)


func _capture_weapon_anchor() -> void:
	if weapon_root == null or skeleton == null:
		return
	# Store rifle orientation in operator space. Store only the chest position
	# separately. This lets stance carry the rifle without inheriting a bent or
	# rolling torso bone's rotation.
	weapon_anchor_local = skeleton.global_transform.affine_inverse() * weapon_root.global_transform
	weapon_anchor_bone_origin = (
		skeleton.get_bone_global_pose(weapon_anchor_bone_idx).origin
		if weapon_anchor_bone_idx >= 0
		else Vector3.ZERO
	)
	weapon_anchor_ready = true


func _weapon_anchor_target_transform() -> Transform3D:
	if not weapon_anchor_ready:
		return weapon_root.global_transform if weapon_root else Transform3D.IDENTITY
	var target_local := weapon_anchor_local
	var current_anchor_origin := (
		skeleton.get_bone_global_pose(weapon_anchor_bone_idx).origin
		if weapon_anchor_bone_idx >= 0
		else Vector3.ZERO
	)
	target_local.origin += current_anchor_origin - weapon_anchor_bone_origin
	return skeleton.global_transform * target_local


func _update_weapon_master_anchor() -> void:
	if (
		weapon_root == null
		or not weapon_anchor_ready
		or weapon_owner_state != WeaponOwnershipContract.OWNER_WEAPON_MASTER
		or action_weapon_follow_active
		or action_recovery_elapsed < action_recovery_duration
	):
		return
	# The chest-relative anchor carries the rifle with the operator. The weapon
	# remains the pose master; both arms solve to its authored grip sockets.
	weapon_root.global_transform = _weapon_anchor_target_transform()


func _gunsmith_live_aim_active() -> bool:
	return (
		live_weapon_aim_enabled
		and active_lab_tab_name != "Composure"
		and weapon_master_pose_initialized
		and weapon_owner_state == WeaponOwnershipContract.OWNER_WEAPON_MASTER
		and not action_weapon_follow_active
		and not is_reloading
		and not authoring_pointer_down
		and dragged_dot_id == ""
		and (animation_frame_editor == null or not animation_frame_editor.active)
	)


func _update_live_aim_weapon_pose() -> void:
	gunsmith_live_aim_rotation = Quaternion.IDENTITY
	if (
		not _gunsmith_live_aim_active()
		or weapon_root == null
		or right_grip_marker == null
		or barrel_base_marker == null
		or muzzle_marker == null
	):
		return
	var trigger_world := right_grip_marker.global_position
	var current_direction := _barrel_direction_world()
	if current_direction.length_squared() < 0.50:
		return
	# Gunsmith aim preview is deliberately independent of the inspection camera.
	# Yaw turns around the operator's up axis; pitch follows the yawed weapon-right
	# axis. Both rotate the attached hand-and-rifle unit around the trigger grip.
	var up_axis := skeleton.global_basis.y.normalized() if skeleton != null else Vector3.UP
	var right_axis := current_direction.cross(up_axis).normalized()
	if right_axis.length_squared() < 0.50:
		right_axis = weapon_root.global_basis.x.normalized()
	var yaw_delta := Quaternion(up_axis, deg_to_rad(live_weapon_yaw_deg))
	var yawed_right_axis := (yaw_delta * right_axis).normalized()
	var pitch_delta := Quaternion(yawed_right_axis, deg_to_rad(live_weapon_pitch_deg))
	var aim_delta := (pitch_delta * yaw_delta).normalized()
	gunsmith_live_aim_rotation = aim_delta
	var world_scale := weapon_root.global_basis.get_scale()
	weapon_root.global_basis = (
		Basis(aim_delta) * weapon_root.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale)
	weapon_root.global_position += trigger_world - right_grip_marker.global_position


func _update_visual_weapon_recoil(delta: float) -> void:
	visual_recoil_pitch_deg = lerpf(
		visual_recoil_pitch_deg,
		0.0,
		1.0 - exp(-VISUAL_RECOIL_RECOVERY * delta)
	)
	visual_recoil_back_m = lerpf(
		visual_recoil_back_m,
		0.0,
		1.0 - exp(-VISUAL_RECOIL_RECOVERY * delta)
	)
	if (
		weapon_root == null
		or weapon_owner_state != WeaponOwnershipContract.OWNER_WEAPON_MASTER
		or visual_recoil_pitch_deg <= 0.001
	):
		return
	var barrel_direction := _barrel_direction_world()
	var pitch_axis := barrel_direction.cross(Vector3.UP).normalized()
	if pitch_axis.length_squared() < 0.50:
		pitch_axis = weapon_root.global_basis.x.normalized()
	var world_scale := weapon_root.global_basis.get_scale()
	weapon_root.global_basis = (
		Basis(Quaternion(pitch_axis, deg_to_rad(visual_recoil_pitch_deg)))
		* weapon_root.global_basis.orthonormalized()
	).orthonormalized().scaled(world_scale)
	weapon_root.global_position -= barrel_direction * visual_recoil_back_m


func _right_hand_pose_is_ready() -> bool:
	var bone_index: int = _get_right_hand_bone_index()
	if bone_index < 0 or skeleton == null:
		return false
	var pose: Transform3D = skeleton.get_bone_global_pose(bone_index)
	var rest: Transform3D = skeleton.get_bone_global_rest(bone_index)
	if not pose.origin.is_finite():
		return false
	if absf(pose.basis.determinant()) < 0.0001:
		return false
	if pose.origin.length() < 0.05 and rest.origin.length() > 0.25:
		return false
	return true


func _load_operator_mount(profile: Dictionary) -> void:
	var mount_value: Variant = profile.get("operator_mount", null)
	var inv_scale: float = 1.0 / trooper_scale
	if typeof(mount_value) != TYPE_DICTIONARY:
		var mount_basis := Basis.from_euler(Vector3(deg_to_rad(-90.0), deg_to_rad(180.0), 0.0)).scaled(Vector3.ONE * inv_scale)
		weapon_mount_local = Transform3D(mount_basis, Vector3(-0.02, 0.08, 0.05) * inv_scale)
		return
	var mount: Dictionary = mount_value
	var fallback_rotation_degrees: Vector3 = _radians_to_degrees_vector(
		weapon_mount_local.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)
	)
	var mount_position: Vector3 = _dictionary_to_vector3(
		mount.get("position", {}),
		Vector3(-0.02, 0.08, 0.05)
	) * inv_scale
	var mount_rotation_degrees: Vector3 = _dictionary_to_vector3(
		mount.get("rotation_degrees", {}),
		fallback_rotation_degrees
	)
	var mount_rotation_radians: Vector3 = _degrees_to_radians_vector(mount_rotation_degrees)
	var mount_basis := Basis.from_euler(mount_rotation_radians, EULER_ORDER_YXZ).scaled(Vector3.ONE * inv_scale)
	weapon_mount_local = Transform3D(
		mount_basis,
		mount_position
	)


func _dictionary_to_vector3(value: Variant, fallback: Vector3) -> Vector3:
	if typeof(value) != TYPE_DICTIONARY:
		return fallback
	var data: Dictionary = value
	return Vector3(
		float(data.get("x", fallback.x)),
		float(data.get("y", fallback.y)),
		float(data.get("z", fallback.z))
	)


func _vector3_to_dictionary(v: Vector3) -> Dictionary:
	return {"x": v.x, "y": v.y, "z": v.z}


func _degrees_to_radians_vector(value: Vector3) -> Vector3:
	return Vector3(deg_to_rad(value.x), deg_to_rad(value.y), deg_to_rad(value.z))


func _radians_to_degrees_vector(value: Vector3) -> Vector3:
	return Vector3(rad_to_deg(value.x), rad_to_deg(value.y), rad_to_deg(value.z))


func _world_drag_to_parent_local_delta(parent_node: Node3D, world_start: Vector3, world_current: Vector3) -> Vector3:
	if parent_node == null:
		return world_current - world_start
	var parent_inverse: Transform3D = parent_node.global_transform.affine_inverse()
	var local_start: Vector3 = parent_inverse * world_start
	var local_current: Vector3 = parent_inverse * world_current
	return local_current - local_start


func _show_rig_error(msg: String) -> void:
	push_warning(msg)
	if hud_status:
		hud_status.text = "⚠️ " + msg
		hud_status.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))


func _validate_weapon_rig_before_save() -> bool:
	if not weapon_master_pose_initialized:
		_show_rig_error("The weapon pose has not finished initializing. Save blocked.")
		return false
	var serialized_grip_position: Vector3 = auto_grip_center_offset + grip_offset_pos
	if not serialized_grip_position.is_finite():
		_show_rig_error("Grip offset contains a non-finite value. Save blocked.")
		return false
	if serialized_grip_position.length() > MAX_GRIP_OFFSET_RADIUS_METERS:
		_show_rig_error("Grip offset is outside safe local range (%.2fm > %.2fm). Save blocked." % [serialized_grip_position.length(), MAX_GRIP_OFFSET_RADIUS_METERS])
		return false
	var hand_world: Transform3D = _get_right_hand_world_transform()
	var grip_target_world: Vector3 = (
		right_grip_marker.global_position
		if right_grip_marker
		else (weapon_pivot.global_transform * right_grip_local_pos if weapon_pivot else Vector3.ZERO)
	)
	var hand_to_grip_error: float = hand_world.origin.distance_to(grip_target_world)
	if hand_to_grip_error > MAX_HAND_TO_GRIP_ERROR_METERS:
		_show_rig_error("Right-hand grip target is detached by %.3fm (max %.2fm). Save blocked." % [hand_to_grip_error, MAX_HAND_TO_GRIP_ERROR_METERS])
		return false
	if not muzzle_local_pos.is_finite() or not barrel_base_local_pos.is_finite():
		_show_rig_error("Muzzle or barrel-base socket contains a non-finite value. Save blocked.")
		return false
	var barrel_axis_length := muzzle_local_pos.distance_to(barrel_base_local_pos)
	if barrel_axis_length < MIN_BARREL_AXIS_LENGTH_METERS:
		_show_rig_error(
			"Muzzle must stay at least %.2fm from the barrel-base socket. Save blocked."
			% MIN_BARREL_AXIS_LENGTH_METERS
		)
		return false
	return true


func _finish_weapon_bootstrap() -> void:
	if animation_player != null:
		animation_player.advance(0.0)
	await get_tree().process_frame

	if not _right_hand_pose_is_ready():
		push_error("Gunsmith bootstrap aborted: right-hand pose was not valid.")
		return

	var hand_world: Transform3D = _get_right_hand_world_transform()
	if weapon_root:
		weapon_root.global_transform = hand_world * weapon_mount_local
		_capture_weapon_anchor()

	weapon_master_pose_initialized = true

	_sync_weapon_transform(false)
	_sync_markers()
	_register_interactive_dots()

	if left_hand_ik and left_grip_marker:
		left_hand_ik.target_node = NodePath()

	_set_weapon_ik_enabled(true)
	_set_save_enabled(true)
	if hud_status:
		hud_status.text = "Ready! (Biomechanical Engine Active | Drag Blue Dot to place hand | Space to Fire)"
		hud_status.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))

func _calculate_palm_anchor(side: String, hand_index: int) -> Vector3:
	if not skeleton or hand_index < 0:
		return Vector3.ZERO
	var hand_rest := _get_bone_global_rest(hand_index)
	var palm_points: Array[Vector3] = []
	for finger_name in ["Thumb", "Index", "Middle", "Ring", "Pinky"]:
		var bone_name := "mixamorig_%sHand%s1" % [side, finger_name]
		var bone_idx := skeleton.find_bone(bone_name)
		if bone_idx >= 0:
			palm_points.append(hand_rest.affine_inverse() * _get_bone_global_rest(bone_idx).origin)
	if palm_points.is_empty():
		return Vector3.ZERO
	var anchor := Vector3.ZERO
	for point in palm_points:
		anchor += point
	return anchor / float(palm_points.size())


func _right_palm_contact_world() -> Vector3:
	if not skeleton or right_hand_idx < 0:
		return Vector3.ZERO
	var hand_pose := skeleton.get_bone_global_pose(right_hand_idx)
	return skeleton.global_transform * (hand_pose * right_palm_anchor_local)

func _left_palm_contact_world() -> Vector3:
	if not skeleton or left_hand_idx < 0:
		return Vector3.ZERO
	var hand_pose := skeleton.get_bone_global_pose(left_hand_idx)
	return skeleton.global_transform * (hand_pose * left_palm_anchor_local)

func _get_bone_global_rest(bone_idx: int) -> Transform3D:
	var chain: Array[Transform3D] = []
	var current_idx := bone_idx
	while current_idx >= 0:
		chain.push_front(skeleton.get_bone_rest(current_idx))
		current_idx = skeleton.get_bone_parent(current_idx)
	var result := Transform3D.IDENTITY
	for local_rest in chain:
		result = result * local_rest
	return result

func _setup_target_range() -> void:
	target_board = Node3D.new()
	target_board.position = Vector3(0.0, 1.25, 6.0)
	add_child(target_board)

	var board_mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.2, 1.6, 0.08)
	board_mesh.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.22, 0.18)
	board_mesh.material_override = mat
	target_board.add_child(board_mesh)

	var board_body := StaticBody3D.new()
	board_body.name = "ReticleTargetBody"
	board_body.set_meta("gun_lab_target", true)
	var board_shape := CollisionShape3D.new()
	var board_box := BoxShape3D.new()
	board_box.size = Vector3(1.2, 1.6, 0.08)
	board_shape.shape = board_box
	board_body.add_child(board_shape)
	target_board.add_child(board_body)

	var bullseye := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.3
	cyl.bottom_radius = 0.3
	cyl.height = 0.1
	bullseye.mesh = cyl
	bullseye.rotation_degrees = Vector3(90, 0, 0)
	bullseye.position = Vector3(0, 0.15, 0.01)
	var bull_mat := StandardMaterial3D.new()
	bull_mat.albedo_color = Color(0.85, 0.15, 0.15)
	bullseye.material_override = bull_mat
	target_board.add_child(bullseye)

func _create_axis_arrow(color: Color, axis_dir: Vector3, arrow_name: String, length: float = 0.26) -> Node3D:
	var root := Node3D.new()
	root.name = arrow_name

	var shaft := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 0.008
	cyl.bottom_radius = 0.008
	cyl.height = length
	shaft.mesh = cyl

	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.020
	cone.height = 0.050
	head.mesh = cone

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 110
	mat.no_depth_test = true
	shaft.material_override = mat
	head.material_override = mat

	shaft.position = Vector3(0, length * 0.5, 0)
	head.position = Vector3(0, length + 0.025, 0)
	root.add_child(shaft)
	root.add_child(head)

	if axis_dir.is_equal_approx(Vector3.RIGHT):
		root.rotation_degrees = Vector3(0, 0, -90)
	elif axis_dir.is_equal_approx(Vector3.BACK):
		root.rotation_degrees = Vector3(90, 0, 0)
	elif axis_dir.is_equal_approx(Vector3.FORWARD):
		root.rotation_degrees = Vector3(-90, 0, 0)

	return root

func _create_rotation_ring(color: Color, normal_axis: Vector3, radius: float, ring_name: String) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = ring_name
	var torus := TorusMesh.new()
	torus.inner_radius = radius - 0.012
	torus.outer_radius = radius + 0.012
	torus.rings = 48
	torus.ring_segments = 16
	mi.mesh = torus

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 110
	mat.no_depth_test = true
	mi.material_override = mat

	if normal_axis.is_equal_approx(Vector3.RIGHT):
		mi.rotation_degrees = Vector3(0, 0, 90)
	elif normal_axis.is_equal_approx(Vector3.FORWARD) or normal_axis.is_equal_approx(Vector3.BACK):
		mi.rotation_degrees = Vector3(90, 0, 0)

	return mi

func _create_marker(color: Color, marker_name: String, radius: float = 0.055) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = marker_name
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	mi.mesh = sphere
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 100
	mat.no_depth_test = true
	mi.material_override = mat
	return mi

func _create_selection_box(color: Color, marker_name: String, size: float = 0.065) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.name = marker_name
	var box := BoxMesh.new()
	box.size = Vector3.ONE * size
	mi.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 100
	mat.no_depth_test = true
	mi.material_override = mat
	return mi

func _load_weapon(file_name: String) -> void:
	selected_weapon_file = file_name
	weapon_name = file_name
	_reset_fire_profile_defaults()
	handling_profile = WeaponAnimationProfile.build_default(
		WeaponAnimationProfile.infer_family(weapon_name, selected_category),
		animation_catalog.clip_paths if animation_catalog else {}
	)

	_set_weapon_ik_enabled(false)
	_set_save_enabled(false)
	weapon_master_pose_initialized = false

	if current_weapon_mesh:
		current_weapon_mesh.queue_free()
		current_weapon_mesh = null
	if current_silencer_mesh:
		current_silencer_mesh.queue_free()
		current_silencer_mesh = null
	if current_scope_mesh:
		current_scope_mesh.queue_free()
		current_scope_mesh = null
	if reload_magazine_proxy:
		reload_magazine_proxy.queue_free()
		reload_magazine_proxy = null

	var is_ak := (file_name == "ak-47")
	var is_9mm := (file_name == "9mm_pistol")
	var path := ""
	if is_ak:
		path = "res://assets/weapons/ps1_ak47/source/ak-47.fbx"
	elif is_9mm:
		path = "res://assets/weapons/9mm_pistol/source/model/model.dae"
	else:
		path = WEAPON_BASE_PATH + file_name + ".fbx"

	var scene := load(path) as PackedScene
	if not scene:
		push_error("Could not load weapon scene: %s" % path)
		return

	current_weapon_mesh = scene.instantiate() as Node3D
	if geometry_root == null and weapon_pivot != null:
		geometry_root = Node3D.new()
		geometry_root.name = "GeometryRoot"
		weapon_pivot.add_child(geometry_root)
	if socket_root == null and weapon_pivot != null:
		socket_root = Node3D.new()
		socket_root.name = "SocketRoot"
		weapon_pivot.add_child(socket_root)

	geometry_root.add_child(current_weapon_mesh)

	var effective_size := Vector3.ZERO
	for c in current_weapon_mesh.get_children():
		if c is MeshInstance3D and (c as MeshInstance3D).mesh:
			var mi: MeshInstance3D = c
			var raw_aabb = mi.mesh.get_aabb()
			effective_size = raw_aabb.size * mi.scale

	var true_raw_length := maxf(effective_size.x, maxf(effective_size.y, effective_size.z))
	var target_len := 0.68
	if "Pistol" in file_name or "Revolver" in file_name or is_9mm:
		target_len = 0.22
	elif "Submachine" in file_name or "Bullpup" in file_name:
		target_len = 0.50
	elif "Sniper" in file_name:
		target_len = 0.95
	elif "Shotgun" in file_name:
		target_len = 0.72

	if true_raw_length > 0.01:
		auto_normalized_scale = (target_len / true_raw_length)
	else:
		auto_normalized_scale = 0.13

	if is_ak:
		auto_normalized_scale = 0.028
		current_weapon_mesh.rotation_degrees = Vector3(0, 180, 0)
		auto_grip_center_offset = Vector3(0.0, 0.01, -0.07)
		var ak_mat := StandardMaterial3D.new()
		ak_mat.albedo_texture = preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
		ak_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		for c in current_weapon_mesh.get_children():
			if c is MeshInstance3D: (c as MeshInstance3D).material_override = ak_mat
	elif is_9mm:
		auto_normalized_scale = 0.025
		current_weapon_mesh.rotation_degrees = Vector3(0, -90, 0)
		auto_grip_center_offset = Vector3(0.0, -0.01, -0.04)
		_apply_9mm_textures(current_weapon_mesh)
	else:
		current_weapon_mesh.rotation_degrees = Vector3(0, -90, 0)
		auto_grip_center_offset = Vector3(0.0, -0.015, -target_len * 0.26)
		_apply_camo_skin_to_weapon(current_weapon_mesh, selected_camo_idx)

	# Sockets directly attached to SocketRoot (in unscaled WeaponPivot meter-space)
	if left_grip_marker: left_grip_marker.queue_free()
	if right_grip_marker: right_grip_marker.queue_free()
	if muzzle_marker: muzzle_marker.queue_free()
	if barrel_base_marker: barrel_base_marker.queue_free()
	if ejection_marker: ejection_marker.queue_free()
	if optic_marker: optic_marker.queue_free()

	left_grip_marker = _create_marker(Color(0.0, 0.95, 1.0), "Socket_LeftHand", 0.016)
	right_grip_marker = _create_marker(Color(1.0, 0.55, 0.08), "Socket_RightHand", 0.012)
	muzzle_marker = _create_marker(Color(1.0, 0.2, 0.2), "Socket_Muzzle", 0.016)
	barrel_base_marker = _create_marker(Color(1.0, 0.4, 0.4), "Socket_BarrelBase", 0.012)
	ejection_marker = _create_marker(Color(1.0, 0.85, 0.1), "Socket_Ejection", 0.012)
	optic_marker = _create_marker(Color(0.2, 1.0, 0.4), "Socket_Optic", 0.012)

	socket_root.add_child(left_grip_marker)
	socket_root.add_child(right_grip_marker)
	socket_root.add_child(muzzle_marker)
	socket_root.add_child(barrel_base_marker)
	socket_root.add_child(ejection_marker)
	socket_root.add_child(optic_marker)

	_setup_unscaled_hand_gizmo()
	_setup_unscaled_weapon_gizmo()
	_set_active_gizmo(active_gizmo_id)

	left_grip_local_pos = Vector3(-0.04, -0.04, -0.30)
	right_grip_local_pos = Vector3.ZERO
	right_grip_profile_loaded = false
	right_grip_needs_initialization = false
	muzzle_local_pos = Vector3(0.0, 0.0, -target_len)
	barrel_base_local_pos = Vector3(0.0, 0.0, -0.12)
	ejection_local_pos = Vector3(0.05, 0.03, -0.10)
	optic_local_pos = Vector3(0.0, 0.08, -0.18)

	_try_load_saved_profile(weapon_name)
	_setup_reload_magazine_proxy()

	if selected_silencer != "None": _load_silencer(selected_silencer)
	if selected_scope != "None": _load_scope(selected_scope)
	_refresh_handling_ui()

	call_deferred("_finish_weapon_bootstrap")


func _setup_reload_magazine_proxy() -> void:
	# The modular rifle FBX is one baked mesh, so it has no detachable magazine
	# node. This separate presentation prop makes handoff timing editable without
	# destructively rewriting the imported source asset.
	reload_magazine_proxy = MeshInstance3D.new()
	reload_magazine_proxy.name = "ReloadMagazineVisual"
	var magazine_mesh := BoxMesh.new()
	magazine_mesh.size = Vector3(0.034, 0.145, 0.055)
	reload_magazine_proxy.mesh = magazine_mesh
	var magazine_material := StandardMaterial3D.new()
	magazine_material.albedo_color = Color(0.075, 0.085, 0.09)
	magazine_material.metallic = 0.72
	magazine_material.roughness = 0.34
	reload_magazine_proxy.material_override = magazine_material
	reload_magazine_proxy.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	reload_magazine_proxy.visible = false
	add_child(reload_magazine_proxy)

func _try_load_saved_profile(w_id: String) -> void:
	var cfg_path := "res://config/weapons/" + w_id.to_lower() + ".json"
	if FileAccess.file_exists(cfg_path):
		var file := FileAccess.open(cfg_path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				var d: Dictionary = json.data
				_loaded_weapon_profile = d.duplicate(true)
				_load_operator_mount(_loaded_weapon_profile)
				if d.get("animation_hand_maps", {}) is Dictionary:
					animation_hand_maps = (d.get("animation_hand_maps", {}) as Dictionary).duplicate(true)
				animation_frame_editor.load_data(d.get("animation_frame_pose_keys", {}))
				if d.get("handling_profile", {}) is Dictionary and not (d.get("handling_profile", {}) as Dictionary).is_empty():
					handling_profile = (d.get("handling_profile", {}) as Dictionary).duplicate(true)
				var sock: Dictionary = d.get("weapon_sockets", {})
				if sock.has("left_hand_ik_target"):
					var ik = sock["left_hand_ik_target"]
					left_grip_local_pos = Vector3(ik.get("x", left_grip_local_pos.x), ik.get("y", left_grip_local_pos.y), ik.get("z", left_grip_local_pos.z))
				elif d.has("left_hand_ik_target"):
					var ik = d["left_hand_ik_target"]
					left_grip_local_pos = Vector3(ik.get("x", left_grip_local_pos.x), ik.get("y", left_grip_local_pos.y), ik.get("z", left_grip_local_pos.z))
				if sock.has("right_hand_grip_target"):
					var right_grip: Dictionary = sock["right_hand_grip_target"]
					right_grip_local_pos = Vector3(
						float(right_grip.get("x", right_grip_local_pos.x)),
						float(right_grip.get("y", right_grip_local_pos.y)),
						float(right_grip.get("z", right_grip_local_pos.z))
					)
					right_grip_profile_loaded = true

				if sock.has("muzzle_socket"):
					var mz = sock["muzzle_socket"]
					muzzle_local_pos = Vector3(mz.get("x", muzzle_local_pos.x), mz.get("y", muzzle_local_pos.y), mz.get("z", muzzle_local_pos.z))
				if sock.has("barrel_base_socket"):
					var bb = sock["barrel_base_socket"]
					barrel_base_local_pos = Vector3(bb.get("x", barrel_base_local_pos.x), bb.get("y", barrel_base_local_pos.y), bb.get("z", barrel_base_local_pos.z))
				if sock.has("ejection_port"):
					var ej = sock["ejection_port"]
					ejection_local_pos = Vector3(ej.get("x", ejection_local_pos.x), ej.get("y", ejection_local_pos.y), ej.get("z", ejection_local_pos.z))
				if sock.has("optic_rail"):
					var op = sock["optic_rail"]
					optic_local_pos = Vector3(op.get("x", optic_local_pos.x), op.get("y", optic_local_pos.y), op.get("z", optic_local_pos.z))
				if d.has("grip_offset"):
					var gp = d["grip_offset"]
					grip_offset_pos = Vector3(gp.get("pos_x", 0.0), gp.get("pos_y", 0.0), gp.get("pos_z", 0.0)) - auto_grip_center_offset
					grip_offset_rot = Vector3(gp.get("rot_x", 0.0), gp.get("rot_y", 0.0), gp.get("rot_z", 0.0))
				if d.has("support_hand_pose"):
					var hand_pose: Dictionary = d["support_hand_pose"]
					palm_pitch = float(hand_pose.get("palm_pitch_deg", palm_pitch))
					palm_yaw = float(hand_pose.get("palm_yaw_deg", palm_yaw))
					palm_roll = float(hand_pose.get("palm_roll_deg", palm_roll))
					finger_curl = float(hand_pose.get("finger_curl", finger_curl))
					thumb_wrap = float(hand_pose.get("thumb_wrap", thumb_wrap))
				var stances_data: Variant = d.get("stances", {})
				if stances_data is Dictionary and not (stances_data as Dictionary).is_empty():
					for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
						var stance_dict: Dictionary = (stances_data as Dictionary).get(String(posture), {})
						if not stance_dict.is_empty():
							hand_poses_by_stance[posture] = stance_dict.duplicate(true)
				else:
					for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
						var slot: String = "idle_standing" if posture == &"STANDING" else ("idle_crouched" if posture == &"CROUCHED" else "idle_prone")
						var clip: String = String((handling_profile.get("animation_slots", {}) as Dictionary).get(slot, ""))
						var map: Dictionary = animation_hand_maps.get(clip, {})
						if map.is_empty():
							map = animation_hand_maps.get(String(all_animation_paths.get(clip, "")), {})
						if not map.is_empty():
							hand_poses_by_stance[posture] = map.duplicate(true)
				var elbow_poles: Variant = d.get("elbow_poles", {})
				if elbow_poles is Dictionary:
					var pole_data := elbow_poles as Dictionary
					var by_stance: Variant = pole_data.get("by_stance", {})
					if by_stance is Dictionary and not (by_stance as Dictionary).is_empty():
						for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
							var saved_stance: Dictionary = (by_stance as Dictionary).get(String(posture), {})
							elbow_poles_by_stance[posture] = {
								"right": _vector_from_data(saved_stance.get("right", {}), Vector3.ZERO),
								"left": _vector_from_data(saved_stance.get("left", {}), Vector3.ZERO),
							}
					else:
						var legacy_right := _vector_from_data(pole_data.get("right", {}), Vector3.ZERO)
						var legacy_left := _vector_from_data(pole_data.get("left", {}), Vector3.ZERO)
						for posture: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
							elbow_poles_by_stance[posture] = {"right": legacy_right, "left": legacy_left}
					_restore_current_stance_elbow_poles()
					_restore_current_stance_hands()
				var ballistics: Variant = d.get("ballistics", {})
				if ballistics is Dictionary:
					var fire_values := ballistics as Dictionary
					fire_rate_rpm = int(fire_values.get("fire_rate_rpm", fire_rate_rpm))
					damage_per_shot = int(fire_values.get("damage", damage_per_shot))
					muzzle_velocity_mps = float(fire_values.get("muzzle_velocity_mps", muzzle_velocity_mps))
					base_spread_deg = float(fire_values.get("base_spread_deg", base_spread_deg))
					bloom_per_shot_deg = float(fire_values.get("bloom_per_shot_deg", bloom_per_shot_deg))
					max_recoil_bloom_deg = float(fire_values.get("max_recoil_bloom_deg", max_recoil_bloom_deg))
					bloom_recovery_speed = float(fire_values.get("bloom_recovery_speed", bloom_recovery_speed))
					is_silenced = bool(fire_values.get("is_silenced", is_silenced))
				var reticle: Variant = d.get("reticle", {})
				if reticle is Dictionary:
					var reticle_values := reticle as Dictionary
					reticle_base_gap_px = float(reticle_values.get("base_gap_px", reticle_base_gap_px))
					reticle_max_gap_px = float(reticle_values.get("max_gap_px", reticle_max_gap_px))
					reticle_response_speed = float(reticle_values.get("response_speed", reticle_response_speed))
					reticle_shot_kick_px = float(reticle_values.get("shot_kick_px", reticle_shot_kick_px))
					reticle_shot_kick_return = float(reticle_values.get("shot_kick_return", reticle_shot_kick_return))
					reticle_maximum_shot_kick_px = float(reticle_values.get("maximum_shot_kick_px", reticle_maximum_shot_kick_px))
				var composure_profile: Variant = d.get("composure", {})
				if composure_profile is Dictionary:
					var composure_values := composure_profile as Dictionary
					composure.configure_weapon(composure_values)
					composure_opening_stress_multiplier = float(
						composure_values.get(
							"opening_stress_multiplier",
							composure_opening_stress_multiplier
						)
					)
					composure_graze_damage_scale = float(
						composure_values.get(
							"graze_damage_scale",
							composure_graze_damage_scale
						)
					)
				user_scale_multiplier = float(d.get("user_scale_multiplier", user_scale_multiplier))
			file.close()
	_refresh_fire_controls()


func _reset_fire_profile_defaults() -> void:
	fire_rate_rpm = 650
	damage_per_shot = 34
	muzzle_velocity_mps = _default_muzzle_velocity_mps()
	is_silenced = false
	base_spread_deg = 0.28
	bloom_per_shot_deg = 0.32
	bloom_recovery_speed = 10.0
	max_recoil_bloom_deg = 2.4
	reticle_base_gap_px = 10.0
	reticle_max_gap_px = 46.0
	reticle_response_speed = 24.0
	reticle_shot_kick_px = 6.0
	reticle_shot_kick_return = 18.0
	reticle_maximum_shot_kick_px = 18.0
	composure = OperatorComposureScript.new()
	composure_opening_stress_multiplier = 0.28
	composure_graze_damage_scale = 0.38
	current_bloom = 0.0
	burst_shot_count = 0


func _refresh_fire_controls() -> void:
	if fire_profile_title:
		fire_profile_title.text = "RETICLE & FIRE — %s" % weapon_name
	if composure_profile_title:
		composure_profile_title.text = "COMPOSURE — %s" % weapon_name
	_update_slider_value("rpm", float(fire_rate_rpm))
	_update_slider_value("dmg", float(damage_per_shot))
	_update_slider_value("muzzle_velocity", muzzle_velocity_mps)
	_update_slider_value("base_spread", base_spread_deg)
	_update_slider_value("bloom", bloom_per_shot_deg)
	_update_slider_value("max_bloom", max_recoil_bloom_deg)
	_update_slider_value("rec", bloom_recovery_speed)
	_update_slider_value("reticle_base", reticle_base_gap_px)
	_update_slider_value("reticle_max", reticle_max_gap_px)
	_update_slider_value("reticle_response", reticle_response_speed)
	_update_slider_value("reticle_kick", reticle_shot_kick_px)
	_update_slider_value("reticle_return", reticle_shot_kick_return)
	_update_slider_value("reticle_kick_limit", reticle_maximum_shot_kick_px)
	_update_slider_value("composure_shot_stress", composure.shot_stress)
	_update_slider_value("composure_movement_stress", composure.movement_stress)
	_update_slider_value("composure_turning_stress", composure.turning_stress)
	_update_slider_value("composure_attack", composure.stress_attack_speed)
	_update_slider_value("composure_recovery", composure.recovery_speed)
	_update_slider_value("composure_core", composure.minimum_core_scale)
	_update_slider_value("composure_spring", composure.visual_spring)
	_update_slider_value("composure_damping", composure.visual_damping)
	_update_slider_value("composure_bounce_time", composure.shot_bounce_duration)
	_update_slider_value("composure_bounce_strength", composure.shot_bounce_strength)
	_update_slider_value("composure_opening", composure_opening_stress_multiplier)
	_update_slider_value("composure_moving_first", composure.moving_first_shot_multiplier)
	_update_slider_value("composure_second", composure.second_shot_multiplier)
	_update_slider_value("composure_graze", composure_graze_damage_scale)
	_apply_reticle_preview_profile()


func _default_muzzle_velocity_mps() -> float:
	match selected_category:
		"Pistols", "Revolvers": return 350.0
		"SMGs": return 400.0
		"Shotguns": return 420.0
		"Sniper Rifles": return 850.0
		_: return 715.0

func _apply_9mm_textures(node: Node) -> void:
	var body_tex = load("res://assets/weapons/9mm_pistol/textures/Body_albedo.jpeg") as Texture2D
	var slide_tex = load("res://assets/weapons/9mm_pistol/textures/Slide_albedo.jpeg") as Texture2D
	var mag_tex = load("res://assets/weapons/9mm_pistol/textures/Magazine_albedo.jpeg") as Texture2D

	for c in node.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			var mat := StandardMaterial3D.new()
			mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
			if "Body" in mi.name: mat.albedo_texture = body_tex
			elif "Slide" in mi.name: mat.albedo_texture = slide_tex
			elif "Mag" in mi.name: mat.albedo_texture = mag_tex
			else: mat.albedo_color = Color(0.2, 0.2, 0.2)
			mi.material_override = mat

func _apply_camo_skin_to_weapon(node: Node, camo_idx: int) -> void:
	var wood_color := Color(0.38, 0.24, 0.14)
	var steel_color := Color(0.22, 0.24, 0.26)
	var poly_color := Color(0.12, 0.12, 0.13)
	var bolt_color := Color(0.45, 0.48, 0.52)

	match camo_idx:
		1: # SOCOM Desert Tan
			wood_color = Color(0.72, 0.60, 0.44)
			steel_color = Color(0.55, 0.48, 0.36)
			poly_color = Color(0.20, 0.18, 0.15)
			bolt_color = Color(0.35, 0.35, 0.35)
		2: # SOCOM Woodland OD
			wood_color = Color(0.28, 0.35, 0.22)
			steel_color = Color(0.22, 0.25, 0.20)
			poly_color = Color(0.14, 0.16, 0.12)
			bolt_color = Color(0.40, 0.42, 0.40)
		3: # Midnight Spec-Ops
			wood_color = Color(0.08, 0.08, 0.09)
			steel_color = Color(0.12, 0.13, 0.14)
			poly_color = Color(0.06, 0.06, 0.07)
			bolt_color = Color(0.25, 0.25, 0.27)
		4: # Arctic Whiteout
			wood_color = Color(0.85, 0.88, 0.90)
			steel_color = Color(0.70, 0.75, 0.80)
			poly_color = Color(0.30, 0.35, 0.40)
			bolt_color = Color(0.60, 0.65, 0.70)
		5: # Titanium & Carbon
			wood_color = Color(0.15, 0.15, 0.16)
			steel_color = Color(0.65, 0.68, 0.72)
			poly_color = Color(0.10, 0.10, 0.11)
			bolt_color = Color(0.80, 0.82, 0.85)

	for c in node.get_children():
		if c is MeshInstance3D:
			var mi: MeshInstance3D = c
			mi.material_override = null
			if mi.mesh:
				for s in range(mi.mesh.get_surface_count()):
					var surf_mat := mi.mesh.surface_get_material(s)
					var mat_name := surf_mat.resource_name.to_lower() if surf_mat else ""
					var sm := StandardMaterial3D.new()
					sm.roughness = 0.45
					sm.metallic = 0.75

					if "wood" in mat_name:
						sm.albedo_color = wood_color
						sm.roughness = 0.6
						sm.metallic = 0.1
					elif "darkmetal" in mat_name or "receiver" in mat_name:
						sm.albedo_color = steel_color
					elif "black" in mat_name or "grip" in mat_name or "stock" in mat_name:
						sm.albedo_color = poly_color
						sm.metallic = 0.2
					elif "metal" in mat_name or "bolt" in mat_name:
						sm.albedo_color = bolt_color
						sm.metallic = 0.9
						sm.roughness = 0.25
					else:
						sm.albedo_color = steel_color

					mi.set_surface_override_material(s, sm)

func _load_silencer(s_name: String) -> void:
	selected_silencer = s_name
	if current_silencer_mesh:
		current_silencer_mesh.queue_free()
		current_silencer_mesh = null

	if s_name == "None" or s_name == "":
		is_silenced = false
		return

	is_silenced = true
	var path := WEAPON_BASE_PATH + "Accessories/" + s_name + ".fbx"
	var scene := load(path) as PackedScene
	if scene:
		current_silencer_mesh = scene.instantiate() as Node3D
		current_silencer_mesh.scale = Vector3.ONE * (auto_normalized_scale * user_scale_multiplier)
		current_silencer_mesh.rotation_degrees = Vector3(0, -90, 0)
		current_silencer_mesh.position = muzzle_marker.position if muzzle_marker else muzzle_local_pos
		weapon_pivot.add_child(current_silencer_mesh)
		_apply_camo_skin_to_weapon(current_silencer_mesh, selected_camo_idx)

func _load_scope(sc_name: String) -> void:
	selected_scope = sc_name
	if current_scope_mesh:
		current_scope_mesh.queue_free()
		current_scope_mesh = null

	if sc_name == "None" or sc_name == "":
		return

	var path := WEAPON_BASE_PATH + "Accessories/" + sc_name + ".fbx"
	var scene := load(path) as PackedScene
	if scene:
		current_scope_mesh = scene.instantiate() as Node3D
		current_scope_mesh.scale = Vector3.ONE * (auto_normalized_scale * user_scale_multiplier)
		current_scope_mesh.rotation_degrees = Vector3(0, -90, 0)
		current_scope_mesh.position = optic_marker.position if optic_marker else optic_local_pos
		weapon_pivot.add_child(current_scope_mesh)
		_apply_camo_skin_to_weapon(current_scope_mesh, selected_camo_idx)

func _sync_weapon_transform(keep_trigger_attached: bool = true) -> void:
	if not weapon_pivot: return
	weapon_pivot.position = auto_grip_center_offset + grip_offset_pos
	weapon_pivot.rotation_degrees = grip_offset_rot
	if geometry_root:
		geometry_root.scale = Vector3.ONE * (auto_normalized_scale * user_scale_multiplier)
	elif current_weapon_mesh:
		current_weapon_mesh.scale = Vector3.ONE * (auto_normalized_scale * user_scale_multiplier)
	# Do not move the weapon to satisfy a hand constraint. The weapon is the
	# master object; right- and left-hand IK consume its saved sockets.


func _sync_weapon_translation() -> void:
	_sync_weapon_transform(false)

func _sync_ballistic_markers() -> void:
	if socket_root == null:
		return
	if muzzle_marker:
		muzzle_marker.position = muzzle_local_pos
	if barrel_base_marker:
		barrel_base_marker.position = barrel_base_local_pos
	if current_silencer_mesh and muzzle_marker:
		current_silencer_mesh.position = muzzle_marker.position
	_update_fire_debug_lines()
	if reticle_canvas:
		reticle_canvas.queue_redraw()


func _sync_hand_markers() -> void:
	if right_grip_marker:
		right_grip_marker.position = right_grip_local_pos
	if left_grip_marker:
		left_grip_marker.position = left_grip_local_pos


func _sync_markers() -> void:
	_sync_hand_markers()
	_sync_ballistic_markers()
	if ejection_marker: ejection_marker.position = ejection_local_pos
	if optic_marker: optic_marker.position = optic_local_pos
	if current_scope_mesh and optic_marker: current_scope_mesh.position = optic_marker.position


func _preview_screen_rect() -> Rect2:
	var viewport_rect := get_viewport().get_visible_rect()
	var preview_left := viewport_rect.position.x
	if sidebar_panel and is_instance_valid(sidebar_panel):
		preview_left = clampf(
			sidebar_panel.get_global_rect().end.x + 8.0,
			viewport_rect.position.x,
			viewport_rect.end.x - 1.0
		)
	return Rect2(
		Vector2(preview_left, viewport_rect.position.y),
		Vector2(viewport_rect.end.x - preview_left, viewport_rect.size.y)
	)


func _reticle_screen_position() -> Vector2:
	return GunsmithBallisticsView.calculate_reticle_screen_position(
		cam,
		socket_root,
		muzzle_local_pos,
		_calibrated_barrel_base(),
		_preview_screen_rect().get_center(),
		MUZZLE_RETICLE_LEAD_PX
	)


func _camera_aim_sample() -> Dictionary:
	if cam == null:
		return {"position": Vector3.ZERO, "target_locked": false}
	# Kept as a separate reference layer so the calibration view can compare the
	# gameplay camera center with the physical weapon bore without coupling them.
	var screen_center := _preview_screen_rect().get_center()
	var ray_origin := cam.project_ray_origin(screen_center)
	var ray_direction := cam.project_ray_normal(screen_center).normalized()
	var ray_end := ray_origin + ray_direction * 120.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": ray_end, "target_locked": false}
	var collider: Object = hit.get("collider")
	return {
		"position": hit.position,
		"target_locked": collider != null and collider.has_meta("gun_lab_target"),
	}


func _muzzle_axis_sample() -> Dictionary:
	if muzzle_marker == null or current_weapon_mesh == null:
		return _camera_aim_sample()
	var ray_origin := muzzle_marker.global_position
	var ray_direction := _barrel_direction_world()
	var ray_end := ray_origin + ray_direction * 120.0
	var query := PhysicsRayQueryParameters3D.create(ray_origin, ray_end)
	query.collision_mask = 1
	query.collide_with_areas = true
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return {"position": ray_end, "target_locked": false}
	var collider: Object = hit.get("collider")
	return {
		"position": hit.position,
		"target_locked": collider != null and collider.has_meta("gun_lab_target"),
	}


func _stance_spread_multiplier() -> float:
	match preview_posture:
		&"PRONE": return 0.22
		&"CROUCHED": return 0.60
		_: return 1.0


func _current_total_spread_deg() -> float:
	var composure_bloom := composure.get_visual_bloom() * max_recoil_bloom_deg
	return (
		base_spread_deg * _stance_spread_multiplier()
		+ maxf(current_bloom, composure_bloom)
	)


func _composure_stance() -> OperatorComposure.Stance:
	match preview_posture:
		&"PRONE": return OperatorComposure.Stance.PRONE
		&"CROUCHED": return OperatorComposure.Stance.CROUCHED
		_: return OperatorComposure.Stance.STANDING


func _update_composure_readout() -> void:
	if composure_readout == null:
		return
	composure_readout.text = (
		"COMPOSURE  %5.1f%%\n"
		+ "AUTHORITATIVE STRESS  %5.1f%%\n"
		+ "VISIBLE BLOOM  %5.1f%%\n"
		+ "PRECISION CORE  %5.1f%%\n"
		+ "SHOT IMPULSE  %5.1f%%"
	) % [
		composure.get_composure() * 100.0,
		composure.stress * 100.0,
		composure.get_visual_bloom() * 100.0,
		composure.get_precision_core_scale() * 100.0,
		composure.get_shot_bounce() * 100.0,
	]

func _align_trigger_socket_to_right_hand(update_controls: bool = true) -> void:
	if not weapon_pivot or not right_grip_marker or not right_hand_dot:
		return
	var parent_node := weapon_pivot.get_parent_node_3d()
	if parent_node == null:
		return
	var correction := right_hand_dot.global_position - right_grip_marker.global_position
	var new_world := weapon_pivot.global_position + correction
	var local_pos := parent_node.global_transform.affine_inverse() * new_world
	grip_offset_pos = local_pos - auto_grip_center_offset
	_sync_weapon_transform(false)
	_sync_markers()
	if update_controls:
		_update_slider_value("grip_x", grip_offset_pos.x)
		_update_slider_value("grip_y", grip_offset_pos.y)
		_update_slider_value("grip_z", grip_offset_pos.z)

func _fire_shot() -> void:
	var interval := 60.0 / float(maxi(100, fire_rate_rpm))
	fire_cooldown = interval
	burst_shot_count += 1
	_preview_fire_animation()
	visual_recoil_pitch_deg = minf(
		VISUAL_RECOIL_MAX_PITCH_DEG,
		visual_recoil_pitch_deg + VISUAL_RECOIL_PITCH_PER_SHOT_DEG
	)
	visual_recoil_back_m = minf(
		VISUAL_RECOIL_MAX_BACK_M,
		visual_recoil_back_m + VISUAL_RECOIL_BACK_PER_SHOT_M
	)
	var dispersion_multiplier := composure.get_shot_dispersion_multiplier(
		burst_shot_count,
		composure_preview_movement,
		composure_preview_turning
	)
	var stress_multiplier := (
		composure_opening_stress_multiplier
		if burst_shot_count <= 2
		else 1.0
	)
	composure.notify_shot(1.0, stress_multiplier)

	if burst_shot_count > 2:
		current_bloom = minf(
			max_recoil_bloom_deg,
			current_bloom + bloom_per_shot_deg
		)
	if dynamic_reticle:
		dynamic_reticle.notify_shot(
			burst_shot_count,
			1.0 + current_bloom / maxf(max_recoil_bloom_deg, 0.001)
		)

	if muzzle_marker:
		var flash := OmniLight3D.new()
		flash.light_color = Color(1.0, 0.85, 0.3) if not is_silenced else Color(0.3, 0.6, 1.0)
		flash.omni_range = 3.5
		flash.light_energy = 3.0
		muzzle_marker.add_child(flash)
		get_tree().create_timer(0.04).timeout.connect(flash.queue_free)

		var tracer := MeshInstance3D.new()
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.008
		cyl.bottom_radius = 0.008
		cyl.height = 1.2
		tracer.mesh = cyl
		var t_mat := StandardMaterial3D.new()
		t_mat.albedo_color = Color(1.0, 0.9, 0.4) if not is_silenced else Color(0.4, 0.8, 1.0)
		t_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		tracer.material_override = t_mat

		last_shot_origin = muzzle_marker.global_position
		var aim_sample := _muzzle_axis_sample()
		current_aim_target = aim_sample.position
		var forward_dir := _barrel_direction_world()
		var spread_rad := deg_to_rad(_current_total_spread_deg()) * dispersion_multiplier
		var random := RandomNumberGenerator.new()
		random.seed = burst_shot_count
		var random_angle := random.randf() * TAU
		var random_radius := sqrt(random.randf()) * spread_rad
		var spread_offset := Vector3(
			cos(random_angle) * random_radius,
			sin(random_angle) * random_radius,
			0.0
		)
		var shot_basis := Basis.looking_at(forward_dir, Vector3.UP)
		var shot_direction := (shot_basis * (Vector3.FORWARD + spread_offset)).normalized()
		var shot_target := last_shot_origin + shot_direction * 120.0
		var shot_query := PhysicsRayQueryParameters3D.create(last_shot_origin, shot_target)
		shot_query.collision_mask = 1
		shot_query.collide_with_areas = true
		var shot_hit := get_world_3d().direct_space_state.intersect_ray(shot_query)
		if not shot_hit.is_empty():
			shot_target = shot_hit.position
		last_shot_end = shot_target
		bullet_tracers.add_child(tracer)
		tracer.global_position = last_shot_origin
		tracer.look_at(shot_target)
		tracer.rotation_degrees.x += 90.0

		var tween := create_tween()
		tween.tween_property(tracer, "global_position", shot_target, 0.07)
		tween.tween_callback(tracer.queue_free)

	if hud_status:
		hud_status.text = "💥 BANG! RPM: %d | Burst: #%d | Bloom: %.2f° | Silenced: %s" % [
			fire_rate_rpm, burst_shot_count, current_bloom, "YES" if is_silenced else "NO"
		]

func _apply_pixel_texture(node: Node) -> void:
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = PS1_GAS_MASK_TEX
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		node.material_override = mat
	for child in node.get_children():
		_apply_pixel_texture(child)

func _ensure_65_bone_contract() -> void:
	for side in ["Left", "Right"]:
		var hand_index := skeleton.find_bone("mixamorig_%sHand" % side)
		if hand_index < 0: continue
		for finger in ["Middle", "Ring", "Pinky"]:
			var parent_index := hand_index
			for segment in range(1, 5):
				var bone_name := "mixamorig_%sHand%s%d" % [side, finger, segment]
				var bone_index := skeleton.find_bone(bone_name)
				if bone_index < 0:
					bone_index = skeleton.add_bone(bone_name)
					var index_reference := skeleton.find_bone("mixamorig_%sHandIndex%d" % [side, segment])
					if index_reference >= 0:
						skeleton.set_bone_rest(bone_index, skeleton.get_bone_rest(index_reference))
				skeleton.set_bone_parent(bone_index, parent_index)
				parent_index = bone_index

func _retarget_aim_anim(src_anim: Animation) -> Animation:
	var retargeted := src_anim.duplicate()
	var root_n := animation_player.get_node(animation_player.root_node)
	var skel_path := root_n.get_path_to(skeleton)
	for i in range(retargeted.get_track_count() - 1, -1, -1):
		var old_path := str(retargeted.track_get_path(i))
		var raw_bone := old_path.split(":")[-1]
		var norm := raw_bone.replace("mixamorig:", "mixamorig_")
		if not norm.begins_with("mixamorig_"): norm = "mixamorig_" + norm
		var target_bone := ""
		if skeleton.find_bone(raw_bone) != -1: target_bone = raw_bone
		elif skeleton.find_bone(norm) != -1: target_bone = norm
		if target_bone != "":
			retargeted.track_set_path(i, NodePath(str(skel_path) + ":" + target_bone))
			if ("Hips" in raw_bone or "root" in raw_bone.to_lower()) and retargeted.track_get_type(i) == Animation.TYPE_POSITION_3D:
				for k in range(retargeted.track_get_key_count(i)):
					var pos: Vector3 = retargeted.track_get_key_value(i, k)
					pos.x = 0.0; pos.z = 0.0
					pos.y = pos.y * 0.0191988
					retargeted.track_set_key_value(i, k, pos)
		else:
			retargeted.remove_track(i)
	return retargeted

func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D: return node as Skeleton3D
	for child in node.get_children():
		var f := _find_skeleton(child)
		if f: return f
	return null

func _find_animation_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer: return node as AnimationPlayer
	for child in node.get_children():
		var f := _find_animation_player(child)
		if f: return f
	return null

func _request_save_everything() -> void:
	if hud_status:
		hud_status.text = "💾 Saving every Rig & Hands, animation, composure, posture, and hitbox change…"
		hud_status.tooltip_text = hud_status.text
	_save_weapon_config()


func _save_weapon_config() -> bool:
	if not _validate_weapon_rig_before_save():
		return false
	if not HurtboxProfile.save_profile(
		shared_hurtbox_scales,
		shared_hurtbox_geometry,
		shared_custom_hitboxes
	):
		_show_rig_error(
			"Shared hitbox profile could not be saved. Weapon save blocked so main cannot drift from this preview."
		)
		return false
	if animation_frame_editor.active:
		_capture_animation_frame_pose_key()
	else:
		_save_selected_animation_hand_map()
	_store_current_stance_elbow_poles()
	if runtime_posture_layer and not runtime_posture_layer.save_procedural_profile():
		_show_rig_error("Operator joint and posture edits could not be saved. Save blocked.")
		return false
	var config_dir := "res://config/weapons/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(config_dir))
	var saved_stance_hands := _hand_maps_without_legacy_mounts(hand_poses_by_stance)
	var saved_animation_hands := _hand_maps_without_legacy_mounts(animation_hand_maps)

	var config_data: Dictionary = {
		"schema_version": 3,
		"socket_contract_authored": true,
		"coordinate_space": {
			"grip_offset": "weapon_root_local_meters",
			"weapon_sockets": "weapon_pivot_local_meters"
		},
		"weapon_id": weapon_name.to_lower(),
		"display_name": weapon_name,
		"category": selected_category,
		"camo_skin": camo_skins[selected_camo_idx],
		"model_fbx": WEAPON_BASE_PATH + weapon_name + ".fbx" if (weapon_name != "ak-47" and weapon_name != "9mm_pistol") else ("res://assets/weapons/ps1_ak47/source/ak-47.fbx" if weapon_name == "ak-47" else "res://assets/weapons/9mm_pistol/source/model/model.dae"),
		"silencer_attachment": selected_silencer,
		"scope_attachment": selected_scope,
		"normalized_scale": auto_normalized_scale * user_scale_multiplier,
		"user_scale_multiplier": user_scale_multiplier,
		"model_rotation_degrees": {
			"x": current_weapon_mesh.rotation_degrees.x if current_weapon_mesh else 0.0,
			"y": current_weapon_mesh.rotation_degrees.y if current_weapon_mesh else 0.0,
			"z": current_weapon_mesh.rotation_degrees.z if current_weapon_mesh else 0.0
		},
		"operator_mount": {
			"position": _vector3_to_dictionary(weapon_mount_local.origin * trooper_scale),
			"rotation_degrees": _vector3_to_dictionary(_radians_to_degrees_vector(weapon_mount_local.basis.orthonormalized().get_euler(EULER_ORDER_YXZ)))
		},
		"grip_offset": {
			"pos_x": (auto_grip_center_offset + grip_offset_pos).x,
			"pos_y": (auto_grip_center_offset + grip_offset_pos).y,
			"pos_z": (auto_grip_center_offset + grip_offset_pos).z,
			"rot_x": grip_offset_rot.x,
			"rot_y": grip_offset_rot.y,
			"rot_z": grip_offset_rot.z
		},
		"support_hand_pose": {
			"palm_pitch_deg": palm_pitch,
			"palm_yaw_deg": palm_yaw,
			"palm_roll_deg": palm_roll,
			"finger_curl": finger_curl,
			"thumb_wrap": thumb_wrap
		},
		"elbow_poles": {
			"right": {"x": right_elbow_pole_offset.x, "y": right_elbow_pole_offset.y, "z": right_elbow_pole_offset.z},
			"left": {"x": left_elbow_pole_offset.x, "y": left_elbow_pole_offset.y, "z": left_elbow_pole_offset.z},
			"by_stance": _elbow_poles_save_data()
		},
		"stances": saved_stance_hands,
		"animation_hand_maps": saved_animation_hands,
		"animation_frame_pose_keys": animation_frame_editor.save_data(),
		"handling_profile": handling_profile.duplicate(true),
		"weapon_sockets": _weapon_sockets_save_data(),
		"ballistics": {
			"fire_rate_rpm": fire_rate_rpm,
			"damage": damage_per_shot,
			"muzzle_velocity_mps": muzzle_velocity_mps,
			"base_spread_deg": base_spread_deg,
			"bloom_per_shot_deg": bloom_per_shot_deg,
			"max_recoil_bloom_deg": max_recoil_bloom_deg,
			"bloom_recovery_speed": bloom_recovery_speed,
			"is_silenced": is_silenced
		},
		"reticle": _current_reticle_profile(),
		"composure": _current_composure_profile()
	}

	var file_path := config_dir + weapon_name.to_lower() + ".json"
	# Preserve unknown forward-compatible reticle fields while Gunsmith remains
	# the authoritative editor for the known reticle and composure contracts.
	if FileAccess.file_exists(file_path):
		var existing_file := FileAccess.open(file_path, FileAccess.READ)
		var existing_value: Variant = JSON.parse_string(existing_file.get_as_text()) if existing_file else null
		if existing_value is Dictionary:
			var existing := existing_value as Dictionary
			if existing.get("reticle", {}) is Dictionary:
				var existing_reticle := existing.get("reticle", {}) as Dictionary
				for key: Variant in existing_reticle:
					if not (config_data["reticle"] as Dictionary).has(key):
						(config_data["reticle"] as Dictionary)[key] = existing_reticle[key]
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file == null:
		_show_rig_error("Weapon profile could not be opened for writing. Save blocked.")
		return false
	file.store_string(JSON.stringify(config_data, "  "))
	file.close()
	if not _save_operator_loadout(weapon_name.to_lower()):
		_show_rig_error("Operator loadout could not be written. Save blocked.")
		return false

	_export_weapon_packed_scene(config_data)
	if hud_status:
		hud_status.text = "💾 SAVED & EQUIPPED! %s • muzzle (%.3f, %.3f, %.3f) saved exactly." % [
			weapon_name,
			muzzle_local_pos.x,
			muzzle_local_pos.y,
			muzzle_local_pos.z,
		]
		hud_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	return true


func _weapon_sockets_save_data() -> Dictionary:
	return {
		"right_hand_grip_target": _vector3_to_dictionary(right_grip_local_pos),
		"left_hand_ik_target": _vector3_to_dictionary(left_grip_local_pos),
		"muzzle_socket": _vector3_to_dictionary(muzzle_local_pos),
		"barrel_base_socket": _vector3_to_dictionary(_calibrated_barrel_base()),
		"ejection_port": _vector3_to_dictionary(ejection_local_pos),
		"optic_rail": _vector3_to_dictionary(optic_local_pos),
	}

func _barrel_axis_local() -> Vector3:
	var axis := muzzle_local_pos - barrel_base_local_pos
	if axis.length_squared() <= 0.000001:
		return Vector3.FORWARD
	return axis.normalized()


func _calibrated_barrel_base() -> Vector3:
	return barrel_base_local_pos


func _gunsmith_bore_direction_world() -> Vector3:
	if socket_root == null:
		return Vector3.FORWARD
	var clean_basis: Basis = socket_root.global_basis.orthonormalized()
	return (clean_basis * _barrel_axis_local()).normalized()


func _barrel_direction_world() -> Vector3:
	return _gunsmith_bore_direction_world()


func _bullet_velocity_vector() -> Vector3:
	return _barrel_direction_world() * muzzle_velocity_mps

func _save_and_play_latest_playground() -> void:
	# One canonical handoff: the live build never guesses which lab or scene is
	# newest. Save the selected weapon contract, then enter main.tscn.
	if not _save_weapon_config():
		return
	if hud_status:
		hud_status.text = "✅ Rig saved. Opening the latest gameplay playground…"
	call_deferred("_open_latest_playground")

func _open_latest_playground() -> void:
	var nav := get_node_or_null("/root/StudioNavigation")
	if nav != null:
		nav.call("open_scene", "res://main.tscn")
	else:
		var change_error := get_tree().change_scene_to_file("res://main.tscn")
		if change_error != OK and hud_status:
			hud_status.text = "Could not open the latest playground (%s)." % error_string(change_error)

func _save_operator_loadout(weapon_id: String) -> bool:
	var path := "res://config/weapons/operator_loadout.json"
	var loadout := {
		"schema_version": 1,
		"primary_weapon_id": weapon_id,
		"rig_config": "res://config/weapons/%s.json" % weapon_id,
	}
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(JSON.stringify(loadout, "  "))
	file.close()
	return true

func _export_weapon_packed_scene(config_data: Dictionary) -> void:
	var scenes_dir := "res://scenes/weapons/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(scenes_dir))

	var w_id: String = weapon_name.to_lower()
	var root := Node3D.new()
	root.name = weapon_name

	if current_weapon_mesh:
		var model_copy := current_weapon_mesh.duplicate() as Node3D
		model_copy.name = "WeaponMesh"
		root.add_child(model_copy)
		model_copy.owner = root

		var sock_lh := Marker3D.new()
		sock_lh.name = "Socket_LeftHand"
		sock_lh.position = left_grip_local_pos
		root.add_child(sock_lh)
		sock_lh.owner = root

		var sock_rh := Marker3D.new()
		sock_rh.name = "Socket_RightHand"
		sock_rh.position = right_grip_local_pos
		root.add_child(sock_rh)
		sock_rh.owner = root

		var sock_mz := Marker3D.new()
		sock_mz.name = "Socket_Muzzle"
		sock_mz.position = muzzle_local_pos
		root.add_child(sock_mz)
		sock_mz.owner = root

		var sock_barrel := Marker3D.new()
		sock_barrel.name = "Socket_BarrelBase"
		sock_barrel.position = _calibrated_barrel_base()
		root.add_child(sock_barrel)
		sock_barrel.owner = root

		var sock_ej := Marker3D.new()
		sock_ej.name = "Socket_Ejection"
		sock_ej.position = ejection_local_pos
		root.add_child(sock_ej)
		sock_ej.owner = root

		var sock_op := Marker3D.new()
		sock_op.name = "Socket_Optic"
		sock_op.position = optic_local_pos
		root.add_child(sock_op)
		sock_op.owner = root

		if current_silencer_mesh:
			var sil_copy := current_silencer_mesh.duplicate() as Node3D
			sil_copy.name = "Attachment_Silencer"
			root.add_child(sil_copy)
			sil_copy.owner = root

		if current_scope_mesh:
			var sc_copy := current_scope_mesh.duplicate() as Node3D
			sc_copy.name = "Attachment_Scope"
			root.add_child(sc_copy)
			sc_copy.owner = root

	var packed := PackedScene.new()
	var pack_result := packed.pack(root)
	if pack_result == OK:
		var tscn_path := scenes_dir + w_id + ".tscn"
		var save_err := ResourceSaver.save(packed, tscn_path)
		if save_err == OK:
			if hud_status:
				hud_status.text = "✅ SAVED + EQUIPPED: %s | Character will load this exact rig" % w_id
			print("Successfully exported ready-to-use game asset to: ", tscn_path)
	root.queue_free()

# ─── UI ───────────────────────────────────────────────────────────────────────

func _setup_rotation_corner_controls() -> void:
	rotation_panel = PanelContainer.new()
	rotation_panel.name = "RotationCornerPanel"
	rotation_panel.anchor_left = 1.0
	rotation_panel.anchor_right = 1.0
	rotation_panel.offset_left = -254.0
	rotation_panel.offset_right = -16.0
	rotation_panel.offset_top = 16.0
	rotation_panel.offset_bottom = 198.0
	rotation_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.035, 0.045, 0.06, 0.90)
	panel_style.border_color = Color(0.25, 0.85, 1.0, 0.70)
	panel_style.set_border_width_all(1)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 10.0
	panel_style.content_margin_right = 10.0
	panel_style.content_margin_top = 7.0
	panel_style.content_margin_bottom = 7.0
	rotation_panel.add_theme_stylebox_override("panel", panel_style)
	overlay.add_child(rotation_panel)

	var content := VBoxContainer.new()
	rotation_panel.add_child(content)
	rotation_title_label = Label.new()
	rotation_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rotation_title_label.add_theme_font_size_override("font_size", 12)
	rotation_title_label.add_theme_color_override("font_color", Color(0.75, 0.95, 1.0))
	content.add_child(rotation_title_label)

	rotation_orbit_control = Control.new()
	rotation_orbit_control.custom_minimum_size = Vector2(218.0, 112.0)
	rotation_orbit_control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	rotation_orbit_control.mouse_filter = Control.MOUSE_FILTER_STOP
	rotation_orbit_control.draw.connect(_draw_rotation_orbit)
	rotation_orbit_control.gui_input.connect(_on_rotation_orbit_input)
	rotation_orbit_control.mouse_exited.connect(func():
		if rotation_pad_drag_axis == "":
			rotation_pad_hover_axis = ""
			rotation_orbit_control.queue_redraw()
	)
	content.add_child(rotation_orbit_control)

	var values_row := HBoxContainer.new()
	values_row.alignment = BoxContainer.ALIGNMENT_CENTER
	content.add_child(values_row)
	for axis_name in ["pitch", "yaw", "roll"]:
		var value_label := Label.new()
		value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value_label.add_theme_font_size_override("font_size", 10)
		value_label.custom_minimum_size.x = 70.0
		var axis_color := _rotation_axis_color(axis_name)
		value_label.add_theme_color_override("font_color", axis_color)
		values_row.add_child(value_label)
		rotation_value_labels[axis_name] = value_label
	_refresh_rotation_dials()

func _draw_rotation_orbit() -> void:
	if not rotation_orbit_control: return
	if active_gizmo_id == "hand":
		_draw_human_hand_controls()
		return
	var center := Vector2(rotation_orbit_control.size.x * 0.5, 56.0)
	rotation_orbit_control.draw_circle(center, 7.0, Color(0.0, 0.95, 1.0) if active_gizmo_id == "hand" else Color(1.0, 0.55, 0.08))
	for axis_name in ["yaw", "pitch", "roll"]:
		var highlighted: bool = rotation_pad_hover_axis == axis_name or rotation_pad_drag_axis == axis_name
		var points := _rotation_orbit_points(center, axis_name, 1.08 if highlighted else 1.0)
		var color := Color.WHITE if rotation_pad_drag_axis == axis_name else _rotation_axis_color(axis_name)
		rotation_orbit_control.draw_polyline(points, color, 6.0 if highlighted else 3.5, true)
		var knob_angle := deg_to_rad(_rotation_axis_value(axis_name))
		var knob := _rotation_orbit_point(center, axis_name, knob_angle, 1.08 if highlighted else 1.0)
		rotation_orbit_control.draw_circle(knob, 5.0 if highlighted else 3.5, color)

func _draw_human_hand_controls() -> void:
	var roll_center := Vector2(58.0, 56.0)
	var direction_center := Vector2(160.0, 56.0)
	var roll_highlighted := rotation_pad_hover_axis == "roll" or rotation_pad_drag_axis == "roll"
	var direction_highlighted := rotation_pad_hover_axis == "direction" or rotation_pad_drag_axis == "direction"
	var roll_color := Color.WHITE if rotation_pad_drag_axis == "roll" else _rotation_axis_color("roll")
	var direction_color := Color.WHITE if rotation_pad_drag_axis == "direction" else Color(0.20, 0.85, 1.0)

	# Roll moves the palm continuously under, beside, and over the rifle.
	var roll_radius := 38.0 if roll_highlighted else 34.0
	rotation_orbit_control.draw_circle(roll_center, roll_radius, Color(1.0, 0.9, 0.2, 0.10))
	rotation_orbit_control.draw_arc(roll_center, roll_radius, 0.0, TAU, 48, roll_color, 6.0 if roll_highlighted else 3.5, true)
	var roll_angle := deg_to_rad(palm_roll - 90.0)
	var roll_marker := roll_center + Vector2(cos(roll_angle), sin(roll_angle)) * roll_radius
	_draw_open_hand_marker(roll_marker, roll_color, 0.72 if roll_highlighted else 0.62)

	# Open-hand pad: horizontal turns the fingers, vertical bends the wrist.
	var pad_radius := 39.0 if direction_highlighted else 35.0
	rotation_orbit_control.draw_circle(direction_center, pad_radius, Color(0.2, 0.85, 1.0, 0.09))
	rotation_orbit_control.draw_arc(direction_center, pad_radius, 0.0, TAU, 48, direction_color, 5.0 if direction_highlighted else 2.5, true)
	rotation_orbit_control.draw_line(direction_center + Vector2(-27, 0), direction_center + Vector2(27, 0), Color(direction_color.r, direction_color.g, direction_color.b, 0.45), 1.5, true)
	rotation_orbit_control.draw_line(direction_center + Vector2(0, -27), direction_center + Vector2(0, 27), Color(direction_color.r, direction_color.g, direction_color.b, 0.45), 1.5, true)
	var hand_point := direction_center + Vector2(clampf(palm_yaw / 90.0, -1.0, 1.0) * 25.0, -clampf(palm_pitch / 90.0, -1.0, 1.0) * 25.0)
	_draw_open_hand_marker(hand_point, direction_color, 0.88 if direction_highlighted else 0.76)

func _draw_open_hand_marker(center: Vector2, color: Color, scale_factor: float) -> void:
	var palm_size := Vector2(12.0, 14.0) * scale_factor
	rotation_orbit_control.draw_rect(Rect2(center - palm_size * 0.5, palm_size), color, true)
	for finger in range(5):
		var finger_x := (float(finger) - 2.0) * 2.7 * scale_factor
		var finger_length := (10.0 + (2.0 - absf(float(finger) - 2.0)) * 1.5) * scale_factor
		var start := center + Vector2(finger_x, -palm_size.y * 0.45)
		rotation_orbit_control.draw_line(start, start + Vector2(0, -finger_length), color, 2.0 * scale_factor, true)
	rotation_orbit_control.draw_line(
		center + Vector2(-palm_size.x * 0.45, 1.0),
		center + Vector2(-10.0, -5.0) * scale_factor,
		color,
		2.5 * scale_factor,
		true
	)

func _on_rotation_orbit_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			rotation_pad_drag_axis = _pick_rotation_orbit_axis(event.position)
			rotation_pad_hover_axis = rotation_pad_drag_axis
		else:
			rotation_pad_drag_axis = ""
		rotation_orbit_control.queue_redraw()
		rotation_orbit_control.accept_event()
	elif event is InputEventMouseMotion:
		var motion := event as InputEventMouseMotion
		if rotation_pad_drag_axis != "":
			if active_gizmo_id == "hand" and rotation_pad_drag_axis == "direction":
				palm_yaw = clampf(palm_yaw + motion.relative.x * 0.75, -90.0, 90.0)
				palm_pitch = clampf(palm_pitch - motion.relative.y * 0.65, -90.0, 90.0)
				_update_slider_value("p_yaw", palm_yaw)
				_update_slider_value("p_pitch", palm_pitch)
				_refresh_rotation_dials()
			else:
				var delta_degrees := -motion.relative.y * 0.65 if rotation_pad_drag_axis == "pitch" else motion.relative.x * (0.85 if rotation_pad_drag_axis == "roll" else 0.75)
				_apply_rotation_dial_delta(rotation_pad_drag_axis, delta_degrees)
		else:
			rotation_pad_hover_axis = _pick_rotation_orbit_axis(motion.position)
			rotation_orbit_control.queue_redraw()
		rotation_orbit_control.accept_event()

func _pick_rotation_orbit_axis(mouse_position: Vector2) -> String:
	if active_gizmo_id == "hand":
		var roll_center := Vector2(58.0, 56.0)
		var direction_center := Vector2(160.0, 56.0)
		if absf(mouse_position.distance_to(roll_center) - 34.0) <= 17.0:
			return "roll"
		if mouse_position.distance_to(direction_center) <= 42.0:
			return "direction"
		return ""
	var center := Vector2(rotation_orbit_control.size.x * 0.5, 56.0)
	var closest_axis := ""
	var closest_distance := 16.0
	for axis_name in ["yaw", "pitch", "roll"]:
		var points := _rotation_orbit_points(center, axis_name)
		for point in points:
			var distance := mouse_position.distance_to(point)
			if distance < closest_distance:
				closest_distance = distance
				closest_axis = axis_name
	return closest_axis

func _rotation_orbit_points(center: Vector2, axis_name: String, scale_factor: float = 1.0) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in range(65):
		points.append(_rotation_orbit_point(center, axis_name, TAU * float(i) / 64.0, scale_factor))
	return points

func _rotation_orbit_point(center: Vector2, axis_name: String, angle: float, scale_factor: float = 1.0) -> Vector2:
	var radii := Vector2(48.0, 23.0)
	var tilt := deg_to_rad(5.0)
	if axis_name == "pitch":
		radii = Vector2(28.0, 49.0)
		tilt = deg_to_rad(-18.0)
	elif axis_name == "roll":
		radii = Vector2(25.0, 50.0)
		tilt = deg_to_rad(34.0)
	var local_point := Vector2(cos(angle) * radii.x, sin(angle) * radii.y) * scale_factor
	return center + local_point.rotated(tilt)

func _rotation_axis_color(axis_name: String) -> Color:
	if axis_name == "pitch": return Color(1.0, 0.32, 0.90)
	if axis_name == "yaw": return Color(0.20, 0.85, 1.0)
	return Color(1.0, 0.90, 0.20)

func _apply_rotation_dial_delta(axis_name: String, delta_degrees: float) -> void:
	if active_gizmo_id == "hand":
		if axis_name == "pitch": palm_pitch = clampf(palm_pitch + delta_degrees, -90.0, 90.0)
		elif axis_name == "yaw": palm_yaw = clampf(palm_yaw + delta_degrees, -90.0, 90.0)
		else: palm_roll = wrapf(palm_roll + delta_degrees, -180.0, 180.0)
		_update_slider_value("p_" + axis_name, _rotation_axis_value(axis_name))
	else:
		_adjust_weapon_rotation(axis_name, delta_degrees)
	_refresh_rotation_dials()

func _rotation_axis_value(axis_name: String) -> float:
	if active_gizmo_id == "hand":
		if axis_name == "pitch": return palm_pitch
		if axis_name == "yaw": return palm_yaw
		return palm_roll
	if _editing_action_weapon_frame():
		if axis_name == "pitch": return animation_frame_weapon_rotation_correction_deg.x
		if axis_name == "yaw": return animation_frame_weapon_rotation_correction_deg.y
		return animation_frame_weapon_rotation_correction_deg.z
	if axis_name == "pitch": return grip_offset_rot.x
	if axis_name == "yaw": return grip_offset_rot.y
	return grip_offset_rot.z

func _refresh_rotation_dials() -> void:
	if rotation_title_label:
		rotation_title_label.text = (
			"🔵 HUMAN HAND GRIP"
			if active_gizmo_id == "hand"
			else (
				"🟠 FRAME WEAPON CORRECTION — MUZZLE AXIS"
				if _editing_action_weapon_frame()
				else "🟠 WEAPON-MOUNT ROTATION"
			)
		)
	if rotation_orbit_control:
		rotation_orbit_control.queue_redraw()
	for axis_name in ["pitch", "yaw", "roll"]:
		if rotation_value_labels.has(axis_name):
			var value_label: Label = rotation_value_labels[axis_name]
			var display_name := String(axis_name).to_upper()
			if active_gizmo_id == "hand":
				if axis_name == "pitch": display_name = "BEND"
				elif axis_name == "yaw": display_name = "TURN"
				else: display_name = "AROUND"
			value_label.text = "%s  %.1f°" % [display_name, _rotation_axis_value(axis_name)]

func _build_studio_ui() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	dynamic_reticle = DynamicReticleScript.new()
	dynamic_reticle.name = "SharedWeaponReticlePreview"
	dynamic_reticle.apply_profile(_current_reticle_profile())
	overlay.add_child(dynamic_reticle)

	reticle_canvas = Control.new()
	reticle_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	reticle_canvas.draw.connect(_draw_socom_reticle)
	overlay.add_child(reticle_canvas)
	_setup_rotation_corner_controls()

	# Left Sidebar
	var panel := PanelContainer.new()
	panel.name = "GunsmithSidebarPanel"
	sidebar_panel = panel
	# Fill the available window height. The previous fixed 750 px height pushed the
	# save/play actions below short windows (and behind the macOS window edge).
	panel.anchor_left = 0.0
	panel.anchor_top = 0.0
	panel.anchor_right = 0.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 16.0
	panel.offset_top = 16.0
	panel.offset_right = 476.0
	panel.offset_bottom = -16.0
	overlay.add_child(panel)

	var sidebar := VBoxContainer.new()
	sidebar.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(sidebar)

	var tab_container := TabContainer.new()
	tab_container.name = "GunLabTabs"
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sidebar.add_child(tab_container)

	var scroll := ScrollContainer.new()
	scroll.name = "Rig & Hands"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	var title := Label.new()
	title.text = "🔫 SOCOM GUNSMITH & BIOMECHANICAL RIG"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
	vbox.add_child(title)

	var hint := Label.new()
	hint.text = "💡 Left arm automatically solves human biomechanics to grip the gun!"
	hint.add_theme_font_size_override("font_size", 10)
	hint.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	vbox.add_child(hint)

	# Camera Presets Row
	var cam_row := HBoxContainer.new()
	vbox.add_child(cam_row)
	var btn_hands := Button.new(); btn_hands.text = "🎥 Hands"; btn_hands.pressed.connect(func(): _set_camera_preset("hands")); cam_row.add_child(btn_hands)
	var btn_ots := Button.new(); btn_ots.text = "🎥 OTS"; btn_ots.pressed.connect(func(): _set_camera_preset("ots")); cam_row.add_child(btn_ots)
	var btn_side := Button.new(); btn_side.text = "🎥 Side"; btn_side.pressed.connect(func(): _set_camera_preset("side")); cam_row.add_child(btn_side)
	var btn_full := Button.new(); btn_full.text = "🎥 Full"; btn_full.pressed.connect(func(): _set_camera_preset("full")); cam_row.add_child(btn_full)
	live_aim_preview_toggle = CheckButton.new()
	live_aim_preview_toggle.name = "LiveAimPreviewToggle"
	live_aim_preview_toggle.text = "🎯 Live Weapon Aim — camera stays fixed"
	live_aim_preview_toggle.tooltip_text = "Yaw and pitch rotate the attached hand and rifle without moving the inspection camera. Frames mode temporarily freezes this preview."
	live_aim_preview_toggle.button_pressed = live_weapon_aim_enabled
	live_aim_preview_toggle.toggled.connect(func(enabled: bool):
		live_weapon_aim_enabled = enabled
		if hud_status:
			hud_status.text = (
				"Live weapon aim enabled — adjust Weapon Yaw and Weapon Pitch; the camera stays fixed."
				if enabled
				else "Live weapon aim paused."
			)
	)
	vbox.add_child(live_aim_preview_toggle)
	_add_slider(vbox, "live_weapon_yaw", "Weapon Yaw (Preview)", -75.0, 75.0, live_weapon_yaw_deg, func(v: float): live_weapon_yaw_deg = v)
	_add_slider(vbox, "live_weapon_pitch", "Weapon Pitch (Preview)", -55.0, 55.0, live_weapon_pitch_deg, func(v: float): live_weapon_pitch_deg = v)
	var reset_live_aim_btn := Button.new()
	reset_live_aim_btn.text = "Reset Weapon Aim Preview"
	reset_live_aim_btn.pressed.connect(func():
		live_weapon_yaw_deg = 0.0
		live_weapon_pitch_deg = 0.0
		_update_slider_value("live_weapon_yaw", 0.0)
		_update_slider_value("live_weapon_pitch", 0.0)
	)
	vbox.add_child(reset_live_aim_btn)

	vbox.add_child(HSeparator.new())

	# 1. Weapon Selector
	var cat_label := Label.new(); cat_label.text = "1. Weapon Category:"; vbox.add_child(cat_label)
	var cat_opt := OptionButton.new()
	for cat in weapon_categories.keys(): cat_opt.add_item(cat)
	vbox.add_child(cat_opt)

	var gun_label := Label.new(); gun_label.text = "Select Firearm:"; vbox.add_child(gun_label)
	var gun_opt := OptionButton.new()
	var populate_guns := func(cat_name: String):
		gun_opt.clear()
		for g in weapon_categories[cat_name]: gun_opt.add_item(g)
	populate_guns.call(selected_category)
	vbox.add_child(gun_opt)

	cat_opt.item_selected.connect(func(idx: int):
		selected_category = weapon_categories.keys()[idx]
		populate_guns.call(selected_category)
		selected_weapon_file = weapon_categories[selected_category][0]
		_load_weapon(selected_weapon_file)
	)

	gun_opt.item_selected.connect(func(idx: int):
		selected_weapon_file = weapon_categories[selected_category][idx]
		_load_weapon(selected_weapon_file)
	)

	# 2. Tactical Camo
	vbox.add_child(HSeparator.new())
	var camo_title := Label.new(); camo_title.text = "2. Tactical Camo / Skin:"; vbox.add_child(camo_title)
	var camo_opt := OptionButton.new()
	for s in camo_skins: camo_opt.add_item(s)
	camo_opt.item_selected.connect(func(idx: int):
		selected_camo_idx = idx
		if current_weapon_mesh and selected_weapon_file != "ak-47" and selected_weapon_file != "9mm_pistol":
			_apply_camo_skin_to_weapon(current_weapon_mesh, selected_camo_idx)
	)
	vbox.add_child(camo_opt)
	_build_handling_animation_ui(vbox)

	# Reload & Attachments
	vbox.add_child(HSeparator.new())
	var reload_btn := Button.new()
	reload_btn.text = "🔄 Test Reload Animation (R)"
	reload_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	reload_btn.pressed.connect(_trigger_reload_animation)
	vbox.add_child(reload_btn)

	support_hand_toggle = CheckButton.new()
	support_hand_toggle.text = "Support hand attached to foregrip"
	support_hand_toggle.tooltip_text = "Turn off to release the left hand for reloads or one-handed actions. The right hand remains the weapon anchor."
	support_hand_toggle.button_pressed = support_hand_attached
	support_hand_toggle.toggled.connect(func(enabled: bool): _set_support_hand_attached(enabled))
	vbox.add_child(support_hand_toggle)

	var sil_row := HBoxContainer.new(); vbox.add_child(sil_row)
	var sil_lbl := Label.new(); sil_lbl.text = "Suppressor:"; sil_lbl.custom_minimum_size.x = 90; sil_row.add_child(sil_lbl)
	var sil_opt := OptionButton.new()
	for s in silencer_options: sil_opt.add_item(s)
	sil_opt.item_selected.connect(func(idx: int): _load_silencer(silencer_options[idx]))
	sil_row.add_child(sil_opt)

	var scope_row := HBoxContainer.new(); vbox.add_child(scope_row)
	var sc_lbl := Label.new(); sc_lbl.text = "Optic Scope:"; sc_lbl.custom_minimum_size.x = 90; scope_row.add_child(sc_lbl)
	var sc_opt := OptionButton.new()
	for sc in scope_options: sc_opt.add_item(sc)
	sc_opt.item_selected.connect(func(idx: int): _load_scope(scope_options[idx]))
	scope_row.add_child(sc_opt)

	# 4. WEAPON MOUNT (Move weapon with XYZ + Rotations)
	vbox.add_child(HSeparator.new())
	var grip_title := Label.new()
	grip_title.text = "4. 🟠 Weapon Mount (Right Hand Pos XYZ & Rotations):"
	grip_title.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
	vbox.add_child(grip_title)

	_add_slider(vbox, "grip_x", "  Pos X", -0.25, 0.25, grip_offset_pos.x, func(v: float): grip_offset_pos.x = v; _sync_weapon_translation())
	_add_slider(vbox, "grip_y", "  Pos Y", -0.25, 0.25, grip_offset_pos.y, func(v: float): grip_offset_pos.y = v; _sync_weapon_translation())
	_add_slider(vbox, "grip_z", "  Pos Z", -0.25, 0.25, grip_offset_pos.z, func(v: float): grip_offset_pos.z = v; _sync_weapon_translation())
	_add_slider(vbox, "rot_pitch", "  Pitch", -180.0, 180.0, grip_offset_rot.x, func(v: float): grip_offset_rot.x = v; _sync_weapon_transform(); _refresh_rotation_dials())
	_add_slider(vbox, "rot_yaw", "  Yaw", -180.0, 180.0, grip_offset_rot.y, func(v: float): grip_offset_rot.y = v; _sync_weapon_transform(); _refresh_rotation_dials())
	_add_slider(vbox, "rot_roll", "  Roll", -180.0, 180.0, grip_offset_rot.z, func(v: float): grip_offset_rot.z = v; _sync_weapon_transform(); _refresh_rotation_dials())
	_add_slider(vbox, "scale_mult", "  Scale Multiplier", 0.5, 2.0, user_scale_multiplier, func(v: float): user_scale_multiplier = v; _sync_weapon_transform())

	# 5. BIOMECHANICAL FOREGRIP & HAND GRIP POSING
	vbox.add_child(HSeparator.new())
	var arm_title := Label.new()
	arm_title.text = "5. 🤲 Hand Placement & Tactical Grip Styles:"
	arm_title.add_theme_color_override("font_color", Color(0.0, 0.95, 1.0))
	vbox.add_child(arm_title)

	# Quick 1-Click Hand Alignment Presets
	var preset_row1 := HBoxContainer.new()
	vbox.add_child(preset_row1)
	var btn_cradle := Button.new(); btn_cradle.text = "🤲 Underneath Cradle"; preset_row1.add_child(btn_cradle)
	var btn_cclamp := Button.new(); btn_cclamp.text = "🤏 Tactical C-Clamp"; preset_row1.add_child(btn_cclamp)

	var preset_row2 := HBoxContainer.new()
	vbox.add_child(preset_row2)
	var btn_magwell := Button.new(); btn_magwell.text = "📐 Magwell Grip"; preset_row2.add_child(btn_magwell)
	var btn_vert := Button.new(); btn_vert.text = "✊ Vertical Grip"; preset_row2.add_child(btn_vert)

	btn_cradle.pressed.connect(func():
		current_grip_style = GripStyle.CLASSIC_CRADLE
		palm_roll = 180.0; palm_pitch = 10.0; palm_yaw = 0.0; finger_curl = 0.65; thumb_wrap = 0.40
		left_grip_local_pos.y = -0.045
		_sync_markers()
		_update_slider_value("ik_y", left_grip_local_pos.y)
		_update_slider_value("p_roll", palm_roll)
		_update_slider_value("p_pitch", palm_pitch)
		_update_slider_value("p_yaw", palm_yaw)
		_update_slider_value("f_curl", finger_curl)
		_update_slider_value("t_wrap", thumb_wrap)
		if hud_status: hud_status.text = "🤲 Set Underneath Handguard Cradle!"
	)

	btn_cclamp.pressed.connect(func():
		current_grip_style = GripStyle.C_CLAMP_TACTICAL
		palm_roll = 90.0; palm_pitch = 15.0; palm_yaw = -15.0; finger_curl = 0.80; thumb_wrap = 0.90
		left_grip_local_pos.y = 0.01
		_sync_markers()
		_update_slider_value("ik_y", left_grip_local_pos.y)
		_update_slider_value("p_roll", palm_roll)
		_update_slider_value("p_pitch", palm_pitch)
		_update_slider_value("p_yaw", palm_yaw)
		_update_slider_value("f_curl", finger_curl)
		_update_slider_value("t_wrap", thumb_wrap)
		if hud_status: hud_status.text = "🤏 Set Tactical C-Clamp (Thumb-Over-Bore)!"
	)

	btn_magwell.pressed.connect(func():
		current_grip_style = GripStyle.MAGWELL_GRIP
		palm_roll = 160.0; palm_pitch = -10.0; palm_yaw = 10.0; finger_curl = 0.85; thumb_wrap = 0.70
		left_grip_local_pos = Vector3(0.06, -0.04, 0.0)
		_sync_markers()
		_update_slider_value("ik_x", left_grip_local_pos.x)
		_update_slider_value("ik_y", left_grip_local_pos.y)
		_update_slider_value("p_roll", palm_roll)
		_update_slider_value("p_pitch", palm_pitch)
		_update_slider_value("p_yaw", palm_yaw)
		_update_slider_value("f_curl", finger_curl)
		_update_slider_value("t_wrap", thumb_wrap)
		if hud_status: hud_status.text = "📐 Set Magwell CQB Grip!"
	)

	btn_vert.pressed.connect(func():
		current_grip_style = GripStyle.VERTICAL_FOREGRIP
		palm_roll = -90.0; palm_pitch = 0.0; palm_yaw = 0.0; finger_curl = 0.90; thumb_wrap = 0.80
		left_grip_local_pos.y = -0.08
		_sync_markers()
		_update_slider_value("ik_y", left_grip_local_pos.y)
		_update_slider_value("p_roll", palm_roll)
		_update_slider_value("p_pitch", palm_pitch)
		_update_slider_value("p_yaw", palm_yaw)
		_update_slider_value("f_curl", finger_curl)
		_update_slider_value("t_wrap", thumb_wrap)
		if hud_status: hud_status.text = "✊ Set Vertical Foregrip Hold!"
	)

	_add_slider(vbox, "ik_x", "  Foregrip X (Along barrel)", -0.40, 1.20, left_grip_local_pos.x, func(v: float): left_grip_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "ik_y", "  Foregrip Y (Height)", -0.20, 0.20, left_grip_local_pos.y, func(v: float): left_grip_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "ik_z", "  Foregrip Z (Side)", -0.20, 0.20, left_grip_local_pos.z, func(v: float): left_grip_local_pos.z = v; _sync_markers())
	var trigger_title := Label.new(); trigger_title.text = "🟠 Trigger-Hand Socket (moves gun to the hand):"; vbox.add_child(trigger_title)
	_add_slider(vbox, "rh_x", "  Trigger Grip X", -1.50, 1.50, right_grip_local_pos.x, func(v: float): right_grip_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "rh_y", "  Trigger Grip Y", -1.50, 1.50, right_grip_local_pos.y, func(v: float): right_grip_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "rh_z", "  Trigger Grip Z", -1.50, 1.50, right_grip_local_pos.z, func(v: float): right_grip_local_pos.z = v; _sync_markers())
	_add_slider(vbox, "p_roll", "  Palm Roll (Underneath/Side)", -180.0, 180.0, palm_roll, func(v: float): palm_roll = v; _refresh_rotation_dials())
	_add_slider(vbox, "p_pitch", "  Palm Pitch (Wrist Tilt)", -90.0, 90.0, palm_pitch, func(v: float): palm_pitch = v; _refresh_rotation_dials())
	_add_slider(vbox, "p_yaw", "  Palm Yaw (Barrel Angle)", -90.0, 90.0, palm_yaw, func(v: float): palm_yaw = v; _refresh_rotation_dials())
	_add_slider(vbox, "f_curl", "  Fingers Wrap Tightness", 0.0, 1.0, finger_curl, func(v: float): finger_curl = v)
	_add_slider(vbox, "t_wrap", "  Thumb Over-Bore Wrap", 0.0, 1.0, thumb_wrap, func(v: float): thumb_wrap = v)

	# 6. WEAPON SOCKETS (Muzzle, Ejection, Optic)
	vbox.add_child(HSeparator.new())
	var sock_title := Label.new()
	sock_title.text = "6. Weapon Sockets (Muzzle, Ejection, Optic):"
	sock_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
	vbox.add_child(sock_title)

	var mz_lbl := Label.new(); mz_lbl.text = "🔴 Muzzle Tip Socket (Pos XYZ on gun):"; vbox.add_child(mz_lbl)
	_add_slider(vbox, "mz_x", "  Muzzle X", -1.60, 1.60, muzzle_local_pos.x, func(v: float): muzzle_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "mz_y", "  Muzzle Y", -0.80, 0.80, muzzle_local_pos.y, func(v: float): muzzle_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "mz_z", "  Muzzle Z", -1.60, 1.60, muzzle_local_pos.z, func(v: float): muzzle_local_pos.z = v; _sync_markers())

	var ej_lbl := Label.new(); ej_lbl.text = "🟡 Shell Ejection Port (Pos XYZ on gun):"; vbox.add_child(ej_lbl)
	_add_slider(vbox, "ej_x", "  Ejection X", -0.20, 0.80, ejection_local_pos.x, func(v: float): ejection_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "ej_y", "  Ejection Y", -0.20, 0.20, ejection_local_pos.y, func(v: float): ejection_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "ej_z", "  Ejection Z", -0.20, 0.20, ejection_local_pos.z, func(v: float): ejection_local_pos.z = v; _sync_markers())

	var op_lbl := Label.new(); op_lbl.text = "🟢 Optic Scope Rail (Pos XYZ on gun):"; vbox.add_child(op_lbl)
	_add_slider(vbox, "op_x", "  Optic X", -0.20, 0.80, optic_local_pos.x, func(v: float): optic_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "op_y", "  Optic Y", -0.20, 0.20, optic_local_pos.y, func(v: float): optic_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "op_z", "  Optic Z", -0.20, 0.20, optic_local_pos.z, func(v: float): optic_local_pos.z = v; _sync_markers())

	# Reticle and firing are a second view of this exact weapon profile—not a
	# disconnected lab. Saving below equips the same values in gameplay.
	var fire_scroll := ScrollContainer.new()
	fire_scroll.name = "Reticle & Fire"
	fire_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	fire_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(fire_scroll)
	var fire_vbox := VBoxContainer.new()
	fire_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	fire_scroll.add_child(fire_vbox)

	fire_profile_title = Label.new()
	fire_profile_title.text = "RETICLE & FIRE — %s" % weapon_name
	fire_profile_title.add_theme_font_size_override("font_size", 17)
	fire_profile_title.add_theme_color_override("font_color", Color(0.3, 0.95, 1.0))
	fire_vbox.add_child(fire_profile_title)
	var fire_help := Label.new()
	fire_help.text = "Space or left-click fires. The center dot is fixed aim authority; the four outer ticks expand and recover using this gun's saved profile."
	fire_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_vbox.add_child(fire_help)

	fire_vbox.add_child(HSeparator.new())
	var stance_title := Label.new()
	stance_title.text = "SOCOM STANCE PREVIEW"
	fire_vbox.add_child(stance_title)
	var stance_help := Label.new()
	stance_help.text = "1 Stand  •  2 Crouch  •  3 Prone. Stance changes body height and accuracy; it never changes the calibrated barrel direction."
	stance_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_vbox.add_child(stance_help)
	var stance_row := HBoxContainer.new()
	fire_vbox.add_child(stance_row)
	var stance_group := ButtonGroup.new()
	for posture_name: StringName in [&"STANDING", &"CROUCHED", &"PRONE"]:
		var stance_button := Button.new()
		stance_button.name = "Stance%s" % String(posture_name).capitalize()
		stance_button.text = String(posture_name).capitalize()
		stance_button.toggle_mode = true
		stance_button.button_group = stance_group
		stance_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		stance_button.pressed.connect(_set_preview_posture.bind(posture_name))
		stance_row.add_child(stance_button)
		stance_buttons[posture_name] = stance_button
	(stance_buttons[preview_posture] as Button).set_pressed_no_signal(true)

	var elbow_title := Label.new()
	elbow_title.text = "JOINT POLES — XYZ ELBOW SHAPE"
	elbow_title.add_theme_color_override("font_color", Color(0.9, 0.45, 1.0))
	fire_vbox.add_child(elbow_title)
	var elbow_help := Label.new()
	elbow_help.text = "Offsets move the IK bend targets, not the bones. This preserves human arm lengths across every stance."
	elbow_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_vbox.add_child(elbow_help)
	_add_slider(fire_vbox, "right_elbow_x", "Right Elbow X (Out/In)", -0.30, 0.30, right_elbow_pole_offset.x, _set_elbow_component.bind(&"right", &"x"))
	_add_slider(fire_vbox, "right_elbow_y", "Right Elbow Y (Up/Down)", -0.30, 0.30, right_elbow_pole_offset.y, _set_elbow_component.bind(&"right", &"y"))
	_add_slider(fire_vbox, "right_elbow_z", "Right Elbow Z (Forward/Back)", -0.30, 0.30, right_elbow_pole_offset.z, _set_elbow_component.bind(&"right", &"z"))
	_add_slider(fire_vbox, "left_elbow_x", "Left Elbow X (Out/In)", -0.30, 0.30, left_elbow_pole_offset.x, _set_elbow_component.bind(&"left", &"x"))
	_add_slider(fire_vbox, "left_elbow_y", "Left Elbow Y (Up/Down)", -0.30, 0.30, left_elbow_pole_offset.y, _set_elbow_component.bind(&"left", &"y"))
	_add_slider(fire_vbox, "left_elbow_z", "Left Elbow Z (Forward/Back)", -0.30, 0.30, left_elbow_pole_offset.z, _set_elbow_component.bind(&"left", &"z"))

	selected_joint_title = Label.new()
	selected_joint_title.text = "SELECTED JOINT"
	selected_joint_title.add_theme_color_override("font_color", Color(0.25, 0.9, 1.0))
	fire_vbox.add_child(selected_joint_title)
	selected_joint_help = Label.new()
	selected_joint_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fire_vbox.add_child(selected_joint_help)
	var joint_picker := OptionButton.new()
	joint_picker.name = "BodyJointPicker"
	for joint_name: StringName in TUNABLE_BODY_JOINTS:
		joint_picker.add_item(String(joint_name).replace("_", " ").capitalize())
		joint_picker.set_item_metadata(joint_picker.item_count - 1, joint_name)
	joint_picker.select(TUNABLE_BODY_JOINTS.find(selected_body_joint))
	joint_picker.item_selected.connect(func(index: int):
		_select_body_joint(StringName(joint_picker.get_item_metadata(index)))
	)
	fire_vbox.add_child(joint_picker)
	_add_slider(fire_vbox, "body_joint_pitch", "Bend", -55.0, 55.0, 0.0, _set_body_joint_component.bind(&"x"))
	_add_slider(fire_vbox, "body_joint_yaw", "Turn", -55.0, 55.0, 0.0, _set_body_joint_component.bind(&"y"))
	_add_slider(fire_vbox, "body_joint_roll", "Twist", -55.0, 55.0, 0.0, _set_body_joint_component.bind(&"z"))
	_sync_body_joint_controls()

	fire_vbox.add_child(HSeparator.new())
	var bal_title := Label.new(); bal_title.text = "FIRE & DISPERSION"; fire_vbox.add_child(bal_title)
	_add_slider(fire_vbox, "rpm", "Fire Rate (RPM)", 200.0, 1200.0, float(fire_rate_rpm), func(v: float): fire_rate_rpm = int(v))
	_add_slider(fire_vbox, "dmg", "Damage", 10.0, 100.0, float(damage_per_shot), func(v: float): damage_per_shot = int(v))
	_add_slider(fire_vbox, "muzzle_velocity", "Bullet Velocity (m/s)", 150.0, 1200.0, muzzle_velocity_mps, func(v: float): muzzle_velocity_mps = v)
	_add_slider(fire_vbox, "base_spread", "Base Spread (deg)", 0.0, 3.0, base_spread_deg, func(v: float): base_spread_deg = v)
	_add_slider(fire_vbox, "bloom", "Bloom Per Shot", 0.0, 5.0, bloom_per_shot_deg, func(v: float): bloom_per_shot_deg = v)
	_add_slider(fire_vbox, "max_bloom", "Maximum Bloom", 0.25, 8.0, max_recoil_bloom_deg, func(v: float): max_recoil_bloom_deg = v)
	_add_slider(fire_vbox, "rec", "Bloom Recovery", 2.0, 30.0, bloom_recovery_speed, func(v: float): bloom_recovery_speed = v)

	fire_vbox.add_child(HSeparator.new())
	var reticle_title := Label.new(); reticle_title.text = "RETICLE RESPONSE"; fire_vbox.add_child(reticle_title)
	_add_slider(fire_vbox, "reticle_base", "Resting Gap (px)", 4.0, 28.0, reticle_base_gap_px, func(v: float): reticle_base_gap_px = v; _apply_reticle_preview_profile())
	_add_slider(fire_vbox, "reticle_max", "Maximum Gap (px)", 18.0, 90.0, reticle_max_gap_px, func(v: float): reticle_max_gap_px = v; _apply_reticle_preview_profile())
	_add_slider(fire_vbox, "reticle_response", "Bloom Response", 4.0, 40.0, reticle_response_speed, func(v: float): reticle_response_speed = v; _apply_reticle_preview_profile())
	_add_slider(fire_vbox, "reticle_kick", "Shot Kick (px)", 0.0, 20.0, reticle_shot_kick_px, func(v: float): reticle_shot_kick_px = v; _apply_reticle_preview_profile())
	_add_slider(fire_vbox, "reticle_return", "Kick Recovery", 3.0, 40.0, reticle_shot_kick_return, func(v: float): reticle_shot_kick_return = v; _apply_reticle_preview_profile())
	_add_slider(fire_vbox, "reticle_kick_limit", "Kick Limit (px)", 0.0, 36.0, reticle_maximum_shot_kick_px, func(v: float): reticle_maximum_shot_kick_px = v; _apply_reticle_preview_profile())

	fire_vbox.add_child(HSeparator.new())
	var layers_title := Label.new(); layers_title.text = "TRAJECTORY STUDY LAYERS"; fire_vbox.add_child(layers_title)
	var convergence_toggle := CheckButton.new()
	convergence_toggle.name = "BulletVelocityToggle"
	convergence_toggle.text = "Green — bullet velocity vector"
	convergence_toggle.tooltip_text = "Starts at the red muzzle socket. Direction is the bore; length shows 4 ms of travel at the saved muzzle velocity."
	convergence_toggle.button_pressed = show_bullet_velocity
	convergence_toggle.toggled.connect(func(enabled: bool): show_bullet_velocity = enabled)
	fire_vbox.add_child(convergence_toggle)
	var barrel_toggle := CheckButton.new()
	barrel_toggle.text = "Red — physical barrel axis"
	barrel_toggle.toggled.connect(func(enabled: bool): show_barrel_axis = enabled)
	fire_vbox.add_child(barrel_toggle)
	var aim_toggle := CheckButton.new()
	aim_toggle.text = "Cyan — camera/reticle intent"
	aim_toggle.toggled.connect(func(enabled: bool): show_camera_aim = enabled)
	fire_vbox.add_child(aim_toggle)
	var eye_toggle := CheckButton.new()
	eye_toggle.name = "EyeSightToggle"
	eye_toggle.text = "Blue — operator eye sight"
	eye_toggle.tooltip_text = "Starts between the operator's eyes and ends at the shared reticle target. Use it to align the connected weapon rail and arm pose."
	eye_toggle.button_pressed = show_eye_sight
	eye_toggle.toggled.connect(func(enabled: bool):
		show_eye_sight = enabled
		_update_eye_sight_marker()
	)
	fire_vbox.add_child(eye_toggle)
	var eye_correction := _eye_sight_correction()
	_add_slider(
		fire_vbox,
		"eye_sight_pitch",
		"Eye Pitch (Up/Down)",
		-24.0,
		24.0,
		eye_correction.x,
		_set_eye_sight_component.bind(&"pitch")
	)
	_add_slider(
		fire_vbox,
		"eye_sight_yaw",
		"Eye Yaw (Left/Right)",
		-38.0,
		38.0,
		eye_correction.y,
		_set_eye_sight_component.bind(&"yaw")
	)
	var shot_toggle := CheckButton.new()
	shot_toggle.text = "Yellow — last actual shot"
	shot_toggle.toggled.connect(func(enabled: bool): show_last_shot = enabled)
	fire_vbox.add_child(shot_toggle)

	var reset_fire_button := Button.new()
	reset_fire_button.text = "Reset Bloom / Burst"
	reset_fire_button.pressed.connect(func():
		current_bloom = 0.0
		burst_shot_count = 0
		composure.reset()
	)
	fire_vbox.add_child(reset_fire_button)

	_build_composure_tab(tab_container)
	tab_container.tab_changed.connect(_on_gun_lab_tab_changed.bind(tab_container))

	# 8. Save & Export. Keep these controls outside the scrolling settings so
	# Save and Play are always reachable at every supported window height.
	var action_footer := VBoxContainer.new()
	action_footer.add_child(HSeparator.new())
	sidebar.add_child(action_footer)
	var save_btn := Button.new()
	save_btn.name = "SaveEverythingButton"
	save_btn.text = "✅ Save Everything + Equip (Cmd/Ctrl+S)"
	save_btn.tooltip_text = "Save weapon, sockets, animation corrections, composure, posture, and the complete shared hitbox layout."
	save_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	save_btn.pressed.connect(_request_save_everything)
	save_btn.disabled = not weapon_master_pose_initialized
	save_rig_button = save_btn
	action_footer.add_child(save_btn)

	var play_latest_btn := Button.new()
	play_latest_btn.text = "▶ Save + Play Latest Playground"
	play_latest_btn.tooltip_text = "Save this exact gun rig and launch the canonical current gameplay scene."
	play_latest_btn.add_theme_color_override("font_color", Color(0.35, 1.0, 0.55))
	play_latest_btn.pressed.connect(_save_and_play_latest_playground)
	play_latest_btn.disabled = not weapon_master_pose_initialized
	play_latest_button = play_latest_btn
	action_footer.add_child(play_latest_btn)

	hud_status = Label.new()
	hud_status.text = "Ready! (Biomechanical Engine Active | Drag Blue Dot to place hand | Space to Fire)"
	hud_status.add_theme_font_size_override("font_size", 11)
	hud_status.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	hud_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	hud_status.tooltip_text = hud_status.text
	action_footer.add_child(hud_status)


func _build_composure_tab(tab_container: TabContainer) -> void:
	var composure_scroll := ScrollContainer.new()
	composure_scroll.name = "Composure"
	composure_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	composure_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tab_container.add_child(composure_scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	composure_scroll.add_child(vbox)

	composure_profile_title = Label.new()
	composure_profile_title.text = "COMPOSURE — %s" % weapon_name
	composure_profile_title.add_theme_font_size_override("font_size", 17)
	composure_profile_title.add_theme_color_override("font_color", Color("77f29a"))
	vbox.add_child(composure_profile_title)

	var explanation := Label.new()
	explanation.text = (
		"Composure is the operator's recoverable firing stability. Authoritative "
		+ "stress determines dispersion and precision damage; the visual spring "
		+ "controls reticle breathing without changing server validation."
	)
	explanation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(explanation)

	vbox.add_child(HSeparator.new())
	var simulation_title := Label.new()
	simulation_title.text = "PREVIEW CONDITIONS"
	vbox.add_child(simulation_title)
	_add_slider(vbox, "composure_preview_move", "Movement input", 0.0, 1.0, composure_preview_movement, func(v: float): composure_preview_movement = v)
	_add_slider(vbox, "composure_preview_turn", "Turning input", 0.0, 1.0, composure_preview_turning, func(v: float): composure_preview_turning = v)
	var stance_help := Label.new()
	stance_help.text = "The stance selected in Reticle & Fire also governs composure recovery."
	stance_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(stance_help)

	vbox.add_child(HSeparator.new())
	var authority_title := Label.new()
	authority_title.text = "AUTHORITATIVE GAMEPLAY RESPONSE"
	authority_title.add_theme_color_override("font_color", Color("ffcf54"))
	vbox.add_child(authority_title)
	_add_slider(vbox, "composure_shot_stress", "Stress per shot", 0.0, 0.30, composure.shot_stress, func(v: float): composure.shot_stress = v)
	_add_slider(vbox, "composure_movement_stress", "Movement stress ceiling", 0.0, 1.0, composure.movement_stress, func(v: float): composure.movement_stress = v)
	_add_slider(vbox, "composure_turning_stress", "Turning stress ceiling", 0.0, 1.0, composure.turning_stress, func(v: float): composure.turning_stress = v)
	_add_slider(vbox, "composure_attack", "Stress acquisition rate", 0.5, 10.0, composure.stress_attack_speed, func(v: float): composure.stress_attack_speed = v)
	_add_slider(vbox, "composure_recovery", "Recovery rate", 0.20, 4.0, composure.recovery_speed, func(v: float): composure.recovery_speed = v)
	_add_slider(vbox, "composure_core", "Minimum precision core", 0.30, 1.0, composure.minimum_core_scale, func(v: float): composure.minimum_core_scale = v)
	_add_slider(vbox, "composure_opening", "Opening-pair stress scale", 0.0, 1.0, composure_opening_stress_multiplier, func(v: float): composure_opening_stress_multiplier = v)
	_add_slider(vbox, "composure_moving_first", "Moving first-shot dispersion", 0.0, 1.0, composure.moving_first_shot_multiplier, func(v: float): composure.moving_first_shot_multiplier = v)
	_add_slider(vbox, "composure_second", "Second-shot dispersion", 0.0, 1.0, composure.second_shot_multiplier, func(v: float): composure.second_shot_multiplier = v)
	_add_slider(vbox, "composure_graze", "Graze damage scale", 0.0, 1.0, composure_graze_damage_scale, func(v: float): composure_graze_damage_scale = v)

	vbox.add_child(HSeparator.new())
	var presentation_title := Label.new()
	presentation_title.text = "PRESENTATION RESPONSE"
	presentation_title.add_theme_color_override("font_color", Color("55e7ff"))
	vbox.add_child(presentation_title)
	_add_slider(vbox, "composure_spring", "Reticle spring", 10.0, 150.0, composure.visual_spring, func(v: float): composure.visual_spring = v)
	_add_slider(vbox, "composure_damping", "Reticle damping", 2.0, 30.0, composure.visual_damping, func(v: float): composure.visual_damping = v)
	_add_slider(vbox, "composure_bounce_time", "Shot impulse duration", 0.03, 0.20, composure.shot_bounce_duration, func(v: float): composure.shot_bounce_duration = v; _apply_reticle_preview_profile())
	_add_slider(vbox, "composure_bounce_strength", "Shot impulse strength", 0.0, 2.0, composure.shot_bounce_strength, func(v: float): composure.shot_bounce_strength = v)

	vbox.add_child(HSeparator.new())
	var hurtbox_title := Label.new()
	hurtbox_title.text = "SHARED ANATOMICAL HITBOX EDITOR"
	hurtbox_title.add_theme_color_override("font_color", Color("ff9f54"))
	vbox.add_child(hurtbox_title)
	var hurtbox_help := Label.new()
	hurtbox_help.text = (
		"These are the authoritative damage shapes used by the target range and "
		+ "network operators in main. Changes update this preview immediately; "
		+ "Save Rig or the button below writes the shared gameplay profile."
	)
	hurtbox_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(hurtbox_help)
	_add_slider(
		vbox,
		"hurtbox_global",
		"All hitboxes",
		HurtboxProfile.MIN_SCALE,
		HurtboxProfile.MAX_SCALE,
		float(shared_hurtbox_scales.get(&"global", 0.88)),
		func(v: float): _set_shared_hurtbox_scale(v, &"global")
	)
	hurtbox_region_picker = OptionButton.new()
	hurtbox_region_picker.name = "HurtboxRegionPicker"
	_refresh_hurtbox_region_picker()
	hurtbox_region_picker.item_selected.connect(func(index: int):
		_select_hurtbox_region(StringName(hurtbox_region_picker.get_item_metadata(index)))
	)
	vbox.add_child(hurtbox_region_picker)
	hurtbox_damage_type_picker = OptionButton.new()
	hurtbox_damage_type_picker.name = "HurtboxDamageTypePicker"
	for damage_type: StringName in HurtboxProfile.DAMAGE_TYPE_KEYS:
		hurtbox_damage_type_picker.add_item(
			"Paint as %s" % HurtboxProfile.damage_type_label(damage_type)
		)
		hurtbox_damage_type_picker.set_item_metadata(
			hurtbox_damage_type_picker.item_count - 1,
			damage_type
		)
	hurtbox_damage_type_picker.item_selected.connect(func(index: int):
		_set_selected_hurtbox_damage_type(
			StringName(hurtbox_damage_type_picker.get_item_metadata(index))
		)
	)
	vbox.add_child(hurtbox_damage_type_picker)
	_add_slider(
		vbox, "hurtbox_selected_size", "Selected width",
		HurtboxProfile.MIN_SCALE, HurtboxProfile.MAX_SCALE,
		float(shared_hurtbox_scales.get(selected_hurtbox_region, 1.0)),
		_set_selected_hurtbox_size
	)
	_add_slider(
		vbox, "hurtbox_selected_length", "Selected length",
		HurtboxProfile.MIN_LENGTH_SCALE, HurtboxProfile.MAX_LENGTH_SCALE,
		HurtboxProfile.geometry_length_scale(shared_hurtbox_geometry, selected_hurtbox_region),
		_set_selected_hurtbox_length
	)
	var offset := HurtboxProfile.geometry_offset(
		shared_hurtbox_geometry,
		selected_hurtbox_region
	)
	_add_slider(
		vbox, "hurtbox_offset_x", "Move sideways",
		-HurtboxProfile.MAX_OFFSET_METERS, HurtboxProfile.MAX_OFFSET_METERS,
		offset.x, _set_selected_hurtbox_offset_component.bind(&"x")
	)
	_add_slider(
		vbox, "hurtbox_offset_y", "Move along body part",
		-HurtboxProfile.MAX_OFFSET_METERS, HurtboxProfile.MAX_OFFSET_METERS,
		offset.y, _set_selected_hurtbox_offset_component.bind(&"y")
	)
	_add_slider(
		vbox, "hurtbox_offset_z", "Move forward / back",
		-HurtboxProfile.MAX_OFFSET_METERS, HurtboxProfile.MAX_OFFSET_METERS,
		offset.z, _set_selected_hurtbox_offset_component.bind(&"z")
	)
	var drag_help := Label.new()
	drag_help.text = "Orange points are hitbox centers. Click one to select it, then drag it directly in the preview."
	drag_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	drag_help.add_theme_color_override("font_color", Color("ffb36b"))
	vbox.add_child(drag_help)
	var duplicate_row := HBoxContainer.new()
	vbox.add_child(duplicate_row)
	var copy_hitbox_button := Button.new()
	copy_hitbox_button.name = "CopySelectedHitboxButton"
	copy_hitbox_button.text = "Duplicate Selected"
	copy_hitbox_button.tooltip_text = "Create another real bone-following damage shape from the selected hitbox."
	copy_hitbox_button.pressed.connect(_duplicate_selected_hitbox)
	duplicate_row.add_child(copy_hitbox_button)
	delete_hitbox_button = Button.new()
	delete_hitbox_button.name = "DeleteSelectedHitboxButton"
	delete_hitbox_button.text = "Delete Duplicate"
	delete_hitbox_button.tooltip_text = "Delete the selected extra shape. Built-in anatomy cannot be deleted."
	delete_hitbox_button.pressed.connect(_delete_selected_hitbox)
	duplicate_row.add_child(delete_hitbox_button)
	var alignment_row := HBoxContainer.new()
	vbox.add_child(alignment_row)
	var snap_hitbox_button := Button.new()
	snap_hitbox_button.name = "SnapSelectedHitboxButton"
	snap_hitbox_button.text = "Snap Selected to Rig"
	snap_hitbox_button.tooltip_text = "Center this hitbox on its animated bone span and restore bone-matched length. Width is preserved."
	snap_hitbox_button.pressed.connect(_snap_selected_hurtbox_to_rig)
	alignment_row.add_child(snap_hitbox_button)
	var align_all_hitboxes_button := Button.new()
	align_all_hitboxes_button.name = "AlignAllHitboxesButton"
	align_all_hitboxes_button.text = "Align All to Rig"
	align_all_hitboxes_button.tooltip_text = "Rebuild every hitbox center and length from the animated skeleton. Widths are preserved."
	align_all_hitboxes_button.pressed.connect(_align_all_hitboxes_to_rig)
	alignment_row.add_child(align_all_hitboxes_button)
	var save_hurtboxes_button := Button.new()
	save_hurtboxes_button.name = "SaveSharedHitboxesButton"
	save_hurtboxes_button.text = "Save Shared Hitboxes to Main Game"
	save_hurtboxes_button.tooltip_text = (
		"Writes config/combat/hurtbox_profile.json, loaded by every new gameplay damage rig."
	)
	save_hurtboxes_button.pressed.connect(_save_shared_hurtboxes)
	vbox.add_child(save_hurtboxes_button)

	vbox.add_child(HSeparator.new())
	composure_readout = Label.new()
	composure_readout.add_theme_font_size_override("font_size", 12)
	composure_readout.add_theme_color_override("font_color", Color("a9f4c0"))
	vbox.add_child(composure_readout)

	var reset_button := Button.new()
	reset_button.text = "Reset Current Composure"
	reset_button.pressed.connect(func():
		composure.reset()
		current_bloom = 0.0
		burst_shot_count = 0
	)
	vbox.add_child(reset_button)
	_update_composure_readout()


func _setup_composure_target_preview() -> void:
	composure_preview_dummy = TargetDummyScript.new() as Node3D
	composure_preview_dummy.name = "ComposureTposeTarget"
	composure_preview_dummy.visible = false
	add_child(composure_preview_dummy)
	call_deferred("_finish_composure_target_preview")


func _finish_composure_target_preview() -> void:
	if composure_preview_dummy == null:
		return
	if composure_preview_dummy.has_method("set_hurtbox_debug_visible"):
		composure_preview_dummy.call("set_hurtbox_debug_visible", true)
	if composure_preview_dummy.has_method("apply_hurtbox_tuning"):
		composure_preview_dummy.call("apply_hurtbox_tuning", shared_hurtbox_scales)
	if composure_preview_dummy.has_method("apply_hurtbox_geometry"):
		composure_preview_dummy.call("apply_hurtbox_geometry", shared_hurtbox_geometry)
	if composure_preview_dummy.has_method("apply_custom_hitboxes"):
		composure_preview_dummy.call("apply_custom_hitboxes", shared_custom_hitboxes)
	if composure_preview_dummy.has_method("set_precision_core_debug"):
		composure_preview_dummy.call(
			"set_precision_core_debug",
			composure_preview_active,
			composure.get_precision_core_scale()
		)
	var preview_health := composure_preview_dummy.get_node_or_null("HealthLabel") as Label3D
	if preview_health:
		preview_health.visible = false
	_create_hurtbox_edit_markers()
	_sync_selected_hurtbox_controls()


func _editable_hitbox_ids() -> Array[StringName]:
	var result: Array[StringName] = HurtboxProfile.REGION_KEYS.duplicate()
	for entry in shared_custom_hitboxes:
		result.append(StringName(entry.get("id", &"")))
	return result


func _custom_hitbox_index(editor_id: StringName) -> int:
	for index in shared_custom_hitboxes.size():
		if StringName(shared_custom_hitboxes[index].get("id", &"")) == editor_id:
			return index
	return -1


func _hitbox_source_region(editor_id: StringName) -> StringName:
	var custom_index := _custom_hitbox_index(editor_id)
	if custom_index >= 0:
		return StringName(shared_custom_hitboxes[custom_index].get("source_region", &"torso"))
	return editor_id


func _hitbox_damage_type(editor_id: StringName) -> StringName:
	var custom_index := _custom_hitbox_index(editor_id)
	if custom_index >= 0:
		return StringName(shared_custom_hitboxes[custom_index].get(
			"damage_region",
			HurtboxProfile.damage_type_for_source_region(_hitbox_source_region(editor_id))
		))
	return HurtboxProfile.damage_type_for_source_region(editor_id)


func _hitbox_display_name(editor_id: StringName) -> String:
	var custom_index := _custom_hitbox_index(editor_id)
	if custom_index >= 0:
		return String(shared_custom_hitboxes[custom_index].get(
			"display_name",
			"%s extra" % HurtboxProfile.region_label(_hitbox_source_region(editor_id))
		))
	return HurtboxProfile.region_label(editor_id)


func _hitbox_width(editor_id: StringName) -> float:
	var custom_index := _custom_hitbox_index(editor_id)
	if custom_index >= 0:
		return clampf(
			float(shared_custom_hitboxes[custom_index].get("width_scale", 1.0)),
			HurtboxProfile.MIN_SCALE,
			HurtboxProfile.MAX_SCALE
		)
	return clampf(
		float(shared_hurtbox_scales.get(editor_id, 1.0)),
		HurtboxProfile.MIN_SCALE,
		HurtboxProfile.MAX_SCALE
	)


func _set_hitbox_width(editor_id: StringName, value: float) -> void:
	var bounded := clampf(value, HurtboxProfile.MIN_SCALE, HurtboxProfile.MAX_SCALE)
	var custom_index := _custom_hitbox_index(editor_id)
	if custom_index >= 0:
		shared_custom_hitboxes[custom_index]["width_scale"] = bounded
	else:
		shared_hurtbox_scales[editor_id] = bounded


func _hitbox_geometry(editor_id: StringName) -> Dictionary:
	var custom_index := _custom_hitbox_index(editor_id)
	var geometry_entry: Dictionary
	if custom_index >= 0:
		geometry_entry = (shared_custom_hitboxes[custom_index].get("geometry", {}) as Dictionary).duplicate(true)
	else:
		geometry_entry = (shared_hurtbox_geometry.get(editor_id, {}) as Dictionary).duplicate(true)
	return {editor_id: geometry_entry}


func _set_hitbox_geometry(editor_id: StringName, geometry_entry: Dictionary) -> void:
	var custom_index := _custom_hitbox_index(editor_id)
	if custom_index >= 0:
		shared_custom_hitboxes[custom_index]["geometry"] = geometry_entry.duplicate(true)
	else:
		shared_hurtbox_geometry[editor_id] = geometry_entry.duplicate(true)


func _hitbox_offset(editor_id: StringName) -> Vector3:
	return HurtboxProfile.geometry_offset(_hitbox_geometry(editor_id), editor_id)


func _set_hitbox_offset(editor_id: StringName, offset: Vector3) -> void:
	var geometry := _hitbox_geometry(editor_id)
	HurtboxProfile.set_geometry_offset(geometry, editor_id, offset)
	_set_hitbox_geometry(editor_id, geometry[editor_id])


func _hitbox_length(editor_id: StringName) -> float:
	return HurtboxProfile.geometry_length_scale(_hitbox_geometry(editor_id), editor_id)


func _next_custom_hitbox_id(source_region: StringName) -> StringName:
	var suffix := 1
	while true:
		var candidate := StringName("%s_extra_%d" % [String(source_region), suffix])
		if candidate not in _editable_hitbox_ids():
			return candidate
		suffix += 1
	return &"extra_hitbox"


func _refresh_hurtbox_region_picker() -> void:
	if hurtbox_region_picker == null:
		return
	hurtbox_region_picker.clear()
	for region_key: StringName in HurtboxProfile.REGION_KEYS:
		hurtbox_region_picker.add_item(HurtboxProfile.region_label(region_key))
		hurtbox_region_picker.set_item_metadata(
			hurtbox_region_picker.item_count - 1,
			region_key
		)
	for entry in shared_custom_hitboxes:
		var editor_id := StringName(entry.get("id", &""))
		var damage_type := StringName(entry.get("damage_region", &"TORSO"))
		hurtbox_region_picker.add_item("➕ %s · %s" % [
			_hitbox_display_name(editor_id),
			HurtboxProfile.damage_type_label(damage_type),
		])
		hurtbox_region_picker.set_item_metadata(
			hurtbox_region_picker.item_count - 1,
			editor_id
		)
	for picker_index in hurtbox_region_picker.item_count:
		if StringName(hurtbox_region_picker.get_item_metadata(picker_index)) == selected_hurtbox_region:
			hurtbox_region_picker.select(picker_index)
			break


func _set_shared_hurtbox_scale(value: float, region_key: StringName) -> void:
	shared_hurtbox_scales[region_key] = clampf(
		value,
		HurtboxProfile.MIN_SCALE,
		HurtboxProfile.MAX_SCALE
	)
	_apply_shared_hurtbox_preview()


func _select_hurtbox_region(region_key: StringName) -> void:
	if region_key not in _editable_hitbox_ids():
		return
	selected_hurtbox_region = region_key
	if hurtbox_region_picker:
		for picker_index in hurtbox_region_picker.item_count:
			if StringName(hurtbox_region_picker.get_item_metadata(picker_index)) == region_key:
				hurtbox_region_picker.select(picker_index)
				break
	_sync_selected_hurtbox_controls()
	_update_hurtbox_edit_markers()
	if hud_status:
		hud_status.text = "🟠 Editing %s. Drag its center, resize it, or paint its damage type." % _hitbox_display_name(region_key)


func _set_selected_hurtbox_size(value: float) -> void:
	_set_hitbox_width(selected_hurtbox_region, value)
	_apply_shared_hurtbox_preview()


func _set_selected_hurtbox_length(value: float) -> void:
	var geometry := _hitbox_geometry(selected_hurtbox_region)
	HurtboxProfile.set_geometry_length_scale(geometry, selected_hurtbox_region, value)
	_set_hitbox_geometry(selected_hurtbox_region, geometry[selected_hurtbox_region])
	_apply_shared_hurtbox_preview()


func _set_selected_hurtbox_offset_component(value: float, axis: StringName) -> void:
	var selected_offset := _hitbox_offset(selected_hurtbox_region)
	match axis:
		&"x": selected_offset.x = value
		&"y": selected_offset.y = value
		&"z": selected_offset.z = value
	_set_hitbox_offset(selected_hurtbox_region, selected_offset)
	_apply_shared_hurtbox_preview()


func _sync_selected_hurtbox_controls() -> void:
	_update_slider_value(
		"hurtbox_selected_size",
		_hitbox_width(selected_hurtbox_region)
	)
	_update_slider_value(
		"hurtbox_selected_length",
		_hitbox_length(selected_hurtbox_region)
	)
	var selected_offset := _hitbox_offset(selected_hurtbox_region)
	_update_slider_value("hurtbox_offset_x", selected_offset.x)
	_update_slider_value("hurtbox_offset_y", selected_offset.y)
	_update_slider_value("hurtbox_offset_z", selected_offset.z)
	var length_entry: Dictionary = sliders_map.get("hurtbox_selected_length", {})
	var length_slider := length_entry.get("slider") as HSlider
	if length_slider:
		length_slider.editable = _hitbox_source_region(selected_hurtbox_region) not in [
			&"head", &"left_foot", &"right_foot"
		]
	if delete_hitbox_button:
		delete_hitbox_button.disabled = _custom_hitbox_index(selected_hurtbox_region) < 0
	if hurtbox_damage_type_picker:
		var is_custom := _custom_hitbox_index(selected_hurtbox_region) >= 0
		hurtbox_damage_type_picker.disabled = not is_custom
		var damage_type := _hitbox_damage_type(selected_hurtbox_region)
		for type_index in hurtbox_damage_type_picker.item_count:
			if StringName(hurtbox_damage_type_picker.get_item_metadata(type_index)) == damage_type:
				hurtbox_damage_type_picker.select(type_index)
				break


func _apply_shared_hurtbox_preview() -> void:
	if composure_preview_dummy == null:
		return
	if composure_preview_dummy.has_method("apply_hurtbox_tuning"):
		composure_preview_dummy.call("apply_hurtbox_tuning", shared_hurtbox_scales)
	if composure_preview_dummy.has_method("apply_hurtbox_geometry"):
		composure_preview_dummy.call("apply_hurtbox_geometry", shared_hurtbox_geometry)
	if composure_preview_dummy.has_method("apply_custom_hitboxes"):
		composure_preview_dummy.call("apply_custom_hitboxes", shared_custom_hitboxes)
	_sync_hurtbox_edit_marker_set()
	_update_hurtbox_edit_markers()


func _duplicate_selected_hitbox() -> void:
	var source_region := _hitbox_source_region(selected_hurtbox_region)
	var editor_id := _next_custom_hitbox_id(source_region)
	var geometry_entry := (_hitbox_geometry(selected_hurtbox_region)[selected_hurtbox_region] as Dictionary).duplicate(true)
	var copied_offset := HurtboxProfile.geometry_offset(
		{editor_id: geometry_entry},
		editor_id
	)
	# Put the new physical shape just beside its source so it is immediately
	# visible and selectable instead of hiding perfectly inside the original.
	copied_offset.x += 0.025 if copied_offset.x <= HurtboxProfile.MAX_OFFSET_METERS - 0.025 else -0.025
	HurtboxProfile.set_geometry_offset({editor_id: geometry_entry}, editor_id, copied_offset)
	geometry_entry["offset"] = {
		"x": copied_offset.x, "y": copied_offset.y, "z": copied_offset.z,
	}
	shared_custom_hitboxes.append({
		"id": String(editor_id),
		"source_region": String(source_region),
		"damage_region": String(_hitbox_damage_type(selected_hurtbox_region)),
		"display_name": "%s extra" % HurtboxProfile.region_label(source_region),
		"width_scale": _hitbox_width(selected_hurtbox_region),
		"geometry": geometry_entry,
	})
	shared_custom_hitboxes = HurtboxProfile.normalize_custom_hitboxes(shared_custom_hitboxes)
	_apply_shared_hurtbox_preview()
	_refresh_hurtbox_region_picker()
	_select_hurtbox_region(editor_id)
	if hud_status:
		hud_status.text = "➕ New physical hitbox created. Drag it into place, resize it, then paint its damage type."


func _delete_selected_hitbox() -> void:
	var custom_index := _custom_hitbox_index(selected_hurtbox_region)
	if custom_index < 0:
		_show_rig_error("Built-in anatomy cannot be deleted. Select a duplicate first.")
		return
	var source_region := StringName(shared_custom_hitboxes[custom_index].get("source_region", &"torso"))
	shared_custom_hitboxes.remove_at(custom_index)
	selected_hurtbox_region = source_region
	_apply_shared_hurtbox_preview()
	_refresh_hurtbox_region_picker()
	_select_hurtbox_region(source_region)
	if hud_status:
		hud_status.text = "🗑 Duplicate hitbox removed."


func _set_selected_hurtbox_damage_type(damage_type: StringName) -> void:
	var custom_index := _custom_hitbox_index(selected_hurtbox_region)
	if custom_index < 0 or damage_type not in HurtboxProfile.DAMAGE_TYPE_KEYS:
		return
	shared_custom_hitboxes[custom_index]["damage_region"] = String(damage_type)
	_apply_shared_hurtbox_preview()
	_refresh_hurtbox_region_picker()
	if hud_status:
		hud_status.text = "🎨 %s painted as %s damage." % [
			_hitbox_display_name(selected_hurtbox_region),
			HurtboxProfile.damage_type_label(damage_type),
		]


func _snap_selected_hurtbox_to_rig() -> void:
	var defaults := HurtboxProfile.default_geometry()
	var source_region := _hitbox_source_region(selected_hurtbox_region)
	_set_hitbox_geometry(
		selected_hurtbox_region,
		(defaults[source_region] as Dictionary).duplicate(true)
	)
	_apply_shared_hurtbox_preview()
	_sync_selected_hurtbox_controls()
	if hud_status:
		hud_status.text = "🦴 %s snapped to its animated rig bones. Width and paint were preserved." % _hitbox_display_name(selected_hurtbox_region)


func _align_all_hitboxes_to_rig() -> void:
	shared_hurtbox_geometry = HurtboxProfile.default_geometry()
	_apply_shared_hurtbox_preview()
	_sync_selected_hurtbox_controls()
	if hud_status:
		hud_status.text = "🦴 Built-in hitboxes aligned to the animated rig. Authored duplicates were preserved."


func _create_hurtbox_edit_markers() -> void:
	_sync_hurtbox_edit_marker_set()


func _sync_hurtbox_edit_marker_set() -> void:
	var desired_ids := _editable_hitbox_ids()
	for existing_id: StringName in hurtbox_edit_markers.keys():
		if existing_id in desired_ids:
			continue
		var old_marker := hurtbox_edit_markers[existing_id] as MeshInstance3D
		if is_instance_valid(old_marker):
			old_marker.queue_free()
		hurtbox_edit_markers.erase(existing_id)
	for region_key: StringName in desired_ids:
		if hurtbox_edit_markers.has(region_key):
			continue
		var marker := _create_marker(
			Color(1.0, 0.52, 0.12),
			"HitboxCenter_%s" % String(region_key),
			0.014
		)
		marker.visible = false
		add_child(marker)
		hurtbox_edit_markers[region_key] = marker
	_register_interactive_dots()


func _hurtbox_region_area(region_key: StringName) -> Area3D:
	if composure_preview_dummy == null or not composure_preview_dummy.has_method("get_hurtbox_rig"):
		return null
	var rig := composure_preview_dummy.call("get_hurtbox_rig") as Node3D
	if rig == null:
		return null
	return rig.call("get_editor_hitbox_area", region_key) as Area3D


func _update_hurtbox_edit_markers() -> void:
	for region_key: StringName in hurtbox_edit_markers:
		var marker := hurtbox_edit_markers[region_key] as MeshInstance3D
		var area := _hurtbox_region_area(region_key)
		marker.visible = composure_preview_active and area != null
		if area != null:
			marker.global_position = area.global_position
			marker.scale = Vector3.ONE * (1.45 if region_key == selected_hurtbox_region else 1.0)


func _save_shared_hurtboxes() -> bool:
	if not HurtboxProfile.save_profile(
		shared_hurtbox_scales,
		shared_hurtbox_geometry,
		shared_custom_hitboxes
	):
		_show_rig_error("Could not save the shared gameplay hitbox profile.")
		return false
	if hud_status:
		hud_status.text = "✅ Shared hitboxes saved. Main targets and network operators will load these exact sizes."
		hud_status.tooltip_text = hud_status.text
		hud_status.add_theme_color_override("font_color", Color(0.2, 1.0, 0.4))
	return true


func _on_gun_lab_tab_changed(tab_index: int, tab_container: TabContainer) -> void:
	var selected := tab_container.get_tab_control(tab_index)
	active_lab_tab_name = selected.name if selected != null else ""
	var show_composure := selected != null and selected.name == "Composure"
	composure_preview_active = show_composure
	if trooper_node:
		trooper_node.visible = not show_composure
	if composure_preview_dummy:
		composure_preview_dummy.visible = show_composure
	if hand_gizmo_world:
		hand_gizmo_world.visible = not show_composure
	if weapon_gizmo_world:
		weapon_gizmo_world.visible = not show_composure
	for editor_marker in [
		right_elbow_pole_marker,
		left_elbow_pole_marker,
		left_grip_marker,
		right_grip_marker,
		muzzle_marker,
		barrel_base_marker,
		ejection_marker,
		optic_marker,
		eye_sight_marker,
	]:
		if editor_marker != null:
			(editor_marker as Node3D).visible = not show_composure
	if joint_debug_instance:
		joint_debug_instance.visible = not show_composure
	_update_body_joint_visuals()
	_update_hurtbox_edit_markers()
	if show_composure:
		cam_target = Vector3(0.0, 1.02, 0.0)
		cam_distance = 3.15
		cam_pitch = -2.0
		cam_yaw = 180.0
		_update_camera()

func _add_slider(parent: Control, key: String, label_text: String, min_val: float, max_val: float, initial_val: float, callback: Callable) -> void:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 26
	parent.add_child(row)

	var lbl := Label.new()
	lbl.text = label_text + ":"
	lbl.custom_minimum_size.x = 160
	lbl.add_theme_font_size_override("font_size", 11)
	row.add_child(lbl)

	var slider := HSlider.new()
	slider.min_value = min_val
	slider.max_value = max_val
	slider.step = 0.005 if max_val <= 2.0 else (0.01 if max_val <= 10.0 else 0.5)
	slider.value = initial_val
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.x = 170

	var val_lbl := Label.new()
	val_lbl.text = "%.2f" % initial_val if absf(max_val) >= 5.0 else ("%.3f" % initial_val)
	val_lbl.custom_minimum_size.x = 60
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	val_lbl.add_theme_font_size_override("font_size", 11)
	val_lbl.add_theme_color_override("font_color", Color(1.0, 0.9, 0.4))

	slider.value_changed.connect(func(v: float):
		val_lbl.text = "%.2f" % v if absf(max_val) >= 5.0 else ("%.3f" % v)
		callback.call(v)
	)
	row.add_child(slider)
	row.add_child(val_lbl)

	sliders_map[key] = {"slider": slider, "label": val_lbl, "name_label": lbl, "row": row}

func _current_reticle_profile() -> Dictionary:
	return {
		"base_gap_px": reticle_base_gap_px,
		"max_gap_px": reticle_max_gap_px,
		"response_speed": reticle_response_speed,
		"shot_kick_px": reticle_shot_kick_px,
		"shot_kick_return": reticle_shot_kick_return,
		"maximum_shot_kick_px": reticle_maximum_shot_kick_px,
		"shot_bounce_duration": composure.shot_bounce_duration,
	}


func _current_composure_profile() -> Dictionary:
	var profile := composure.export_profile()
	profile["opening_stress_multiplier"] = composure_opening_stress_multiplier
	profile["graze_damage_scale"] = composure_graze_damage_scale
	return profile


func _apply_reticle_preview_profile() -> void:
	if dynamic_reticle:
		dynamic_reticle.apply_profile(_current_reticle_profile())


func _update_fire_debug_lines() -> void:
	if fire_debug_instance == null:
		return
	if active_lab_tab_name == "Composure":
		fire_debug_instance.visible = false
		return
	fire_debug_mesh.clear_surfaces()
	if not show_bullet_velocity and not show_barrel_axis and not show_camera_aim and not show_eye_sight and not show_last_shot:
		fire_debug_instance.visible = false
		return
	fire_debug_instance.visible = true
	fire_debug_mesh.surface_begin(Mesh.PRIMITIVE_LINES, fire_debug_material)
	var target: Vector3 = (
		current_aim_target
		if current_aim_target != Vector3.ZERO
		else _camera_aim_sample().position
	)
	# Green is velocity, not a camera-to-target connector. It starts at the red
	# muzzle socket and points down local +X, completely independent of either
	# hand socket. Its display length is distance travelled in the first 4 ms.
	if show_bullet_velocity and muzzle_marker:
		_add_fire_debug_segment(
			muzzle_marker.global_position,
			muzzle_marker.global_position
				+ _bullet_velocity_vector() * BULLET_VELOCITY_PREVIEW_SECONDS,
			Color(0.15, 1.0, 0.18)
		)
	if show_barrel_axis and weapon_pivot and muzzle_marker:
		var barrel_base := weapon_pivot.to_global(_calibrated_barrel_base())
		var barrel_direction := _barrel_direction_world()
		_add_fire_debug_segment(
			barrel_base,
			muzzle_marker.global_position + barrel_direction * 5.0,
			Color(1.0, 0.12, 0.08)
		)
	if show_camera_aim and cam:
		_add_fire_debug_segment(cam.global_position, target, Color(0.1, 0.9, 1.0))
	if show_eye_sight and eye_sight_marker:
		var eye_direction := _eye_sight_direction_world()
		_add_fire_debug_segment(
			eye_sight_marker.global_position,
			eye_sight_marker.global_position + eye_direction * 50.0,
			Color(0.25, 0.55, 1.0)
		)
	if show_last_shot and last_shot_origin != last_shot_end:
		_add_fire_debug_segment(last_shot_origin, last_shot_end, Color(1.0, 0.88, 0.15))
	fire_debug_mesh.surface_end()


func _update_eye_sight_marker() -> void:
	if eye_sight_marker == null:
		return
	eye_sight_marker.visible = show_eye_sight and active_lab_tab_name != "Composure"
	if not eye_sight_marker.visible or skeleton == null or head_idx < 0:
		return
	var head_origin := _bone_world_origin(head_idx)
	var operator_up := skeleton.global_basis.y.normalized()
	# This imported operator faces local +Z. Using Godot's conventional -Z put
	# the authored eye point on the back of the skull.
	var operator_forward := skeleton.global_basis.z.normalized()
	# Keep the origin fixed between the eyes. Yaw and pitch rotate only the sight
	# direction; they must never orbit the origin around or behind the skull.
	eye_sight_marker.global_position = (
		head_origin
		+ operator_up * EYE_ORIGIN_HEIGHT_METERS
		+ operator_forward * EYE_ORIGIN_FORWARD_METERS
	)


func _eye_sight_correction() -> Vector3:
	if runtime_posture_layer == null:
		return Vector3.ZERO
	var reference := runtime_posture_layer.get_eye_sight_reference_degrees(
		preview_posture
	)
	return Vector3(reference.x, reference.y, 0.0)


func _eye_sight_direction_world() -> Vector3:
	if skeleton == null:
		return Vector3.FORWARD
	var operator_up := skeleton.global_basis.y.normalized()
	var operator_forward := skeleton.global_basis.z.normalized()
	var correction := _eye_sight_correction()
	var yaw_rotation := Quaternion(operator_up, deg_to_rad(correction.y))
	var yawed_forward := (yaw_rotation * operator_forward).normalized()
	var right_axis := yawed_forward.cross(operator_up).normalized()
	if right_axis.length_squared() < 0.99:
		right_axis = skeleton.global_basis.x.normalized()
	return (
		Quaternion(right_axis, deg_to_rad(correction.x)) * yawed_forward
	).normalized()


func _set_eye_sight_component(value: float, component: StringName) -> void:
	if runtime_posture_layer == null:
		return
	var correction := _eye_sight_correction()
	if component == &"pitch":
		correction.x = value
	elif component == &"yaw":
		correction.y = value
	runtime_posture_layer.set_eye_sight_reference_degrees(
		preview_posture,
		Vector2(correction.x, correction.y)
	)


func _sync_eye_sight_controls() -> void:
	var correction := _eye_sight_correction()
	_update_slider_value("eye_sight_pitch", correction.x)
	_update_slider_value("eye_sight_yaw", correction.y)


func _add_fire_debug_segment(start: Vector3, finish: Vector3, color: Color) -> void:
	fire_debug_mesh.surface_set_color(color)
	fire_debug_mesh.surface_add_vertex(start)
	fire_debug_mesh.surface_set_color(color)
	fire_debug_mesh.surface_add_vertex(finish)


func _draw_socom_reticle() -> void:
	# The shared SocomDynamicReticle owns the actual reticle. This transparent
	# overlay only draws calibration selection brackets above it.
	_draw_active_selection_brackets()

func _draw_active_selection_brackets() -> void:
	if not cam or not reticle_canvas: return
	var target_world := Vector3.ZERO
	var selected_id := ""
	var color := Color(1.0, 0.55, 0.08)
	if active_lab_tab_name == "Composure":
		var hitbox_marker := hurtbox_edit_markers.get(selected_hurtbox_region) as MeshInstance3D
		if hitbox_marker == null or not hitbox_marker.visible:
			return
		target_world = hitbox_marker.global_position
		selected_id = "hurtbox:%s" % String(selected_hurtbox_region)
		color = Color(1.0, 0.52, 0.12)
	elif active_gizmo_id == "hand":
		if not left_grip_marker or not is_instance_valid(left_grip_marker): return
		target_world = left_grip_marker.global_position
		selected_id = "left_ik"
		color = Color(0.0, 0.95, 1.0)
	else:
		if not weapon_gizmo_world or not is_instance_valid(weapon_gizmo_world): return
		target_world = weapon_gizmo_world.global_position
		selected_id = "weapon_mount"
	if cam.is_position_behind(target_world): return

	var center := cam.unproject_position(target_world)
	var is_hovered := hovered_dot_id == selected_id or dragged_dot_id == selected_id
	var radius := 17.0 if is_hovered else 14.0
	var arm := 7.0
	color = Color.WHITE if is_hovered else color
	var width := 3.0 if is_hovered else 2.0
	# Four unobtrusive L-shaped brackets highlight the selected real object.
	reticle_canvas.draw_line(center + Vector2(-radius, -radius), center + Vector2(-radius + arm, -radius), color, width, true)
	reticle_canvas.draw_line(center + Vector2(-radius, -radius), center + Vector2(-radius, -radius + arm), color, width, true)
	reticle_canvas.draw_line(center + Vector2(radius, -radius), center + Vector2(radius - arm, -radius), color, width, true)
	reticle_canvas.draw_line(center + Vector2(radius, -radius), center + Vector2(radius, -radius + arm), color, width, true)
	reticle_canvas.draw_line(center + Vector2(-radius, radius), center + Vector2(-radius + arm, radius), color, width, true)
	reticle_canvas.draw_line(center + Vector2(-radius, radius), center + Vector2(-radius, radius - arm), color, width, true)
	reticle_canvas.draw_line(center + Vector2(radius, radius), center + Vector2(radius - arm, radius), color, width, true)
	reticle_canvas.draw_line(center + Vector2(radius, radius), center + Vector2(radius, radius - arm), color, width, true)

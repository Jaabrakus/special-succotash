class_name GunCalibrationLab
extends Node3D

## SOCOM-141 AAA Tactical Gunsmith & Biomechanical Arm Engine
## Full Anatomical Human Arm Biomechanics (Anatomical Hinge Elbow, Shoulder Ball-Socket, Palm Alignment)
## Left hand automatically finds and biomechanically grips Socket_LeftHand on any firearm.

const PS1_GAS_MASK_RIGGED_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const PS1_GAS_MASK_TEX := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const WEAPON_BASE_PATH := "res://assets/weapons/modular_pack/"

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
var skeleton: Skeleton3D
var animation_player: AnimationPlayer

# Bone Indices
var left_arm_idx: int = -1
var left_forearm_idx: int = -1
var left_hand_idx: int = -1
var right_arm_idx: int = -1
var right_forearm_idx: int = -1
var right_hand_idx: int = -1

# Biomechanical Engine Parameters
var upper_arm_len: float = 0.315
var forearm_len: float = 0.312
var max_reach: float = 0.620

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
var current_weapon_mesh: Node3D
var current_silencer_mesh: Node3D
var current_scope_mesh: Node3D

# Unscaled World 3D Transform Gizmo for Hand
var hand_gizmo_world: Node3D
var gizmo_arrow_x: Node3D
var gizmo_arrow_y: Node3D
var gizmo_arrow_z: Node3D
var gizmo_ring_roll: MeshInstance3D
var gizmo_ring_pitch: MeshInstance3D

# Weapon Sockets
var left_grip_marker: MeshInstance3D
var muzzle_marker: MeshInstance3D
var ejection_marker: MeshInstance3D
var optic_marker: MeshInstance3D

# Transform Calibration
var grip_offset_pos := Vector3.ZERO
var grip_offset_rot := Vector3.ZERO
var user_scale_multiplier: float = 1.0
var auto_normalized_scale: float = 1.0
var auto_grip_center_offset := Vector3.ZERO

# Socket Local Coordinates on Weapon Mesh
var left_grip_local_pos := Vector3(0.20, -0.03, 0.0)
var muzzle_local_pos := Vector3(0.70, 0.02, 0.0)
var ejection_local_pos := Vector3(0.05, 0.03, 0.06)
var optic_local_pos := Vector3(0.05, 0.08, 0.0)

# Interactive 3D Dragging
var interactive_dots: Array[Dictionary] = []
var hovered_dot_id: String = ""
var dragged_dot_id: String = ""
var drag_plane := Plane()
var drag_initial_world := Vector3.ZERO
var drag_offset_vector := Vector3.ZERO

# Ballistics & Firing
var weapon_name: String = "AssaultRifle_1"
var selected_category: String = "Assault Rifles"
var fire_rate_rpm: int = 650
var damage_per_shot: int = 34
var is_silenced: bool = false
var base_spread_deg: float = 0.4
var bloom_per_shot_deg: float = 1.2
var bloom_recovery_speed: float = 14.0
var current_bloom: float = 0.0
var fire_cooldown: float = 0.0
var burst_shot_count: int = 0
var is_reloading: bool = false

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

# Every imported animation can be previewed against the live weapon sockets.
# Per-clip hand maps let one weapon keep distinct contact poses for idle,
# locomotion, prone, reload, and action animations.
var all_animation_entries: Array[Dictionary] = []
var all_animation_paths: Dictionary = {}
var all_animation_select: OptionButton
var selected_animation_key: StringName = &""
var animation_hand_maps: Dictionary = {}

# UI Sliders Map
var sliders_map: Dictionary = {}
var overlay: Control
var hud_status: Label
var reticle_canvas: Control
var reticle_bloom_radius: float = 12.0

func _ready() -> void:
	_scan_all_animation_assets()
	_setup_studio_environment()
	_setup_trooper_and_rig()
	_setup_target_range()
	_load_weapon(selected_weapon_file)
	_build_studio_ui()

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var ek := event as InputEventKey
		if ek.keycode == KEY_S and (ek.ctrl_pressed or ek.meta_pressed):
			_save_weapon_config()
			get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_R and not (ek.ctrl_pressed or ek.meta_pressed):
			_trigger_reload_animation()
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var target_dot := dragged_dot_id if dragged_dot_id != "" else hovered_dot_id

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if target_dot == "left_ik":
				left_grip_local_pos.x = clampf(left_grip_local_pos.x + 0.015, -0.40, 1.20)
				_sync_markers()
				_update_slider_value("ik_x", left_grip_local_pos.x)
				get_viewport().set_input_as_handled()
				return
			elif target_dot == "right_hand":
				grip_offset_rot.y = wrapf(grip_offset_rot.y + 3.0, -180.0, 180.0)
				_sync_weapon_transform()
				_update_slider_value("rot_yaw", grip_offset_rot.y)
				get_viewport().set_input_as_handled()
				return
			else:
				cam_distance = clampf(cam_distance - 0.08, 0.20, 3.5)
				_update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if target_dot == "left_ik":
				left_grip_local_pos.x = clampf(left_grip_local_pos.x - 0.015, -0.40, 1.20)
				_sync_markers()
				_update_slider_value("ik_x", left_grip_local_pos.x)
				get_viewport().set_input_as_handled()
				return
			elif target_dot == "right_hand":
				grip_offset_rot.y = wrapf(grip_offset_rot.y - 3.0, -180.0, 180.0)
				_sync_weapon_transform()
				_update_slider_value("rot_yaw", grip_offset_rot.y)
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
				var hit_dot := _find_dot_under_mouse(mb.position)
				if hit_dot != "":
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
							hud_status.text = "🎯 Positioning %s (Left arm biomechanically auto-grips!)" % hit_dot
			else:
				if dragged_dot_id != "":
					if hud_status:
						hud_status.text = "✅ %s locked!" % dragged_dot_id
					dragged_dot_id = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
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
			if dragged_dot_id == "left_ik_ring_roll":
				palm_roll = wrapf(palm_roll + mm.relative.x * 0.85, -180.0, 180.0)
				_update_slider_value("p_roll", palm_roll)
				if hud_status: hud_status.text = "🟡 Spinning Palm Roll: %.1f° (Underneath / C-Clamp)" % palm_roll
			elif dragged_dot_id == "left_ik_ring_pitch":
				palm_pitch = clampf(palm_pitch - mm.relative.y * 0.65, -90.0, 90.0)
				_update_slider_value("p_pitch", palm_pitch)
				if hud_status: hud_status.text = "🟣 Tilting Wrist Pitch: %.1f°" % palm_pitch
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
		fire_cooldown -= delta

	if current_bloom > 0.0:
		current_bloom = maxf(0.0, current_bloom - bloom_recovery_speed * delta)
		if current_bloom <= 0.01:
			burst_shot_count = 0

	if (Input.is_key_pressed(KEY_SPACE) or (Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and dragged_dot_id == "")) and not is_orbiting and not is_panning and not is_reloading:
		if fire_cooldown <= 0.0:
			_fire_shot()

	if animation_player:
		animation_player.advance(delta)

	_solve_biomechanical_arm_engine()
	_apply_hand_and_finger_posing()
	if skeleton:
		skeleton.force_update_all_bone_transforms()

	if hand_gizmo_world and left_grip_marker and is_instance_valid(left_grip_marker):
		hand_gizmo_world.global_position = left_grip_marker.global_position
		if current_weapon_mesh:
			hand_gizmo_world.global_basis = current_weapon_mesh.global_basis.orthonormalized()

	reticle_bloom_radius = lerpf(reticle_bloom_radius, 12.0 + current_bloom * 16.0, delta * 20.0)
	if reticle_canvas:
		reticle_canvas.queue_redraw()

var left_hand_ik: SkeletonIK3D

func _solve_biomechanical_arm_engine() -> void:
	if not skeleton or is_reloading or not left_grip_marker or not is_instance_valid(left_grip_marker): return
	if not left_hand_ik: return

	# Feed exact target transform directly in local skeleton space
	var target_global_xf := left_grip_marker.global_transform
	var palm_rot := Basis.from_euler(Vector3(deg_to_rad(palm_pitch), deg_to_rad(palm_yaw), deg_to_rad(palm_roll)))
	target_global_xf.basis = target_global_xf.basis * palm_rot

	left_hand_ik.target = skeleton.global_transform.affine_inverse() * target_global_xf
	left_hand_ik.override_tip_basis = true

	# Magnet vector defines natural human elbow direction
	match current_grip_style:
		GripStyle.CLASSIC_CRADLE:
			left_hand_ik.magnet = Vector3(-0.35, -0.75, 0.15)
		GripStyle.C_CLAMP_TACTICAL:
			left_hand_ik.magnet = Vector3(-0.65, -0.20, 0.40)
		GripStyle.MAGWELL_GRIP:
			left_hand_ik.magnet = Vector3(-0.20, -0.85, -0.10)
		GripStyle.VERTICAL_FOREGRIP:
			left_hand_ik.magnet = Vector3(-0.40, -0.70, 0.0)
		GripStyle.ANGLED_AFG:
			left_hand_ik.magnet = Vector3(-0.50, -0.55, 0.25)

	if not left_hand_ik.is_running():
		left_hand_ik.start()

func _apply_hand_and_finger_posing() -> void:
	if not skeleton or is_reloading: return

	# 1. Palm Orientation Adjustment
	if left_hand_idx >= 0:
		var palm_rot := Quaternion.from_euler(Vector3(deg_to_rad(palm_pitch), deg_to_rad(palm_yaw), deg_to_rad(palm_roll)))
		var cur_rot := skeleton.get_bone_pose_rotation(left_hand_idx)
		skeleton.set_bone_pose_rotation(left_hand_idx, cur_rot * palm_rot)

	# 2. Fingers Curl (Wrapping around handguard)
	var idx1 := skeleton.find_bone("mixamorig_LeftHandIndex1")
	var idx2 := skeleton.find_bone("mixamorig_LeftHandIndex2")
	var idx3 := skeleton.find_bone("mixamorig_LeftHandIndex3")
	var curl_rad := deg_to_rad(finger_curl * 80.0)

	if idx1 >= 0: skeleton.set_bone_pose_rotation(idx1, Quaternion(Vector3.RIGHT, curl_rad * 0.45))
	if idx2 >= 0: skeleton.set_bone_pose_rotation(idx2, Quaternion(Vector3.RIGHT, curl_rad * 0.35))
	if idx3 >= 0: skeleton.set_bone_pose_rotation(idx3, Quaternion(Vector3.RIGHT, curl_rad * 0.20))

	# 3. Thumb Wrap
	var th1 := skeleton.find_bone("mixamorig_LeftHandThumb1")
	var th2 := skeleton.find_bone("mixamorig_LeftHandThumb2")
	var th3 := skeleton.find_bone("mixamorig_LeftHandThumb3")
	var thumb_rad := deg_to_rad(thumb_wrap * 65.0)

	if th1 >= 0: skeleton.set_bone_pose_rotation(th1, Quaternion(Vector3.FORWARD, thumb_rad * 0.5) * Quaternion(Vector3.UP, thumb_rad * 0.3))
	if th2 >= 0: skeleton.set_bone_pose_rotation(th2, Quaternion(Vector3.FORWARD, thumb_rad * 0.5))

func _trigger_reload_animation() -> void:
	if is_reloading: return
	is_reloading = true
	if hud_status: hud_status.text = "🔄 Reloading... Left hand leaves foregrip to change mag!"

	if animation_player and animation_player.has_animation("reload"):
		animation_player.play("reload")
		get_tree().create_timer(1.8).timeout.connect(func():
			if animation_player: animation_player.play("aim_idle")
			is_reloading = false
			if hud_status: hud_status.text = "✅ Reload complete! Biomechanical engine relocked left hand."
		)
	else:
		get_tree().create_timer(1.2).timeout.connect(func():
			is_reloading = false
			if hud_status: hud_status.text = "✅ Reload complete! Biomechanical engine relocked left hand."
		)

func _setup_unscaled_hand_gizmo() -> void:
	if hand_gizmo_world and is_instance_valid(hand_gizmo_world):
		hand_gizmo_world.queue_free()
		hand_gizmo_world = null

	hand_gizmo_world = Node3D.new()
	hand_gizmo_world.name = "HandGizmoWorld"
	add_child(hand_gizmo_world)

	# Full Extra-Large Human-Scale 3D Transform Gizmo (0.26m arrows, 0.24m rings)
	gizmo_arrow_x = _create_axis_arrow(Color(1.0, 0.25, 0.25), Vector3.RIGHT, "left_ik_arrow_x", 0.26)
	gizmo_arrow_y = _create_axis_arrow(Color(0.25, 1.0, 0.25), Vector3.UP, "left_ik_arrow_y", 0.26)
	gizmo_arrow_z = _create_axis_arrow(Color(0.35, 0.65, 1.0), Vector3.BACK, "left_ik_arrow_z", 0.26)
	gizmo_ring_roll = _create_rotation_ring(Color(1.0, 0.9, 0.2), Vector3.RIGHT, 0.24, "left_ik_ring_roll")
	gizmo_ring_pitch = _create_rotation_ring(Color(1.0, 0.3, 0.9), Vector3.BACK, 0.24, "left_ik_ring_pitch")

	hand_gizmo_world.add_child(gizmo_arrow_x)
	hand_gizmo_world.add_child(gizmo_arrow_y)
	hand_gizmo_world.add_child(gizmo_arrow_z)
	hand_gizmo_world.add_child(gizmo_ring_roll)
	hand_gizmo_world.add_child(gizmo_ring_pitch)

func _register_interactive_dots() -> void:
	interactive_dots.clear()
	if left_grip_marker:
		interactive_dots.append({"id": "left_ik", "mesh": left_grip_marker, "label": "🔵 Hand Rig (Free 3D Translate)", "color": Color(0.0, 0.95, 1.0)})
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

	if muzzle_marker: interactive_dots.append({"id": "muzzle", "mesh": muzzle_marker, "label": "🔴 Muzzle Tip Socket", "color": Color(1.0, 0.2, 0.2)})
	if ejection_marker: interactive_dots.append({"id": "ejection", "mesh": ejection_marker, "label": "🟡 Shell Ejection Port", "color": Color(1.0, 0.85, 0.1)})
	if optic_marker: interactive_dots.append({"id": "optic", "mesh": optic_marker, "label": "🟢 Optic Scope Rail", "color": Color(0.2, 1.0, 0.4)})
	if right_hand_dot: interactive_dots.append({"id": "right_hand", "mesh": right_hand_dot, "label": "🟠 Weapon Mount (Right Hand)", "color": Color(1.0, 0.6, 0.1)})

func _find_dot_under_mouse(screen_pos: Vector2) -> String:
	if not cam: return ""
	var closest_id := ""
	var closest_dist := 48.0

	var center_world := Vector3.ZERO
	var gizmo_basis := Basis.IDENTITY
	if hand_gizmo_world and is_instance_valid(hand_gizmo_world):
		center_world = hand_gizmo_world.global_position
		gizmo_basis = hand_gizmo_world.global_basis

	for item in interactive_dots:
		var id: String = item["id"]
		var mi: MeshInstance3D = item["mesh"]
		if not mi or not is_instance_valid(mi): continue

		# Accurate 3D Geometric Hit-Testing for Gizmo
		if id == "left_ik_ring_roll":
			# Yellow Ring: Circle in YZ plane around X axis
			for i in range(24):
				var angle := (TAU / 24.0) * float(i)
				var ring_pt := center_world + (gizmo_basis.y * cos(angle) + gizmo_basis.z * sin(angle)) * 0.24
				if not cam.is_position_behind(ring_pt):
					var p2d := cam.unproject_position(ring_pt)
					var dist := screen_pos.distance_to(p2d)
					if dist < closest_dist:
						closest_dist = dist
						closest_id = id
			continue

		if id == "left_ik_ring_pitch":
			# Magenta Ring: Circle in XY plane around Z axis
			for i in range(24):
				var angle := (TAU / 24.0) * float(i)
				var ring_pt := center_world + (gizmo_basis.x * cos(angle) + gizmo_basis.y * sin(angle)) * 0.24
				if not cam.is_position_behind(ring_pt):
					var p2d := cam.unproject_position(ring_pt)
					var dist := screen_pos.distance_to(p2d)
					if dist < closest_dist:
						closest_dist = dist
						closest_id = id
			continue
		elif id == "left_ik_arrow_x":
			var tip := center_world + gizmo_basis.x * 0.16
			if not cam.is_position_behind(tip):
				var dist := screen_pos.distance_to(cam.unproject_position(tip))
				if dist < closest_dist:
					closest_dist = dist
					closest_id = id
		elif id == "left_ik_arrow_y":
			var tip := center_world + gizmo_basis.y * 0.16
			if not cam.is_position_behind(tip):
				var dist := screen_pos.distance_to(cam.unproject_position(tip))
				if dist < closest_dist:
					closest_dist = dist
					closest_id = id
		elif id == "left_ik_arrow_z":
			var tip := center_world - gizmo_basis.z * 0.16
			if not cam.is_position_behind(tip):
				var dist := screen_pos.distance_to(cam.unproject_position(tip))
				if dist < closest_dist:
					closest_dist = dist
					closest_id = id
		else:
			if not cam.is_position_behind(mi.global_position):
				var p2d := cam.unproject_position(mi.global_position)
				var dist := screen_pos.distance_to(p2d)
				if dist < closest_dist:
					closest_dist = dist
					closest_id = id
	return closest_id

func _get_dot_mesh_by_id(dot_id: String) -> MeshInstance3D:
	for item in interactive_dots:
		if item["id"] == dot_id: return item["mesh"]
	return null

func _highlight_dot(dot_id: String) -> void:
	for item in interactive_dots:
		var mi: MeshInstance3D = item["mesh"]
		if mi and is_instance_valid(mi):
			var is_target: bool = (item["id"] == dot_id)
			mi.scale = Vector3.ONE * (1.6 if is_target else 1.0)
			var mat = mi.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color.WHITE if is_target else (item["color"] as Color)

func _apply_dot_world_drag(dot_id: String, world_pos: Vector3) -> void:
	match dot_id:
		"left_ik":
			if current_weapon_mesh:
				left_grip_local_pos = current_weapon_mesh.global_transform.affine_inverse() * world_pos
				_sync_markers()
				_update_slider_value("ik_x", left_grip_local_pos.x)
				_update_slider_value("ik_y", left_grip_local_pos.y)
				_update_slider_value("ik_z", left_grip_local_pos.z)
		"muzzle":
			if current_weapon_mesh:
				muzzle_local_pos = current_weapon_mesh.global_transform.affine_inverse() * world_pos
				_sync_markers()
				_update_slider_value("mz_x", muzzle_local_pos.x)
				_update_slider_value("mz_y", muzzle_local_pos.y)
				_update_slider_value("mz_z", muzzle_local_pos.z)
		"ejection":
			if current_weapon_mesh:
				ejection_local_pos = current_weapon_mesh.global_transform.affine_inverse() * world_pos
				_sync_markers()
				_update_slider_value("ej_x", ejection_local_pos.x)
				_update_slider_value("ej_y", ejection_local_pos.y)
				_update_slider_value("ej_z", ejection_local_pos.z)
		"optic":
			if current_weapon_mesh:
				optic_local_pos = current_weapon_mesh.global_transform.affine_inverse() * world_pos
				_sync_markers()
				_update_slider_value("op_x", optic_local_pos.x)
				_update_slider_value("op_y", optic_local_pos.y)
				_update_slider_value("op_z", optic_local_pos.z)
		"right_hand":
			if weapon_root:
				var loc: Vector3 = weapon_root.global_transform.affine_inverse() * world_pos
				grip_offset_pos = loc - auto_grip_center_offset
				_sync_weapon_transform()
				_update_slider_value("grip_x", grip_offset_pos.x)
				_update_slider_value("grip_y", grip_offset_pos.y)
				_update_slider_value("grip_z", grip_offset_pos.z)

func _update_slider_value(slider_key: String, val: float) -> void:
	if sliders_map.has(slider_key):
		var s: HSlider = sliders_map[slider_key]["slider"]
		var lbl: Label = sliders_map[slider_key]["label"]
		if s:
			s.set_value_no_signal(val)
			if lbl: lbl.text = "%.2f" % val if absf(val) >= 5.0 else ("%.3f" % val)

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

	if left_arm_idx >= 0 and left_hand_idx >= 0:
		left_hand_ik = SkeletonIK3D.new()
		left_hand_ik.name = "LeftHandIK"
		left_hand_ik.root_bone = "mixamorig_LeftArm"
		left_hand_ik.tip_bone = "mixamorig_LeftHand"
		left_hand_ik.use_magnet = true
		left_hand_ik.magnet = Vector3(-0.35, -0.75, 0.15)
		skeleton.add_child(left_hand_ik)
		left_hand_ik.start()

	var inv_scale := 1.0 / trooper_scale

	if right_hand_idx >= 0:
		ba_right_hand = BoneAttachment3D.new()
		ba_right_hand.name = "BA_RightHand"
		ba_right_hand.bone_name = "mixamorig_RightHand"
		skeleton.add_child(ba_right_hand)
		right_hand_dot = _create_marker(Color(1.0, 0.6, 0.1), "RightHand_Bone_Dot", 0.024 * inv_scale)
		ba_right_hand.add_child(right_hand_dot)

		weapon_root = Node3D.new()
		weapon_root.name = "WeaponRoot"
		weapon_root.scale = Vector3.ONE * inv_scale
		weapon_root.position = Vector3(-0.02, 0.08, 0.05) * inv_scale
		weapon_root.rotation_degrees = Vector3(-90, 180, 0)
		ba_right_hand.add_child(weapon_root)

		weapon_pivot = Node3D.new()
		weapon_pivot.name = "WeaponPivot"
		weapon_root.add_child(weapon_pivot)

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
	cyl.top_radius = 0.012
	cyl.bottom_radius = 0.012
	cyl.height = length
	shaft.mesh = cyl

	var head := MeshInstance3D.new()
	var cone := CylinderMesh.new()
	cone.top_radius = 0.0
	cone.bottom_radius = 0.028
	cone.height = 0.065
	head.mesh = cone

	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.render_priority = 110
	mat.no_depth_test = true
	shaft.material_override = mat
	head.material_override = mat

	shaft.position = Vector3(0, length * 0.5, 0)
	head.position = Vector3(0, length + 0.032, 0)
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
	torus.inner_radius = radius - 0.014
	torus.outer_radius = radius + 0.014
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

func _load_weapon(file_name: String) -> void:
	selected_weapon_file = file_name
	weapon_name = file_name

	if current_weapon_mesh:
		current_weapon_mesh.queue_free()
		current_weapon_mesh = null
	if current_silencer_mesh:
		current_silencer_mesh.queue_free()
		current_silencer_mesh = null
	if current_scope_mesh:
		current_scope_mesh.queue_free()
		current_scope_mesh = null

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
	weapon_pivot.add_child(current_weapon_mesh)

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

	# Sockets directly attached to Weapon Mesh!
	left_grip_marker = _create_marker(Color(0.0, 0.95, 1.0), "Socket_LeftHand", 0.055)
	muzzle_marker = _create_marker(Color(1.0, 0.2, 0.2), "Socket_Muzzle", 0.055)
	ejection_marker = _create_marker(Color(1.0, 0.85, 0.1), "Socket_Ejection", 0.050)
	optic_marker = _create_marker(Color(0.2, 1.0, 0.4), "Socket_Optic", 0.048)

	current_weapon_mesh.add_child(left_grip_marker)
	current_weapon_mesh.add_child(muzzle_marker)
	current_weapon_mesh.add_child(ejection_marker)
	current_weapon_mesh.add_child(optic_marker)

	_setup_unscaled_hand_gizmo()

	left_grip_local_pos = Vector3(target_len * 0.20, -0.03, 0.0)
	muzzle_local_pos = Vector3(target_len * 0.70, 0.02, 0.0)
	ejection_local_pos = Vector3(target_len * 0.05, 0.03, 0.06)
	optic_local_pos = Vector3(target_len * 0.05, 0.08, 0.0)

	_try_load_saved_profile(weapon_name)

	_sync_weapon_transform()
	_sync_markers()
	_register_interactive_dots()

	if left_hand_ik and left_grip_marker:
		left_hand_ik.target_node = left_grip_marker.get_path()
		left_hand_ik.start()

	if selected_silencer != "None": _load_silencer(selected_silencer)
	if selected_scope != "None": _load_scope(selected_scope)

func _try_load_saved_profile(w_id: String) -> void:
	var cfg_path := "res://config/weapons/" + w_id.to_lower() + ".json"
	if FileAccess.file_exists(cfg_path):
		var file := FileAccess.open(cfg_path, FileAccess.READ)
		if file:
			var json := JSON.new()
			if json.parse(file.get_as_text()) == OK and json.data is Dictionary:
				var d: Dictionary = json.data
				if d.get("animation_hand_maps", {}) is Dictionary:
					animation_hand_maps = (d.get("animation_hand_maps", {}) as Dictionary).duplicate(true)
				var sock: Dictionary = d.get("weapon_sockets", {})
				if sock.has("left_hand_ik_target"):
					var ik = sock["left_hand_ik_target"]
					left_grip_local_pos = Vector3(ik.get("x", left_grip_local_pos.x), ik.get("y", left_grip_local_pos.y), ik.get("z", left_grip_local_pos.z))
				elif d.has("left_hand_ik_target"):
					var ik = d["left_hand_ik_target"]
					left_grip_local_pos = Vector3(ik.get("x", left_grip_local_pos.x), ik.get("y", left_grip_local_pos.y), ik.get("z", left_grip_local_pos.z))

				if sock.has("muzzle_socket"):
					var mz = sock["muzzle_socket"]
					muzzle_local_pos = Vector3(mz.get("x", muzzle_local_pos.x), mz.get("y", muzzle_local_pos.y), mz.get("z", muzzle_local_pos.z))
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
			file.close()

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

func _sync_weapon_transform() -> void:
	if not weapon_pivot: return
	weapon_pivot.position = auto_grip_center_offset + grip_offset_pos
	weapon_pivot.rotation_degrees = grip_offset_rot
	if current_weapon_mesh:
		current_weapon_mesh.scale = Vector3.ONE * (auto_normalized_scale * user_scale_multiplier)

func _sync_markers() -> void:
	if left_grip_marker: left_grip_marker.position = left_grip_local_pos
	if muzzle_marker: muzzle_marker.position = muzzle_local_pos
	if ejection_marker: ejection_marker.position = ejection_local_pos
	if optic_marker: optic_marker.position = optic_local_pos
	if current_silencer_mesh and muzzle_marker: current_silencer_mesh.position = muzzle_marker.position
	if current_scope_mesh and optic_marker: current_scope_mesh.position = optic_marker.position

func _fire_shot() -> void:
	var interval := 60.0 / float(maxi(100, fire_rate_rpm))
	fire_cooldown = interval
	burst_shot_count += 1

	if burst_shot_count > 2:
		current_bloom += bloom_per_shot_deg

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

		bullet_tracers.add_child(tracer)
		tracer.global_position = muzzle_marker.global_position
		tracer.look_at(target_board.global_position + Vector3(randf_range(-current_bloom*0.04, current_bloom*0.04), randf_range(-current_bloom*0.04, current_bloom*0.04), 0))
		tracer.rotation_degrees.x += 90.0

		var tween := create_tween()
		tween.tween_property(tracer, "global_position", target_board.global_position, 0.07)
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

func _scan_all_animation_assets() -> void:
	all_animation_entries.clear()
	all_animation_paths.clear()
	_scan_animation_directory("res://assets/animations")
	all_animation_entries.sort_custom(func(a: Dictionary, b: Dictionary):
		return String(a.get("display", "")).naturalnocasecmp_to(
			String(b.get("display", ""))
		) < 0
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
		elif (
			file_name.ends_with(".fbx")
			or file_name.ends_with(".glb")
			or file_name.ends_with(".gltf")
		) and not file_name.begins_with("."):
			var full_path := "%s/%s" % [directory_path, file_name]
			var relative_path := full_path.trim_prefix("res://assets/animations/")
			var key := StringName("gunsmith_catalog_%s" % abs(full_path.hash()))
			all_animation_paths[key] = full_path
			all_animation_entries.append({
				"key": key,
				"display": relative_path.get_basename().replace("/", " › ").capitalize(),
				"path": full_path,
			})
		file_name = directory.get_next()
	directory.list_dir_end()

func _preview_selected_catalog_animation() -> void:
	if all_animation_select == null or all_animation_select.item_count == 0:
		return
	var clip_key := StringName(
		all_animation_select.get_item_metadata(all_animation_select.selected)
	)
	if clip_key == &"" or not _ensure_catalog_animation(clip_key):
		if hud_status:
			hud_status.text = "⚠ Could not load the selected animation."
		return
	selected_animation_key = clip_key
	_apply_animation_hand_map(clip_key)
	is_reloading = false
	animation_player.play(clip_key, 0.08)
	if hud_status:
		hud_status.text = "▶ Inspecting %s — both hand and weapon gizmos remain live." % _catalog_display_name(clip_key)

func _ensure_catalog_animation(clip_key: StringName) -> bool:
	if animation_player == null:
		return false
	if animation_player.has_animation(clip_key):
		return true
	var resource_path := String(all_animation_paths.get(clip_key, ""))
	if resource_path.is_empty():
		return false
	var packed := load(resource_path) as PackedScene
	if packed == null:
		return false
	var source_root := packed.instantiate()
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
	if _catalog_clip_should_loop(resource_path):
		retargeted.loop_mode = Animation.LOOP_LINEAR
	var library := animation_player.get_animation_library(&"")
	if library == null:
		library = AnimationLibrary.new()
		animation_player.add_animation_library(&"", library)
	library.add_animation(clip_key, retargeted)
	source_root.queue_free()
	return true

func _catalog_clip_should_loop(resource_path: String) -> bool:
	var normalized := resource_path.to_lower()
	for token in ["idle", "walk", "run", "strafe", "crawl", "prone forward", "prone backwards"]:
		if token in normalized:
			return true
	return false

func _catalog_display_name(clip_key: StringName) -> String:
	for entry in all_animation_entries:
		if StringName(entry.get("key", &"")) == clip_key:
			return String(entry.get("display", clip_key))
	return String(clip_key)

func _catalog_path(clip_key: StringName) -> String:
	return String(all_animation_paths.get(clip_key, ""))

func _save_selected_animation_hand_map() -> void:
	if all_animation_select == null or all_animation_select.item_count == 0:
		return
	var clip_key := selected_animation_key
	if clip_key == &"":
		clip_key = StringName(
			all_animation_select.get_item_metadata(all_animation_select.selected)
		)
	var resource_path := _catalog_path(clip_key)
	if resource_path.is_empty():
		return
	animation_hand_maps[resource_path] = {
		"left_grip": _vector_to_data(left_grip_local_pos),
		"weapon_mount_position": _vector_to_data(grip_offset_pos),
		"weapon_mount_rotation_deg": _vector_to_data(grip_offset_rot),
		"palm_pitch_deg": palm_pitch,
		"palm_yaw_deg": palm_yaw,
		"palm_roll_deg": palm_roll,
		"finger_curl": finger_curl,
		"thumb_wrap": thumb_wrap,
	}
	if hud_status:
		hud_status.text = "💾 Hand map staged for %s. Ctrl/Cmd+S saves it with this weapon." % _catalog_display_name(clip_key)

func _apply_animation_hand_map(clip_key: StringName) -> void:
	var resource_path := _catalog_path(clip_key)
	var raw_map: Variant = animation_hand_maps.get(resource_path, {})
	if not (raw_map is Dictionary) or (raw_map as Dictionary).is_empty():
		return
	var hand_map := raw_map as Dictionary
	left_grip_local_pos = _vector_from_data(hand_map.get("left_grip", {}), left_grip_local_pos)
	grip_offset_pos = _vector_from_data(
		hand_map.get("weapon_mount_position", {}), grip_offset_pos
	)
	grip_offset_rot = _vector_from_data(
		hand_map.get("weapon_mount_rotation_deg", {}), grip_offset_rot
	)
	palm_pitch = float(hand_map.get("palm_pitch_deg", palm_pitch))
	palm_yaw = float(hand_map.get("palm_yaw_deg", palm_yaw))
	palm_roll = float(hand_map.get("palm_roll_deg", palm_roll))
	finger_curl = float(hand_map.get("finger_curl", finger_curl))
	thumb_wrap = float(hand_map.get("thumb_wrap", thumb_wrap))
	_sync_weapon_transform()
	_sync_markers()
	for value_pair in [
		["ik_x", left_grip_local_pos.x], ["ik_y", left_grip_local_pos.y],
		["ik_z", left_grip_local_pos.z], ["grip_x", grip_offset_pos.x],
		["grip_y", grip_offset_pos.y], ["grip_z", grip_offset_pos.z],
		["rot_pitch", grip_offset_rot.x], ["rot_yaw", grip_offset_rot.y],
		["rot_roll", grip_offset_rot.z], ["p_pitch", palm_pitch],
		["p_yaw", palm_yaw], ["p_roll", palm_roll],
		["f_curl", finger_curl], ["t_wrap", thumb_wrap],
	]:
		_update_slider_value(String(value_pair[0]), float(value_pair[1]))

func _vector_to_data(value: Vector3) -> Dictionary:
	return {"x": value.x, "y": value.y, "z": value.z}

func _vector_from_data(raw_value: Variant, fallback: Vector3) -> Vector3:
	if not (raw_value is Dictionary):
		return fallback
	var data := raw_value as Dictionary
	return Vector3(
		float(data.get("x", fallback.x)),
		float(data.get("y", fallback.y)),
		float(data.get("z", fallback.z))
	)

func _save_weapon_config() -> void:
	var config_dir := "res://config/weapons/"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(config_dir))

	var config_data: Dictionary = {
		"weapon_id": weapon_name.to_lower(),
		"display_name": weapon_name,
		"category": selected_category,
		"camo_skin": camo_skins[selected_camo_idx],
		"model_fbx": WEAPON_BASE_PATH + weapon_name + ".fbx" if (weapon_name != "ak-47" and weapon_name != "9mm_pistol") else ("res://assets/weapons/ps1_ak47/source/ak-47.fbx" if weapon_name == "ak-47" else "res://assets/weapons/9mm_pistol/source/model/model.dae"),
		"silencer_attachment": selected_silencer,
		"scope_attachment": selected_scope,
		"animation_hand_maps": animation_hand_maps.duplicate(true),
		"normalized_scale": auto_normalized_scale * user_scale_multiplier,
		"grip_offset": {
			"pos_x": (auto_grip_center_offset + grip_offset_pos).x,
			"pos_y": (auto_grip_center_offset + grip_offset_pos).y,
			"pos_z": (auto_grip_center_offset + grip_offset_pos).z,
			"rot_x": grip_offset_rot.x,
			"rot_y": grip_offset_rot.y,
			"rot_z": grip_offset_rot.z
		},
		"weapon_sockets": {
			"left_hand_ik_target": {
				"x": left_grip_local_pos.x,
				"y": left_grip_local_pos.y,
				"z": left_grip_local_pos.z
			},
			"muzzle_socket": {
				"x": muzzle_local_pos.x,
				"y": muzzle_local_pos.y,
				"z": muzzle_local_pos.z
			},
			"ejection_port": {
				"x": ejection_local_pos.x,
				"y": ejection_local_pos.y,
				"z": ejection_local_pos.z
			},
			"optic_rail": {
				"x": optic_local_pos.x,
				"y": optic_local_pos.y,
				"z": optic_local_pos.z
			}
		},
		"ballistics": {
			"fire_rate_rpm": fire_rate_rpm,
			"damage": damage_per_shot,
			"base_spread_deg": base_spread_deg,
			"bloom_per_shot_deg": bloom_per_shot_deg,
			"bloom_recovery_speed": bloom_recovery_speed,
			"is_silenced": is_silenced
		}
	}

	var file_path := config_dir + weapon_name.to_lower() + ".json"
	var file := FileAccess.open(file_path, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(config_data, "  "))
		file.close()

	_export_weapon_packed_scene(config_data)

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

		var sock_mz := Marker3D.new()
		sock_mz.name = "Socket_Muzzle"
		sock_mz.position = muzzle_local_pos
		root.add_child(sock_mz)
		sock_mz.owner = root

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
				hud_status.text = "📦 Asset Exported: %s & %s.json!" % [tscn_path, w_id]
			print("Successfully exported ready-to-use game asset to: ", tscn_path)
	root.queue_free()

# ─── UI ───────────────────────────────────────────────────────────────────────

func _build_studio_ui() -> void:
	overlay = Control.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(overlay)

	reticle_canvas = Control.new()
	reticle_canvas.set_anchors_preset(Control.PRESET_FULL_RECT)
	reticle_canvas.draw.connect(_draw_socom_reticle)
	overlay.add_child(reticle_canvas)

	# Left Sidebar
	var panel := PanelContainer.new()
	panel.position = Vector2(16, 16)
	panel.size = Vector2(460, 750)
	overlay.add_child(panel)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_child(scroll)

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

	# 3. Reload & Attachments
	vbox.add_child(HSeparator.new())
	var reload_btn := Button.new()
	reload_btn.text = "🔄 Test Reload Animation (R)"
	reload_btn.add_theme_color_override("font_color", Color(0.4, 0.9, 1.0))
	reload_btn.pressed.connect(_trigger_reload_animation)
	vbox.add_child(reload_btn)

	var animation_title := Label.new()
	animation_title.text = "All Imported Animations (%d)" % all_animation_entries.size()
	animation_title.tooltip_text = "Preview every imported operator clip while both hand/weapon gizmos remain active."
	animation_title.add_theme_color_override("font_color", Color(0.35, 0.9, 1.0))
	vbox.add_child(animation_title)
	var animation_row := HBoxContainer.new()
	vbox.add_child(animation_row)
	all_animation_select = OptionButton.new()
	all_animation_select.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in all_animation_entries:
		all_animation_select.add_item(String(entry.get("display", entry.get("key", "animation"))))
		all_animation_select.set_item_metadata(
			all_animation_select.item_count - 1,
			String(entry.get("key", ""))
		)
	animation_row.add_child(all_animation_select)
	var inspect_button := Button.new()
	inspect_button.text = "▶ Inspect"
	inspect_button.tooltip_text = "Play this animation and keep the hand and weapon gizmos live."
	inspect_button.pressed.connect(_preview_selected_catalog_animation)
	animation_row.add_child(inspect_button)
	var save_hand_map_button := Button.new()
	save_hand_map_button.text = "💾 Map Hands to This Animation"
	save_hand_map_button.tooltip_text = "Store the current trigger-hand weapon mount and support-hand grip for the selected clip. Ctrl/Cmd+S writes all maps into the weapon JSON."
	save_hand_map_button.pressed.connect(_save_selected_animation_hand_map)
	vbox.add_child(save_hand_map_button)

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

	_add_slider(vbox, "grip_x", "  Pos X", -0.25, 0.25, grip_offset_pos.x, func(v: float): grip_offset_pos.x = v; _sync_weapon_transform())
	_add_slider(vbox, "grip_y", "  Pos Y", -0.25, 0.25, grip_offset_pos.y, func(v: float): grip_offset_pos.y = v; _sync_weapon_transform())
	_add_slider(vbox, "grip_z", "  Pos Z", -0.25, 0.25, grip_offset_pos.z, func(v: float): grip_offset_pos.z = v; _sync_weapon_transform())
	_add_slider(vbox, "rot_pitch", "  Pitch", -180.0, 180.0, grip_offset_rot.x, func(v: float): grip_offset_rot.x = v; _sync_weapon_transform())
	_add_slider(vbox, "rot_yaw", "  Yaw", -180.0, 180.0, grip_offset_rot.y, func(v: float): grip_offset_rot.y = v; _sync_weapon_transform())
	_add_slider(vbox, "rot_roll", "  Roll", -180.0, 180.0, grip_offset_rot.z, func(v: float): grip_offset_rot.z = v; _sync_weapon_transform())
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
	_add_slider(vbox, "p_roll", "  Palm Roll (Underneath/Side)", -180.0, 180.0, palm_roll, func(v: float): palm_roll = v)
	_add_slider(vbox, "p_pitch", "  Palm Pitch (Wrist Tilt)", -90.0, 90.0, palm_pitch, func(v: float): palm_pitch = v)
	_add_slider(vbox, "p_yaw", "  Palm Yaw (Barrel Angle)", -90.0, 90.0, palm_yaw, func(v: float): palm_yaw = v)
	_add_slider(vbox, "f_curl", "  Fingers Wrap Tightness", 0.0, 1.0, finger_curl, func(v: float): finger_curl = v)
	_add_slider(vbox, "t_wrap", "  Thumb Over-Bore Wrap", 0.0, 1.0, thumb_wrap, func(v: float): thumb_wrap = v)

	# 6. WEAPON SOCKETS (Muzzle, Ejection, Optic)
	vbox.add_child(HSeparator.new())
	var sock_title := Label.new()
	sock_title.text = "6. Weapon Sockets (Muzzle, Ejection, Optic):"
	sock_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.8))
	vbox.add_child(sock_title)

	var mz_lbl := Label.new(); mz_lbl.text = "🔴 Muzzle Tip Socket (Pos XYZ on gun):"; vbox.add_child(mz_lbl)
	_add_slider(vbox, "mz_x", "  Muzzle X", -0.20, 1.60, muzzle_local_pos.x, func(v: float): muzzle_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "mz_y", "  Muzzle Y", -0.20, 0.20, muzzle_local_pos.y, func(v: float): muzzle_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "mz_z", "  Muzzle Z", -0.20, 0.20, muzzle_local_pos.z, func(v: float): muzzle_local_pos.z = v; _sync_markers())

	var ej_lbl := Label.new(); ej_lbl.text = "🟡 Shell Ejection Port (Pos XYZ on gun):"; vbox.add_child(ej_lbl)
	_add_slider(vbox, "ej_x", "  Ejection X", -0.20, 0.80, ejection_local_pos.x, func(v: float): ejection_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "ej_y", "  Ejection Y", -0.20, 0.20, ejection_local_pos.y, func(v: float): ejection_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "ej_z", "  Ejection Z", -0.20, 0.20, ejection_local_pos.z, func(v: float): ejection_local_pos.z = v; _sync_markers())

	var op_lbl := Label.new(); op_lbl.text = "🟢 Optic Scope Rail (Pos XYZ on gun):"; vbox.add_child(op_lbl)
	_add_slider(vbox, "op_x", "  Optic X", -0.20, 0.80, optic_local_pos.x, func(v: float): optic_local_pos.x = v; _sync_markers())
	_add_slider(vbox, "op_y", "  Optic Y", -0.20, 0.20, optic_local_pos.y, func(v: float): optic_local_pos.y = v; _sync_markers())
	_add_slider(vbox, "op_z", "  Optic Z", -0.20, 0.20, optic_local_pos.z, func(v: float): optic_local_pos.z = v; _sync_markers())

	# 7. Ballistics
	vbox.add_child(HSeparator.new())
	var bal_title := Label.new(); bal_title.text = "7. Ballistics Physics:"; vbox.add_child(bal_title)
	_add_slider(vbox, "rpm", "Fire Rate (RPM)", 200.0, 1200.0, float(fire_rate_rpm), func(v: float): fire_rate_rpm = int(v))
	_add_slider(vbox, "dmg", "Damage", 10.0, 100.0, float(damage_per_shot), func(v: float): damage_per_shot = int(v))
	_add_slider(vbox, "bloom", "Bloom Per Shot", 0.1, 5.0, bloom_per_shot_deg, func(v: float): bloom_per_shot_deg = v)
	_add_slider(vbox, "rec", "Bloom Recovery", 2.0, 30.0, bloom_recovery_speed, func(v: float): bloom_recovery_speed = v)

	# 8. Save & Export
	vbox.add_child(HSeparator.new())
	var save_btn := Button.new()
	save_btn.text = "📦 Export .tscn Asset & JSON Rig (Ctrl+S)"
	save_btn.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
	save_btn.pressed.connect(_save_weapon_config)
	vbox.add_child(save_btn)

	hud_status = Label.new()
	hud_status.text = "Ready! (Biomechanical Engine Active | Drag Blue Dot to place hand | Space to Fire)"
	hud_status.add_theme_font_size_override("font_size", 11)
	hud_status.add_theme_color_override("font_color", Color(0.4, 1.0, 0.4))
	vbox.add_child(hud_status)

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

	sliders_map[key] = {"slider": slider, "label": val_lbl}

func _draw_socom_reticle() -> void:
	if not is_instance_valid(target_board): return
	var center := get_viewport().get_visible_rect().size * 0.5
	if cam:
		center = cam.unproject_position(target_board.global_position + Vector3(0, 0.15, 0))

	var color := Color(0.85, 0.95, 0.15, 0.9)
	var ring_col := Color(0.85, 0.95, 0.15, 0.25)
	var r := reticle_bloom_radius

	reticle_canvas.draw_circle(center, 2.0, color)
	var tick_len := 8.0
	reticle_canvas.draw_line(center + Vector2(0, -r), center + Vector2(0, -r - tick_len), color, 1.5)
	reticle_canvas.draw_line(center + Vector2(0, r), center + Vector2(0, r + tick_len), color, 1.5)
	reticle_canvas.draw_line(center + Vector2(-r, 0), center + Vector2(-r - tick_len, 0), color, 1.5)
	reticle_canvas.draw_line(center + Vector2(r, 0), center + Vector2(r + tick_len, 0), color, 1.5)
	reticle_canvas.draw_arc(center, r, 0, TAU, 32, ring_col, 1.0)

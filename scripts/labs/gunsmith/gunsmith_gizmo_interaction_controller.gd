extends RefCounted

const HurtboxProfile := preload("res://scripts/combat/socom_hurtbox_profile.gd")
const HAND_GIZMO_ARROW_LENGTH := 0.12
const HAND_GIZMO_RING_RADIUS := 0.09
const WEAPON_GIZMO_ARROW_LENGTH := 0.10
const WEAPON_GIZMO_RING_RADIUS := 0.075
const GIZMO_CENTER_RADIUS := 0.018
const GIZMO_PICK_DISTANCE_PX := 28.0
const EYE_SIGHT_PICK_LENGTH_METERS := 0.5

static func _setup_unscaled_hand_gizmo(lab: Node) -> void:
	if lab.hand_gizmo_world and is_instance_valid(lab.hand_gizmo_world):
		lab.hand_gizmo_world.queue_free()
		lab.hand_gizmo_world = null

	lab.hand_gizmo_world = Node3D.new()
	lab.hand_gizmo_world.name = "HandGizmoWorld"
	lab.add_child(lab.hand_gizmo_world)

	# Large, unscaled controls stay readable even when the imported weapon is tiny.
	lab.hand_gizmo_center = lab._create_marker(Color(0.0, 0.95, 1.0), "left_ik", GIZMO_CENTER_RADIUS)
	lab.gizmo_arrow_x = lab._create_axis_arrow(Color(1.0, 0.25, 0.25), Vector3.RIGHT, "left_ik_arrow_x", HAND_GIZMO_ARROW_LENGTH)
	lab.gizmo_arrow_y = lab._create_axis_arrow(Color(0.25, 1.0, 0.25), Vector3.UP, "left_ik_arrow_y", HAND_GIZMO_ARROW_LENGTH)
	lab.gizmo_arrow_z = lab._create_axis_arrow(Color(0.35, 0.65, 1.0), Vector3.BACK, "left_ik_arrow_z", HAND_GIZMO_ARROW_LENGTH)
	lab.gizmo_ring_roll = lab._create_rotation_ring(Color(1.0, 0.9, 0.2), Vector3.RIGHT, HAND_GIZMO_RING_RADIUS, "left_ik_ring_roll")
	lab.gizmo_ring_pitch = lab._create_rotation_ring(Color(1.0, 0.3, 0.9), Vector3.BACK, HAND_GIZMO_RING_RADIUS, "left_ik_ring_pitch")
	lab.gizmo_ring_yaw = lab._create_rotation_ring(Color(0.2, 0.85, 1.0), Vector3.UP, HAND_GIZMO_RING_RADIUS, "left_ik_ring_yaw")

	lab.hand_gizmo_world.add_child(lab.hand_gizmo_center)
	lab.hand_gizmo_world.add_child(lab.gizmo_arrow_x)
	lab.hand_gizmo_world.add_child(lab.gizmo_arrow_y)
	lab.hand_gizmo_world.add_child(lab.gizmo_arrow_z)
	lab.hand_gizmo_world.add_child(lab.gizmo_ring_roll)
	lab.hand_gizmo_world.add_child(lab.gizmo_ring_pitch)
	lab.hand_gizmo_world.add_child(lab.gizmo_ring_yaw)

static func _setup_unscaled_weapon_gizmo(lab: Node) -> void:
	if lab.weapon_gizmo_world and is_instance_valid(lab.weapon_gizmo_world):
		lab.weapon_gizmo_world.queue_free()
		lab.weapon_gizmo_world = null

	lab.weapon_gizmo_world = Node3D.new()
	lab.weapon_gizmo_world.name = "WeaponMountGizmoWorld"
	lab.add_child(lab.weapon_gizmo_world)

	lab.weapon_gizmo_center = lab._create_selection_box(Color(1.0, 0.55, 0.08), "weapon_mount", GIZMO_CENTER_RADIUS * 1.15)
	lab.weapon_gizmo_arrow_x = lab._create_axis_arrow(Color(1.0, 0.25, 0.25), Vector3.RIGHT, "weapon_arrow_x", WEAPON_GIZMO_ARROW_LENGTH)
	lab.weapon_gizmo_arrow_y = lab._create_axis_arrow(Color(0.25, 1.0, 0.25), Vector3.UP, "weapon_arrow_y", WEAPON_GIZMO_ARROW_LENGTH)
	lab.weapon_gizmo_arrow_z = lab._create_axis_arrow(Color(0.35, 0.65, 1.0), Vector3.BACK, "weapon_arrow_z", WEAPON_GIZMO_ARROW_LENGTH)
	lab.weapon_gizmo_ring_roll = lab._create_rotation_ring(Color(1.0, 0.9, 0.2), Vector3.RIGHT, WEAPON_GIZMO_RING_RADIUS, "weapon_ring_roll")
	lab.weapon_gizmo_ring_pitch = lab._create_rotation_ring(Color(1.0, 0.3, 0.9), Vector3.BACK, WEAPON_GIZMO_RING_RADIUS, "weapon_ring_pitch")
	lab.weapon_gizmo_ring_yaw = lab._create_rotation_ring(Color(0.2, 0.85, 1.0), Vector3.UP, WEAPON_GIZMO_RING_RADIUS, "weapon_ring_yaw")

	lab.weapon_gizmo_world.add_child(lab.weapon_gizmo_center)
	lab.weapon_gizmo_world.add_child(lab.weapon_gizmo_arrow_x)
	lab.weapon_gizmo_world.add_child(lab.weapon_gizmo_arrow_y)
	lab.weapon_gizmo_world.add_child(lab.weapon_gizmo_arrow_z)
	lab.weapon_gizmo_world.add_child(lab.weapon_gizmo_ring_roll)
	lab.weapon_gizmo_world.add_child(lab.weapon_gizmo_ring_pitch)
	lab.weapon_gizmo_world.add_child(lab.weapon_gizmo_ring_yaw)

static func _set_active_gizmo(lab: Node,gizmo_id: String) -> void:
	lab.active_gizmo_id = gizmo_id
	var show_hand: bool = lab.active_gizmo_id == "hand"
	var hand_arrows: Array[Node3D] = [lab.gizmo_arrow_x, lab.gizmo_arrow_y, lab.gizmo_arrow_z]
	var weapon_arrows: Array[Node3D] = [lab.weapon_gizmo_arrow_x, lab.weapon_gizmo_arrow_y, lab.weapon_gizmo_arrow_z]
	var world_rings: Array[Node3D] = [lab.gizmo_ring_roll, lab.gizmo_ring_pitch, lab.gizmo_ring_yaw, lab.weapon_gizmo_ring_roll, lab.weapon_gizmo_ring_pitch, lab.weapon_gizmo_ring_yaw]
	for control in hand_arrows:
		if control and is_instance_valid(control): control.visible = false
	for control in weapon_arrows:
		if control and is_instance_valid(control): control.visible = false
	for ring in world_rings:
		if ring and is_instance_valid(ring): ring.visible = false
	# The support-hand point stays uncluttered. Keep one compact orange box on the
	# rifle so the weapon itself can always be selected and freely repositioned.
	if lab.hand_gizmo_center: lab.hand_gizmo_center.visible = false
	if lab.weapon_gizmo_center: lab.weapon_gizmo_center.visible = true
	lab._refresh_rotation_dials()
	if lab.hud_status:
		lab.hud_status.text = "🔵 Support-hand controls active" if show_hand else "🟠 Weapon-mount controls active"

static func _register_interactive_dots(lab: Node) -> void:
	lab.interactive_dots.clear()
	for joint_name: StringName in lab.body_joint_markers:
		lab.interactive_dots.append({
			"id": "body_joint:%s" % String(joint_name),
			"mesh": lab.body_joint_markers[joint_name],
			"label": "🔷 %s procedural joint" % String(joint_name).replace("_", " ").capitalize(),
			"color": Color(0.15, 0.85, 1.0),
		})
	for region_key: StringName in lab.hurtbox_edit_markers:
		lab.interactive_dots.append({
			"id": "hurtbox:%s" % String(region_key),
			"mesh": lab.hurtbox_edit_markers[region_key],
			"label": "🟠 %s hitbox" % HurtboxProfile.region_label(region_key),
			"color": Color(1.0, 0.52, 0.12),
		})
	if lab.right_elbow_pole_marker:
		lab.interactive_dots.append({"id": "right_elbow_pole", "mesh": lab.right_elbow_pole_marker, "label": "🟣 Right Elbow IK Pole", "color": Color(1.0, 0.25, 0.9)})
	if lab.left_elbow_pole_marker:
		lab.interactive_dots.append({"id": "left_elbow_pole", "mesh": lab.left_elbow_pole_marker, "label": "🟣 Left Elbow IK Pole", "color": Color(0.75, 0.35, 1.0)})
	if lab.hand_gizmo_center:
		lab.interactive_dots.append({"id": "left_ik", "mesh": lab.hand_gizmo_center, "label": "🔵 Hand Rig (Free 3D Translate)", "color": Color(0.0, 0.95, 1.0)})
	if lab.gizmo_arrow_x and lab.gizmo_arrow_x.get_child_count() > 1:
		lab.interactive_dots.append({"id": "left_ik_arrow_x", "mesh": lab.gizmo_arrow_x.get_child(1), "label": "🔴 Drag Along Barrel (X)", "color": Color(1.0, 0.25, 0.25)})
	if lab.gizmo_arrow_y and lab.gizmo_arrow_y.get_child_count() > 1:
		lab.interactive_dots.append({"id": "left_ik_arrow_y", "mesh": lab.gizmo_arrow_y.get_child(1), "label": "🟢 Drag Height (Y)", "color": Color(0.25, 1.0, 0.25)})
	if lab.gizmo_arrow_z and lab.gizmo_arrow_z.get_child_count() > 1:
		lab.interactive_dots.append({"id": "left_ik_arrow_z", "mesh": lab.gizmo_arrow_z.get_child(1), "label": "🔵 Drag Side (Z)", "color": Color(0.35, 0.65, 1.0)})
	if lab.gizmo_ring_roll:
		lab.interactive_dots.append({"id": "left_ik_ring_roll", "mesh": lab.gizmo_ring_roll, "label": "🟡 Spin Palm Around Gun (Roll)", "color": Color(1.0, 0.9, 0.2)})
	if lab.gizmo_ring_pitch:
		lab.interactive_dots.append({"id": "left_ik_ring_pitch", "mesh": lab.gizmo_ring_pitch, "label": "🟣 Tilt Wrist Pitch", "color": Color(1.0, 0.3, 0.9)})
	if lab.gizmo_ring_yaw:
		lab.interactive_dots.append({"id": "left_ik_ring_yaw", "mesh": lab.gizmo_ring_yaw, "label": "🔷 Turn Wrist Yaw", "color": Color(0.2, 0.85, 1.0)})

	if lab.weapon_gizmo_center:
		lab.interactive_dots.append({"id": "weapon_mount", "mesh": lab.weapon_gizmo_center, "label": "🟠 Grab and Move Weapon", "color": Color(1.0, 0.55, 0.08)})
	if lab.weapon_gizmo_arrow_x and lab.weapon_gizmo_arrow_x.get_child_count() > 1:
		lab.interactive_dots.append({"id": "weapon_arrow_x", "mesh": lab.weapon_gizmo_arrow_x.get_child(1), "label": "🔴 Move Weapon X", "color": Color(1.0, 0.25, 0.25)})
	if lab.weapon_gizmo_arrow_y and lab.weapon_gizmo_arrow_y.get_child_count() > 1:
		lab.interactive_dots.append({"id": "weapon_arrow_y", "mesh": lab.weapon_gizmo_arrow_y.get_child(1), "label": "🟢 Move Weapon Y", "color": Color(0.25, 1.0, 0.25)})
	if lab.weapon_gizmo_arrow_z and lab.weapon_gizmo_arrow_z.get_child_count() > 1:
		lab.interactive_dots.append({"id": "weapon_arrow_z", "mesh": lab.weapon_gizmo_arrow_z.get_child(1), "label": "🔵 Move Weapon Z", "color": Color(0.35, 0.65, 1.0)})
	if lab.weapon_gizmo_ring_roll:
		lab.interactive_dots.append({"id": "weapon_ring_roll", "mesh": lab.weapon_gizmo_ring_roll, "label": "🟡 Rotate Weapon Roll", "color": Color(1.0, 0.9, 0.2)})
	if lab.weapon_gizmo_ring_pitch:
		lab.interactive_dots.append({"id": "weapon_ring_pitch", "mesh": lab.weapon_gizmo_ring_pitch, "label": "🟣 Rotate Weapon Pitch", "color": Color(1.0, 0.3, 0.9)})
	if lab.weapon_gizmo_ring_yaw:
		lab.interactive_dots.append({"id": "weapon_ring_yaw", "mesh": lab.weapon_gizmo_ring_yaw, "label": "🔷 Rotate Weapon Yaw", "color": Color(0.2, 0.85, 1.0)})

	if lab.muzzle_marker: lab.interactive_dots.append({"id": "muzzle", "mesh": lab.muzzle_marker, "label": "🔴 Muzzle Tip Socket", "color": Color(1.0, 0.2, 0.2)})
	if lab.barrel_base_marker: lab.interactive_dots.append({"id": "barrel_base", "mesh": lab.barrel_base_marker, "label": "🔴 Barrel Base Socket", "color": Color(1.0, 0.4, 0.4)})
	if lab.ejection_marker: lab.interactive_dots.append({"id": "ejection", "mesh": lab.ejection_marker, "label": "🟡 Shell Ejection Port", "color": Color(1.0, 0.85, 0.1)})
	if lab.optic_marker: lab.interactive_dots.append({"id": "optic", "mesh": lab.optic_marker, "label": "🟢 Optic Scope Rail", "color": Color(0.2, 1.0, 0.4)})
	if lab.right_grip_marker: lab.interactive_dots.append({"id": "right_grip", "mesh": lab.right_grip_marker, "label": "🟠 Trigger-Hand Grip (moves gun in right hand)", "color": Color(1.0, 0.55, 0.08)})
	if lab.eye_sight_dot: lab.interactive_dots.append({"id": "eye_sight", "mesh": lab.eye_sight_dot, "label": "🔵 Gun Placement Origin — drag X/Y, Shift or wheel Z", "color": Color(0.25, 0.55, 1.0)})
	# The pale-blue direction dot is a reticle-lock indicator, not a draggable
	# authoring target. Only the dark-blue origin remains interactive.

static func _find_dot_under_mouse(lab: Node,screen_pos: Vector2) -> String:
	if not lab.cam: return ""
	var closest_id := ""
	var closest_dist := GIZMO_PICK_DISTANCE_PX
	# Weapon sockets are precise authoring points. Give them priority over the
	# larger body-joint pick radius so the red muzzle dot can never select a bone.
	for socket_pick in [
		["muzzle", lab.muzzle_marker],
		["barrel_base", lab.barrel_base_marker],
		["ejection", lab.ejection_marker],
		["optic", lab.optic_marker],
	]:
		var socket_mesh := socket_pick[1] as MeshInstance3D
		if socket_mesh != null and socket_mesh.is_visible_in_tree() and not lab.cam.is_position_behind(socket_mesh.global_position):
			if screen_pos.distance_to(lab.cam.unproject_position(socket_mesh.global_position)) <= 18.0:
				return String(socket_pick[0])
	# The pale-blue dot communicates the automatic reticle lock. Do not let the
	# nearby draggable line segment reinterpret it as an origin edit.
	if (
		lab.eye_sight_direction_dot != null
		and lab.eye_sight_direction_dot.is_visible_in_tree()
		and not lab.cam.is_position_behind(lab.eye_sight_direction_dot.global_position)
		and screen_pos.distance_to(
			lab.cam.unproject_position(lab.eye_sight_direction_dot.global_position)
		) <= 18.0
	):
		return ""
	# The origin is a small dot, so make the visible blue segment a direct X/Y/Z
	# authoring handle too. Keep this after weapon sockets so a placement line
	# crossing the rifle can never steal a muzzle or optic selection.
	if lab.eye_sight_marker != null and lab.eye_sight_marker.is_visible_in_tree():
		var eye_origin: Vector3 = lab.eye_sight_marker.global_position
		# Keep the pick segment close to the face. The sight direction can point
		# toward the editor camera, so a long endpoint can cross behind the camera
		# and make the otherwise-visible blue handle impossible to select.
		var eye_pick_end: Vector3 = (
			eye_origin
			+ lab._eye_sight_direction_world() * EYE_SIGHT_PICK_LENGTH_METERS
		)
		if not lab.cam.is_position_behind(eye_origin) and not lab.cam.is_position_behind(eye_pick_end):
			var eye_line_distance: float = lab._screen_point_segment_distance(
				screen_pos,
				lab.cam.unproject_position(eye_origin),
				lab.cam.unproject_position(eye_pick_end)
			)
			if eye_line_distance <= 14.0:
				return "eye_sight"

	# Select the real support-hand area instead of requiring a visible sphere.
	if lab.left_grip_marker and not lab.cam.is_position_behind(lab.left_grip_marker.global_position):
		var hand_screen: Vector2 = lab.cam.unproject_position(lab.left_grip_marker.global_position)
		var hand_dist := screen_pos.distance_to(hand_screen)
		if hand_dist < closest_dist:
			closest_dist = hand_dist
			closest_id = "left_ik"

	for item in lab.interactive_dots:
		var id: String = item["id"]
		var mi: MeshInstance3D = item["mesh"]
		if not mi or not is_instance_valid(mi) or not mi.is_visible_in_tree(): continue

		var pick_dist := INF
		var is_hand_control := id.begins_with("left_ik_")
		var is_weapon_control := id.begins_with("weapon_")
		var control_root: Node3D = lab.hand_gizmo_world if is_hand_control else lab.weapon_gizmo_world
		var ring_radius := HAND_GIZMO_RING_RADIUS if is_hand_control else WEAPON_GIZMO_RING_RADIUS
		var arrow_length := HAND_GIZMO_ARROW_LENGTH if is_hand_control else WEAPON_GIZMO_ARROW_LENGTH

		if (is_hand_control or is_weapon_control) and id.contains("ring_") and control_root:
			var ring_axis := id.get_slice("ring_", 1)
			pick_dist = lab._ring_pick_distance(screen_pos, control_root.global_position, control_root.global_basis, ring_axis, ring_radius)
		elif (is_hand_control or is_weapon_control) and id.contains("arrow_") and control_root:
			var arrow_axis := id.get_slice("arrow_", 1)
			var direction := control_root.global_basis.x
			if arrow_axis == "y": direction = control_root.global_basis.y
			elif arrow_axis == "z": direction = -control_root.global_basis.z
			var tip := control_root.global_position + direction.normalized() * (arrow_length + 0.025)
			if not lab.cam.is_position_behind(tip):
				pick_dist = screen_pos.distance_to(lab.cam.unproject_position(tip))
		elif not lab.cam.is_position_behind(mi.global_position):
			pick_dist = screen_pos.distance_to(lab.cam.unproject_position(mi.global_position))

		if pick_dist < closest_dist:
			closest_dist = pick_dist
			closest_id = id
	return closest_id

static func _screen_point_segment_distance(lab: Node,point: Vector2, segment_start: Vector2, segment_end: Vector2) -> float:
	var segment := segment_end - segment_start
	var length_squared := segment.length_squared()
	if length_squared <= 0.001:
		return point.distance_to(segment_start)
	var amount := clampf((point - segment_start).dot(segment) / length_squared, 0.0, 1.0)
	return point.distance_to(segment_start + segment * amount)

static func _ring_pick_distance(lab: Node,screen_pos: Vector2, center: Vector3, basis: Basis, axis_name: String, radius: float) -> float:
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
		if not lab.cam.is_position_behind(ring_pt):
			best = minf(best, screen_pos.distance_to(lab.cam.unproject_position(ring_pt)))
	return best

static func _get_dot_mesh_by_id(lab: Node,dot_id: String) -> MeshInstance3D:
	for item in lab.interactive_dots:
		if item["id"] == dot_id: return item["mesh"]
	return null

static func _highlight_dot(lab: Node,dot_id: String) -> void:
	for item in lab.interactive_dots:
		var mi: MeshInstance3D = item["mesh"]
		if mi and is_instance_valid(mi):
			var is_target: bool = (item["id"] == dot_id)
			var hover_scale := 1.55 if String(item["id"]).contains("ring_") else 1.70
			mi.scale = Vector3.ONE * (hover_scale if is_target else 1.0)
			var mat = mi.material_override as StandardMaterial3D
			if mat:
				mat.albedo_color = Color.WHITE if is_target else (item["color"] as Color)

static func _apply_dot_world_drag(lab: Node,dot_id: String, world_pos: Vector3) -> void:
	if dot_id.begins_with("hurtbox:"):
		var region_key := StringName(dot_id.trim_prefix("hurtbox:"))
		var area: Area3D = lab._hurtbox_region_area(region_key)
		if area != null:
			var world_delta: Vector3 = world_pos - lab.drag_initial_world
			var local_delta: Vector3 = area.global_basis.orthonormalized().inverse() * world_delta
			lab._set_hitbox_offset(region_key, lab.hitbox_drag_offset_start + local_delta)
			lab._apply_shared_hurtbox_preview()
			lab._sync_selected_hurtbox_controls()
		return
	match dot_id:
		"right_elbow_pole":
			lab._set_elbow_pole_from_world(&"right", world_pos)
		"left_elbow_pole":
			lab._set_elbow_pole_from_world(&"left", world_pos)
		"weapon_mount":
			if lab._editing_action_weapon_frame():
				var grip_world: Transform3D = lab._right_hand_grip_world_transform()
				var world_delta: Vector3 = world_pos - lab.drag_initial_world
				lab.animation_frame_weapon_position_correction = (
					lab.frame_weapon_drag_position_start
					+ grip_world.basis.inverse() * world_delta
				)
				lab.animation_frame_weapon_position_correction.x = clampf(lab.animation_frame_weapon_position_correction.x, -0.25, 0.25)
				lab.animation_frame_weapon_position_correction.y = clampf(lab.animation_frame_weapon_position_correction.y, -0.25, 0.25)
				lab.animation_frame_weapon_position_correction.z = clampf(lab.animation_frame_weapon_position_correction.z, -0.25, 0.25)
			elif lab.weapon_pivot:
				var parent_node: Node3D = lab.weapon_pivot.get_parent_node_3d()
				var local_pos: Vector3 = parent_node.global_transform.affine_inverse() * world_pos if parent_node else world_pos
				lab.grip_offset_pos = local_pos - lab.auto_grip_center_offset
				lab._sync_weapon_transform(false)
				lab._update_slider_value("grip_x", lab.grip_offset_pos.x)
				lab._update_slider_value("grip_y", lab.grip_offset_pos.y)
				lab._update_slider_value("grip_z", lab.grip_offset_pos.z)
		"left_ik":
			if lab.socket_root:
				lab.left_grip_local_pos = lab.socket_root.to_local(world_pos)
				lab._sync_hand_markers()
				lab._update_slider_value("ik_x", lab.left_grip_local_pos.x)
				lab._update_slider_value("ik_y", lab.left_grip_local_pos.y)
				lab._update_slider_value("ik_z", lab.left_grip_local_pos.z)
		"muzzle":
			if lab.socket_root:
				lab.muzzle_local_pos = lab.socket_root.to_local(world_pos)
				lab._sync_ballistic_markers()
				lab._update_slider_value("mz_x", lab.muzzle_local_pos.x)
				lab._update_slider_value("mz_y", lab.muzzle_local_pos.y)
				lab._update_slider_value("mz_z", lab.muzzle_local_pos.z)
		"barrel_base":
			if lab.socket_root:
				lab.barrel_base_local_pos = lab.socket_root.to_local(world_pos)
				lab._sync_ballistic_markers()
				lab._update_slider_value("bb_x", lab.barrel_base_local_pos.x)
				lab._update_slider_value("bb_y", lab.barrel_base_local_pos.y)
				lab._update_slider_value("bb_z", lab.barrel_base_local_pos.z)
		"ejection":
			if lab.socket_root:
				lab.ejection_local_pos = lab.socket_root.to_local(world_pos)
				lab._sync_markers()
				lab._update_slider_value("ej_x", lab.ejection_local_pos.x)
				lab._update_slider_value("ej_y", lab.ejection_local_pos.y)
				lab._update_slider_value("ej_z", lab.ejection_local_pos.z)
		"optic":
			if lab.socket_root:
				lab.optic_local_pos = lab.socket_root.to_local(world_pos)
				lab._sync_markers()
				lab._update_slider_value("op_x", lab.optic_local_pos.x)
				lab._update_slider_value("op_y", lab.optic_local_pos.y)
				lab._update_slider_value("op_z", lab.optic_local_pos.z)
		"right_grip":
			if lab.socket_root:
				lab.right_grip_local_pos = lab.socket_root.to_local(world_pos)
				lab._sync_hand_markers()
				lab._update_slider_value("rh_x", lab.right_grip_local_pos.x)
				lab._update_slider_value("rh_y", lab.right_grip_local_pos.y)
				lab._update_slider_value("rh_z", lab.right_grip_local_pos.z)


static func _pointer_over_editor_ui(lab: Node,screen_position: Vector2) -> bool:
	for control in [lab.sidebar_panel, lab.animation_frame_panel, lab.rotation_panel]:
		if (
			control != null
			and (control as Control).visible
			and (control as Control).get_global_rect().has_point(screen_position)
		):
			return true
	return false


static func _cancel_3d_authoring_pointer(lab: Node) -> void:
	lab.mouse_fire_armed = false
	lab.authoring_pointer_down = false
	lab.dragged_dot_id = ""
	lab.hovered_dot_id = ""
	lab._highlight_dot("")

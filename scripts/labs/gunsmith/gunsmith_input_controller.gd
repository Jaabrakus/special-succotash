class_name GunsmithInputController
extends RefCounted

## Routes Gunsmith authoring input to existing commands. It owns no weapon,
## animation, camera, or profile state.

static func handle(lab, event: InputEvent) -> void:
	if event is InputEventKey and event.pressed:
		var ek := event as InputEventKey
		if ek.keycode == KEY_S and (ek.ctrl_pressed or ek.meta_pressed):
			lab._request_save_everything()
			lab.get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_R and not (ek.ctrl_pressed or ek.meta_pressed):
			lab._trigger_reload_animation()
			lab.get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_1:
			lab._set_preview_posture(&"STANDING")
			lab.get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_2:
			lab._set_preview_posture(&"CROUCHED")
			lab.get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_3:
			lab._set_preview_posture(&"PRONE")
			lab.get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_B:
			lab.show_joint_bubbles = not lab.show_joint_bubbles
			lab._update_body_joint_visuals()
			if lab.hud_status:
				lab.hud_status.text = "👁 Joint Bubbles: %s" % ("VISIBLE" if lab.show_joint_bubbles else "HIDDEN")
			lab.get_viewport().set_input_as_handled()
			return
		elif ek.keycode == KEY_I:
			lab.isolate_selected_node = not lab.isolate_selected_node
			lab._update_body_joint_visuals()
			if lab.hud_status:
				lab.hud_status.text = "🎯 Isolate Active Node: %s" % ("ON (Showing %s only)" % String(lab.selected_body_joint) if lab.isolate_selected_node else "OFF")
			lab.get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if (
			mb.button_index == MOUSE_BUTTON_LEFT
			and mb.pressed
			and lab.save_rig_button != null
			and not lab.save_rig_button.disabled
			and lab.save_rig_button.get_global_rect().has_point(mb.position)
		):
			lab._cancel_3d_authoring_pointer()
			lab._request_save_everything()
			lab.get_viewport().set_input_as_handled()
			return
		if lab._pointer_over_editor_ui(mb.position):
			if mb.button_index == MOUSE_BUTTON_LEFT and not mb.pressed:
				lab._cancel_3d_authoring_pointer()
			return
		var target_dot: String = lab.dragged_dot_id if lab.dragged_dot_id != "" else lab.hovered_dot_id

		if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			if target_dot.begins_with("body_joint:"):
				lab._select_body_joint(StringName(target_dot.trim_prefix("body_joint:")))
				lab._adjust_selected_joint_rotation(Vector3(0.0, 0.0, 2.0))
				lab.get_viewport().set_input_as_handled()
				return
			elif target_dot == "left_ik":
				lab.left_grip_local_pos.x = clampf(lab.left_grip_local_pos.x + 0.015, -0.40, 1.20)
				lab._sync_markers()
				lab._update_slider_value("ik_x", lab.left_grip_local_pos.x)
				lab.get_viewport().set_input_as_handled()
				return
			elif target_dot == "right_grip":
				lab._adjust_weapon_rotation("yaw", 3.0)
				lab.get_viewport().set_input_as_handled()
				return
			elif target_dot == "eye_sight":
				var line_offset: Vector3 = lab._eye_sight_origin_offset()
				lab._set_eye_sight_origin_component(line_offset.z + 0.015, &"z")
				lab._sync_eye_sight_controls()
				lab.get_viewport().set_input_as_handled()
				return
			else:
				lab.cam_distance = clampf(lab.cam_distance - 0.08, 0.20, 3.5)
				lab._update_camera()
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if target_dot.begins_with("body_joint:"):
				lab._select_body_joint(StringName(target_dot.trim_prefix("body_joint:")))
				lab._adjust_selected_joint_rotation(Vector3(0.0, 0.0, -2.0))
				lab.get_viewport().set_input_as_handled()
				return
			elif target_dot == "left_ik":
				lab.left_grip_local_pos.x = clampf(lab.left_grip_local_pos.x - 0.015, -0.40, 1.20)
				lab._sync_markers()
				lab._update_slider_value("ik_x", lab.left_grip_local_pos.x)
				lab.get_viewport().set_input_as_handled()
				return
			elif target_dot == "right_grip":
				lab._adjust_weapon_rotation("yaw", -3.0)
				lab.get_viewport().set_input_as_handled()
				return
			elif target_dot == "eye_sight":
				var line_offset: Vector3 = lab._eye_sight_origin_offset()
				lab._set_eye_sight_origin_component(line_offset.z - 0.015, &"z")
				lab._sync_eye_sight_controls()
				lab.get_viewport().set_input_as_handled()
				return
			else:
				lab.cam_distance = clampf(lab.cam_distance + 0.08, 0.20, 3.5)
				lab._update_camera()
		elif mb.button_index == MOUSE_BUTTON_RIGHT:
			lab.is_orbiting = mb.pressed
			lab.last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			lab.is_panning = mb.pressed
			lab.last_mouse_pos = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# A mouse shot must start on empty range space. Never derive fire from
				# the global button state because Godot can sample that state before a
				# socket drag has claimed the press.
				lab.mouse_fire_armed = false
				var hit_dot: String = lab._find_dot_under_mouse(mb.position)
				if hit_dot != "":
					if hit_dot == "eye_sight_direction":
						if lab.hud_status:
							lab.hud_status.text = "🔹 Blue aim is locked to the active reticle. Move the dark-blue origin to place the gun."
						lab.get_viewport().set_input_as_handled()
						return
					lab.authoring_pointer_down = true
					lab.fire_input_held = false
					lab._pause_animation_frame_editor_for_authoring()
					if hit_dot.begins_with("body_joint:"):
						lab._select_body_joint(StringName(hit_dot.trim_prefix("body_joint:")))
					elif hit_dot.begins_with("hurtbox:"):
						lab._select_hurtbox_region(StringName(hit_dot.trim_prefix("hurtbox:")))
						lab.hitbox_drag_offset_start = lab._hitbox_offset(lab.selected_hurtbox_region)
					elif hit_dot == "left_ik":
						lab._set_active_gizmo("hand")
					elif hit_dot == "right_grip" or hit_dot == "weapon_mount":
						lab._set_active_gizmo("weapon")
						if hit_dot == "weapon_mount" and lab._editing_action_weapon_frame():
							lab.frame_weapon_drag_position_start = lab.animation_frame_weapon_position_correction
					lab.dragged_dot_id = hit_dot
					var dot_mesh := lab._get_dot_mesh_by_id(hit_dot) as MeshInstance3D
					if dot_mesh:
						lab.drag_initial_world = dot_mesh.global_position
						var cam_norm: Vector3 = -lab.cam.global_transform.basis.z.normalized()
						lab.drag_plane = Plane(cam_norm, cam_norm.dot(lab.drag_initial_world))
						var ray_orig: Vector3 = lab.cam.project_ray_origin(mb.position)
						var ray_dir: Vector3 = lab.cam.project_ray_normal(mb.position)
						var hit_pos: Variant = lab.drag_plane.intersects_ray(ray_orig, ray_dir)
						if hit_pos != null:
							lab.drag_offset_vector = lab.drag_initial_world - hit_pos
						else:
							lab.drag_offset_vector = Vector3.ZERO
						if lab.hud_status:
							if hit_dot == "eye_sight":
								lab.hud_status.text = "🔵 Move origin X/Y • Shift-drag or wheel = Z"
							elif hit_dot == "eye_sight_direction":
								lab.hud_status.text = "🔹 Aim direction • horizontal = yaw • vertical = pitch"
							else:
								lab.hud_status.text = "🎯 Positioning %s (Left arm biomechanically auto-grips!)" % hit_dot
					lab.get_viewport().set_input_as_handled()
					return
				lab.mouse_fire_armed = (
					lab.active_lab_tab_name == "Reticle & Fire"
					and not lab.animation_frame_editor.active
					and lab._preview_screen_rect().has_point(mb.position)
				)
			else:
				lab.mouse_fire_armed = false
				lab.authoring_pointer_down = false
				if lab.dragged_dot_id != "":
					if lab.hud_status:
						lab.hud_status.text = "✅ %s locked!" % lab.dragged_dot_id
					lab.dragged_dot_id = ""
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if lab._pointer_over_editor_ui(mm.position) and lab.dragged_dot_id == "":
			if lab.hovered_dot_id != "":
				lab.hovered_dot_id = ""
				lab._highlight_dot("")
			return
		if lab.is_orbiting:
			lab.cam_yaw -= mm.relative.x * 0.4
			lab.cam_pitch = clampf(lab.cam_pitch - mm.relative.y * 0.4, -85.0, 85.0)
			lab._update_camera()
		elif lab.is_panning:
			var right: Vector3 = lab.cam.global_transform.basis.x
			var up: Vector3 = lab.cam.global_transform.basis.y
			lab.cam_target -= (right * mm.relative.x - up * mm.relative.y) * 0.002
			lab._update_camera()
		elif lab.dragged_dot_id != "":
			if lab.dragged_dot_id.begins_with("body_joint:"):
				lab._adjust_selected_joint_rotation(Vector3(-mm.relative.y * 0.25, mm.relative.x * 0.25, 0.0))
			elif lab.dragged_dot_id == "eye_sight":
				var line_offset: Vector3 = lab._eye_sight_origin_offset()
				if mm.shift_pressed:
					line_offset.z -= mm.relative.y * 0.003
				else:
					line_offset.x += mm.relative.x * 0.0025
					line_offset.y -= mm.relative.y * 0.0025
				lab.runtime_posture_layer.set_eye_sight_origin_offset_meters(
					lab.preview_posture,
					line_offset
				)
				lab._sync_eye_sight_controls()
				lab._update_eye_sight_marker()
				if lab.hud_status:
					line_offset = lab._eye_sight_origin_offset()
					lab.hud_status.text = "🔵 Line X %.3f • Y %.3f • Z %.3f" % [
						line_offset.x,
						line_offset.y,
						line_offset.z,
					]
			elif lab.dragged_dot_id == "left_ik_ring_roll":
				lab.palm_roll = wrapf(lab.palm_roll + mm.relative.x * 0.85, -180.0, 180.0)
				lab._update_slider_value("p_roll", lab.palm_roll)
				if lab.hud_status: lab.hud_status.text = "🟡 Spinning Palm Roll: %.1f° (Underneath / C-Clamp)" % lab.palm_roll
			elif lab.dragged_dot_id == "left_ik_ring_pitch":
				lab.palm_pitch = clampf(lab.palm_pitch - mm.relative.y * 0.65, -90.0, 90.0)
				lab._update_slider_value("p_pitch", lab.palm_pitch)
				if lab.hud_status: lab.hud_status.text = "🟣 Tilting Wrist Pitch: %.1f°" % lab.palm_pitch
			elif lab.dragged_dot_id == "left_ik_ring_yaw":
				lab.palm_yaw = clampf(lab.palm_yaw + mm.relative.x * 0.75, -90.0, 90.0)
				lab._update_slider_value("p_yaw", lab.palm_yaw)
				if lab.hud_status: lab.hud_status.text = "🔷 Turning Palm Yaw: %.1f°" % lab.palm_yaw
			elif lab.dragged_dot_id == "left_ik_arrow_x":
				lab.left_grip_local_pos.x = clampf(lab.left_grip_local_pos.x + mm.relative.x * 0.003, -0.40, 1.20)
				lab._sync_markers()
				lab._update_slider_value("ik_x", lab.left_grip_local_pos.x)
				if lab.hud_status: lab.hud_status.text = "🔴 Sliding Foregrip along Barrel (X): %.3f" % lab.left_grip_local_pos.x
			elif lab.dragged_dot_id == "left_ik_arrow_y":
				lab.left_grip_local_pos.y = clampf(lab.left_grip_local_pos.y - mm.relative.y * 0.003, -0.20, 0.20)
				lab._sync_markers()
				lab._update_slider_value("ik_y", lab.left_grip_local_pos.y)
				if lab.hud_status: lab.hud_status.text = "🟢 Adjusting Hand Height (Y): %.3f" % lab.left_grip_local_pos.y
			elif lab.dragged_dot_id == "left_ik_arrow_z":
				lab.left_grip_local_pos.z = clampf(lab.left_grip_local_pos.z + mm.relative.x * 0.003, -0.20, 0.20)
				lab._sync_markers()
				lab._update_slider_value("ik_z", lab.left_grip_local_pos.z)
				if lab.hud_status: lab.hud_status.text = "🔵 Adjusting Hand Side (Z): %.3f" % lab.left_grip_local_pos.z
			elif lab.dragged_dot_id == "weapon_ring_pitch":
				var pitch_value: float = lab._adjust_weapon_rotation("pitch", -mm.relative.y * 0.65)
				if lab.hud_status: lab.hud_status.text = "🟣 %s Pitch: %.1f°" % ["Frame Weapon" if lab._editing_action_weapon_frame() else "Weapon", pitch_value]
			elif lab.dragged_dot_id == "weapon_ring_yaw":
				var yaw_value: float = lab._adjust_weapon_rotation("yaw", mm.relative.x * 0.75)
				if lab.hud_status: lab.hud_status.text = "🔷 %s Yaw: %.1f°" % ["Frame Weapon" if lab._editing_action_weapon_frame() else "Weapon", yaw_value]
			elif lab.dragged_dot_id == "weapon_ring_roll":
				var roll_value: float = lab._adjust_weapon_rotation("roll", mm.relative.x * 0.85)
				if lab.hud_status: lab.hud_status.text = "🟡 %s Roll: %.1f°" % ["Frame Weapon" if lab._editing_action_weapon_frame() else "Weapon", roll_value]
			elif lab.dragged_dot_id == "weapon_arrow_x":
				lab._adjust_weapon_translation("x", mm.relative.x * 0.0025)
			elif lab.dragged_dot_id == "weapon_arrow_y":
				lab._adjust_weapon_translation("y", -mm.relative.y * 0.0025)
			elif lab.dragged_dot_id == "weapon_arrow_z":
				lab._adjust_weapon_translation("z", mm.relative.x * 0.0025)
			else:
				var ray_orig: Vector3 = lab.cam.project_ray_origin(mm.position)
				var ray_dir: Vector3 = lab.cam.project_ray_normal(mm.position)
				var hit_pos: Variant = lab.drag_plane.intersects_ray(ray_orig, ray_dir)
				if hit_pos != null:
					var new_world_pos: Vector3 = hit_pos + lab.drag_offset_vector
					lab._apply_dot_world_drag(lab.dragged_dot_id, new_world_pos)
		else:
			var hovered: String = lab._find_dot_under_mouse(mm.position)
			if hovered != lab.hovered_dot_id:
				lab.hovered_dot_id = hovered
				lab._highlight_dot(lab.hovered_dot_id)


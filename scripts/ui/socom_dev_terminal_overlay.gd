class_name SocomDevTerminalOverlay
extends CanvasLayer

## Live Tactical Developer Terminal & Input Stream Overlay.
## Displays real-time button presses and active subsystem/code events.
## Toggle visibility with F1 or ~ (Tilde).

const MAX_LOG_LINES := 10

var container: PanelContainer
var input_ticker_label: Label
var subsystem_label: Label
var log_label: RichTextLabel
var log_history: Array[String] = []

var active_keys: Dictionary = {}
var host_node: Node


func _ready() -> void:
	layer = 120
	_build_ui()
	log_event("SYS", "Developer Terminal Initialized • Press F1 or ~ to toggle")


func configure(host: Node) -> void:
	host_node = host


func _input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key_event := event as InputEventKey
		if key_event.pressed and not key_event.echo:
			if key_event.keycode == KEY_F1 or key_event.keycode == KEY_QUOTELEFT:
				visible = not visible
				get_viewport().set_input_as_handled()
				return
		
		var key_name := OS.get_keycode_string(key_event.keycode)
		if key_event.pressed:
			active_keys[key_name] = true
			log_event("INPUT", "Key Pressed: [%s]" % key_name)
		else:
			active_keys.erase(key_name)
			
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		var btn_name := "MOUSE_%d" % mouse_event.button_index
		match mouse_event.button_index:
			MOUSE_BUTTON_LEFT: btn_name = "LMB (FIRE)"
			MOUSE_BUTTON_RIGHT: btn_name = "RMB (AIM/ADS)"
			MOUSE_BUTTON_MIDDLE: btn_name = "MMB (WHEEL)"
			MOUSE_BUTTON_WHEEL_UP: btn_name = "WHEEL_UP"
			MOUSE_BUTTON_WHEEL_DOWN: btn_name = "WHEEL_DOWN"
			
		if mouse_event.pressed:
			active_keys[btn_name] = true
			log_event("INPUT", "Button Pressed: [%s]" % btn_name)
		else:
			active_keys.erase(btn_name)


func _process(_delta: float) -> void:
	if not visible:
		return
	_update_input_ticker()
	_update_live_subsystems()


func log_event(subsystem: String, message: String) -> void:
	var time_str := Time.get_time_string_from_system()
	var line := "[color=#55ff99]%s[/color] [color=#ffaa00][%s][/color] %s" % [time_str, subsystem, message]
	log_history.append(line)
	if log_history.size() > MAX_LOG_LINES:
		log_history.pop_front()
	if log_label != null:
		log_label.text = "\n".join(log_history)


func _update_input_ticker() -> void:
	if input_ticker_label == null:
		return
	if active_keys.is_empty():
		input_ticker_label.text = "LIVE INPUT: [IDLE]"
		input_ticker_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.8))
	else:
		var pressed_str := " + ".join(active_keys.keys())
		input_ticker_label.text = "LIVE INPUT: ▶ %s" % pressed_str
		input_ticker_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))


func _update_live_subsystems() -> void:
	if subsystem_label == null or host_node == null:
		return
		
	var lines: Array[String] = []
	
	# 1. Player & Locomotion Subsystem
	var player = host_node.get("player")
	if player != null:
		var posture = player.call("get_posture_name") if player.has_method("get_posture_name") else "STANDING"
		var motion = player.call("get_motion_state_name") if player.has_method("get_motion_state_name") else "IDLE"
		var vel: Vector3 = player.velocity
		lines.append("⚙ [player_controller.gd] Posture: %s | Motion: %s | Spd: %.1f m/s" % [
			posture, motion, Vector2(vel.x, vel.z).length()
		])
	
	# 2. Camera & Collision Subsystem
	var camera_rig = host_node.get("camera_rig")
	if camera_rig != null:
		var near_crop = bool(camera_rig.get("near_body_crop_active"))
		var yaw_deg = rad_to_deg(float(camera_rig.get("yaw")))
		var pitch_deg = rad_to_deg(float(camera_rig.get("pitch")))
		lines.append("🎥 [socom_camera.gd] Yaw: %.1f° | Pitch: %.1f° | NearCrop: %s" % [
			yaw_deg, pitch_deg, ("TRUE" if near_crop else "FALSE")
		])
		
	# 3. Weapon & Socket IK Subsystem
	var weapon_ctrl = host_node.get("weapon_controller")
	if weapon_ctrl != null:
		var equipped_name = weapon_ctrl.get("equipped_weapon_display_name") if "equipped_weapon_display_name" in weapon_ctrl else "M16A2"
		var rpm = weapon_ctrl.get("fire_rate_rpm") if "fire_rate_rpm" in weapon_ctrl else 600
		var ammo = weapon_ctrl.get("current_magazine") if "current_magazine" in weapon_ctrl else 30
		lines.append("🎯 [weapon_rig_contract.gd] Weapon: %s | Mag: %s | Rate: %s RPM | IK: ACTIVE" % [
			equipped_name, str(ammo), str(rpm)
		])
		
	subsystem_label.text = "\n".join(lines)


func _build_ui() -> void:
	container = PanelContainer.new()
	container.name = "DevTerminalContainer"
	container.anchor_left = 0.0
	container.anchor_top = 0.0
	container.offset_left = 16.0
	container.offset_top = 16.0
	container.offset_right = 560.0
	container.offset_bottom = 280.0
	
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.08, 0.12, 0.88)
	style.border_color = Color(0.2, 0.8, 0.5, 0.8)
	style.border_width_left = 2
	style.border_width_top = 2
	style.border_width_right = 2
	style.border_width_bottom = 2
	style.corner_radius_top_left = 6
	style.corner_radius_top_right = 6
	style.corner_radius_bottom_left = 6
	style.corner_radius_bottom_right = 6
	container.add_theme_stylebox_override("panel", style)
	add_child(container)
	
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 10)
	container.add_child(margin)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 5)
	margin.add_child(vbox)
	
	var header := Label.new()
	header.text = "⚡ SOCOM LIVE DEV TERMINAL [F1 / ~ TO TOGGLE]"
	header.add_theme_font_size_override("font_size", 13)
	header.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
	vbox.add_child(header)
	
	input_ticker_label = Label.new()
	input_ticker_label.text = "LIVE INPUT: [IDLE]"
	input_ticker_label.add_theme_font_size_override("font_size", 12)
	input_ticker_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.5))
	vbox.add_child(input_ticker_label)
	
	vbox.add_child(HSeparator.new())
	
	subsystem_label = Label.new()
	subsystem_label.text = "Connecting subsystems..."
	subsystem_label.add_theme_font_size_override("font_size", 11)
	subsystem_label.add_theme_color_override("font_color", Color(0.7, 0.85, 1.0))
	vbox.add_child(subsystem_label)
	
	vbox.add_child(HSeparator.new())
	
	log_label = RichTextLabel.new()
	log_label.bbcode_enabled = true
	log_label.fit_content = true
	log_label.scroll_active = false
	log_label.add_theme_font_size_override("normal_font_size", 11)
	vbox.add_child(log_label)

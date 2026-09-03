extends Node3D

const ModularOperatorController := preload("res://scripts/player/modular_operator_controller.gd")

@onready var player: ModularOperatorController = $ModularOperatorPlayer
@onready var camera_pivot: Node3D = $CameraPivot
@onready var camera: Camera3D = $CameraPivot/Camera3D

var cam_yaw: float = 0.0
var cam_pitch: float = -10.0
var cam_distance: float = 3.5


func _ready() -> void:
	_setup_ui()
	_update_camera()


func _setup_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_LEFT)
	panel.position = Vector2(20, 20)
	panel.custom_minimum_size = Vector2(280, 420)
	canvas.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 8)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = "MODULAR OPERATOR LAB"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	vbox.add_child(HSeparator.new())

	# Weapon Selection
	var weapon_label := Label.new()
	weapon_label.text = "UPPER TORSO WEAPON MODE"
	vbox.add_child(weapon_label)

	var weapon_opt := OptionButton.new()
	weapon_opt.add_item("Rifle (M16A2)", 0)
	weapon_opt.add_item("Pistol", 1)
	weapon_opt.add_item("Unarmed", 2)
	weapon_opt.item_selected.connect(func(idx: int):
		player.set_weapon_mode(idx as ModularOperatorController.WeaponMode)
	)
	vbox.add_child(weapon_opt)

	vbox.add_child(HSeparator.new())

	# Stance Selection
	var stance_label := Label.new()
	stance_label.text = "TACTICAL STANCE"
	vbox.add_child(stance_label)

	var stance_opt := OptionButton.new()
	stance_opt.add_item("Standing", 0)
	stance_opt.add_item("Crouch", 1)
	stance_opt.add_item("Prone", 2)
	stance_opt.item_selected.connect(func(idx: int):
		player.set_stance(idx as ModularOperatorController.Stance)
	)
	vbox.add_child(stance_opt)

	vbox.add_child(HSeparator.new())

	# Actions
	var act_label := Label.new()
	act_label.text = "UPPER BODY ACTIONS"
	vbox.add_child(act_label)

	var hbox_acts := HBoxContainer.new()
	var btn_fire := Button.new()
	btn_fire.text = "Fire (Recoil)"
	btn_fire.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_fire.pressed.connect(func(): player.trigger_fire())
	hbox_acts.add_child(btn_fire)

	var btn_reload := Button.new()
	btn_reload.text = "Reload"
	btn_reload.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	btn_reload.pressed.connect(func(): player.trigger_reload())
	hbox_acts.add_child(btn_reload)
	vbox.add_child(hbox_acts)

	vbox.add_child(HSeparator.new())

	var hint := Label.new()
	hint.text = "Controls:\nWASD - 8-Way Strafe\nShift - Sprint\nC - Crouch\nZ - Prone\nLMB - Fire\nR - Reload\nRight Drag - Rotate Orbit"
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD
	vbox.add_child(hint)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			cam_distance = clampf(cam_distance - 0.25, 1.5, 8.0)
			_update_camera()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			cam_distance = clampf(cam_distance + 0.25, 1.5, 8.0)
			_update_camera()
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_RIGHT):
		cam_yaw -= event.relative.x * 0.4
		cam_pitch = clampf(cam_pitch - event.relative.y * 0.4, -60.0, 45.0)
		_update_camera()
	elif event is InputEventKey and event.pressed:
		match event.physical_keycode:
			KEY_C:
				player.set_stance(ModularOperatorController.Stance.CROUCHING)
			KEY_Z:
				player.set_stance(ModularOperatorController.Stance.PRONE)
			KEY_X:
				player.set_stance(ModularOperatorController.Stance.STANDING)
			KEY_1:
				player.set_weapon_mode(ModularOperatorController.WeaponMode.RIFLE)
			KEY_2:
				player.set_weapon_mode(ModularOperatorController.WeaponMode.PISTOL)
			KEY_3:
				player.set_weapon_mode(ModularOperatorController.WeaponMode.UNARMED)
			KEY_F:
				player.trigger_fire()
			KEY_R:
				player.trigger_reload()


func _update_camera() -> void:
	if camera_pivot == null or camera == null:
		return
	camera_pivot.rotation_degrees = Vector3(cam_pitch, cam_yaw, 0.0)
	camera.position = Vector3(0.0, 0.0, cam_distance)

extends Node3D

const Appearance := preload("res://scripts/player/character_appearance_profile.gd")
const TeamAppearance := preload("res://scripts/player/operator_team_appearance.gd")
const PLAYER := preload("res://scenes/player/operator_player.tscn")
var choices: Dictionary = {}
var actor: CharacterBody3D
var driver: Node3D
var pivot: Node3D
var status: Label
var camera: Camera3D
var pose_index := 0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	choices = Appearance.load_profile()
	pivot = Node3D.new()
	pivot.name = "PreviewTurntable"
	add_child(pivot)
	actor = PLAYER.instantiate() as CharacterBody3D
	pivot.add_child(actor)
	actor.set_physics_process(false)
	actor.set_local_input_enabled(false)
	driver = actor.get_node("Mannequin/ProductionAnimation") as Node3D
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-35, -30, 0)
	sun.light_energy = 1.3
	add_child(sun)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-20, 135, 0)
	fill.light_color = Color(.55,.7,1)
	fill.light_energy = .6
	add_child(fill)
	var environment := WorldEnvironment.new()
	environment.environment = Environment.new()
	environment.environment.background_mode = Environment.BG_COLOR
	environment.environment.background_color = Color(.025,.035,.045)
	environment.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color = Color(.7,.8,1)
	environment.environment.ambient_light_energy = .6
	add_child(environment)
	camera = Camera3D.new()
	camera.position = Vector3(1.7, 1.4, -4.2)
	camera.fov = 40
	add_child(camera)
	camera.look_at(Vector3(-.45, 1.0, 0))
	camera.make_current()
	_build_ui()
	_refresh()

func _process(_delta: float) -> void:
	if driver == null:
		return
	var posture := &"CROUCHED" if pose_index == 3 else &"PRONE" if pose_index == 4 else &"STANDING"
	var direction := Vector2(0, 1) if pose_index == 2 else Vector2.ZERO
	driver.set_visual_inputs(direction, posture, 0.0, 0.0, 1.0 if pose_index == 1 else 0.0, false, 0.0, direction.length(), &"LOCOMOTION", 0.0, &"FULL" if pose_index == 2 else &"WALK")

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	var panel := PanelContainer.new()
	panel.name = "CharacterControls"
	panel.position = Vector2(24, 24)
	panel.custom_minimum_size = Vector2(330, 650)
	canvas.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 20)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 12)
	margin.add_child(column)
	_label(column, "CREATE YOUR OPERATOR", 23)
	_label(column, "MODERN / MODULAR SOLDIER", 14)
	_label(column, "Cosmetic gear only • original gameplay", 13)
	for garment in ["shirt", "pants"]:
		_label(column, garment.capitalize() + " tint", 15)
		var options := OptionButton.new()
		options.name = garment.capitalize() + "Tint"
		for color in Appearance.COLORS:
			options.add_item(String(color).capitalize())
		options.select(Appearance.COLORS.keys().find(choices[garment]))
		options.item_selected.connect(func(index: int):
			choices[garment] = Appearance.COLORS.keys()[index]
			_refresh())
		column.add_child(options)
	for gear in Appearance.GEAR:
		var toggle := CheckButton.new()
		toggle.name = String(gear).capitalize() + "Toggle"
		toggle.text = String(gear).capitalize()
		toggle.button_pressed = bool(choices[gear])
		toggle.toggled.connect(func(value: bool):
			choices[gear] = value
			_refresh())
		column.add_child(toggle)
	var poses := OptionButton.new()
	poses.name = "PreviewPose"
	for label in ["Weapon ready", "Aim / ADS", "Run", "Crouch", "Prone"]:
		poses.add_item(label)
	poses.item_selected.connect(func(index: int): pose_index = index)
	column.add_child(poses)
	_label(column, "Rotate preview", 15)
	var rotation_slider := HSlider.new()
	rotation_slider.name = "RotatePreview"
	rotation_slider.min_value = -180
	rotation_slider.max_value = 180
	rotation_slider.value_changed.connect(func(value: float): pivot.rotation.y = deg_to_rad(value))
	column.add_child(rotation_slider)
	_button(column, "SAVE CHARACTER", _save, "SaveCharacter")
	_button(column, "SAVE & PLAY", _play, "SaveAndPlay")
	_button(column, "BACK TO MENU", func(): get_tree().change_scene_to_file("res://game_launcher.tscn"), "BackToMenu")
	status = _label(column, "Local preset. Online cosmetic sync not added yet.", 13)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status.custom_minimum_size.x = 285

func _label(parent: Node, text: String, size: int) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(parent: Node, text: String, callback: Callable, node_name: String) -> void:
	var button := Button.new()
	button.name = node_name
	button.text = text
	button.custom_minimum_size.y = 38
	button.pressed.connect(callback)
	parent.add_child(button)

func _refresh() -> void:
	var model := driver.get_node("TrooperModel")
	TeamAppearance.apply(model, 0, String(TeamAppearance.profile().get("solo_color", "black")), choices)
	if status != null:
		status.text = "Preview updated. Save to use this in game."

func _save() -> bool:
	var error := Appearance.save_profile(choices)
	status.text = "Character saved. Ready for training." if error == OK else "Save failed: " + error_string(error)
	return error == OK

func _play() -> void:
	if not _save():
		return
	ProjectSettings.set_setting("socom/session/public_training", true)
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	get_tree().change_scene_to_file("res://main.tscn")

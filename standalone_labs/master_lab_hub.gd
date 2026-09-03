extends Control

## Master Standalone Labs Hub
## Connects the 5 core standalone calibration systems.


func _ready() -> void:
	var btn_cam := get_node_or_null("MarginContainer/VBoxContainer/LabsList/Btn_CameraLab") as Button
	var btn_guns := get_node_or_null("MarginContainer/VBoxContainer/LabsList/Btn_GunsLab") as Button
	var btn_grenade := get_node_or_null("MarginContainer/VBoxContainer/LabsList/Btn_GrenadeLab") as Button
	var btn_sound := get_node_or_null("MarginContainer/VBoxContainer/LabsList/Btn_SoundLab") as Button
	var btn_reticle := get_node_or_null("MarginContainer/VBoxContainer/LabsList/Btn_ReticleLab") as Button

	if btn_cam != null:
		btn_cam.pressed.connect(func(): get_tree().change_scene_to_file("res://standalone_labs/1_camera_lab.tscn"))
	if btn_guns != null:
		btn_guns.pressed.connect(func(): get_tree().change_scene_to_file("res://standalone_labs/2_guns_lab.tscn"))
	if btn_grenade != null:
		btn_grenade.pressed.connect(func(): get_tree().change_scene_to_file("res://standalone_labs/3_grenade_lab.tscn"))
	if btn_sound != null:
		btn_sound.pressed.connect(func(): get_tree().change_scene_to_file("res://standalone_labs/4_sound_lab.tscn"))
	if btn_reticle != null:
		btn_reticle.pressed.connect(func(): get_tree().change_scene_to_file("res://standalone_labs/5_reticle_lab.tscn"))

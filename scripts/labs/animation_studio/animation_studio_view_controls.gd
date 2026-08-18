extends "res://scripts/labs/animation_studio/animation_studio_view.gd"

func _add_slider_control(parent: Control, label_text: String, min_val: float, max_val: float, default_val: float, callback: Callable) -> void:
    var hbox := HBoxContainer.new()
    parent.add_child(hbox)
    var lbl := Label.new()
    lbl.text = "%-12s" % label_text
    lbl.custom_minimum_size = Vector2(95, 0)
    hbox.add_child(lbl)
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = (max_val - min_val) / 200.0
    slider.value = default_val
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(callback)
    hbox.add_child(slider)

func _add_pose_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, step_val: float) -> void:
    var row := HBoxContainer.new()
    parent.add_child(row)
    var label := Label.new()
    label.text = label_text
    label.custom_minimum_size.x = 108.0
    label.add_theme_font_size_override("font_size", 11)
    row.add_child(label)
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = step_val
    slider.value = 0.0
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    row.add_child(slider)
    var value_label := Label.new()
    value_label.text = _pose_slider_value_text(key, 0.0)
    value_label.custom_minimum_size.x = 64.0
    value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
    value_label.add_theme_font_size_override("font_size", 11)
    row.add_child(value_label)
    pose_slider_controls[key] = {"slider": slider, "label": value_label}
    slider.value_changed.connect(func(value: float): _set_pose_slider_value(key, value))

func _add_gun_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, default_val: float, step_val: float, callback: Callable) -> void:
    var hbox := HBoxContainer.new()
    parent.add_child(hbox)
    var lbl := Label.new()
    lbl.text = "%-16s" % label_text
    lbl.custom_minimum_size = Vector2(130, 0)
    lbl.add_theme_font_size_override("font_size", 11)
    hbox.add_child(lbl)
    
    var val_lbl := Label.new()
    val_lbl.text = "%.2f" % default_val
    val_lbl.custom_minimum_size = Vector2(45, 0)
    val_lbl.add_theme_font_size_override("font_size", 11)
    val_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = step_val
    slider.value = default_val
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(func(v):
        val_lbl.text = ("%.1f°" % v) if "rot" in key else ("%.3f" % v if "pos" in key else "%.2fx" % v)
        callback.call(v)
    )
    hbox.add_child(slider)
    hbox.add_child(val_lbl)
    gun_sliders[key] = {"slider": slider, "label": val_lbl}

func _update_gun_sliders_and_mesh() -> void:
    if gun_sliders.has("pos_x"): gun_sliders["pos_x"]["slider"].value = right_grip_pos.x
    if gun_sliders.has("pos_y"): gun_sliders["pos_y"]["slider"].value = right_grip_pos.y
    if gun_sliders.has("pos_z"): gun_sliders["pos_z"]["slider"].value = right_grip_pos.z
    if gun_sliders.has("rot_x"): gun_sliders["rot_x"]["slider"].value = right_grip_rot.x
    if gun_sliders.has("rot_y"): gun_sliders["rot_y"]["slider"].value = right_grip_rot.y
    if gun_sliders.has("rot_z"): gun_sliders["rot_z"]["slider"].value = right_grip_rot.z
    if gun_sliders.has("scale"): gun_sliders["scale"]["slider"].value = weapon_scale_factor
    _sync_weapon_node_transform()

func _print_weapon_config() -> void:
    print("=" .repeat(60))
    print("  WEAPON TRANSFORM CONFIG")
    print("=" .repeat(60))
    print("var right_grip_pos := Vector3(%.4f, %.4f, %.4f)" % [right_grip_pos.x, right_grip_pos.y, right_grip_pos.z])
    print("var right_grip_rot := Vector3(%.1f, %.1f, %.1f)" % [right_grip_rot.x, right_grip_rot.y, right_grip_rot.z])
    print("var weapon_scale_factor: float = %.2f" % weapon_scale_factor)
    print("=" .repeat(60))
    if limb_hud_label:
        limb_hud_label.visible = true
        limb_hud_label.text = "Config printed to Godot Output!"
        get_tree().create_timer(3.0).timeout.connect(func(): limb_hud_label.visible = false)

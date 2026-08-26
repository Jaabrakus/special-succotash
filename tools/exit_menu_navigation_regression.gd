extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	var menu_script := load("res://scripts/ui/socom_exit_menu.gd")
	_expect(menu_script != null, "Escape menu script loads")
	if menu_script == null:
		_finish()
		return
	var menu: Node = menu_script.new()
	root.add_child(menu)
	await process_frame
	_expect(menu.has_signal("return_to_launcher_requested"), "Escape menu exposes Main Menu navigation")
	_expect(menu.has_signal("launch_studio_requested"), "Escape menu exposes canonical Studio navigation")
	var labels: Array[String] = []
	_collect_button_labels(menu, labels)
	_expect(labels.has("RETURN TO MAIN MENU"), "Escape menu shows Main Menu")
	_expect(labels.has("LAUNCH STUDIO"), "Escape menu shows Launch Studio")
	_expect(
		FileAccess.get_file_as_string("res://scripts/runtime/main_gameplay_hud.gd").contains(
			'navigation.call("open_home")'
		),
		"playable runtime routes Studio through canonical navigation"
	)
	_expect(
		FileAccess.get_file_as_string("res://scripts/network/socom_multiplayer_world_ui.gd").contains(
			'navigation.call("open_home")'
		),
		"multiplayer routes Studio through canonical navigation"
	)
	menu.queue_free()
	_finish()


func _collect_button_labels(node: Node, labels: Array[String]) -> void:
	if node is Button:
		labels.append((node as Button).text)
	for child in node.get_children():
		_collect_button_labels(child, labels)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("EXIT_MENU_NAVIGATION_CHECK PASS ", label)
	else:
		failures.append(label)
		push_error("EXIT_MENU_NAVIGATION_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("EXIT_MENU_NAVIGATION_REGRESSION PASS")
		quit(0)
	else:
		print("EXIT_MENU_NAVIGATION_REGRESSION FAIL ", failures)
		quit(1)

extends Node

## Shared display behavior for exported player builds. F11 and Alt+Enter toggle
## desktop fullscreen. Android stays in platform-managed immersive fullscreen.

func _ready() -> void:
	if DisplayServer.get_name() == "headless" or OS.has_feature("mobile"):
		return
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)


func _unhandled_key_input(event: InputEvent) -> void:
	if OS.has_feature("mobile") or not event is InputEventKey:
		return
	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return
	if key_event.keycode == KEY_F11 or (
		key_event.keycode == KEY_ENTER and key_event.alt_pressed
	):
		var current := DisplayServer.window_get_mode()
		DisplayServer.window_set_mode(
			DisplayServer.WINDOW_MODE_WINDOWED
			if current in [
				DisplayServer.WINDOW_MODE_FULLSCREEN,
				DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN,
			]
			else DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
		)
		get_viewport().set_input_as_handled()

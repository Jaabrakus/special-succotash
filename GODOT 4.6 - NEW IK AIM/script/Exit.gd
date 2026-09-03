extends Node

var last_esc_press_time: float = -1.0  # Time of the last ESC press
var esc_double_press_threshold: float = 1.0  # 1-second threshold

func _ready():
    # Engine.max_fps = 240
    pass

func _unhandled_input(event: InputEvent):
    if event.is_action_pressed("exit"):  # ESC key
        var current_time = Time.get_ticks_msec() / 1000.0  # Current time in seconds

        # Check if the last ESC press was within the threshold
        if last_esc_press_time > 0 and (current_time - last_esc_press_time) <= esc_double_press_threshold:
            # Double press: Quit the game
            get_tree().quit()
        else:
            # Single press: Toggle mouse visibility
            if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
                Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
            else:
                Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

        # Update the last ESC press time
        last_esc_press_time = current_time

        pass
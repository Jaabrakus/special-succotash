class_name SocomMouseAimStringGuide
extends Control

var camera_rig

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    queue_redraw()

func _process(_delta: float) -> void:
    visible = (
        camera_rig != null
        and camera_rig.mouse_aim_string_enabled
        and camera_rig.mouse_string_debug_visible
        and camera_rig.orbit_input_enabled
        and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
    )
    if visible:
        queue_redraw()

func _draw() -> void:
    if camera_rig == null:
        return
    var viewport_size: Vector2 = get_viewport_rect().size
    var center := viewport_size * 0.5
    var endpoint: Vector2 = (
        camera_rig.get_mouse_string_screen_normalized() * viewport_size
    )
    var opacity: float = camera_rig.profile.mouse_string_debug_opacity
    var color := Color(0.20, 0.72, 1.0, opacity)
    var deadzone_radius: float = camera_rig.profile.mouse_string_deadzone_radius_px
    var blue_radius: float = camera_rig.profile.mouse_string_blue_radius_px
    # The centered white circle is both the fixed shot reticle and the camera
    # deadzone. Blue must leave it while the mouse is moving to request aim.
    draw_circle(center, deadzone_radius, Color(1.0, 1.0, 1.0, opacity * 0.035))
    draw_arc(
        center,
        deadzone_radius,
        0.0,
        TAU,
        32,
        Color(1.0, 1.0, 1.0, opacity * 0.88),
        2.0,
        true
    )
    # Blue exists only for an active mouse gesture. It never animates home:
    # releasing the mouse hides it, and the next gesture starts at center.
    if camera_rig.mouse_aim_model.motion_active:
        draw_line(center, endpoint, Color(color, opacity * 0.45), 1.5, true)
        draw_circle(
            endpoint,
            blue_radius,
            Color(0.06, 0.28, 0.42, opacity * 0.65)
        )
        draw_arc(
            endpoint,
            blue_radius,
            0.0,
            TAU,
            24,
            color,
            2.0,
            true
        )

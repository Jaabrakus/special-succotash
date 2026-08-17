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
    var center: Vector2 = camera_rig.reticle_screen_normalized * viewport_size
    var endpoint: Vector2 = (
        camera_rig.get_mouse_string_screen_normalized() * viewport_size
    )
    var opacity: float = camera_rig.profile.mouse_string_debug_opacity
    var color := Color(0.20, 0.72, 1.0, opacity)
    var slack_radius: float = camera_rig.profile.mouse_string_slack_radius_px
    var reticle_radius: float = camera_rig.profile.mouse_string_reticle_radius_px
    # White is the actual shot reticle. It follows blue until its center
    # reaches the blue outline; camera collision never moves either marker.
    draw_circle(center, reticle_radius, Color(1.0, 1.0, 1.0, opacity * 0.035))
    draw_arc(
        center,
        reticle_radius,
        0.0,
        TAU,
        32,
        Color(1.0, 1.0, 1.0, opacity * 0.88),
        2.0,
        true
    )
    draw_line(center, endpoint, Color(color, opacity * 0.45), 1.5, true)
    draw_circle(
        endpoint,
        slack_radius,
        Color(0.06, 0.28, 0.42, opacity * 0.65)
    )
    draw_arc(
        endpoint,
        slack_radius,
        0.0,
        TAU,
        24,
        color,
        2.0,
        true
    )

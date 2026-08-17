class_name SocomMouseCursorGuide
extends Control

var camera_rig

func _ready() -> void:
    mouse_filter = Control.MOUSE_FILTER_IGNORE
    set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    queue_redraw()

func _process(_delta: float) -> void:
    visible = (
        camera_rig != null
        and camera_rig.mouse_cursor_cage_enabled
        and camera_rig.orbit_input_enabled
        and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
    )
    if visible:
        queue_redraw()

func _draw() -> void:
    if camera_rig == null:
        return
    var viewport_size: Vector2 = get_viewport_rect().size
    var center: Vector2 = viewport_size * 0.5
    var outer_half: Vector2 = Vector2(
        viewport_size.x * camera_rig.profile.mouse_cage_half_width,
        viewport_size.y * camera_rig.profile.mouse_cage_half_height
    )
    var inner_half: Vector2 = (
        outer_half * float(camera_rig.profile.mouse_edge_turn_start)
    )
    var opacity: float = camera_rig.profile.mouse_cage_guide_opacity
    draw_rect(
        Rect2(center - outer_half, outer_half * 2.0),
        Color(1.0, 1.0, 1.0, opacity),
        false,
        1.0
    )
    draw_rect(
        Rect2(center - inner_half, inner_half * 2.0),
        Color(0.45, 0.78, 1.0, opacity * 0.55),
        false,
        1.0
    )

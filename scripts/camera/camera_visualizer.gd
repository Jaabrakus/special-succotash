class_name SocomCameraVisualizer
extends Node3D

const DEBUG_LAYER := 20

var camera_rig
var player
var mannequin
var visible_in_workbench: bool = true

var _lines := ImmediateMesh.new()
var _line_instance := MeshInstance3D.new()
var _current_marker := MeshInstance3D.new()
var _preferred_marker := MeshInstance3D.new()
var _collision_marker := MeshInstance3D.new()
var _line_material := StandardMaterial3D.new()


func _ready() -> void:
    _line_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    _line_material.vertex_color_use_as_albedo = true
    _line_material.no_depth_test = true
    _line_instance.mesh = _lines
    _line_instance.layers = 1 << (DEBUG_LAYER - 1)
    _line_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(_line_instance)

    _configure_marker(_current_marker, Color(0.25, 1.0, 0.42), 0.15)
    _configure_marker(_preferred_marker, Color(0.20, 0.78, 1.0), 0.11)
    _configure_marker(_collision_marker, Color(1.0, 0.75, 0.20), 0.12)


func _process(_delta: float) -> void:
    visible = visible_in_workbench
    if not visible_in_workbench or camera_rig == null or player == null:
        return

    var anchor: Vector3 = (
        player.global_position
        + Vector3.UP * float(camera_rig.profile.collision_anchor_height)
    )
    var muzzle: Vector3 = player.global_position + Vector3.UP * 1.35
    if mannequin and mannequin.muzzle_marker:
        muzzle = mannequin.muzzle_marker.global_position

    _lines.clear_surfaces()
    _lines.surface_begin(Mesh.PRIMITIVE_LINES, _line_material)
    # These three muted lines are camera booms: they point from the player
    # anchor backward to candidate lens positions. They are not view/aim rays.
    _segment(anchor, camera_rig.preferred_camera_position, Color(0.08, 0.32, 0.48))
    _segment(anchor, camera_rig.collision_camera_position, Color(0.46, 0.34, 0.06))
    _segment(anchor, camera_rig.global_position, Color(0.08, 0.38, 0.16))

    # Compare like with like: the bright cyan optical ray and white/red weapon
    # ray both point forward for the same fixed display distance.
    var ray_length := 7.0
    var camera_forward: Vector3 = -camera_rig.camera.global_basis.z.normalized()
    var weapon_forward: Vector3 = (camera_rig.aim_point - muzzle).normalized()
    if weapon_forward.length_squared() < 0.99:
        weapon_forward = camera_forward
    _segment(
        camera_rig.global_position,
        camera_rig.global_position + camera_forward * ray_length,
        Color(0.15, 0.95, 1.0)
    )
    _segment(muzzle, muzzle + weapon_forward * ray_length, (
        Color(1.0, 0.24, 0.18)
        if camera_rig.shot_blocked
        else Color(1.0, 1.0, 1.0)
    ))
    _lines.surface_end()

    _current_marker.global_position = camera_rig.global_position
    _preferred_marker.global_position = camera_rig.preferred_camera_position
    _collision_marker.global_position = camera_rig.collision_camera_position


func _segment(from: Vector3, to: Vector3, color: Color) -> void:
    if from == Vector3.ZERO and to == Vector3.ZERO:
        return
    _lines.surface_set_color(color)
    _lines.surface_add_vertex(to_local(from))
    _lines.surface_set_color(color)
    _lines.surface_add_vertex(to_local(to))


func _configure_marker(marker: MeshInstance3D, color: Color, radius: float) -> void:
    var sphere := SphereMesh.new()
    sphere.radius = radius
    sphere.height = radius * 2.0
    sphere.radial_segments = 12
    sphere.rings = 6
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    material.no_depth_test = true
    marker.mesh = sphere
    marker.material_override = material
    marker.layers = 1 << (DEBUG_LAYER - 1)
    marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
    add_child(marker)

extends "res://scripts/labs/animation_studio/animation_studio_weapon.gd"

func _build_stage() -> void:
    var environment := WorldEnvironment.new()
    var settings := Environment.new()
    settings.background_mode = Environment.BG_COLOR
    settings.background_color = Color(0.035, 0.045, 0.06)
    settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    settings.ambient_light_color = Color(0.55, 0.60, 0.68)
    settings.ambient_light_energy = 0.95
    environment.environment = settings
    add_child(environment)

    var floor_mesh := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(24.0, 24.0)
    floor_mesh.mesh = plane
    var floor_mat := StandardMaterial3D.new()
    floor_mat.albedo_color = Color(0.11, 0.13, 0.15)
    floor_mat.roughness = 0.85
    floor_mesh.material_override = floor_mat
    add_child(floor_mesh)

    # Pose contacts use the same physics query path as gameplay IK. The mesh
    # remains visual-only; this thin collider makes floor snapping measurable.
    var floor_body := StaticBody3D.new()
    floor_body.name = "PoseContactFloor"
    var floor_shape_node := CollisionShape3D.new()
    var floor_shape := BoxShape3D.new()
    floor_shape.size = Vector3(24.0, 0.1, 24.0)
    floor_shape_node.shape = floor_shape
    floor_shape_node.position.y = -0.05
    floor_body.add_child(floor_shape_node)
    add_child(floor_body)

    var wall_body := StaticBody3D.new()
    wall_body.name = "PoseContactWall"
    wall_body.position = Vector3(1.35, 1.25, 0.0)
    var wall_shape_node := CollisionShape3D.new()
    var wall_shape := BoxShape3D.new()
    wall_shape.size = Vector3(0.1, 2.5, 3.0)
    wall_shape_node.shape = wall_shape
    wall_body.add_child(wall_shape_node)
    add_child(wall_body)
    pose_contact_wall_visual = MeshInstance3D.new()
    pose_contact_wall_visual.name = "PoseContactWallGuide"
    var wall_mesh := BoxMesh.new()
    wall_mesh.size = wall_shape.size
    pose_contact_wall_visual.mesh = wall_mesh
    var wall_material := StandardMaterial3D.new()
    wall_material.albedo_color = Color(0.15, 0.75, 0.9, 0.16)
    wall_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
    wall_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
    pose_contact_wall_visual.material_override = wall_material
    pose_contact_wall_visual.visible = false
    wall_body.add_child(pose_contact_wall_visual)

    var key_light := DirectionalLight3D.new()
    key_light.rotation_degrees = Vector3(-45.0, -35.0, 0.0)
    key_light.light_energy = 1.8
    key_light.shadow_enabled = true
    add_child(key_light)

    var rim_light := DirectionalLight3D.new()
    rim_light.rotation_degrees = Vector3(-25.0, 145.0, 0.0)
    rim_light.light_energy = 1.2
    rim_light.light_color = Color(0.65, 0.75, 0.95)
    add_child(rim_light)

    camera = Camera3D.new()
    camera.fov = 48.0
    add_child(camera)
    _update_camera()

func _update_camera() -> void:
    if camera == null:
        return
    var target_pos := Vector3(0.0, target_height, 0.0)
    var horizontal := cos(orbit_pitch) * orbit_distance
    camera.position = target_pos + Vector3(
        sin(orbit_yaw) * horizontal,
        sin(orbit_pitch) * orbit_distance + 0.4,
        cos(orbit_yaw) * horizontal
    )
    camera.look_at(target_pos, Vector3.UP)

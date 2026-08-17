extends SceneTree

const DRIVER_SCRIPT := preload("res://scripts/player/operator_animation_driver.gd")
const CAPTURE_DIR := "/private/tmp/socom-retarget-captures"

var driver

func _initialize() -> void:
    call_deferred("_run")

func _run() -> void:
    root.size = Vector2i(960, 720)
    DirAccess.make_dir_recursive_absolute(CAPTURE_DIR)
    _build_world()
    driver = DRIVER_SCRIPT.new()
    root.add_child(driver)
    await process_frame
    await process_frame
    driver.animation_tree.active = false

    var samples := {
        "idle": [&"mx_low_ready_idle", 0.45],
        "walk_contact": [&"mx_low_ready_walk_forward", 0.05],
        "walk_pass": [&"mx_low_ready_walk_forward", 0.52],
        "run_contact": [&"mx_low_ready_run_forward", 0.05],
        "run_pass": [&"mx_low_ready_run_forward", 0.52],
        "reload": [&"mx_rifle_reload", 0.52],
        "dive_roll": [&"mx_running_dive_roll", 0.58],
        "kneel_to_prone": [&"mx_kneel_to_prone", 0.72],
        "prone_crawl": [&"mx_prone_forward", 0.50],
    }
    for label in samples:
        var sample: Array = samples[label]
        await _capture(label, sample[0], sample[1])
    print("RETARGET_VISUAL_CAPTURE_COMPLETE ", CAPTURE_DIR)
    quit(0)

func _build_world() -> void:
    var environment := Environment.new()
    environment.background_mode = Environment.BG_COLOR
    environment.background_color = Color("17202a")
    environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
    environment.ambient_light_color = Color("b8c7d9")
    environment.ambient_light_energy = 0.72
    var world_environment := WorldEnvironment.new()
    world_environment.environment = environment
    root.add_child(world_environment)

    var key := DirectionalLight3D.new()
    key.rotation_degrees = Vector3(-48.0, -28.0, 0.0)
    key.light_color = Color("fff1d6")
    key.light_energy = 1.4
    key.shadow_enabled = true
    root.add_child(key)

    var floor := MeshInstance3D.new()
    var plane := PlaneMesh.new()
    plane.size = Vector2(8.0, 8.0)
    floor.mesh = plane
    var floor_material := StandardMaterial3D.new()
    floor_material.albedo_color = Color("465467")
    floor.material_override = floor_material
    root.add_child(floor)

    var camera := Camera3D.new()
    camera.fov = 42.0
    root.add_child(camera)
    camera.position = Vector3(3.2, 2.25, -4.5)
    camera.look_at(Vector3(0.0, 1.0, 0.0), Vector3.UP)
    camera.current = true

func _capture(label: String, clip_name: StringName, normalized_time: float) -> void:
    var animation: Animation = driver.animation_player.get_animation(clip_name)
    driver.animation_player.play(clip_name)
    driver.animation_player.seek(animation.length * normalized_time, true)
    await process_frame
    await process_frame
    RenderingServer.force_draw()
    await process_frame
    var image := root.get_texture().get_image()
    var path := CAPTURE_DIR.path_join("%s.png" % label)
    var error := image.save_png(path)
    if error != OK:
        push_error("Could not save retarget capture %s" % path)
        quit(1)
        return
    print("RETARGET_VISUAL_CAPTURE ", label, " ", clip_name, " ", path)

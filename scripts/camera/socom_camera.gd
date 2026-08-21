class_name SocomCameraRig
extends Node3D

const CameraAimResolverScript := preload("res://scripts/camera/camera_aim_resolver.gd")
const CameraCompositionControllerScript := preload("res://scripts/camera/camera_composition_controller.gd")
const CameraCollisionSolverScript := preload("res://scripts/camera/camera_collision_solver.gd")
const CameraFramingSolverScript := preload("res://scripts/camera/camera_framing_solver.gd")
const CameraFramePipelineScript := preload("res://scripts/camera/camera_frame_pipeline.gd")
const CameraDebugSnapshotScript := preload("res://scripts/camera/camera_debug_snapshot.gd")
const CameraInputControllerScript := preload("res://scripts/camera/camera_input_controller.gd")
const CameraInputPresenterScript := preload("res://scripts/camera/camera_input_presenter.gd")
const CameraProfileScript := preload("res://scripts/camera/camera_profile.gd")
const CameraPreferredShotSolverScript := preload("res://scripts/camera/camera_preferred_shot_solver.gd")
const CameraRecoverySolverScript := preload("res://scripts/camera/camera_recovery_solver.gd")
const CameraRuntimeSupportScript := preload("res://scripts/camera/camera_runtime_support.gd")
const CameraStateControllerScript := preload("res://scripts/camera/camera_state_controller.gd")
const CameraSubjectProjectorScript := preload("res://scripts/camera/camera_subject_projector.gd")
const MouseAimModelScript := preload("res://scripts/camera/mouse_aim_model.gd")
const MouseCursorGuideScript := preload("res://scripts/camera/mouse_cursor_guide.gd")
const MouseAimStringGuideScript := preload("res://scripts/camera/mouse_aim_string_guide.gd")
const VIRTUAL_WALL_OBSERVER_LAYER := 19

const CameraState = CameraStateControllerScript.CameraState

var target: Node3D
var head_marker: Node3D
var torso_marker: Node3D
var pelvis_marker: Node3D
var feet_marker: Node3D
var profile := CameraProfileScript.new()

var aim_yaw: float = 0.0
var aim_pitch: float = deg_to_rad(-2.0)
var yaw: float = 0.0
var pitch: float = deg_to_rad(-2.0)
var orbit_drag_enabled: bool = true
var mouse_aim_string_enabled: bool = true
var mouse_string_debug_visible: bool = true
var weapon_aim_instability: float = 0.0
var functional_aim_climb_enabled: bool = false
var functional_recoil_pitch_rad: float = 0.0
var functional_recoil_yaw_rad: float = 0.0
var functional_recoil_pitch_per_shot_rad: float = 0.0
var functional_recoil_yaw_per_shot_rad: float = 0.0
var functional_recoil_max_pitch_rad: float = 0.0
var functional_recoil_max_yaw_rad: float = 0.0
var functional_recoil_recovery_delay_seconds: float = 0.10
var functional_recoil_recovery_speed_rad: float = deg_to_rad(6.0)
var functional_recoil_age_seconds: float = 999.0
var mouse_aim_model := MouseAimModelScript.new()
var aim_input_controller := CameraInputControllerScript.new()
var subject_projector := CameraSubjectProjectorScript.new()
var aim_resolver := CameraAimResolverScript.new()
var state_controller := CameraStateControllerScript.new()
var composition_controller := CameraCompositionControllerScript.new()
var preferred_shot_solver := CameraPreferredShotSolverScript.new()
var framing_solver := CameraFramingSolverScript.new()
var collision_solver := CameraCollisionSolverScript.new()
var recovery_solver := CameraRecoverySolverScript.new()
var frame_pipeline := CameraFramePipelineScript.new()
var input_presenter := CameraInputPresenterScript.new()
var runtime_support := CameraRuntimeSupportScript.new()
var mouse_intent_yaw: float:
    get:
        return mouse_aim_model.intent_yaw
    set(value):
        mouse_aim_model.intent_yaw = value
var mouse_intent_pitch: float:
    get:
        return mouse_aim_model.intent_pitch
    set(value):
        mouse_aim_model.intent_pitch = value
var initial_orbit_sync_pending: bool = true
var current_camera_position := Vector3.ZERO
var preferred_camera_position := Vector3.ZERO
var virtual_camera_position := Vector3.ZERO
var collision_camera_position := Vector3.ZERO
var excursion := Vector3.ZERO
var collision_active := false
var collision_name := "CLEAR"
var collision_blocker_node: Node3D
var terrain_slope_deg: float = 0.0
var terrain_crop_relaxation: float = 0.0
var framing_correction: float = 0.0
var pelvis_crop_state := "UNKNOWN"
var boom_compression: float = 0.0
var overhead_confinement: float = 0.0
var tight_space_amount: float = 0.0
var tight_space_pelvis_crop: float = 0.0
var framing_mode := "OUTDOOR TACTICAL"
var downward_aim_amount: float = 0.0
var downward_crane_amount: float = 0.0
var downward_ledge_raise: float = 0.0
var aim_point := Vector3.ZERO
var view_aim_point := Vector3.ZERO
var weapon_aim_point := Vector3.ZERO
var aim_hit := false
var aim_collider_name := "OPEN"
var shot_point := Vector3.ZERO
var shot_blocked: bool = false
var shot_collider_name := "OPEN"
var last_fired_direction := Vector3.ZERO
var last_fired_point := Vector3.ZERO
var last_fired_tick: int = -1
var last_fired_spread_deg: float = 0.0
var measured_head_y: float = -1.0
var measured_head_x: float = -1.0
var measured_torso_y: float = -1.0
var current_head_target_x: float = 0.48
var measured_pelvis_y: float = -1.0
var measured_feet_y: float = -1.0
var current_head_target_y: float = 0.72
var current_torso_target_y: float = 0.82
var current_pelvis_target_y: float = 0.99
var current_feet_target_y: float = 1.22
var current_fov: float = 60.0
var wall_escape_active: bool = false
var wall_escape_angle_deg: float = 0.0
var local_cutout_active: bool = false
var local_cutout_center := Vector3.ZERO
var local_cutout_node: Node3D
var interior_amount: float = 0.0
var movement_lead := Vector3.ZERO
var movement_speed_ratio: float = 0.0
var movement_lateral_ratio: float = 0.0
var framing_side_correction: float = 0.0
var post_collision_reframe: bool = false
var post_initial_score: float = -1.0
var post_validated_score: float = -1.0
var post_validated_clearance: bool = false
var post_initial_head_distance: float = -1.0
var post_validated_head_distance: float = -1.0
var last_readable_post_solve_position := Vector3.ZERO
var collision_crane_active: bool = false
var collision_crane_look_ahead: float = 3.0
var collision_crane_view_amount: float = 0.0
var surface_slide_active: bool = false
var surface_slide_normal := Vector3.ZERO
var near_body_crop_active: bool = false
var near_body_geometry_hidden: bool = false
var transition_crop_active: bool = false
var surface_slide_candidate_count: int = 0
var surface_slide_clear_count: int = 0
var surface_slide_readable_count: int = 0
var surface_slide_target_x: float = -99.0
var surface_slide_target_y: float = -99.0
var reticle_screen_normalized := Vector2(0.5, 0.5)
var reticle_dynamic_amount: float = 0.0
var mouse_cursor_cage_enabled: bool = true
var mouse_cursor_deflection := Vector2.ZERO
var mouse_edge_turn := Vector2.ZERO
var mouse_cursor_guide_layer: CanvasLayer
var mouse_cursor_guide: Control
var mouse_string_guide_layer: CanvasLayer
var mouse_string_guide: Control
var camera_collision_shape := SphereShape3D.new()
var collision_cast_count: int = 0
var collision_solver_usec: int = 0
var wall_context_amount: float = 0.0
var camera_state: int = CameraState.PREFERRED
var camera_state_age: float = 0.0
var camera_state_transition_count: int = 0
var obstruction_hold_result: Dictionary = {}
var obstruction_clear_elapsed: float = 0.0
var aim_intent_sequence: int = 0
var previous_target_position := Vector3.ZERO
var target_position_initialized: bool = false
var camera_tether_rebased: bool = false
var composition_recovery_active: bool = false
var composition_hard_rebase: bool = false
var composition_hard_rebase_count: int = 0
var target_translation_blocked: bool = false
var physical_recovery_state: String = "idle"
var virtual_wall_occluder: Node3D
var virtual_wall_original_layers: Dictionary = {}

var camera: Camera3D
var orbit_input_enabled: bool = true
var automated_wall_turn: bool = false
var head_impact_age: float = 99.0
var head_impact_strength: float = 1.0
var head_impact_count: int = 0

func _init() -> void:
    # Solvers must also work in isolated unit tests before this node enters a
    # scene tree. _ready repeats no ownership work; it only builds live nodes.
    aim_input_controller.configure(mouse_aim_model)
    subject_projector.configure(self)
    aim_resolver.configure(self)
    state_controller.configure(self)
    composition_controller.configure(self)
    preferred_shot_solver.configure(self)
    framing_solver.configure(self)
    collision_solver.configure(self)
    recovery_solver.configure(self)
    frame_pipeline.configure(self)
    input_presenter.configure(self)
    runtime_support.configure(self)

func _ready() -> void:
    add_to_group("socom_camera_rig")
    camera = Camera3D.new()
    camera.name = "Camera3D"
    camera.current = true
    camera.fov = profile.vertical_fov
    camera.keep_aspect = Camera3D.KEEP_HEIGHT
    camera.near = 0.08
    add_child(camera)
    camera.set_cull_mask_value(VIRTUAL_WALL_OBSERVER_LAYER, false)
    camera_collision_shape.radius = profile.camera_collision_radius
    current_fov = profile.vertical_fov
    orbit_input_enabled = not OS.get_cmdline_user_args().has("--automated-test")
    orbit_drag_enabled = (
        profile.orbit_trail_enabled
        and not OS.get_cmdline_user_args().has("--automated-test")
    )
    mouse_cursor_cage_enabled = (
        profile.mouse_cursor_cage_enabled
        and not OS.get_cmdline_user_args().has("--automated-test")
    )
    mouse_aim_string_enabled = (
        profile.mouse_aim_string_enabled
        and not OS.get_cmdline_user_args().has("--automated-test")
    )
    mouse_string_debug_visible = profile.mouse_string_debug_dot_visible
    automated_wall_turn = (
        OS.get_cmdline_user_args().has("--wall-turn-test")
        or OS.get_cmdline_user_args().has("--interior-turn-test")
        or OS.get_cmdline_user_args().has("--wall-entry-test")
        or OS.get_cmdline_user_args().has("--wall-follow-test")
        or OS.get_cmdline_user_args().has("--camera-stress-test")
    )
    if OS.get_cmdline_user_args().has("--upward-aim-test"):
        pitch = deg_to_rad(20.0)
    elif OS.get_cmdline_user_args().has("--steep-downward-aim-test"):
        pitch = deg_to_rad(-58.0)
    elif OS.get_cmdline_user_args().has("--downward-aim-test"):
        pitch = deg_to_rad(-45.0)
    aim_yaw = yaw
    aim_pitch = pitch
    mouse_intent_yaw = aim_yaw
    mouse_intent_pitch = aim_pitch
    _build_mouse_cursor_guide()
    _build_mouse_aim_string_guide()
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if orbit_input_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        if mouse_cursor_cage_enabled:
            _accumulate_mouse_cursor(event.relative)
        elif mouse_aim_string_enabled:
            _apply_mouse_aim_string_input(event.relative)
        else:
            _apply_raw_mouse_input(event.relative)
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_M:
        set_mouse_aim_string_enabled(not mouse_aim_string_enabled)
    elif event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_N:
        mouse_string_debug_visible = not mouse_string_debug_visible
    elif orbit_input_enabled and aim_input_controller.is_controller_look_event(event, profile):
        aim_input_controller.activate_controller(Vector2(aim_yaw, aim_pitch))
    elif orbit_input_enabled and event is InputEventMouseButton and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
    _advance_functional_aim_climb(delta)
    frame_pipeline.step(delta)


func configure_functional_aim_climb(values: Dictionary) -> void:
    functional_aim_climb_enabled = bool(
        values.get("functional_aim_climb_enabled", false)
    )
    functional_recoil_pitch_per_shot_rad = deg_to_rad(maxf(
        float(values.get("aim_climb_pitch_per_shot_deg", 0.35)),
        0.0
    ))
    functional_recoil_yaw_per_shot_rad = deg_to_rad(maxf(
        float(values.get("aim_climb_yaw_per_shot_deg", 0.0)),
        0.0
    ))
    functional_recoil_max_pitch_rad = deg_to_rad(maxf(
        float(values.get("aim_climb_max_pitch_deg", 3.5)),
        0.0
    ))
    functional_recoil_max_yaw_rad = deg_to_rad(maxf(
        float(values.get("aim_climb_max_yaw_deg", 0.75)),
        0.0
    ))
    functional_recoil_recovery_delay_seconds = maxf(
        float(values.get("aim_climb_recovery_delay_seconds", 0.10)),
        0.0
    )
    functional_recoil_recovery_speed_rad = deg_to_rad(maxf(
        float(values.get("aim_climb_recovery_speed_deg_per_second", 6.0)),
        0.01
    ))
    if not functional_aim_climb_enabled:
        functional_recoil_pitch_rad = 0.0
        functional_recoil_yaw_rad = 0.0


func notify_functional_aim_climb(shot_index: int = 1) -> void:
    if not functional_aim_climb_enabled:
        return
    functional_recoil_pitch_rad = minf(
        functional_recoil_max_pitch_rad,
        functional_recoil_pitch_rad + functional_recoil_pitch_per_shot_rad
    )
    if functional_recoil_yaw_per_shot_rad > 0.0:
        var horizontal_sign := -1.0 if posmod(shot_index, 4) in [0, 1] else 1.0
        functional_recoil_yaw_rad = clampf(
            functional_recoil_yaw_rad
            + functional_recoil_yaw_per_shot_rad * horizontal_sign,
            -functional_recoil_max_yaw_rad,
            functional_recoil_max_yaw_rad
        )
    functional_recoil_age_seconds = 0.0


func _advance_functional_aim_climb(delta: float) -> void:
    if not functional_aim_climb_enabled:
        return
    functional_recoil_age_seconds += maxf(delta, 0.0)
    if functional_recoil_age_seconds < functional_recoil_recovery_delay_seconds:
        return
    var recovery_step := functional_recoil_recovery_speed_rad * maxf(delta, 0.0)
    functional_recoil_pitch_rad = move_toward(
        functional_recoil_pitch_rad,
        0.0,
        recovery_step
    )
    functional_recoil_yaw_rad = move_toward(
        functional_recoil_yaw_rad,
        0.0,
        recovery_step
    )


func get_functional_recoil_screen_offset_normalized() -> Vector2:
    if not functional_aim_climb_enabled or camera == null:
        return Vector2.ZERO
    var viewport_size := get_viewport().get_visible_rect().size
    var aspect := viewport_size.x / maxf(viewport_size.y, 1.0)
    var vertical_fov := deg_to_rad(camera.fov)
    var horizontal_fov := 2.0 * atan(tan(vertical_fov * 0.5) * aspect)
    return Vector2(
        tan(functional_recoil_yaw_rad) / maxf(2.0 * tan(horizontal_fov * 0.5), 0.001),
        -tan(functional_recoil_pitch_rad) / maxf(2.0 * tan(vertical_fov * 0.5), 0.001)
    )


func get_functional_aim_climb_debug_state() -> Dictionary:
    return {
        "enabled": functional_aim_climb_enabled,
        "pitch_deg": rad_to_deg(functional_recoil_pitch_rad),
        "yaw_deg": rad_to_deg(functional_recoil_yaw_rad),
        "screen_offset": get_functional_recoil_screen_offset_normalized(),
    }


func notify_head_impact(intensity: float = 1.0) -> void:
    # This is a presentation-only response to server-confirmed damage. It does
    # not modify yaw, pitch, the shared aim point, or the authoritative body.
    head_impact_age = 0.0
    head_impact_strength = clampf(intensity, 0.75, 1.25)
    head_impact_count += 1


func _begin_camera_presentation_frame() -> void:
    # Remove the previous rendered-lens offset before any projection, collision,
    # or aim work. The authoritative camera rig always solves from identity.
    if camera != null:
        camera.transform = Transform3D.IDENTITY


func _apply_head_impact_presentation(delta: float) -> void:
    if camera == null:
        return
    var duration := maxf(profile.head_impact_duration_seconds, 0.01)
    if head_impact_age >= duration:
        camera.transform = Transform3D.IDENTITY
        return
    head_impact_age = minf(head_impact_age + delta, duration)
    var phase := clampf(head_impact_age / duration, 0.0, 1.0)
    # One strong kick and one damped side snap. There is no continuous random
    # vibration, so each confirmed head impact reads as one discrete event.
    var kick := sin(phase * PI)
    var snap := sin(phase * TAU) * pow(1.0 - phase, 1.35)
    camera.rotation = Vector3(
        deg_to_rad(-profile.head_impact_pitch_deg * kick * head_impact_strength),
        deg_to_rad(profile.head_impact_yaw_deg * snap * head_impact_strength),
        deg_to_rad(profile.head_impact_roll_deg * snap * head_impact_strength)
    )


func get_head_impact_debug_state() -> Dictionary:
    return {
        "count": head_impact_count,
        "active": head_impact_age < profile.head_impact_duration_seconds,
        "age": head_impact_age,
        "camera_rotation": camera.rotation if camera != null else Vector3.ZERO,
    }
func reset_camera_to_target() -> void:
    _sync_aim_to_orbit()
    initial_orbit_sync_pending = false
    mouse_cursor_deflection = Vector2.ZERO
    mouse_edge_turn = Vector2.ZERO
    functional_recoil_pitch_rad = 0.0
    functional_recoil_yaw_rad = 0.0
    functional_recoil_age_seconds = 999.0
    current_camera_position = Vector3.ZERO
    preferred_camera_position = Vector3.ZERO
    virtual_camera_position = Vector3.ZERO
    collision_camera_position = Vector3.ZERO
    last_readable_post_solve_position = Vector3.ZERO
    wall_context_amount = 0.0
    tight_space_amount = 0.0
    collision_crane_view_amount = 0.0
    surface_slide_active = false
    near_body_crop_active = false
    transition_crop_active = false
    target_translation_blocked = false
    composition_hard_rebase_count = 0
    camera_state = CameraState.PREFERRED
    camera_state_age = 0.0
    obstruction_hold_result.clear()
    obstruction_clear_elapsed = 0.0
    previous_target_position = target.global_position if target else Vector3.ZERO
    target_position_initialized = target != null

func _enforce_rendered_composition(
    rendered_position: Vector3,
    legal_position: Vector3,
    delta: float
) -> Vector3:
    return recovery_solver._enforce_rendered_composition(
        rendered_position,
        legal_position,
        delta
    )

func _physical_branch_recovery(
    from_position: Vector3,
    destination: Vector3,
    maximum_step: float,
    exclude: Array[RID]
) -> Vector3:
    return recovery_solver._physical_branch_recovery(
        from_position,
        destination,
        maximum_step,
        exclude
    )
func _follow_target_translation() -> void:
    runtime_support._follow_target_translation()

func _update_virtual_wall_occluder() -> void:
    runtime_support._update_virtual_wall_occluder()

func _set_virtual_wall_occluder(blocker: Node3D) -> void:
    runtime_support._set_virtual_wall_occluder(blocker)
func _apply_collision_result(result: Dictionary) -> void:
    state_controller.apply_collision_result(result)

func _update_collision_crane_view(delta: float) -> void:
    state_controller.update_collision_crane_view(delta)

func _update_wall_camera_state(delta: float) -> void:
    state_controller.update_wall_context(delta)

func _update_deterministic_camera_state(delta: float) -> void:
    state_controller.update_state(delta)

func get_camera_state_name() -> String:
    return state_controller.state_name(camera_state)


func _smooth_legal_camera_position(
    desired: Vector3,
    delta: float,
    close_context: bool,
    open_response: float
) -> Vector3:
    return recovery_solver._smooth_legal_camera_position(
        desired,
        delta,
        close_context,
        open_response
    )

func _smooth_surface_slide_position(
    anchor: Vector3,
    desired: Vector3,
    delta: float,
    wall_normal: Vector3
) -> Vector3:
    return recovery_solver._smooth_surface_slide_position(
        anchor,
        desired,
        delta,
        wall_normal
    )

func _advance_local_lens_toward(
    from_position: Vector3,
    destination: Vector3,
    maximum_step: float,
    exclude: Array[RID]
) -> Vector3:
    return recovery_solver._advance_local_lens_toward(
        from_position,
        destination,
        maximum_step,
        exclude
    )
func _preferred_position() -> Vector3:
    return preferred_shot_solver.preferred_position()

func _low_stance_amount() -> float:
    return preferred_shot_solver.low_stance_amount()

func _prone_stance_amount() -> float:
    return preferred_shot_solver.prone_stance_amount()

func _update_environment_state(delta: float) -> void:
    preferred_shot_solver.update_environment_state(delta)

func _calculate_downward_aim_amount() -> float:
    return preferred_shot_solver.downward_aim_amount()

func _forward_direction() -> Vector3:
    return preferred_shot_solver.forward_direction()

func _composed_view_pitch() -> float:
    return preferred_shot_solver.composed_view_pitch()

func _look_target() -> Vector3:
    return preferred_shot_solver.look_target_from(global_position)

func _look_target_from(camera_position: Vector3, _force_collision_context: bool = false) -> Vector3:
    return preferred_shot_solver.look_target_from(camera_position)

func _close_wall_aim_point(look_ahead: float) -> Vector3:
    return preferred_shot_solver.close_wall_aim_point(look_ahead)

func _perched_view_direction(
    camera_position: Vector3,
    look_ahead: float,
    horizontal_correction: float = 1.0
) -> Vector3:
    return preferred_shot_solver.perched_view_direction(
        camera_position,
        look_ahead,
        horizontal_correction
    )

func _solve_collision(desired: Vector3) -> Dictionary:
    return collision_solver._solve_collision(desired)

func _solve_better_post_collision(
    initial_result: Dictionary,
    requested_position: Vector3
) -> Dictionary:
    return collision_solver._solve_better_post_collision(
        initial_result,
        requested_position
    )

func _solve_virtual_camera_surface(
    anchor: Vector3,
    virtual_position: Vector3,
    continuity_seed: Vector3,
    exclude: Array[RID]
) -> Dictionary:
    return collision_solver._solve_virtual_camera_surface(
        anchor,
        virtual_position,
        continuity_seed,
        exclude
    )

func _cast_camera_volume(
    anchor: Vector3,
    destination: Vector3,
    exclude: Array[RID]
) -> Dictionary:
    return collision_solver._cast_camera_volume(anchor, destination, exclude)

func _subject_projection(candidate: Vector3, force_collision_context: bool = false) -> Dictionary:
    return subject_projector.subject_projection(candidate, force_collision_context)

func _subject_projection_to(candidate: Vector3, look_target: Vector3) -> Dictionary:
    return subject_projector.subject_projection_to(candidate, look_target)

func _projection_keeps_subject(projection: Dictionary) -> bool:
    return subject_projector.projection_keeps_subject(projection)

func _projection_is_reframeable(projection: Dictionary) -> bool:
    return subject_projector.projection_is_reframeable(projection)

func _projection_keeps_horizontal_subject(projection: Dictionary) -> bool:
    return subject_projector.projection_keeps_horizontal_subject(projection)

func _candidate_is_reframeable(candidate: Vector3) -> bool:
    return subject_projector.candidate_is_reframeable(candidate)

func _post_solve_projection_score(projection: Dictionary) -> float:
    return subject_projector.post_solve_projection_score(projection)

func _candidate_has_subject_clearance(candidate: Vector3) -> bool:
    return subject_projector.candidate_has_subject_clearance(candidate)

func _shares_current_camera_branch(candidate: Vector3) -> bool:
    return subject_projector.shares_current_camera_branch(candidate)

func _camera_marker_visibility(marker: Node3D) -> Dictionary:
    return subject_projector.camera_marker_visibility(marker)

func _camera_subject_visibility() -> Dictionary:
    return subject_projector.camera_subject_visibility()

func _candidate_is_subject_readable(candidate: Vector3) -> bool:
    return subject_projector.candidate_is_subject_readable(candidate)

func _solve_framing(candidate: Vector3) -> Vector3:
    return framing_solver.solve(candidate)
func _update_terrain_crop_relaxation() -> void:
    composition_controller.update_terrain_crop_relaxation()

func _update_visual_crop_state() -> void:
    composition_controller.update_visual_crop_state()

func _update_tight_space_state(delta: float) -> void:
    composition_controller.update_tight_space_state(delta)

func _update_dynamic_fov(delta: float) -> void:
    composition_controller.update_dynamic_fov(delta)

func _update_movement_follow(delta: float) -> void:
    composition_controller.update_movement_follow(delta)

func _measure_overhead_confinement() -> float:
    return composition_controller.measure_overhead_confinement()

func _limit_excursion(candidate: Vector3) -> Vector3:
    return composition_controller.limit_excursion(candidate)

func _orient_camera(_delta: float) -> void:
    var desired_basis := _basis_looking_at(_look_target())
    # Gameplay aim remains immediate and independent below. Only the special
    # perched-wall composition blends its rendered view to avoid a visual pop.
    # Positional boom release remains smoothed independently.
    global_basis = desired_basis

func _snap_orientation() -> void:
    global_basis = _basis_looking_at(_look_target())

func _basis_looking_at(point: Vector3) -> Basis:
    var direction := (point - global_position).normalized()
    if direction.length_squared() < 0.0001:
        return global_basis
    return Basis.looking_at(direction, Vector3.UP, false)

func _update_aim_point() -> void:
    aim_resolver.update_aim_point()

func _update_weapon_aim_point() -> void:
    aim_resolver.update_weapon_aim_point()

func _update_shot_validation() -> void:
    aim_resolver.update_shot_validation()

func build_local_aim_intent() -> Dictionary:
    return aim_resolver.build_local_aim_intent()

func get_shared_aim_target() -> Vector3:
    return aim_resolver.shared_target()

func get_shared_aim_direction(origin: Vector3) -> Vector3:
    return aim_resolver.shared_direction_from(origin)

func get_shared_aim_yaw_pitch(origin: Vector3) -> Vector2:
    return aim_resolver.shared_yaw_pitch_from(origin)

func get_shared_body_aim_yaw_pitch() -> Vector2:
    return aim_resolver.shared_body_yaw_pitch()

func _update_reticle_position(delta: float) -> void:
    input_presenter._update_reticle_position(delta)

func get_mouse_cursor_screen_normalized() -> Vector2:
    return input_presenter.get_mouse_cursor_screen_normalized()

func get_debug_data() -> Dictionary:
    return CameraDebugSnapshotScript.build(self)

func set_aim_angles(new_yaw: float, new_pitch: float, snap_orbit: bool = false) -> void:
    input_presenter.set_aim_angles(new_yaw, new_pitch, snap_orbit)

func set_orbit_trail_enabled(enabled: bool) -> void:
    input_presenter.set_orbit_trail_enabled(enabled)

func _sync_aim_to_orbit() -> void:
    input_presenter._sync_aim_to_orbit()

func set_mouse_aim_string_enabled(enabled: bool) -> void:
    input_presenter.set_mouse_aim_string_enabled(enabled)

func _apply_raw_mouse_input(relative_motion: Vector2) -> void:
    input_presenter._apply_raw_mouse_input(relative_motion)

func _apply_mouse_aim_string_input(relative_motion: Vector2) -> void:
    input_presenter._apply_mouse_aim_string_input(relative_motion)

func _update_mouse_aim_string(delta: float) -> void:
    input_presenter._update_mouse_aim_string(delta)

func _update_controller_aim(delta: float) -> void:
    input_presenter._update_controller_aim(delta)

func is_controller_aim_active() -> bool:
    return input_presenter.is_controller_aim_active()

func get_active_aim_device_name() -> String:
    return input_presenter.get_active_aim_device_name()

func get_mouse_string_screen_normalized() -> Vector2:
    return input_presenter.get_mouse_string_screen_normalized()

func set_weapon_aim_instability(value: float) -> void:
    # Local presentation only. The weapon controller remains authoritative for
    # the actual spread and supplies the same movement/bloom pressure used here.
    weapon_aim_instability = clampf(value, 0.0, 1.0)
    var live_leash := get_effective_mouse_string_max_lead_px()
    if mouse_aim_model.blue_offset_pixels.length() > live_leash:
        mouse_aim_model.blue_offset_pixels = (
            mouse_aim_model.blue_offset_pixels.normalized() * live_leash
        )

func get_effective_mouse_string_deadzone_radius_px() -> float:
    return (
        profile.mouse_string_deadzone_radius_px
        + profile.mouse_string_instability_deadzone_gain_px * weapon_aim_instability
    )

func get_effective_mouse_string_max_lead_px() -> float:
    return (
        profile.mouse_string_max_lead_px
        + profile.mouse_string_instability_lead_gain_px * weapon_aim_instability
    )

func get_operator_alignment_screen_normalized() -> Vector2:
    return input_presenter.get_operator_alignment_screen_normalized()

func _update_orbit_trail(delta: float, scoped_view: bool) -> void:
    input_presenter._update_orbit_trail(delta, scoped_view)

func set_mouse_cursor_cage_enabled(enabled: bool) -> void:
    input_presenter.set_mouse_cursor_cage_enabled(enabled)

func _accumulate_mouse_cursor(relative_motion: Vector2) -> void:
    input_presenter._accumulate_mouse_cursor(relative_motion)

func _update_mouse_cursor_turn(delta: float) -> void:
    input_presenter._update_mouse_cursor_turn(delta)

func _mouse_edge_axis(value: float) -> float:
    return input_presenter._mouse_edge_axis(value)
func _direction_to_yaw_pitch(direction: Vector3) -> Vector2:
    return aim_resolver.direction_to_yaw_pitch(direction)

func _build_mouse_cursor_guide() -> void:
    mouse_cursor_guide_layer = CanvasLayer.new()
    mouse_cursor_guide_layer.name = "MouseCursorCageLayer"
    mouse_cursor_guide_layer.layer = 90
    add_child(mouse_cursor_guide_layer)
    mouse_cursor_guide = MouseCursorGuideScript.new()
    mouse_cursor_guide.name = "MouseCursorCageGuide"
    mouse_cursor_guide.camera_rig = self
    mouse_cursor_guide_layer.add_child(mouse_cursor_guide)

func _build_mouse_aim_string_guide() -> void:
    mouse_string_guide_layer = CanvasLayer.new()
    mouse_string_guide_layer.name = "MouseAimStringLayer"
    mouse_string_guide_layer.layer = 91
    add_child(mouse_string_guide_layer)
    mouse_string_guide = MouseAimStringGuideScript.new()
    mouse_string_guide.name = "MouseAimStringGuide"
    mouse_string_guide.camera_rig = self
    mouse_string_guide_layer.add_child(mouse_string_guide)

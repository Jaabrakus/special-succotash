class_name SocomCameraRig
extends Node3D

const CameraAimResolverScript := preload("res://scripts/camera/camera_aim_resolver.gd")
const CameraCompositionControllerScript := preload("res://scripts/camera/camera_composition_controller.gd")
const CameraCollisionSolverScript := preload("res://scripts/camera/camera_collision_solver.gd")
const CameraFramingSolverScript := preload("res://scripts/camera/camera_framing_solver.gd")
const CameraDebugSnapshotScript := preload("res://scripts/camera/camera_debug_snapshot.gd")
const CameraInputControllerScript := preload("res://scripts/camera/camera_input_controller.gd")
const CameraProfileScript := preload("res://scripts/camera/camera_profile.gd")
const CameraPreferredShotSolverScript := preload("res://scripts/camera/camera_preferred_shot_solver.gd")
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
var mouse_aim_model := MouseAimModelScript.new()
var aim_input_controller := CameraInputControllerScript.new()
var subject_projector := CameraSubjectProjectorScript.new()
var aim_resolver := CameraAimResolverScript.new()
var state_controller := CameraStateControllerScript.new()
var composition_controller := CameraCompositionControllerScript.new()
var preferred_shot_solver := CameraPreferredShotSolverScript.new()
var framing_solver := CameraFramingSolverScript.new()
var collision_solver := CameraCollisionSolverScript.new()
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
var weapon_aim_point := Vector3.ZERO
var aim_hit := false
var aim_collider_name := "OPEN"
var shot_point := Vector3.ZERO
var shot_blocked: bool = false
var shot_collider_name := "OPEN"
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
    if target == null or camera == null:
        return

    # The lab selects scenario yaw/pitch immediately after add_child() returns,
    # which is after _ready(). Capture that final initial orbit once so the
    # camera cannot ease back toward stale startup intent on its first frame.
    if initial_orbit_sync_pending:
        _sync_aim_to_orbit()
        initial_orbit_sync_pending = false

    if Input.is_action_just_pressed("reset_camera"):
        aim_yaw = target.global_rotation.y
        aim_pitch = deg_to_rad(-2.0)
        yaw = aim_yaw
        pitch = aim_pitch
        mouse_intent_yaw = aim_yaw
        mouse_intent_pitch = aim_pitch
        mouse_aim_model.reset(Vector2(aim_yaw, aim_pitch))
        mouse_cursor_deflection = Vector2.ZERO
        reset_camera_to_target()
    _follow_target_translation()
    var rendered_frame_start: Vector3 = current_camera_position
    if automated_wall_turn:
        var automated_turn_speed := (
            150.0
            if OS.get_cmdline_user_args().has("--camera-stress-test")
            else 38.0
        )
        yaw -= deg_to_rad(automated_turn_speed) * delta
        aim_yaw = yaw
    else:
        if aim_input_controller.is_controller_active() and orbit_input_enabled:
            _update_controller_aim(delta)
        elif mouse_aim_string_enabled and orbit_input_enabled:
            _update_mouse_aim_string(delta)
        if (
            mouse_cursor_cage_enabled
            and aim_input_controller.is_mouse_active()
            and orbit_input_enabled
            and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        ):
            _update_mouse_cursor_turn(delta)
        elif not mouse_aim_string_enabled:
            mouse_edge_turn = Vector2.ZERO
        if orbit_drag_enabled:
            # Standard SOCOM weapons have no ADS camera. The tighter response
            # is reserved for a future explicit sniper/scope state.
            _update_orbit_trail(delta, false)
        else:
            yaw = aim_yaw
            pitch = aim_pitch
    yaw = wrapf(yaw, -PI, PI)

    _update_movement_follow(delta)
    downward_aim_amount = _calculate_downward_aim_amount()
    downward_crane_amount = smoothstep(0.0, 1.0, downward_aim_amount)
    # Mid-range downward pitch is where a parapet most often blocks the center
    # ray. Add a bell-shaped ledge lift that fades out again for true top-down aim.
    downward_ledge_raise = (
        sin(PI * downward_aim_amount)
        * profile.mid_downward_ledge_raise
    )
    _update_environment_state(delta)
    # Raw player yaw/pitch owns one camera-independent crosshair target. Camera
    # placement, collision and animation may react to it, but never rewrite it.
    _update_aim_point()
    # Framing must measure the same projection that will be rendered this frame.
    # Updating FOV after composition caused a one-frame scale/pop disagreement.
    _update_dynamic_fov(delta)

    # A crane view is a result of this frame's collision solve, never an input
    # to the preferred-shot composition pass. Clearing it here prevents the
    # previous wall frame from biasing the next open/preferred solve.
    collision_crane_active = false

    preferred_camera_position = _preferred_position()
    var composed_position := _solve_framing(preferred_camera_position)
    var bounded_position := _limit_excursion(composed_position)
    # The virtual lens always follows input. Collision may constrain only the
    # rendered lens; it must never rewrite or stall this desired position.
    virtual_camera_position = bounded_position
    collision_cast_count = 0
    var collision_solve_started: int = Time.get_ticks_usec()
    var collision_result := _solve_collision(bounded_position)
    _apply_collision_result(collision_result)
    post_collision_reframe = false
    post_initial_score = -1.0
    post_validated_score = -1.0
    post_validated_clearance = false
    post_initial_head_distance = -1.0
    post_validated_head_distance = -1.0

    # Collision can completely change the composition that was solved above.
    # Recompose from the legal collision result, then volume-cast that correction
    # again. This lets a constrained camera rise enough to lower the head on
    # screen without ever lifting the lens through a ceiling or wall.
    if collision_active:
        var initial_collision_name := collision_name
        var initial_wall_escape := wall_escape_active
        var initial_escape_angle := wall_escape_angle_deg
        var initial_collision_result := collision_result
        var initial_collision_position := collision_camera_position
        var initial_projection := _subject_projection(initial_collision_position, true)
        post_initial_score = _post_solve_projection_score(initial_projection)
        post_initial_head_distance = initial_collision_position.distance_to(head_marker.global_position)
        # A close collision result is precisely when composition needs its
        # second pass. The old reframeable gate skipped this block whenever the
        # head had already crossed the screen guard, leaving the HUD on
        # "preferred pass" and allowing the lens to crowd the operator.
        var normal_post_solve_applied: bool = false
        if bool(initial_projection.visible):
            var reframed_position := _solve_framing(collision_camera_position)
            var reframed_bounded := _limit_excursion(reframed_position)
            var validated_result := _solve_collision(reframed_bounded)
            var validated_position: Vector3 = validated_result.position
            var validated_projection := _subject_projection(validated_position, true)
            post_validated_score = _post_solve_projection_score(validated_projection)
            post_validated_clearance = _candidate_has_subject_clearance(validated_position)
            post_validated_head_distance = validated_position.distance_to(head_marker.global_position)
            var validated_current_branch: bool = _shares_current_camera_branch(
                validated_position
            )
            # A legal, readable composition is the primary acceptance rule.
            # Requiring its numeric score to beat an already-broken close shot
            # rejected useful wall escapes and put the camera back on the raw
            # preferred pass. The score remains a fallback for edge projections.
            if (
                validated_current_branch
                and (
                    _candidate_is_subject_readable(validated_position)
                    or (
                        post_validated_clearance
                        and post_validated_score <= post_initial_score + 0.001
                    )
                )
            ):
                _apply_collision_result(validated_result)
                normal_post_solve_applied = true
                # A later cast may report CLEAR because its starting position
                # was already moved away from the original blocker. Preserve
                # the obstruction state so response/tight framing do not flicker.
                if not collision_active:
                    collision_active = true
                    collision_name = "%s / REFRAMED" % initial_collision_name
                    wall_escape_active = initial_wall_escape
                    wall_escape_angle_deg = initial_escape_angle

        # If the normal composition pass cannot produce a legal readable shot,
        # do not stop at its physical seed. Run a second bounded post-solve over
        # volume-cast boom angles, then refine the best result locally. This is
        # collision -> post-solve -> better post-solve, never collision -> stop.
        if not normal_post_solve_applied:
            var better_result := _solve_better_post_collision(
                initial_collision_result,
                bounded_position
            )
            _apply_collision_result(better_result)
            var better_position: Vector3 = better_result.position
            var better_projection := _subject_projection(better_position, true)
            post_validated_score = _post_solve_projection_score(better_projection)
            post_validated_clearance = _candidate_has_subject_clearance(better_position)
            post_validated_head_distance = better_position.distance_to(head_marker.global_position)

        # This flag now means the collision result completed the post-solve
        # pipeline. Whether the second stage found an improvement is recorded
        # in the collision name instead of exposing a raw fallback state.
        post_collision_reframe = true

    # Keep one fixed legal composition anchor for crane continuity. A
    # constrained frame never overwrites it, so repeated frames cannot
    # accumulate height or walk the camera away from the player.
    if (
        _candidate_has_subject_clearance(collision_camera_position)
        and _candidate_is_reframeable(collision_camera_position)
    ):
        last_readable_post_solve_position = collision_camera_position

    collision_solver_usec = Time.get_ticks_usec() - collision_solve_started
    _update_collision_crane_view(delta)
    _update_wall_camera_state(delta)
    _update_tight_space_state(delta)
    _update_deterministic_camera_state(delta)

    excursion = collision_camera_position - preferred_camera_position

    # A side strafe can block the old camera's world-space translation even
    # though this frame has already solved a new legal player-relative shot.
    # Seed presentation from that fresh result so the camera cannot remain on
    # the wall while the player walks away. The final local speed limit below
    # still makes the visible correction bounded whenever a legal route exists.
    if target_translation_blocked:
        current_camera_position = collision_camera_position
        transition_crop_active = false

    var movement_response: float = lerpf(
        profile.normal_return_response,
        profile.movement_camera_response,
        movement_speed_ratio
    )
    if current_camera_position == Vector3.ZERO:
        current_camera_position = collision_camera_position
    else:
        transition_crop_active = false
        # Always follow the player on a pivot-relative boom. A Cartesian world
        # lerp trails behind orbit input and visibly separates the centered
        # character from the centered reticle while turning.
        current_camera_position = _smooth_legal_camera_position(
            collision_camera_position,
            delta,
            (
                camera_state != CameraState.PREFERRED
                or collision_active
                or collision_crane_view_amount > 0.01
            ),
            movement_response
        )

    current_camera_position = _enforce_rendered_composition(
        current_camera_position,
        collision_camera_position,
        delta
    )

    # Final presentation invariant: no solver branch may bypass the close-wall
    # speed limit. Validate the short local lens move instead of the obstructed
    # player-to-camera boom, which keeps the camera outside geometry while it
    # travels smoothly around the virtual wall surface.
    var close_transition_active: bool = (
        camera_state != CameraState.PREFERRED
        or collision_active
        or wall_context_amount > 0.01
    )
    if close_transition_active and rendered_frame_start != Vector3.ZERO:
        var rendered_motion: Vector3 = (
            current_camera_position - rendered_frame_start
        )
        var rendered_maximum_step: float = (
            (
                profile.wall_branch_max_linear_speed
                if collision_active
                else profile.composition_recovery_speed
            ) * delta
        )
        if rendered_motion.length() > rendered_maximum_step:
            var rendered_exclude: Array[RID] = []
            if target is CollisionObject3D:
                rendered_exclude.append((target as CollisionObject3D).get_rid())
            current_camera_position = _advance_local_lens_toward(
                rendered_frame_start,
                current_camera_position,
                rendered_maximum_step,
                rendered_exclude
            )

    camera_tether_rebased = false
    # Fairness beats continuity when no continuous branch exists. Never leave
    # the operator off-screen for multiple frames and never render a boom that
    # crosses solid geometry. Both fallbacks use this frame's physical solve;
    # outward release remains smoothed by the ordinary path above.
    var final_exclude: Array[RID] = []
    if target is CollisionObject3D:
        final_exclude.append((target as CollisionObject3D).get_rid())
    var final_anchor: Vector3 = (
        target.global_position
        + Vector3.UP * float(profile.collision_anchor_height)
    )
    var final_boom_cast := _cast_camera_volume(
        final_anchor,
        current_camera_position,
        final_exclude
    )
    if float(final_boom_cast.safe_fraction) < 0.999:
        current_camera_position = collision_camera_position
        transition_crop_active = false
        camera_tether_rebased = true

    # A rendered lens can never remain at an obsolete world-space wall point
    # after the player has left. Normal motion is handled by the translation
    # follower above; this tether is the spawn/teleport and impossible-route
    # invariant. A fresh collision solve is always safer than a multi-second
    # stale camera hold.
    if (
        current_camera_position.distance_to(target.global_position)
        > profile.max_rendered_target_distance
    ):
        current_camera_position = collision_camera_position
        transition_crop_active = false
        camera_tether_rebased = true

    global_position = current_camera_position
    _update_virtual_wall_occluder()
    _orient_camera(delta)
    _update_reticle_position(delta)
    _update_weapon_aim_point()
    var mannequin = target.get_node_or_null("Mannequin") if target else null
    near_body_geometry_hidden = (
        near_body_crop_active
        and head_marker != null
        and global_position.distance_to(head_marker.global_position) < 0.62
    )
    if mannequin and mannequin.has_method("set_near_camera_crop"):
        mannequin.set_near_camera_crop(near_body_geometry_hidden)
    _update_visual_crop_state()
    _update_shot_validation()

func reset_camera_to_target() -> void:
    _sync_aim_to_orbit()
    initial_orbit_sync_pending = false
    mouse_cursor_deflection = Vector2.ZERO
    mouse_edge_turn = Vector2.ZERO
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
    previous_target_position = target.global_position if target else Vector3.ZERO
    target_position_initialized = target != null

func _enforce_rendered_composition(
    rendered_position: Vector3,
    legal_position: Vector3,
    delta: float
) -> Vector3:
    composition_recovery_active = false
    composition_hard_rebase = false
    physical_recovery_state = "idle"
    var rendered_projection := _subject_projection(rendered_position)
    var rendered_visible: bool = bool(rendered_projection.visible)
    var rendered_error: float = INF
    if rendered_visible:
        rendered_error = absf(
            float(rendered_projection.x) - current_head_target_x
        )
    if rendered_error <= profile.rendered_head_soft_limit_x:
        return rendered_position

    # Recovery may only target the collision solver's physical endpoint. The
    # former virtual endpoint could sit beyond a wall and required hiding that
    # wall to make the shot appear valid.
    var recovery_position := legal_position
    var legal_projection := _subject_projection(recovery_position, true)
    if not bool(legal_projection.visible):
        return rendered_position
    var legal_error: float = absf(
        float(legal_projection.x) - current_head_target_x
    )
    if legal_error >= rendered_error - 0.001:
        return rendered_position

    composition_recovery_active = true
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    # Once the subject is effectively gone, continuity has failed—but an
    # emergency correction must still travel through local free space. A cut
    # to a distant legal endpoint can cross a wall and is the visible snap the
    # regression test catches. Search one bounded, improving lens step instead.
    if (
        not rendered_visible
        or rendered_error >= profile.rendered_head_hard_limit_x
    ):
        composition_hard_rebase = true
        composition_hard_rebase_count += 1
        var local_recovery := _physical_branch_recovery(
            rendered_position,
            recovery_position,
            profile.wall_branch_max_linear_speed * delta,
            exclude
        )
        if local_recovery != rendered_position:
            return local_recovery
        return recovery_position

    # At the soft guard, take only a volume-validated local step toward the
    # legal physical shot.
    return _physical_branch_recovery(
        rendered_position,
        recovery_position,
        profile.composition_recovery_speed * delta,
        exclude
    )

func _physical_branch_recovery(
    from_position: Vector3,
    destination: Vector3,
    maximum_step: float,
    exclude: Array[RID]
) -> Vector3:
    # A solid wall can separate two otherwise legal orbit endpoints. The
    # physical route is the classic spring-arm route: retract on the current
    # player ray, rotate while close, then let normal release extend the boom.
    # Starting this at the soft composition guard prevents both the stale-wall
    # hold and an emergency opposite-branch cut.
    var anchor: Vector3 = (
        target.global_position
        + Vector3.UP * float(profile.collision_anchor_height)
    )
    var current_offset: Vector3 = from_position - anchor
    var destination_offset: Vector3 = destination - anchor
    var current_length: float = current_offset.length()
    var destination_length: float = destination_offset.length()
    if current_length < 0.001 or destination_length < 0.001:
        return destination

    var current_direction: Vector3 = current_offset / current_length
    var destination_direction: Vector3 = destination_offset / destination_length
    var branch_angle: float = current_direction.angle_to(destination_direction)
    var close_length: float = (
        profile.min_camera_target_distance
        + profile.camera_collision_radius
        + profile.collision_margin
    )
    var candidate := from_position
    if branch_angle > deg_to_rad(8.0) and current_length > close_length + 0.01:
        physical_recovery_state = "RETRACT"
        candidate = anchor + current_direction * maxf(
            close_length,
            current_length - maximum_step
        )
    elif branch_angle > deg_to_rad(0.5):
        physical_recovery_state = "ROTATE"
        var angular_step: float = minf(
            branch_angle,
            deg_to_rad(profile.wall_branch_max_angular_speed_deg)
                * get_process_delta_time()
        )
        var rotated_direction := current_direction.slerp(
            destination_direction,
            angular_step / maxf(branch_angle, 0.0001)
        ).normalized()
        candidate = anchor + rotated_direction * minf(
            current_length,
            close_length
        )
    else:
        return _advance_local_lens_toward(
            from_position,
            destination,
            maximum_step,
            exclude
        )

    var anchor_cast := _cast_camera_volume(anchor, candidate, exclude)
    var local_cast := _cast_camera_volume(from_position, candidate, exclude)
    if (
        float(anchor_cast.safe_fraction) >= 0.999
        and float(local_cast.safe_fraction) >= 0.999
        and _candidate_has_subject_clearance(candidate)
    ):
        return candidate

    var candidate_projection := _subject_projection(candidate)
    var candidate_head_distance: float = candidate.distance_to(
        head_marker.global_position
    )
    if (
        physical_recovery_state == "RETRACT"
        and float(anchor_cast.safe_fraction) >= 0.999
        and float(local_cast.safe_fraction) >= 0.999
        and bool(candidate_projection.visible)
        and float(candidate_projection.x) >= 0.05
        and float(candidate_projection.x) <= 0.95
        and float(candidate_projection.y) >= 0.02
        and float(candidate_projection.y) <= 1.02
        and candidate_head_distance >= 0.70
    ):
        physical_recovery_state = "RETRACT CLOSE"
        return candidate

    # The current wall shot can already be inside the nominal head-clearance
    # radius. Retracting farther would make that worse. First rotate at the
    # current radius; this often increases clearance without changing zoom.
    var recovery_angle_step: float = minf(
        branch_angle,
        maximum_step / maxf(current_length, 0.001)
    )
    var recovery_direction := current_direction.slerp(
        destination_direction,
        recovery_angle_step / maxf(branch_angle, 0.0001)
    ).normalized()
    var rotate_candidate := anchor + recovery_direction * current_length
    var rotate_anchor_cast := _cast_camera_volume(
        anchor,
        rotate_candidate,
        exclude
    )
    var rotate_local_cast := _cast_camera_volume(
        from_position,
        rotate_candidate,
        exclude
    )
    var current_head_distance: float = from_position.distance_to(
        head_marker.global_position
    )
    var current_projection := _subject_projection(from_position)
    var rotate_projection := _subject_projection(rotate_candidate)
    var current_projection_error: float = (
        absf(float(current_projection.x) - current_head_target_x)
        if bool(current_projection.visible)
        else INF
    )
    var rotate_projection_error: float = (
        absf(float(rotate_projection.x) - current_head_target_x)
        if bool(rotate_projection.visible)
        else INF
    )
    if (
        float(rotate_anchor_cast.safe_fraction) >= 0.999
        and float(rotate_local_cast.safe_fraction) >= 0.999
        and bool(rotate_projection.visible)
        and float(rotate_projection.x) >= 0.05
        and float(rotate_projection.x) <= 0.95
        and float(rotate_projection.y) >= 0.02
        and float(rotate_projection.y) <= 1.02
        and (
            _candidate_has_subject_clearance(rotate_candidate)
            or rotate_projection_error
                < current_projection_error - 0.0001
        )
    ):
        physical_recovery_state = "ROTATE WIDE"
        return rotate_candidate

    # If the arc is blocked, rise locally on the same player side until the
    # clearance opens. Never spend vertical composition past the frame guard.
    var maximum_height: float = (
        target.global_position.y + profile.close_wall_crane_max_height
    )
    var lift_candidate := from_position + Vector3.UP * maximum_step
    lift_candidate.y = minf(lift_candidate.y, maximum_height)
    var lift_anchor_cast := _cast_camera_volume(anchor, lift_candidate, exclude)
    var lift_local_cast := _cast_camera_volume(
        from_position,
        lift_candidate,
        exclude
    )
    var lift_head_distance: float = lift_candidate.distance_to(
        head_marker.global_position
    )
    var lift_projection := _subject_projection(lift_candidate)
    if (
        lift_candidate != from_position
        and float(lift_anchor_cast.safe_fraction) >= 0.999
        and float(lift_local_cast.safe_fraction) >= 0.999
        and _projection_is_reframeable(lift_projection)
        and (
            _candidate_has_subject_clearance(lift_candidate)
            or lift_head_distance > current_head_distance + 0.001
        )
    ):
        physical_recovery_state = "LIFT"
        return lift_candidate
    physical_recovery_state = "BLOCKED rotcast %.2f/%.2f rot %.2f,%.2f err %.2f>%.2f" % [
        float(rotate_anchor_cast.safe_fraction),
        float(rotate_local_cast.safe_fraction),
        float(rotate_projection.x),
        float(rotate_projection.y),
        rotate_projection_error,
        current_projection_error
    ]
    return _advance_local_lens_toward(
        from_position,
        destination,
        maximum_step,
        exclude
    )

func _follow_target_translation() -> void:
    target_translation_blocked = false
    var target_position := target.global_position
    if not target_position_initialized:
        previous_target_position = target_position
        target_position_initialized = true
        return
    var target_motion := target_position - previous_target_position
    previous_target_position = target_position
    if target_motion.length_squared() < 0.0000001:
        return
    # Spawn/test teleports get a fresh solve. Smoothing a camera across the map
    # is both slower and less readable than rebasing on the new player pose.
    if target_motion.length() > 1.50:
        reset_camera_to_target()
        return
    if current_camera_position == Vector3.ZERO:
        return

    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())
    var translated := current_camera_position + target_motion
    var translation_cast := _cast_camera_volume(
        current_camera_position,
        translated,
        exclude
    )
    var applied_motion: Vector3 = target_motion * clampf(
        float(translation_cast.safe_fraction),
        0.0,
        1.0
    )
    target_translation_blocked = float(translation_cast.safe_fraction) < 0.999
    current_camera_position += applied_motion
    if last_readable_post_solve_position != Vector3.ZERO:
        last_readable_post_solve_position += applied_motion

func _update_virtual_wall_occluder() -> void:
    # Solid world geometry always remains visible. Camera recovery is physical
    # now, so concealing the blocker would only reveal unfair information from
    # rooms or buildings behind it.
    _set_virtual_wall_occluder(null)

func _set_virtual_wall_occluder(blocker: Node3D) -> void:
    if blocker == virtual_wall_occluder:
        return
    for instance_id in virtual_wall_original_layers:
        var instance := instance_from_id(int(instance_id)) as GeometryInstance3D
        if instance:
            instance.layers = int(virtual_wall_original_layers[instance_id])
    virtual_wall_original_layers.clear()
    virtual_wall_occluder = blocker
    if blocker == null:
        return
    var geometry_nodes: Array[Node] = blocker.find_children(
        "*",
        "GeometryInstance3D",
        true,
        false
    )
    if blocker is GeometryInstance3D:
        geometry_nodes.append(blocker)
    for node in geometry_nodes:
        var geometry := node as GeometryInstance3D
        if geometry == null:
            continue
        virtual_wall_original_layers[geometry.get_instance_id()] = geometry.layers
        geometry.set_layer_mask_value(VIRTUAL_WALL_OBSERVER_LAYER, true)
        geometry.set_layer_mask_value(1, false)

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
    if target == null or current_camera_position == Vector3.ZERO:
        return desired

    var anchor: Vector3 = target.global_position + Vector3.UP * float(profile.collision_anchor_height)
    var current_offset: Vector3 = current_camera_position - anchor
    var desired_offset: Vector3 = desired - anchor
    var desired_length: float = desired_offset.length()
    if desired_length < 0.001:
        return desired

    if surface_slide_active:
        return _smooth_surface_slide_position(
            anchor,
            desired,
            delta,
            surface_slide_normal
        )

    # The perched-wall solve can move from the last ordinary legal shot to a
    # slightly higher continuity shot. Interpolate that short legal-side move
    # directly before applying the radial boom release below; otherwise the
    # direction change can turn a 30 cm rise into a one-frame position pop.
    if collision_crane_active:
        var transition_weight: float = 1.0 - exp(
            -profile.close_wall_crane_enter_response * delta
        )
        var transition_candidate := current_camera_position
        if current_camera_position.y < desired.y - 0.02:
            # Rise on the known legal side first. The direct diagonal between
            # two legal endpoints can still clip the wall's top corner.
            transition_candidate.y = lerpf(
                current_camera_position.y,
                desired.y,
                transition_weight
            )
        else:
            transition_candidate = current_camera_position.lerp(
                desired,
                transition_weight
            )
        var transition_exclude: Array[RID] = []
        if target is CollisionObject3D:
            transition_exclude.append((target as CollisionObject3D).get_rid())
        var transition_cast := _cast_camera_volume(
            current_camera_position,
            transition_candidate,
            transition_exclude
        )
        if (
            transition_cast.safe_fraction >= 0.999
            and _candidate_has_subject_clearance(transition_candidate)
        ):
            return transition_candidate

    # Raw aim follows input immediately. The visible lens normally follows the
    # requested boom, but a close-wall branch change slews between fully legal
    # rays while the gun/reticle keep the player's yaw and pitch authoritative.
    # Outward release remains damped to prevent a wall-exit pop.
    var current_length: float = current_offset.length()
    var current_direction: Vector3 = (
        current_offset / current_length
        if current_length > 0.001
        else desired_offset.normalized()
    )
    var desired_direction: Vector3 = desired_offset.normalized()
    var next_direction := desired_direction
    var branch_angle: float = acos(clampf(
        current_direction.dot(desired_direction),
        -1.0,
        1.0
    ))
    var branch_transition: bool = (
        close_context and branch_angle > deg_to_rad(0.5)
    )
    if (
        branch_transition
        and not near_body_crop_active
        and not _projection_is_reframeable(
            _subject_projection(current_camera_position)
        )
    ):
        # Keep traversing toward the current readable endpoint. Rejecting every
        # intermediate cropped frame is what converted a short transition into
        # a permanent wall hold.
        transition_crop_active = true
    if branch_transition:
        var maximum_angle_step: float = (
            deg_to_rad(float(profile.wall_branch_max_angular_speed_deg)) * delta
        )
        next_direction = current_direction.slerp(
            desired_direction,
            minf(1.0, maximum_angle_step / maxf(branch_angle, 0.0001))
        ).normalized()
    var next_length: float = desired_length
    if desired_length > current_length:
        var release_response: float = (
            profile.collision_release_radial_response
            if close_context
            else open_response
        )
        var release_speed: float = (
            profile.collision_release_max_radial_speed
            if close_context
            else profile.collision_max_radial_speed
        )
        var release_step: float = (desired_length - current_length) * (
            1.0 - exp(-release_response * delta)
        )
        release_step = minf(release_step, release_speed * delta)
        next_length = minf(current_length + release_step, desired_length)

    var candidate: Vector3 = anchor + next_direction * next_length
    # Constrained outward/sideways recovery is speed-limited here. The final
    # presentation invariant below also catches any emergency solver branch
    # that would otherwise bypass this local slew.
    if (
        branch_transition
        or (close_context and desired_length >= current_length - 0.001)
    ):
        var candidate_motion := candidate - current_camera_position
        var maximum_linear_step: float = (
            profile.wall_branch_max_linear_speed * delta
        )
        if candidate_motion.length() > maximum_linear_step:
            candidate = (
                current_camera_position
                + candidate_motion.normalized() * maximum_linear_step
            )
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())
    var candidate_cast := _cast_camera_volume(anchor, candidate, exclude)
    var candidate_projection := _subject_projection(candidate)
    var candidate_readable: bool = _candidate_is_subject_readable(candidate)
    # Close shots may intentionally crop the lower body, but they may never
    # use that crop permission to lose the operator horizontally. That stale
    # branch was what left the lens parked on a wall while the player moved on.
    if near_body_crop_active or transition_crop_active:
        candidate_readable = (
            bool(candidate_projection.visible)
            and _projection_keeps_horizontal_subject(candidate_projection)
        )
    if branch_transition and not near_body_crop_active and not transition_crop_active:
        candidate_readable = _projection_is_reframeable(
            _subject_projection(candidate)
        )
    if (
        not near_body_crop_active
        and (collision_crane_active or collision_crane_view_amount > 0.01)
    ):
        candidate_readable = _projection_is_reframeable(
            _subject_projection_to(
                candidate,
                candidate + _perched_view_direction(
                    candidate,
                    collision_crane_look_ahead,
                    smoothstep(0.0, 1.0, collision_crane_view_amount)
                ) * profile.look_ahead_distance
            )
        )
    if (
        candidate_cast.safe_fraction >= 0.999
        and candidate_readable
    ):
        return candidate

    # A blocked intermediate angle does not make the solver's distant legal
    # endpoint safe to render this frame. Returning `desired` here used to
    # bypass the branch slew entirely and teleport the lens to the opposite
    # side of the operator. Retract on the currently rendered legal ray until
    # a continuous angular route opens. Aim remains authoritative through the
    # independent gun ray and bounded reticle while the camera clears the wall.
    if branch_transition:
        var continuity_length: float = maxf(
            profile.min_camera_target_distance + profile.camera_collision_radius,
            current_length - profile.wall_branch_max_linear_speed * delta
        )
        var continuity_candidate: Vector3 = anchor + current_direction * continuity_length
        var continuity_cast := _cast_camera_volume(
            anchor,
            continuity_candidate,
            exclude
        )
        var continuity_projection := _subject_projection(continuity_candidate)
        var continuity_readable := _projection_is_reframeable(
            continuity_projection
        )
        if near_body_crop_active:
            continuity_readable = (
                bool(continuity_projection.visible)
                and _projection_keeps_horizontal_subject(continuity_projection)
            )
        if not near_body_crop_active and collision_crane_view_amount > 0.01:
            continuity_readable = _projection_is_reframeable(
                _subject_projection_to(
                    continuity_candidate,
                    continuity_candidate + _perched_view_direction(
                        continuity_candidate,
                        collision_crane_look_ahead,
                        smoothstep(0.0, 1.0, collision_crane_view_amount)
                    ) * profile.look_ahead_distance
                )
            )
        if (
            continuity_cast.safe_fraction >= 0.999
            and continuity_readable
        ):
            return continuity_candidate

        # The current world-space lens is the last known rendered shot. It is
        # preferable to hold one frame than cross geometry or snap branches.
        # This check is repeated against the live player anchor, so movement
        # cannot preserve a stale position after it ceases to be legal.
        var hold_cast := _cast_camera_volume(
            anchor,
            current_camera_position,
            exclude
        )
        var hold_readable := _projection_is_reframeable(
            _subject_projection(current_camera_position)
        )
        if collision_crane_view_amount > 0.01:
            hold_readable = _projection_is_reframeable(
                _subject_projection_to(
                    current_camera_position,
                    current_camera_position + _perched_view_direction(
                        current_camera_position,
                        collision_crane_look_ahead,
                        smoothstep(0.0, 1.0, collision_crane_view_amount)
                    ) * profile.look_ahead_distance
                )
            )
        if hold_cast.safe_fraction >= 0.999 and hold_readable:
            return current_camera_position
        # Never teleport to a distant solver branch merely because the
        # intermediate projection is cropped. The raw view still follows input
        # and the next frame recomputes a close virtual-boom or surface target.
        return current_camera_position
    return desired

func _smooth_surface_slide_position(
    anchor: Vector3,
    desired: Vector3,
    delta: float,
    wall_normal: Vector3
) -> Vector3:
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    var normal := wall_normal.normalized()
    var requested_motion: Vector3 = desired - current_camera_position
    if normal.length_squared() > 0.5:
        # Follow the virtual lens along the wall. Keep only the small normal
        # correction needed to settle on the constraint surface; never drive
        # farther into the blocker.
        var tangent_motion: Vector3 = requested_motion.slide(normal)
        var normal_motion: Vector3 = normal * maxf(
            requested_motion.dot(normal),
            0.0
        )
        requested_motion = tangent_motion + normal_motion

    var maximum_step: float = profile.wall_branch_max_linear_speed * delta
    if requested_motion.length() > maximum_step:
        requested_motion = requested_motion.normalized() * maximum_step
    var candidate := current_camera_position + requested_motion

    var local_cast := _cast_camera_volume(
        current_camera_position,
        candidate,
        exclude
    )
    var anchor_cast := _cast_camera_volume(anchor, candidate, exclude)
    if (
        local_cast.safe_fraction >= 0.999
        and anchor_cast.safe_fraction >= 0.999
        and _candidate_has_subject_clearance(candidate)
    ):
        return candidate

    # A corner may briefly block the tangent. Retract on the already legal
    # player-to-camera segment so the next frame can continue sliding. This is
    # bounded movement, not a world-space hold or opposite-side teleport.
    var current_offset: Vector3 = current_camera_position - anchor
    var current_length := current_offset.length()
    var minimum_length: float = (
        profile.min_camera_target_distance
        + profile.camera_collision_radius
    )
    if current_length > minimum_length + 0.001:
        var retracted_length := maxf(
            minimum_length,
            current_length - maximum_step
        )
        var retracted := anchor + current_offset.normalized() * retracted_length
        var retract_cast := _cast_camera_volume(anchor, retracted, exclude)
        if (
            retract_cast.safe_fraction >= 0.999
            and _candidate_has_subject_clearance(retracted)
        ):
            return retracted

    return current_camera_position

func _advance_local_lens_toward(
    from_position: Vector3,
    destination: Vector3,
    maximum_step: float,
    exclude: Array[RID]
) -> Vector3:
    var requested: Vector3 = destination - from_position
    var requested_length: float = requested.length()
    if requested_length < 0.001:
        return destination

    var step: float = minf(maximum_step, requested_length)
    var directions: Array[Vector3] = [requested.normalized()]
    var horizontal := Vector3(requested.x, 0.0, requested.z)
    if horizontal.length_squared() > 0.0001:
        var horizontal_direction := horizontal.normalized()
        for angle in [0.0, 45.0, -45.0, 90.0, -90.0, 135.0, -135.0, 180.0]:
            directions.append(
                horizontal_direction.rotated(Vector3.UP, deg_to_rad(float(angle)))
            )
    if absf(requested.y) > 0.001:
        directions.append(Vector3.UP * signf(requested.y))
    if absf(requested.x) > 0.001:
        directions.append(Vector3.RIGHT * signf(requested.x))
    if absf(requested.z) > 0.001:
        directions.append(Vector3.BACK * signf(requested.z))

    var from_projection := _subject_projection(from_position)
    var from_error := INF
    if bool(from_projection.visible):
        from_error = absf(float(from_projection.x) - current_head_target_x)
    var best_position := from_position
    var best_distance: float = requested_length
    var best_error: float = from_error
    for direction in directions:
        var candidate: Vector3 = from_position + direction.normalized() * step
        var local_cast := _cast_camera_volume(
            from_position,
            candidate,
            exclude
        )
        if local_cast.safe_fraction < 0.999:
            continue
        var candidate_clearance: bool = _candidate_has_subject_clearance(candidate)
        if not candidate_clearance:
            candidate_clearance = (
                near_body_crop_active
                and candidate.distance_to(target.global_position)
                    >= profile.camera_collision_radius + profile.collision_margin
            )
        if not candidate_clearance:
            continue
        var candidate_projection := _subject_projection(candidate)
        if not bool(candidate_projection.visible):
            continue
        var candidate_x: float = float(candidate_projection.x)
        var candidate_error: float = absf(candidate_x - current_head_target_x)
        # Inside the normal ownership guard, prefer progress toward the legal
        # endpoint. Outside it, every accepted micro-step must actively recover
        # the operator toward screen center.
        if (
            (candidate_x < 0.18 or candidate_x > 0.82)
            and candidate_error >= from_error - 0.0001
        ):
            continue
        var remaining: float = candidate.distance_to(destination)
        var recovering_horizontal: bool = (
            from_error > profile.rendered_head_soft_limit_x
        )
        if (
            (recovering_horizontal and candidate_error < best_error - 0.0001)
            or (
                not recovering_horizontal
                and remaining < best_distance - 0.0001
            )
        ):
            best_distance = remaining
            best_error = candidate_error
            best_position = candidate
    return best_position

func _preferred_position() -> Vector3:
    return preferred_shot_solver.preferred_position()

func _low_stance_amount() -> float:
    return preferred_shot_solver.low_stance_amount()

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

func _update_reticle_position(_delta: float) -> void:
    # The shot reticle is authoritative and permanently centered. Mouse input
    # moves only the transient blue indicator; camera collision owns neither.
    if mouse_aim_string_enabled:
        reticle_dynamic_amount = 0.0
        reticle_screen_normalized = Vector2(0.5, 0.5)
        return
    if not mouse_cursor_cage_enabled:
        reticle_dynamic_amount = 0.0
        reticle_screen_normalized = Vector2(0.5, 0.5)
        return
    reticle_dynamic_amount = maxf(
        absf(mouse_cursor_deflection.x),
        absf(mouse_cursor_deflection.y)
    )
    reticle_screen_normalized = get_mouse_cursor_screen_normalized()

func get_mouse_cursor_screen_normalized() -> Vector2:
    return Vector2(0.5, 0.5) + Vector2(
        mouse_cursor_deflection.x * profile.mouse_cage_half_width,
        mouse_cursor_deflection.y * profile.mouse_cage_half_height
    )

func get_debug_data() -> Dictionary:
    return CameraDebugSnapshotScript.build(self)

func _damp(current: float, target_val: float, rate: float, dt: float) -> float:
    return lerpf(current, target_val, 1.0 - exp(-rate * dt))

func _damp_angle(current: float, target_val: float, rate: float, dt: float) -> float:
    var diff := fposmod(target_val - current + PI, TAU) - PI
    return current + diff * (1.0 - exp(-rate * dt))

func set_aim_angles(new_yaw: float, new_pitch: float, snap_orbit: bool = false) -> void:
    aim_yaw = wrapf(new_yaw, -PI, PI)
    aim_pitch = clampf(
        new_pitch,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )
    mouse_intent_yaw = aim_yaw
    mouse_intent_pitch = aim_pitch
    if snap_orbit or not orbit_drag_enabled:
        yaw = aim_yaw
        pitch = aim_pitch

func set_orbit_trail_enabled(enabled: bool) -> void:
    orbit_drag_enabled = enabled
    if not orbit_drag_enabled:
        yaw = aim_yaw
        pitch = aim_pitch

func _sync_aim_to_orbit() -> void:
    aim_yaw = wrapf(yaw, -PI, PI)
    aim_pitch = clampf(
        pitch,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )
    mouse_intent_yaw = aim_yaw
    mouse_intent_pitch = aim_pitch

func set_mouse_aim_string_enabled(enabled: bool) -> void:
    mouse_aim_string_enabled = enabled
    mouse_aim_model.reset(Vector2(aim_yaw, aim_pitch))
    _update_reticle_position(0.0)
    if enabled:
        set_mouse_cursor_cage_enabled(false)

func _apply_raw_mouse_input(relative_motion: Vector2) -> void:
    aim_input_controller.activate_mouse(Vector2(aim_yaw, aim_pitch))
    set_aim_angles(
        aim_yaw - relative_motion.x * profile.mouse_sensitivity,
        aim_pitch - relative_motion.y * profile.mouse_sensitivity
    )

func _apply_mouse_aim_string_input(relative_motion: Vector2) -> void:
    aim_input_controller.apply_mouse_motion(
        relative_motion,
        Vector2(aim_yaw, aim_pitch),
        profile
    )

func _update_mouse_aim_string(delta: float) -> void:
    var current_aim := Vector2(aim_yaw, aim_pitch)
    var updated_aim: Vector2 = aim_input_controller.update_mouse_aim(
        current_aim,
        delta,
        profile
    )
    mouse_edge_turn = mouse_aim_model.aim_error_normalized(current_aim, profile)
    aim_yaw = updated_aim.x
    aim_pitch = updated_aim.y
    _update_reticle_position(delta)

func _update_controller_aim(delta: float) -> void:
    var updated_aim: Vector2 = aim_input_controller.update_controller_aim(
        Vector2(aim_yaw, aim_pitch),
        aim_input_controller.controller_stick(),
        delta,
        profile
    )
    aim_yaw = updated_aim.x
    aim_pitch = updated_aim.y
    mouse_edge_turn = Vector2.ZERO
    _update_reticle_position(delta)

func is_controller_aim_active() -> bool:
    return aim_input_controller.is_controller_active()

func get_active_aim_device_name() -> String:
    return aim_input_controller.active_device_name()

func get_mouse_string_screen_normalized() -> Vector2:
    return mouse_aim_model.target_screen_normalized(
        get_viewport().get_visible_rect().size
    )

func get_operator_alignment_screen_normalized() -> Vector2:
    return get_mouse_string_screen_normalized()

func _update_orbit_trail(delta: float, scoped_view: bool) -> void:
    var dt := clampf(delta, 0.0, 0.05)
    var yaw_rate: float = (
        profile.scoped_orbit_yaw_response
        if scoped_view
        else profile.orbit_yaw_response
    )
    var pitch_rate: float = (
        profile.scoped_orbit_pitch_response
        if scoped_view
        else profile.orbit_pitch_response
    )
    yaw = _damp_angle(yaw, aim_yaw, yaw_rate, dt)
    pitch = _damp(pitch, aim_pitch, pitch_rate, dt)

func set_mouse_cursor_cage_enabled(enabled: bool) -> void:
    mouse_cursor_cage_enabled = enabled
    if enabled:
        mouse_aim_string_enabled = false
    mouse_cursor_deflection = Vector2.ZERO
    mouse_edge_turn = Vector2.ZERO
    _update_reticle_position(0.0)

func _accumulate_mouse_cursor(relative_motion: Vector2) -> void:
    var viewport_size := get_viewport().get_visible_rect().size
    var half_extent_pixels := Vector2(
        maxf(viewport_size.x * profile.mouse_cage_half_width, 1.0),
        maxf(viewport_size.y * profile.mouse_cage_half_height, 1.0)
    )
    mouse_cursor_deflection += Vector2(
        relative_motion.x / half_extent_pixels.x,
        relative_motion.y / half_extent_pixels.y
    )
    mouse_cursor_deflection.x = clampf(mouse_cursor_deflection.x, -1.0, 1.0)
    mouse_cursor_deflection.y = clampf(mouse_cursor_deflection.y, -1.0, 1.0)
    _update_reticle_position(0.0)

func _update_mouse_cursor_turn(delta: float) -> void:
    mouse_edge_turn = Vector2(
        _mouse_edge_axis(mouse_cursor_deflection.x),
        _mouse_edge_axis(mouse_cursor_deflection.y)
    )
    var dt := clampf(delta, 0.0, 0.05)
    aim_yaw = wrapf(
        aim_yaw - deg_to_rad(profile.mouse_edge_yaw_speed_deg) * mouse_edge_turn.x * dt,
        -PI,
        PI
    )
    aim_pitch = clampf(
        aim_pitch - deg_to_rad(profile.mouse_edge_pitch_speed_deg) * mouse_edge_turn.y * dt,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )

func _mouse_edge_axis(value: float) -> float:
    var magnitude := absf(value)
    if magnitude <= profile.mouse_edge_turn_start:
        return 0.0
    var normalized := inverse_lerp(profile.mouse_edge_turn_start, 1.0, magnitude)
    return signf(value) * pow(normalized, profile.mouse_edge_turn_curve)

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

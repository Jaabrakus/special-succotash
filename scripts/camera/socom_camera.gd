class_name SocomCameraRig
extends Node3D

const AimIntentScript := preload("res://scripts/network/socom_aim_intent.gd")
const CameraProfileScript := preload("res://scripts/camera/camera_profile.gd")
const VIRTUAL_WALL_OBSERVER_LAYER := 19

enum CameraState {
    PREFERRED,
    COMPRESSED,
    POST_SOLVED,
    PERCHED,
    RELEASE
}

var target: Node3D
var head_marker: Node3D
var torso_marker: Node3D
var pelvis_marker: Node3D
var feet_marker: Node3D
var profile := CameraProfileScript.new()

var yaw: float = 0.0
var pitch: float = deg_to_rad(-2.0)
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
var virtual_wall_occluder: Node3D
var virtual_wall_original_layers: Dictionary = {}

var camera: Camera3D
var orbit_input_enabled: bool = true
var automated_wall_turn: bool = false

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
    Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _unhandled_input(event: InputEvent) -> void:
    if orbit_input_enabled and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
        yaw -= event.relative.x * profile.mouse_sensitivity
        pitch -= event.relative.y * profile.mouse_sensitivity
        pitch = clampf(pitch, deg_to_rad(profile.pitch_min_deg), deg_to_rad(profile.pitch_max_deg))
    elif event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
        Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
    elif orbit_input_enabled and event is InputEventMouseButton and event.pressed:
        Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

func _physics_process(delta: float) -> void:
    if target == null or camera == null:
        return

    if Input.is_action_just_pressed("reset_camera"):
        yaw = target.global_rotation.y
        pitch = deg_to_rad(-2.0)
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
            profile.wall_branch_max_linear_speed * delta
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

    # A rendered lens can never remain at an obsolete world-space wall point
    # after the player has left. Normal motion is handled by the translation
    # follower above; this tether is the spawn/teleport and impossible-route
    # invariant. A fresh collision solve is always safer than a multi-second
    # stale camera hold.
    camera_tether_rebased = false
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
    _update_reticle_position(delta)

func reset_camera_to_target() -> void:
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
    var rendered_projection := _subject_projection(rendered_position)
    var rendered_visible: bool = bool(rendered_projection.visible)
    var rendered_error: float = INF
    if rendered_visible:
        rendered_error = absf(
            float(rendered_projection.x) - current_head_target_x
        )
    if rendered_error <= profile.rendered_head_soft_limit_x:
        return rendered_position

    var recovery_position := legal_position
    if collision_active and virtual_camera_position != Vector3.ZERO:
        var virtual_projection := _subject_projection(
            virtual_camera_position,
            true
        )
        if bool(virtual_projection.visible):
            recovery_position = virtual_camera_position
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
        var local_recovery := _advance_local_lens_toward(
            rendered_position,
            recovery_position,
            profile.wall_branch_max_linear_speed * delta,
            exclude
        )
        if local_recovery != rendered_position:
            return local_recovery
        # There is no continuous physical route when the desired orbit crosses
        # the wall plane itself. Continue the post-solved virtual lens through
        # that infinitesimal transition instead of freezing input or cutting to
        # the far branch. Rendering/visibility policy owns the occluder; weapon
        # and multiplayer authority remain tied to the player-side rays.
        return _virtual_composition_step(
            rendered_position,
            recovery_position,
            profile.wall_branch_max_linear_speed * delta
        )

    # Begin the virtual crossing at the soft guard, before the operator reaches
    # the edge. A topological wall crossing can briefly move sideways before it
    # improves projection, so requiring every intermediate step to score better
    # recreates the freeze.
    return _virtual_composition_step(
        rendered_position,
        recovery_position,
        profile.composition_recovery_speed * delta
    )

func _virtual_composition_step(
    from_position: Vector3,
    destination: Vector3,
    maximum_step: float
) -> Vector3:
    # A straight chord between a compressed wall lens and the preferred boom
    # can be too close and too high midway through the crossing. Clear the wall
    # plane at the already readable height first, then settle vertically once
    # the preferred horizontal boom is close.
    var horizontal_destination := Vector3(
        destination.x,
        from_position.y,
        destination.z
    )
    var horizontal_distance := Vector2(
        destination.x - from_position.x,
        destination.z - from_position.z
    ).length()
    if horizontal_distance > profile.wall_branch_transition_distance:
        return from_position.move_toward(
            horizontal_destination,
            maximum_step
        )
    return from_position.move_toward(destination, maximum_step)

func _follow_target_translation() -> void:
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
    current_camera_position += applied_motion
    if last_readable_post_solve_position != Vector3.ZERO:
        last_readable_post_solve_position += applied_motion

func _update_virtual_wall_occluder() -> void:
    if target == null or current_camera_position == Vector3.ZERO:
        _set_virtual_wall_occluder(null)
        return
    var virtual_separation := current_camera_position.distance_to(
        collision_camera_position
    )
    if not collision_active or virtual_separation < 0.20:
        _set_virtual_wall_occluder(null)
        return
    _set_virtual_wall_occluder(collision_blocker_node)

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
    collision_camera_position = result.position
    collision_active = result.collided
    collision_name = result.collider_name
    collision_blocker_node = result.get("collider_node") as Node3D
    wall_escape_active = result.escaped
    wall_escape_angle_deg = result.escape_angle_deg
    local_cutout_active = result.local_cutout
    local_cutout_center = result.cutout_center
    local_cutout_node = result.cutout_node
    collision_crane_active = bool(result.get("crane_active", false))
    surface_slide_active = bool(result.get("surface_slide_active", false))
    surface_slide_normal = result.get("surface_slide_normal", Vector3.ZERO)
    near_body_crop_active = bool(result.get("near_body_crop_active", false))
    if collision_crane_active:
        collision_crane_look_ahead = float(result.get(
            "crane_look_ahead",
            profile.close_wall_crane_default_look_ahead
        ))

func _update_collision_crane_view(delta: float) -> void:
    # The old branch-transition feedback kept this blend at 100% whenever the
    # rendered and requested lenses stayed apart. That turned a one-frame
    # continuity hold into a permanent camera-orientation lock.
    var view_target: float = 1.0 if collision_crane_active else 0.0
    var response: float = (
        profile.close_wall_crane_enter_response
        if view_target > 0.5
        else profile.close_wall_crane_exit_response
    )
    collision_crane_view_amount = lerpf(
        collision_crane_view_amount,
        view_target,
        1.0 - exp(-response * delta)
    )

func _update_wall_camera_state(delta: float) -> void:
    var context_target: float = 1.0 if collision_active else 0.0
    var context_response: float = (
        profile.wall_context_enter_response
        if collision_active
        else profile.wall_context_exit_response
    )
    wall_context_amount = lerpf(
        wall_context_amount,
        context_target,
        1.0 - exp(-context_response * delta)
    )


func _update_deterministic_camera_state(delta: float) -> void:
    camera_state_age += delta
    var requested := CameraState.PREFERRED
    if collision_crane_active or collision_crane_view_amount >= 0.55:
        requested = CameraState.PERCHED
    elif collision_active and post_collision_reframe:
        requested = CameraState.POST_SOLVED
    elif collision_active:
        requested = CameraState.COMPRESSED
    elif (
        camera_state != CameraState.PREFERRED
        and (
            wall_context_amount > 0.04
            or current_camera_position.distance_to(collision_camera_position)
                > profile.wall_branch_transition_distance
        )
    ):
        requested = CameraState.RELEASE

    if requested == camera_state:
        return

    # Obstruction entry is immediate for fairness. Non-safety transitions use
    # a short dwell so noisy solver labels cannot produce A/B/A camera states.
    var safety_entry: bool = (
        requested == CameraState.COMPRESSED
        or requested == CameraState.POST_SOLVED
        or requested == CameraState.PERCHED
    )
    if not safety_entry and camera_state_age < 0.12:
        return
    camera_state = requested
    camera_state_age = 0.0
    camera_state_transition_count += 1


func get_camera_state_name() -> String:
    match camera_state:
        CameraState.PREFERRED:
            return "PREFERRED"
        CameraState.COMPRESSED:
            return "COMPRESSED"
        CameraState.POST_SOLVED:
            return "POST-SOLVED"
        CameraState.PERCHED:
            return "PERCHED"
        CameraState.RELEASE:
            return "RELEASE"
    return "UNKNOWN"


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
        directions.append(horizontal_direction)
        directions.append(horizontal_direction.rotated(Vector3.UP, PI * 0.5))
        directions.append(horizontal_direction.rotated(Vector3.UP, -PI * 0.5))
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
    for direction in directions:
        var candidate: Vector3 = from_position + direction.normalized() * step
        var local_cast := _cast_camera_volume(
            from_position,
            candidate,
            exclude
        )
        if (
            local_cast.safe_fraction < 0.999
            or not _candidate_has_subject_clearance(candidate)
        ):
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
        if remaining < best_distance - 0.0001:
            best_distance = remaining
            best_position = candidate
    return best_position

func _preferred_position() -> Vector3:
    var anchor := target.global_position + movement_lead + Vector3.UP * 1.05
    var yaw_basis := Basis(Vector3.UP, yaw)
    var back := yaw_basis * Vector3.BACK
    var side := yaw_basis * Vector3.RIGHT

    var forward := yaw_basis * Vector3.FORWARD
    var base_distance: float = lerpf(profile.distance, profile.interior_distance, interior_amount)
    var base_height: float = lerpf(profile.height, profile.interior_height, interior_amount)
    var base_shoulder: float = lerpf(
        profile.shoulder_offset,
        profile.interior_shoulder_offset,
        interior_amount
    )
    var shot_distance: float = lerpf(base_distance, profile.downward_distance, downward_crane_amount)
    var shot_height: float = lerpf(base_height, profile.downward_height, downward_crane_amount)
    var shot_shoulder: float = lerpf(
        base_shoulder,
        profile.downward_shoulder_offset,
        downward_crane_amount
    )
    return (
        anchor
        + back * shot_distance
        + Vector3.UP * (
            shot_height
            + downward_crane_amount * profile.max_downward_camera_raise
            + downward_ledge_raise
        )
        + forward * (downward_crane_amount * profile.max_downward_camera_forward)
        + side * (shot_shoulder + downward_crane_amount * profile.max_downward_camera_side)
    )

func _low_stance_amount() -> float:
    if target == null or head_marker == null:
        return 0.0
    var head_height: float = head_marker.global_position.y - target.global_position.y
    var stance_range: float = maxf(
        profile.low_stance_head_height_start - profile.low_stance_head_height_full,
        0.001
    )
    return clampf(
        (profile.low_stance_head_height_start - head_height) / stance_range,
        0.0,
        1.0
    )

func _update_environment_state(delta: float) -> void:
    overhead_confinement = _measure_overhead_confinement()
    var target_interior: float = smoothstep(0.08, 0.62, overhead_confinement)
    interior_amount = lerpf(
        interior_amount,
        target_interior,
        1.0 - exp(-profile.interior_state_response * delta)
    )

func _calculate_downward_aim_amount() -> float:
    var pitch_deg: float = rad_to_deg(pitch)
    var pitch_range: float = maxf(
        absf(profile.downward_aim_full_deg - profile.downward_aim_start_deg),
        0.001
    )
    return clampf(
        (profile.downward_aim_start_deg - pitch_deg) / pitch_range,
        0.0,
        1.0
    )

func _forward_direction() -> Vector3:
    var yaw_basis := Basis(Vector3.UP, yaw)
    var yaw_forward := yaw_basis * Vector3.FORWARD
    var right := yaw_basis * Vector3.RIGHT
    var pitch_basis := Basis(right, _composed_view_pitch())
    return (pitch_basis * yaw_forward).normalized()

func _composed_view_pitch() -> float:
    var interior_bias: float = (
        deg_to_rad(profile.interior_view_pitch_bias_deg)
        * interior_amount
        * (1.0 - downward_aim_amount)
    )
    return clampf(
        pitch + interior_bias,
        deg_to_rad(profile.pitch_min_deg),
        deg_to_rad(profile.pitch_max_deg)
    )

func _look_target() -> Vector3:
    # Converge the rendered optical axis on the same camera-independent point
    # used by the weapon. At normal ranges this preserves raw yaw/pitch while
    # removing the parallel-ray mismatch visible in the workbench.
    if aim_point != Vector3.ZERO and global_position.distance_to(aim_point) > 0.1:
        return aim_point
    return global_position + _forward_direction() * profile.look_ahead_distance

func _look_target_from(camera_position: Vector3, _force_collision_context: bool = false) -> Vector3:
    if aim_point != Vector3.ZERO and camera_position.distance_to(aim_point) > 0.1:
        return aim_point
    return camera_position + _forward_direction() * profile.look_ahead_distance

func _close_wall_aim_point(look_ahead: float) -> Vector3:
    return (
        target.global_position
        + movement_lead
        + Vector3.UP * profile.look_height
        + _forward_direction() * look_ahead
    )

func _perched_view_direction(
    camera_position: Vector3,
    look_ahead: float,
    horizontal_correction: float = 1.0
) -> Vector3:
    # Wall composition is horizontal only. Raw pitch is copied exactly so
    # collision can never force the player to look at the floor or ceiling.
    var raw_direction := _forward_direction()
    var raw_flat := Vector3(raw_direction.x, 0.0, raw_direction.z).normalized()
    var convergence_delta := _close_wall_aim_point(look_ahead) - camera_position
    var convergence_flat := Vector3(
        convergence_delta.x,
        0.0,
        convergence_delta.z
    ).normalized()
    if convergence_flat.length_squared() < 0.0001:
        convergence_flat = raw_flat
    var corrected_flat := raw_flat.slerp(
        convergence_flat,
        clampf(horizontal_correction, 0.0, 1.0)
    ).normalized()
    var horizontal_length := sqrt(maxf(1.0 - raw_direction.y * raw_direction.y, 0.0))
    return (
        corrected_flat * horizontal_length
        + Vector3.UP * raw_direction.y
    ).normalized()

func _solve_collision(desired: Vector3) -> Dictionary:
    var anchor: Vector3 = target.global_position + Vector3.UP * float(profile.collision_anchor_height)
    var space := get_world_3d().direct_space_state
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    var desired_cast := _cast_camera_volume(anchor, desired, exclude)
    if desired_cast.safe_fraction >= 0.999:
        return {
            "position": desired,
            "collided": false,
            "collider_name": "CLEAR",
            "collider_node": null,
            "escaped": false,
            "escape_angle_deg": 0.0,
            "local_cutout": false,
            "cutout_center": Vector3.ZERO,
            "cutout_node": null
        }

    var collider_name := "CAMERA VOLUME"
    var collider_node: Node3D = null
    var hit_query := PhysicsRayQueryParameters3D.create(anchor, desired)
    hit_query.exclude = exclude
    hit_query.collide_with_areas = false
    var center_hit: Dictionary = space.intersect_ray(hit_query)
    if not center_hit.is_empty():
        var collider: Variant = center_hit.get("collider")
        if collider is Node:
            collider_name = str((collider as Node).name)
            if collider is Node3D:
                collider_node = collider as Node3D
        elif collider is Object:
            collider_name = (collider as Object).get_class()

    # Classic third-person boom: spend distance on the existing camera ray
    # before considering any lateral movement. This is deterministic, cheap,
    # and keeps input rotation separate from collision response.
    var desired_offset: Vector3 = desired - anchor
    var safe_fraction: float = clampf(float(desired_cast.safe_fraction), 0.0, 1.0)
    var compressed_position: Vector3 = anchor + desired_offset * safe_fraction
    var compressed_projection := _subject_projection(compressed_position, true)
    if (
        _candidate_has_subject_clearance(compressed_position)
        and _projection_is_reframeable(compressed_projection)
    ):
        return {
            "position": compressed_position,
            "collided": true,
            "collider_name": "%s / BOOM COMPRESSED" % collider_name,
            "collider_node": collider_node,
            "escaped": false,
            "escape_angle_deg": 0.0,
            "local_cutout": false,
            "cutout_center": Vector3.ZERO,
            "cutout_node": null
        }

    # If the direct compressed shot cannot retain the character, test a tiny
    # PS2-style correction set. Outdoor walls get a few deterministic lateral
    # candidates so the lens can remain behind the operator instead of entering
    # the head. Enclosed rooms stay vertical-only, preventing the old shoulder
    # jump and opposite-side flip regression.
    var micro_offsets: Array[Vector3] = [
        Vector3.UP * 0.20,
        Vector3.UP * 0.40,
        Vector3.UP * 0.60,
        Vector3.UP * 0.90,
        Vector3.UP * 1.20,
        Vector3.UP * 1.50,
        Vector3.DOWN * 0.20
    ]
    var camera_right: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
    var micro_destinations: Array[Vector3] = []
    for adjustment in micro_offsets:
        micro_destinations.append(compressed_position + adjustment)
    # Outdoor side escape must begin from the desired boom. Offsetting an
    # already-crushed lens leaves it beside the head; offsetting the desired
    # shot lets the volume cast recover the proven ~3 m close-wall position.
    if overhead_confinement < 0.25:
        for side_value in [0.25, 0.45]:
            var side: float = float(side_value)
            micro_destinations.append(desired + camera_right * side)
            micro_destinations.append(desired + camera_right * -side)
            micro_destinations.append(
                desired + Vector3.UP * 0.30 + camera_right * side
            )
            micro_destinations.append(
                desired + Vector3.UP * 0.30 + camera_right * -side
            )
    # If the compressed lens is resting on the blocker, rising from that exact
    # boundary can still graze it. Try progressively shorter versions of the
    # same boom with extra height—the classic closer-and-higher wall response.
    for boom_scale_value in [0.85, 0.70, 0.55]:
        var boom_scale: float = float(boom_scale_value)
        for lift_value in [0.30, 0.60, 0.90, 1.20]:
            var lift: float = float(lift_value)
            micro_destinations.append(
                anchor + (compressed_position - anchor) * boom_scale + Vector3.UP * lift
            )
    var best_candidate := Vector3.ZERO
    var best_score := INF
    var best_side_amount: float = 0.0
    for adjusted_destination in micro_destinations:
        # Every correction is re-cast as a camera volume. Vertical corrections
        # originate at the compressed lens; outdoor side corrections originate
        # at the desired boom so they can recover useful subject distance.
        var adjusted_cast := _cast_camera_volume(anchor, adjusted_destination, exclude)
        var candidate: Vector3 = anchor + (
            adjusted_destination - anchor
        ) * clampf(float(adjusted_cast.safe_fraction), 0.0, 1.0)
        if not _candidate_has_subject_clearance(candidate):
            continue
        var projection := _subject_projection(candidate, true)
        if not _projection_is_reframeable(projection):
            continue
        var composition_cost: float = (
            absf(float(projection.x) - current_head_target_x) * 10.0
            + absf(float(projection.y) - current_head_target_y) * 4.0
        )
        var correction_cost: float = adjusted_destination.distance_to(compressed_position) * 0.75
        var score: float = composition_cost + correction_cost
        if score < best_score:
            best_score = score
            best_candidate = candidate
            best_side_amount = (candidate - compressed_position).dot(camera_right)

    if best_score < INF:
        var escaped_sideways: bool = absf(best_side_amount) > 0.01
        var escape_angle: float = 0.0
        if escaped_sideways:
            var boom_length: float = maxf(
                (compressed_position - anchor).length(),
                0.001
            )
            escape_angle = rad_to_deg(atan2(best_side_amount, boom_length))
        return {
            "position": best_candidate,
            "collided": true,
            "collider_name": "%s / MICRO ADJUST" % collider_name,
            "collider_node": collider_node,
            "escaped": escaped_sideways,
            "escape_angle_deg": escape_angle,
            "local_cutout": false,
            "cutout_center": Vector3.ZERO,
            "cutout_node": null
        }

    # Physical fallback remains on the current requested boom ray. Never reuse
    # a readable position from an older yaw, because that would make collision
    # lag or consume the player's turn input.
    return {
        "position": compressed_position,
        "collided": true,
        "collider_name": "%s / PHYSICAL CLOSE" % collider_name,
        "collider_node": collider_node,
        "escaped": false,
        "escape_angle_deg": 0.0,
        "local_cutout": false,
        "cutout_center": Vector3.ZERO,
        "cutout_node": null
    }

func _solve_better_post_collision(
    initial_result: Dictionary,
    requested_position: Vector3
) -> Dictionary:
    var anchor: Vector3 = target.global_position + Vector3.UP * float(profile.collision_anchor_height)
    var exclude: Array[RID] = []
    if target is CollisionObject3D:
        exclude.append((target as CollisionObject3D).get_rid())

    var initial_position: Vector3 = initial_result.position
    var best_position: Vector3 = initial_position
    var best_projection := _subject_projection(initial_position, true)
    var best_score: float = _post_solve_projection_score(best_projection)
    var best_is_readable: bool = (
        _candidate_has_subject_clearance(initial_position)
        and _projection_is_reframeable(best_projection)
        and _projection_keeps_horizontal_subject(best_projection)
    )
    var best_escape_angle: float = float(initial_result.escape_angle_deg)
    var surface_slide_solved: bool = false
    var near_body_crop_solved: bool = false
    var solved_surface_normal := Vector3.ZERO

    # Low rooms keep the established centerline-only behavior. Their regular
    # post-pass normally succeeds; these vertical candidates are a final legal
    # refinement without reintroducing corner-to-corner shoulder jumps.
    var desired_offset: Vector3 = requested_position - anchor
    var orbit_angles: Array[float] = [0.0]
    if overhead_confinement < 0.25:
        orbit_angles = [
            0.0,
            18.0, -18.0,
            36.0, -36.0,
            60.0, -60.0
        ]
    var radius_scales: Array[float] = [1.0, 0.70]
    var lift_offsets: Array[float] = [0.0, 0.60]
    for angle_deg in orbit_angles:
        var rotated_offset: Vector3 = (
            Basis(Vector3.UP, deg_to_rad(angle_deg)) * desired_offset
        )
        for radius_scale in radius_scales:
            for lift in lift_offsets:
                var destination: Vector3 = (
                    anchor
                    + rotated_offset * radius_scale
                    + Vector3.UP * lift
                )
                var candidate_cast := _cast_camera_volume(anchor, destination, exclude)
                if candidate_cast.safe_fraction < 0.999:
                    continue
                if not _candidate_has_subject_clearance(destination):
                    continue
                var projection := _subject_projection(destination, true)
                if not _projection_is_reframeable(projection):
                    continue
                if not _projection_keeps_horizontal_subject(projection):
                    continue
                var score: float = _post_solve_projection_score(projection)
                score += absf(angle_deg) * 0.012
                score += absf(1.0 - radius_scale) * 0.35
                score += lift * 0.12
                if current_camera_position != Vector3.ZERO:
                    score += destination.distance_to(current_camera_position) * (
                        profile.post_solve_position_continuity_weight
                    )
                if not best_is_readable or score < best_score:
                    best_is_readable = true
                    best_score = score
                    best_position = destination
                    best_escape_angle = angle_deg

    # The coarse post-solve establishes a legal boom. Compose once more from
    # that position and probe a small local neighborhood, accepting only fully
    # volume-clear improvements. This is the "better post-solve" stage.
    if best_is_readable:
        var camera_right: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
        var refinement_destinations: Array[Vector3] = [
            _solve_framing(best_position),
            best_position + Vector3.UP * 0.15,
            best_position + Vector3.DOWN * 0.15,
            best_position + camera_right * 0.15,
            best_position + camera_right * -0.15,
            best_position + camera_right * 0.30,
            best_position + camera_right * -0.30,
            best_position + Vector3.UP * 0.15 + camera_right * 0.15,
            best_position + Vector3.UP * 0.15 + camera_right * -0.15
        ]
        for destination in refinement_destinations:
            var candidate_cast := _cast_camera_volume(anchor, destination, exclude)
            if candidate_cast.safe_fraction < 0.999:
                continue
            if not _candidate_has_subject_clearance(destination):
                continue
            var projection := _subject_projection(destination, true)
            if not _projection_is_reframeable(projection):
                continue
            if not _projection_keeps_horizontal_subject(projection):
                continue
            var score: float = _post_solve_projection_score(projection)
            score += destination.distance_to(best_position) * 0.08
            if current_camera_position != Vector3.ZERO:
                score += destination.distance_to(current_camera_position) * (
                    profile.post_solve_position_continuity_weight
                )
            if score < best_score:
                best_score = score
                best_position = destination

    # A readable endpoint is not a usable camera move when it sits on another
    # orbit branch behind the blocker. Keep following the close virtual boom
    # until the angular route opens instead of selecting a target that the
    # continuity stage can only hold against forever.
    if best_is_readable and current_camera_position != Vector3.ZERO:
        var current_offset := current_camera_position - anchor
        var best_offset := best_position - anchor
        if current_offset.length_squared() > 0.001 and best_offset.length_squared() > 0.001:
            var branch_angle := current_offset.normalized().angle_to(
                best_offset.normalized()
            )
            if (
                branch_angle > deg_to_rad(8.0)
                and current_camera_position.distance_to(best_position)
                    > profile.wall_branch_transition_distance
            ):
                best_is_readable = false

    # Treat the preferred lens as a free virtual camera. When that point lies
    # beyond a nearby wall, project it back onto the wall's player-facing
    # constraint plane. The resulting lens follows input continuously along
    # the surface instead of holding an older world-space camera position.
    if not best_is_readable and overhead_confinement < 0.25:
        var continuity_seed: Vector3 = current_camera_position
        if (
            continuity_seed == Vector3.ZERO
            or not _candidate_has_subject_clearance(continuity_seed)
        ):
            continuity_seed = last_readable_post_solve_position
        var surface_result := _solve_virtual_camera_surface(
            anchor,
            requested_position,
            continuity_seed,
            exclude
        )
        if bool(surface_result.get("found", false)):
            var surface_position: Vector3 = surface_result.position
            var surface_projection := _subject_projection(surface_position, true)
            if (
                _projection_is_reframeable(surface_projection)
                and _projection_keeps_horizontal_subject(surface_projection)
            ):
                best_position = surface_position
                best_projection = surface_projection
                best_is_readable = true
                surface_slide_solved = true
                solved_surface_normal = surface_result.normal
            else:
                # No surface point can preserve both view direction and the
                # operator. Follow the collision-safe compressed virtual boom
                # and crop only head geometry intersecting the near lens.
                best_position = initial_position
                best_projection = _subject_projection(initial_position, true)
                best_is_readable = true
                near_body_crop_solved = true

    # A wall-surface or orbit endpoint is not a valid tactical shot when raw
    # aim leaves the operator outside the horizontal composition guard. Fall
    # back to the collision-safe point on the current virtual boom instead of
    # preserving an old wall-side lens while the player orbits away from it.
    if not best_is_readable:
        best_position = initial_position
        best_projection = _subject_projection(initial_position, true)
        best_is_readable = true
        near_body_crop_solved = true

    var solved_result: Dictionary = initial_result.duplicate()
    solved_result.position = best_position
    solved_result.collided = true
    solved_result.escaped = absf(best_escape_angle) > 0.01
    solved_result.escape_angle_deg = best_escape_angle
    solved_result.crane_active = false
    solved_result.crane_look_ahead = profile.close_wall_crane_default_look_ahead
    solved_result.surface_slide_active = surface_slide_solved
    solved_result.surface_slide_normal = solved_surface_normal
    solved_result.near_body_crop_active = near_body_crop_solved
    var collision_base_name: String = str(initial_result.collider_name)
    collision_base_name = collision_base_name.replace(" / PHYSICAL CLOSE", "")
    if near_body_crop_solved:
        solved_result.collider_name = "%s / VIRTUAL BOOM CLOSE" % collision_base_name
    elif surface_slide_solved:
        solved_result.collider_name = "%s / VIRTUAL SURFACE SLIDE" % collision_base_name
    elif best_is_readable:
        solved_result.collider_name = "%s / BETTER POST-SOLVED" % collision_base_name
    else:
        # Geometry still owns the boundary, but the result remains inside the
        # post-solve pipeline and is reconsidered next frame rather than entering
        # a separate forced fallback mode.
        solved_result.collider_name = "%s / POST-SOLVED CONSTRAINED" % collision_base_name
    return solved_result

func _solve_virtual_camera_surface(
    anchor: Vector3,
    virtual_position: Vector3,
    continuity_seed: Vector3,
    exclude: Array[RID]
) -> Dictionary:
    surface_slide_candidate_count = 0
    surface_slide_clear_count = 0
    surface_slide_readable_count = 0
    surface_slide_target_x = -99.0
    surface_slide_target_y = -99.0
    var hit_query := PhysicsRayQueryParameters3D.create(anchor, virtual_position)
    hit_query.exclude = exclude
    hit_query.collide_with_areas = false
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(hit_query)
    if hit.is_empty():
        return {"found": false}

    var hit_position: Vector3 = hit.position
    var normal: Vector3 = hit.normal.normalized()
    if (anchor - hit_position).dot(normal) < 0.0:
        normal = -normal
    var skin: float = (
        profile.camera_collision_radius
        + profile.collision_margin
        + 0.015
    )
    var signed_distance: float = (virtual_position - hit_position).dot(normal)
    var projected_virtual := (
        virtual_position
        + normal * maxf(skin - signed_distance, 0.0)
    )

    # The primary point is the exact wall-plane projection. Retractions and a
    # small vertical assist handle corners and low cover without switching to a
    # separate orbit branch or changing view direction.
    var candidates: Array[Vector3] = [projected_virtual]
    var wall_tangent := Vector3.UP.cross(normal).normalized()
    if wall_tangent.length_squared() > 0.5:
        for tangent_value in [
            -3.00, -1.80, -0.60,
            0.60, 1.80, 3.00
        ]:
            var tangent_point := (
                projected_virtual
                + wall_tangent * float(tangent_value)
            )
            candidates.append(tangent_point)
            candidates.append(tangent_point + Vector3.DOWN * 0.25)
            candidates.append(tangent_point + Vector3.UP * 0.35)
    for scale_value in [0.90, 0.70, 0.54]:
        var scale: float = float(scale_value)
        var retracted := anchor + (projected_virtual - anchor) * scale
        candidates.append(retracted)
        candidates.append(retracted + Vector3.UP * 0.25)
        candidates.append(retracted + Vector3.UP * 0.75)

    var best := Vector3.ZERO
    var best_score := INF
    for candidate in candidates:
        surface_slide_candidate_count += 1
        var candidate_cast := _cast_camera_volume(anchor, candidate, exclude)
        if candidate_cast.safe_fraction < 0.999:
            continue
        surface_slide_clear_count += 1
        if not _candidate_has_subject_clearance(candidate):
            continue
        var projection := _subject_projection(candidate, true)
        var readable := _projection_is_reframeable(projection)
        if readable:
            surface_slide_readable_count += 1
        # A readable surface shot wins. If the wall makes that impossible, a
        # physically valid position that still tracks the virtual camera beats
        # freezing the lens indefinitely; the character may crop temporarily.
        var score: float = (
            _post_solve_projection_score(projection)
            if bool(projection.visible)
            else 100.0
        )
        if not readable:
            score += 25.0
        score += candidate.distance_to(projected_virtual) * 0.30
        if continuity_seed != Vector3.ZERO:
            score += candidate.distance_to(continuity_seed) * 0.08
        if score < best_score:
            best_score = score
            best = candidate
            surface_slide_target_x = float(projection.x)
            surface_slide_target_y = float(projection.y)

    return {
        "found": best_score < INF,
        "position": best,
        "normal": normal
    }

func _cast_camera_volume(anchor: Vector3, destination: Vector3, exclude: Array[RID]) -> Dictionary:
    collision_cast_count += 1
    var query := PhysicsShapeQueryParameters3D.new()
    query.shape = camera_collision_shape
    query.transform = Transform3D(Basis.IDENTITY, anchor)
    query.motion = destination - anchor
    query.margin = profile.collision_margin
    query.exclude = exclude
    query.collide_with_areas = false
    var cast_result: PackedFloat32Array = get_world_3d().direct_space_state.cast_motion(query)
    var safe_fraction: float = cast_result[0] if cast_result.size() >= 1 else 1.0
    return {"safe_fraction": safe_fraction}

func _subject_projection(candidate: Vector3, force_collision_context: bool = false) -> Dictionary:
    return _subject_projection_to(
        candidate,
        _look_target_from(candidate, force_collision_context)
    )

func _subject_projection_to(candidate: Vector3, look_target: Vector3) -> Dictionary:
    if head_marker == null or camera == null:
        return {"visible": true, "x": current_head_target_x, "y": current_head_target_y, "distance": 99.0}
    # Project analytically. The previous version temporarily moved and rotated
    # the live camera node for every candidate; a blocked boom can evaluate
    # hundreds of candidates, making close quarters visibly hitch.
    var direction := (look_target - candidate).normalized()
    if direction.length_squared() < 0.0001:
        return {"visible": false, "x": -99.0, "y": -99.0, "distance": 0.0}
    var candidate_basis := Basis.looking_at(direction, Vector3.UP, false)
    var local_head: Vector3 = candidate_basis.transposed() * (head_marker.global_position - candidate)
    var depth: float = -local_head.z
    var visible: bool = depth > camera.near
    var head_x := -99.0
    var head_y := -99.0
    if visible:
        var viewport_size := get_viewport().get_visible_rect().size
        var aspect: float = maxf(viewport_size.x, 1.0) / maxf(viewport_size.y, 1.0)
        var half_height: float = depth * tan(deg_to_rad(camera.fov) * 0.5)
        var half_width: float = half_height * aspect
        head_x = 0.5 + local_head.x / maxf(half_width * 2.0, 0.0001)
        head_y = 0.5 - local_head.y / maxf(half_height * 2.0, 0.0001)
    var head_distance: float = candidate.distance_to(head_marker.global_position)
    return {"visible": visible, "x": head_x, "y": head_y, "distance": head_distance}

func _projection_keeps_subject(projection: Dictionary) -> bool:
    if not bool(projection.visible):
        return false
    var head_tolerance_above: float = lerpf(0.22, 0.16, interior_amount)
    return (
        float(projection.distance) >= profile.min_subject_camera_distance
        and float(projection.x) >= current_head_target_x - 0.09
        and float(projection.x) <= current_head_target_x + 0.09
        and float(projection.y) >= current_head_target_y - head_tolerance_above
        and float(projection.y) <= current_head_target_y + 0.14
    )

func _projection_is_reframeable(projection: Dictionary) -> bool:
    return (
        bool(projection.visible)
        and float(projection.distance) >= profile.min_subject_camera_distance
        and float(projection.x) >= 0.05
        and float(projection.x) <= 0.95
        and float(projection.y) >= 0.05
        and float(projection.y) <= 0.98
    )

func _projection_keeps_horizontal_subject(projection: Dictionary) -> bool:
    return (
        bool(projection.visible)
        and float(projection.x) >= current_head_target_x - 0.12
        and float(projection.x) <= current_head_target_x + 0.12
    )

func _candidate_is_reframeable(candidate: Vector3) -> bool:
    return _projection_is_reframeable(_subject_projection(candidate))

func _post_solve_projection_score(projection: Dictionary) -> float:
    if not bool(projection.visible):
        return INF
    var distance: float = float(projection.distance)
    var score: float = (
        absf(float(projection.x) - current_head_target_x) * 10.0
        + absf(float(projection.y) - current_head_target_y) * 4.0
    )
    if distance < profile.min_subject_camera_distance:
        score += (profile.min_subject_camera_distance - distance) * 20.0
    return score

func _candidate_has_subject_clearance(candidate: Vector3) -> bool:
    if target == null or head_marker == null:
        return true
    return (
        candidate.distance_to(target.global_position) >= profile.min_camera_target_distance
        and candidate.distance_to(head_marker.global_position) >= profile.min_subject_camera_distance
    )

func _shares_current_camera_branch(candidate: Vector3) -> bool:
    if target == null or current_camera_position == Vector3.ZERO:
        return true
    var anchor := (
        target.global_position
        + Vector3.UP * float(profile.collision_anchor_height)
    )
    var current_offset := current_camera_position - anchor
    var candidate_offset := candidate - anchor
    if current_offset.length_squared() < 0.001 or candidate_offset.length_squared() < 0.001:
        return true
    var branch_angle := current_offset.normalized().angle_to(
        candidate_offset.normalized()
    )
    return (
        branch_angle <= deg_to_rad(8.0)
        or current_camera_position.distance_to(candidate)
            <= profile.wall_branch_transition_distance
    )

func _camera_marker_visibility(marker: Node3D) -> Dictionary:
    if marker == null or target == null:
        return {"visible": true, "blocker": "CLEAR"}
    var query := PhysicsRayQueryParameters3D.create(
        global_position,
        marker.global_position
    )
    query.collide_with_areas = false
    query.hit_from_inside = true
    if target is CollisionObject3D:
        query.exclude = [(target as CollisionObject3D).get_rid()]
    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return {"visible": true, "blocker": "CLEAR"}
    var collider: Variant = hit.get("collider")
    var blocker := "GEOMETRY"
    if collider is Node:
        blocker = str((collider as Node).name)
    elif collider is Object:
        blocker = (collider as Object).get_class()
    return {"visible": false, "blocker": blocker}

func _camera_subject_visibility() -> Dictionary:
    var head_result := _camera_marker_visibility(head_marker)
    var torso_result := _camera_marker_visibility(torso_marker)
    return {
        "head_visible": bool(head_result.visible),
        "head_blocker": str(head_result.blocker),
        "torso_visible": bool(torso_result.visible),
        "torso_blocker": str(torso_result.blocker),
    }

func _candidate_is_subject_readable(candidate: Vector3) -> bool:
    if not _candidate_has_subject_clearance(candidate):
        return false
    var projection := _subject_projection(candidate)
    return (
        bool(projection.visible)
        and _projection_keeps_horizontal_subject(projection)
        and float(projection.y) >= 0.05
        and float(projection.y) <= 0.98
    )

func _solve_framing(candidate: Vector3) -> Vector3:
    if head_marker == null or torso_marker == null or pelvis_marker == null or feet_marker == null:
        return candidate

    # Temporarily place the rig for screen-space measurement.
    var old_pos := global_position
    var old_basis := global_basis
    global_position = candidate
    _snap_orientation()

    var viewport_size := get_viewport().get_visible_rect().size
    var head_screen: Vector2 = camera.unproject_position(head_marker.global_position)
    var torso_screen: Vector2 = camera.unproject_position(torso_marker.global_position)
    var pelvis_screen: Vector2 = camera.unproject_position(pelvis_marker.global_position)
    var feet_screen: Vector2 = camera.unproject_position(feet_marker.global_position)
    var head_x: float = head_screen.x / maxf(viewport_size.x, 1.0)
    var head_y: float = head_screen.y / maxf(viewport_size.y, 1.0)
    var torso_y: float = torso_screen.y / maxf(viewport_size.y, 1.0)
    var pelvis_y: float = pelvis_screen.y / maxf(viewport_size.y, 1.0)
    var feet_y: float = feet_screen.y / maxf(viewport_size.y, 1.0)
    measured_head_x = head_x
    measured_head_y = head_y
    measured_torso_y = torso_y
    measured_pelvis_y = pelvis_y
    measured_feet_y = feet_y

    # Measure the local screen response instead of assuming a fixed conversion
    # between world height and screen height. This remains stable across pitch,
    # collision compression and steep rooftop views.
    var probe_height: float = maxf(profile.framing_probe_height, 0.01)
    global_position = candidate + Vector3.UP * probe_height
    _snap_orientation()
    var probe_head_y: float = camera.unproject_position(head_marker.global_position).y / maxf(viewport_size.y, 1.0)
    var probe_torso_y: float = camera.unproject_position(torso_marker.global_position).y / maxf(viewport_size.y, 1.0)
    var probe_pelvis_y: float = camera.unproject_position(pelvis_marker.global_position).y / maxf(viewport_size.y, 1.0)
    var probe_feet_y: float = camera.unproject_position(feet_marker.global_position).y / maxf(viewport_size.y, 1.0)
    var head_height_response: float = (probe_head_y - head_y) / probe_height
    var torso_height_response: float = (probe_torso_y - torso_y) / probe_height
    var pelvis_height_response: float = (probe_pelvis_y - pelvis_y) / probe_height
    var feet_height_response: float = (probe_feet_y - feet_y) / probe_height

    global_position = candidate
    _snap_orientation()
    var camera_right: Vector3 = global_basis.x.normalized()
    var probe_side: float = maxf(profile.framing_probe_side, 0.01)
    global_position = candidate + camera_right * probe_side
    _snap_orientation()
    var probe_head_x: float = camera.unproject_position(head_marker.global_position).x / maxf(viewport_size.x, 1.0)
    var head_side_response: float = (probe_head_x - head_x) / probe_side

    global_position = old_pos
    global_basis = old_basis

    _update_terrain_crop_relaxation()
    current_head_target_y = lerpf(
        profile.desired_head_y,
        profile.downward_aim_head_y,
        downward_aim_amount
    )
    var steep_head_drop: float = smoothstep(0.82, 1.0, downward_aim_amount)
    current_head_target_y = lerpf(
        current_head_target_y,
        profile.steep_downward_head_y,
        steep_head_drop
    )
    current_head_target_x = profile.desired_head_x
    current_head_target_x -= movement_lateral_ratio * profile.movement_head_x_shift
    current_head_target_y = lerpf(current_head_target_y, profile.tight_space_head_y, tight_space_amount)
    current_head_target_y = lerpf(current_head_target_y, profile.interior_head_y, interior_amount)
    current_torso_target_y = lerpf(
        profile.desired_torso_y,
        profile.interior_torso_y,
        interior_amount
    )
    var wall_head_weight: float = (
        (1.0 - overhead_confinement) * wall_context_amount
    )
    current_head_target_x = lerpf(current_head_target_x, profile.wall_escape_head_x, wall_head_weight)
    current_head_target_y = lerpf(current_head_target_y, profile.wall_escape_head_y, wall_head_weight)
    var base_pelvis_target: float = lerpf(
        profile.desired_pelvis_y,
        profile.downward_aim_pelvis_y,
        downward_aim_amount
    )
    base_pelvis_target = lerpf(base_pelvis_target, profile.interior_pelvis_y, interior_amount)
    current_pelvis_target_y = (
        base_pelvis_target
        - terrain_crop_relaxation
        + tight_space_pelvis_crop
    )
    current_feet_target_y = profile.desired_feet_y - terrain_crop_relaxation
    var pelvis_target: float = current_pelvis_target_y
    var pelvis_min: float = pelvis_target - profile.pelvis_crop_tolerance_above
    var pelvis_max: float = pelvis_target + profile.pelvis_crop_tolerance_below
    var feet_min: float = current_feet_target_y - profile.feet_crop_tolerance_above
    var feet_max: float = current_feet_target_y + profile.feet_crop_tolerance_below

    var head_x_error: float = head_x - current_head_target_x
    var head_error: float = head_y - current_head_target_y
    var torso_error: float = torso_y - current_torso_target_y
    var pelvis_error: float = 0.0
    pelvis_crop_state = "CROPPED"
    if pelvis_y < pelvis_min:
        pelvis_error = pelvis_y - pelvis_min
    elif pelvis_y > pelvis_max:
        pelvis_error = pelvis_y - pelvis_max

    # Open space keeps some lower-body context without hard-locking the boots.
    # The influence fades as geometry compresses the boom so indoor framing can
    # intentionally spend the legs and then the lower torso.
    var feet_error: float = 0.0
    if feet_y < feet_min:
        feet_error = feet_y - feet_min
    elif feet_y > feet_max:
        feet_error = feet_y - feet_max

    var visual_pelvis_min: float = lerpf(0.88, 0.78, downward_aim_amount) - terrain_crop_relaxation
    var visual_pelvis_max: float = lerpf(1.08, 0.94, downward_aim_amount)
    if pelvis_y < visual_pelvis_min:
        pelvis_crop_state = "TOO MUCH LEG"
    elif pelvis_y > visual_pelvis_max:
        pelvis_crop_state = "UPPER BODY ONLY"

    if absf(head_error) < profile.framing_deadzone:
        head_error = 0.0
    if absf(head_x_error) < profile.framing_deadzone:
        head_x_error = 0.0

    # The head is the primary anchor. The pelvis is a crop guardrail rather than a
    # second hard target, so gait animation cannot make the camera hunt each frame.
    var low_stance_amount := _low_stance_amount()
    var pelvis_weight: float = lerpf(
        profile.pelvis_framing_weight,
        profile.pelvis_framing_weight * profile.tight_space_pelvis_weight_scale,
        tight_space_amount
    )
    var feet_weight: float = lerpf(
        profile.feet_framing_weight,
        profile.feet_framing_weight * profile.tight_space_feet_weight_scale,
        tight_space_amount
    )
    pelvis_weight *= lerpf(1.0, profile.low_stance_pelvis_weight_scale, low_stance_amount)
    feet_weight *= lerpf(1.0, profile.low_stance_feet_weight_scale, low_stance_amount)
    # Looking over a ledge is an aiming state, not a request to preserve a
    # full-body portrait. Let the head/torso anchors spend the lower body.
    pelvis_weight *= lerpf(1.0, 0.20, downward_aim_amount)
    feet_weight *= 1.0 - downward_aim_amount
    var torso_weight: float = (
        profile.torso_framing_weight
        * lerpf(1.0, 0.15, downward_crane_amount)
    )
    var combined_error: float = (
        head_error * profile.head_framing_weight
        + torso_error * torso_weight
        + pelvis_error * pelvis_weight
        + feet_error * feet_weight
    )
    var combined_height_response: float = (
        head_height_response * profile.head_framing_weight
        + torso_height_response * torso_weight
        + (pelvis_height_response * pelvis_weight if pelvis_error != 0.0 else 0.0)
        + (feet_height_response * feet_weight if feet_error != 0.0 else 0.0)
    )
    var max_height_correction: float = lerpf(
        profile.max_framing_height_correction,
        profile.downward_max_framing_height_correction,
        downward_aim_amount
    )
    max_height_correction = lerpf(
        max_height_correction,
        profile.interior_max_framing_height_correction,
        interior_amount
    )
    max_height_correction = lerpf(
        max_height_correction,
        maxf(max_height_correction, profile.wall_escape_max_framing_height_correction),
        wall_context_amount
    )
    max_height_correction = maxf(
        max_height_correction,
        low_stance_amount * profile.max_low_stance_camera_drop
    )
    if absf(combined_height_response) > 0.0001:
        framing_correction = clampf(
            -combined_error / combined_height_response,
            -max_height_correction,
            max_height_correction
        )
    else:
        framing_correction = clampf(
            -combined_error * profile.framing_gain,
            -max_height_correction,
            max_height_correction
        )
    var max_side_correction: float = lerpf(
        profile.max_framing_side_correction,
        profile.wall_escape_max_framing_side_correction,
        wall_context_amount
    )
    if absf(head_side_response) > 0.0001:
        framing_side_correction = clampf(
            -head_x_error / head_side_response,
            -max_side_correction,
            max_side_correction
        )
    else:
        framing_side_correction = 0.0
    return candidate + camera_right * framing_side_correction + Vector3.UP * framing_correction

func _update_terrain_crop_relaxation() -> void:
    terrain_slope_deg = 0.0
    terrain_crop_relaxation = 0.0
    if not target is CharacterBody3D:
        return

    var body := target as CharacterBody3D
    if not body.is_on_floor():
        return

    var floor_normal: Vector3 = body.get_floor_normal()
    terrain_slope_deg = rad_to_deg(floor_normal.angle_to(Vector3.UP))
    var slope_ratio: float = clampf(
        terrain_slope_deg / maxf(profile.terrain_full_relaxation_deg, 0.001),
        0.0,
        1.0
    )
    terrain_crop_relaxation = slope_ratio * profile.max_terrain_pelvis_reveal

func _update_visual_crop_state() -> void:
    if pelvis_marker == null or feet_marker == null or camera == null:
        pelvis_crop_state = "UNKNOWN"
        return

    var viewport_height: float = maxf(get_viewport().get_visible_rect().size.y, 1.0)
    var final_pelvis_y: float = camera.unproject_position(pelvis_marker.global_position).y / viewport_height
    var final_feet_y: float = camera.unproject_position(feet_marker.global_position).y / viewport_height
    # At steep top-down pitch the projected feet can sit numerically close to
    # the pelvis even when the entire lower body is below the frame. Classify
    # the pelvis first so the debug state matches what is actually visible.
    if final_pelvis_y > 1.02:
        pelvis_crop_state = "UPPER BODY ONLY"
    elif final_feet_y <= 1.0:
        pelvis_crop_state = "LEGS + FEET"
    elif final_feet_y <= 1.16:
        pelvis_crop_state = "LEGS, FEET CROPPED"
    elif final_pelvis_y <= 0.98:
        pelvis_crop_state = "THIGHS / WAIST CROP"
    else:
        pelvis_crop_state = "UPPER BODY ONLY"

func _update_tight_space_state(delta: float) -> void:
    var anchor: Vector3 = target.global_position + Vector3.UP * profile.collision_anchor_height
    var preferred_boom: float = anchor.distance_to(preferred_camera_position)
    var collision_boom: float = anchor.distance_to(collision_camera_position)
    boom_compression = 0.0
    if collision_active:
        boom_compression = clampf(
            1.0 - collision_boom / maxf(preferred_boom, 0.001),
            0.0,
            1.0
        )

    var compression_range: float = maxf(
        profile.tight_space_full_compression - profile.tight_space_compression_start,
        0.001
    )
    var compression_tightness: float = clampf(
        (boom_compression - profile.tight_space_compression_start) / compression_range,
        0.0,
        1.0
    )
    if collision_active:
        compression_tightness = maxf(compression_tightness, 0.12)
    if wall_escape_active:
        compression_tightness = maxf(compression_tightness, profile.wall_escape_min_tightness)
    var target_tightness: float = maxf(compression_tightness, overhead_confinement)
    tight_space_amount = lerpf(
        tight_space_amount,
        target_tightness,
        1.0 - exp(-profile.tight_space_response * delta)
    )
    tight_space_pelvis_crop = tight_space_amount * profile.max_tight_space_pelvis_crop

    if tight_space_amount >= 0.55:
        framing_mode = "TIGHT UPPER BODY"
    elif tight_space_amount >= 0.08:
        framing_mode = "CONSTRAINED CROP"
    else:
        framing_mode = "OUTDOOR TACTICAL"

func _update_dynamic_fov(delta: float) -> void:
    # The crane increases subject distance, so a controlled lens blend preserves
    # the upper-body scale. It runs before framing and uses the same smooth state
    # curve as the crane, avoiding the former projection mismatch and pitch pop.
    var target_fov: float = lerpf(
        profile.vertical_fov,
        profile.downward_fov,
        downward_crane_amount
    )
    var steep_lens_amount: float = smoothstep(0.82, 1.0, downward_aim_amount)
    target_fov = lerpf(target_fov, profile.steep_downward_fov, steep_lens_amount)
    # v2.0 pre-enclosed baseline: when geometry forces a level camera very
    # close, widen the lens without moving the camera or redirecting aim.
    # Downward rooftop aim retains its purpose-built narrower lens.
    var close_lens_amount: float = smoothstep(
        profile.close_fov_start_compression,
        profile.close_fov_full_compression,
        boom_compression
    ) * (1.0 - downward_aim_amount)
    target_fov = lerpf(
        target_fov,
        maxf(target_fov, profile.close_level_fov),
        close_lens_amount
    )
    var lens_response: float = maxf(
        profile.downward_fov_response,
        profile.close_fov_response * close_lens_amount
    )
    current_fov = lerpf(
        current_fov,
        target_fov,
        1.0 - exp(-lens_response * delta)
    )
    camera.fov = current_fov

func _update_movement_follow(delta: float) -> void:
    if not target is CharacterBody3D:
        movement_lead = Vector3.ZERO
        movement_speed_ratio = 0.0
        movement_lateral_ratio = 0.0
        return

    var body := target as CharacterBody3D
    var horizontal_velocity := Vector3(body.velocity.x, 0.0, body.velocity.z)
    var horizontal_speed: float = horizontal_velocity.length()
    movement_speed_ratio = clampf(horizontal_speed / maxf(profile.movement_full_speed, 0.001), 0.0, 1.0)
    var camera_right: Vector3 = Basis(Vector3.UP, yaw) * Vector3.RIGHT
    movement_lateral_ratio = clampf(
        horizontal_velocity.dot(camera_right) / maxf(profile.movement_full_speed, 0.001),
        -1.0,
        1.0
    )
    var desired_lead: Vector3 = horizontal_velocity * profile.movement_lead_time
    if desired_lead.length() > profile.max_movement_lead:
        desired_lead = desired_lead.normalized() * profile.max_movement_lead
    var response: float = profile.movement_lead_response if horizontal_speed > 0.05 else profile.movement_return_response
    movement_lead = movement_lead.lerp(desired_lead, 1.0 - exp(-response * delta))

func _measure_overhead_confinement() -> float:
    if head_marker == null:
        return 0.0

    var origin: Vector3 = head_marker.global_position + Vector3.UP * 0.08
    var destination: Vector3 = origin + Vector3.UP * profile.ceiling_probe_distance
    var query := PhysicsRayQueryParameters3D.create(origin, destination)
    query.collide_with_areas = false
    if target is CollisionObject3D:
        query.exclude = [(target as CollisionObject3D).get_rid()]

    var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    if hit.is_empty():
        return 0.0

    var hit_position: Vector3 = hit["position"]
    var clearance: float = origin.distance_to(hit_position)
    return clampf(1.0 - clearance / maxf(profile.ceiling_probe_distance, 0.001), 0.0, 1.0)

func _limit_excursion(candidate: Vector3) -> Vector3:
    var delta := candidate - preferred_camera_position
    var allowed_drop: float = (
        profile.max_drop
        + tight_space_amount * profile.max_tight_space_extra_drop
        + _low_stance_amount() * profile.max_low_stance_camera_drop
    )
    var allowed_raise: float = lerpf(
        profile.max_raise,
        profile.downward_max_framing_height_correction,
        downward_aim_amount
    )
    delta.y = clampf(delta.y, -allowed_drop, allowed_raise)

    var yaw_basis := Basis(Vector3.UP, yaw)
    var right := yaw_basis * Vector3.RIGHT
    var back := yaw_basis * Vector3.BACK
    var local_side := delta.dot(right)
    var local_depth := delta.dot(back)
    var local_vertical := delta.y

    var allowed_side: float = lerpf(
        profile.max_side_excursion,
        profile.max_wall_escape_side_excursion,
        maxf(tight_space_amount, wall_context_amount)
    )
    local_side = clamp(local_side, -allowed_side, allowed_side)
    # Collision is allowed to compress nearly to the anchor when geometry demands it.
    # The solver first tries to escape upward; this lower bound only prevents crossing
    # through the player anchor to the wrong side.
    local_depth = clamp(local_depth, -(profile.distance - 0.15), 0.5)

    return preferred_camera_position + right * local_side + back * local_depth + Vector3.UP * local_vertical

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
    # Raw player yaw/pitch owns a distant, camera-independent view point. Keeping
    # collision out of this value prevents a nearby wall hit from becoming an
    # orbit pivot and dragging the operator out of frame.
    var origin: Vector3 = (
        target.global_position
        + movement_lead
        + Vector3.UP * profile.look_height
    )
    var direction: Vector3 = _forward_direction()
    var destination: Vector3 = origin + direction * profile.aim_distance
    aim_point = destination

func _update_weapon_aim_point() -> void:
    # Once the legal rendered lens is known, cast through the fixed center
    # reticle. This produces the one exact world point shared by the camera,
    # weapon pose and authoritative muzzle trace without feeding camera
    # collision back into orbit control.
    var lens_origin: Vector3 = camera.global_position
    var direction: Vector3 = -camera.global_basis.z.normalized()
    # A virtual wall camera is allowed to render from the far side of a wall
    # behind the operator. Do not let that deliberately hidden rear surface
    # become the center-reticle target. Begin acquisition on the same center
    # ray at the operator's depth plane; forward cover is still hittable and
    # the independent muzzle trace still prevents shooting through it.
    var player_aim_origin: Vector3 = (
        target.global_position
        + movement_lead
        + Vector3.UP * profile.look_height
    )
    var player_depth: float = maxf(
        (player_aim_origin - lens_origin).dot(direction),
        0.0
    )
    var acquisition_depth: float = minf(
        player_depth + maxf(camera.near, 0.05),
        profile.aim_distance - 0.10
    )
    var origin: Vector3 = lens_origin + direction * acquisition_depth
    var destination: Vector3 = (
        lens_origin + direction * profile.aim_distance
    )
    weapon_aim_point = destination
    var query := PhysicsRayQueryParameters3D.create(origin, destination)
    query.collide_with_areas = false
    if target is CollisionObject3D:
        query.exclude = [(target as CollisionObject3D).get_rid()]

    var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    aim_hit = not result.is_empty()
    aim_collider_name = "OPEN"
    if aim_hit:
        var hit_position: Vector3 = result["position"]
        weapon_aim_point = hit_position
        var collider: Variant = result.get("collider")
        if collider is Node:
            aim_collider_name = str((collider as Node).name)
        elif collider is Object:
            aim_collider_name = (collider as Object).get_class()

func _update_shot_validation() -> void:
    shot_point = weapon_aim_point
    shot_blocked = false
    shot_collider_name = aim_collider_name
    if target == null or weapon_aim_point == Vector3.ZERO:
        return

    var mannequin = target.get_node_or_null("Mannequin")
    if mannequin == null or mannequin.muzzle_marker == null:
        return

    var muzzle_position: Vector3 = mannequin.muzzle_marker.global_position
    var query := PhysicsRayQueryParameters3D.create(muzzle_position, weapon_aim_point)
    query.collide_with_areas = false
    if target is CollisionObject3D:
        query.exclude = [(target as CollisionObject3D).get_rid()]

    var result: Dictionary = get_world_3d().direct_space_state.intersect_ray(query)
    if result.is_empty():
        return

    shot_point = result["position"]
    var remaining_to_reticle_hit: float = shot_point.distance_to(weapon_aim_point)
    shot_blocked = remaining_to_reticle_hit > 0.08
    var collider: Variant = result.get("collider")
    if collider is Node:
        shot_collider_name = str((collider as Node).name)
    elif collider is Object:
        shot_collider_name = (collider as Object).get_class()


func build_local_aim_intent() -> Dictionary:
    # Multiplayer boundary: camera placement and wall-solving state remain
    # entirely local. A shot sends only sequenced aim intent; the server must
    # replace the reported muzzle with its authoritative character muzzle and
    # repeat collision in the authoritative world.
    if target == null:
        return {}
    var mannequin = target.get_node_or_null("Mannequin")
    if mannequin == null or mannequin.muzzle_marker == null:
        return {}
    var muzzle: Vector3 = mannequin.muzzle_marker.global_position
    var direction: Vector3 = (weapon_aim_point - muzzle).normalized()
    if direction.length_squared() < 0.99:
        direction = _forward_direction()
    aim_intent_sequence += 1
    return AimIntentScript.create(
        aim_intent_sequence,
        Engine.get_physics_frames(),
        yaw,
        pitch,
        muzzle,
        direction
    )

func _update_reticle_position(delta: float) -> void:
    var center := Vector2(0.5, 0.5)
    var desired := center
    reticle_dynamic_amount = collision_crane_view_amount
    if (
        reticle_dynamic_amount > 0.001
        and weapon_aim_point != Vector3.ZERO
        and not camera.is_position_behind(weapon_aim_point)
    ):
        var viewport_size := get_viewport().get_visible_rect().size
        var projected_pixels := camera.unproject_position(weapon_aim_point)
        var projected := Vector2(
            projected_pixels.x / maxf(viewport_size.x, 1.0),
            projected_pixels.y / maxf(viewport_size.y, 1.0)
        )
        var offset := projected - center
        var maximum := Vector2(
            profile.close_wall_reticle_max_x,
            profile.close_wall_reticle_max_y
        )
        var elliptical := Vector2(
            offset.x / maxf(maximum.x, 0.001),
            offset.y / maxf(maximum.y, 0.001)
        )
        if elliptical.length() > 1.0:
            elliptical = elliptical.normalized()
        desired = center + Vector2(
            elliptical.x * maximum.x,
            elliptical.y * maximum.y
        ) * reticle_dynamic_amount
    reticle_screen_normalized = reticle_screen_normalized.lerp(
        desired,
        1.0 - exp(-profile.close_wall_reticle_response * delta)
    )

func get_debug_data() -> Dictionary:
    var viewport_size := get_viewport().get_visible_rect().size
    var head_x := -1.0
    var head_y := -1.0
    var torso_y := -1.0
    var pelvis_y := -1.0
    var feet_y := -1.0
    var aim_screen_x := -1.0
    var aim_screen_y := -1.0
    var camera_weapon_angle_deg := 0.0
    var camera_aim_angle_deg := 0.0
    var subject_visibility := _camera_subject_visibility()
    var rendered_view_yaw_deg := rad_to_deg(yaw)
    if head_marker and camera:
        head_x = camera.unproject_position(head_marker.global_position).x / maxf(viewport_size.x, 1.0)
        head_y = camera.unproject_position(head_marker.global_position).y / maxf(viewport_size.y, 1.0)
    if torso_marker and camera:
        torso_y = camera.unproject_position(torso_marker.global_position).y / maxf(viewport_size.y, 1.0)
    if pelvis_marker and camera:
        pelvis_y = camera.unproject_position(pelvis_marker.global_position).y / maxf(viewport_size.y, 1.0)
    if feet_marker and camera:
        feet_y = camera.unproject_position(feet_marker.global_position).y / maxf(viewport_size.y, 1.0)
    if camera and weapon_aim_point != Vector3.ZERO and not camera.is_position_behind(weapon_aim_point):
        var aim_pixels := camera.unproject_position(weapon_aim_point)
        aim_screen_x = aim_pixels.x / maxf(viewport_size.x, 1.0)
        aim_screen_y = aim_pixels.y / maxf(viewport_size.y, 1.0)
        var camera_forward: Vector3 = -camera.global_basis.z.normalized()
        rendered_view_yaw_deg = rad_to_deg(atan2(
            -camera_forward.x,
            -camera_forward.z
        ))
        var camera_to_aim: Vector3 = (weapon_aim_point - camera.global_position).normalized()
        camera_aim_angle_deg = rad_to_deg(camera_forward.angle_to(camera_to_aim))
        var mannequin = target.get_node_or_null("Mannequin") if target else null
        if mannequin and mannequin.muzzle_marker:
            var weapon_to_aim: Vector3 = (
                weapon_aim_point - mannequin.muzzle_marker.global_position
            ).normalized()
            camera_weapon_angle_deg = rad_to_deg(
                camera_forward.angle_to(weapon_to_aim)
            )

    var rear_boom_distance: float = 0.0
    if target:
        var yaw_back: Vector3 = Basis(Vector3.UP, yaw) * Vector3.BACK
        rear_boom_distance = maxf(
            (global_position - target.global_position).dot(yaw_back),
            0.0
        )
    var weapon_obstruction_amount: float = 0.0
    var debug_mannequin = target.get_node_or_null("Mannequin") if target else null
    if debug_mannequin and debug_mannequin.has_method("get_aim_debug_data"):
        weapon_obstruction_amount = float(
            debug_mannequin.get_aim_debug_data().weapon_obstruction_amount
        )

    return {
        "fov": camera.fov if camera else profile.vertical_fov,
        "distance": global_position.distance_to(target.global_position) if target else 0.0,
        "rear_boom_distance": rear_boom_distance,
        "height_above_player": global_position.y - target.global_position.y if target else 0.0,
        "head_x": head_x,
        "head_y": head_y,
        "torso_y": torso_y,
        "pelvis_y": pelvis_y,
        "feet_y": feet_y,
        "head_target_x": current_head_target_x,
        "head_target_y": current_head_target_y,
        "torso_target_y": current_torso_target_y,
        "pelvis_target_y": current_pelvis_target_y,
        "feet_target_y": current_feet_target_y,
        "measured_head_x": measured_head_x,
        "measured_head_y": measured_head_y,
        "measured_torso_y": measured_torso_y,
        "measured_pelvis_y": measured_pelvis_y,
        "measured_feet_y": measured_feet_y,
        "pelvis_crop_state": pelvis_crop_state,
        "framing_correction": framing_correction,
        "framing_side_correction": framing_side_correction,
        "post_collision_reframe": post_collision_reframe,
        "post_initial_score": post_initial_score,
        "post_validated_score": post_validated_score,
        "post_validated_clearance": post_validated_clearance,
        "post_initial_head_distance": post_initial_head_distance,
        "post_validated_head_distance": post_validated_head_distance,
        "collision_crane_active": collision_crane_active,
        "collision_crane_look_ahead": collision_crane_look_ahead,
        "collision_crane_view_amount": collision_crane_view_amount,
        "surface_slide_active": surface_slide_active,
        "near_body_crop_active": near_body_crop_active,
        "near_body_geometry_hidden": near_body_geometry_hidden,
        "transition_crop_active": transition_crop_active,
        "surface_slide_candidates": surface_slide_candidate_count,
        "surface_slide_clear": surface_slide_clear_count,
        "surface_slide_readable": surface_slide_readable_count,
        "surface_slide_target_x": surface_slide_target_x,
        "surface_slide_target_y": surface_slide_target_y,
        "reticle_x": reticle_screen_normalized.x,
        "reticle_y": reticle_screen_normalized.y,
        "reticle_dynamic_amount": reticle_dynamic_amount,
        "aim_screen_x": aim_screen_x,
        "aim_screen_y": aim_screen_y,
        "camera_weapon_angle_deg": camera_weapon_angle_deg,
        "camera_aim_angle_deg": camera_aim_angle_deg,
        "camera_head_visible": subject_visibility.head_visible,
        "camera_head_blocker": subject_visibility.head_blocker,
        "camera_torso_visible": subject_visibility.torso_visible,
        "camera_torso_blocker": subject_visibility.torso_blocker,
        "rendered_view_yaw_deg": rendered_view_yaw_deg,
        "collision_cast_count": collision_cast_count,
        "collision_solver_usec": collision_solver_usec,
        "camera_state": get_camera_state_name(),
        "camera_state_age": camera_state_age,
        "camera_state_transitions": camera_state_transition_count,
        "camera_tether_rebased": camera_tether_rebased,
        "composition_recovery_active": composition_recovery_active,
        "composition_hard_rebase": composition_hard_rebase,
        "composition_hard_rebase_count": composition_hard_rebase_count,
        "virtual_wall_occluder": (
            str(virtual_wall_occluder.name)
            if virtual_wall_occluder
            else "CLEAR"
        ),
        "wall_context_amount": wall_context_amount,
        "terrain_slope_deg": terrain_slope_deg,
        "terrain_crop_relaxation": terrain_crop_relaxation,
        "boom_compression": boom_compression,
        "overhead_confinement": overhead_confinement,
        "tight_space_amount": tight_space_amount,
        "interior_amount": interior_amount,
        "framing_mode": framing_mode,
        "wall_escape_active": wall_escape_active,
        "wall_escape_angle_deg": wall_escape_angle_deg,
        "local_cutout_active": local_cutout_active,
        "local_cutout_center": local_cutout_center,
        "local_cutout_node": str(local_cutout_node.name) if local_cutout_node else "CLEAR",
        "movement_lead": movement_lead,
        "movement_speed_ratio": movement_speed_ratio,
        "movement_lateral_ratio": movement_lateral_ratio,
        "downward_aim_amount": downward_aim_amount,
        "downward_crane_amount": downward_crane_amount,
        "downward_ledge_raise": downward_ledge_raise,
        "aim_hit": aim_hit,
        "aim_collider": aim_collider_name,
        "aim_point": weapon_aim_point,
        "camera_intent_point": aim_point,
        "shot_point": shot_point,
        "shot_blocked": shot_blocked,
        "shot_collider": shot_collider_name,
        "weapon_obstruction_amount": weapon_obstruction_amount,
        "excursion": excursion,
        "virtual_camera_position": virtual_camera_position,
        "collision_camera_position": collision_camera_position,
        "collision": collision_name,
        "collision_active": collision_active,
        "yaw_deg": rad_to_deg(yaw),
        "pitch_deg": rad_to_deg(pitch),
        "view_pitch_deg": rad_to_deg(_composed_view_pitch())
    }

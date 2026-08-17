class_name SocomCameraFramePipeline
extends RefCounted

const CameraState = preload("res://scripts/camera/camera_state_controller.gd").CameraState

var rig
var automated_wall_turn:
    get: return rig.automated_wall_turn
var target:
    get: return rig.target
    set(value): rig.target = value
var head_marker:
    get: return rig.head_marker
    set(value): rig.head_marker = value
var profile:
    get: return rig.profile
    set(value): rig.profile = value
var aim_yaw:
    get: return rig.aim_yaw
    set(value): rig.aim_yaw = value
var aim_pitch:
    get: return rig.aim_pitch
    set(value): rig.aim_pitch = value
var yaw:
    get: return rig.yaw
    set(value): rig.yaw = value
var pitch:
    get: return rig.pitch
    set(value): rig.pitch = value
var orbit_drag_enabled:
    get: return rig.orbit_drag_enabled
    set(value): rig.orbit_drag_enabled = value
var mouse_aim_string_enabled:
    get: return rig.mouse_aim_string_enabled
    set(value): rig.mouse_aim_string_enabled = value
var mouse_aim_model:
    get: return rig.mouse_aim_model
    set(value): rig.mouse_aim_model = value
var aim_input_controller:
    get: return rig.aim_input_controller
    set(value): rig.aim_input_controller = value
var mouse_intent_yaw:
    get: return rig.mouse_intent_yaw
    set(value): rig.mouse_intent_yaw = value
var mouse_intent_pitch:
    get: return rig.mouse_intent_pitch
    set(value): rig.mouse_intent_pitch = value
var initial_orbit_sync_pending:
    get: return rig.initial_orbit_sync_pending
    set(value): rig.initial_orbit_sync_pending = value
var current_camera_position:
    get: return rig.current_camera_position
    set(value): rig.current_camera_position = value
var preferred_camera_position:
    get: return rig.preferred_camera_position
    set(value): rig.preferred_camera_position = value
var virtual_camera_position:
    get: return rig.virtual_camera_position
    set(value): rig.virtual_camera_position = value
var collision_camera_position:
    get: return rig.collision_camera_position
    set(value): rig.collision_camera_position = value
var excursion:
    get: return rig.excursion
    set(value): rig.excursion = value
var collision_active:
    get: return rig.collision_active
    set(value): rig.collision_active = value
var collision_name:
    get: return rig.collision_name
    set(value): rig.collision_name = value
var downward_aim_amount:
    get: return rig.downward_aim_amount
    set(value): rig.downward_aim_amount = value
var downward_crane_amount:
    get: return rig.downward_crane_amount
    set(value): rig.downward_crane_amount = value
var downward_ledge_raise:
    get: return rig.downward_ledge_raise
    set(value): rig.downward_ledge_raise = value
var wall_escape_active:
    get: return rig.wall_escape_active
    set(value): rig.wall_escape_active = value
var wall_escape_angle_deg:
    get: return rig.wall_escape_angle_deg
    set(value): rig.wall_escape_angle_deg = value
var movement_speed_ratio:
    get: return rig.movement_speed_ratio
    set(value): rig.movement_speed_ratio = value
var post_collision_reframe:
    get: return rig.post_collision_reframe
    set(value): rig.post_collision_reframe = value
var post_initial_score:
    get: return rig.post_initial_score
    set(value): rig.post_initial_score = value
var post_validated_score:
    get: return rig.post_validated_score
    set(value): rig.post_validated_score = value
var post_validated_clearance:
    get: return rig.post_validated_clearance
    set(value): rig.post_validated_clearance = value
var post_initial_head_distance:
    get: return rig.post_initial_head_distance
    set(value): rig.post_initial_head_distance = value
var post_validated_head_distance:
    get: return rig.post_validated_head_distance
    set(value): rig.post_validated_head_distance = value
var last_readable_post_solve_position:
    get: return rig.last_readable_post_solve_position
    set(value): rig.last_readable_post_solve_position = value
var collision_crane_active:
    get: return rig.collision_crane_active
    set(value): rig.collision_crane_active = value
var collision_crane_view_amount:
    get: return rig.collision_crane_view_amount
    set(value): rig.collision_crane_view_amount = value
var near_body_crop_active:
    get: return rig.near_body_crop_active
    set(value): rig.near_body_crop_active = value
var near_body_geometry_hidden:
    get: return rig.near_body_geometry_hidden
    set(value): rig.near_body_geometry_hidden = value
var transition_crop_active:
    get: return rig.transition_crop_active
    set(value): rig.transition_crop_active = value
var mouse_cursor_cage_enabled:
    get: return rig.mouse_cursor_cage_enabled
    set(value): rig.mouse_cursor_cage_enabled = value
var mouse_cursor_deflection:
    get: return rig.mouse_cursor_deflection
    set(value): rig.mouse_cursor_deflection = value
var mouse_edge_turn:
    get: return rig.mouse_edge_turn
    set(value): rig.mouse_edge_turn = value
var collision_cast_count:
    get: return rig.collision_cast_count
    set(value): rig.collision_cast_count = value
var collision_solver_usec:
    get: return rig.collision_solver_usec
    set(value): rig.collision_solver_usec = value
var wall_context_amount:
    get: return rig.wall_context_amount
    set(value): rig.wall_context_amount = value
var camera_state:
    get: return rig.camera_state
    set(value): rig.camera_state = value
var camera_tether_rebased:
    get: return rig.camera_tether_rebased
    set(value): rig.camera_tether_rebased = value
var target_translation_blocked:
    get: return rig.target_translation_blocked
    set(value): rig.target_translation_blocked = value
var camera:
    get: return rig.camera
    set(value): rig.camera = value
var orbit_input_enabled:
    get: return rig.orbit_input_enabled
    set(value): rig.orbit_input_enabled = value

func configure(camera_rig) -> void:
    rig = camera_rig

func step(delta: float) -> void:
    if target == null or camera == null:
        return

    # The lab selects scenario yaw/pitch immediately after add_child() returns,
    # which is after rig._ready(). Capture that final initial orbit once so the
    # camera cannot ease back toward stale startup intent on its first frame.
    if initial_orbit_sync_pending:
        rig._sync_aim_to_orbit()
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
        rig.reset_camera_to_target()
    rig._follow_target_translation()
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
            rig._update_controller_aim(delta)
        elif mouse_aim_string_enabled and orbit_input_enabled:
            rig._update_mouse_aim_string(delta)
        if (
            mouse_cursor_cage_enabled
            and aim_input_controller.is_mouse_active()
            and orbit_input_enabled
            and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
        ):
            rig._update_mouse_cursor_turn(delta)
        elif not mouse_aim_string_enabled:
            mouse_edge_turn = Vector2.ZERO
        if orbit_drag_enabled:
            # Standard SOCOM weapons have no ADS camera. The tighter response
            # is reserved for a future explicit sniper/scope state.
            rig._update_orbit_trail(delta, false)
        else:
            yaw = aim_yaw
            pitch = aim_pitch
    yaw = wrapf(yaw, -PI, PI)

    rig._update_movement_follow(delta)
    downward_aim_amount = rig._calculate_downward_aim_amount()
    downward_crane_amount = smoothstep(0.0, 1.0, downward_aim_amount)
    # Mid-range downward pitch is where a parapet most often blocks the center
    # ray. Add a bell-shaped ledge lift that fades out again for true top-down aim.
    downward_ledge_raise = (
        sin(PI * downward_aim_amount)
        * profile.mid_downward_ledge_raise
    )
    rig._update_environment_state(delta)
    # Raw player yaw/pitch owns one camera-independent crosshair target. Camera
    # placement, collision and animation may react to it, but never rewrite it.
    rig._update_aim_point()
    # Framing must measure the same projection that will be rendered this frame.
    # Updating FOV after composition caused a one-frame scale/pop disagreement.
    rig._update_dynamic_fov(delta)

    # A crane view is a result of this frame's collision solve, never an input
    # to the preferred-shot composition pass. Clearing it here prevents the
    # previous wall frame from biasing the next open/preferred solve.
    collision_crane_active = false

    preferred_camera_position = rig._preferred_position()
    var composed_position: Vector3 = rig._solve_framing(preferred_camera_position)
    var bounded_position: Vector3 = rig._limit_excursion(composed_position)
    # The virtual lens always follows input. Collision may constrain only the
    # rendered lens; it must never rewrite or stall this desired position.
    virtual_camera_position = bounded_position
    collision_cast_count = 0
    var collision_solve_started: int = Time.get_ticks_usec()
    var collision_result: Dictionary = rig._solve_collision(bounded_position)
    rig._apply_collision_result(collision_result)
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
        var initial_collision_name: String = collision_name
        var initial_wall_escape: bool = wall_escape_active
        var initial_escape_angle: float = wall_escape_angle_deg
        var initial_collision_result: Dictionary = collision_result
        var initial_collision_position: Vector3 = collision_camera_position
        var initial_projection: Dictionary = rig._subject_projection(initial_collision_position, true)
        post_initial_score = rig._post_solve_projection_score(initial_projection)
        post_initial_head_distance = initial_collision_position.distance_to(head_marker.global_position)
        # A close collision result is precisely when composition needs its
        # second pass. The old reframeable gate skipped this block whenever the
        # head had already crossed the screen guard, leaving the HUD on
        # "preferred pass" and allowing the lens to crowd the operator.
        var normal_post_solve_applied: bool = false
        if bool(initial_projection.visible):
            var reframed_position: Vector3 = rig._solve_framing(collision_camera_position)
            var reframed_bounded: Vector3 = rig._limit_excursion(reframed_position)
            var validated_result: Dictionary = rig._solve_collision(reframed_bounded)
            var validated_position: Vector3 = validated_result.position
            var validated_projection: Dictionary = rig._subject_projection(validated_position, true)
            post_validated_score = rig._post_solve_projection_score(validated_projection)
            post_validated_clearance = rig._candidate_has_subject_clearance(validated_position)
            post_validated_head_distance = validated_position.distance_to(head_marker.global_position)
            var validated_current_branch: bool = rig._shares_current_camera_branch(
                validated_position
            )
            # A legal, readable composition is the primary acceptance rule.
            # Requiring its numeric score to beat an already-broken close shot
            # rejected useful wall escapes and put the camera back on the raw
            # preferred pass. The score remains a fallback for edge projections.
            if (
                validated_current_branch
                and (
                    rig._candidate_is_subject_readable(validated_position)
                    or (
                        post_validated_clearance
                        and post_validated_score <= post_initial_score + 0.001
                    )
                )
            ):
                rig._apply_collision_result(validated_result)
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
            var better_result: Dictionary = rig._solve_better_post_collision(
                initial_collision_result,
                bounded_position
            )
            rig._apply_collision_result(better_result)
            var better_position: Vector3 = better_result.position
            var better_projection: Dictionary = rig._subject_projection(better_position, true)
            post_validated_score = rig._post_solve_projection_score(better_projection)
            post_validated_clearance = rig._candidate_has_subject_clearance(better_position)
            post_validated_head_distance = better_position.distance_to(head_marker.global_position)

        # This flag now means the collision result completed the post-solve
        # pipeline. Whether the second stage found an improvement is recorded
        # in the collision name instead of exposing a raw fallback state.
        post_collision_reframe = true

    # Keep one fixed legal composition anchor for crane continuity. A
    # constrained frame never overwrites it, so repeated frames cannot
    # accumulate height or walk the camera away from the player.
    if (
        rig._candidate_has_subject_clearance(collision_camera_position)
        and rig._candidate_is_reframeable(collision_camera_position)
    ):
        last_readable_post_solve_position = collision_camera_position

    collision_solver_usec = Time.get_ticks_usec() - collision_solve_started
    rig._update_collision_crane_view(delta)
    rig._update_wall_camera_state(delta)
    rig._update_tight_space_state(delta)
    rig._update_deterministic_camera_state(delta)

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
        current_camera_position = rig._smooth_legal_camera_position(
            collision_camera_position,
            delta,
            (
                camera_state != CameraState.PREFERRED
                or collision_active
                or collision_crane_view_amount > 0.01
            ),
            movement_response
        )

    current_camera_position = rig._enforce_rendered_composition(
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
            current_camera_position = rig._advance_local_lens_toward(
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
    var final_boom_cast: Dictionary = rig._cast_camera_volume(
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

    rig.global_position = current_camera_position
    rig._update_virtual_wall_occluder()
    rig._orient_camera(delta)
    rig._update_reticle_position(delta)
    rig._update_weapon_aim_point()
    var mannequin = target.get_node_or_null("Mannequin") if target else null
    near_body_geometry_hidden = (
        near_body_crop_active
        and head_marker != null
        and rig.global_position.distance_to(head_marker.global_position) < 0.62
    )
    if mannequin and mannequin.has_method("set_near_camera_crop"):
        mannequin.set_near_camera_crop(near_body_geometry_hidden)
    rig._update_visual_crop_state()
    rig._update_shot_validation()


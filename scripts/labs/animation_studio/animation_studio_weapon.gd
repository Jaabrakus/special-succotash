extends "res://scripts/labs/animation_studio/animation_studio_sequence.gd"

func _toggle_skin() -> void:
    var next_idx := (int(current_skin) + 1) % SkinType.size()
    _load_skin(next_idx as SkinType)

func _skin_name(skin: SkinType) -> String:
    match skin:
        SkinType.PS1_GAS_MASK_SOLDIER: return "PS1 Gas Mask Trooper (Rigged & Skinned)"
        SkinType.MILITARY_TACTICAL_OPERATOR: return "Military Tactical Suit (Game-Ready 87-Bone)"
        SkinType.SOCOM_OPERATOR: return "SOCOM Operator (Authored Rig)"
        SkinType.MIXAMO_MANNEQUIN: return "Mixamo Beta Skin"
        SkinType.PS1_NIGHT_VISION_SEAL: return "PS1 Night Vision SEAL"
        SkinType.COUNTER_STRIKE_URBAN: return "Counter-Strike Urban (Shared SOCOM Rig)"
    return "Unknown"

func _cycle_weapon() -> void:
    var next_idx := (int(current_weapon) + 1) % 5
    current_weapon = next_idx as WeaponType
    _rebuild_weapon_socket()
    weapon_selector_button.text = "Weapon (G): " + _weapon_name(current_weapon)

func _toggle_gun_lab() -> void:
    gun_lab_visible = not gun_lab_visible
    gun_lab_panel.visible = gun_lab_visible

func _reset_camera() -> void:
    orbit_yaw = -0.48
    orbit_pitch = -0.10
    orbit_distance = 3.6
    target_height = 0.95

func _should_loop(clip_name: String) -> bool:
    var s := clip_name.to_lower()
    if "jump loop" in s:
        return true
    for one_shot_word in [
        "start", "stop", "turn", "transition", "death", "hit", "reload",
        "throw", "fire", "shoot", "dive", "roll", "jump", "land", "climb",
        "idle to", "to walk", "kneel to", "to kneel", "to prone", "to standing", "to crouch",
    ]:
        if one_shot_word in s:
            return false
    return (
        "idle" in s
        or "walk" in s
        or "run" in s
        or "strafe" in s
        or "crawl" in s
        or "prone forward" in s
        or "backward in prone" in s
    )

func _filter_category(cat: String) -> void:
    current_category = cat
    if cat in ["LIVE IN GAME", "RIFLE + SHOOTER CANDIDATES", "NEEDS CLASSIFICATION"]:
        filtered_entries = clip_catalog.filter(all_clip_entries, state_slots, cat)
    else:
        filtered_entries = workshop_repository.filter_entries(all_clip_entries, cat)
    clip_index = 0
    if cat == "LIVE IN GAME":
        # Aim idle is the neutral, authored two-hand inspection pose. Starting
        # on the first catalog item previously opened an unclassified crouch
        # clip and made the Studio look broken before the user selected a job.
        var neutral_path := String(
            state_slots.get("aim_idle", state_slots.get("idle_rifle", ""))
        )
        for index in range(filtered_entries.size()):
            if String(filtered_entries[index].get("path", "")) == neutral_path:
                clip_index = index
                break
    _play_selected()
    _refresh_clip_list_ui()

func _assign_to_slot(slot_name: String) -> void:
    if filtered_entries.is_empty():
        return
    _assign_entry_to_slot(filtered_entries[clip_index], slot_name)

func _assign_entry_to_slot(entry: Dictionary, slot_name: String) -> void:
    var resource_path := str(entry.get("path", ""))
    if resource_path.is_empty():
        status_label.text = "This baked preview cannot be assigned; choose an FBX clip."
        return
    if not state_slots.has(slot_name):
        status_label.text = "Unknown gameplay slot: %s" % slot_name
        return
    var clip_label := str(entry.get("display", resource_path.get_file()))
    var compatibility_error := ANIMATION_STATE_CONTRACT.clip_compatibility_error(
        slot_name,
        clip_label,
        resource_path
    )
    if not compatibility_error.is_empty():
        status_label.text = "NOT APPLIED: %s Choose an aim/fire clip for this action." % compatibility_error
        return
    state_slots[slot_name] = resource_path
    _save_state_slots()
    _refresh_slot_ui()
    _refresh_clip_list_ui()
    status_label.text = "%s is now bound to %s." % [clip_label, slot_name]

func _refresh_slot_ui() -> void:
    if slot_panel_label == null:
        return
    var mapped := 0
    for path in state_slots.values():
        if not str(path).is_empty():
            mapped += 1
    var selected_path := str(state_slots.get(selected_state_slot, ""))
    var clip_label := "UNASSIGNED" if selected_path.is_empty() else selected_path.get_file()
    slot_panel_label.text = (
        "GAMEPLAY STATE: %s\n↓ logical slot\nCLIP: %s\n%d/%d basic slots mapped"
        % [selected_state_slot, clip_label, mapped, state_slots.size()]
    )
    if slot_drop_label:
        slot_drop_label.text = "DROP CLIP HERE\n→ %s" % selected_state_slot
    _refresh_runtime_state_tree()
    _refresh_slot_suggestion()
    _refresh_state_rule_editor()
    _refresh_event_routing_ui()
    _refresh_state_workflow_cues()

func _load_state_slots() -> void:
    state_slots = workshop_repository.load_state_slots(ANIMATION_MAP_PATH)
    clip_catalog.refresh_equipped_family()
    state_slot_keys.clear()
    for slot_name in state_slots.keys():
        state_slot_keys.append(str(slot_name))
    state_slot_keys.sort()
    state_rules = ANIMATION_STATE_CONTRACT.normalized_rules(
        state_slots,
        workshop_repository.load_state_rules(ANIMATION_MAP_PATH)
    )
    event_routes = ANIMATION_STATE_CONTRACT.normalized_event_routes(
        state_slots,
        workshop_repository.load_event_routes(ANIMATION_MAP_PATH)
    )
    presentation_router.configure(state_slots, state_rules, event_routes)
    if not state_slot_keys.is_empty():
        selected_state_slot = state_slot_keys[0]

func _save_state_slots() -> void:
    state_rules = ANIMATION_STATE_CONTRACT.normalized_rules(state_slots, state_rules)
    if not workshop_repository.save_state_authoring(
        ANIMATION_MAP_PATH,
        state_slots,
        state_rules,
        event_routes
    ):
        status_label.text = "Could not save the runtime animation map."


func _save_animation_states() -> void:
    _save_state_slots()
    if status_label:
        status_label.text = "Animation states saved. New playtests will use these clips and blend settings."


func _refresh_state_rule_editor() -> void:
    if state_condition_label == null or not state_rules.has(selected_state_slot):
        return
    state_rule_syncing = true
    var rule: Dictionary = state_rules[selected_state_slot]
    state_condition_label.text = "WHEN: %s" % ANIMATION_STATE_CONTRACT.condition_summary(
        selected_state_slot
    )
    var layer_name := String(rule.get("layer", ANIMATION_STATE_CONTRACT.FULL_BODY))
    var layer_index := 0
    for index in state_layer_selector.item_count:
        if String(state_layer_selector.get_item_metadata(index)) == layer_name:
            layer_index = index
            break
    state_layer_selector.select(layer_index)
    state_layer_selector.disabled = not ANIMATION_STATE_CONTRACT.state_supports_layer_choice(
        selected_state_slot
    )
    state_layer_selector.tooltip_text = (
        "Action states may replace only the torso and arms. Locomotion must retain whole-body ownership."
        if state_layer_selector.disabled
        else "Choose whether this action replaces the complete body or only the torso and arms."
    )
    state_blend_in_control.value = float(rule.get("blend_in_seconds", 0.12))
    state_blend_out_control.value = float(rule.get("blend_out_seconds", 0.14))
    var return_state := String(rule.get("return_state", selected_state_slot))
    for index in state_return_selector.item_count:
        if String(state_return_selector.get_item_metadata(index)) == return_state:
            state_return_selector.select(index)
            break
    var return_label := (
        "current movement / stance"
        if return_state == ANIMATION_STATE_CONTRACT.CURRENT_BASE
        else return_state
    )
    state_rule_summary_label.text = "%s • %.2fs in • %.2fs out • returns to %s" % [
        "Torso + arms" if layer_name == ANIMATION_STATE_CONTRACT.UPPER_BODY else "Whole body",
        float(rule.get("blend_in_seconds", 0.12)),
        float(rule.get("blend_out_seconds", 0.14)),
        return_label,
    ]
    var source_rule := String(rule.get("source_rule", "")).strip_edges()
    if not source_rule.is_empty():
        state_rule_summary_label.text += "\nSOCOM RULE: “%s”" % source_rule
    state_rule_syncing = false


func _on_state_layer_selected(index: int) -> void:
    if state_rule_syncing or not state_rules.has(selected_state_slot):
        return
    var rule: Dictionary = state_rules[selected_state_slot]
    rule["layer"] = String(state_layer_selector.get_item_metadata(index))
    state_rules[selected_state_slot] = rule
    _refresh_state_rule_editor()


func _on_state_blend_in_changed(value: float) -> void:
    if state_rule_syncing or not state_rules.has(selected_state_slot):
        return
    var rule: Dictionary = state_rules[selected_state_slot]
    rule["blend_in_seconds"] = value
    state_rules[selected_state_slot] = rule
    _refresh_state_rule_editor()


func _on_state_blend_out_changed(value: float) -> void:
    if state_rule_syncing or not state_rules.has(selected_state_slot):
        return
    var rule: Dictionary = state_rules[selected_state_slot]
    rule["blend_out_seconds"] = value
    state_rules[selected_state_slot] = rule
    _refresh_state_rule_editor()


func _on_state_return_selected(index: int) -> void:
    if state_rule_syncing or not state_rules.has(selected_state_slot):
        return
    var rule: Dictionary = state_rules[selected_state_slot]
    rule["return_state"] = String(state_return_selector.get_item_metadata(index))
    state_rules[selected_state_slot] = rule
    _refresh_state_rule_editor()


func _preview_selected_state_transition(base_state_override: String = "") -> void:
    var selected_path := String(state_slots.get(selected_state_slot, ""))
    if selected_path.is_empty():
        status_label.text = "Assign a clip to this state before previewing it."
        return
    state_preview_serial += 1
    var preview_id := state_preview_serial
    var rule: Dictionary = state_rules.get(
        selected_state_slot,
        ANIMATION_STATE_CONTRACT.default_rule(selected_state_slot)
    )
    var layer_name := String(rule.get(
        "layer",
        ANIMATION_STATE_CONTRACT.FULL_BODY
    ))
    var base_state := (
        base_state_override
        if not base_state_override.is_empty()
        else _contextual_preview_return_state(selected_state_slot)
    )
    var base_path := String(state_slots.get(base_state, ""))
    if not _play_state_resource(
        selected_path,
        float(rule.get("blend_in_seconds", 0.12)),
        base_path,
        layer_name
    ):
        status_label.text = "The assigned clip could not be loaded for preview."
        return
    status_label.text = (
        "Layered preview: %s controls torso + arms; %s keeps the legs."
        % [selected_state_slot, base_state]
        if layer_name == ANIMATION_STATE_CONTRACT.UPPER_BODY and not base_path.is_empty()
        else "Whole-body preview: %s." % selected_state_slot
    )
    var current_animation := animation_player.get_animation(animation_player.current_animation)
    var hold_seconds := minf(
        (current_animation.length if current_animation else 0.35) / maxf(playback_speed, 0.01),
        2.0
    )
    await get_tree().create_timer(maxf(hold_seconds, 0.15)).timeout
    if preview_id != state_preview_serial:
        return
    var return_state := String(rule.get("return_state", selected_state_slot))
    if return_state == ANIMATION_STATE_CONTRACT.CURRENT_BASE:
        return_state = _contextual_preview_return_state(selected_state_slot)
    var return_path := String(state_slots.get(return_state, ""))
    if not return_path.is_empty():
        _play_state_resource(
            return_path,
            float(rule.get("blend_out_seconds", 0.14))
        )


func _contextual_preview_return_state(state_name: String) -> String:
    if state_name.begins_with("prone_"):
        return "idle_prone"
    if state_name.begins_with("crouch_"):
        return "idle_crouch"
    return "aim_idle" if state_slots.has("aim_idle") else "idle_rifle"


func _run_animation_state_demo() -> void:
    _show_editor_page("States")
    if not state_slots.has("combat_fire"):
        status_label.text = "The combat fire state is not mapped yet."
        return
    selected_state_slot = "combat_fire"
    _select_state_slot_in_selector(selected_state_slot)
    _refresh_slot_ui()
    selected_animation_event = "FIRE_ACCEPTED"
    _select_animation_event(selected_animation_event)
    natural_language_state_input.text = (
        "When a valid rifle shot happens, play Firing Rifle on the torso and arms. "
        + "Blend in over 0.04 seconds, blend out over 0.10 seconds, "
        + "and return to the current aim movement."
    )
    _propose_natural_language_state()
    status_label.text = "DEMO: Review the FIRE_ACCEPTED proposal. Nothing changes until you approve and save it."
    await get_tree().create_timer(0.8).timeout
    for shot_index in range(3):
        _preview_selected_state_transition()
        if shot_index == 0:
            await get_tree().create_timer(0.22).timeout
            await RenderingServer.frame_post_draw
            get_viewport().get_texture().get_image().save_png(
                "/private/tmp/socom-animation-event-graph-demo.png"
            )
            await get_tree().create_timer(1.98).timeout
        else:
            await get_tree().create_timer(2.2).timeout
        if shot_index < 2:
            await get_tree().create_timer(0.45).timeout
    status_label.text = "DEMO COMPLETE: proposal remains unsaved until you approve it."


func _preview_presentation_effects(presentation: Dictionary, posture: String) -> void:
    var effects: Array = presentation.get("effects", [])
    if ANIMATION_STATE_CONTRACT.RAIL_TO_BLUE_LINE not in effects:
        return
    if _animation_preview_is_full_body_mobility():
        _reset_state_event_weapon_solver()
        # A jump still accepts and previews the shot, but the full-body clip
        # keeps ownership of both arms and the right-hand rifle.  Pulse the
        # fixed authoritative reticle instead of applying the ready solver and
        # twisting the airborne pose.
        if animation_studio_aim_reticle != null:
            animation_studio_aim_reticle.call("notify_shot", 1, 1.0)
        status_label.text = (
            "FIRE_ACCEPTED PREVIEW: shot and reticle kick shown. This jump / mobility clip "
            + "keeps the whole body and right-hand rifle; ready aim begins after landing."
        )
        return
    if not _ensure_state_event_weapon_solver():
        status_label.text = "The animation played, but the shared blue-line weapon solver is unavailable."
        return
    _clear_state_event_return_pose()
    state_event_return_animation_path = ""
    if ANIMATION_STATE_CONTRACT.ENTER_READY_AIM in effects:
        var ready_transition := _state_event_ready_transition()
        var ready_path := String(ready_transition.get("ready_path", ""))
        state_event_return_animation_path = String(
            ready_transition.get("return_path", "")
        )
        state_event_return_animation_blend_seconds = float(
            presentation.get("blend_out_seconds", 0.10)
        )
        if not ready_path.is_empty():
            _play_state_resource(
                ready_path,
                float(presentation.get("blend_in_seconds", 0.04))
            )
    # Capture the fixed yellow reticle direction once. The event can then lift
    # the rifle rail to that blue line while later orbit input remains visual
    # inspection only.
    state_event_effect_forward_direction = _state_event_reticle_direction_world()
    state_event_effect_posture = StringName(posture)
    state_event_effect_active_seconds = 0.65
    state_event_effect_release_seconds = STATE_EVENT_RETURN_SECONDS
    state_event_weapon_solver.call(
        "trigger_rail_to_blue_line",
        state_event_effect_active_seconds
    )
    status_label.text = (
        "FIRE_ACCEPTED: enter ready aim, raise the rail to the fixed yellow reticle, then return to current movement."
    )


func _state_event_ready_transition() -> Dictionary:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return {}
    var entry: Dictionary = filtered_entries[clip_index]
    var return_path := String(entry.get("path", ""))
    var source_slot := ""
    for raw_slot in state_slots.keys():
        var slot_name := String(raw_slot)
        if String(state_slots[slot_name]) == return_path:
            source_slot = slot_name
            break
    if source_slot.is_empty():
        source_slot = workshop_repository.suggest_slot(entry)
    var ready_slot := ""
    if source_slot == "idle_rifle":
        ready_slot = "aim_idle"
    elif source_slot.begins_with("run_"):
        ready_slot = "walk_" + source_slot.trim_prefix("run_")
    elif source_slot.begins_with("walk_"):
        ready_slot = source_slot
    if ready_slot.is_empty() or not state_slots.has(ready_slot):
        return {"return_path": return_path}
    return {
        "ready_state": ready_slot,
        "ready_path": String(state_slots.get(ready_slot, "")),
        "return_path": return_path,
    }


func _state_event_reticle_direction_world() -> Vector3:
    var desired := _animation_placement_direction_world().normalized()
    # The authored blue line is reticle-locked. Do not silently replace it with
    # body or barrel forward when Preview Fire starts; that made the reference
    # jump at the exact moment the rifle was supposed to move toward it.
    if desired.length_squared() > 0.50:
        return desired
    var barrel_direction := _state_event_barrel_direction_world().normalized()
    if barrel_direction.length_squared() > 0.50:
        return barrel_direction
    return (-global_basis.z).normalized()


func _state_event_barrel_direction_world() -> Vector3:
    if weapon_barrel_base_marker != null and weapon_muzzle_marker != null:
        var barrel_direction := (
            weapon_muzzle_marker.global_position
            - weapon_barrel_base_marker.global_position
        ).normalized()
        if barrel_direction.length_squared() > 0.50:
            return barrel_direction
    var fallback := _animation_placement_direction_world().normalized()
    if fallback.length_squared() > 0.50:
        return fallback
    return skeleton.global_basis.z.normalized() if skeleton != null else Vector3.FORWARD


func _ensure_state_event_weapon_solver() -> bool:
    if (
        state_event_weapon_solver != null
        and is_instance_valid(state_event_weapon_solver)
        and state_event_weapon_solver.get("weapon_node") == weapon_node
    ):
        return true
    _reset_state_event_weapon_solver()
    if skeleton == null or weapon_node == null or gunsmith_weapon_config.is_empty():
        return false
    state_event_weapon_solver = OPERATOR_WEAPON_POSE_SOLVER_SCRIPT.new()
    state_event_weapon_solver.name = "AnimationStateEventWeaponSolver"
    add_child(state_event_weapon_solver)
    state_event_weapon_solver.call("bind", skeleton, weapon_node)
    state_event_weapon_solver.call(
        "configure_joint_poles",
        gunsmith_weapon_config.get("elbow_poles", {})
    )
    var handling: Variant = gunsmith_weapon_config.get("handling_profile", {})
    if handling is Dictionary:
        state_event_weapon_solver.call("configure_dynamic_hold", handling)
    state_event_weapon_solver.call(
        "configure_gun_placement_line",
        gunsmith_weapon_config.get("gun_placement_line", {})
    )
    state_event_head_look_layer = OPERATOR_POSTURE_LAYER_SCRIPT.new()
    state_event_head_look_layer.bind(skeleton)
    return true


func _update_state_event_effect_preview(delta: float) -> bool:
    if state_event_weapon_solver == null or not is_instance_valid(state_event_weapon_solver):
        return false
    if active_editor_page != "States":
        _reset_state_event_weapon_solver()
        return false
    if state_event_effect_active_seconds <= 0.0 and state_event_effect_release_seconds <= 0.0:
        return false
    if state_event_effect_active_seconds > 0.0:
        var placement_origin := _animation_placement_origin_world()
        var placement_direction := state_event_effect_forward_direction.normalized()
        if placement_direction.length_squared() < 0.50:
            placement_direction = _state_event_barrel_direction_world()
        var world_target := placement_origin + placement_direction * 120.0
        if state_event_head_look_layer != null:
            state_event_head_look_radians = state_event_head_look_layer.apply_head_look_at(
                world_target,
                1.0,
                deg_to_rad(56.0),
                deg_to_rad(34.0)
            )
        state_event_weapon_solver.call(
            "apply",
            0.0,
            0.0,
            state_event_effect_posture,
            &"LOCOMOTION",
            1.0,
            0.0,
            &"",
            false,
            world_target,
            self,
            delta
        )
        state_event_effect_active_seconds = maxf(
            state_event_effect_active_seconds - delta,
            0.0
        )
        if state_event_effect_active_seconds <= 0.0:
            _capture_state_event_return_pose()
    else:
        _apply_state_event_return_blend()
        state_event_effect_release_seconds = maxf(
            state_event_effect_release_seconds - delta,
            0.0
        )
        if state_event_effect_release_seconds <= 0.0:
            _clear_state_event_return_pose()
            state_event_weapon_solver.call("release_visual_control")
            # The gameplay solver returns the rifle to its hand parent while
            # preserving world space. That is correct during a live blend, but
            # the Studio must then restore the canonical Gunsmith hand-local
            # mount. Otherwise the completed event leaves a large local offset
            # and the rifle appears to vanish until the next preview.
            animation_weapon_ownership_preview.restore_hand_mount()
            if not state_event_return_animation_path.is_empty():
                _play_state_resource(
                    state_event_return_animation_path,
                    state_event_return_animation_blend_seconds
                )
                state_event_return_animation_path = ""
    return true


func _capture_state_event_return_pose() -> void:
    state_event_return_bone_poses.clear()
    if skeleton == null:
        return
    skeleton.force_update_all_bone_transforms()
    for candidates in STATE_EVENT_RETURN_BONE_CANDIDATES:
        var bone_index := -1
        for candidate in candidates:
            bone_index = skeleton.find_bone(String(candidate))
            if bone_index >= 0:
                break
        if bone_index >= 0:
            state_event_return_bone_poses[bone_index] = skeleton.get_bone_global_pose(
                bone_index
            )
    if weapon_node != null:
        state_event_return_weapon_transform = weapon_node.global_transform
    state_event_return_blend_weight = 1.0
    state_event_return_pose_captured = not state_event_return_bone_poses.is_empty()


func _apply_state_event_return_blend() -> void:
    if not state_event_return_pose_captured or skeleton == null:
        return
    var linear_weight := clampf(
        state_event_effect_release_seconds / STATE_EVENT_RETURN_SECONDS,
        0.0,
        1.0
    )
    state_event_return_blend_weight = linear_weight * linear_weight * (
        3.0 - 2.0 * linear_weight
    )
    for bone_index_variant in state_event_return_bone_poses.keys():
        var bone_index := int(bone_index_variant)
        var captured_pose: Transform3D = state_event_return_bone_poses[bone_index]
        skeleton.set_bone_global_pose_override(
            bone_index,
            captured_pose,
            state_event_return_blend_weight,
            true
        )
    skeleton.force_update_all_bone_transforms()
    if (
        weapon_node != null
        and socket_attachment != null
        and animation_weapon_ownership_preview.has_hand_local_transform
    ):
        var movement_weapon_transform: Transform3D = (
            socket_attachment.global_transform
            * animation_weapon_ownership_preview.hand_local_transform
        )
        weapon_node.global_transform = state_event_return_weapon_transform.interpolate_with(
            movement_weapon_transform,
            1.0 - state_event_return_blend_weight
        )
    state_event_head_look_radians *= state_event_return_blend_weight


func _clear_state_event_return_pose() -> void:
    if skeleton != null and state_event_return_pose_captured:
        skeleton.clear_bones_global_pose_override()
        skeleton.force_update_all_bone_transforms()
    state_event_return_bone_poses.clear()
    state_event_return_weapon_transform = Transform3D.IDENTITY
    state_event_return_blend_weight = 0.0
    state_event_return_pose_captured = false


func _reset_state_event_weapon_solver() -> void:
    _clear_state_event_return_pose()
    state_event_effect_active_seconds = 0.0
    state_event_effect_release_seconds = 0.0
    state_event_effect_forward_direction = Vector3.ZERO
    state_event_return_animation_path = ""
    state_event_head_look_radians = Vector2.ZERO
    if state_event_head_look_layer != null:
        state_event_head_look_layer.clear_head_look_additive()
    state_event_head_look_layer = null
    if state_event_weapon_solver == null or not is_instance_valid(state_event_weapon_solver):
        state_event_weapon_solver = null
        return
    state_event_weapon_solver.call("release_visual_control")
    animation_weapon_ownership_preview.restore_hand_mount()
    state_event_weapon_solver.queue_free()
    state_event_weapon_solver = null


func _play_state_resource(
    resource_path: String,
    blend_seconds: float,
    base_resource_path: String = "",
    layer_name: String = ANIMATION_STATE_CONTRACT.FULL_BODY
) -> bool:
    var entry := workshop_repository.entry_for_path(all_clip_entries, resource_path)
    if entry.is_empty() or animation_player == null:
        return false
    _set_animation_preview_ownership(entry)
    _apply_gunsmith_hand_map_for_entry(entry)
    match String(entry.get("type", "")):
        "FBX":
            _load_and_retarget_fbx(entry)
        "AUTHORED":
            _load_authored_animation(entry)
    var clip_name := StringName(entry.get("name", ""))
    var animation := _get_current_animation(entry)
    if animation == null or not animation_player.has_animation(clip_name):
        return false
    if (
        layer_name == ANIMATION_STATE_CONTRACT.UPPER_BODY
        and not base_resource_path.is_empty()
    ):
        var base_entry := workshop_repository.entry_for_path(
            all_clip_entries,
            base_resource_path
        )
        if not base_entry.is_empty():
            match String(base_entry.get("type", "")):
                "FBX":
                    _load_and_retarget_fbx(base_entry)
                "AUTHORED":
                    _load_authored_animation(base_entry)
            var base_animation := _get_current_animation(base_entry)
            if base_animation != null:
                var layered_preview := layer_composer.compose({
                    "duration_reference": animation,
                    "lower_body": base_animation,
                    "torso": animation,
                    "left_arm": animation,
                    "right_arm": animation,
                    "head": animation,
                }, EDITOR_FPS)
                if layered_preview != null and layered_preview.get_track_count() > 0:
                    var preview_key := StringName("state_upper_body_preview")
                    if dynamic_anim_lib.has_animation(preview_key):
                        dynamic_anim_lib.remove_animation(preview_key)
                    layered_preview.loop_mode = Animation.LOOP_NONE
                    dynamic_anim_lib.add_animation(preview_key, layered_preview)
                    animation_player.speed_scale = playback_speed
                    _sync_animation_preview_weapon_parent()
                    animation_player.play(
                        StringName("dyn/%s" % preview_key),
                        maxf(blend_seconds, 0.0)
                    )
                    is_playing = true
                    return true
    animation.loop_mode = (
        Animation.LOOP_LINEAR
        if _should_loop(String(entry.get("display", "")))
        else Animation.LOOP_NONE
    )
    animation_player.speed_scale = playback_speed
    _sync_animation_preview_weapon_parent()
    animation_player.play(clip_name, maxf(blend_seconds, 0.0))
    is_playing = true
    return true

func _save_animation_work_and_play_latest() -> void:
    # One project-level commit: animation routes, authored body recipe, review
    # shortlist, and the authoritative Gunsmith rig selection all survive the
    # scene change into the integration playground.
    _save_state_slots()
    _save_highlighted_shortlist()
    _save_layer_recipe()
    var weapon_rig_path := _save_linked_gunsmith_profile()
    if status_label:
        status_label.text = (
            "Project saved with weapon rig %s. Opening the latest playground…" % weapon_rig_path.get_file()
            if not weapon_rig_path.is_empty()
            else "Animation work saved. No compatible Gunsmith profile is available for this preview weapon."
        )
    if weapon_rig_path.is_empty():
        return
    call_deferred("_open_latest_playground")

func _save_linked_gunsmith_profile() -> String:
    var rig_config_path := ""
    var weapon_id := ""
    if FileAccess.file_exists(WEAPON_LOADOUT_PATH):
        var existing_file := FileAccess.open(WEAPON_LOADOUT_PATH, FileAccess.READ)
        var existing_value: Variant = JSON.parse_string(existing_file.get_as_text()) if existing_file else null
        if existing_value is Dictionary:
            rig_config_path = String((existing_value as Dictionary).get("rig_config", ""))
            weapon_id = String((existing_value as Dictionary).get("primary_weapon_id", ""))
    if rig_config_path.is_empty() or not FileAccess.file_exists(rig_config_path):
        var fallback_ids := {
            WeaponType.M4A1_SOPMOD: "assaultrifle_1",
            WeaponType.MP5_SD: "submachinegun_1",
            WeaponType.AK_47: "ak-47",
        }
        weapon_id = String(fallback_ids.get(current_weapon, ""))
        rig_config_path = "res://config/weapons/%s.json" % weapon_id if not weapon_id.is_empty() else ""
    if rig_config_path.is_empty() or not FileAccess.file_exists(rig_config_path):
        return ""
    var config_file := FileAccess.open(rig_config_path, FileAccess.READ)
    var config_value: Variant = JSON.parse_string(config_file.get_as_text()) if config_file else null
    if not config_value is Dictionary:
        return ""
    var config: Dictionary = config_value as Dictionary
    weapon_id = String(config.get("weapon_id", weapon_id))
    var loadout_file := FileAccess.open(WEAPON_LOADOUT_PATH, FileAccess.WRITE)
    if loadout_file == null:
        return ""
    loadout_file.store_string(JSON.stringify({
        "schema_version": 1,
        "primary_weapon_id": weapon_id,
        "rig_config": rig_config_path,
        "saved_by": "animation_workshop",
    }, "  "))
    return rig_config_path

func _open_latest_playground() -> void:
    var change_error := get_tree().change_scene_to_file("res://main.tscn")
    if change_error != OK and status_label:
        status_label.text = "Could not open the latest playground (%s)." % error_string(change_error)

func _merge_state_slots_into_config(existing_config: Dictionary) -> Dictionary:
    var merged := existing_config.duplicate(true)
    merged["clips"] = state_slots.duplicate(true)
    return merged

func _weapon_name(wep: WeaponType) -> String:
    match wep:
        WeaponType.M4A1_SOPMOD: return "M4A1 SOPMOD Rifle"
        WeaponType.MP5_SD: return "MP5-SD Submachine Gun"
        WeaponType.COMBAT_PISTOL: return "9mm Combat Pistol"
        WeaponType.AK_47: return "AK-47 Assault Rifle"
        WeaponType.NONE: return "Holstered (None)"
    return "Unknown"

func _gunsmith_fallback_weapon_id() -> String:
    match current_weapon:
        WeaponType.M4A1_SOPMOD: return "assaultrifle_1"
        WeaponType.MP5_SD: return "submachinegun_1"
        WeaponType.COMBAT_PISTOL: return "9mm_pistol"
        WeaponType.AK_47: return "ak-47"
    return ""

func _attach_saved_gunsmith_weapon() -> bool:
    var config_path: String = WEAPON_RIG_PREVIEW.resolve_config_path(_gunsmith_fallback_weapon_id())
    gunsmith_weapon_config = WEAPON_RIG_PREVIEW.load_config(config_path)
    if gunsmith_weapon_config.is_empty():
        return false
    var mount: Dictionary = gunsmith_weapon_config.get("operator_mount", {})
    right_grip_pos = WEAPON_RIG_PREVIEW.vector3_from_map(mount.get("position", {}), right_grip_pos)
    right_grip_rot = WEAPON_RIG_PREVIEW.vector3_from_map(mount.get("rotation_degrees", {}), right_grip_rot)
    var factor := _weapon_attachment_inverse_scale()
    var attached: Dictionary = WEAPON_RIG_PREVIEW.attach_to_hand(
        gunsmith_weapon_config,
        socket_attachment,
        right_grip_pos,
        right_grip_rot,
        factor
    )
    if attached.is_empty():
        gunsmith_weapon_config.clear()
        return false
    weapon_node = attached.get("weapon_root") as Node3D
    weapon_calibrated_pivot = attached.get("calibrated_pivot") as Node3D
    left_hand_marker = attached.get("left_hand") as Marker3D
    right_hand_marker = attached.get("right_hand") as Marker3D
    weapon_muzzle_marker = attached.get("muzzle") as Marker3D
    weapon_barrel_base_marker = attached.get("barrel_base") as Marker3D
    weapon_ejection_marker = attached.get("ejection") as Marker3D
    weapon_optic_marker = attached.get("optic") as Marker3D
    loaded_gunsmith_config_path = config_path
    return true

func _rebuild_weapon_socket() -> void:
    _reset_state_event_weapon_solver()
    animation_weapon_ownership_preview.reset()
    if socket_attachment:
        socket_attachment.queue_free()
        socket_attachment = null
        weapon_node = null
        left_hand_marker = null
        right_hand_marker = null
        weapon_muzzle_marker = null
        weapon_barrel_base_marker = null
        weapon_ejection_marker = null
        weapon_optic_marker = null
        weapon_calibrated_pivot = null
        gunsmith_weapon_config.clear()
        loaded_gunsmith_config_path = ""

    if current_weapon == WeaponType.NONE:
        return

    if skeleton == null:
        if model_root:
            weapon_node = Node3D.new()
            weapon_node.name = "AttachedWeapon"
            weapon_node.position = Vector3(-0.20, 0.95, 0.22)
            weapon_node.rotation_degrees = Vector3(0, 0, 0)
            var weapon_mesh := _create_weapon_mesh(current_weapon)
            weapon_node.add_child(weapon_mesh)
            model_root.add_child(weapon_node)
        return

    # Attach weapon directly to the active Right Hand bone
    var target_bone := "mixamorig_RightHand"
    if skeleton.find_bone("mixamorig_RightHand") != -1:
        target_bone = "mixamorig_RightHand"
    elif skeleton.find_bone("mixamorig:RightHand") != -1:
        target_bone = "mixamorig:RightHand"
    elif skeleton.find_bone("Hand.R.001") != -1:
        target_bone = "Hand.R.001"
    elif skeleton.find_bone("HandWrist.R") != -1:
        target_bone = "HandWrist.R"
    elif skeleton.find_bone("Bip01 R Hand") != -1:
        target_bone = "Bip01 R Hand"

    socket_attachment = BoneAttachment3D.new()
    socket_attachment.name = "WeaponSocketAttachment"
    socket_attachment.bone_name = target_bone
    skeleton.add_child(socket_attachment)

    # Imported model, both hand targets, muzzle/ejection/optic sockets and
    # animation hand maps all come from the profile saved by the Gunsmith.
    if _attach_saved_gunsmith_weapon():
        return

    weapon_node = Node3D.new()
    weapon_node.name = "AttachedWeapon"
    _sync_weapon_node_transform()

    # Build the 3D Weapon Mesh
    var weapon_mesh := _create_weapon_mesh(current_weapon)
    weapon_node.add_child(weapon_mesh)

    # Left Hand Handguard Target Socket
    left_hand_marker = Marker3D.new()
    left_hand_marker.name = "LeftHandGripTarget"
    left_hand_marker.position = left_handguard_pos
    weapon_node.add_child(left_hand_marker)

    socket_attachment.add_child(weapon_node)

func _sync_weapon_node_transform() -> void:
    if weapon_node == null:
        return
    var factor := _weapon_attachment_inverse_scale()
    weapon_node.position = right_grip_pos * factor
    weapon_node.rotation_degrees = right_grip_rot
    weapon_node.scale = Vector3.ONE * factor * weapon_scale_factor


func _weapon_attachment_inverse_scale() -> float:
    if socket_attachment == null:
        return 1.0
    var inherited_scale := socket_attachment.global_basis.get_scale()
    var average_scale := (
        inherited_scale.x + inherited_scale.y + inherited_scale.z
    ) / 3.0
    return 1.0 / maxf(average_scale, 0.001)

func _hide_baked_rifle_parts(node: Node) -> void:
    if node is MeshInstance3D and ("Rifle" in node.name or "weapon" in node.name.to_lower()):
        node.visible = false
    for child in node.get_children():
        _hide_baked_rifle_parts(child)

func _create_weapon_mesh(wep: WeaponType) -> Node3D:
    var root := Node3D.new()
    var metal := StandardMaterial3D.new()
    metal.albedo_color = Color(0.12, 0.13, 0.15)
    metal.metallic = 0.85
    metal.roughness = 0.35

    var dark_plastic := StandardMaterial3D.new()
    dark_plastic.albedo_color = Color(0.08, 0.09, 0.10)
    dark_plastic.roughness = 0.8

    var wood := StandardMaterial3D.new()
    wood.albedo_color = Color(0.40, 0.22, 0.12)
    wood.roughness = 0.65

    match wep:
        WeaponType.M4A1_SOPMOD:
            left_handguard_pos = Vector3(0.0, 0.02, 0.28)
            _add_box(root, Vector3(0.045, 0.09, 0.28), Vector3(0, 0.02, 0.05), dark_plastic)
            _add_box(root, Vector3(0.038, 0.08, 0.18), Vector3(0, 0.04, -0.16), dark_plastic)
            _add_box(root, Vector3(0.042, 0.055, 0.24), Vector3(0, 0.035, 0.28), dark_plastic)
            _add_cylinder(root, 0.012, 0.20, Vector3(0, 0.035, 0.46), metal)
            _add_cylinder(root, 0.018, 0.12, Vector3(0, 0.035, 0.58), metal)
            _add_box(root, Vector3(0.026, 0.16, 0.075), Vector3(0, -0.08, 0.12), metal, Vector3(14, 0, 0))
            _add_box(root, Vector3(0.034, 0.045, 0.08), Vector3(0, 0.095, 0.10), dark_plastic)
            _add_box(root, Vector3(0.032, 0.11, 0.045), Vector3(0, -0.06, 0.0), dark_plastic, Vector3(-20, 0, 0))

        WeaponType.MP5_SD:
            left_handguard_pos = Vector3(0.0, 0.015, 0.22)
            _add_box(root, Vector3(0.04, 0.07, 0.24), Vector3(0, 0.02, 0.06), metal)
            _add_cylinder(root, 0.026, 0.28, Vector3(0, 0.025, 0.28), dark_plastic)
            _add_box(root, Vector3(0.022, 0.15, 0.045), Vector3(0, -0.07, 0.12), metal, Vector3(18, 0, 0))
            _add_box(root, Vector3(0.03, 0.10, 0.04), Vector3(0, -0.05, 0.0), dark_plastic, Vector3(-22, 0, 0))
            _add_box(root, Vector3(0.035, 0.06, 0.14), Vector3(0, 0.03, -0.12), metal)

        WeaponType.COMBAT_PISTOL:
            left_handguard_pos = Vector3(-0.025, -0.01, 0.02)
            _add_box(root, Vector3(0.03, 0.038, 0.19), Vector3(0, 0.04, 0.06), metal)
            _add_box(root, Vector3(0.028, 0.11, 0.048), Vector3(0, -0.03, 0.02), dark_plastic, Vector3(-16, 0, 0))
            _add_box(root, Vector3(0.015, 0.035, 0.04), Vector3(0, -0.01, 0.07), dark_plastic)

        WeaponType.AK_47:
            left_handguard_pos = Vector3(0.0, 0.05, 0.32)
            var ak_pivot := Node3D.new()
            ak_pivot.name = "AK47_Pivot"
            
            var ak_inst := AK47_FBX_SCENE.instantiate() as Node3D
            # Scale from FBX units (29.2 units long) to real rifle length (0.88m)
            ak_inst.scale = Vector3.ONE * 0.030
            # Offset so the pistol grip / trigger is right at (0,0,0)
            ak_inst.position = Vector3(0.0, 0.02, -0.05)
            ak_inst.rotation_degrees = Vector3(0, 180, 0)
            
            # Apply texture
            var ak_mat := StandardMaterial3D.new()
            ak_mat.albedo_texture = AK47_TEXTURE
            for child in ak_inst.get_children():
                if child is MeshInstance3D:
                    child.material_override = ak_mat
                for grandchild in child.get_children():
                    if grandchild is MeshInstance3D:
                        grandchild.material_override = ak_mat
            ak_pivot.add_child(ak_inst)
            root.add_child(ak_pivot)

    return root

func _add_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, rot_deg: Vector3 = Vector3.ZERO) -> void:
    var mi := MeshInstance3D.new()
    var box := BoxMesh.new()
    box.size = size
    mi.mesh = box
    mi.position = pos
    mi.rotation_degrees = rot_deg
    mi.material_override = mat
    parent.add_child(mi)

func _add_cylinder(parent: Node3D, radius: float, height: float, pos: Vector3, mat: Material) -> void:
    var mi := MeshInstance3D.new()
    var cyl := CylinderMesh.new()
    cyl.top_radius = radius
    cyl.bottom_radius = radius
    cyl.height = height
    mi.mesh = cyl
    mi.position = pos
    mi.rotation_degrees = Vector3(90, 0, 0)
    mi.material_override = mat
    parent.add_child(mi)

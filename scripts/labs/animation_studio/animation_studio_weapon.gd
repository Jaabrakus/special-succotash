extends "res://scripts/labs/animation_studio/animation_studio_sequence.gd"

func _toggle_skin() -> void:
    var next_idx := (int(current_skin) + 1) % 5
    _load_skin(next_idx as SkinType)

func _skin_name(skin: SkinType) -> String:
    match skin:
        SkinType.PS1_GAS_MASK_SOLDIER: return "PS1 Gas Mask Trooper (Rigged & Skinned)"
        SkinType.MILITARY_TACTICAL_OPERATOR: return "Military Tactical Suit (Game-Ready 87-Bone)"
        SkinType.SOCOM_OPERATOR: return "SOCOM Operator (Authored Rig)"
        SkinType.MIXAMO_MANNEQUIN: return "Mixamo Beta Skin"
        SkinType.PS1_NIGHT_VISION_SEAL: return "PS1 Night Vision SEAL"
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
    filtered_entries = workshop_repository.filter_entries(all_clip_entries, cat)
    clip_index = 0
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
    state_slots[slot_name] = resource_path
    _save_state_slots()
    _refresh_slot_ui()
    status_label.text = "%s is now bound to %s." % [str(entry.get("display", resource_path.get_file())), slot_name]

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

func _load_state_slots() -> void:
    state_slots = workshop_repository.load_state_slots(ANIMATION_MAP_PATH)
    state_slot_keys.clear()
    for slot_name in state_slots.keys():
        state_slot_keys.append(str(slot_name))
    state_slot_keys.sort()
    if not state_slot_keys.is_empty():
        selected_state_slot = state_slot_keys[0]

func _save_state_slots() -> void:
    if not workshop_repository.save_state_slots(ANIMATION_MAP_PATH, state_slots):
        status_label.text = "Could not save the runtime animation map."

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
    var factor := (1.0 / model_root.scale.x) if (model_root and model_root.scale.x > 1.5) else 1.0
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
    loaded_gunsmith_config_path = config_path
    return true

func _rebuild_weapon_socket() -> void:
    if socket_attachment:
        socket_attachment.queue_free()
        socket_attachment = null
        weapon_node = null
        left_hand_marker = null
        right_hand_marker = null
        weapon_muzzle_marker = null
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
    var factor := (1.0 / model_root.scale.x) if (model_root and model_root.scale.x > 1.5) else 1.0
    weapon_node.position = right_grip_pos * factor
    weapon_node.rotation_degrees = right_grip_rot
    weapon_node.scale = Vector3.ONE * factor * weapon_scale_factor

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

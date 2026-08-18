extends Node3D

const PS1_GAS_MASK_RIGGED_SCENE := preload("res://assets/characters/ps1_gas_mask_soldier/trooper_rigged.fbx")
const MILITARY_TACTICAL_SCENE := preload("res://assets/characters/military_tactical_operator/Anim_Idle_MIL_R5.fbx")
const OPERATOR_SCENE := preload("res://assets/characters/operator3d/socom_141_operator_animated.glb")
const MIXAMO_SKIN_SCENE := preload("res://assets/characters/operator3d/mixamo_beta_skin.glb")
const PS1_NV_SCENE := preload("res://assets/characters/ps1_night_vision_operator/NVoperatorsoldier.glb")
const PS1_GAS_MASK_OBJ := preload("res://assets/characters/ps1_gas_mask_soldier/sasman5.obj")
const PS1_GAS_MASK_TEX := preload("res://assets/characters/ps1_gas_mask_soldier/trooper.png")
const AK47_FBX_SCENE := preload("res://assets/weapons/ps1_ak47/source/ak-47.fbx")
const AK47_TEXTURE := preload("res://assets/weapons/ps1_ak47/textures/AK-47TextureMap.png")
const ANIMATION_MAP_PATH := "res://config/operator_animation_map.json"
const HIGHLIGHT_SHORTLIST_PATH := "res://config/highlighted_animation_candidates.json"
const AUTHORED_ANIMATION_DIR := "res://assets/animations/authored"
const CLIP_DRAG_BUTTON := preload("res://scripts/labs/animation_clip_drag_button.gd")
const SLOT_DROP_TARGET := preload("res://scripts/labs/animation_slot_drop_target.gd")
const STATE_TREE_DROP := preload("res://scripts/labs/animation_state_tree_drop.gd")
const ROUTE_GRAPH := preload("res://scripts/labs/animation_route_graph.gd")
const CLIP_EDITOR_SCRIPT := preload("res://scripts/labs/animation_clip_editor.gd")
const ROOT_SANITIZER := preload("res://scripts/player/operator_animation_root_sanitizer.gd")
const EDITOR_FPS := 30.0

enum SkinType {
    PS1_GAS_MASK_SOLDIER,
    MILITARY_TACTICAL_OPERATOR,
    SOCOM_OPERATOR,
    MIXAMO_MANNEQUIN,
    PS1_NIGHT_VISION_SEAL
}

enum WeaponType {
    M4A1_SOPMOD,
    MP5_SD,
    COMBAT_PISTOL,
    AK_47,
    NONE
}

var current_skin: SkinType = SkinType.PS1_GAS_MASK_SOLDIER
var current_weapon: WeaponType = WeaponType.AK_47
var model_root: Node3D
var animation_player: AnimationPlayer
var skeleton: Skeleton3D

# Animation lists
var baked_clips: Array[StringName] = []
var fbx_files: Dictionary = {}
var authored_animation_files: Dictionary = {}
var all_clip_entries: Array[Dictionary] = []
var filtered_entries: Array[Dictionary] = []
var highlighted_clip_entries: Array[Dictionary] = []
var highlight_shortlist_loaded: bool = false
var clip_index: int = 0
var current_category: String = "ALL"
var dynamic_anim_lib: AnimationLibrary

# Playback controls
var is_playing: bool = true
var playback_speed: float = 1.0
var trim_in_seconds: float = 0.0
var trim_out_seconds: float = 0.0
var assembly_segments: Array[Dictionary] = []
var clip_editor = CLIP_EDITOR_SCRIPT.new()
var weapon_socket_visible: bool = true
var weapon_node: Node3D
var socket_attachment: BoneAttachment3D
var left_hand_marker: Marker3D

# Two-Hand Gun Engine Offsets
var right_grip_pos := Vector3(-0.02, 0.08, 0.05)
var right_grip_rot := Vector3(-90.0, 180.0, 0.0)
var left_handguard_pos := Vector3(0.0, 0.02, 0.28)
var two_hand_ik_enabled: bool = true
var two_hand_ik_weight: float = 1.0
var weapon_scale_factor: float = 1.0
var gun_sliders: Dictionary = {}

# 3D Draggable Limb Bubbles System
var bubbles_enabled: bool = true
var bubble_nodes: Dictionary = {} # BoneName -> {mesh: MeshInstance3D, bone_idx: int, color: Color}
var active_dragged_bone: String = ""
var drag_start_mouse: Vector2 = Vector2.ZERO
var bone_rot_offsets: Dictionary = {} # BoneName -> Vector3 (euler angles in degrees)
var bone_pos_offsets: Dictionary = {} # BoneName -> local translation in meters
var bone_edit_base_poses: Dictionary = {} # Stable paused-frame pose; prevents cumulative edits
var pose_edit_mode: StringName = &"ROTATE"
var rotation_degrees_per_pixel: float = 0.18
var translation_meters_per_pixel: float = 0.0015

# Camera Orbit
var camera: Camera3D
var orbit_yaw: float = -0.48
var orbit_pitch: float = -0.10
var orbit_distance: float = 3.6
var target_height: float = 0.95
var dragging: bool = false
var panning: bool = false

# UI Elements
var overlay: CanvasLayer
var status_label: Label
var category_container: HBoxContainer
var clip_scroll: ScrollContainer
var clip_list_vbox: VBoxContainer
var timeline_slider: HSlider
var time_label: Label
var trim_label: Label
var assembly_label: Label
var assembly_drop_label: Label
var assembly_drop_target: PanelContainer
var authored_name_input: LineEdit
var speed_button: Button
var weapon_selector_button: Button
var skin_button: Button
var bubbles_toggle_btn: Button
var pose_tool_button: Button
var slot_panel_label: Label
var slot_suggestion_label: Label
var slot_drop_label: Label
var runtime_route_graph: Control
var state_slot_selector: OptionButton
var gun_lab_panel: PanelContainer
var gun_lab_visible: bool = false
var limb_hud_label: Label

# Gameplay Slot Mappings. Values are FBX resource paths shared with the runtime
# animation driver, so a workbench assignment is immediately authoritative.
var state_slots: Dictionary = {}
var state_slot_keys: Array[String] = []
var selected_state_slot: String = "idle_rifle"

const MIXAMO_TO_PS1_MAP := {
    "mixamorig_Hips": "Spinelower",
    "mixamorig_Spine": "Spinelower",
    "mixamorig_Spine1": "Spineupper",
    "mixamorig_Spine2": "Spineupper",
    "mixamorig_Neck": "Neck",
    "mixamorig_Head": "head",
    "mixamorig_LeftShoulder": "Spineupper",
    "mixamorig_LeftArm": "ArmUpper.L",
    "mixamorig_LeftForeArm": "ArmLower.L",
    "mixamorig_LeftHand": "Hand.L.001",
    "mixamorig_RightShoulder": "Spineupper",
    "mixamorig_RightArm": "ArmUpper.R",
    "mixamorig_RightForeArm": "ArmLower.R",
    "mixamorig_RightHand": "Hand.R.001",
    "mixamorig_LeftUpLeg": "LegThigh.L",
    "mixamorig_LeftLeg": "LegShin.L",
    "mixamorig_LeftFoot": "Foot.L",
    "mixamorig_LeftToeBase": "FootToe.L",
    "mixamorig_RightUpLeg": "LegThigh.R",
    "mixamorig_RightLeg": "LegShin.R",
    "mixamorig_RightFoot": "Foot.R",
    "mixamorig_RightToeBase": "FootToe.R"
}

func _ready() -> void:
    _scan_all_mixamo_fbx()
    _load_state_slots()
    _build_stage()
    _build_ui()
    _load_skin(current_skin)

func _scan_all_mixamo_fbx() -> void:
    fbx_files.clear()
    _scan_dir_recursive("res://assets/animations/mixamo")
    _scan_authored_animations()

func _scan_authored_animations() -> void:
    authored_animation_files.clear()
    var directory := DirAccess.open(AUTHORED_ANIMATION_DIR)
    if directory == null:
        return
    directory.list_dir_begin()
    var file_name := directory.get_next()
    while not file_name.is_empty():
        if not directory.current_is_dir() and file_name.ends_with(".tres"):
            authored_animation_files[file_name.get_basename().capitalize()] = "%s/%s" % [AUTHORED_ANIMATION_DIR, file_name]
        file_name = directory.get_next()

func _scan_dir_recursive(dir_path: String) -> void:
    var dir := DirAccess.open(dir_path)
    if dir:
        dir.list_dir_begin()
        var file_name := dir.get_next()
        while file_name != "":
            if dir.current_is_dir() and not file_name.begins_with("."):
                _scan_dir_recursive(dir_path + "/" + file_name)
            elif file_name.ends_with(".fbx") and not file_name.begins_with("."):
                var full_path := dir_path + "/" + file_name
                var clean_name := file_name.get_basename().capitalize()
                var folder := dir_path.get_file()
                var tag := ""
                if "Pistol" in folder: tag = "[Pistol] "
                elif "Locomotion" in folder or "Lite" in folder: tag = "[Rifle] "
                elif "Shooter" in folder: tag = "[Shooter] "
                clean_name = tag + clean_name
                fbx_files[clean_name] = full_path
            file_name = dir.get_next()

func _load_skin(skin: SkinType) -> void:
    if model_root:
        model_root.queue_free()
        model_root = null
    
    current_skin = skin
    
    match skin:
        SkinType.PS1_GAS_MASK_SOLDIER:
            model_root = PS1_GAS_MASK_RIGGED_SCENE.instantiate() as Node3D
            model_root.scale = Vector3.ONE * 55.0  # Mixamo exported at ~3cm tall, scale to ~1.8m
            _apply_trooper_texture(model_root)

        SkinType.MILITARY_TACTICAL_OPERATOR:
            model_root = MILITARY_TACTICAL_SCENE.instantiate() as Node3D

        SkinType.SOCOM_OPERATOR:
            model_root = OPERATOR_SCENE.instantiate() as Node3D

        SkinType.MIXAMO_MANNEQUIN:
            model_root = MIXAMO_SKIN_SCENE.instantiate() as Node3D

        SkinType.PS1_NIGHT_VISION_SEAL:
            model_root = PS1_NV_SCENE.instantiate() as Node3D
    
    model_root.name = "PreviewOperator"
    model_root.rotation.y = PI
    add_child(model_root)

    if skin == SkinType.SOCOM_OPERATOR:
        _hide_baked_rifle_parts(model_root)

    animation_player = _find_animation_player(model_root)
    skeleton = _find_skeleton(model_root)

    # If model has a skeleton but no AnimationPlayer (e.g. trooper_rigged.fbx),
    # create one so we can load and play Mixamo clips dynamically
    if animation_player == null and skeleton != null:
        animation_player = AnimationPlayer.new()
        animation_player.name = "AnimationPlayer"
        skeleton.add_child(animation_player)
        animation_player.owner = model_root
        # Point the animation player root at the skeleton so bone tracks resolve
        animation_player.root_node = animation_player.get_path_to(skeleton)

    if animation_player:
        dynamic_anim_lib = AnimationLibrary.new()
        if not animation_player.has_animation_library("dyn"):
            animation_player.add_animation_library("dyn", dynamic_anim_lib)

    _rebuild_weapon_socket()
    _rebuild_limb_bubbles()

    baked_clips.clear()
    if animation_player:
        for anim_name in animation_player.get_animation_list():
            if not str(anim_name).begins_with("dyn/"):
                baked_clips.append(StringName(anim_name))
        baked_clips.sort()

    all_clip_entries.clear()
    for baked in baked_clips:
        all_clip_entries.append({"name": baked, "key": str(baked), "display": str(baked), "type": "BAKED", "path": ""})
    for fbx_name in fbx_files.keys():
        var clean_key: String = str(fbx_name).replace("[", "").replace("]", "").replace(" ", "_").replace("-", "_").replace("(", "").replace(")", "").replace(".", "_").to_lower()
        all_clip_entries.append({"name": StringName("dyn/" + clean_key), "key": clean_key, "display": fbx_name, "type": "FBX", "path": fbx_files[fbx_name]})
    for authored_name in authored_animation_files.keys():
        var authored_key := "authored_" + str(authored_name).to_snake_case()
        all_clip_entries.append({
            "name": StringName("dyn/" + authored_key),
            "key": authored_key,
            "display": "[Authored] " + str(authored_name),
            "type": "AUTHORED",
            "path": authored_animation_files[authored_name],
        })

    if not highlight_shortlist_loaded:
        _load_highlighted_shortlist()
        highlight_shortlist_loaded = true

    _filter_category(current_category)
    clip_index = 0
    _play_selected()
    _refresh_clip_list_ui()

func _hide_mannequin_mesh(node: Node) -> void:
    if node is MeshInstance3D:
        node.visible = false
    for c in node.get_children():
        _hide_mannequin_mesh(c)

func _apply_trooper_texture(node: Node) -> void:
    if node is MeshInstance3D:
        var mat := StandardMaterial3D.new()
        mat.albedo_texture = PS1_GAS_MASK_TEX
        mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
        mat.roughness = 0.9
        (node as MeshInstance3D).material_override = mat
    for c in node.get_children():
        _apply_trooper_texture(c)

func _generate_auto_skinned_mesh(src_mesh: ArrayMesh, skel: Skeleton3D) -> ArrayMesh:
    var src_arrays := src_mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
    var uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
    
    var bones: PackedInt32Array = PackedInt32Array()
    var weights: PackedFloat32Array = PackedFloat32Array()
    var new_vertices: PackedVector3Array = PackedVector3Array()
    
    # Scale from 3.34m to 1.85m standard height
    var scale_factor := 1.85 / 3.344682
    
    var head_idx := skel.find_bone("mixamorig_Head")
    if head_idx == -1: head_idx = skel.find_bone("mixamorig:Head")
    var spine_idx := skel.find_bone("mixamorig_Spine2")
    if spine_idx == -1: spine_idx = skel.find_bone("mixamorig:Spine2")
    var hips_idx := skel.find_bone("mixamorig_Hips")
    if hips_idx == -1: hips_idx = skel.find_bone("mixamorig:Hips")
    var r_arm_idx := skel.find_bone("mixamorig_RightArm")
    if r_arm_idx == -1: r_arm_idx = skel.find_bone("mixamorig:RightArm")
    var r_forearm_idx := skel.find_bone("mixamorig_RightForeArm")
    if r_forearm_idx == -1: r_forearm_idx = skel.find_bone("mixamorig:RightForeArm")
    var l_arm_idx := skel.find_bone("mixamorig_LeftArm")
    if l_arm_idx == -1: l_arm_idx = skel.find_bone("mixamorig:LeftArm")
    var l_forearm_idx := skel.find_bone("mixamorig_LeftForeArm")
    if l_forearm_idx == -1: l_forearm_idx = skel.find_bone("mixamorig:LeftForeArm")
    var r_thigh_idx := skel.find_bone("mixamorig_RightUpLeg")
    if r_thigh_idx == -1: r_thigh_idx = skel.find_bone("mixamorig:RightUpLeg")
    var r_leg_idx := skel.find_bone("mixamorig_RightLeg")
    if r_leg_idx == -1: r_leg_idx = skel.find_bone("mixamorig:RightLeg")
    var r_foot_idx := skel.find_bone("mixamorig_RightFoot")
    if r_foot_idx == -1: r_foot_idx = skel.find_bone("mixamorig:RightFoot")
    var l_thigh_idx := skel.find_bone("mixamorig_LeftUpLeg")
    if l_thigh_idx == -1: l_thigh_idx = skel.find_bone("mixamorig:LeftUpLeg")
    var l_leg_idx := skel.find_bone("mixamorig_LeftLeg")
    if l_leg_idx == -1: l_leg_idx = skel.find_bone("mixamorig:LeftLeg")
    var l_foot_idx := skel.find_bone("mixamorig_LeftFoot")
    if l_foot_idx == -1: l_foot_idx = skel.find_bone("mixamorig:LeftFoot")
    
    for v in vertices:
        var scaled_v := v * scale_factor
        new_vertices.append(scaled_v)
        
        var chosen_bone := hips_idx
        var y := scaled_v.y
        var x := scaled_v.x
        
        if y > 1.48:
            chosen_bone = head_idx
        elif y > 0.95:
            if x > 0.28:
                chosen_bone = r_forearm_idx if y < 1.30 else r_arm_idx
            elif x < -0.28:
                chosen_bone = l_forearm_idx if y < 1.30 else l_arm_idx
            else:
                chosen_bone = spine_idx
        else:
            if x >= 0:
                if y < 0.18: chosen_bone = r_foot_idx
                elif y < 0.55: chosen_bone = r_leg_idx
                else: chosen_bone = r_thigh_idx
            else:
                if y < 0.18: chosen_bone = l_foot_idx
                elif y < 0.55: chosen_bone = l_leg_idx
                else: chosen_bone = l_thigh_idx
                
        bones.append(chosen_bone if chosen_bone != -1 else 0)
        bones.append(0)
        bones.append(0)
        bones.append(0)
        
        weights.append(1.0)
        weights.append(0.0)
        weights.append(0.0)
        weights.append(0.0)
        
    var new_arrays := []
    new_arrays.resize(Mesh.ARRAY_MAX)
    new_arrays[Mesh.ARRAY_VERTEX] = new_vertices
    new_arrays[Mesh.ARRAY_NORMAL] = normals
    new_arrays[Mesh.ARRAY_TEX_UV] = uvs
    new_arrays[Mesh.ARRAY_BONES] = bones
    new_arrays[Mesh.ARRAY_WEIGHTS] = weights
    
    var out_mesh := ArrayMesh.new()
    out_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, new_arrays)
    return out_mesh

func _build_segmented_meshes(src_mesh: ArrayMesh, skel: Skeleton3D, bone_map: Dictionary) -> Dictionary:
    var src_arrays := src_mesh.surface_get_arrays(0)
    var vertices: PackedVector3Array = src_arrays[Mesh.ARRAY_VERTEX]
    var normals: PackedVector3Array = src_arrays[Mesh.ARRAY_NORMAL]
    var uvs: PackedVector2Array = src_arrays[Mesh.ARRAY_TEX_UV]
    var indices: PackedInt32Array = src_arrays[Mesh.ARRAY_INDEX]
    
    var seg_verts := {"head": PackedVector3Array(), "torso": PackedVector3Array(), "left_arm": PackedVector3Array(), "right_arm": PackedVector3Array(), "left_leg": PackedVector3Array(), "right_leg": PackedVector3Array()}
    var seg_norms := {"head": PackedVector3Array(), "torso": PackedVector3Array(), "left_arm": PackedVector3Array(), "right_arm": PackedVector3Array(), "left_leg": PackedVector3Array(), "right_leg": PackedVector3Array()}
    var seg_uvs := {"head": PackedVector2Array(), "torso": PackedVector2Array(), "left_arm": PackedVector2Array(), "right_arm": PackedVector2Array(), "left_leg": PackedVector2Array(), "right_leg": PackedVector2Array()}
    
    var scale_factor := 1.85 / 3.344682
    
    for i in range(0, indices.size(), 3):
        var idx0 := indices[i]
        var idx1 := indices[i+1]
        var idx2 := indices[i+2]
        
        var v0 := vertices[idx0] * scale_factor
        var v1 := vertices[idx1] * scale_factor
        var v2 := vertices[idx2] * scale_factor
        var center := (v0 + v1 + v2) / 3.0
        
        var target := "torso"
        if center.y > 1.45:
            target = "head"
        elif center.y > 0.95:
            if center.x > 0.22: target = "right_arm"
            elif center.x < -0.22: target = "left_arm"
            else: target = "torso"
        else:
            if center.x >= 0: target = "right_leg"
            else: target = "left_leg"
            
        var bone_name: String = bone_map.get(target, "mixamorig_Hips")
        var b_idx := skel.find_bone(bone_name)
        var bone_rest: Transform3D = skel.get_bone_global_rest(b_idx) if b_idx != -1 else Transform3D.IDENTITY
        var inv_rest := bone_rest.affine_inverse()
        
        for v_idx in [idx0, idx1, idx2]:
            var world_v := vertices[v_idx] * scale_factor
            var local_v := inv_rest * world_v
            var local_norm := inv_rest.basis * normals[v_idx]
            
            seg_verts[target].append(local_v)
            seg_norms[target].append(local_norm)
            seg_uvs[target].append(uvs[v_idx])
            
    var result := {}
    for key in seg_verts.keys():
        if seg_verts[key].size() > 0:
            var arrs := []
            arrs.resize(Mesh.ARRAY_MAX)
            arrs[Mesh.ARRAY_VERTEX] = seg_verts[key]
            arrs[Mesh.ARRAY_NORMAL] = seg_norms[key]
            arrs[Mesh.ARRAY_TEX_UV] = seg_uvs[key]
            var m := ArrayMesh.new()
            m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrs)
            result[key] = m
    return result

func _process(delta: float) -> void:
    if not dragging and not panning and active_dragged_bone == "":
        orbit_yaw += delta * 0.04
    _update_camera()
    _update_ui_state()
    _apply_two_hand_ik()
    _apply_bone_rot_overrides()
    _update_bubble_positions()

func _rebuild_limb_bubbles() -> void:
    for b in bubble_nodes.values():
        if is_instance_valid(b["node"]):
            b["node"].queue_free()
    bubble_nodes.clear()

    if skeleton == null:
        return

    # Core draggable landmarks
    var landmarks := {
        "HEAD": {"names": ["mixamorig_Head", "mixamorig:Head", "head"], "color": Color(1.0, 0.85, 0.2, 0.85), "radius": 0.07},
        "RIGHT_HAND": {"names": ["mixamorig_RightHand", "mixamorig:RightHand", "Hand.R.001"], "color": Color(0.1, 0.95, 0.85, 0.9), "radius": 0.065},
        "LEFT_HAND": {"names": ["mixamorig_LeftHand", "mixamorig:LeftHand", "Hand.L.001"], "color": Color(0.2, 1.0, 0.35, 0.9), "radius": 0.065},
        "RIGHT_ELBOW": {"names": ["mixamorig_RightForeArm", "mixamorig:RightForeArm", "ArmLower.R"], "color": Color(0.2, 0.65, 1.0, 0.8), "radius": 0.055},
        "LEFT_ELBOW": {"names": ["mixamorig_LeftForeArm", "mixamorig:LeftForeArm", "ArmLower.L"], "color": Color(0.2, 0.65, 1.0, 0.8), "radius": 0.055},
        "SPINE": {"names": ["mixamorig_Spine1", "mixamorig:Spine1", "Spineupper"], "color": Color(0.85, 0.5, 1.0, 0.8), "radius": 0.075},
        "HIPS": {"names": ["mixamorig_Hips", "mixamorig:Hips", "Spinelower"], "color": Color(1.0, 1.0, 1.0, 0.85), "radius": 0.08},
        "RIGHT_FOOT": {"names": ["mixamorig_RightFoot", "mixamorig:RightFoot", "Foot.R"], "color": Color(1.0, 0.5, 0.1, 0.85), "radius": 0.065},
        "LEFT_FOOT": {"names": ["mixamorig_LeftFoot", "mixamorig:LeftFoot", "Foot.L"], "color": Color(1.0, 0.2, 0.6, 0.85), "radius": 0.065},
    }

    for landmark_id in landmarks.keys():
        var cfg: Dictionary = landmarks[landmark_id]
        var target_bone := ""
        var bone_idx := -1
        for cand in cfg["names"]:
            bone_idx = skeleton.find_bone(cand)
            if bone_idx != -1:
                target_bone = cand
                break
        
        if bone_idx != -1:
            var bubble_root := Node3D.new()
            bubble_root.name = "Bubble_" + landmark_id
            
            var sphere_mesh := MeshInstance3D.new()
            var sph := SphereMesh.new()
            sph.radius = cfg["radius"]
            sph.height = cfg["radius"] * 2.0
            sphere_mesh.mesh = sph
            
            var mat := StandardMaterial3D.new()
            mat.albedo_color = cfg["color"]
            mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
            mat.emission_enabled = true
            mat.emission = cfg["color"]
            mat.emission_energy_multiplier = 1.2
            mat.no_depth_test = true
            sphere_mesh.material_override = mat
            bubble_root.add_child(sphere_mesh)
            
            add_child(bubble_root)
            bubble_nodes[landmark_id] = {
                "node": bubble_root,
                "mesh": sphere_mesh,
                "bone_name": target_bone,
                "bone_idx": bone_idx,
                "color": cfg["color"],
                "radius": cfg["radius"]
            }

func _update_bubble_positions() -> void:
    if not bubbles_enabled or skeleton == null:
        for b in bubble_nodes.values():
            if is_instance_valid(b["node"]):
                b["node"].visible = false
        return

    for landmark_id in bubble_nodes.keys():
        var b: Dictionary = bubble_nodes[landmark_id]
        var node: Node3D = b["node"]
        if is_instance_valid(node):
            node.visible = bubbles_enabled
            var bone_global_trans := skeleton.global_transform * skeleton.get_bone_global_pose(b["bone_idx"])
            node.global_position = bone_global_trans.origin

func _apply_bone_rot_overrides() -> void:
    if skeleton == null:
        return
    var edited_bones: Dictionary = {}
    for bone_name in bone_rot_offsets.keys():
        edited_bones[bone_name] = true
    for bone_name in bone_pos_offsets.keys():
        edited_bones[bone_name] = true
    for bone_name in edited_bones.keys():
        var b_idx := skeleton.find_bone(bone_name)
        if b_idx != -1:
            if not bone_edit_base_poses.has(bone_name):
                _capture_bone_edit_base(bone_name)
            var pose: Transform3D = (
                skeleton.get_bone_pose(b_idx)
                if is_playing
                else bone_edit_base_poses[bone_name]
            )
            var deg: Vector3 = bone_rot_offsets.get(bone_name, Vector3.ZERO)
            var position: Vector3 = bone_pos_offsets.get(bone_name, Vector3.ZERO)
            var rad := Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))
            var add_basis := Basis.from_euler(rad)
            pose.basis = pose.basis * add_basis
            pose.origin += position
            skeleton.set_bone_pose(b_idx, pose)

func _capture_bone_edit_base(bone_name: String, replace_existing: bool = false) -> void:
    if skeleton == null or bone_name.is_empty():
        return
    if bone_edit_base_poses.has(bone_name) and not replace_existing:
        return
    var bone_idx := skeleton.find_bone(bone_name)
    if bone_idx < 0:
        return
    bone_edit_base_poses[bone_name] = skeleton.get_bone_pose(bone_idx)
    if not bone_rot_offsets.has(bone_name):
        bone_rot_offsets[bone_name] = Vector3.ZERO
    if not bone_pos_offsets.has(bone_name):
        bone_pos_offsets[bone_name] = Vector3.ZERO

func _capture_all_edit_bases_after_seek() -> void:
    if skeleton == null:
        return
    for bone_name in bone_edit_base_poses.keys():
        var bone_idx := skeleton.find_bone(bone_name)
        if bone_idx >= 0:
            bone_edit_base_poses[bone_name] = skeleton.get_bone_pose(bone_idx)

func _pause_for_pose_edit() -> void:
    if animation_player == null:
        return
    if animation_player.is_playing():
        var current_time := animation_player.current_animation_position
        animation_player.pause()
        animation_player.seek(current_time, true)
    is_playing = false
    _capture_all_edit_bases_after_seek()

func _toggle_pose_edit_mode() -> void:
    pose_edit_mode = &"MOVE" if pose_edit_mode == &"ROTATE" else &"ROTATE"
    if pose_tool_button != null:
        pose_tool_button.text = "Bone Tool (M): %s" % pose_edit_mode

func _apply_two_hand_ik() -> void:
    if not two_hand_ik_enabled or skeleton == null or left_hand_marker == null or current_weapon == WeaponType.NONE:
        return
    # Skip IK on scaled models — the target positions don't match
    if model_root and model_root.scale.x > 1.5:
        return
    
    var left_hand_idx := skeleton.find_bone("mixamorig_LeftHand")
    if left_hand_idx == -1: left_hand_idx = skeleton.find_bone("mixamorig:LeftHand")
    if left_hand_idx == -1: left_hand_idx = skeleton.find_bone("Hand.L.001")
    if left_hand_idx == -1: return

    var target_global_pos := left_hand_marker.global_position
    var target_in_skel := skeleton.global_transform.affine_inverse() * target_global_pos
    var current_hand_pose := skeleton.get_bone_global_pose(left_hand_idx)
    
    var blend_pos := current_hand_pose.origin.lerp(target_in_skel, 0.85 * two_hand_ik_weight)
    current_hand_pose.origin = blend_pos
    skeleton.set_bone_global_pose_override(left_hand_idx, current_hand_pose, 0.85 * two_hand_ik_weight, true)

func _update_ui_state() -> void:
    if animation_player == null or filtered_entries.is_empty():
        return
    
    var entry: Dictionary = filtered_entries[clip_index]
    var anim: Animation = _get_current_animation(entry)
    var length: float = anim.length if anim else 1.0
    var current_pos: float = animation_player.current_animation_position
    
    if not timeline_slider.has_focus():
        timeline_slider.max_value = length
        timeline_slider.value = current_pos
    
    var current_frame := clampi(roundi(current_pos * EDITOR_FPS), 0, maxi(1, roundi(length * EDITOR_FPS)))
    var total_frames := maxi(1, roundi(length * EDITOR_FPS))
    timeline_slider.step = 1.0 / EDITOR_FPS
    timeline_slider.tick_count = total_frames + 1
    timeline_slider.ticks_on_borders = true
    time_label.text = "Frame %d / %d  •  %.2fs / %.2fs" % [current_frame, total_frames, current_pos, length]
    _refresh_frame_editor_labels()
    
    var skin_name := _skin_name(current_skin)
    var wep_name := _weapon_name(current_weapon)
    status_label.text = "[ %s ]  •  Weapon: %s  •  Clip %d/%d: %s (%.2fs)" % [
        skin_name,
        wep_name,
        clip_index + 1,
        filtered_entries.size(),
        entry["display"],
        length
    ]

    if active_dragged_bone != "":
        limb_hud_label.visible = true
        var deg: Vector3 = bone_rot_offsets.get(active_dragged_bone, Vector3.ZERO)
        var pos: Vector3 = bone_pos_offsets.get(active_dragged_bone, Vector3.ZERO)
        limb_hud_label.text = (
            "%s [%s]  ROT %.1f°, %.1f°, %.1f°  POS %.3f, %.3f, %.3f m"
            % [pose_edit_mode, active_dragged_bone, deg.x, deg.y, deg.z, pos.x, pos.y, pos.z]
        )
    else:
        limb_hud_label.visible = false

func _get_current_animation(entry: Dictionary) -> Animation:
    if entry["type"] == "BAKED":
        return animation_player.get_animation(entry["name"]) if animation_player else null
    elif dynamic_anim_lib and entry.has("key"):
        var anim_key: StringName = StringName(entry["key"])
        if dynamic_anim_lib.has_animation(anim_key):
            return dynamic_anim_lib.get_animation(anim_key)
    return null

func _unhandled_input(event: InputEvent) -> void:
    if event is InputEventKey and event.pressed and not event.echo:
        match event.physical_keycode:
            KEY_LEFT:
                _select_relative(-1)
            KEY_RIGHT:
                _select_relative(1)
            KEY_SPACE:
                _toggle_play_pause()
            KEY_TAB:
                _toggle_skin()
            KEY_G:
                _cycle_weapon()
            KEY_B:
                _toggle_bubbles()
            KEY_M:
                _toggle_pose_edit_mode()
            KEY_L:
                _toggle_gun_lab()
            KEY_R:
                _reset_camera()
            KEY_C:
                _clear_bone_rot_offsets()
            KEY_1:
                _assign_to_slot("idle_rifle")
            KEY_2:
                _assign_to_slot("run_forward")
            KEY_3:
                _assign_to_slot("run_backward")
            KEY_4:
                _assign_to_slot("jump_loop")
            KEY_5:
                _assign_to_slot("dive_roll")
            KEY_6:
                _assign_to_slot("prone_backward")
            KEY_ESCAPE:
                get_tree().quit()

    elif event is InputEventMouseButton:
        if event.button_index == MOUSE_BUTTON_LEFT:
            if event.pressed:
                # Raycast to find clicked limb bubble
                var clicked_bone := _find_bubble_at_mouse(event.position)
                if clicked_bone != "":
                    _pause_for_pose_edit()
                    active_dragged_bone = clicked_bone
                    drag_start_mouse = event.position
                    _capture_bone_edit_base(clicked_bone)
                else:
                    dragging = true
            else:
                dragging = false
                active_dragged_bone = ""

        elif event.button_index == MOUSE_BUTTON_RIGHT:
            panning = event.pressed
        elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
            orbit_distance = maxf(1.4, orbit_distance - 0.25)
        elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
            orbit_distance = minf(7.5, orbit_distance + 0.25)

    elif event is InputEventMouseMotion:
        if active_dragged_bone != "":
            var delta_drag: Vector2 = event.position - drag_start_mouse
            drag_start_mouse = event.position
            if pose_edit_mode == &"ROTATE":
                var current_rot: Vector3 = bone_rot_offsets.get(active_dragged_bone, Vector3.ZERO)
                current_rot.x = clampf(
                    current_rot.x - delta_drag.y * rotation_degrees_per_pixel,
                    -90.0,
                    90.0
                )
                current_rot.y = clampf(
                    current_rot.y + delta_drag.x * rotation_degrees_per_pixel,
                    -120.0,
                    120.0
                )
                bone_rot_offsets[active_dragged_bone] = current_rot
            else:
                var current_pos: Vector3 = bone_pos_offsets.get(active_dragged_bone, Vector3.ZERO)
                if event.shift_pressed:
                    current_pos.z = clampf(
                        current_pos.z - delta_drag.y * translation_meters_per_pixel,
                        -0.35,
                        0.35
                    )
                else:
                    current_pos.x = clampf(
                        current_pos.x + delta_drag.x * translation_meters_per_pixel,
                        -0.35,
                        0.35
                    )
                    current_pos.y = clampf(
                        current_pos.y - delta_drag.y * translation_meters_per_pixel,
                        -0.35,
                        0.35
                    )
                bone_pos_offsets[active_dragged_bone] = current_pos
        elif dragging:
            orbit_yaw -= event.relative.x * 0.007
            orbit_pitch = clampf(orbit_pitch - event.relative.y * 0.005, -0.65, 0.45)
        elif panning:
            target_height = clampf(target_height + event.relative.y * 0.004, 0.2, 1.8)

func _find_bubble_at_mouse(m_pos: Vector2) -> String:
    if not bubbles_enabled or camera == null:
        return ""
    var closest_dist := 36.0 # pixel hit radius
    var selected_bone := ""
    
    for landmark_id in bubble_nodes.keys():
        var b: Dictionary = bubble_nodes[landmark_id]
        var node: Node3D = b["node"]
        if is_instance_valid(node) and not camera.is_position_behind(node.global_position):
            var screen_pos := camera.unproject_position(node.global_position)
            var d := screen_pos.distance_to(m_pos)
            if d < closest_dist:
                closest_dist = d
                selected_bone = b["bone_name"]
    return selected_bone

func _toggle_bubbles() -> void:
    bubbles_enabled = not bubbles_enabled
    bubbles_toggle_btn.text = "Pose Bubbles (B): " + ("ON" if bubbles_enabled else "OFF")

func _clear_bone_rot_offsets() -> void:
    if skeleton != null:
        for bone_name in bone_edit_base_poses.keys():
            var bone_idx := skeleton.find_bone(bone_name)
            if bone_idx >= 0:
                skeleton.set_bone_pose(bone_idx, bone_edit_base_poses[bone_name])
    bone_rot_offsets.clear()
    bone_pos_offsets.clear()
    bone_edit_base_poses.clear()

func _select_relative(amount: int) -> void:
    if filtered_entries.is_empty():
        return
    clip_index = wrapi(clip_index + amount, 0, filtered_entries.size())
    _play_selected()
    _refresh_clip_list_ui()

func _play_selected() -> void:
    if animation_player == null or filtered_entries.is_empty():
        return
    var entry: Dictionary = filtered_entries[clip_index]
    var clip_name: StringName = entry["name"]
    
    if entry["type"] == "FBX":
        _load_and_retarget_fbx(entry)
    elif entry["type"] == "AUTHORED":
        _load_authored_animation(entry)
    
    var anim := _get_current_animation(entry)
    if anim:
        anim.loop_mode = Animation.LOOP_LINEAR if _should_loop(entry["display"]) else Animation.LOOP_NONE
    
    animation_player.speed_scale = playback_speed
    if animation_player.has_animation(clip_name):
        animation_player.play(clip_name, 0.1)
        is_playing = true
        trim_in_seconds = 0.0
        trim_out_seconds = anim.length if anim else 0.0
        _refresh_frame_editor_labels()

func _load_authored_animation(entry: Dictionary) -> void:
    var anim_key: StringName = StringName(entry.get("key", ""))
    if anim_key == &"" or dynamic_anim_lib.has_animation(anim_key):
        return
    var source_authored := load(str(entry.get("path", ""))) as Animation
    if source_authored != null:
        var authored := source_authored.duplicate(true) as Animation
        ROOT_SANITIZER.sanitize(authored, _should_loop(str(entry.get("display", ""))))
        dynamic_anim_lib.add_animation(anim_key, authored)

func _load_and_retarget_fbx(entry: Dictionary) -> void:
    var anim_key: StringName = StringName(entry["key"])
    if dynamic_anim_lib.has_animation(anim_key):
        return
    
    var fbx_path: String = entry["path"]
    var packed: PackedScene = load(fbx_path) as PackedScene
    if not packed:
        return
    
    var temp_instance := packed.instantiate()
    var temp_player := _find_animation_player(temp_instance)
    if not temp_player or temp_player.get_animation_list().is_empty():
        temp_instance.queue_free()
        return
    
    var src_anim_name := _select_source_animation_name(temp_player)
    if src_anim_name == &"":
        temp_instance.queue_free()
        return
    var src_anim: Animation = temp_player.get_animation(src_anim_name)
    if not src_anim:
        temp_instance.queue_free()
        return

    # Universal 65-Bone Retargeter with Full Finger & Spine Tracks
    var retargeted: Animation = src_anim.duplicate()
    var skel_path: NodePath = NodePath("GeneralSkeleton")
    if skeleton:
        skel_path = animation_player.get_node(animation_player.root_node).get_path_to(skeleton)

    var track_idx := retargeted.get_track_count() - 1
    while track_idx >= 0:
        var old_path_str := str(retargeted.track_get_path(track_idx))
        var raw_bone := old_path_str.split(":")[-1]
        var normalized_mixamo := raw_bone.replace("mixamorig:", "mixamorig_")
        if not normalized_mixamo.begins_with("mixamorig_"):
            normalized_mixamo = "mixamorig_" + normalized_mixamo

        var target_bone := ""
        if skeleton:
            if current_skin == SkinType.PS1_NIGHT_VISION_SEAL and MIXAMO_TO_PS1_MAP.has(normalized_mixamo):
                target_bone = MIXAMO_TO_PS1_MAP[normalized_mixamo]
            elif skeleton.find_bone(raw_bone) != -1:
                target_bone = raw_bone
            elif skeleton.find_bone(normalized_mixamo) != -1:
                target_bone = normalized_mixamo
            elif skeleton.find_bone(normalized_mixamo.replace("mixamorig_", "mixamorig:")) != -1:
                target_bone = normalized_mixamo.replace("mixamorig_", "mixamorig:")
            else:
                var lower_raw := raw_bone.to_lower().replace("mixamorig_", "").replace("mixamorig:", "")
                for b_i in range(skeleton.get_bone_count()):
                    var b_name := skeleton.get_bone_name(b_i)
                    if b_name.to_lower() == lower_raw or b_name.to_lower().begins_with(lower_raw):
                        target_bone = b_name
                        break

        if target_bone != "":
            var new_path := NodePath(str(skel_path) + ":" + target_bone)
            retargeted.track_set_path(track_idx, new_path)

            if ("Hips" in raw_bone or "Spinelower" in target_bone or "root" in raw_bone.to_lower()) and retargeted.track_get_type(track_idx) == Animation.TYPE_POSITION_3D:
                var bone_idx := skeleton.find_bone(target_bone) if skeleton else -1
                var rest_y := skeleton.get_bone_rest(bone_idx).origin.y if bone_idx != -1 else 0.92
                var base_y := 0.0
                if retargeted.track_get_key_count(track_idx) > 0:
                    base_y = retargeted.track_get_key_value(track_idx, 0).y
                    
                # Scale factor: ratio of target skeleton hips to source animation hips
                # This keeps the bobbing proportional instead of adding raw meter offsets
                var scale_factor := (rest_y / base_y) if base_y != 0.0 else 1.0
                    
                for key_idx in range(retargeted.track_get_key_count(track_idx)):
                    var pos: Vector3 = retargeted.track_get_key_value(track_idx, key_idx)
                    pos.x = 0.0
                    pos.z = 0.0
                    pos.y = pos.y * scale_factor
                    retargeted.track_set_key_value(track_idx, key_idx, pos)
        else:
            retargeted.remove_track(track_idx)
            
        track_idx -= 1

    ROOT_SANITIZER.sanitize(retargeted, _should_loop(str(entry.get("display", ""))))
    dynamic_anim_lib.add_animation(anim_key, retargeted)
    temp_instance.queue_free()

func _select_source_animation_name(player: AnimationPlayer) -> StringName:
    var names := player.get_animation_list()
    if names.has(&"mixamo_com"):
        return &"mixamo_com"
    for animation_name in names:
        if animation_name != &"RESET":
            return animation_name
    return &""

func _toggle_play_pause() -> void:
    if animation_player == null:
        return
    if animation_player.is_playing():
        _pause_for_pose_edit()
    else:
        animation_player.play()
        is_playing = true

func _step_animation_frame(direction: int) -> void:
    var animation := _selected_animation()
    if animation_player == null or animation == null:
        return
    _pause_for_pose_edit()
    var current_frame := roundi(animation_player.current_animation_position * EDITOR_FPS)
    var total_frames := maxi(1, roundi(animation.length * EDITOR_FPS))
    var target_frame := clampi(current_frame + direction, 0, total_frames)
    animation_player.seek(float(target_frame) / EDITOR_FPS, true)
    _capture_all_edit_bases_after_seek()

func _set_trim_in() -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    trim_in_seconds = minf(_snapped_current_time(), trim_out_seconds - (1.0 / EDITOR_FPS))
    trim_in_seconds = clampf(trim_in_seconds, 0.0, animation.length)
    _refresh_frame_editor_labels()

func _set_trim_out() -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    trim_out_seconds = maxf(_snapped_current_time(), trim_in_seconds + (1.0 / EDITOR_FPS))
    trim_out_seconds = clampf(trim_out_seconds, 0.0, animation.length)
    _refresh_frame_editor_labels()

func _snapped_current_time() -> float:
    if animation_player == null:
        return 0.0
    return roundf(animation_player.current_animation_position * EDITOR_FPS) / EDITOR_FPS

func _selected_animation() -> Animation:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return null
    return _get_current_animation(filtered_entries[clip_index])

func _add_current_trim_segment() -> void:
    var segment := _current_trim_segment()
    if segment.is_empty():
        status_label.text = "A trim segment must contain at least one frame."
        return
    assembly_segments.append(segment)
    _refresh_frame_editor_labels()
    status_label.text = "Added %s frames %d–%d to the assembly." % [
        str(segment.get("display", "Animation clip")),
        roundi(float(segment.get("start", 0.0)) * EDITOR_FPS),
        roundi(float(segment.get("end", 0.0)) * EDITOR_FPS),
    ]

func _current_trim_segment() -> Dictionary:
    var animation := _selected_animation()
    if animation == null or filtered_entries.is_empty():
        return {}
    var safe_in := clampf(trim_in_seconds, 0.0, animation.length)
    var safe_out := clampf(trim_out_seconds, safe_in, animation.length)
    if safe_out - safe_in < 1.0 / EDITOR_FPS:
        return {}
    var entry: Dictionary = filtered_entries[clip_index]
    return {
        "animation": animation.duplicate(true),
        "start": safe_in,
        "end": safe_out,
        "display": str(entry.get("display", "Animation clip")),
        "path": str(entry.get("path", "")),
    }

func _on_clip_dropped_to_assembly(entry: Dictionary) -> void:
    _append_entry_full_range(entry)

func _add_selected_full_clip() -> void:
    if filtered_entries.is_empty() or clip_index < 0 or clip_index >= filtered_entries.size():
        return
    _append_entry_full_range(filtered_entries[clip_index])

func _append_entry_full_range(entry: Dictionary) -> void:
    match str(entry.get("type", "")):
        "FBX":
            _load_and_retarget_fbx(entry)
        "AUTHORED":
            _load_authored_animation(entry)
    var animation := _get_current_animation(entry)
    if animation == null:
        status_label.text = "That clip could not be loaded into the assembly."
        return
    assembly_segments.append({
        "animation": animation.duplicate(true),
        "start": 0.0,
        "end": animation.length,
        "display": str(entry.get("display", "Animation clip")),
        "path": str(entry.get("path", "")),
    })
    _refresh_frame_editor_labels()
    if assembly_drop_label:
        assembly_drop_label.text = "✓ ADDED: %s" % str(entry.get("display", "Animation clip"))
        assembly_drop_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
    status_label.text = "Appended the complete %s clip to the assembly." % str(entry.get("display", "Animation clip"))

func _on_assembly_drop_visual_state_changed(state: String) -> void:
    if assembly_drop_label == null:
        return
    match state:
        "hover":
            assembly_drop_label.text = "RELEASE NOW → add this clip"
            assembly_drop_label.add_theme_color_override("font_color", Color(1.0, 0.86, 0.25))
        "ready":
            assembly_drop_label.text = "VALID DESTINATION → drag clip here"
            assembly_drop_label.add_theme_color_override("font_color", Color(0.2, 0.9, 1.0))
        _:
            assembly_drop_label.text = "DROP CLIP HERE → append full clip"
            assembly_drop_label.add_theme_color_override("font_color", Color(0.65, 0.78, 0.84))

func _undo_assembly_segment() -> void:
    if not assembly_segments.is_empty():
        assembly_segments.pop_back()
    _refresh_frame_editor_labels()

func _clear_assembly_segments() -> void:
    assembly_segments.clear()
    _refresh_frame_editor_labels()

func _nudge_trim_in(frame_delta: int) -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    var step := 1.0 / EDITOR_FPS
    trim_in_seconds = clampf(trim_in_seconds + float(frame_delta) * step, 0.0, trim_out_seconds - step)
    trim_in_seconds = roundf(trim_in_seconds * EDITOR_FPS) / EDITOR_FPS
    animation_player.seek(trim_in_seconds, true)
    _refresh_frame_editor_labels()

func _nudge_trim_out(frame_delta: int) -> void:
    var animation := _selected_animation()
    if animation == null:
        return
    var step := 1.0 / EDITOR_FPS
    trim_out_seconds = clampf(trim_out_seconds + float(frame_delta) * step, trim_in_seconds + step, animation.length)
    trim_out_seconds = roundf(trim_out_seconds * EDITOR_FPS) / EDITOR_FPS
    animation_player.seek(trim_out_seconds, true)
    _refresh_frame_editor_labels()

func _refresh_frame_editor_labels() -> void:
    if trim_label:
        trim_label.text = "TRIM  %d → %d  (%d frames)" % [
            roundi(trim_in_seconds * EDITOR_FPS),
            roundi(trim_out_seconds * EDITOR_FPS),
            maxi(0, roundi((trim_out_seconds - trim_in_seconds) * EDITOR_FPS)),
        ]
    if assembly_label:
        var duration := 0.0
        for segment in assembly_segments:
            duration += maxf(0.0, float(segment.get("end", 0.0)) - float(segment.get("start", 0.0)))
        assembly_label.text = "ASSEMBLY: %d segment%s • %d frames" % [
            assembly_segments.size(),
            "" if assembly_segments.size() == 1 else "s",
            roundi(duration * EDITOR_FPS),
        ]

func _save_authored_assembly() -> void:
    var segments: Array[Dictionary] = []
    for queued_segment in assembly_segments:
        segments.append(queued_segment.duplicate(true))
    if segments.is_empty():
        var current_segment := _current_trim_segment()
        if not current_segment.is_empty():
            segments.append(current_segment)
    if segments.is_empty():
        return
    _save_authored_segments(segments, "combined_clip", true)

func _save_current_trim() -> void:
    var segment := _current_trim_segment()
    if segment.is_empty():
        status_label.text = "Choose a trim range of at least one frame before saving."
        return
    var fallback_name := _safe_authored_name(str(segment.get("display", "animation"))) + "_trim"
    var single_segment: Array[Dictionary] = [segment]
    _save_authored_segments(single_segment, fallback_name, false)

func _save_authored_segments(segments: Array[Dictionary], fallback_name: String, clear_assembly: bool) -> void:
    var combined: Animation = clip_editor.combine(segments, EDITOR_FPS)
    if combined == null or combined.get_track_count() == 0:
        status_label.text = "The selected segments did not contain compatible animation tracks."
        return
    var requested_name := authored_name_input.text.strip_edges() if authored_name_input else ""
    if requested_name.is_empty():
        requested_name = fallback_name
    var safe_name := _safe_authored_name(requested_name)
    DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(AUTHORED_ANIMATION_DIR))
    var resource_path := "%s/%s.tres" % [AUTHORED_ANIMATION_DIR, safe_name]
    var suffix := 2
    while FileAccess.file_exists(resource_path):
        resource_path = "%s/%s_%d.tres" % [AUTHORED_ANIMATION_DIR, safe_name, suffix]
        suffix += 1
    combined.resource_name = resource_path.get_file().get_basename()
    combined.loop_mode = Animation.LOOP_NONE
    var save_error := ResourceSaver.save(combined, resource_path)
    if save_error != OK:
        status_label.text = "Could not save authored clip (%s)." % error_string(save_error)
        return
    var authored_key := "authored_" + resource_path.get_file().get_basename().to_snake_case()
    if dynamic_anim_lib.has_animation(authored_key):
        dynamic_anim_lib.remove_animation(authored_key)
    dynamic_anim_lib.add_animation(authored_key, combined)
    var new_entry := {
        "name": StringName("dyn/" + authored_key),
        "key": authored_key,
        "display": "[Authored] " + combined.resource_name.capitalize(),
        "type": "AUTHORED",
        "path": resource_path,
    }
    all_clip_entries.append(new_entry)
    authored_animation_files[combined.resource_name.capitalize()] = resource_path
    if clear_assembly:
        assembly_segments.clear()
    _filter_category("AUTHORED")
    for index in range(filtered_entries.size()):
        if str(filtered_entries[index].get("path", "")) == resource_path:
            clip_index = index
            break
    _play_selected()
    _refresh_clip_list_ui()
    _refresh_frame_editor_labels()
    status_label.text = "Saved %s (%d frames). It is now available under AUTHORED." % [
        resource_path,
        roundi(combined.length * EDITOR_FPS),
    ]

func _safe_authored_name(value: String) -> String:
    var safe := value.to_snake_case().validate_filename().strip_edges()
    if safe.is_empty():
        return "authored_clip"
    return safe

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
    filtered_entries.clear()
    for entry in all_clip_entries:
        var name_str: String = str(entry["display"]).to_lower()
        match cat:
            "ALL":
                filtered_entries.append(entry)
            "RIFLE LOCO":
                if ("walk" in name_str or "run" in name_str or "sprint" in name_str or "strafe" in name_str) and not "crouch" in name_str and not "pistol" in name_str:
                    filtered_entries.append(entry)
            "PISTOL":
                if "pistol" in name_str:
                    filtered_entries.append(entry)
            "CROUCH & PRONE":
                if "crouch" in name_str or "prone" in name_str or "kneel" in name_str or "crawl" in name_str:
                    filtered_entries.append(entry)
            "COMBAT & FIRE":
                if "fire" in name_str or "aim" in name_str or "reload" in name_str or "shoot" in name_str or "throw" in name_str:
                    filtered_entries.append(entry)
            "AGILITY & DIVE":
                if "dive" in name_str or "roll" in name_str or "jump" in name_str or "land" in name_str:
                    filtered_entries.append(entry)
            "DEATH & HIT":
                if "death" in name_str or "hit" in name_str or "die" in name_str:
                    filtered_entries.append(entry)
            "AUTHORED":
                if entry["type"] in ["BAKED", "AUTHORED"]:
                    filtered_entries.append(entry)

    if filtered_entries.is_empty():
        filtered_entries = all_clip_entries.duplicate()
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
    state_slots.clear()
    if FileAccess.file_exists(ANIMATION_MAP_PATH):
        var file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.READ)
        var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
        if parsed is Dictionary:
            var clips: Variant = (parsed as Dictionary).get("clips", {})
            if clips is Dictionary:
                for slot_name in (clips as Dictionary).keys():
                    state_slots[str(slot_name)] = str((clips as Dictionary)[slot_name])
    state_slot_keys.clear()
    for slot_name in state_slots.keys():
        state_slot_keys.append(str(slot_name))
    state_slot_keys.sort()
    if not state_slot_keys.is_empty():
        selected_state_slot = state_slot_keys[0]

func _save_state_slots() -> void:
    var config: Dictionary = {}
    if FileAccess.file_exists(ANIMATION_MAP_PATH):
        var existing_file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.READ)
        var parsed: Variant = JSON.parse_string(existing_file.get_as_text()) if existing_file else null
        if parsed is Dictionary:
            config = (parsed as Dictionary).duplicate(true)
    if config.is_empty():
        config = {
            "version": 1,
            "description": "Gameplay state -> editable Mixamo FBX mapping.",
        }
    config = _merge_state_slots_into_config(config)
    var file := FileAccess.open(ANIMATION_MAP_PATH, FileAccess.WRITE)
    if file == null:
        status_label.text = "Could not save the runtime animation map."
        return
    file.store_string(JSON.stringify(config, "  "))

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

func _rebuild_weapon_socket() -> void:
    if socket_attachment:
        socket_attachment.queue_free()
        socket_attachment = null
        weapon_node = null
        left_hand_marker = null

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

func _build_ui() -> void:
    overlay = CanvasLayer.new()
    add_child(overlay)

    # Top Header Panel
    var top_panel := PanelContainer.new()
    top_panel.position = Vector2(16, 14)
    top_panel.size = Vector2(880, 96)
    overlay.add_child(top_panel)

    var top_vbox := VBoxContainer.new()
    top_panel.add_child(top_vbox)

    status_label = Label.new()
    status_label.add_theme_font_size_override("font_size", 16)
    top_vbox.add_child(status_label)

    # Category Tab Buttons
    category_container = HBoxContainer.new()
    top_vbox.add_child(category_container)
    var categories := ["ALL", "RIFLE LOCO", "PISTOL", "CROUCH & PRONE", "COMBAT & FIRE", "AGILITY & DIVE", "DEATH & HIT", "AUTHORED"]
    for cat in categories:
        var btn := Button.new()
        btn.text = cat
        btn.pressed.connect(func(): _filter_category(cat))
        category_container.add_child(btn)

    # Left Sidebar: Clips Scroll List with Real-time Search
    var left_panel := PanelContainer.new()
    left_panel.name = "ClipLibraryPanel"
    left_panel.position = Vector2(16, 120)
    left_panel.size = Vector2(320, 390)
    overlay.add_child(left_panel)

    var left_vbox := VBoxContainer.new()
    left_panel.add_child(left_vbox)

    var search_bar := LineEdit.new()
    search_bar.placeholder_text = "🔍 Search 341 Mixamo animations..."
    search_bar.text_changed.connect(_on_search_changed)
    left_vbox.add_child(search_bar)

    clip_scroll = ScrollContainer.new()
    clip_scroll.custom_minimum_size = Vector2(300, 340)
    clip_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    left_vbox.add_child(clip_scroll)

    clip_list_vbox = VBoxContainer.new()
    clip_list_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    clip_scroll.add_child(clip_list_vbox)

    # Right Sidebar: persistent gameplay state -> clip mapping.
    var right_panel := PanelContainer.new()
    right_panel.name = "RuntimeMapPanel"
    right_panel.position = Vector2(842, 14)
    right_panel.size = Vector2(420, 496)
    overlay.add_child(right_panel)

    var right_scroll := ScrollContainer.new()
    right_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
    right_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    right_panel.add_child(right_scroll)

    var slot_vbox := VBoxContainer.new()
    slot_vbox.custom_minimum_size = Vector2(392, 0)
    slot_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    right_scroll.add_child(slot_vbox)

    var slot_title := Label.new()
    slot_title.text = "[ RUNTIME ANIMATION TREE MAP ]"
    slot_title.add_theme_font_size_override("font_size", 14)
    slot_title.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    slot_vbox.add_child(slot_title)

    var graph_scroll := ScrollContainer.new()
    graph_scroll.custom_minimum_size = Vector2(0, 250)
    graph_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    graph_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
    slot_vbox.add_child(graph_scroll)

    runtime_route_graph = ROUTE_GRAPH.new()
    runtime_route_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    runtime_route_graph.state_selected.connect(_on_route_state_selected)
    runtime_route_graph.clip_dropped_on_state.connect(_on_clip_dropped_on_tree_state)
    runtime_route_graph.candidate_selected.connect(_on_graph_candidate_selected)
    graph_scroll.add_child(runtime_route_graph)

    state_slot_selector = OptionButton.new()
    for slot_name in state_slot_keys:
        state_slot_selector.add_item(slot_name)
    state_slot_selector.item_selected.connect(func(index: int):
        selected_state_slot = state_slot_keys[index]
        _refresh_slot_ui()
    )
    slot_vbox.add_child(state_slot_selector)

    var btn_row := HBoxContainer.new()
    slot_vbox.add_child(btn_row)

    var assign_button := Button.new()
    assign_button.text = "Bind Selected Clip ➔"
    assign_button.pressed.connect(func(): _assign_to_slot(selected_state_slot))
    btn_row.add_child(assign_button)

    var auto_map_button := Button.new()
    auto_map_button.text = "⚡ Auto-Build Known States"
    auto_map_button.add_theme_color_override("font_color", Color(1.0, 0.85, 0.2))
    auto_map_button.pressed.connect(_auto_map_all_slots)
    btn_row.add_child(auto_map_button)

    var highlight_help := Label.new()
    highlight_help.text = "★ Highlight clips on the left. Your shortlist is saved for Codex; purple proposals appear here."
    highlight_help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    highlight_help.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
    slot_vbox.add_child(highlight_help)

    slot_suggestion_label = Label.new()
    slot_suggestion_label.add_theme_font_size_override("font_size", 11)
    slot_suggestion_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
    slot_vbox.add_child(slot_suggestion_label)

    var use_suggestion_button := Button.new()
    use_suggestion_button.text = "Approve Selected Suggestion"
    use_suggestion_button.pressed.connect(_assign_selected_to_suggested_slot)
    slot_vbox.add_child(use_suggestion_button)

    var clear_highlights_button := Button.new()
    clear_highlights_button.text = "Clear Highlighted Clips"
    clear_highlights_button.pressed.connect(_clear_highlighted_clips)
    slot_vbox.add_child(clear_highlights_button)

    slot_panel_label = Label.new()
    slot_panel_label.add_theme_font_size_override("font_size", 11)
    slot_vbox.add_child(slot_panel_label)
    _refresh_slot_ui()

    # Active Limb Drag HUD Label
    limb_hud_label = Label.new()
    limb_hud_label.position = Vector2(330, 120)
    limb_hud_label.add_theme_font_size_override("font_size", 15)
    limb_hud_label.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    limb_hud_label.visible = false
    overlay.add_child(limb_hud_label)

    # Gun Lab Calibration Panel (Interactive Weapon Studio)
    gun_lab_panel = PanelContainer.new()
    gun_lab_panel.position = Vector2(880, 232)
    gun_lab_panel.size = Vector2(384, 368)
    gun_lab_panel.visible = false # Animation tree owns the default workspace; L opens weapon tools.
    overlay.add_child(gun_lab_panel)

    var gun_vbox := VBoxContainer.new()
    gun_lab_panel.add_child(gun_vbox)
    
    var gun_title := Label.new()
    gun_title.text = "[ WEAPON ALIGNMENT STUDIO (L) ]"
    gun_title.add_theme_font_size_override("font_size", 14)
    gun_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
    gun_vbox.add_child(gun_title)

    # Quick Rotation Presets
    var quick_rot_hbox := HBoxContainer.new()
    gun_vbox.add_child(quick_rot_hbox)
    
    var btn_roll90 := Button.new()
    btn_roll90.text = "↻ Roll 90°"
    btn_roll90.pressed.connect(func():
        right_grip_rot.z = wrapf(right_grip_rot.z + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_roll90)

    var btn_pitch90 := Button.new()
    btn_pitch90.text = "↻ Pitch 90°"
    btn_pitch90.pressed.connect(func():
        right_grip_rot.x = wrapf(right_grip_rot.x + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_pitch90)

    var btn_yaw90 := Button.new()
    btn_yaw90.text = "↻ Yaw 90°"
    btn_yaw90.pressed.connect(func():
        right_grip_rot.y = wrapf(right_grip_rot.y + 90.0, -180.0, 180.0)
        _update_gun_sliders_and_mesh()
    )
    quick_rot_hbox.add_child(btn_yaw90)

    # Sliders for Position & Rotation & Scale
    _add_gun_slider(gun_vbox, "Pos X (Left/Right)", "pos_x", -0.3, 0.3, right_grip_pos.x, 0.005, func(val):
        right_grip_pos.x = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pos Y (Up/Down)", "pos_y", -0.3, 0.3, right_grip_pos.y, 0.005, func(val):
        right_grip_pos.y = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pos Z (Fwd/Back)", "pos_z", -0.3, 0.3, right_grip_pos.z, 0.005, func(val):
        right_grip_pos.z = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Pitch X (Up/Down)", "rot_x", -180.0, 180.0, right_grip_rot.x, 1.0, func(val):
        right_grip_rot.x = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Yaw Y (Turn)", "rot_y", -180.0, 180.0, right_grip_rot.y, 1.0, func(val):
        right_grip_rot.y = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Roll Z (Tilt)", "rot_z", -180.0, 180.0, right_grip_rot.z, 1.0, func(val):
        right_grip_rot.z = val
        _sync_weapon_node_transform()
    )
    _add_gun_slider(gun_vbox, "Gun Scale", "scale", 0.2, 3.0, weapon_scale_factor, 0.05, func(val):
        weapon_scale_factor = val
        _sync_weapon_node_transform()
    )

    # Action Buttons: Print Config & Reset
    var action_hbox := HBoxContainer.new()
    gun_vbox.add_child(action_hbox)
    
    var print_btn := Button.new()
    print_btn.text = "📋 Print Transform Config"
    print_btn.pressed.connect(_print_weapon_config)
    action_hbox.add_child(print_btn)

    var reset_btn := Button.new()
    reset_btn.text = "↺ Reset"
    reset_btn.pressed.connect(func():
        right_grip_pos = Vector3(-0.02, 0.08, 0.05)
        right_grip_rot = Vector3(-90.0, 180.0, 0.0)
        weapon_scale_factor = 1.0
        _update_gun_sliders_and_mesh()
    )
    action_hbox.add_child(reset_btn)

    # Bottom Toolbar / Timeline
    var bot_panel := PanelContainer.new()
    bot_panel.name = "FrameEditorDock"
    bot_panel.position = Vector2(16, 520)
    bot_panel.size = Vector2(1248, 184)
    overlay.add_child(bot_panel)

    var bot_vbox := VBoxContainer.new()
    bot_panel.add_child(bot_vbox)

    var slider_hbox := HBoxContainer.new()
    bot_vbox.add_child(slider_hbox)

    var play_btn := Button.new()
    play_btn.text = " ▶ / ❚❚ "
    play_btn.pressed.connect(_toggle_play_pause)
    slider_hbox.add_child(play_btn)

    var previous_frame_button := Button.new()
    previous_frame_button.text = "◀ Frame"
    previous_frame_button.pressed.connect(func(): _step_animation_frame(-1))
    slider_hbox.add_child(previous_frame_button)

    var next_frame_button := Button.new()
    next_frame_button.text = "Frame ▶"
    next_frame_button.pressed.connect(func(): _step_animation_frame(1))
    slider_hbox.add_child(next_frame_button)

    timeline_slider = HSlider.new()
    timeline_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    timeline_slider.value_changed.connect(func(val): 
        if animation_player and filtered_entries.size() > 0:
            animation_player.seek(val, true)
            if not animation_player.is_playing():
                _capture_all_edit_bases_after_seek()
    )
    slider_hbox.add_child(timeline_slider)

    time_label = Label.new()
    time_label.text = "Frame 0 / 0 • 0.0s / 0.0s"
    slider_hbox.add_child(time_label)

    var trim_hbox := HBoxContainer.new()
    bot_vbox.add_child(trim_hbox)

    var trim_heading := Label.new()
    trim_heading.text = "TRIM RANGE"
    trim_heading.add_theme_color_override("font_color", Color(0.3, 0.9, 1.0))
    trim_hbox.add_child(trim_heading)

    var trim_in_minus := Button.new()
    trim_in_minus.text = "In −1"
    trim_in_minus.tooltip_text = "Remove one frame from the beginning."
    trim_in_minus.pressed.connect(func(): _nudge_trim_in(1))
    trim_hbox.add_child(trim_in_minus)

    var set_in_button := Button.new()
    set_in_button.text = "Set Trim In"
    set_in_button.pressed.connect(_set_trim_in)
    trim_hbox.add_child(set_in_button)

    var trim_in_plus := Button.new()
    trim_in_plus.text = "In +1"
    trim_in_plus.tooltip_text = "Add one frame before the current trim beginning."
    trim_in_plus.pressed.connect(func(): _nudge_trim_in(-1))
    trim_hbox.add_child(trim_in_plus)

    var trim_out_minus := Button.new()
    trim_out_minus.text = "Out −1"
    trim_out_minus.tooltip_text = "Remove one frame from the end."
    trim_out_minus.pressed.connect(func(): _nudge_trim_out(-1))
    trim_hbox.add_child(trim_out_minus)

    var set_out_button := Button.new()
    set_out_button.text = "Set Trim Out"
    set_out_button.pressed.connect(_set_trim_out)
    trim_hbox.add_child(set_out_button)

    var trim_out_plus := Button.new()
    trim_out_plus.text = "Out +1"
    trim_out_plus.tooltip_text = "Add one frame after the current trim end."
    trim_out_plus.pressed.connect(func(): _nudge_trim_out(1))
    trim_hbox.add_child(trim_out_plus)

    trim_label = Label.new()
    trim_label.custom_minimum_size = Vector2(190, 0)
    trim_hbox.add_child(trim_label)

    var add_segment_button := Button.new()
    add_segment_button.text = "+ Add Range"
    add_segment_button.tooltip_text = "Append the selected frame range to the combined clip queue."
    add_segment_button.pressed.connect(_add_current_trim_segment)
    trim_hbox.add_child(add_segment_button)

    var save_trim_button := Button.new()
    save_trim_button.text = "Save Trim"
    save_trim_button.tooltip_text = "Save only this selected frame range as a new authored clip."
    save_trim_button.pressed.connect(_save_current_trim)
    trim_hbox.add_child(save_trim_button)

    var assembly_hbox := HBoxContainer.new()
    bot_vbox.add_child(assembly_hbox)

    assembly_drop_target = SLOT_DROP_TARGET.new()
    assembly_drop_target.name = "AssemblyClipDropTarget"
    assembly_drop_target.custom_minimum_size = Vector2(305, 28)
    assembly_drop_target.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    assembly_drop_target.tooltip_text = "Drag a clip from the left library here to append its complete frame range."
    assembly_drop_target.clip_dropped.connect(_on_clip_dropped_to_assembly)
    assembly_drop_target.drop_visual_state_changed.connect(_on_assembly_drop_visual_state_changed)
    assembly_hbox.add_child(assembly_drop_target)

    assembly_drop_label = Label.new()
    assembly_drop_label.text = "DROP CLIP HERE → append full clip"
    assembly_drop_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
    assembly_drop_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
    assembly_drop_target.add_child(assembly_drop_label)

    var add_full_clip_button := Button.new()
    add_full_clip_button.text = "+ Add Full Clip"
    add_full_clip_button.tooltip_text = "No dragging required: append the selected library clip's complete frame range."
    add_full_clip_button.pressed.connect(_add_selected_full_clip)
    assembly_hbox.add_child(add_full_clip_button)

    var undo_segment_button := Button.new()
    undo_segment_button.text = "Undo Range"
    undo_segment_button.pressed.connect(_undo_assembly_segment)
    assembly_hbox.add_child(undo_segment_button)

    var clear_segments_button := Button.new()
    clear_segments_button.text = "Clear"
    clear_segments_button.pressed.connect(_clear_assembly_segments)
    assembly_hbox.add_child(clear_segments_button)

    assembly_label = Label.new()
    assembly_label.custom_minimum_size = Vector2(190, 0)
    assembly_hbox.add_child(assembly_label)

    authored_name_input = LineEdit.new()
    authored_name_input.placeholder_text = "new_clip_name"
    authored_name_input.custom_minimum_size = Vector2(180, 0)
    assembly_hbox.add_child(authored_name_input)

    var save_assembly_button := Button.new()
    save_assembly_button.text = "Save Combined Clip"
    save_assembly_button.pressed.connect(_save_authored_assembly)
    assembly_hbox.add_child(save_assembly_button)

    var btn_hbox := HBoxContainer.new()
    bot_vbox.add_child(btn_hbox)

    skin_button = Button.new()
    skin_button.text = "Switch Skin (Tab)"
    skin_button.pressed.connect(_toggle_skin)
    btn_hbox.add_child(skin_button)

    weapon_selector_button = Button.new()
    weapon_selector_button.text = "Weapon (G): " + _weapon_name(current_weapon)
    weapon_selector_button.pressed.connect(_cycle_weapon)
    btn_hbox.add_child(weapon_selector_button)

    bubbles_toggle_btn = Button.new()
    bubbles_toggle_btn.text = "Pose Bubbles (B): ON"
    bubbles_toggle_btn.pressed.connect(_toggle_bubbles)
    btn_hbox.add_child(bubbles_toggle_btn)

    pose_tool_button = Button.new()
    pose_tool_button.text = "Bone Tool (M): ROTATE"
    pose_tool_button.tooltip_text = "Rotate: drag. Move: drag X/Y; hold Shift and drag vertically for depth."
    pose_tool_button.pressed.connect(_toggle_pose_edit_mode)
    btn_hbox.add_child(pose_tool_button)

    var reset_pose_btn := Button.new()
    reset_pose_btn.text = "Reset Pose (C)"
    reset_pose_btn.pressed.connect(_clear_bone_rot_offsets)
    btn_hbox.add_child(reset_pose_btn)

    var gun_lab_btn := Button.new()
    gun_lab_btn.text = "Two-Hand Engine (L)"
    gun_lab_btn.pressed.connect(_toggle_gun_lab)
    btn_hbox.add_child(gun_lab_btn)

    speed_button = Button.new()
    speed_button.text = "Speed: 1.0x"
    speed_button.pressed.connect(func():
        if playback_speed == 1.0: playback_speed = 0.5
        elif playback_speed == 0.5: playback_speed = 0.25
        elif playback_speed == 0.25: playback_speed = 2.0
        else: playback_speed = 1.0
        speed_button.text = "Speed: %.2fx" % playback_speed
        if animation_player:
            animation_player.speed_scale = playback_speed
    )
    btn_hbox.add_child(speed_button)

    var reset_cam_btn := Button.new()
    reset_cam_btn.text = "Reset View (R)"
    reset_cam_btn.pressed.connect(_reset_camera)
    btn_hbox.add_child(reset_cam_btn)

func _add_slider_control(parent: Control, label_text: String, min_val: float, max_val: float, default_val: float, callback: Callable) -> void:
    var hbox := HBoxContainer.new()
    parent.add_child(hbox)
    var lbl := Label.new()
    lbl.text = "%-12s" % label_text
    lbl.custom_minimum_size = Vector2(95, 0)
    hbox.add_child(lbl)
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = (max_val - min_val) / 200.0
    slider.value = default_val
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(callback)
    hbox.add_child(slider)

func _add_gun_slider(parent: Control, label_text: String, key: String, min_val: float, max_val: float, default_val: float, step_val: float, callback: Callable) -> void:
    var hbox := HBoxContainer.new()
    parent.add_child(hbox)
    var lbl := Label.new()
    lbl.text = "%-16s" % label_text
    lbl.custom_minimum_size = Vector2(130, 0)
    lbl.add_theme_font_size_override("font_size", 11)
    hbox.add_child(lbl)
    
    var val_lbl := Label.new()
    val_lbl.text = "%.2f" % default_val
    val_lbl.custom_minimum_size = Vector2(45, 0)
    val_lbl.add_theme_font_size_override("font_size", 11)
    val_lbl.add_theme_color_override("font_color", Color(0.2, 1.0, 0.6))
    
    var slider := HSlider.new()
    slider.min_value = min_val
    slider.max_value = max_val
    slider.step = step_val
    slider.value = default_val
    slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
    slider.value_changed.connect(func(v):
        val_lbl.text = ("%.1f°" % v) if "rot" in key else ("%.3f" % v if "pos" in key else "%.2fx" % v)
        callback.call(v)
    )
    hbox.add_child(slider)
    hbox.add_child(val_lbl)
    gun_sliders[key] = {"slider": slider, "label": val_lbl}

func _update_gun_sliders_and_mesh() -> void:
    if gun_sliders.has("pos_x"): gun_sliders["pos_x"]["slider"].value = right_grip_pos.x
    if gun_sliders.has("pos_y"): gun_sliders["pos_y"]["slider"].value = right_grip_pos.y
    if gun_sliders.has("pos_z"): gun_sliders["pos_z"]["slider"].value = right_grip_pos.z
    if gun_sliders.has("rot_x"): gun_sliders["rot_x"]["slider"].value = right_grip_rot.x
    if gun_sliders.has("rot_y"): gun_sliders["rot_y"]["slider"].value = right_grip_rot.y
    if gun_sliders.has("rot_z"): gun_sliders["rot_z"]["slider"].value = right_grip_rot.z
    if gun_sliders.has("scale"): gun_sliders["scale"]["slider"].value = weapon_scale_factor
    _sync_weapon_node_transform()

func _print_weapon_config() -> void:
    print("=" .repeat(60))
    print("  WEAPON TRANSFORM CONFIG")
    print("=" .repeat(60))
    print("var right_grip_pos := Vector3(%.4f, %.4f, %.4f)" % [right_grip_pos.x, right_grip_pos.y, right_grip_pos.z])
    print("var right_grip_rot := Vector3(%.1f, %.1f, %.1f)" % [right_grip_rot.x, right_grip_rot.y, right_grip_rot.z])
    print("var weapon_scale_factor: float = %.2f" % weapon_scale_factor)
    print("=" .repeat(60))
    if limb_hud_label:
        limb_hud_label.visible = true
        limb_hud_label.text = "Config printed to Godot Output!"
        get_tree().create_timer(3.0).timeout.connect(func(): limb_hud_label.visible = false)

func _refresh_clip_list_ui() -> void:
    for child in clip_list_vbox.get_children():
        child.queue_free()

    for i in range(filtered_entries.size()):
        var entry: Dictionary = filtered_entries[i]
        var row := HBoxContainer.new()
        row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        var highlight_button := Button.new()
        highlight_button.toggle_mode = true
        highlight_button.button_pressed = _is_entry_highlighted(entry)
        highlight_button.text = "★" if highlight_button.button_pressed else "☆"
        highlight_button.custom_minimum_size = Vector2(38, 0)
        highlight_button.tooltip_text = "Highlight this clip and add it to the purple proposal branch."
        var row_entry := entry.duplicate(true)
        highlight_button.toggled.connect(func(enabled: bool):
            _set_entry_highlighted(row_entry, enabled)
        )
        row.add_child(highlight_button)

        var btn := CLIP_DRAG_BUTTON.new()
        btn.clip_entry = entry.duplicate(true)
        btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
        btn.clip_text = true
        btn.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
        var prefix := "▶ " if i == clip_index else "  "
        btn.text = prefix + entry["display"]
        btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
        if highlight_button.button_pressed:
            btn.add_theme_color_override("font_color", Color(0.9, 0.75, 1.0))
        var idx := i
        btn.pressed.connect(func():
            clip_index = idx
            _play_selected()
            _refresh_clip_list_ui()
        )
        row.add_child(btn)
        clip_list_vbox.add_child(row)
    _refresh_slot_suggestion()

func _entry_identity(entry: Dictionary) -> String:
    var path := str(entry.get("path", ""))
    return path if not path.is_empty() else "%s:%s" % [str(entry.get("type", "")), str(entry.get("key", entry.get("name", "")))]

func _highlighted_entry_index(entry: Dictionary) -> int:
    var identity := _entry_identity(entry)
    for index in range(highlighted_clip_entries.size()):
        if _entry_identity(highlighted_clip_entries[index]) == identity:
            return index
    return -1

func _is_entry_highlighted(entry: Dictionary) -> bool:
    return _highlighted_entry_index(entry) >= 0

func _set_entry_highlighted(entry: Dictionary, enabled: bool) -> void:
    var existing_index := _highlighted_entry_index(entry)
    if enabled and existing_index < 0:
        highlighted_clip_entries.append(entry.duplicate(true))
    elif not enabled and existing_index >= 0:
        highlighted_clip_entries.remove_at(existing_index)
    _save_highlighted_shortlist()
    _select_entry_for_preview(entry)
    _refresh_runtime_state_tree()
    _refresh_clip_list_ui()
    status_label.text = "%d highlighted clip%s saved for Codex and shown as purple graph proposals." % [
        highlighted_clip_entries.size(),
        "" if highlighted_clip_entries.size() == 1 else "s",
    ]

func _clear_highlighted_clips() -> void:
    highlighted_clip_entries.clear()
    _save_highlighted_shortlist()
    _refresh_runtime_state_tree()
    _refresh_clip_list_ui()
    status_label.text = "Highlighted animation proposals cleared."

func _highlight_shortlist_payload() -> Dictionary:
    var selected_clips: Array[Dictionary] = []
    for raw_entry in highlighted_clip_entries:
        var entry := raw_entry.duplicate(true)
        entry["suggested_slot"] = _suggest_slot_for_entry(entry)
        selected_clips.append({
            "display": str(entry.get("display", "Animation clip")),
            "type": str(entry.get("type", "")),
            "key": str(entry.get("key", entry.get("name", ""))),
            "path": str(entry.get("path", "")),
            "suggested_slot": str(entry.get("suggested_slot", "")),
        })
    return {
        "version": 1,
        "purpose": "User-selected animation candidates for Codex review and route assembly.",
        "selected_clips": selected_clips,
    }

func _save_highlighted_shortlist() -> void:
    var file := FileAccess.open(HIGHLIGHT_SHORTLIST_PATH, FileAccess.WRITE)
    if file == null:
        if status_label:
            status_label.text = "Could not save the highlighted animation shortlist."
        return
    file.store_string(JSON.stringify(_highlight_shortlist_payload(), "  "))

func _load_highlighted_shortlist() -> void:
    highlighted_clip_entries.clear()
    if not FileAccess.file_exists(HIGHLIGHT_SHORTLIST_PATH):
        return
    var file := FileAccess.open(HIGHLIGHT_SHORTLIST_PATH, FileAccess.READ)
    var parsed: Variant = JSON.parse_string(file.get_as_text()) if file else null
    if not parsed is Dictionary:
        return
    var saved_clips: Variant = (parsed as Dictionary).get("selected_clips", [])
    if not saved_clips is Array:
        return
    for raw_saved in saved_clips:
        if not raw_saved is Dictionary:
            continue
        var saved: Dictionary = raw_saved
        var saved_identity := _entry_identity(saved)
        for entry in all_clip_entries:
            if _entry_identity(entry) == saved_identity:
                highlighted_clip_entries.append(entry.duplicate(true))
                break

func _select_entry_for_preview(entry: Dictionary) -> void:
    var identity := _entry_identity(entry)
    for index in range(filtered_entries.size()):
        if _entry_identity(filtered_entries[index]) == identity:
            clip_index = index
            _play_selected()
            return

func _on_graph_candidate_selected(entry: Dictionary) -> void:
    var identity := _entry_identity(entry)
    for index in range(filtered_entries.size()):
        if _entry_identity(filtered_entries[index]) == identity:
            clip_index = index
            _play_selected()
            _refresh_clip_list_ui()
            status_label.text = "Selected highlighted proposal: %s" % str(entry.get("display", "Animation clip"))
            return

func _on_clip_dropped(entry: Dictionary) -> void:
    _assign_entry_to_slot(entry, selected_state_slot)

func _on_clip_dropped_on_tree_state(entry: Dictionary, slot_name: String) -> void:
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _assign_entry_to_slot(entry, slot_name)

func _on_route_state_selected(slot_name: String) -> void:
    selected_state_slot = slot_name
    _select_state_slot_in_selector(slot_name)
    _refresh_slot_ui()

func _select_state_slot_in_selector(slot_name: String) -> void:
    var selector_index := state_slot_keys.find(slot_name)
    if selector_index >= 0 and state_slot_selector:
        state_slot_selector.select(selector_index)

func _refresh_runtime_state_tree() -> void:
    if runtime_route_graph == null:
        return
    var graph_candidates: Array[Dictionary] = []
    for highlighted_entry in highlighted_clip_entries:
        var candidate := highlighted_entry.duplicate(true)
        candidate["suggested_slot"] = _suggest_slot_for_entry(candidate)
        graph_candidates.append(candidate)
    runtime_route_graph.call("set_state_data", state_slots, selected_state_slot, graph_candidates)

func _state_group_for_slot(slot_name: String) -> String:
    if slot_name == "idle_crouch" or slot_name.begins_with("crouch_"):
        return "CROUCH"
    if slot_name == "idle_prone" or slot_name.begins_with("prone_"):
        return "PRONE"
    if slot_name.begins_with("jump_") or slot_name in ["dive_roll", "roll"]:
        return "MOBILITY"
    if slot_name in ["combat_fire", "reload", "aim_idle"]:
        return "COMBAT"
    if (
        slot_name.begins_with("start_")
        or slot_name.begins_with("stop_")
        or slot_name.begins_with("turn_")
        or slot_name == "run_to_stop"
    ):
        return "TRANSITIONS"
    return "STANDING LOCOMOTION"

func _assign_selected_to_suggested_slot() -> void:
    if filtered_entries.is_empty():
        return
    var entry: Dictionary = filtered_entries[clip_index]
    var suggestion := _suggest_slot_for_entry(entry)
    if suggestion.is_empty():
        status_label.text = "No safe runtime-state suggestion was found for this clip."
        return
    selected_state_slot = suggestion
    _select_state_slot_in_selector(suggestion)
    _assign_entry_to_slot(entry, suggestion)

func _refresh_slot_suggestion() -> void:
    if slot_suggestion_label == null:
        return
    if filtered_entries.is_empty():
        slot_suggestion_label.text = "BEST MATCH: none"
        return
    var suggestion := _suggest_slot_for_entry(filtered_entries[clip_index])
    if suggestion.is_empty():
        slot_suggestion_label.text = "BEST MATCH: preview only — drag manually or propose a new route"
    else:
        slot_suggestion_label.text = "BEST MATCH: %s (review before applying)" % suggestion

func _suggest_slot_for_entry(entry: Dictionary) -> String:
    if str(entry.get("type", "")) != "FBX":
        return ""
    var path := str(entry.get("path", "")).to_lower()
    var best_slot := ""
    var best_score := -1
    var targets := _slot_targets()
    for slot_key in targets.keys():
        for candidate in targets[slot_key]:
            var candidate_text := str(candidate).to_lower()
            if candidate_text in path and candidate_text.length() > best_score:
                best_slot = str(slot_key)
                best_score = candidate_text.length()
    return best_slot

func _find_animation_player(node: Node) -> AnimationPlayer:
    if node is AnimationPlayer:
        return node as AnimationPlayer
    for child in node.get_children():
        var found := _find_animation_player(child)
        if found:
            return found
    return null

func _find_skeleton(node: Node) -> Skeleton3D:
    if node is Skeleton3D:
        return node as Skeleton3D
    for child in node.get_children():
        var found := _find_skeleton(child)
        if found:
            return found
    return null

func _on_search_changed(query: String) -> void:
    filtered_entries.clear()
    var q := query.strip_edges().to_lower()
    for entry in all_clip_entries:
        var name_str: String = str(entry["display"]).to_lower()
        if q == "" or q in name_str:
            filtered_entries.append(entry)
    clip_index = 0
    if not filtered_entries.is_empty():
        _play_selected()
    _refresh_clip_list_ui()

func _auto_map_all_slots() -> void:
    # Conservative mapping into known states. It does not invent gameplay logic.
    var slot_targets: Dictionary = {
        "idle_rifle": ["Lite Rifle Pack/idle", "Rifle 8-Way Locomotion Pack/idle", "idle"],
        "aim_idle": ["Shooter Pack/rifle aiming idle", "aiming idle", "idle"],
        "run_forward": ["Lite Rifle Pack/run forward", "run forward", "walk forward"],
        "run_backward": ["Lite Rifle Pack/run backward", "run backward", "walk backward"],
        "run_left": ["Lite Rifle Pack/run left", "run left", "walk left"],
        "run_right": ["Lite Rifle Pack/run right", "run right", "walk right"],
        "run_forward_left": ["Lite Rifle Pack/run forward left", "run forward left"],
        "run_forward_right": ["Lite Rifle Pack/run forward right", "run forward right"],
        "run_back_left": ["Lite Rifle Pack/run backward left", "run backward left"],
        "run_back_right": ["Lite Rifle Pack/run backward right", "run backward right"],
        "idle_crouch": ["Rifle 8-Way Locomotion Pack/idle crouching", "idle crouching", "crouch idle"],
        "crouch_forward": ["Rifle 8-Way Locomotion Pack/walk crouching forward", "walk crouching forward"],
        "crouch_backward": ["Rifle 8-Way Locomotion Pack/walk crouching backward", "walk crouching backward"],
        "crouch_left": ["Rifle 8-Way Locomotion Pack/walk crouching left", "walk crouching left"],
        "crouch_right": ["Rifle 8-Way Locomotion Pack/walk crouching right", "walk crouching right"],
        "crouch_forward_left": ["Rifle 8-Way Locomotion Pack/walk crouching forward left"],
        "crouch_forward_right": ["Rifle 8-Way Locomotion Pack/walk crouching forward right"],
        "crouch_back_left": ["Rifle 8-Way Locomotion Pack/walk crouching backward left"],
        "crouch_back_right": ["Rifle 8-Way Locomotion Pack/walk crouching backward right"],
        "idle_prone": ["Prone Firing Rifle", "Prone Idle", "Prone Forward Stop"],
        "prone_forward": ["Prone Forward", "Crawl Forward"],
        "prone_backward": ["Moving Backward In Prone Position", "Prone Backward"],
        "prone_turn_left": ["Prone Left Turn", "Prone Turn Left"],
        "prone_turn_right": ["Prone Right Turn", "Prone Turn Right", "Prone Left Turn"],
        "prone_fire": ["Prone Firing Rifle", "Prone Fire"],
        "prone_reload": ["Prone Reloading", "Prone Reload"],
        "dive_roll": ["Running Dive Roll", "Dive Roll"],
        "roll": ["Run To Rolling", "Roll"],
        "jump_up": ["Rifle 8-Way Locomotion Pack/jump up", "jump up"],
        "jump_loop": ["Rifle 8-Way Locomotion Pack/jump loop", "jump loop"],
        "jump_down": ["Rifle 8-Way Locomotion Pack/jump down", "jump down"],
        "combat_fire": ["Shooter Pack/firing rifle", "firing rifle"],
        "reload": ["Reloading", "Reload"]
    }

    var mapped_count := 0
    for slot_key in slot_targets.keys():
        var candidates: Array = slot_targets[slot_key]
        var found_path := ""
        for cand in candidates:
            var cand_str: String = str(cand).to_lower()
            for entry in all_clip_entries:
                if entry["type"] != "FBX": continue
                var full_path: String = entry["path"].to_lower()
                if cand_str in full_path:
                    found_path = entry["path"]
                    break
            if found_path != "":
                break
        
        if found_path != "":
            state_slots[slot_key] = found_path
            mapped_count += 1

    _save_state_slots()
    _refresh_slot_ui()
    if limb_hud_label:
        limb_hud_label.visible = true
        limb_hud_label.text = "⚡ Auto-built %d / %d known runtime states. Review before playtesting." % [mapped_count, slot_targets.size()]
        get_tree().create_timer(4.0).timeout.connect(func(): limb_hud_label.visible = false)

func _slot_targets() -> Dictionary:
    return {
        "idle_rifle": ["Lite Rifle Pack/idle", "Rifle 8-Way Locomotion Pack/idle", "idle"],
        "aim_idle": ["Shooter Pack/rifle aiming idle", "aiming idle"],
        "run_forward": ["Lite Rifle Pack/run forward", "run forward"],
        "run_backward": ["Lite Rifle Pack/run backward", "run backward"],
        "run_left": ["Lite Rifle Pack/run left", "run left"],
        "run_right": ["Lite Rifle Pack/run right", "run right"],
        "run_forward_left": ["Lite Rifle Pack/run forward left", "run forward left"],
        "run_forward_right": ["Lite Rifle Pack/run forward right", "run forward right"],
        "run_back_left": ["Lite Rifle Pack/run backward left", "run backward left"],
        "run_back_right": ["Lite Rifle Pack/run backward right", "run backward right"],
        "idle_crouch": ["idle crouching", "crouch idle"],
        "crouch_forward": ["walk crouching forward"],
        "crouch_backward": ["walk crouching backward"],
        "crouch_left": ["walk crouching left"],
        "crouch_right": ["walk crouching right"],
        "crouch_forward_left": ["walk crouching forward left"],
        "crouch_forward_right": ["walk crouching forward right"],
        "crouch_back_left": ["walk crouching backward left"],
        "crouch_back_right": ["walk crouching backward right"],
        "idle_prone": ["Prone Firing Rifle", "Prone Idle"],
        "prone_forward": ["Prone Forward", "Crawl Forward"],
        "prone_backward": ["Moving Backward In Prone Position", "Prone Backward"],
        "prone_turn_left": ["Prone Left Turn", "Prone Turn Left"],
        "prone_turn_right": ["Prone Right Turn", "Prone Turn Right"],
        "prone_fire": ["Prone Firing Rifle", "Prone Fire"],
        "prone_reload": ["Prone Reloading", "Prone Reload"],
        "dive_roll": ["Running Dive Roll", "Dive Roll"],
        "roll": ["Run To Rolling", "Roll"],
        "jump_up": ["jump up"],
        "jump_loop": ["jump loop"],
        "jump_down": ["jump down"],
        "combat_fire": ["firing rifle"],
        "reload": ["Reloading", "Reload"],
        "start_forward": ["Start Walking"],
        "start_backward": ["start walking backwards"],
        "stop_forward": ["stop walking"],
        "stop_backward": ["walk backwards stop"],
        "run_to_stop": ["Run To Stop"],
        "crouch_start": ["Rifle Crouch Idle To Walk"],
        "crouch_stop": ["Crouch Stop Walking"],
        "turn_90_left": ["turn 90 left"],
        "turn_90_right": ["turn 90 right"],
    }

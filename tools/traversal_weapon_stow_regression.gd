extends SceneTree

const Stow := preload("res://scripts/player/operator_traversal_stow.gd")

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting("socom/session/selected_map_document", load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	change_scene_to_file("res://main.tscn")
	await scene_changed
	for frame in 12: await process_frame
	var driver = current_scene.get_node("Player/Mannequin/ProductionAnimation")
	var skeleton: Skeleton3D = driver.skeleton
	var weapon: Node3D = driver.weapon_node
	var parent := weapon.get_parent()
	var transform := weapon.transform
	var was_visible := weapon.visible
	var helper := Stow.new()
	assert(helper.begin(skeleton, weapon, &"TWO_HAND_RIFLE"))
	assert(helper.copied_mesh_count > 0)
	assert(helper.attachment.bone_name == "mixamorig_Spine2" and not helper.attachment.override_pose)
	assert(helper.begin(skeleton, weapon, &"TWO_HAND_RIFLE"))
	var id := helper.attachment.get_instance_id()
	assert(helper.begin(skeleton, weapon, &"TWO_HAND_RIFLE") and id == helper.attachment.get_instance_id())
	for node: Node in helper.visual.find_children("*", "", true, false):
		assert(node is MeshInstance3D and node.get_script() == null)
		assert((node as MeshInstance3D).skin == null)
	assert(weapon.get_parent() == parent and weapon.transform.is_equal_approx(transform) and weapon.visible == was_visible)
	print("TRAVERSAL_WEAPON_STOW PASS primary cosmetic mesh count=", helper.copied_mesh_count)
	if "--capture" in OS.get_cmdline_user_args():
		weapon.visible = false
		var actor: Node3D = current_scene.get_node("Player")
		var camera := Camera3D.new()
		camera.fov = 45.0
		current_scene.add_child(camera)
		camera.global_position = actor.global_position + Vector3(2.8, 2.1, 3.1)
		camera.look_at(actor.global_position + Vector3.UP * 1.1)
		camera.current = true
		await process_frame
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art_source/traversal_runtime_proof"))
		root.get_texture().get_image().save_png("res://art_source/traversal_runtime_proof/stow-rifle.png")
		weapon.visible = was_visible
	helper.end()
	await process_frame
	assert(helper.attachment == null and helper.visual == null)
	# Build a real saved pistol visual through the existing asset owner without
	# changing the player's equipped weapon, loadout, ammo or saved configuration.
	var pistol_assets = load("res://scripts/player/operator_asset_runtime.gd").new()
	pistol_assets.skeleton = skeleton
	pistol_assets.weapon_attachment = BoneAttachment3D.new()
	pistol_assets.weapon_attachment.bone_name = "mixamorig_RightHand"
	skeleton.add_child(pistol_assets.weapon_attachment)
	var pistol_profile: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://config/weapons/mark_23.json"))
	assert(pistol_assets._attach_calibrated_weapon(pistol_profile))
	var pistol: Node3D = pistol_assets.weapon_node
	var pistol_transform := pistol.transform
	assert(helper.begin(skeleton, pistol, &"TWO_HAND_PISTOL"))
	assert(helper.attachment.bone_name == "mixamorig_Hips")
	assert(pistol.transform.is_equal_approx(pistol_transform))
	print("TRAVERSAL_WEAPON_STOW PASS actual Mark23 cosmetic mesh count=", helper.copied_mesh_count)
	helper.end()
	pistol_assets.weapon_attachment.queue_free()
	await process_frame
	assert(helper.attachment == null and weapon.get_parent() == parent)
	var fixture := Node3D.new()
	current_scene.add_child(fixture)
	var fixture_mesh := MeshInstance3D.new()
	fixture_mesh.mesh = BoxMesh.new()
	fixture.add_child(fixture_mesh)
	assert(helper.begin(skeleton, fixture))
	var old_attachment := helper.attachment.get_instance_id()
	fixture_mesh.mesh = SphereMesh.new()
	assert(helper.begin(skeleton, fixture) and helper.attachment.get_instance_id() != old_attachment)
	assert((helper.visual.get_child(0) as MeshInstance3D).mesh == fixture_mesh.mesh)
	helper.end()
	fixture.queue_free()
	await process_frame
	var temporary_skeleton := Skeleton3D.new()
	temporary_skeleton.add_bone("mixamorig_Spine2")
	current_scene.add_child(temporary_skeleton)
	assert(helper.begin(temporary_skeleton, weapon))
	temporary_skeleton.free()
	helper.end()
	assert(helper.attachment == null)
	print("TRAVERSAL_WEAPON_STOW_REGRESSION PASS cosmetic only / idempotent / source unchanged / clean exit")
	quit()

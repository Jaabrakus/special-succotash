extends SceneTree
## Offline art intake only. No gameplay scene is instantiated or modified.

const BASE := "res://art_source/sketchfab_intake_20260906/"
var failed: bool = false

func _initialize() -> void:
	call_deferred("_run")

func _collect(node: Node, report: Dictionary, parent_transform: Transform3D = Transform3D.IDENTITY) -> void:
	var current: Transform3D = parent_transform
	if node is Node3D:
		current = parent_transform * (node as Node3D).transform
		if not current.is_finite():
			report.errors.append("Nonfinite transform: " + str(node.name))
	if node is MeshInstance3D:
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			report.errors.append("Missing mesh: " + str(node.name))
		else:
			report.mesh_instances += 1
			var box: AABB = current * instance.get_aabb()
			report.mesh_bounds.append({"node": str(node.name), "position": [box.position.x, box.position.y, box.position.z], "size": [box.size.x, box.size.y, box.size.z]})
			for surface in instance.mesh.get_surface_count():
				var material: Material = instance.get_active_material(surface)
				if material == null:
					report.errors.append("Missing material: " + str(node.name))
				elif material is BaseMaterial3D:
					var base := material as BaseMaterial3D
					if base.albedo_texture != null:
						report.textured_surfaces += 1
						if base.albedo_texture.get_width() <= 0:
							report.errors.append("Empty albedo: " + str(node.name))
	if node is Skeleton3D:
		report.skeleton_bones += (node as Skeleton3D).get_bone_count()
	if node is AnimationPlayer:
		for animation in (node as AnimationPlayer).get_animation_list():
			report.animations.append(str(animation))
	for child in node.get_children():
		_collect(child, report, current)

func _run() -> void:
	var manifest: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(BASE + "inventory.json"))
	var results: Array[Dictionary] = []
	for record: Dictionary in manifest.assets:
		if record.status == "held":
			continue
		var report: Dictionary = {"id": record.id, "errors": [], "mesh_instances": 0, "textured_surfaces": 0, "skeleton_bones": 0, "animations": [], "mesh_bounds": []}
		var document := GLTFDocument.new()
		var state := GLTFState.new()
		var err: Error = document.append_from_file("res://" + str(record.gltf), state)
		if err != OK:
			report.errors.append("GLTF load error " + str(err))
		else:
			var scene: Node = document.generate_scene(state, 30.0, false, false)
			if scene == null:
				report.errors.append("No scene generated")
			else:
				var packed := PackedScene.new()
				var target: String = "res://" + str(record.gltf).get_base_dir() + "/imported.scn"
				err = packed.pack(scene)
				if err == OK:
					err = ResourceSaver.save(packed, target, ResourceSaver.FLAG_COMPRESS)
				if err != OK:
					report.errors.append("Scene save error " + str(err))
				else:
					var reloaded := ResourceLoader.load(target, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
					if reloaded == null:
						report.errors.append("Scene reload failed")
					else:
						var check: Node = reloaded.instantiate()
						_collect(check, report)
						check.free()
						report.saved_scene = target
				scene.free()
		if report.mesh_instances != int(record.meshes):
			report.errors.append("Mesh count differs from source")
		if report.textured_surfaces == 0:
			report.errors.append("No textured surfaces")
		for animation: String in record.animations:
			if not report.animations.has(animation):
				report.errors.append("Missing animation: " + animation)
		if int(record.skins) > 0 and report.skeleton_bones == 0:
			report.errors.append("Missing skeleton")
		report.status = "import_save_reload_pass" if report.errors.is_empty() else "failed"
		failed = failed or not report.errors.is_empty()
		results.append(report)
		print(record.id, ": ", report.status, " meshes=", report.mesh_instances, " animations=", report.animations.size(), " errors=", report.errors)
	var output := FileAccess.open(BASE + "godot_validation.json", FileAccess.WRITE)
	output.store_string(JSON.stringify({"engine": Engine.get_version_info(), "results": results, "visual_check": "pending", "runtime_integration": false}, "\t"))
	output.close()
	quit(1 if failed else 0)

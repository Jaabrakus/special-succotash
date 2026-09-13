extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	ProjectSettings.set_setting("socom/playtest/use_active_bundle", false)
	if not "--user-map" in OS.get_cmdline_user_args():
		ProjectSettings.set_setting("socom/session/selected_map_document", load("res://scripts/maps/socom_map_document.gd").load_path("res://config/maps/current_map.json"))
	var scene := load("res://main.tscn").instantiate() as Node3D
	root.add_child(scene)
	for frame in 60:
		await physics_frame
		await process_frame
	var player := scene.get_node("Player") as CharacterBody3D
	player.set_physics_process(false)
	var shape := player.get_node("CollisionShape3D").shape as CapsuleShape3D
	var report: Array = []
	for node in scene.find_children("*", "Node3D", true, false):
		var id := str(node.get_meta("map_object_id", ""))
		if id not in ["relic_014", "relic_038", "relic_039", "relic_040"]: continue
		var bounds := AABB()
		var first := true
		for mesh: MeshInstance3D in node.find_children("*", "MeshInstance3D", true, false):
			if mesh.mesh == null: continue
			var box: AABB = mesh.global_transform * mesh.get_aabb()
			bounds = box if first else bounds.merge(box)
			first = false
		var counts := {}
		var accepted: Array = []
		for side in 4:
			for along in 9:
				for height: float in [0.05, 0.6, 1.15, 1.75, 2.35, 2.95, 3.55]:
					var point := bounds.get_center()
					var direction := Vector3.ZERO
					if side < 2:
						point.x = bounds.position.x - 0.5 if side == 0 else bounds.end.x + 0.5
						point.z = lerpf(bounds.position.z, bounds.end.z, float(along + 1) / 10)
						direction = Vector3.RIGHT if side == 0 else Vector3.LEFT
					else:
						point.z = bounds.position.z - 0.5 if side == 2 else bounds.end.z + 0.5
						point.x = lerpf(bounds.position.x, bounds.end.x, float(along + 1) / 10)
						direction = Vector3.BACK if side == 2 else Vector3.FORWARD
					point.y = height
					player.global_position = point
					var result: Dictionary = player.traversal.mantle_motor.probe_climb(player, direction, shape.height, shape.radius)
					var reason := str(result.get("reason", "accepted"))
					counts[reason] = int(counts.get(reason, 0)) + 1
					if bool(result.get("accepted", false)): accepted.append({"feet":point,"direction":direction,"anchor":result.anchor})
		var row := {"id":id,"bounds":str(bounds),"counts":counts,"accepted":accepted}
		if id == "relic_014":
			var heights: Array = []
			for x: float in [-30.2, -29.8, -29.4, -29.0, -28.5, -28.0, -27.5, -27.0, -26.5, -19.5, -19.0, -18.5, -18.0, -17.5, -17.0, -16.6, -16.2, -15.8]:
				var hit := player.get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(x, 10, 0), Vector3(x, -1, 0), player.collision_mask, [player.get_rid()]))
				heights.append({"x":x,"top":str(hit.get("position", Vector3.INF)),"normal":str(hit.get("normal", Vector3.ZERO)),"collider":str(hit.collider.get_path()) if hit.has("collider") else ""})
			row["roof_cross_section_z0"] = heights
			var colliders: Array = []
			for found: CollisionShape3D in node.find_children("*", "CollisionShape3D", true, false):
				colliders.append({"path":str(found.get_path()),"shape":found.shape.get_class(),"disabled":found.disabled})
			row["colliders"] = colliders
		report.append(row)
		print("MAP_LEDGE ", JSON.stringify(row))
	var file := FileAccess.open("/private/tmp/map-ledge-geometry.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(report, "\t"))
	scene.queue_free()
	await process_frame
	quit()

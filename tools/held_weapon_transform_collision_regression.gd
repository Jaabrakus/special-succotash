extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var packed := load("res://main.tscn") as PackedScene
	_expect(packed != null, "canonical main scene loads")
	if packed == null:
		_finish()
		return
	var scene := packed.instantiate()
	root.add_child(scene)
	for _frame in range(75):
		await process_frame
	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	var weapon := driver.get("weapon_node") as Node3D if driver != null else null
	var skeleton := driver.get("skeleton") as Skeleton3D if driver != null else null
	_expect(driver != null and weapon != null and skeleton != null, "realized held weapon and skeleton exist")
	if weapon == null or skeleton == null:
		scene.queue_free()
		_finish()
		return

	var collision_objects: Array[CollisionObject3D] = []
	var collision_shapes: Array[CollisionShape3D] = []
	_collect_collisions(weapon, collision_objects, collision_shapes)
	print("HELD_WEAPON_AUDIT collision_objects=%d collision_shapes=%d" % [
		collision_objects.size(), collision_shapes.size(),
	])
	for object in collision_objects:
		print("HELD_WEAPON_AUDIT collision_object=%s class=%s layer=%d mask=%d" % [
			object.get_path(), object.get_class(), object.collision_layer, object.collision_mask,
		])
		_expect(
			object.collision_layer == 0 and object.collision_mask == 0,
			"held collision object is disabled: %s" % object.get_path()
		)
	for shape in collision_shapes:
		print("HELD_WEAPON_AUDIT collision_shape=%s disabled=%s" % [shape.get_path(), shape.disabled])
		_expect(shape.disabled, "held collision shape is disabled: %s" % shape.get_path())

	var animated_weapon_tracks: Array[String] = []
	var animation_player := driver.get("animation_player") as AnimationPlayer
	if animation_player != null:
		for library_name in animation_player.get_animation_library_list():
			var library := animation_player.get_animation_library(library_name)
			for animation_name in library.get_animation_list():
				var animation := library.get_animation(animation_name)
				for track_index in range(animation.get_track_count()):
					var path_text := String(animation.track_get_path(track_index))
					if (
						"Attached_" in path_text
						or "CalibratedWeaponPivot" in path_text
						or "WeaponMesh" in path_text
					):
						animated_weapon_tracks.append("%s:%s" % [animation_name, path_text])
	print("HELD_WEAPON_AUDIT animated_weapon_tracks=%s" % [animated_weapon_tracks])
	_expect(animated_weapon_tracks.is_empty(), "AnimationPlayer does not write held weapon transforms")
	_expect(weapon.get_parent() == skeleton, "held weapon root has one Skeleton3D presentation parent")
	var pivot := weapon.get_node_or_null("CalibratedWeaponPivot") as Node3D
	_expect(pivot != null, "held weapon has a separate calibration offset node")
	if pivot != null:
		_expect(pivot.position.length() < 0.0001, "M4 calibration pivot starts at zero position")
		_expect(pivot.rotation.length() < 0.0001, "M4 calibration pivot starts at zero rotation")

	scene.queue_free()
	_finish()


func _collect_collisions(
	node: Node,
	objects: Array[CollisionObject3D],
	shapes: Array[CollisionShape3D]
) -> void:
	if node is CollisionObject3D:
		objects.append(node as CollisionObject3D)
	if node is CollisionShape3D:
		shapes.append(node as CollisionShape3D)
	for child in node.get_children():
		_collect_collisions(child, objects, shapes)


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("HELD_WEAPON_AUDIT PASS ", label)
	else:
		failures.append(label)
		push_error("HELD_WEAPON_AUDIT FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("HELD_WEAPON_TRANSFORM_COLLISION_REGRESSION PASS")
		quit(0)
	else:
		print("HELD_WEAPON_TRANSFORM_COLLISION_REGRESSION FAIL %s" % [failures])
		quit(1)

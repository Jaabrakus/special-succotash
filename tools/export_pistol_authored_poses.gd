extends SceneTree

## Bakes native upper-body rotations onto existing stance-owned lower bodies.
## Writes new animation resources only; never edits the selected weapon profile.
const SOURCE := "res://art_source/animation_audit_20260904/pistol_square_native_candidate.glb"
const DESTINATION := "res://assets/animations/authored/pistol_square"

func _initialize() -> void:
	_run.call_deferred()

func _run() -> void:
	var scene := (load("res://main.tscn") as PackedScene).instantiate()
	root.add_child(scene)
	for _frame in range(60):
		await process_frame
	var driver: Node = scene.get_node("Player/Mannequin").get("production_animation")
	var loader = load("res://tools/pistol_candidate_loader.gd").new()
	if not loader.load_candidate(ProjectSettings.globalize_path(SOURCE)) or loader.low_action == null:
		push_error("PISTOL_ASSET_EXPORT missing ready/low source")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DESTINATION))
	var library: AnimationLibrary = driver.get("dynamic_anim_lib")
	var skeleton: Skeleton3D = driver.get("skeleton")
	for stance in ["standing", "crouched"]:
		var base := library.get_animation(&"pistol_idle" if stance == "standing" else &"pistol_idle_kneeling")
		for kind in ["low", "aim"]:
			var animation: Animation = loader.compose(base, skeleton, loader.low_action if kind == "low" else loader.action)
			if float(loader.last_rest_error) > 0.1:
				push_error("PISTOL_ASSET_EXPORT rest mismatch")
				quit(1)
				return
			animation.resource_name = "pistol_%s_%s" % [kind, stance]
			animation.loop_mode = Animation.LOOP_LINEAR
			var path := "%s/%s.tres" % [DESTINATION, animation.resource_name]
			var error := ResourceSaver.save(animation, path)
			if error != OK:
				push_error("PISTOL_ASSET_EXPORT failed: %s" % path)
				quit(1)
				return
			print("PISTOL_ASSET_EXPORT saved ", path)
	loader.dispose()
	scene.queue_free()
	await process_frame
	quit(0)

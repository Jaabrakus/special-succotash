extends SceneTree

## Verifies that the read-only telemetry observer describes the canonical live
## player, camera, authored skeleton, rifle sockets, and reload presentation.

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
	for _frame in range(55):
		await process_frame
	var telemetry := scene.get_node_or_null("Programmatic3DTelemetry")
	_expect(telemetry != null, "telemetry observer is attached to main")
	if telemetry == null:
		_finish()
		return
	_expect(InputMap.has_action("toggle_3d_telemetry"), "F11 telemetry action is registered")
	_expect(bool(telemetry.call("start_recording", "regression")), "bounded recording starts")
	var status_label := telemetry.get_node_or_null("Programmatic3DStatusLayer/Programmatic3DStatus") as Label
	_expect(status_label != null and status_label.visible, "recording indicator is visible in game")
	var snapshot: Dictionary = telemetry.call("capture_now", true)
	_expect(String(snapshot.get("schema", "")) == "socom.programmatic_3d.v1", "schema is versioned")
	var camera: Dictionary = snapshot.get("camera", {})
	var player: Dictionary = snapshot.get("player", {})
	var skeleton: Dictionary = snapshot.get("skeleton", {})
	var weapon: Dictionary = snapshot.get("weapon", {})
	var animation: Dictionary = snapshot.get("animation", {})
	_expect(bool(camera.get("valid", false)), "live camera transform is captured")
	_expect(bool(player.get("valid", false)), "CharacterBody3D state is captured")
	_expect(int(skeleton.get("captured_bone_count", 0)) >= 10, "authored 3D bone chain is captured")
	var bones: Dictionary = skeleton.get("bones", {})
	_expect(bones.has("mixamorig_LeftHand") and bones.has("mixamorig_RightHand"), "both hand transforms are captured")
	_expect(bones.has("ik_hand_gun"), "AGLS authored weapon helper is captured")
	var sockets: Dictionary = weapon.get("sockets", {})
	_expect(sockets.has("Socket_Muzzle"), "muzzle socket is captured")
	_expect(sockets.has("Socket_LeftHand") and sockets.has("Socket_RightHand"), "rifle grip sockets are captured")
	_expect(bool(animation.get("valid", false)), "animation state is captured")
	_expect(not String(animation.get("weapon_owner", "")).is_empty(), "weapon presentation owner is explicit")

	var driver := scene.get_node_or_null("Player/Mannequin/ProductionAnimation")
	_expect(driver != null, "production animation driver is live")
	var saw_reload := false
	var saw_magazine := false
	if driver != null:
		var accepted := bool(driver.call("play_semantic_action", &"reload", 0.12))
		_expect(accepted, "real reload presentation starts")
		for frame in range(180):
			await process_frame
			if frame % 3 != 0:
				continue
			var reload_snapshot: Dictionary = telemetry.call("capture_now", true)
			var reload: Dictionary = reload_snapshot.get("reload", {})
			if String(reload.get("requested_action", "")).begins_with("reload"):
				saw_reload = true
			if bool(reload.get("magazine_visible", false)):
				var magazine_transform: Dictionary = reload.get("magazine_transform", {})
				saw_magazine = magazine_transform.has("origin")
				break
	_expect(saw_reload, "reload state is visible in telemetry")
	_expect(saw_magazine, "reload magazine has a live 3D transform")

	telemetry.call("stop_recording", "regression")
	var session_path := String(telemetry.call("get_session_path"))
	var latest_path := String(telemetry.call("get_latest_snapshot_path"))
	_expect(not bool(telemetry.get("recording")), "recording stops cleanly")
	_expect(status_label != null and not status_label.visible, "recording indicator hides after stop")
	_expect(FileAccess.file_exists(session_path), "JSONL session exists on disk")
	_expect(FileAccess.file_exists(latest_path), "latest snapshot exists on disk")
	var session_file := FileAccess.open(session_path, FileAccess.READ)
	var header: Variant = null
	if session_file != null:
		header = JSON.parse_string(session_file.get_line())
		session_file.close()
	_expect(header is Dictionary and String((header as Dictionary).get("record_type", "")) == "session", "session file begins with metadata")
	print("PROGRAMMATIC_3D_TELEMETRY_METRIC session=%s latest=%s bones=%d sockets=%d" % [
		session_path,
		latest_path,
		int(skeleton.get("captured_bone_count", 0)),
		sockets.size(),
	])
	scene.queue_free()
	_finish()


func _expect(condition: bool, label: String) -> void:
	if condition:
		print("PROGRAMMATIC_3D_TELEMETRY_CHECK PASS %s" % label)
		return
	failures.append(label)
	push_error("PROGRAMMATIC_3D_TELEMETRY_CHECK FAIL %s" % label)


func _finish() -> void:
	if failures.is_empty():
		print("PROGRAMMATIC_3D_TELEMETRY_REGRESSION PASS")
		quit(0)
	else:
		print("PROGRAMMATIC_3D_TELEMETRY_REGRESSION FAIL %s" % [failures])
		quit(1)

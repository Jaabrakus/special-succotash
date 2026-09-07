extends SceneTree

const Stock := preload("res://scripts/player/operator_weapon_stock_constraint.gd")
var failures: Array[String] = []


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var fixture := Node3D.new()
	root.add_child(fixture)
	var skeleton := Skeleton3D.new()
	fixture.add_child(skeleton)
	for side: String in ["Right", "Left"]:
		skeleton.add_bone("mixamorig_%sArm" % side)
		var index := skeleton.find_bone("mixamorig_%sArm" % side)
		skeleton.set_bone_rest(index, Transform3D(Basis.IDENTITY, Vector3(0.2 if side == "Right" else -0.2, 1.4, 0)))
	var socket := Marker3D.new()
	fixture.add_child(socket)
	socket.position = Vector3(0.2, 1.3, -0.05)
	var stock := Stock.new()
	fixture.add_child(stock)
	stock.bind(skeleton, socket)
	stock.configure({"enabled": false})
	_expect(not stock.is_active(), "legacy stock starts disabled")
	for posture: StringName in [&"STANDING", &"CROUCHED"]:
		_expect(stock.correction_for(Vector3.FORWARD, posture).is_zero_approx(), "default request retains disabled stock: " + posture)
		_expect(stock.can_place_authored_ready(posture), "explicit ready has bound contacts: " + posture)
		var correction := stock.correction_for(Vector3.FORWARD, posture, Vector3.INF, Vector3.ZERO, true)
		_expect(correction.is_finite() and correction.length() > 0.001, "explicit ready receives correction: " + posture)
		_expect(not stock.is_active(), "explicit ready must not enable legacy stock: " + posture)
	for enabled in [false, true]:
		stock.configure({"enabled": enabled})
		for posture: StringName in [&"PRONE", &"AIRBORNE", &"DIVING", &"UNKNOWN"]:
			_expect(not stock.can_place_authored_ready(posture), "authored request rejects posture: " + posture)
			_expect(stock.correction_for(Vector3.FORWARD, posture, Vector3.INF, Vector3.ZERO, true).is_zero_approx(), "rejected request applies no correction: " + posture)
	stock.configure({"enabled": true})
	_expect(stock.is_active(), "ordinary enabled stock retains its original flag")
	_expect(stock.correction_for(Vector3.FORWARD, &"PRONE").length() > 0.001, "ordinary enabled prone path remains available")
	stock.bind(null, null)
	_expect(not stock.can_place_authored_ready(&"STANDING"), "missing contacts cannot accept authored placement")
	_expect(stock.correction_for(Vector3.FORWARD, &"STANDING", Vector3.INF, Vector3.ZERO, true).is_zero_approx(), "unbound authored request applies no correction")
	fixture.queue_free()
	await process_frame
	print("AUTHORED_STOCK_SCOPE ", "PASS" if failures.is_empty() else "FAIL", " ", failures)
	quit(0 if failures.is_empty() else 1)


func _expect(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)

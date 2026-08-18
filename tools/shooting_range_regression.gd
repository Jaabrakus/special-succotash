extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
    _run.call_deferred()


func _run() -> void:
    var packed := load("res://main.tscn") as PackedScene
    _expect(packed != null, "main scene loads")
    if packed == null:
        _finish()
        return
    var scene := packed.instantiate()
    root.add_child(scene)
    await _steps(30)
    scene.call("_set_shooting_range_active", true)
    await _steps(3)
    var range_root := scene.get_node_or_null("AuthoritativeShootingRange")
    _expect(range_root != null, "current integration build creates the target range")
    _expect(range_root != null and range_root.get_child_count() == 3, "range contains three live targets")
    if range_root != null and range_root.get_child_count() > 0:
        var target = range_root.get_child(0)
        var health_before := float(target.get("health"))
        target.call("apply_bullet_hit", 34.0, target.global_position + Vector3.UP)
        _expect(float(target.get("health")) < health_before, "authoritative hit contract damages a target")
    scene.call("_set_shooting_range_active", false)
    await _steps(3)
    _expect(scene.get_node_or_null("AuthoritativeShootingRange") == null, "F4 range toggle removes only range targets")
    scene.queue_free()
    _finish()


func _steps(count: int) -> void:
    for _index in range(count):
        await physics_frame


func _expect(condition: bool, label: String) -> void:
    if condition:
        print("SHOOTING_RANGE_CHECK PASS ", label)
    else:
        failures.append(label)
        push_error("SHOOTING_RANGE_CHECK FAIL %s" % label)


func _finish() -> void:
    if failures.is_empty():
        print("SHOOTING_RANGE_REGRESSION PASS")
        quit(0)
    else:
        print("SHOOTING_RANGE_REGRESSION FAIL ", failures)
        quit(1)

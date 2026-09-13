extends SceneTree

const Mount := preload("res://scripts/player/operator_source_pistol_mount.gd")
var failures: Array[String] = []

func _initialize() -> void:
	var rotation := Basis.from_euler(Vector3(.3, -.9, .6))
	var palm := Transform3D(rotation, Vector3(2, 3, -4))
	var offset := Vector3(0, .015, .035)
	_expect(Mount.contact_transform(palm, false, offset) == palm, "disabled is exact legacy contact")
	_expect(Mount.contact_transform(palm, true, Vector3.ZERO) == palm, "zero is exact legacy contact")
	var result := Mount.contact_transform(palm, true, offset)
	_expect(result.basis == palm.basis, "no wrist or weapon rotation")
	_expect(result.origin.is_equal_approx(palm.origin + rotation * offset), "palm-local metre offset rotates with palm")
	_expect(is_equal_approx(result.origin.distance_to(palm.origin), offset.length()), "calibration uses physical metres")
	for scale in [.016, 1.0, 62.0]:
		var scaled := Transform3D(rotation.scaled(Vector3.ONE * scale), palm.origin)
		var scaled_result := Mount.contact_transform(scaled, true, offset)
		_expect(scaled_result.origin.is_equal_approx(result.origin), "offset is scale independent: " + str(scale))
		_expect(scaled_result.basis == scaled.basis, "preserves supplied basis: " + str(scale))
	for repeat in 120:
		_expect(Mount.contact_transform(palm, true, offset) == result, "repeated canonical getter does not accumulate")
	_expect(palm == Transform3D(rotation, Vector3(2, 3, -4)), "input transform not mutated")
	_expect(Mount.contact_transform(palm, true, Vector3(INF, 0, 0)) == palm, "reject non-finite offset")
	var bounded := Mount.contact_transform(palm, true, Vector3(10, 0, 0))
	_expect(is_equal_approx(bounded.origin.distance_to(palm.origin), .08), "offset bounded to 80 mm")
	print("SOURCE_PISTOL_MOUNT ", JSON.stringify({"result":"PASS" if failures.is_empty() else "FAIL", "failures":failures}))
	quit(0 if failures.is_empty() else 1)

func _expect(condition: bool, label: String) -> void:
	if not condition:
		failures.append(label)

extends SceneTree
const Wrist := preload("res://scripts/player/operator_support_wrist.gd")
func _initialize() -> void:
	for rotation in [Vector3.ZERO, Vector3(0.3,-0.8,1.2)]:
		var world := Basis.from_euler(rotation)
		for degrees in [0.0, 30.0, 90.0, 150.0, 180.0]:
			var source := world * Basis(Vector3.RIGHT, deg_to_rad(degrees))
			var result := Wrist.constrain_basis(source, Vector3.UP, world * Vector3.UP, deg_to_rad(55))
			assert(rad_to_deg((result * Vector3.UP).angle_to(world * Vector3.UP)) < 55.01)
			assert(is_equal_approx(result.determinant(), 1.0))
			if degrees < 55: assert(result.is_equal_approx(source))
	assert(Wrist.constrain_basis(Basis.IDENTITY, Vector3.ZERO, Vector3.UP, 1.0) == Basis.IDENTITY)
	assert(Wrist.constrain_basis(Basis.IDENTITY, Vector3.UP, Vector3.ZERO, 1.0) == Basis.IDENTITY)
	assert(Wrist.constrain_basis(Basis.IDENTITY, Vector3.UP, Vector3.UP, NAN) == Basis.IDENTITY)
	print("SUPPORT_WRIST_GEOMETRY PASS")
	quit()

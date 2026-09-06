extends RefCounted

# Builds proxy mesh primitives only; the mannequin retains the visual registry.

static func _box_on(parent: Node3D, part_name: String, size: Vector3, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := BoxMesh.new()
    mesh.size = size
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    return part


static func _sphere_on(parent: Node3D, part_name: String, radius: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := SphereMesh.new()
    mesh.radius = radius
    mesh.height = radius * 2.0
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    return part


static func _cylinder_on(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := CylinderMesh.new()
    mesh.top_radius = radius
    mesh.bottom_radius = radius
    mesh.height = height
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    return part


static func _capsule_on(parent: Node3D, part_name: String, radius: float, height: float, position: Vector3, material: StandardMaterial3D) -> MeshInstance3D:
    var part := MeshInstance3D.new()
    part.name = part_name
    var mesh := CapsuleMesh.new()
    mesh.radius = radius
    mesh.height = height
    mesh.material = material
    part.mesh = mesh
    part.position = position
    parent.add_child(part)
    return part


static func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.8
    return material

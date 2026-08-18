class_name SocomShootingDummy
extends StaticBody3D

signal health_changed(target_name: StringName, health: float, maximum_health: float)

@export var maximum_health: float = 100.0
@export var reset_delay_seconds: float = 1.5

var health: float = 100.0
var status_label: Label3D
var visual_root: Node3D
var hit_flash_seconds: float = 0.0
var base_color := Color(0.18, 0.28, 0.34)


func _ready() -> void:
    health = maximum_health
    collision_layer = 1
    collision_mask = 1
    _build_collision()
    _build_low_poly_operator()
    _refresh_status()


func _process(delta: float) -> void:
    if hit_flash_seconds <= 0.0:
        return
    hit_flash_seconds = maxf(0.0, hit_flash_seconds - delta)
    _set_visual_color(Color(1.0, 0.32, 0.16) if hit_flash_seconds > 0.0 else base_color)


func apply_bullet_hit(amount: float, _hit_position: Vector3 = Vector3.ZERO) -> void:
    if health <= 0.0:
        return
    health = maxf(0.0, health - maxf(amount, 0.0))
    hit_flash_seconds = 0.12
    _set_visual_color(Color(1.0, 0.32, 0.16))
    _refresh_status()
    health_changed.emit(StringName(name), health, maximum_health)
    if health <= 0.0:
        status_label.text = "%s  DOWN" % name.to_upper()
        get_tree().create_timer(reset_delay_seconds).timeout.connect(_reset_target)


func _reset_target() -> void:
    health = maximum_health
    _set_visual_color(base_color)
    _refresh_status()
    health_changed.emit(StringName(name), health, maximum_health)


func _build_collision() -> void:
    var collider := CollisionShape3D.new()
    var capsule := CapsuleShape3D.new()
    capsule.radius = 0.38
    capsule.height = 1.85
    collider.shape = capsule
    collider.position.y = 0.925
    add_child(collider)


func _build_low_poly_operator() -> void:
    visual_root = Node3D.new()
    visual_root.name = "LowPolyOperator"
    add_child(visual_root)
    _add_box_part("Torso", Vector3(0.66, 0.76, 0.34), Vector3(0.0, 1.18, 0.0))
    _add_box_part("Pelvis", Vector3(0.50, 0.32, 0.30), Vector3(0.0, 0.72, 0.0))
    _add_box_part("Head", Vector3(0.38, 0.38, 0.36), Vector3(0.0, 1.77, 0.0))
    _add_limb("LeftArm", Vector3(-0.47, 1.18, 0.0), -8.0)
    _add_limb("RightArm", Vector3(0.47, 1.18, 0.0), 8.0)
    _add_limb("LeftLeg", Vector3(-0.17, 0.34, 0.0), 0.0, Vector3(0.20, 0.68, 0.24))
    _add_limb("RightLeg", Vector3(0.17, 0.34, 0.0), 0.0, Vector3(0.20, 0.68, 0.24))

    status_label = Label3D.new()
    status_label.name = "Status"
    status_label.position = Vector3(0.0, 2.18, 0.0)
    status_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
    status_label.font_size = 32
    status_label.outline_size = 7
    status_label.modulate = Color(0.35, 0.95, 1.0)
    add_child(status_label)


func _add_limb(
    part_name: String,
    part_position: Vector3,
    roll_degrees: float,
    part_size := Vector3(0.20, 0.70, 0.22)
) -> void:
    var limb := _add_box_part(part_name, part_size, part_position)
    limb.rotation_degrees.z = roll_degrees


func _add_box_part(part_name: String, part_size: Vector3, part_position: Vector3) -> MeshInstance3D:
    var mesh_node := MeshInstance3D.new()
    mesh_node.name = part_name
    var mesh := BoxMesh.new()
    mesh.size = part_size
    mesh_node.mesh = mesh
    mesh_node.position = part_position
    mesh_node.material_override = _material(base_color)
    visual_root.add_child(mesh_node)
    return mesh_node


func _material(color: Color) -> StandardMaterial3D:
    var material := StandardMaterial3D.new()
    material.albedo_color = color
    material.roughness = 0.86
    return material


func _set_visual_color(color: Color) -> void:
    if visual_root == null:
        return
    for child in visual_root.get_children():
        if child is MeshInstance3D:
            (child as MeshInstance3D).material_override = _material(color)


func _refresh_status() -> void:
    if status_label != null:
        status_label.text = "%s  %d" % [name.to_upper(), roundi(health)]

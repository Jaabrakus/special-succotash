class_name SocomTacticalGrenadeLab
extends Node3D

const Smoke := preload("res://scripts/tactical/smoke_grenade.gd")
const Flash := preload("res://scripts/tactical/flashbang_grenade.gd")
const Frag := preload("res://scripts/tactical/frag_grenade.gd")
const Thrower := preload("res://scripts/tactical/tactical_grenade_thrower.gd")
const ScreenEffects := preload("res://scripts/tactical/tactical_screen_effects.gd")

var camera: Camera3D
var thrower: TacticalGrenadeThrower
var selected_type := 0
var underhand := false
var status: Label


func _ready() -> void:
	_build_arena()
	_build_ui()
	thrower = Thrower.new()
	add_child(thrower)
	var effects := ScreenEffects.new()
	add_child(effects)
	effects.bind_camera(camera)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_1: selected_type = 0
		elif event.keycode == KEY_2: selected_type = 1
		elif event.keycode == KEY_3: selected_type = 2
		elif event.keycode == KEY_U: underhand = not underhand
		elif event.keycode == KEY_SPACE: _throw_grenade()


func _throw_grenade() -> void:
	var grenade: TacticalGrenadeBase
	if selected_type == 1:
		grenade = Flash.new()
	elif selected_type == 2:
		grenade = Frag.new()
	else:
		grenade = Smoke.new()
	add_child(grenade)
	grenade.global_position = camera.global_position + -camera.global_basis.z * 0.5
	var mode := Thrower.ThrowMode.UNDERHAND if underhand else Thrower.ThrowMode.OVERHAND
	grenade.launch(thrower.calculate_launch_velocity(-camera.global_basis.z, Vector3.UP, mode))
	status.text = "%s • %s" % [["SMOKE", "FLASH", "FRAG"][selected_type], "UNDERHAND" if underhand else "OVERHAND"]


func _build_arena() -> void:
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("1b202a")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_energy = 0.8
	environment.environment = settings
	add_child(environment)
	var floor := StaticBody3D.new()
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(24, 0.2, 24)
	collision.shape = shape
	floor.add_child(collision)
	var mesh_instance := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = shape.size
	mesh_instance.mesh = mesh
	floor.add_child(mesh_instance)
	add_child(floor)
	camera = Camera3D.new()
	camera.position = Vector3(0, 2.0, 7.0)
	camera.rotation_degrees.x = -8
	add_child(camera)


func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var label := Label.new()
	label.position = Vector2(22, 20)
	label.text = "TACTICAL GRENADE LAB\n1 Smoke • 2 Flash • 3 Frag • U throw mode • Space throw"
	label.add_theme_font_size_override("font_size", 20)
	layer.add_child(label)
	status = Label.new()
	status.position = Vector2(22, 82)
	status.text = "SMOKE • OVERHAND"
	layer.add_child(status)

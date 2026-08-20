class_name SocomMovingTrainingDummy
extends "res://scripts/combat/lab_leak_target_dummy.gd"

var patrol_distance := 6.0
var patrol_speed := 1.5
var turn_pause := 0.35
var patrol_origin := Vector3.ZERO
var patrol_offset := 0.0
var patrol_direction := 1.0
var pause_remaining := 0.0


func _ready() -> void:
	super._ready()
	patrol_origin = global_position
	if health_label:
		health_label.text = "MOVING TARGET  100 HP"
		health_label.modulate = Color(0.3, 0.95, 1.0)


func configure_patrol(properties: Dictionary) -> void:
	patrol_distance = clampf(float(properties.get("patrol_distance", 6.0)), 0.5, 50.0)
	patrol_speed = clampf(float(properties.get("patrol_speed", 1.5)), 0.1, 12.0)
	turn_pause = clampf(float(properties.get("turn_pause", 0.35)), 0.0, 5.0)
	patrol_origin = global_position
	patrol_offset = 0.0


func _physics_process(delta: float) -> void:
	if not is_alive:
		return
	if pause_remaining > 0.0:
		pause_remaining = maxf(0.0, pause_remaining - delta)
		return
	var half_distance := patrol_distance * 0.5
	patrol_offset += patrol_speed * patrol_direction * delta
	if absf(patrol_offset) >= half_distance:
		patrol_offset = clampf(patrol_offset, -half_distance, half_distance)
		patrol_direction *= -1.0
		pause_remaining = turn_pause
	var patrol_axis := global_basis.x.normalized()
	global_position = patrol_origin + patrol_axis * patrol_offset

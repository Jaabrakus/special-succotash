class_name SocomShotPresentation
extends Node

const Tracers := preload("res://scripts/weapons/lab_leak_tracer_system.gd")
const Audio := preload("res://scripts/audio/lab_leak_audio_engine.gd")
const TRACER_COLOR := Color(1.0, 0.86, 0.30)

## Input is an already-authorized visual event, not the match or a damage owner.
func _ready() -> void:
	Tracers.initialize(self)
	Audio.initialize(self)

func present_shot(origin: Vector3, impact: Vector3, hit: bool, message: String,
		weapon_config: Dictionary, acoustic_exclusions: Array) -> void:
	var values: Dictionary = weapon_config.get("ballistics", {})
	Tracers.spawn_tracer(get_tree(), origin, impact, TRACER_COLOR, float(values.get("muzzle_velocity_mps", 715.0)))
	Audio.play_gunshot(get_tree(), bool(values.get("is_silenced", false)), origin, false,
		acoustic_exclusions, String(weapon_config.get("weapon_id", "")))
	if hit:
		if message != "MISS":
			Tracers.spawn_body_hit_effect(get_tree(), impact, Vector3.UP, message.begins_with("HEAD"))
			Audio.play_body_impact(get_tree(), impact, message.begins_with("HEAD"))
		else:
			Tracers.spawn_impact_effect(get_tree(), impact, Vector3.UP)

func present_pellets(origin: Vector3, impacts: Array[Dictionary], weapon_config: Dictionary) -> void:
	var speed := float(weapon_config.get("ballistics", {}).get("muzzle_velocity_mps", 715.0))
	for index in mini(impacts.size(), 31):
		var impact: Dictionary = impacts[index]
		var position := Vector3(impact.position)
		Tracers.spawn_tracer(get_tree(), origin, position, TRACER_COLOR, speed)
		if bool(impact.hit):
			if String(impact.message) != "MISS":
				Tracers.spawn_body_hit_effect(get_tree(), position, Vector3.UP, String(impact.message).begins_with("HEAD"))
			else:
				Tracers.spawn_impact_effect(get_tree(), position, Vector3.UP)

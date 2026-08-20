class_name AudioAnimationEventManager
extends Node

const Profile := preload("res://scripts/audio/audio_animation_event_profile.gd")
const Foley := preload("res://scripts/audio/tactical_foley_engine.gd")

var animation_player: AnimationPlayer
var skeleton: Skeleton3D
var profile: AudioAnimationEventProfile
var foley: TacticalFoleyEngine
var _last_animation := StringName()
var _last_time := 0.0


func _ready() -> void:
	profile = Profile.new()
	profile.load_from_file()
	foley = Foley.new()
	foley.name = "TacticalFoleyEngine"
	add_child(foley)


func bind(player: AnimationPlayer, target_skeleton: Skeleton3D) -> void:
	animation_player = player
	skeleton = target_skeleton
	_last_animation = &""
	_last_time = 0.0


func _process(_delta: float) -> void:
	if animation_player == null or skeleton == null or animation_player.current_animation.is_empty():
		return
	var active := animation_player.current_animation
	var time := animation_player.current_animation_position
	if active != _last_animation:
		_last_animation = active
		_last_time = 0.0
	_dispatch_range(active, _last_time, time)
	_last_time = time


func preview_event(event: Dictionary) -> void:
	_play_event(event)


func _dispatch_range(animation_name: StringName, from: float, to: float) -> void:
	if to < from:
		_dispatch_range(animation_name, from, INF)
		from = 0.0
	for event in profile.events_for(animation_name):
		var event_time := float(event.get("time", 0.0))
		if event_time > from and event_time <= to:
			_play_event(event)


func _play_event(event: Dictionary) -> void:
	var position := skeleton.global_position
	var bone_name := StringName(event.get("bone", "mixamorig_Hips"))
	var bone_index := skeleton.find_bone(bone_name)
	if bone_index >= 0:
		position = skeleton.to_global(skeleton.get_bone_global_pose(bone_index).origin)
	var minimum := float(event.get("pitch_min", 0.96))
	var maximum := float(event.get("pitch_max", 1.04))
	var surface_event := StringName(event.get("event", ""))
	if not surface_event.is_empty():
		foley.play_surface_event(
			surface_event,
			position,
			float(event.get("intensity", 0.75)),
			null,
			StringName(event.get("surface", ""))
		)
		return
	foley.play_cue(
		StringName(event.get("cue", "foot_concrete")),
		position,
		float(event.get("volume_db", 0.0)),
		randf_range(minimum, maximum)
	)

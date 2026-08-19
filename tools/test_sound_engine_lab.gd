extends SceneTree


func _init() -> void:
	var profile := AudioAnimationEventProfile.new()
	if not profile.load_from_file():
		push_error("Audio animation profile did not load")
		quit(1)
		return
	var errors := profile.validate()
	if not errors.is_empty():
		for error in errors:
			push_error(error)
		quit(1)
		return
	print("SOUND_ENGINE_PROFILE_PASS animations=%d" % profile.animations.size())
	quit(0)

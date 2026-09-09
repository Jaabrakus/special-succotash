extends SceneTree

func _initialize() -> void:
	var source := load("res://assets/animations/seal_reference/seal_dive2prone.tres") as Animation
	var clip: Animation = preload("res://tools/seal_dive_clip.gd").build(source)
	if clip == null:
		quit(1)
		return
	var path := "res://assets/animations/seal_gameplay/seal_dive_to_prone.tres"
	if FileAccess.file_exists(path):
		push_error("Refusing to overwrite existing prepared dive")
		quit(1)
		return
	var result := ResourceSaver.save(clip, path)
	print("SEAL_DIVE_PREPARE ", result, " length=", clip.length)
	quit(0 if result == OK else 1)

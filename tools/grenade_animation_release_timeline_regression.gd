extends SceneTree

const Timeline := preload(
	"res://scripts/tactical/grenade_animation_release_timeline.gd"
)


func _initialize() -> void:
	var failures: Array[String] = []
	for clip_name in [&"grenade_toss", &"crouch_grenade_toss", &"grenade_throw"]:
		var fraction := Timeline.release_fraction(clip_name)
		if fraction <= 0.45 or fraction >= 0.70:
			failures.append("%s release cue is outside the authored throw motion" % clip_name)
		var normal_time := Timeline.release_time_seconds(clip_name, 3.2)
		var fast_time := Timeline.release_time_seconds(clip_name, 3.2 / 1.85)
		if fast_time >= normal_time:
			failures.append("%s release cue does not scale with playback speed" % clip_name)
		var recovery := Timeline.recovery_fraction(clip_name)
		if recovery <= fraction or recovery >= 0.95:
			failures.append("%s recovery cue does not follow release inside the blend-out tail" % clip_name)
	if not Timeline.is_grenade_clip(&"crouch_grenade_toss"):
		failures.append("crouched grenade composite is not recognized")
	if Timeline.is_grenade_clip(&"reload_rifle"):
		failures.append("non-grenade action can emit a grenade release cue")
	if failures.is_empty():
		print("GRENADE_ANIMATION_RELEASE_TIMELINE_REGRESSION PASS")
		quit(0)
		return
	for failure in failures:
		push_error("GRENADE_ANIMATION_RELEASE_TIMELINE_REGRESSION: %s" % failure)
	quit(1)

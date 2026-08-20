extends SceneTree

const ReloadTimeline := preload("res://scripts/weapons/weapon_reload_visual_timeline.gd")


func _init() -> void:
	var profile := {}
	var timeline := ReloadTimeline.ensure_profile_timeline(profile, "reload_standing", 99)
	var events: Dictionary = timeline.get("events", {})
	_expect(events.size() == 5, "standing reload exposes all five lifecycle events")
	_expect(
		ReloadTimeline.state_at_frame(events, int(events[ReloadTimeline.EVENT_MAGAZINE_OUT]))
			== ReloadTimeline.STATE_OLD_MAG_IN_HAND,
		"magazine-out transfers the visual prop to the left hand"
	)
	_expect(
		ReloadTimeline.state_at_frame(events, int(events[ReloadTimeline.EVENT_OLD_MAGAZINE_AWAY]))
			== ReloadTimeline.STATE_HAND_EMPTY,
		"old-mag-away clears the visual prop"
	)
	_expect(
		ReloadTimeline.state_at_frame(events, int(events[ReloadTimeline.EVENT_NEW_MAGAZINE_READY]))
			== ReloadTimeline.STATE_NEW_MAG_IN_HAND,
		"new-mag-ready transfers the replacement prop to the left hand"
	)
	_expect(
		ReloadTimeline.support_hand_should_regrip(
			events,
			int(events[ReloadTimeline.EVENT_SUPPORT_REGRIP])
		),
		"support hand returns to two-hand IK at the authored frame"
	)
	ReloadTimeline.set_event_frame(profile, "reload_standing", ReloadTimeline.EVENT_MAGAZINE_OUT, 25, 99)
	var saved_events: Dictionary = profile["reload_visuals"]["reload_standing"]["events"]
	_expect(int(saved_events[ReloadTimeline.EVENT_MAGAZINE_OUT]) == 25, "edited event persists in the weapon profile")
	print("[RELOAD VISUAL TIMELINE] PASS: visual ownership is data-driven and gameplay-safe.")
	quit(0)


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	push_error("[RELOAD VISUAL TIMELINE] FAIL: " + message)
	quit(1)

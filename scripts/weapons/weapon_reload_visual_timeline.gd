class_name SocomWeaponReloadVisualTimeline
extends RefCounted

## Visual-only reload lifecycle. These frame events move presentation props and
## switch support-hand ownership; ammunition and fire authority never live here.

const EVENT_MAGAZINE_OUT := "magazine_out"
const EVENT_OLD_MAGAZINE_AWAY := "old_magazine_away"
const EVENT_NEW_MAGAZINE_READY := "new_magazine_ready"
const EVENT_MAGAZINE_IN := "magazine_in"
const EVENT_SUPPORT_REGRIP := "support_regrip"

const EVENT_ORDER: Array[String] = [
	EVENT_MAGAZINE_OUT,
	EVENT_OLD_MAGAZINE_AWAY,
	EVENT_NEW_MAGAZINE_READY,
	EVENT_MAGAZINE_IN,
	EVENT_SUPPORT_REGRIP,
]

const EVENT_LABELS := {
	EVENT_MAGAZINE_OUT: "Mag Out",
	EVENT_OLD_MAGAZINE_AWAY: "Old Away",
	EVENT_NEW_MAGAZINE_READY: "New Mag",
	EVENT_MAGAZINE_IN: "Mag In",
	EVENT_SUPPORT_REGRIP: "Regrip",
}

const STATE_IN_WEAPON := "IN WEAPON"
const STATE_OLD_MAG_IN_HAND := "OLD MAG IN LEFT HAND"
const STATE_HAND_EMPTY := "LEFT HAND EMPTY"
const STATE_NEW_MAG_IN_HAND := "NEW MAG IN LEFT HAND"
const STATE_REINSERTED := "MAG INSERTED"
const STATE_TWO_HAND_READY := "TWO-HAND GRIP RESTORED"


static func default_events(frame_count: int) -> Dictionary:
	var last_frame := maxi(frame_count, 1)
	return {
		EVENT_MAGAZINE_OUT: int(round(last_frame * 0.20)),
		EVENT_OLD_MAGAZINE_AWAY: int(round(last_frame * 0.40)),
		EVENT_NEW_MAGAZINE_READY: int(round(last_frame * 0.52)),
		EVENT_MAGAZINE_IN: int(round(last_frame * 0.76)),
		EVENT_SUPPORT_REGRIP: int(round(last_frame * 0.92)),
	}


static func normalized_events(raw_events: Variant, frame_count: int) -> Dictionary:
	var result := default_events(frame_count)
	if raw_events is Dictionary:
		for event_name in EVENT_ORDER:
			if (raw_events as Dictionary).has(event_name):
				result[event_name] = clampi(
					int((raw_events as Dictionary).get(event_name, result[event_name])),
					0,
					maxi(frame_count, 1)
				)
	var previous := 0
	for event_name in EVENT_ORDER:
		result[event_name] = maxi(previous, int(result[event_name]))
		previous = int(result[event_name])
	return result


static func ensure_profile_timeline(
	profile: Dictionary,
	slot_name: String,
	frame_count: int
) -> Dictionary:
	var reload_visuals: Dictionary = (
		(profile.get("reload_visuals", {}) as Dictionary).duplicate(true)
		if profile.get("reload_visuals", {}) is Dictionary
		else {}
	)
	var timeline: Dictionary = (
		(reload_visuals.get(slot_name, {}) as Dictionary).duplicate(true)
		if reload_visuals.get(slot_name, {}) is Dictionary
		else {}
	)
	timeline["events"] = normalized_events(timeline.get("events", {}), frame_count)
	if not timeline.get("magazine_hand_offset", {}) is Dictionary:
		timeline["magazine_hand_offset"] = {}
	var hand_offset := (timeline.get("magazine_hand_offset", {}) as Dictionary).duplicate(true)
	if not hand_offset.get("position", {}) is Dictionary:
		hand_offset["position"] = {}
	if not hand_offset.get("rotation_degrees", {}) is Dictionary:
		hand_offset["rotation_degrees"] = {}
	hand_offset["position"] = _vector_map(
		hand_offset.get("position", {}),
		Vector3(0.0, -0.075, 0.018)
	)
	hand_offset["rotation_degrees"] = _vector_map(
		hand_offset.get("rotation_degrees", {}),
		Vector3(8.0, 0.0, 90.0)
	)
	timeline["magazine_hand_offset"] = hand_offset
	reload_visuals[slot_name] = timeline
	profile["reload_visuals"] = reload_visuals
	return timeline


static func set_event_frame(
	profile: Dictionary,
	slot_name: String,
	event_name: String,
	frame_index: int,
	frame_count: int
) -> Dictionary:
	var timeline := ensure_profile_timeline(profile, slot_name, frame_count)
	var events: Dictionary = (timeline.get("events", {}) as Dictionary).duplicate(true)
	events[event_name] = clampi(frame_index, 0, maxi(frame_count, 1))
	timeline["events"] = normalized_events(events, frame_count)
	var reload_visuals := (profile.get("reload_visuals", {}) as Dictionary).duplicate(true)
	reload_visuals[slot_name] = timeline
	profile["reload_visuals"] = reload_visuals
	return timeline


static func state_at_frame(events: Dictionary, frame_index: int) -> String:
	if frame_index < int(events.get(EVENT_MAGAZINE_OUT, 0)):
		return STATE_IN_WEAPON
	if frame_index < int(events.get(EVENT_OLD_MAGAZINE_AWAY, 0)):
		return STATE_OLD_MAG_IN_HAND
	if frame_index < int(events.get(EVENT_NEW_MAGAZINE_READY, 0)):
		return STATE_HAND_EMPTY
	if frame_index < int(events.get(EVENT_MAGAZINE_IN, 0)):
		return STATE_NEW_MAG_IN_HAND
	if frame_index < int(events.get(EVENT_SUPPORT_REGRIP, 0)):
		return STATE_REINSERTED
	return STATE_TWO_HAND_READY


static func magazine_is_in_left_hand(state: String) -> bool:
	return state == STATE_OLD_MAG_IN_HAND or state == STATE_NEW_MAG_IN_HAND


static func support_hand_should_regrip(events: Dictionary, frame_index: int) -> bool:
	return frame_index >= int(events.get(EVENT_SUPPORT_REGRIP, 0))


static func _vector_map(raw_value: Variant, fallback: Vector3) -> Dictionary:
	var raw: Dictionary = raw_value if raw_value is Dictionary else {}
	return {
		"x": float(raw.get("x", fallback.x)),
		"y": float(raw.get("y", fallback.y)),
		"z": float(raw.get("z", fallback.z)),
	}

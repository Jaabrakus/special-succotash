class_name SocomWeaponFireModePolicy
extends RefCounted

## Stateful trigger gate shared by weapon presentation and authority adapters.
## It decides when a trigger may request a shot; ballistics still owns cadence.

const VALID_MODES: Array[String] = ["semi", "burst", "auto"]

var available_modes: Array[String] = ["auto", "semi"]
var current_mode: String = "auto"
var burst_size: int = 3
var _burst_rounds_remaining: int = 0
## A completed burst must be released before a new press can begin another one.
## This prevents clicks made during a burst from becoming a queued next burst.
var _burst_release_required: bool = false


func configure(
	raw_modes: Array,
	preferred_mode: String = "",
	configured_burst_size: int = 3
) -> void:
	available_modes.clear()
	for raw_mode: Variant in raw_modes:
		var mode := String(raw_mode).to_lower().strip_edges()
		if VALID_MODES.has(mode) and not available_modes.has(mode):
			available_modes.append(mode)
	if available_modes.is_empty():
		available_modes = ["auto", "semi"]
	burst_size = clampi(configured_burst_size, 2, 3)
	var normalized_preference := preferred_mode.to_lower().strip_edges()
	current_mode = (
		normalized_preference
		if available_modes.has(normalized_preference)
		else available_modes[0]
	)
	cancel_pending_burst()


func cycle_mode() -> String:
	if available_modes.is_empty():
		return current_mode
	var current_index := available_modes.find(current_mode)
	current_mode = available_modes[(current_index + 1) % available_modes.size()]
	cancel_pending_burst()
	return current_mode


func select_mode(mode: String) -> bool:
	var normalized := mode.to_lower().strip_edges()
	if not available_modes.has(normalized):
		return false
	current_mode = normalized
	cancel_pending_burst()
	return true


func should_attempt_shot(
	trigger_pressed: bool,
	trigger_held: bool,
	rounds_available: int
) -> bool:
	if rounds_available <= 0:
		cancel_pending_burst()
		return false
	match current_mode:
		"semi":
			return trigger_pressed
		"burst":
			if not trigger_held:
				_burst_release_required = false
				return false
			if _burst_rounds_remaining > 0:
				return true
			if _burst_release_required:
				return false
			if trigger_pressed:
				_burst_rounds_remaining = mini(burst_size, rounds_available)
			return _burst_rounds_remaining > 0
		"auto":
			return trigger_held
		_:
			return false


func notify_shot_result(result: Dictionary) -> void:
	if current_mode != "burst" or _burst_rounds_remaining <= 0:
		return
	if bool(result.get("fired", false)):
		_burst_rounds_remaining -= 1
		if _burst_rounds_remaining == 0:
			_burst_release_required = true
		return
	# A result without a reason is the normal cadence cooldown. Keep the burst
	# queued so the next frame can fire the remaining rounds.
	if not String(result.get("reason", "")).is_empty():
		cancel_pending_burst()


func cancel_pending_burst() -> void:
	_burst_rounds_remaining = 0
	_burst_release_required = false


func has_pending_burst() -> bool:
	return _burst_rounds_remaining > 0

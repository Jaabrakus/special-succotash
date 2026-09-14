extends RefCounted

## Construction-time adapter under the existing AnimationTree, never a clock
## or Skeleton writer. Original files and raw key times remain immutable.
const PATH := "res://config/source_animation_runtime.json"
const SOURCE_DEFAULT_BLEND_SECONDS := 0.40000000596046448
var settings: Dictionary = {}
var blend_curve: Curve

func _init() -> void:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if parsed is Dictionary and parsed.get("schema_version") == 1:
		settings = parsed
	blend_curve = make_curve()

static func loop_period(clip: Animation) -> float:
	if clip == null or not bool(clip.get_meta("seal_reference", false)):
		return -1.0
	# The converter disables looping for static native poses (pistol crouch,
	# prone). Source loop metadata still defines their clock. Genuine one-shots
	# remain excluded, and held/windowed gameplay derivatives are checked below.
	if clip.loop_mode != Animation.LOOP_LINEAR and not bool(clip.get_meta("source_static", false)):
		return -1.0
	for key in ["source_window", "seal_held_source_time", "seal_terminal_closure_removed"]:
		if clip.has_meta(key): return -1.0
	var source: Variant = clip.get_meta("source_settings", {})
	if not source is Dictionary or String(source.get("anim_name", "")) != String(clip.get_meta("source_name", "")):
		return -1.0
	var looped: Variant = source.get("looped")
	if not (looped is float or looped is int) or float(looped) != 1.0:
		return -1.0
	for key in ["max_velocity", "playback"]:
		var value: Variant = source.get(key)
		if not (value is float or value is int) or not is_finite(float(value)): return -1.0
	var playback := float(source.playback)
	if playback <= 0.0: return -1.0
	# FTSCore reader+73: bit0x40 looped, bit0x80 max_velocity<0.
	# Nonloop period decoding is deliberately not applied to gameplay actions.
	var period := playback if float(source.max_velocity) < 0.0 else clip.length / playback
	return period if is_finite(period) and period > 0.0 else -1.0

func configure_node(node: AnimationNodeAnimation, clip: Animation) -> bool:
	if not bool(settings.get("loop_periods_enabled", false)): return false
	var period := loop_period(clip)
	if period <= 0.0: return false
	node.use_custom_timeline = true
	node.stretch_time_scale = true
	node.timeline_length = period
	node.loop_mode = Animation.LOOP_LINEAR
	return true

func grounded_curve() -> Curve:
	return blend_curve if settings.get("grounded_idle_curve", "") == "source_quadratic_in_out" else null

static func standing_entry_seconds(clip: Animation) -> float:
	# ZSeal0x586b24 requests Walk2 on ordinary standing movement entry.
	# Restrict this adapter to the proven default take, not firing/ready overrides.
	if clip == null: return -1.0
	var reference: Variant = clip.get_meta("seal_reference", false)
	if not reference is bool or not reference \
			or String(clip.get_meta("source_name", "")) != "seal_walk_alert" \
			or clip.loop_mode != Animation.LOOP_LINEAR:
		return -1.0
	for key in ["source_window", "seal_held_source_time", "seal_terminal_closure_removed"]:
		if clip.has_meta(key): return -1.0
	var source: Variant = clip.get_meta("source_settings", {})
	if not source is Dictionary or source.get("anim_name", "") != "seal_walk_alert": return -1.0
	var looped: Variant = source.get("looped")
	if not (looped is float or looped is int) or float(looped) != 1.0: return -1.0
	# FTSCore0x287f28–0x287f44 initializes +32 before optional reader lookup.
	# A missing key is not the same as an explicitly malformed override.
	var value: Variant = source.get("BlendTime", SOURCE_DEFAULT_BLEND_SECONDS)
	if not (value is float or value is int): return -1.0
	return float(value) if is_finite(float(value)) and float(value) >= 0.0 and float(value) <= 2.0 else -1.0

static func ease(value: float) -> float:
	var x := clampf(value, 0.0, 1.0)
	return 2.0 * x * x if x <= 0.5 else 1.0 - 2.0 * (x - 1.0) * (x - 1.0)

static func make_curve() -> Curve:
	# These Hermite tangents reproduce both quadratic halves exactly, not a
	# sampled lookalike. AnimationNodeTransition samples the remaining weight.
	var curve := Curve.new()
	curve.add_point(Vector2.ZERO, 0.0, 0.0)
	curve.add_point(Vector2(0.5, 0.5), 2.0, 2.0)
	curve.add_point(Vector2.ONE, 0.0, 0.0)
	return curve

extends SceneTree

## Renders the round-score strip in four representative states and saves a
## PNG preview for design review. Run windowed (not headless) so the viewport
## can rasterize:
##   godot --rendering-method gl_compatibility --path . \
##     --script res://tools/preview_round_score_strip.gd

const StripScript := preload("res://scripts/ui/socom_round_score_strip.gd")

const OUTPUT_PATH := "/tmp/round_score_preview.png"

const STATES := [
	{
		"label": "MID-MATCH  (round 6 of 11, 27s)",
		"alpha": 3, "bravo": 2, "max": 11, "to_win": 6,
		"round": 6, "seconds": 27.0, "phase": "Round 6  •  Live", "kind": &"live",
	},
	{
		"label": "MATCH POINT  (5-4, 8s left)",
		"alpha": 5, "bravo": 4, "max": 11, "to_win": 6,
		"round": 10, "seconds": 8.0, "phase": "Match Point", "kind": &"match_point",
	},
	{
		"label": "OVERTIME FLAG  (5-5)",
		"alpha": 5, "bravo": 5, "max": 11, "to_win": 6,
		"round": 11, "seconds": 0.0, "phase": "Overtime  •  Capture the flag", "kind": &"overtime",
	},
	{
		"label": "BUY WINDOW  (round 1, 12s to buy)",
		"alpha": 0, "bravo": 0, "max": 11, "to_win": 6,
		"round": 1, "seconds": 12.0, "phase": "Buy window 12s  •  Press P", "kind": &"buy",
	},
]


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	var background := ColorRect.new()
	background.color = Color(0.09, 0.11, 0.14)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.add_child(background)

	var font := ThemeDB.fallback_font
	var y := 60.0
	for state: Dictionary in STATES:
		var caption := Label.new()
		caption.text = String(state.label)
		caption.position = Vector2(720.0, y - 34.0)
		caption.add_theme_font_size_override("font_size", 14)
		caption.add_theme_color_override("font_color", Color("8bc5ae"))
		root.add_child(caption)

		var strip := StripScript.new()
		root.add_child(strip)
		strip.offset_top = y
		strip.offset_bottom = y + 76.0
		strip.update_round_score(
			int(state.alpha),
			int(state.bravo),
			int(state.max),
			int(state.to_win),
			int(state.round),
			float(state.seconds),
			String(state.phase),
			state.kind
		)
		strip.position = Vector2(640.0 - 240.0, y)
		y += 160.0

	for _frame in 6:
		await process_frame

	var image := root.get_texture().get_image()
	image.save_png(OUTPUT_PATH)
	print("ROUND_SCORE_PREVIEW SAVED ", OUTPUT_PATH)
	quit(0)

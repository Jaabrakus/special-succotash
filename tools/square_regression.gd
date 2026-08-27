extends SceneTree

## The Square nomenclature regression (docs/SQUARE_DESIGN_LANGUAGE.md):
## word sources, map-schema lore normalization, presentation wiring, and the
## classic-mode fallback. Run headless:
##   godot --headless --path . --script res://tools/square_regression.gd

const Nomenclature := preload("res://scripts/network/socom_team_nomenclature.gd")
const MapDocument := preload("res://scripts/maps/socom_map_document.gd")
const StripScript := preload("res://scripts/ui/socom_round_score_strip.gd")

var failures: int = 0


func _expect(condition: bool, message: String) -> void:
	if condition:
		print("SQUARE_CHECK PASS ", message)
		return
	failures += 1
	push_error("SQUARE_CHECK FAIL " + message)


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	_check_word_sources()
	_check_schema()
	_check_strip()
	_check_presentation_wiring()
	_finish()


func _finish() -> void:
	if failures == 0:
		print("SQUARE_REGRESSION PASS")
		quit(0)
		return
	print("SQUARE_REGRESSION FAIL count=", failures)
	quit(1)


func _check_word_sources() -> void:
	var default_labels := Nomenclature.labels_for_axis("default")
	_expect(
		default_labels[0] == "SATOR" and default_labels[1] == "ROTAS",
		"default axis is SATOR against ROTAS"
	)
	var alternate_labels := Nomenclature.labels_for_axis("alternate")
	_expect(
		alternate_labels[0] == "AREPO" and alternate_labels[1] == "OPERA",
		"alternate axis is AREPO against OPERA"
	)
	var classic_labels := Nomenclature.labels_for_axis("classic")
	_expect(
		classic_labels[0] == "ALPHA" and classic_labels[1] == "BRAVO",
		"classic axis preserves the original labels"
	)
	_expect(
		Nomenclature.labels_for_axis("sideways")[0] == "SATOR",
		"unknown axis falls back to the default axis"
	)
	_expect(
		Nomenclature.labels_for_document({})[0] == "SATOR",
		"a map without lore defaults to the Square's words"
	)
	for house: String in Nomenclature.HOUSES:
		if house == "TENET":
			_expect(
				Nomenclature.labels_for_axis("default").has("TENET") == false
				and Nomenclature.labels_for_axis("alternate").has("TENET") == false,
				"TENET never takes a side on any axis"
			)
	_expect(
		Nomenclature.HOUSES.size() == 5,
		"exactly five Houses exist"
	)


func _check_schema() -> void:
	var normalized := MapDocument.normalize({
		"map_id": "lore_test",
		"lore": {
			"axis": "alternate",
			"house": "arepo",
			"brief": "  A listening post that never logged a transmission.  ",
		},
	})
	var lore: Dictionary = normalized.get("lore", {}) as Dictionary
	_expect(String(lore.get("axis", "")) == "alternate", "schema accepts the alternate axis")
	_expect(String(lore.get("house", "")) == "AREPO", "schema uppercases and accepts valid Houses")
	_expect(
		String(lore.get("brief", "")).ends_with("transmission."),
		"schema trims the brief"
	)
	var hostile := MapDocument.normalize({
		"map_id": "hostile_lore",
		"lore": {"axis": "inverted", "house": "NOLAN", "brief": "x".repeat(400)},
	}).get("lore", {}) as Dictionary
	_expect(String(hostile.get("axis", "")) == "default", "hostile axis falls back to default")
	_expect(String(hostile.get("house", "kept")) == "", "unknown Houses are dropped")
	_expect(String(hostile.get("brief", "")).length() <= 160, "brief is clamped to marginalia length")
	var bare := MapDocument.normalize({"map_id": "bare"}).get("lore", {}) as Dictionary
	_expect(
		String(bare.get("axis", "")) == "default" and String(bare.get("house", "x")) == "",
		"maps without lore normalize to the default axis and no House"
	)


func _check_strip() -> void:
	var strip := StripScript.new()
	root.add_child(strip)
	await process_frame
	_expect(strip.alpha_label == "ALPHA" and strip.bravo_label == "BRAVO", "strip defaults to the classic labels")
	strip.set_team_labels("SATOR", "ROTAS")
	await process_frame
	_expect(strip.alpha_label == "SATOR" and strip.bravo_label == "ROTAS", "strip adopts the axis words")
	strip.free()


func _check_presentation_wiring() -> void:
	var rounds_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_multiplayer_rounds.gd"
	)
	_expect(
		not rounds_source.contains('"ALPHA" if winner_team == 0'),
		"round resolution speaks the axis words, not hardcoded ALPHA/BRAVO"
	)
	var world_ui_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_multiplayer_world_ui.gd"
	)
	_expect(
		not world_ui_source.contains('"ALPHA TARGET"') and not world_ui_source.contains('"BRAVO TARGET"'),
		"objective beacons speak the axis words"
	)
	var hud_source := FileAccess.get_file_as_string(
		"res://scripts/network/socom_multiplayer_hud.gd"
	)
	_expect(
		not hud_source.contains('ROUNDS  ALPHA'),
		"score line speaks the axis words"
	)
	_expect(
		hud_source.contains('"JOIN ALPHA"') and hud_source.contains('"JOIN BRAVO"'),
		"lobby keeps ALPHA/BRAVO by design — the Square opens with the match"
	)
